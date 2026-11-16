/* =============================================================================
   12_vetor_dias_analogos.sql  -  Vetores do historico para a busca de dias analogos

   Cada dia do historico vira um vetor de 6 dimensoes (tipo VECTOR do SQL Server
   2025), e "dias parecidos" = vetores proximos (VECTOR_DISTANCE euclidiana).
   Sao vetores de atributos escolhidos a mao, nao embeddings de modelo de IA:
   a mecanica de busca e a mesma, a origem dos numeros e outra.

   Dimensoes (todas existem no historico E na previsao diaria):
     1 temperatura_2m_max          4 LOG(1 + horas_precipitacao)
     2 temperatura_2m_min          5 velocidade_vento_10m_max
     3 LOG(1 + precipitacao_total) 6 radiacao_ondas_curtas_total
   Cada uma padronizada (z-score): (valor - media) / desvio. Sem isso a variavel
   de faixa maior domina a distancia. Chuva e horas de chuva passam por log
   antes: distribuicao muito assimetrica (mediana 0,3 mm, media 3,7 mm).
   Exploracao que embasou as escolhas: analises/dias_analogos.sql.

   1) vet_regua - medias e desvios, calculados UMA vez e congelados. O vetor
      do dia previsto precisa da mesma regua do historico, senao os dois nao
      sao comparaveis. Recalcular a regua exige refazer todos os vetores.
   2) vet_historico_dia - um vetor por municipio x dia.
   3) dbo.atualizar_vetores_historico - grava os vetores que faltam e refaz
      os de dias recarregados (o backfill reescreve os 3 ultimos dias do ERA5).
      Idempotente; e o que a DAG vai chamar todo dia.
   ============================================================================= */

USE ClimaRMBH;
GO

