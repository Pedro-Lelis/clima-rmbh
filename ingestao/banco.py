"""Acesso ao SQL Server: staging em lote + MERGE idempotente.

Estratégia de carga (a mesma para as quatro fatos):
    1. limpa a staging correspondente;
    2. insere o lote inteiro com `fast_executemany` (uma viagem, não uma por linha);
    3. faz um único MERGE em conjunto contra a tabela final.

O MERGE é montado a partir do catálogo do próprio banco (`sys.columns`): as
colunas do payload já têm o nome das colunas da tabela, então não existe lista
de de-para para manter em sincronia. Se amanhã uma variável for acrescentada ao
schema e ao pedido da API, ela entra sozinha.
"""

from __future__ import annotations

import os

import pyodbc


def conectar(autocommit: bool = False) -> pyodbc.Connection:
    """Conexão com o banco. A senha vem SEMPRE de variável de ambiente."""
    senha = os.environ.get("SA_PASSWORD")
    if not senha:
        raise RuntimeError("defina a variável de ambiente SA_PASSWORD")

    conn = pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={os.environ.get('SQL_SERVER', 'localhost')},{os.environ.get('SQL_PORT', '1433')};"
        f"DATABASE={os.environ.get('SQL_DATABASE', 'ClimaRMBH')};"
        f"UID={os.environ.get('SQL_USER', 'sa')};PWD={senha};"
        "TrustServerCertificate=yes;",       # certificado autoassinado da VPS
        autocommit=autocommit,
    )
    return conn


def colunas_da_tabela(conn: pyodbc.Connection, tabela: str) -> list[str]:
    cur = conn.cursor()
    cur.execute(
        "SELECT c.name FROM sys.columns c "
        "WHERE c.object_id = OBJECT_ID(?) ORDER BY c.column_id", f"dbo.{tabela}")
    return [linha[0] for linha in cur.fetchall()]


def municipios_ativos(conn: pyodbc.Connection) -> list[dict]:
    cur = conn.cursor()
    cur.execute(
        "SELECT municipio_id, nome, latitude, longitude "
        "FROM dbo.dim_municipio WHERE ativo = 1 ORDER BY municipio_id")
    return [{"municipio_id": m, "nome": n, "latitude": float(la), "longitude": float(lo)}
            for m, n, la, lo in cur.fetchall()]


# Tipos declarados de cada coluna, para `setinputsizes`.
# Sem isso, `fast_executemany` deduz o tipo do parâmetro pela PRIMEIRA linha do
# lote - e se essa linha tiver NULL numa medida (acontece o tempo todo em série
# climática), o driver assume texto e a carga quebra com "Invalid character
# value for cast specification". Declarar o tipo elimina a adivinhação.
_CACHE_TIPOS: dict[str, dict[str, tuple]] = {}


def _tipos_das_colunas(conn: pyodbc.Connection, tabela: str) -> dict[str, tuple]:
    if tabela in _CACHE_TIPOS:
        return _CACHE_TIPOS[tabela]

    cur = conn.cursor()
    cur.execute("""
        SELECT c.name, t.name, c.precision, c.scale
          FROM sys.columns c
          JOIN sys.types t ON t.user_type_id = c.user_type_id
         WHERE c.object_id = OBJECT_ID(?)
    """, f"dbo.{tabela}")

    mapa: dict[str, tuple] = {}
    for nome, tipo, precisao, escala in cur.fetchall():
        if tipo in ("decimal", "numeric"):
            # SQL_DOUBLE, não SQL_DECIMAL: os valores chegam da API como float e
            # o próprio servidor converte double -> decimal(p,s) no INSERT, com
            # arredondamento decimal correto. Declarar DECIMAL aqui obrigaria a
            # converter 180 milhões de números para Decimal em Python no backfill.
            mapa[nome] = (pyodbc.SQL_DOUBLE, 0, 0)
        elif tipo in ("int", "smallint", "tinyint", "bigint"):
            mapa[nome] = (pyodbc.SQL_INTEGER, 0, 0)
        elif tipo == "bit":
            mapa[nome] = (pyodbc.SQL_BIT, 0, 0)
        elif tipo.startswith("datetime2"):
            mapa[nome] = (pyodbc.SQL_TYPE_TIMESTAMP, 27, 7)
    _CACHE_TIPOS[tabela] = mapa
    return mapa


