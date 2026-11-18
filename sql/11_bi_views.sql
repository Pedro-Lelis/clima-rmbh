/* =============================================================================
   11_bi_views.sql  -  Camada de leitura do Power BI (schema bi)

   O Power BI le so estas views, nunca as tabelas:
   - desacopla o painel do modelo fisico (mudar uma tabela nao quebra o .pbix
     se a view mantiver o contrato);
   - agregacoes pesadas ficam no SQL Server (4,5 mi de linhas horarias viram
     ~190 mil diarias e ~520 anuais) e o .pbix fica leve;
   - o login do painel enxerga so o schema bi. Funciona sem permissao nas
     tabelas por encadeamento de propriedade (ownership chaining): schema bi e
     schema dbo tem o mesmo dono (dbo), entao a permissao e checada so na view.

   Views por pagina do painel:
     comuns ........ vw_municipio, vw_data, vw_codigo_tempo
     1 agora ....... vw_condicao_atual, vw_previsao_hora, vw_previsao_dia
     2 historico ... vw_historico_dia, vw_historico_ano
     3 previsao .... vw_previsao_x_realizado
     5 pipeline .... vw_execucoes
   (pagina 4, dias analogos, entra com a tabela do vetorial)
   ============================================================================= */

USE ClimaRMBH;
GO

IF SCHEMA_ID(N'bi') IS NULL
    EXEC (N'CREATE SCHEMA bi AUTHORIZATION dbo;');
GO

/* ---------------------------------------------------------------------------
   Comuns
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW bi.vw_municipio
AS
SELECT municipio_id,
       nome,
       codigo_ibge,
       uf,
       latitude,      -- no Power BI: categoria de dados Latitude (visual de mapa)
       longitude,
       elevacao_m
FROM dbo.dim_municipio;
GO

CREATE OR ALTER VIEW bi.vw_data
AS
SELECT data_id,
       data,
       ano,
       (ano / 10) * 10                                   AS decada,       -- 1940, 1950...
       CONCAT((ano / 10) * 10, N'–', (ano / 10) * 10 + 9) AS decada_nome,  -- '1940–1949'
       trimestre,
       mes,
       nome_mes,
       nome_mes_abrev,
       ano_mes,
       ano_mes_nome,
       dia,
       dia_do_ano,
       semana_iso,
       num_dia_semana,
       nome_dia_semana,
       eh_fim_de_semana,
       estacao
FROM dbo.dim_data;
GO

-- codigos WMO usados pela Open-Meteo, com texto em portugues e um grupo para cores/icones
CREATE OR ALTER VIEW bi.vw_codigo_tempo
AS
SELECT codigo_tempo, descricao, grupo
FROM (VALUES
    (0,  N'Céu limpo',                        N'Limpo'),
    (1,  N'Predominantemente limpo',          N'Limpo'),
    (2,  N'Parcialmente nublado',             N'Nublado'),
    (3,  N'Encoberto',                        N'Nublado'),
    (45, N'Nevoeiro',                         N'Nevoeiro'),
    (48, N'Nevoeiro com geada',               N'Nevoeiro'),
    (51, N'Garoa fraca',                      N'Garoa'),
    (53, N'Garoa moderada',                   N'Garoa'),
    (55, N'Garoa intensa',                    N'Garoa'),
    (56, N'Garoa congelante fraca',           N'Garoa'),
    (57, N'Garoa congelante intensa',         N'Garoa'),
    (61, N'Chuva fraca',                      N'Chuva'),
    (63, N'Chuva moderada',                   N'Chuva'),
    (65, N'Chuva forte',                      N'Chuva'),
    (66, N'Chuva congelante fraca',           N'Chuva'),
    (67, N'Chuva congelante forte',           N'Chuva'),
    (71, N'Neve fraca',                       N'Neve'),
    (73, N'Neve moderada',                    N'Neve'),
    (75, N'Neve forte',                       N'Neve'),
    (77, N'Grãos de neve',                    N'Neve'),
    (80, N'Pancadas de chuva fracas',         N'Pancadas'),
    (81, N'Pancadas de chuva moderadas',      N'Pancadas'),
    (82, N'Pancadas de chuva violentas',      N'Pancadas'),
    (85, N'Pancadas de neve fracas',          N'Neve'),
    (86, N'Pancadas de neve fortes',          N'Neve'),
    (95, N'Trovoada',                         N'Trovoada'),
    (96, N'Trovoada com granizo fraco',       N'Trovoada'),
    (99, N'Trovoada com granizo forte',       N'Trovoada')
) AS c (codigo_tempo, descricao, grupo);
GO

/* ---------------------------------------------------------------------------
   Pagina 1 - agora e proximos 16 dias
   "Agora" = momento da ultima atualizacao do painel (modo importacao).
   --------------------------------------------------------------------------- */

