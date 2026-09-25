"""Confere, sem tocar no banco, se DDL, API e transformacao continuam casando.

Roda offline contra as amostras de payload em docs/amostras-api/. Serve como
teste de regressao: se alguem acrescentar uma variavel no pedido da API e
esquecer da coluna (ou o contrario), este script aponta.

    python ingestao/verificar_mapeamento.py
"""

from __future__ import annotations

import json
import re
import sys
import types
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "ingestao"))

# O teste exercita so a transformacao; o driver do banco nao precisa existir.
_falso = types.ModuleType("pyodbc")
for _nome in ("SQL_DECIMAL", "SQL_DOUBLE", "SQL_INTEGER", "SQL_BIT", "SQL_TYPE_TIMESTAMP"):
    setattr(_falso, _nome, _nome)
_falso.Connection = object
sys.modules.setdefault("pyodbc", _falso)

import ingestao          # noqa: E402
import nomes             # noqa: E402
import open_meteo        # noqa: E402

COLUNAS_TECNICAS = nomes.COLUNAS_TECNICAS

CASOS = [
    ("sql/04_fact_clima_historico_hora.sql", open_meteo.HORA_ARCHIVE, "hourly",
     "docs/amostras-api/open-meteo_archive_exemplo.json"),
    ("sql/05_fact_clima_historico_dia.sql", open_meteo.DIA_ARCHIVE, "daily",
     "docs/amostras-api/open-meteo_archive_exemplo.json"),
    ("sql/06_fact_clima_atual_hora.sql", open_meteo.HORA_FORECAST, "hourly",
     "docs/amostras-api/open-meteo_forecast_exemplo.json"),
    ("sql/07_fact_clima_atual_dia.sql", open_meteo.DIA_FORECAST, "daily",
     "docs/amostras-api/open-meteo_forecast_exemplo.json"),
]


def colunas_do_ddl(caminho: Path) -> set[str]:
    texto = caminho.read_text(encoding="utf-8")
    corpo = texto.split("CREATE TABLE", 1)[1]
    padrao = re.compile(
        r"\s{8}(\w+)\s+(INT|SMALLINT|TINYINT|BIT|DECIMAL|DATETIME2|NVARCHAR|CHAR)")
    return {m.group(1) for linha in corpo.splitlines() if (m := padrao.match(linha))}


def main() -> int:
    problemas: list[str] = []

    for ddl, pedidas, bloco_nome, amostra in CASOS:
        colunas = colunas_do_ddl(RAIZ / ddl)

        # 1) toda variavel pedida precisa estar cadastrada no de-para...
        sem_traducao = [v for v in pedidas if v not in nomes.TRADUCAO]
        # 2) ...e a coluna correspondente precisa existir na tabela
        faltando = [v for v in pedidas
                    if v in nomes.TRADUCAO and nomes.TRADUCAO[v] not in colunas]
        # 3) e nenhuma coluna pode ficar orfa, sem variavel que a alimente
        esperadas = {nomes.TRADUCAO[v] for v in pedidas if v in nomes.TRADUCAO}
        sobrando = [c for c in colunas
                    if c not in esperadas and c not in COLUNAS_TECNICAS]

        dados = json.loads((RAIZ / amostra).read_text(encoding="utf-8"))
        bloco = (dados if isinstance(dados, dict) else dados[0])[bloco_nome]
        cabecalho, linhas = ingestao.montar_linhas(
            bloco, municipio_id=1, colunas_tabela=colunas,
            horario=(bloco_nome == "hourly"),
            marcar_previsao=("eh_previsao" in colunas))
        largura_ok = all(len(l) == len(cabecalho) for l in linhas)

        print(f"{ddl}")
        print(f"  DDL {len(colunas):>3} colunas | API {len(pedidas):>3} variaveis | "
              f"lote {len(linhas)} x {len(cabecalho)}")
        if sem_traducao:
            problemas.append(
                f"{ddl}: variavel pedida sem entrada em nomes.TRADUCAO -> {sem_traducao}")
        if faltando:
            problemas.append(f"{ddl}: variavel pedida sem coluna -> {faltando}")
        if sobrando:
            problemas.append(f"{ddl}: coluna sem variavel correspondente -> {sobrando}")
        if not largura_ok:
            problemas.append(f"{ddl}: linhas com largura diferente do cabecalho")

    if problemas:
        print("\nPROBLEMAS:")
        for p in problemas:
            print(" -", p)
        return 1

    print("\nOK - DDL, API e transformacao casando.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
