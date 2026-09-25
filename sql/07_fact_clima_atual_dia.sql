/* =============================================================================
   07_fact_clima_atual_dia.sql
   Fonte..: Open-Meteo /v1/forecast  (bloco "daily")
   Grao...: 1 linha por MUNICIPIO x DATA
   Igual ao historico diario, mais as medidas exclusivas do modelo de previsao
   (indice UV maximo, pancadas, probabilidade maxima de chuva).
   ============================================================================= */

USE ClimaRMBH;
GO

IF OBJECT_ID(N'dbo.fact_clima_atual_dia', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.fact_clima_atual_dia
    (
        municipio_id                   INT           NOT NULL,
        data_id                        INT           NOT NULL,

        codigo_tempo                   SMALLINT      NULL,   -- codigo WMO predominante

        temperatura_2m_max             DECIMAL(5,2)  NULL,   -- °C
        temperatura_2m_min             DECIMAL(5,2)  NULL,   -- °C
        temperatura_2m_media           DECIMAL(5,2)  NULL,   -- °C
        sensacao_termica_max           DECIMAL(5,2)  NULL,   -- °C
        sensacao_termica_min           DECIMAL(5,2)  NULL,   -- °C
        sensacao_termica_media         DECIMAL(5,2)  NULL,   -- °C

        nascer_sol                     DATETIME2(0)  NULL,   -- hora local
        por_sol                        DATETIME2(0)  NULL,   -- hora local
        duracao_dia_claro              DECIMAL(8,1)  NULL,   -- segundos entre nascer e por do sol
        duracao_insolacao              DECIMAL(8,1)  NULL,   -- segundos de sol direto
        indice_uv_max                  DECIMAL(4,2)  NULL,   -- indice UV maximo do dia

        precipitacao_total             DECIMAL(7,2)  NULL,   -- mm
        chuva_total                    DECIMAL(7,2)  NULL,   -- mm
        pancadas_chuva_total           DECIMAL(7,2)  NULL,   -- mm
        neve_total                     DECIMAL(7,2)  NULL,   -- cm
        horas_precipitacao             DECIMAL(4,1)  NULL,   -- horas com chuva no dia
        probabilidade_precipitacao_max TINYINT       NULL,   -- %

        velocidade_vento_10m_max       DECIMAL(6,2)  NULL,   -- km/h
        rajada_vento_10m_max           DECIMAL(6,2)  NULL,   -- km/h
        direcao_vento_10m_dominante    SMALLINT      NULL,   -- graus

        radiacao_ondas_curtas_total    DECIMAL(7,3)  NULL,   -- MJ/m2 no dia
        evapotranspiracao_et0          DECIMAL(6,3)  NULL,   -- mm no dia

        eh_previsao                    BIT           NOT NULL,  -- 1 = dia ainda no futuro na coleta
        dt_carga                       DATETIME2(3)  NOT NULL
            CONSTRAINT DF_fcad_dt_carga DEFAULT (SYSDATETIME()),

        CONSTRAINT PK_fact_clima_atual_dia
            PRIMARY KEY CLUSTERED (municipio_id, data_id),
        CONSTRAINT FK_fcad_municipio FOREIGN KEY (municipio_id) REFERENCES dbo.dim_municipio (municipio_id),
        CONSTRAINT FK_fcad_data      FOREIGN KEY (data_id)      REFERENCES dbo.dim_data (data_id)
    );

    CREATE NONCLUSTERED INDEX IX_fcad_data
        ON dbo.fact_clima_atual_dia (data_id, municipio_id);
END
GO