def carregar_lote(conn: pyodbc.Connection, staging: str, destino: str,
                  chaves: list[str], colunas: list[str],
                  linhas: list[tuple]) -> int:
    """Grava o lote na staging e faz o MERGE. Devolve o nº de linhas afetadas."""
    if not linhas:
        return 0

    cur = conn.cursor()
    cur.fast_executemany = True
    cur.execute(f"TRUNCATE TABLE dbo.[{staging}]")

    lista = ", ".join(f"[{c}]" for c in colunas)
    marcadores = ", ".join("?" for _ in colunas)
    tipos = _tipos_das_colunas(conn, staging)
    cur.setinputsizes([tipos.get(c) for c in colunas])
    cur.executemany(f"INSERT INTO dbo.[{staging}] ({lista}) VALUES ({marcadores})", linhas)

    medidas = [c for c in colunas if c not in chaves]
    juncao = " AND ".join(f"d.[{k}] = s.[{k}]" for k in chaves)
    atualizacao = ", ".join(f"d.[{c}] = s.[{c}]" for c in medidas)
    particao = ", ".join(f"[{k}]" for k in chaves)

    # HOLDLOCK: o MERGE precisa da leitura serializável do destino para não
    # deixar brecha entre o "não achei" e o INSERT.
    # ROW_NUMBER: se o mesmo par chave vier repetido no lote, o MERGE falharia;
    # ficamos com a primeira ocorrência.
    cur.execute(f"""
        MERGE dbo.[{destino}] WITH (HOLDLOCK) AS d
        USING (
            SELECT {lista}
              FROM (SELECT {lista},
                           ROW_NUMBER() OVER (PARTITION BY {particao} ORDER BY (SELECT NULL)) AS rn
                      FROM dbo.[{staging}]) AS dedup
             WHERE rn = 1
        ) AS s
           ON {juncao}
        WHEN MATCHED THEN
            UPDATE SET {atualizacao}, d.[dt_carga] = SYSDATETIME()
        WHEN NOT MATCHED THEN
            INSERT ({lista}, [dt_carga])
            VALUES ({", ".join(f"s.[{c}]" for c in colunas)}, SYSDATETIME());
    """)
    afetadas = cur.rowcount
    conn.commit()
    return afetadas


# --------------------------------------------------------------------------- #
# controle de execução
# --------------------------------------------------------------------------- #

def abrir_execucao(conn: pyodbc.Connection, modo: str, parametros: str) -> int:
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO dbo.etl_execucao (modo, parametros, status) OUTPUT INSERTED.execucao_id "
        "VALUES (?, ?, 'rodando')", modo, parametros)
    execucao_id = cur.fetchone()[0]
    conn.commit()
    return execucao_id


def fechar_execucao(conn: pyodbc.Connection, execucao_id: int, status: str,
                    linhas_hora: int = 0, linhas_dia: int = 0, mensagem: str | None = None) -> None:
    cur = conn.cursor()
    cur.execute(
        "UPDATE dbo.etl_execucao SET dt_fim = SYSDATETIME(), status = ?, "
        "linhas_hora = ?, linhas_dia = ?, mensagem = ? WHERE execucao_id = ?",
        status, linhas_hora, linhas_dia, (mensagem or "")[:2000], execucao_id)
    conn.commit()


def ultima_data_historico(conn: pyodbc.Connection):
    """Dia mais recente ja gravado no historico diario (None se vazio)."""
    cur = conn.cursor()
    cur.execute(
        "SELECT MAX(d.data) FROM dbo.fact_clima_historico_dia f "
        "JOIN dbo.dim_data d ON d.data_id = f.data_id")
    return cur.fetchone()[0]


def anos_ja_carregados(conn: pyodbc.Connection) -> set[tuple[int, int]]:
    cur = conn.cursor()
    cur.execute("SELECT municipio_id, ano FROM dbo.etl_backfill_ano WHERE status = 'sucesso'")
    return {(m, a) for m, a in cur.fetchall()}


def marcar_ano(conn: pyodbc.Connection, municipio_id: int, ano: int, status: str,
               linhas_hora: int, linhas_dia: int) -> None:
    cur = conn.cursor()
    cur.execute("""
        MERGE dbo.etl_backfill_ano AS d
        USING (SELECT ? AS municipio_id, ? AS ano) AS s
           ON d.municipio_id = s.municipio_id AND d.ano = s.ano
        WHEN MATCHED THEN UPDATE SET status = ?, linhas_hora = ?, linhas_dia = ?,
                                     dt_conclusao = SYSDATETIME()
        WHEN NOT MATCHED THEN INSERT (municipio_id, ano, status, linhas_hora, linhas_dia)
                              VALUES (s.municipio_id, s.ano, ?, ?, ?);
    """, municipio_id, ano, status, linhas_hora, linhas_dia, status, linhas_hora, linhas_dia)
    conn.commit()