-- ultima hora ja realizada de cada municipio (cartoes do topo)
CREATE OR ALTER VIEW bi.vw_condicao_atual
AS
SELECT municipio_id, data_id, data_hora_local, codigo_tempo,
       temperatura_2m, sensacao_termica, umidade_relativa_2m, ponto_orvalho_2m, precipitacao,
       velocidade_vento_10m, rajada_vento_10m, direcao_vento_10m,
       cobertura_nuvens, indice_uv, dt_carga
FROM (
    SELECT fah.*,
           ROW_NUMBER() OVER (PARTITION BY fah.municipio_id ORDER BY fah.data_hora_local DESC) AS ordem
    FROM dbo.fact_clima_atual_hora fah
    WHERE fah.eh_previsao = 0
) ultima
WHERE ordem = 1;
GO

-- janela horaria: 7 dias passados + previsao (graficos de linha)
CREATE OR ALTER VIEW bi.vw_previsao_hora
AS
SELECT municipio_id, data_id, hora, data_hora_local, eh_previsao, codigo_tempo,
       temperatura_2m, sensacao_termica, umidade_relativa_2m,
       precipitacao, probabilidade_precipitacao,
       velocidade_vento_10m, rajada_vento_10m, direcao_vento_10m,
       cobertura_nuvens, indice_uv, radiacao_ondas_curtas
FROM dbo.fact_clima_atual_hora
WHERE data_hora_local >= DATEADD(DAY, -7, CAST(GETDATE() AS DATE));
GO

CREATE OR ALTER VIEW bi.vw_previsao_dia
AS
SELECT municipio_id, data_id, eh_previsao, codigo_tempo,
       temperatura_2m_max, temperatura_2m_min, temperatura_2m_media,
       sensacao_termica_max, sensacao_termica_min,
       precipitacao_total, horas_precipitacao, probabilidade_precipitacao_max,
       velocidade_vento_10m_max, rajada_vento_10m_max, direcao_vento_10m_dominante,
       indice_uv_max,
       CAST(duracao_insolacao / 3600.0 AS DECIMAL(4,1)) AS horas_sol,
       nascer_sol, por_sol
FROM dbo.fact_clima_atual_dia
WHERE data_id >= CONVERT(INT, CONVERT(CHAR(8), DATEADD(DAY, -7, GETDATE()), 112));
GO

/* ---------------------------------------------------------------------------
   Pagina 2 - 86 anos de clima (ERA5)
   --------------------------------------------------------------------------- */

-- ~190 mil linhas: base para extremos, ciclo mensal por decada e filtros
CREATE OR ALTER VIEW bi.vw_historico_dia
AS
SELECT municipio_id, data_id, codigo_tempo,
       temperatura_2m_max, temperatura_2m_min, temperatura_2m_media,
       sensacao_termica_max,
       precipitacao_total, horas_precipitacao,
       velocidade_vento_10m_max, rajada_vento_10m_max,
       radiacao_ondas_curtas_total,
       CAST(duracao_insolacao / 3600.0 AS DECIMAL(4,1)) AS horas_sol,
       CAST(duracao_dia_claro / 3600.0 AS DECIMAL(4,1)) AS horas_dia_claro
FROM dbo.fact_clima_historico_dia;
GO

/* Uma linha por municipio x ano. Anomalia = media do ano - media de 1961-1990
   do mesmo municipio (periodo de referencia classico da WMO). E a base das
   "faixas de aquecimento". O ano corrente vem marcado como incompleto: a media
   de um ano pela metade puxa para a estacao que ja passou - filtrar no painel. */
