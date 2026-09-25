"""Ingestao do historico climatico da RMBH.

    python ingestao.py backfill                 # 1940 -> hoje, retomavel
    python ingestao.py backfill --inicio 2020
    python ingestao.py incremental              # coleta diaria (cron)

Backfill e incremental gravam em tabelas diferentes de proposito: o archive e
reanalise estavel, o forecast e numero revisado a cada rodada do modelo.
"""

from __future__ import annotations

import argparse
import sys
import time
from datetime import date, datetime, timedelta

import banco
import nomes
import open_meteo

# O ERA5 sai com alguns dias de atraso; pedir data mais recente que isso so
# devolve linha vazia. Cobrir esses dias e papel do modo incremental.
ATRASO_ARCHIVE_DIAS = 6


class ParadaPorCota(Exception):
    """Backfill interrompido pela cota da API, com progresso preservado."""

    def __init__(self, ano: int) -> None:
        super().__init__(f"cota esgotada ao pedir {ano}")
        self.ano = ano


def _para_datahora(valor: str) -> datetime:
    """Converte o texto ISO da API (com ou sem hora) em datetime."""
    return datetime.fromisoformat(valor)


def montar_linhas(bloco: dict, municipio_id: int, colunas_tabela: set[str],
                  horario: bool, marcar_previsao: bool) -> tuple[list[str], list[tuple]]:
    """Transforma um bloco horario/diario da API em linhas prontas para a staging.

    As colunas do banco estao em portugues e as variaveis da API em ingles, entao
    o casamento passa por nomes.TRADUCAO. Entra no lote a variavel que tiver
    traducao E cuja coluna exista na tabela de destino; qualquer outra e ignorada,
    em vez de derrubar a carga.

    `medidas` guarda os dois nomes: o da API (para ler o valor do payload) e o da
    coluna (para escrever no banco).
    """
    tempos = bloco["time"]
    medidas = [(variavel, nomes.TRADUCAO[variavel])
               for variavel in bloco
               if variavel != "time"
               and variavel in nomes.TRADUCAO
               and nomes.TRADUCAO[variavel] in colunas_tabela]

    colunas = ["municipio_id", "data_id"]
    if horario:
        colunas += ["hora", "data_hora_local"]
    colunas += [coluna for _, coluna in medidas]
    if marcar_previsao:
        colunas.append("eh_previsao")

    agora = datetime.now()
    hoje = agora.date()
    linhas: list[tuple] = []

    for i, texto in enumerate(tempos):
        momento = _para_datahora(texto)
        chave_data = int(momento.strftime("%Y%m%d"))

        linha: list = [municipio_id, chave_data]
        if horario:
            linha += [momento.hour, momento]

        for variavel, _coluna in medidas:
            valor = bloco[variavel][i]
            if valor is not None and variavel in ("sunrise", "sunset"):
                valor = _para_datahora(valor)
            elif valor is not None and variavel == "is_day":
                valor = int(valor)
            linha.append(valor)

        if marcar_previsao:
            # No grao diario o dia corrente ainda e parcialmente previsto,
            # por isso entra como previsao ate virar o dia.
            futuro = momento > agora if horario else momento.date() >= hoje
            linha.append(1 if futuro else 0)

        linhas.append(tuple(linha))

    return colunas, linhas


def gravar(conn, respostas: list[dict], municipios: list[dict],
           tabela_hora: str, tabela_dia: str, staging_hora: str, staging_dia: str,
           marcar_previsao: bool) -> tuple[int, int]:
    """Grava as respostas (uma por municipio, na ordem enviada) nas duas fatos."""
    cols_hora = set(banco.colunas_da_tabela(conn, tabela_hora))
    cols_dia = set(banco.colunas_da_tabela(conn, tabela_dia))

    total_hora = total_dia = 0
    for municipio, resposta in zip(municipios, respostas):
        # O casamento e por POSICAO: a API devolve as coordenadas do ponto de
        # grade, nao as que enviamos.
        colunas, linhas = montar_linhas(resposta["hourly"], municipio["municipio_id"],
                                        cols_hora, horario=True, marcar_previsao=marcar_previsao)
        total_hora += banco.carregar_lote(conn, staging_hora, tabela_hora,
                                          ["municipio_id", "data_id", "hora"], colunas, linhas)

        colunas, linhas = montar_linhas(resposta["daily"], municipio["municipio_id"],
                                        cols_dia, horario=False, marcar_previsao=marcar_previsao)
        total_dia += banco.carregar_lote(conn, staging_dia, tabela_dia,
                                         ["municipio_id", "data_id"], colunas, linhas)

    return total_hora, total_dia


