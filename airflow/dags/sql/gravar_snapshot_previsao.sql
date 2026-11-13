/* Foto diaria da previsao: copia os dias ainda previstos (eh_previsao = 1) da
   ultima carga incremental para a fact_previsao_snapshot_dia.

   Roda toda hora, depois das tres checagens, mas so grava uma vez por dia: a
   chave (data_coleta, municipio_id, data_id) + NOT EXISTS fazem a primeira
   carga validada do dia gravar e as seguintes nao fazerem nada. Se as checagens
   falharem a meia-noite, a foto sai na proxima hora que passar.

   data_coleta vem do dt_carga das linhas, nao do relogio da tarefa: se a ultima
   carga for de ontem, a data_coleta e de ontem - e essa ja foi gravada. */
SET NOCOUNT ON;

INSERT INTO dbo.fact_previsao_snapshot_dia
    (data_coleta, municipio_id, data_id, antecedencia_dias,
     codigo_tempo, temperatura_2m_max, temperatura_2m_min, precipitacao_total,
     horas_precipitacao, probabilidade_precipitacao_max, velocidade_vento_10m_max,
     dt_carga_origem)
SELECT
    CAST(fca.dt_carga AS DATE),
    fca.municipio_id,
    fca.data_id,
    DATEDIFF(DAY, CAST(fca.dt_carga AS DATE), CONVERT(DATE, CONVERT(CHAR(8), fca.data_id), 112)),
    fca.codigo_tempo,
    fca.temperatura_2m_max,
    fca.temperatura_2m_min,
    fca.precipitacao_total,
    fca.horas_precipitacao,
    fca.probabilidade_precipitacao_max,
    fca.velocidade_vento_10m_max,
    fca.dt_carga
FROM dbo.fact_clima_atual_dia fca
WHERE fca.eh_previsao = 1
  AND fca.dt_carga >= (SELECT TOP 1 dt_inicio
                       FROM dbo.etl_execucao
                       WHERE modo = 'incremental'
                       ORDER BY dt_inicio DESC)
  AND NOT EXISTS (SELECT 1
                  FROM dbo.fact_previsao_snapshot_dia s
                  WHERE s.data_coleta  = CAST(fca.dt_carga AS DATE)
                    AND s.municipio_id = fca.municipio_id
                    AND s.data_id      = fca.data_id);

-- aparece no log da tarefa: 96 na primeira carga do dia (6 municipios x 16 dias), 0 nas demais
SELECT @@ROWCOUNT AS linhas_gravadas;