CREATE OR ALTER VIEW bi.vw_historico_ano
AS
WITH anual AS (
    SELECT fhd.municipio_id,
           dd.ano,
           COUNT(*)                                                       AS dias_no_ano,
           CAST(AVG(fhd.temperatura_2m_media) AS DECIMAL(5,2))            AS temp_media,
           MAX(fhd.temperatura_2m_max)                                    AS temp_max_ano,
           MIN(fhd.temperatura_2m_min)                                    AS temp_min_ano,
           SUM(fhd.precipitacao_total)                                    AS chuva_total,
           SUM(CASE WHEN fhd.precipitacao_total  >= 1  THEN 1 ELSE 0 END) AS dias_com_chuva,
           SUM(CASE WHEN fhd.temperatura_2m_max  >  30 THEN 1 ELSE 0 END) AS dias_max_acima_30,
           SUM(CASE WHEN fhd.temperatura_2m_min  <  10 THEN 1 ELSE 0 END) AS dias_min_abaixo_10
    FROM dbo.fact_clima_historico_dia fhd
    JOIN dbo.dim_data dd ON dd.data_id = fhd.data_id
    GROUP BY fhd.municipio_id, dd.ano
),
referencia AS (
    SELECT municipio_id,
           CAST(AVG(temp_media) AS DECIMAL(5,2)) AS temp_media_1961_1990
    FROM anual
    WHERE ano BETWEEN 1961 AND 1990
    GROUP BY municipio_id
)
SELECT a.municipio_id,
       a.ano,
       (a.ano / 10) * 10                                     AS decada,
       a.dias_no_ano,
       CAST(CASE WHEN a.ano < YEAR(GETDATE()) THEN 1 ELSE 0 END AS BIT) AS ano_completo,
       a.temp_media,
       r.temp_media_1961_1990,
       CAST(a.temp_media - r.temp_media_1961_1990 AS DECIMAL(5,2)) AS anomalia_temp,
       a.temp_max_ano,
       a.temp_min_ano,
       a.chuva_total,
       a.dias_com_chuva,
       a.dias_max_acima_30,
       a.dias_min_abaixo_10
FROM anual a
JOIN referencia r ON r.municipio_id = a.municipio_id;
GO

/* ---------------------------------------------------------------------------
   Pagina 3 - previsao x realizado
   Cada foto da previsao cruzada com o realizado do mesmo dia (eh_previsao = 0:
   o dia ja terminou). Dias previstos que ainda nao aconteceram nao aparecem.
   erro = previsto - realizado: positivo = a previsao exagerou.
   Realizado = o proprio modelo de previsao depois que o dia passa (mesma grade,
   isola o erro da previsao); nao e o ERA5.
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW bi.vw_previsao_x_realizado
AS
SELECT s.data_coleta,
       s.municipio_id,
       s.data_id,
       s.antecedencia_dias,

       s.temperatura_2m_max                              AS temp_max_prevista,
       r.temperatura_2m_max                              AS temp_max_realizada,
       s.temperatura_2m_max - r.temperatura_2m_max       AS erro_temp_max,

       s.temperatura_2m_min                              AS temp_min_prevista,
       r.temperatura_2m_min                              AS temp_min_realizada,
       s.temperatura_2m_min - r.temperatura_2m_min       AS erro_temp_min,

       s.precipitacao_total                              AS chuva_prevista,
       r.precipitacao_total                              AS chuva_realizada,
       s.precipitacao_total - r.precipitacao_total       AS erro_chuva,

       s.probabilidade_precipitacao_max                  AS probabilidade_chuva_prevista,
       -- dia chuvoso = 1 mm ou mais (limiar usual; abaixo disso e garoa/orvalho)
       CAST(CASE WHEN s.precipitacao_total >= 1 THEN 1 ELSE 0 END AS BIT) AS choveu_previsto,
       CAST(CASE WHEN r.precipitacao_total >= 1 THEN 1 ELSE 0 END AS BIT) AS choveu_realizado
FROM dbo.fact_previsao_snapshot_dia s
JOIN dbo.fact_clima_atual_dia r
  ON r.municipio_id = s.municipio_id
 AND r.data_id      = s.data_id
 AND r.eh_previsao  = 0;
GO

/* ---------------------------------------------------------------------------
   Pagina 5 - saude do pipeline
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW bi.vw_execucoes
AS
SELECT execucao_id,
       modo,
       status,
       CONVERT(INT, CONVERT(CHAR(8), dt_inicio, 112)) AS data_id,
       dt_inicio,
       dt_fim,
       DATEDIFF(SECOND, dt_inicio, dt_fim)            AS duracao_s,
       linhas_hora,
       linhas_dia
FROM dbo.etl_execucao;
GO

/* ---------------------------------------------------------------------------
   Login do painel: so leitura, so no schema bi.
   O LOGIN e criado a mao, com a senha do Bitwarden (nunca neste arquivo):
     CREATE LOGIN svc_powerbi_leitura WITH PASSWORD = '<SENHA>', CHECK_POLICY = ON;
   --------------------------------------------------------------------------- */
IF SUSER_ID(N'svc_powerbi_leitura') IS NOT NULL
BEGIN
    IF USER_ID(N'svc_powerbi_leitura') IS NULL
        CREATE USER svc_powerbi_leitura FOR LOGIN svc_powerbi_leitura;

    GRANT SELECT ON SCHEMA::bi TO svc_powerbi_leitura;
END
ELSE
    PRINT 'Login svc_powerbi_leitura ainda nao existe: crie e rode este script de novo.';
GO