def rodar_backfill(conn, ano_inicio: int, ano_fim: int, pausa: float,
                   refazer: bool) -> tuple[int, int]:
    municipios = banco.municipios_ativos(conn)
    if not municipios:
        raise RuntimeError("nenhum municipio ativo em dim_municipio")

    latitudes = [m["latitude"] for m in municipios]
    longitudes = [m["longitude"] for m in municipios]
    limite = date.today() - timedelta(days=ATRASO_ARCHIVE_DIAS)
    ja_feitos = set() if refazer else banco.anos_ja_carregados(conn)

    total_hora = total_dia = 0
    for ano in range(ano_inicio, ano_fim + 1):
        inicio = date(ano, 1, 1)
        if inicio > limite:
            break
        fim = min(date(ano, 12, 31), limite)

        # Ano corrente: o ERA5 ainda vai publicar o resto dele. Ele nunca conta
        # como "ja carregado" - senao a primeira carga parcial o marcava como
        # concluido e o historico parava de crescer para sempre naquela data.
        ano_incompleto = fim < date(ano, 12, 31)

        pendentes = [m for m in municipios if (m["municipio_id"], ano) not in ja_feitos]
        if not pendentes and not ano_incompleto:
            print(f"{ano}: ja carregado, pulando", flush=True)
            continue

        if ano_incompleto:
            # Pede so a ponta nova, nao o ano inteiro de novo: a cota da API e
            # proporcional ao numero de dias. Os 3 dias de sobreposicao cobrem
            # revisoes da reanalise; o MERGE absorve o que ja existia.
            ultima = banco.ultima_data_historico(conn)
            if ultima is not None and ultima.year == ano:
                inicio = max(inicio, ultima - timedelta(days=3))

        t0 = time.time()
        try:
            respostas = open_meteo.buscar_historico(
                latitudes, longitudes, inicio.isoformat(), fim.isoformat())
        except open_meteo.LimiteApiAtingido as cota:
            # Nao e falha: e o teto do plano gratuito. Para aqui; a proxima
            # execucao retoma neste mesmo ano, pelo etl_backfill_ano.
            print(f"{ano}: {cota} - parando. Retome mais tarde; "
                  f"o progresso ate {ano - 1} esta salvo.", flush=True)
            raise ParadaPorCota(ano) from cota

        linhas_hora, linhas_dia = gravar(
            conn, respostas, municipios,
            "fact_clima_historico_hora", "fact_clima_historico_dia",
            "stg_clima_historico_hora", "stg_clima_historico_dia",
            marcar_previsao=False)

        # 'parcial' nao entra em anos_ja_carregados, entao o ano corrente segue
        # sendo completado a cada rodada ate virar o ano.
        status = "parcial" if ano_incompleto else "sucesso"
        for municipio in municipios:
            banco.marcar_ano(conn, municipio["municipio_id"], ano, status,
                             linhas_hora // len(municipios), linhas_dia // len(municipios))

        total_hora += linhas_hora
        total_dia += linhas_dia
        print(f"{ano}: {linhas_hora:>7} linhas/hora  {linhas_dia:>5} linhas/dia  "
              f"({time.time() - t0:.1f}s)", flush=True)

        time.sleep(pausa)   # respeitar o limite de requisicoes da API

    return total_hora, total_dia


def rodar_incremental(conn, dias_passados: int, dias_previsao: int) -> tuple[int, int]:
    municipios = banco.municipios_ativos(conn)
    respostas = open_meteo.buscar_atual(
        [m["latitude"] for m in municipios], [m["longitude"] for m in municipios],
        dias_passados=dias_passados, dias_previsao=dias_previsao)

    return gravar(conn, respostas, municipios,
                  "fact_clima_atual_hora", "fact_clima_atual_dia",
                  "stg_clima_atual_hora", "stg_clima_atual_dia",
                  marcar_previsao=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Ingestao Open-Meteo -> SQL Server")
    sub = parser.add_subparsers(dest="modo", required=True)

    p_back = sub.add_parser("backfill", help="carga historica (/v1/archive), ano a ano")
    p_back.add_argument("--inicio", type=int, default=1940, help="ano inicial (padrao: 1940)")
    p_back.add_argument("--fim", type=int, default=date.today().year, help="ano final")
    p_back.add_argument("--pausa", type=float, default=2.0, help="segundos entre chamadas")
    p_back.add_argument("--refazer", action="store_true", help="ignora o controle e recarrega tudo")

    p_inc = sub.add_parser("incremental", help="coleta diaria (/v1/forecast)")
    p_inc.add_argument("--dias-passados", type=int, default=7)
    p_inc.add_argument("--dias-previsao", type=int, default=16)

    args = parser.parse_args()
    conn = banco.conectar()
    execucao_id = banco.abrir_execucao(conn, args.modo, " ".join(sys.argv[1:]))

    try:
        if args.modo == "backfill":
            hora, dia = rodar_backfill(conn, args.inicio, args.fim, args.pausa, args.refazer)
        else:
            hora, dia = rodar_incremental(conn, args.dias_passados, args.dias_previsao)
    except ParadaPorCota as pausa_cota:
        # Saida 0: para o cron, parar na cota e comportamento esperado, nao falha.
        banco.fechar_execucao(conn, execucao_id, "parcial", mensagem=str(pausa_cota))
        print(f"\nPAUSADO - {pausa_cota}. Rode de novo mais tarde para continuar.")
        return 0
    except Exception as erro:   # qualquer falha precisa virar registro em etl_execucao
        banco.fechar_execucao(conn, execucao_id, "erro",
                              mensagem=f"{type(erro).__name__}: {erro}")
        print(f"ERRO: {erro}", file=sys.stderr)
        return 1

    banco.fechar_execucao(conn, execucao_id, "sucesso", hora, dia)
    print(f"\nOK - {hora} linhas horarias e {dia} linhas diarias gravadas.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
