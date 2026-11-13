/* =============================================================================
   10_fact_previsao_snapshot_dia.sql
   Fonte..: copia da fact_clima_atual_dia (eh_previsao = 1), uma vez por dia
   Grao...: 1 linha por DATA DA COLETA x MUNICIPIO x DATA PREVISTA

   Por que existe: a fact_clima_atual_dia e reescrita a cada hora, e a previsao
   de um dia e sobrescrita quando o dia passa. Sem uma foto, "quanto a previsao
   erra conforme a antecedencia" nao tem como ser respondido. O historico de
   previsoes so existe a partir do dia em que esta tabela comecou a ser gravada.

   - data_coleta vem do dt_carga dos dados copiados, nao da data em que a
     tarefa rodou: se a carga da meia-noite falhar, a foto nao grava dados de
     ontem com a data de hoje.
   - antecedencia_dias = data prevista - data da coleta (0 = o proprio dia da
     coleta, que ainda e parcialmente previsto; 15 = ultimo dia do horizonte).
   - So as medidas que o painel compara; a fact_clima_atual_dia segue completa.
   - Gravada pela tarefa gravar_snapshot_previsao da DAG clima_incremental,
     depois das checagens de qualidade: so foto de carga validada entra aqui.
   ============================================================================= */

USE ClimaRMBH;
GO

IF OBJECT_ID(N'dbo.fact_previsao_snapshot_dia', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.fact_previsao_snapshot_dia
    (
        data_coleta                    DATE          NOT NULL,
        municipio_id                   INT           NOT NULL,
        data_id                        INT           NOT NULL,   -- dia previsto (AAAAMMDD)
        antecedencia_dias              TINYINT       NOT NULL,   -- 0..15

        codigo_tempo                   SMALLINT      NULL,       -- codigo WMO mais severo
        temperatura_2m_max             DECIMAL(5,2)  NULL,       -- °C
        temperatura_2m_min             DECIMAL(5,2)  NULL,       -- °C
        precipitacao_total             DECIMAL(7,2)  NULL,       -- mm
        horas_precipitacao             DECIMAL(4,1)  NULL,       -- horas
        probabilidade_precipitacao_max TINYINT       NULL,       -- %
        velocidade_vento_10m_max       DECIMAL(6,2)  NULL,       -- km/h

        dt_carga_origem                DATETIME2(3)  NOT NULL,   -- dt_carga da linha copiada
        dt_snapshot                    DATETIME2(3)  NOT NULL
            CONSTRAINT DF_fpsd_dt_snapshot DEFAULT (SYSDATETIME()),

        CONSTRAINT PK_fact_previsao_snapshot_dia
            PRIMARY KEY CLUSTERED (data_coleta, municipio_id, data_id),
        CONSTRAINT FK_fpsd_municipio FOREIGN KEY (municipio_id) REFERENCES dbo.dim_municipio (municipio_id),
        CONSTRAINT FK_fpsd_data      FOREIGN KEY (data_id)      REFERENCES dbo.dim_data (data_id),
        CONSTRAINT CK_fpsd_antecedencia CHECK (antecedencia_dias BETWEEN 0 AND 15)
    );

    -- o painel cruza previsao x realizado pelo dia previsto
    CREATE NONCLUSTERED INDEX IX_fpsd_data
        ON dbo.fact_previsao_snapshot_dia (data_id, municipio_id, antecedencia_dias);
END
GO

/* -----------------------------------------------------------------------------
   Permissao para a tarefa do Airflow: um login so para gravar a foto.
   O LOGIN e criado a mao, com a senha do Bitwarden (nunca neste arquivo):
     CREATE LOGIN svc_airflow_snapshot WITH PASSWORD = '<SENHA>', CHECK_POLICY = ON;
   Este bloco so cria o usuario e as permissoes se o login ja existir.
   Pode ler a origem e o log de execucoes; pode inserir so na tabela da foto.
   ----------------------------------------------------------------------------- */
IF SUSER_ID(N'svc_airflow_snapshot') IS NOT NULL
BEGIN
    IF USER_ID(N'svc_airflow_snapshot') IS NULL
        CREATE USER svc_airflow_snapshot FOR LOGIN svc_airflow_snapshot;

    GRANT SELECT         ON dbo.fact_clima_atual_dia       TO svc_airflow_snapshot;
    GRANT SELECT         ON dbo.etl_execucao               TO svc_airflow_snapshot;
    GRANT SELECT, INSERT ON dbo.fact_previsao_snapshot_dia TO svc_airflow_snapshot;
END
ELSE
    PRINT 'Login svc_airflow_snapshot ainda nao existe: crie e rode este script de novo.';
GO
