/* =============================================================================
   06_fact_clima_atual_hora.sql
   Fonte..: Open-Meteo /v1/forecast  (modelo de previsao, base ICON)
   Grao...: 1 linha por MUNICIPIO x DATA x HORA
   Por que NAO reaproveitar a tabela do historico:
     1) as profundidades de solo sao outras. O ERA5 (historico) entrega camadas
        0-7 / 7-28 / 28-100 / 100-255 cm; o modelo de previsao entrega
        temperatura em 0 / 6 / 18 / 54 cm e umidade em 0-1 / 1-3 / 3-9 / 9-27 /
        27-81 cm. Sao grandezas diferentes: empilhar as duas na mesma coluna
        seria erro de medicao, nao so de layout.
     2) o forecast tem medidas que o archive nao tem (visibilidade, indice UV,
        probabilidade de chuva, pancadas) e e numero previsto, revisado a cada
        coleta, enquanto o historico e reanalise estavel.
   Reprocesso: a coleta diaria traz dias recentes ja realizados + ate 16 dias a
   frente. O MERGE sobrescreve a linha, entao a previsao vai sendo corrigida.
   ============================================================================= */

USE ClimaRMBH;
GO

IF OBJECT_ID(N'dbo.fact_clima_atual_hora', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.fact_clima_atual_hora
    (
        municipio_id                 INT           NOT NULL,
        data_id                      INT           NOT NULL,
        hora                         TINYINT       NOT NULL,                  -- 0..23 (local, UTC-3)
        data_hora_local              DATETIME2(0)  NOT NULL,                  -- eixo continuo para o Power BI

        temperatura_2m               DECIMAL(5,2)  NULL,                      -- °C
        umidade_relativa_2m          DECIMAL(5,2)  NULL,                      -- %
        ponto_orvalho_2m             DECIMAL(5,2)  NULL,                      -- °C
        sensacao_termica             DECIMAL(5,2)  NULL,                      -- °C (sensacao termica)
        deficit_pressao_vapor        DECIMAL(6,3)  NULL,                      -- kPa

        precipitacao                 DECIMAL(6,2)  NULL,                      -- mm (total)
        chuva                        DECIMAL(6,2)  NULL,                      -- mm
        pancadas_chuva               DECIMAL(6,2)  NULL,                      -- mm (pancadas convectivas)
        neve                         DECIMAL(6,2)  NULL,                      -- cm
        probabilidade_precipitacao   TINYINT       NULL,                      -- %

        codigo_tempo                 SMALLINT      NULL,                      -- codigo WMO
        eh_dia                       BIT           NULL,                      -- 1 = dia, 0 = noite
        visibilidade                 DECIMAL(9,1)  NULL,                      -- metros
        indice_uv                    DECIMAL(4,2)  NULL,                      -- indice UV

        pressao_nivel_mar            DECIMAL(6,1)  NULL,                      -- hPa (nivel do mar)
        pressao_superficie           DECIMAL(6,1)  NULL,                      -- hPa (superficie)
        cobertura_nuvens             DECIMAL(5,2)  NULL,                      -- %
        cobertura_nuvens_baixa       DECIMAL(5,2)  NULL,                      -- %
        cobertura_nuvens_media       DECIMAL(5,2)  NULL,                      -- %
        cobertura_nuvens_alta        DECIMAL(5,2)  NULL,                      -- %

        velocidade_vento_10m         DECIMAL(6,2)  NULL,                      -- km/h
        velocidade_vento_100m        DECIMAL(6,2)  NULL,                      -- km/h
        direcao_vento_10m            SMALLINT      NULL,                      -- graus
        direcao_vento_100m           SMALLINT      NULL,                      -- graus
        rajada_vento_10m             DECIMAL(6,2)  NULL,                      -- km/h (rajada)

        temperatura_solo_0cm         DECIMAL(5,2)  NULL,                      -- °C
        temperatura_solo_6cm         DECIMAL(5,2)  NULL,                      -- °C
        temperatura_solo_18cm        DECIMAL(5,2)  NULL,                      -- °C
        temperatura_solo_54cm        DECIMAL(5,2)  NULL,                      -- °C
        umidade_solo_0_1cm           DECIMAL(5,3)  NULL,                      -- m3/m3
        umidade_solo_1_3cm           DECIMAL(5,3)  NULL,                      -- m3/m3
        umidade_solo_3_9cm           DECIMAL(5,3)  NULL,                      -- m3/m3
        umidade_solo_9_27cm          DECIMAL(5,3)  NULL,                      -- m3/m3
        umidade_solo_27_81cm         DECIMAL(5,3)  NULL,                      -- m3/m3

        radiacao_ondas_curtas        DECIMAL(7,2)  NULL,                      -- W/m2 (global horizontal)
        radiacao_direta              DECIMAL(7,2)  NULL,                      -- W/m2
        radiacao_difusa              DECIMAL(7,2)  NULL,                      -- W/m2
        irradiancia_normal_direta    DECIMAL(7,2)  NULL,                      -- W/m2
        radiacao_terrestre           DECIMAL(7,2)  NULL,                      -- W/m2
        duracao_insolacao            DECIMAL(8,1)  NULL,                      -- segundos de sol na hora

        evapotranspiracao            DECIMAL(6,3)  NULL,                      -- mm (real, do modelo)
        evapotranspiracao_et0        DECIMAL(6,3)  NULL,                      -- mm (referencia FAO-56)

        eh_previsao                  BIT           NOT NULL,                  -- 1 = hora ainda no futuro no momento da coleta
        dt_carga                     DATETIME2(3)  NOT NULL
            CONSTRAINT DF_fcah_dt_carga DEFAULT (SYSDATETIME()),

        CONSTRAINT PK_fact_clima_atual_hora
            PRIMARY KEY CLUSTERED (municipio_id, data_id, hora),
        CONSTRAINT FK_fcah_municipio FOREIGN KEY (municipio_id) REFERENCES dbo.dim_municipio (municipio_id),
        CONSTRAINT FK_fcah_data      FOREIGN KEY (data_id)      REFERENCES dbo.dim_data (data_id),
        CONSTRAINT CK_fcah_hora      CHECK (hora BETWEEN 0 AND 23)
    );

    CREATE NONCLUSTERED INDEX IX_fcah_data
        ON dbo.fact_clima_atual_hora (data_id, municipio_id);
END
GO
