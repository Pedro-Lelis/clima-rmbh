/* =============================================================================
   04_fact_clima_historico_hora.sql
   Fonte..: Open-Meteo /v1/archive  (reanalise ERA5 / ERA5-Land / ECMWF IFS)
   Grao...: 1 linha por MUNICIPIO x DATA x HORA
   Fuso...: a API e chamada com timezone=America/Sao_Paulo, que na Open-Meteo
            equivale a UTC-3 FIXO - testado em 2018-11-04 (virada do antigo
            horario de verao) e a serie voltou 24 horas, sem hora repetida nem
            faltante. Por isso (data_id, hora) e uma chave segura.
   Nomes..: as colunas de medida estao em portugues. O de-para com o nome da
            variavel na API vive em ingestao/nomes.py - variavel nova pedida a
            API precisa ser cadastrada la para nao ser ignorada na carga.
   ============================================================================= */

USE ClimaRMBH;
GO

IF OBJECT_ID(N'dbo.fact_clima_historico_hora', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.fact_clima_historico_hora
    (
        /* ---------- chaves ---------- */
        municipio_id                   INT           NOT NULL,
        data_id                        INT           NOT NULL,
        hora                           TINYINT       NOT NULL,   -- 0..23 (local, UTC-3)
        data_hora_local                DATETIME2(0)  NOT NULL,   -- eixo continuo para o Power BI

        /* ---------- temperatura e umidade ---------- */
        temperatura_2m                 DECIMAL(5,2)  NULL,       -- °C
        umidade_relativa_2m            DECIMAL(5,2)  NULL,       -- %
        ponto_orvalho_2m               DECIMAL(5,2)  NULL,       -- °C
        sensacao_termica               DECIMAL(5,2)  NULL,       -- °C (sensacao termica)
        deficit_pressao_vapor          DECIMAL(6,3)  NULL,       -- kPa

        /* ---------- precipitacao ---------- */
        precipitacao                   DECIMAL(6,2)  NULL,       -- mm (chuva + neve equiv.)
        chuva                          DECIMAL(6,2)  NULL,       -- mm
        neve                           DECIMAL(6,2)  NULL,       -- cm (sempre 0 na RMBH; mantida por fidelidade ao payload)

        /* ---------- condicao do tempo ---------- */
        codigo_tempo                   SMALLINT      NULL,       -- codigo WMO
        eh_dia                         BIT           NULL,

        /* ---------- pressao e nuvens ---------- */
        pressao_nivel_mar              DECIMAL(6,1)  NULL,       -- hPa (nivel do mar)
        pressao_superficie             DECIMAL(6,1)  NULL,       -- hPa (superficie)
        cobertura_nuvens               DECIMAL(5,2)  NULL,       -- %
        cobertura_nuvens_baixa         DECIMAL(5,2)  NULL,
        cobertura_nuvens_media         DECIMAL(5,2)  NULL,
        cobertura_nuvens_alta          DECIMAL(5,2)  NULL,

        /* ---------- vento ---------- */
        velocidade_vento_10m           DECIMAL(6,2)  NULL,       -- km/h
        velocidade_vento_100m          DECIMAL(6,2)  NULL,
        direcao_vento_10m              SMALLINT      NULL,       -- graus
        direcao_vento_100m             SMALLINT      NULL,
        rajada_vento_10m               DECIMAL(6,2)  NULL,       -- km/h (rajada)

        /* ---------- solo (profundidades do ERA5-Land) ---------- */
        temperatura_solo_0_7cm         DECIMAL(5,2)  NULL,       -- °C
        temperatura_solo_7_28cm        DECIMAL(5,2)  NULL,
        temperatura_solo_28_100cm      DECIMAL(5,2)  NULL,
        temperatura_solo_100_255cm     DECIMAL(5,2)  NULL,
        umidade_solo_0_7cm             DECIMAL(5,3)  NULL,       -- m3/m3
        umidade_solo_7_28cm            DECIMAL(5,3)  NULL,
        umidade_solo_28_100cm          DECIMAL(5,3)  NULL,
        umidade_solo_100_255cm         DECIMAL(5,3)  NULL,

        /* ---------- radiacao solar ---------- */
        radiacao_ondas_curtas          DECIMAL(7,2)  NULL,       -- W/m2 (global horizontal)
        radiacao_direta                DECIMAL(7,2)  NULL,
        radiacao_difusa                DECIMAL(7,2)  NULL,
        irradiancia_normal_direta      DECIMAL(7,2)  NULL,
        radiacao_terrestre             DECIMAL(7,2)  NULL,
        duracao_insolacao              DECIMAL(8,1)  NULL,       -- segundos de sol na hora

        /* ---------- agua ---------- */
        evapotranspiracao_et0          DECIMAL(6,3)  NULL,       -- mm (ET0 referencia FAO-56)

        /* ---------- auditoria ---------- */
        dt_carga                       DATETIME2(3)  NOT NULL
            CONSTRAINT DF_fchh_dt_carga DEFAULT (SYSDATETIME()),

        CONSTRAINT PK_fact_clima_historico_hora
            PRIMARY KEY CLUSTERED (municipio_id, data_id, hora),
        CONSTRAINT FK_fchh_municipio FOREIGN KEY (municipio_id) REFERENCES dbo.dim_municipio (municipio_id),
        CONSTRAINT FK_fchh_data      FOREIGN KEY (data_id)      REFERENCES dbo.dim_data (data_id),
        CONSTRAINT CK_fchh_hora      CHECK (hora BETWEEN 0 AND 23)
    );

    /* A PK comeca por municipio_id (bom para "1 municipio, muitos anos").
       Este indice cobre o caminho oposto: "um periodo, todos os municipios",
       que e o filtro tipico do painel. */
    CREATE NONCLUSTERED INDEX IX_fchh_data
        ON dbo.fact_clima_historico_hora (data_id, municipio_id);
END
GO
