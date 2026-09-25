/* =============================================================================
   08_etl_controle.sql  -  Tabelas de apoio da ingestao
   1) Controle de carga: o backfill vai de 1940 ate hoje. Nenhuma carga desse
      tamanho roda de uma vez sem tropecar (limite de requisicoes da API, queda
      de rede, reinicio da VPS). O controle por municipio x ano permite parar e
      retomar exatamente de onde parou.
   2) Areas de staging: a ingestao grava em lote na staging e depois faz um
      MERGE em conjunto contra a tabela final. E mais rapido que MERGE linha a
      linha e mantem a carga idempotente.
      Criadas com SELECT TOP 0 * INTO: mesma estrutura das fatos, sem chaves,
      indices ou defaults - e sem repetir a lista de colunas.
   ============================================================================= */

USE ClimaRMBH;
GO

/* ---------- 1) log de execucoes ---------- */
IF OBJECT_ID(N'dbo.etl_execucao', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.etl_execucao
    (
        execucao_id  BIGINT        IDENTITY(1,1) NOT NULL,
        modo         NVARCHAR(20)  NOT NULL,      -- 'backfill' | 'incremental'
        parametros   NVARCHAR(200) NULL,          -- periodo pedido, para rastreio
        dt_inicio    DATETIME2(3)  NOT NULL CONSTRAINT DF_etlex_inicio DEFAULT (SYSDATETIME()),
        dt_fim       DATETIME2(3)  NULL,
        status       NVARCHAR(20)  NOT NULL,      -- 'rodando' | 'sucesso' | 'erro'
        linhas_hora  INT           NULL,
        linhas_dia   INT           NULL,
        mensagem     NVARCHAR(2000) NULL,

        CONSTRAINT PK_etl_execucao PRIMARY KEY CLUSTERED (execucao_id)
    );
END
GO

/* ---------- 2) progresso do backfill ---------- */
IF OBJECT_ID(N'dbo.etl_backfill_ano', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.etl_backfill_ano
    (
        municipio_id  INT          NOT NULL,
        ano           SMALLINT     NOT NULL,
        status        NVARCHAR(20) NOT NULL,      -- 'sucesso' | 'erro'
        linhas_hora   INT          NULL,
        linhas_dia    INT          NULL,
        dt_conclusao  DATETIME2(3) NOT NULL CONSTRAINT DF_etlba_dt DEFAULT (SYSDATETIME()),

        CONSTRAINT PK_etl_backfill_ano PRIMARY KEY CLUSTERED (municipio_id, ano),
        CONSTRAINT FK_etlba_municipio  FOREIGN KEY (municipio_id) REFERENCES dbo.dim_municipio (municipio_id)
    );
END
GO

/* ---------- 3) staging ---------- */
IF OBJECT_ID(N'dbo.stg_clima_historico_hora', N'U') IS NULL
    SELECT TOP 0 * INTO dbo.stg_clima_historico_hora FROM dbo.fact_clima_historico_hora;
GO
IF OBJECT_ID(N'dbo.stg_clima_historico_dia', N'U') IS NULL
    SELECT TOP 0 * INTO dbo.stg_clima_historico_dia FROM dbo.fact_clima_historico_dia;
GO
IF OBJECT_ID(N'dbo.stg_clima_atual_hora', N'U') IS NULL
    SELECT TOP 0 * INTO dbo.stg_clima_atual_hora FROM dbo.fact_clima_atual_hora;
GO
IF OBJECT_ID(N'dbo.stg_clima_atual_dia', N'U') IS NULL
    SELECT TOP 0 * INTO dbo.stg_clima_atual_dia FROM dbo.fact_clima_atual_dia;
GO

PRINT 'Tabelas de controle e staging prontas.';
GO

/* -----------------------------------------------------------------------------
   Ajuste das stagings: remover dt_carga.

   SELECT ... INTO copia nome, tipo e nulabilidade das colunas, mas NAO copia
   constraints - inclusive o DEFAULT. As stagings nasciam, portanto, com
   dt_carga NOT NULL e sem default, e qualquer INSERT falhava com
   "Cannot insert the value NULL into column 'dt_carga'".

   A coluna nao faz falta ali: a staging e area de passagem, e quem carimba a
   data de carga e o MERGE, com SYSDATETIME(), na tabela final. Removendo,
   o problema deixa de existir em vez de ser contornado.

   Bloco idempotente: pode rodar de novo sem erro.
   ----------------------------------------------------------------------------- */
IF COL_LENGTH(N'dbo.stg_clima_historico_hora', N'dt_carga') IS NOT NULL
    ALTER TABLE dbo.stg_clima_historico_hora DROP COLUMN dt_carga;
GO
IF COL_LENGTH(N'dbo.stg_clima_historico_dia', N'dt_carga') IS NOT NULL
    ALTER TABLE dbo.stg_clima_historico_dia DROP COLUMN dt_carga;
GO
IF COL_LENGTH(N'dbo.stg_clima_atual_hora', N'dt_carga') IS NOT NULL
    ALTER TABLE dbo.stg_clima_atual_hora DROP COLUMN dt_carga;
GO
IF COL_LENGTH(N'dbo.stg_clima_atual_dia', N'dt_carga') IS NOT NULL
    ALTER TABLE dbo.stg_clima_atual_dia DROP COLUMN dt_carga;
GO

PRINT 'Stagings ajustadas (sem dt_carga).';
GO