/* ---------- 1) a regua ---------- */
IF OBJECT_ID(N'dbo.vet_regua', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.vet_regua
    (
        regua_id               TINYINT       NOT NULL,
        media_temp_max         FLOAT         NOT NULL,
        media_temp_min         FLOAT         NOT NULL,
        media_log_chuva        FLOAT         NOT NULL,
        media_log_horas_chuva  FLOAT         NOT NULL,
        media_vento_max        FLOAT         NOT NULL,
        media_radiacao         FLOAT         NOT NULL,
        desvio_temp_max        FLOAT         NOT NULL,
        desvio_temp_min        FLOAT         NOT NULL,
        desvio_log_chuva       FLOAT         NOT NULL,
        desvio_log_horas_chuva FLOAT         NOT NULL,
        desvio_vento_max       FLOAT         NOT NULL,
        desvio_radiacao        FLOAT         NOT NULL,
        periodo_inicio         DATE          NOT NULL,   -- dias usados no calculo
        periodo_fim            DATE          NOT NULL,
        dt_calculo             DATETIME2(3)  NOT NULL
            CONSTRAINT DF_vet_regua_dt DEFAULT (SYSDATETIME()),
        CONSTRAINT PK_vet_regua PRIMARY KEY CLUSTERED (regua_id),
        CONSTRAINT CK_vet_regua_uma_linha CHECK (regua_id = 1)   -- regua e unica
    );
END
GO

-- so calcula se ainda nao existe: a regua nao muda sozinha
IF NOT EXISTS (SELECT 1 FROM dbo.vet_regua)
BEGIN
    INSERT INTO dbo.vet_regua
        (regua_id,
         media_temp_max, media_temp_min, media_log_chuva, media_log_horas_chuva, media_vento_max, media_radiacao,
         desvio_temp_max, desvio_temp_min, desvio_log_chuva, desvio_log_horas_chuva, desvio_vento_max, desvio_radiacao,
         periodo_inicio, periodo_fim)
    SELECT
        1,
        AVG(CAST(f.temperatura_2m_max AS FLOAT)),
        AVG(CAST(f.temperatura_2m_min AS FLOAT)),
        AVG(LOG(1 + f.precipitacao_total)),
        AVG(LOG(1 + f.horas_precipitacao)),
        AVG(CAST(f.velocidade_vento_10m_max AS FLOAT)),
        AVG(CAST(f.radiacao_ondas_curtas_total AS FLOAT)),
        STDEVP(f.temperatura_2m_max),
        STDEVP(f.temperatura_2m_min),
        STDEVP(LOG(1 + f.precipitacao_total)),
        STDEVP(LOG(1 + f.horas_precipitacao)),
        STDEVP(f.velocidade_vento_10m_max),
        STDEVP(f.radiacao_ondas_curtas_total),
        MIN(dd.data),
        MAX(dd.data)
    FROM dbo.fact_clima_historico_dia f
    JOIN dbo.dim_data dd ON dd.data_id = f.data_id;
END
GO

/* ---------- 2) os vetores ---------- */
IF OBJECT_ID(N'dbo.vet_historico_dia', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.vet_historico_dia
    (
        municipio_id  INT           NOT NULL,
        data_id       INT           NOT NULL,
        vetor         VECTOR(6)     NOT NULL,   -- 6 dimensoes em float32
        dt_calculo    DATETIME2(3)  NOT NULL
            CONSTRAINT DF_vet_historico_dia_dt DEFAULT (SYSDATETIME()),
        CONSTRAINT PK_vet_historico_dia PRIMARY KEY CLUSTERED (municipio_id, data_id),
        CONSTRAINT FK_vhd_municipio FOREIGN KEY (municipio_id) REFERENCES dbo.dim_municipio (municipio_id),
        CONSTRAINT FK_vhd_data      FOREIGN KEY (data_id)      REFERENCES dbo.dim_data (data_id)
    );
END
GO

/* ---------- 3) a carga ---------- */
CREATE OR ALTER PROCEDURE dbo.atualizar_vetores_historico
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- qualquer erro desfaz tudo: nunca fica vetor apagado sem ser refeito

    BEGIN TRANSACTION;

    -- dia recarregado depois do calculo do vetor: o vetor esta velho, sai e volta abaixo
    DELETE v
    FROM dbo.vet_historico_dia v
    JOIN dbo.fact_clima_historico_dia f
      ON f.municipio_id = v.municipio_id
     AND f.data_id      = v.data_id
    WHERE f.dt_carga > v.dt_calculo;

    DECLARE @refeitos INT = @@ROWCOUNT;

    INSERT INTO dbo.vet_historico_dia (municipio_id, data_id, vetor)
    SELECT
        f.municipio_id,
        f.data_id,
        -- JSON_ARRAY monta '[z1, z2, ...]' e o CAST converte para o tipo vetorial
        CAST(JSON_ARRAY(
            (f.temperatura_2m_max          - r.media_temp_max)        / r.desvio_temp_max,
            (f.temperatura_2m_min          - r.media_temp_min)        / r.desvio_temp_min,
            (LOG(1 + f.precipitacao_total) - r.media_log_chuva)       / r.desvio_log_chuva,
            (LOG(1 + f.horas_precipitacao) - r.media_log_horas_chuva) / r.desvio_log_horas_chuva,
            (f.velocidade_vento_10m_max    - r.media_vento_max)       / r.desvio_vento_max,
            (f.radiacao_ondas_curtas_total - r.media_radiacao)        / r.desvio_radiacao
        ) AS VECTOR(6))
    FROM dbo.fact_clima_historico_dia f
    CROSS JOIN dbo.vet_regua r
    -- JSON_ARRAY descarta NULL: uma variavel nula viraria um array de 5 e o CAST falharia
    WHERE f.temperatura_2m_max          IS NOT NULL
      AND f.temperatura_2m_min          IS NOT NULL
      AND f.precipitacao_total          IS NOT NULL
      AND f.horas_precipitacao          IS NOT NULL
      AND f.velocidade_vento_10m_max    IS NOT NULL
      AND f.radiacao_ondas_curtas_total IS NOT NULL
      AND NOT EXISTS (SELECT 1
                      FROM dbo.vet_historico_dia v
                      WHERE v.municipio_id = f.municipio_id
                        AND v.data_id      = f.data_id);

    DECLARE @gravados INT = @@ROWCOUNT;

    COMMIT TRANSACTION;

    SELECT @gravados - @refeitos AS vetores_novos,
           @refeitos             AS vetores_refeitos;
END
GO

EXEC dbo.atualizar_vetores_historico;
GO

SELECT COUNT(*) AS vetores FROM dbo.vet_historico_dia;
GO
