/* =============================================================================
   05_fact_clima_historico_dia.sql
   Fonte..: Open-Meteo /v1/archive  (bloco "daily")
   Grao...: 1 linha por MUNICIPIO x DATA
   Por que uma tabela separada da versao horaria: agregado diario e um grao
   diferente. Misturar os dois na mesma tabela faria qualquer SUM()/AVG()
   contar a mesma grandeza duas vezes. Alem disso, varias medidas daqui
   (nascer/por do sol, horas de chuva, direcao dominante do vento) simplesmente
   nao existem no grao horario.
   ============================================================================= */

USE ClimaRMBH;
GO

IF OBJECT_ID(N'dbo.fact_clima_historico_dia', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.fact_clima_historico_dia
    (
        /* ---------- chaves ---------- */
        municipio_id                  INT           NOT NULL,
        data_id                       INT           NOT NULL,

        /* ---------- condicao do tempo ---------- */
        codigo_tempo                  SMALLINT      NULL,       -- codigo WMO predominante

        /* ---------- temperatura ---------- */
        temperatura_2m_max            DECIMAL(5,2)  NULL,       -- °C
        temperatura_2m_min            DECIMAL(5,2)  NULL,
        temperatura_2m_media          DECIMAL(5,2)  NULL,
        sensacao_termica_max          DECIMAL(5,2)  NULL,
        sensacao_termica_min          DECIMAL(5,2)  NULL,
        sensacao_termica_media        DECIMAL(5,2)  NULL,

        /* ---------- sol ---------- */
        nascer_sol                    DATETIME2(0)  NULL,
        por_sol                       DATETIME2(0)  NULL,
        duracao_dia_claro             DECIMAL(8,1)  NULL,       -- segundos entre nascer e por
        duracao_insolacao             DECIMAL(8,1)  NULL,       -- segundos de sol direto

        /* ---------- precipitacao ---------- */
        precipitacao_total            DECIMAL(7,2)  NULL,       -- mm
        chuva_total                   DECIMAL(7,2)  NULL,       -- mm
        neve_total                    DECIMAL(7,2)  NULL,       -- cm
        horas_precipitacao            DECIMAL(4,1)  NULL,       -- horas com chuva no dia

        /* ---------- vento ---------- */
        velocidade_vento_10m_max      DECIMAL(6,2)  NULL,       -- km/h
        rajada_vento_10m_max          DECIMAL(6,2)  NULL,       -- km/h
        direcao_vento_10m_dominante   SMALLINT      NULL,       -- graus

        /* ---------- energia e agua ---------- */
        radiacao_ondas_curtas_total   DECIMAL(7,3)  NULL,       -- MJ/m2 no dia
        evapotranspiracao_et0         DECIMAL(6,3)  NULL,       -- mm no dia

        /* ---------- auditoria ---------- */
        dt_carga                      DATETIME2(3)  NOT NULL
            CONSTRAINT DF_fchd_dt_carga DEFAULT (SYSDATETIME()),

        CONSTRAINT PK_fact_clima_historico_dia
            PRIMARY KEY CLUSTERED (municipio_id, data_id),
        CONSTRAINT FK_fchd_municipio FOREIGN KEY (municipio_id) REFERENCES dbo.dim_municipio (municipio_id),
        CONSTRAINT FK_fchd_data      FOREIGN KEY (data_id)      REFERENCES dbo.dim_data (data_id)
    );

    CREATE NONCLUSTERED INDEX IX_fchd_data
        ON dbo.fact_clima_historico_dia (data_id, municipio_id);
END
GO
