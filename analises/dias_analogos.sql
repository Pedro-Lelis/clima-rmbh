/* =============================================================================
   Dias analogos - exploracao (passos 1 e 2 do vetorial)
   Antes de usar o tipo VECTOR, a busca feita "na mao": padronizar as variaveis
   e medir a distancia euclidiana com SQL comum. O passo 3 refaz a mesma busca
   com VECTOR_DISTANCE, e os resultados tem que bater.

   Vetor de cada dia (6 dimensoes), so variaveis que existem no historico E na
   previsao diaria - o dia previsto vai ser comparado com o historico:
     temperatura_2m_max, temperatura_2m_min, precipitacao_total,
     horas_precipitacao, velocidade_vento_10m_max, radiacao_ondas_curtas_total

   Chuva e horas de chuva entram como LOG(1 + x): a distribuicao e muito
   assimetrica (desvio 7,5 mm > media 3,7 mm). Sem o log, um temporal teria
   z ~ +10 e decidiria sozinho a distancia, e a diferenca que importa (seco x
   garoa) valeria quase nada. O "1 +" mantem 0 mm em 0 (log de 0 nao existe).
   ============================================================================= */

/* ---------------------------------------------------------------------------
   Passo 1 - media e desvio-padrao de cada variavel (todos os municipios juntos:
   a mesma regua para todos). STDEVP: os 86 anos tratados como a populacao.
   --------------------------------------------------------------------------- */
SELECT
    AVG(temperatura_2m_max)                    AS media_temp_max,
    AVG(temperatura_2m_min)                    AS media_temp_min,
    AVG(LOG(1 + precipitacao_total))           AS media_log_chuva,
    AVG(LOG(1 + horas_precipitacao))           AS media_log_horas_chuva,
    AVG(velocidade_vento_10m_max)              AS media_vento_max,
    AVG(radiacao_ondas_curtas_total)           AS media_radiacao,
    STDEVP(temperatura_2m_max)                 AS desvio_temp_max,
    STDEVP(temperatura_2m_min)                 AS desvio_temp_min,
    STDEVP(LOG(1 + precipitacao_total))        AS desvio_log_chuva,
    STDEVP(LOG(1 + horas_precipitacao))        AS desvio_log_horas_chuva,
    STDEVP(velocidade_vento_10m_max)           AS desvio_vento_max,
    STDEVP(radiacao_ondas_curtas_total)        AS desvio_radiacao
FROM dbo.fact_clima_historico_dia;

-- confirmacao da assimetria: mediana bem abaixo da media de 3,7 mm
SELECT DISTINCT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY precipitacao_total) OVER () AS mediana_chuva
FROM dbo.fact_clima_historico_dia;


/* ---------------------------------------------------------------------------
   Passo 2 - os 10 dias mais parecidos com um dia escolhido, sem tipo vetorial
   Distancia euclidiana nos z-scores: raiz da soma dos quadrados das diferencas.
   --------------------------------------------------------------------------- */
DECLARE @municipio_id INT  = 1;              -- Belo Horizonte
DECLARE @data_alvo    DATE = '2020-01-24';   -- recorde de chuva, enchentes

-- o dia de referencia, para comparar a olho com os analogos
SELECT dd.data, f.temperatura_2m_max, f.temperatura_2m_min, f.precipitacao_total,
       f.horas_precipitacao, f.velocidade_vento_10m_max, f.radiacao_ondas_curtas_total
FROM dbo.fact_clima_historico_dia f
JOIN dbo.dim_data dd ON dd.data_id = f.data_id
WHERE f.municipio_id = @municipio_id
  AND dd.data = @data_alvo;

