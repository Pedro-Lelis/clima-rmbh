/* Gera docs/dicionario_dados.md a partir das MS_Description gravadas no banco
   (sql/99_dicionario_dados.sql). O .md nao se edita a mao: muda o texto no 99,
   roda o 99 no banco e gera de novo.

   Como gerar: rode no SSMS (banco ClimaRMBH), clique no cabecalho da coluna
   "linha" no grid, copie (Ctrl+C) e cole no docs/dicionario_dados.md.

   Saida: uma linha de Markdown por registro, ja na ordem do documento -
   cabecalho, e para cada tabela (dimensoes, fatos, controle): titulo,
   descricao e uma tabela com as colunas na ordem de column_id.
   Stagings ficam de fora: espelham as fatos e so tem descricao de tabela. */
SET NOCOUNT ON;

WITH colunas AS (
    SELECT
        CASE WHEN stb.name LIKE 'dim[_]%'  THEN 1
             WHEN stb.name LIKE 'fact[_]%' THEN 2
             ELSE 3 END                                             AS grupo,
        stb.name                                                    AS tabela,
        CAST(sep_tab.value AS NVARCHAR(2000))                       AS descricao_tabela,
        scm.column_id,
        scm.name                                                    AS coluna,
        CASE WHEN stp.name IN ('decimal', 'numeric')
                 THEN CONCAT(stp.name, '(', scm.precision, ',', scm.scale, ')')
             -- max_length esta em bytes; nvarchar/nchar gastam 2 por caractere
             WHEN stp.name IN ('nvarchar', 'nchar')
                 THEN CONCAT(stp.name, '(', IIF(scm.max_length = -1, 'max', CAST(scm.max_length / 2 AS VARCHAR(10))), ')')
             WHEN stp.name IN ('varchar', 'char')
                 THEN CONCAT(stp.name, '(', IIF(scm.max_length = -1, 'max', CAST(scm.max_length AS VARCHAR(10))), ')')
             WHEN stp.name IN ('datetime2', 'time', 'datetimeoffset')
                 THEN CONCAT(stp.name, '(', scm.scale, ')')
             ELSE stp.name END                                      AS tipo,
        IIF(scm.is_nullable = 1, 'sim', 'não')                      AS aceita_nulo,
        IIF(EXISTS (SELECT 1
                    FROM sys.indexes six
                    JOIN sys.index_columns sic
                      ON sic.object_id = six.object_id AND sic.index_id = six.index_id
                    WHERE six.object_id = stb.object_id
                      AND six.is_primary_key = 1
                      AND sic.column_id = scm.column_id), 'PK', '')  AS chave,
        -- "|" quebraria a tabela Markdown
        REPLACE(COALESCE(CAST(sep_col.value AS NVARCHAR(2000)), N'(sem descrição)'), N'|', N'\|')
                                                                    AS descricao_coluna
    FROM sys.tables stb
    INNER JOIN sys.columns scm ON scm.object_id = stb.object_id
    INNER JOIN sys.types   stp ON stp.user_type_id = scm.user_type_id
    LEFT JOIN sys.extended_properties sep_col
           ON sep_col.class    = 1
          AND sep_col.major_id = stb.object_id
          AND sep_col.minor_id = scm.column_id
          AND sep_col.name     = 'MS_Description'
    LEFT JOIN sys.extended_properties sep_tab
           ON sep_tab.class    = 1
          AND sep_tab.major_id = stb.object_id
          AND sep_tab.minor_id = 0
          AND sep_tab.name     = 'MS_Description'
    WHERE stb.schema_id = SCHEMA_ID('dbo')
      AND (stb.name LIKE 'dim[_]%' OR stb.name LIKE 'fact[_]%' OR stb.name LIKE 'etl[_]%')
),
tabelas AS (
    SELECT DISTINCT grupo, tabela, descricao_tabela FROM colunas
),
linhas AS (
    -- cabecalho do documento (grupo 0)
    SELECT 0 AS grupo, N'' AS tabela, v.ordem, v.linha
    FROM (VALUES
        (1, N'# Dicionário de dados — ClimaRMBH'),
        (2, N''),
        (3, N'Gerado das descrições gravadas no próprio banco (`sql/99_dicionario_dados.sql`) por `docs/gerar_dicionario_dados.sql`. Não editar à mão.'),
        (4, N''),
        (5, N'Valores **instantâneos** na hora H: temperatura, umidade, pressão, nuvens, vento, solo, visibilidade. Valores da **hora anterior** (H−1 a H): chuva, radiação, insolação, evapotranspiração, rajada.'),
        (6, N'')
    ) AS v (ordem, linha)

    UNION ALL

    -- abertura de cada tabela (ordens negativas: antes das colunas)
    SELECT t.grupo, t.tabela, v.ordem, v.linha
    FROM tabelas t
    CROSS APPLY (VALUES
        (-6, CONCAT(N'## ', t.tabela)),
        (-5, N''),
        (-4, COALESCE(t.descricao_tabela, N'(sem descrição)')),
        (-3, N''),
        (-2, N'| Coluna | Tipo | Nulo | Chave | Descrição |'),
        (-1, N'|---|---|---|---|---|')
    ) AS v (ordem, linha)

    UNION ALL

    -- uma linha por coluna
    SELECT c.grupo, c.tabela, c.column_id,
           CONCAT(N'| `', c.coluna, N'` | ', c.tipo, N' | ', c.aceita_nulo, N' | ', c.chave, N' | ',
                  c.descricao_coluna, N' |')
    FROM colunas c

    UNION ALL

    -- linha em branco depois de cada tabela
    SELECT t.grupo, t.tabela, 10000, N''
    FROM tabelas t
)
SELECT linha
FROM linhas
ORDER BY grupo, tabela, ordem;