WITH estatisticas AS (
    SELECT
        AVG(temperatura_2m_max)              AS media_temp_max,
        AVG(temperatura_2m_min)              AS media_temp_min,
        AVG(LOG(1 + precipitacao_total))     AS media_log_chuva,
        AVG(LOG(1 + horas_precipitacao))     AS media_log_horas_chuva,
        AVG(velocidade_vento_10m_max)        AS media_vento_max,
        AVG(radiacao_ondas_curtas_total)     AS media_radiacao,
        STDEVP(temperatura_2m_max)           AS desvio_temp_max,
        STDEVP(temperatura_2m_min)           AS desvio_temp_min,
        STDEVP(LOG(1 + precipitacao_total))  AS desvio_log_chuva,
        STDEVP(LOG(1 + horas_precipitacao))  AS desvio_log_horas_chuva,
        STDEVP(velocidade_vento_10m_max)     AS desvio_vento_max,
        STDEVP(radiacao_ondas_curtas_total)  AS desvio_radiacao
    FROM dbo.fact_clima_historico_dia
),
padronizado AS (
    -- cada dia do municipio vira 6 z-scores: quantos desvios acima/abaixo da media
    SELECT
        dd.data,
        f.temperatura_2m_max, f.temperatura_2m_min, f.precipitacao_total,
        f.horas_precipitacao, f.velocidade_vento_10m_max, f.radiacao_ondas_curtas_total,
        (f.temperatura_2m_max               - e.media_temp_max)        / e.desvio_temp_max        AS z_temp_max,
        (f.temperatura_2m_min               - e.media_temp_min)        / e.desvio_temp_min        AS z_temp_min,
        (LOG(1 + f.precipitacao_total)      - e.media_log_chuva)       / e.desvio_log_chuva       AS z_chuva,
        (LOG(1 + f.horas_precipitacao)      - e.media_log_horas_chuva) / e.desvio_log_horas_chuva AS z_horas_chuva,
        (f.velocidade_vento_10m_max         - e.media_vento_max)       / e.desvio_vento_max       AS z_vento_max,
        (f.radiacao_ondas_curtas_total      - e.media_radiacao)        / e.desvio_radiacao        AS z_radiacao
    FROM dbo.fact_clima_historico_dia f
    JOIN dbo.dim_data dd ON dd.data_id = f.data_id
    CROSS JOIN estatisticas e
    WHERE f.municipio_id = @municipio_id
),
alvo AS (
    SELECT * FROM padronizado WHERE data = @data_alvo
)
SELECT TOP (10)
    d.data,
    CAST(c.distancia AS DECIMAL(6,3)) AS distancia,
    d.temperatura_2m_max, d.temperatura_2m_min, d.precipitacao_total,
    d.horas_precipitacao, d.velocidade_vento_10m_max, d.radiacao_ondas_curtas_total
FROM padronizado d
CROSS JOIN alvo a
-- a conta fica num lugar so e e reaproveitada no WHERE e no ORDER BY
CROSS APPLY (SELECT SQRT(  SQUARE(d.z_temp_max    - a.z_temp_max)
                         + SQUARE(d.z_temp_min    - a.z_temp_min)
                         + SQUARE(d.z_chuva       - a.z_chuva)
                         + SQUARE(d.z_horas_chuva - a.z_horas_chuva)
                         + SQUARE(d.z_vento_max   - a.z_vento_max)
                         + SQUARE(d.z_radiacao    - a.z_radiacao)) AS distancia) c
-- fora: o proprio episodio (+-10 dias), senao os analogos sao a mesma frente de chuva
WHERE d.data NOT BETWEEN DATEADD(DAY, -10, a.data) AND DATEADD(DAY, 10, a.data)
  -- NULL viria primeiro no ORDER BY crescente
  AND c.distancia IS NOT NULL
ORDER BY c.distancia;
GO


/* ---------------------------------------------------------------------------
   Passo 3 - a mesma busca com o tipo VECTOR (sql/12_vetor_dias_analogos.sql)
   Resultado conferido em 16/11/2026: as mesmas 10 datas, na mesma ordem, e as
   mesmas distancias do passo 2 ate a 3a casa (o VECTOR guarda float32).
   Euclidiana e nao cosseno: o cosseno compara so a DIRECAO do vetor. Um dia
   levemente quente e seco e um dia extremamente quente e seco apontam para o
   mesmo lado (z positivos na temperatura, negativos na chuva) e o cosseno os
   daria como quase identicos; a euclidiana mede tambem o quanto.
   --------------------------------------------------------------------------- */
DECLARE @municipio_id INT = 1;
DECLARE @data_id      INT = 20200124;   -- INT, como a coluna: sem conversao implicita
DECLARE @vetor_alvo   VECTOR(6);

SELECT @vetor_alvo = vetor
FROM dbo.vet_historico_dia
WHERE municipio_id = @municipio_id
  AND data_id      = @data_id;

SELECT TOP (10)
    dd.data,
    VECTOR_DISTANCE('euclidean', v.vetor, @vetor_alvo) AS distancia,
    v.vetor
FROM dbo.vet_historico_dia v
JOIN dbo.dim_data dd ON dd.data_id = v.data_id
WHERE v.municipio_id = @municipio_id
  -- fora o proprio episodio (+-10 dias)
  AND dd.data NOT BETWEEN DATEADD(DAY, -10, CONVERT(DATE, CONVERT(CHAR(8), @data_id), 112))
                      AND DATEADD(DAY,  10, CONVERT(DATE, CONVERT(CHAR(8), @data_id), 112))
ORDER BY distancia;
