/* Regra: nenhuma coluna de medida pode vir 100% nula na ultima carga incremental.
   Coluna inteira vazia indica variavel renomeada ou removida pela API, ou de-para
   (ingestao/nomes.py) quebrado - a carga nao falha, a completude passa, e so esta
   checagem acusa.
   Nao e "zero nulos": as 9 colunas de solo vem nulas nas ultimas ~26 h do horizonte
   de 16 dias (o modelo de previsao nao calcula solo ate o fim), e isso e esperado.
   Lista das 42 colunas de medida de fact_clima_atual_hora; coluna nova na tabela
   precisa entrar aqui tambem. Devolve 1 (passa) ou 0 (falha). */
WITH conferir_colunas AS (
    SELECT
        v.Indicador,
        COUNT(v.Valor) AS nao_nulos
    FROM dbo.fact_clima_atual_hora cah
    CROSS APPLY (
        VALUES
            ('temperatura_2m',             CAST(cah.temperatura_2m             AS SQL_VARIANT)),
            ('umidade_relativa_2m',        CAST(cah.umidade_relativa_2m        AS SQL_VARIANT)),
            ('ponto_orvalho_2m',           CAST(cah.ponto_orvalho_2m           AS SQL_VARIANT)),
            ('sensacao_termica',           CAST(cah.sensacao_termica           AS SQL_VARIANT)),
            ('deficit_pressao_vapor',      CAST(cah.deficit_pressao_vapor      AS SQL_VARIANT)),
            ('precipitacao',               CAST(cah.precipitacao               AS SQL_VARIANT)),
            ('chuva',                      CAST(cah.chuva                      AS SQL_VARIANT)),
            ('pancadas_chuva',             CAST(cah.pancadas_chuva             AS SQL_VARIANT)),
            ('neve',                       CAST(cah.neve                       AS SQL_VARIANT)),
            ('probabilidade_precipitacao', CAST(cah.probabilidade_precipitacao AS SQL_VARIANT)),
            ('codigo_tempo',               CAST(cah.codigo_tempo               AS SQL_VARIANT)),
            ('eh_dia',                     CAST(cah.eh_dia                     AS SQL_VARIANT)),
            ('visibilidade',               CAST(cah.visibilidade               AS SQL_VARIANT)),
            ('indice_uv',                  CAST(cah.indice_uv                  AS SQL_VARIANT)),
            ('pressao_nivel_mar',          CAST(cah.pressao_nivel_mar          AS SQL_VARIANT)),
            ('pressao_superficie',         CAST(cah.pressao_superficie         AS SQL_VARIANT)),
            ('cobertura_nuvens',           CAST(cah.cobertura_nuvens           AS SQL_VARIANT)),
            ('cobertura_nuvens_baixa',     CAST(cah.cobertura_nuvens_baixa     AS SQL_VARIANT)),
            ('cobertura_nuvens_media',     CAST(cah.cobertura_nuvens_media     AS SQL_VARIANT)),
            ('cobertura_nuvens_alta',      CAST(cah.cobertura_nuvens_alta      AS SQL_VARIANT)),
            ('velocidade_vento_10m',       CAST(cah.velocidade_vento_10m       AS SQL_VARIANT)),
            ('velocidade_vento_100m',      CAST(cah.velocidade_vento_100m      AS SQL_VARIANT)),
            ('direcao_vento_10m',          CAST(cah.direcao_vento_10m          AS SQL_VARIANT)),
            ('direcao_vento_100m',         CAST(cah.direcao_vento_100m         AS SQL_VARIANT)),
            ('rajada_vento_10m',           CAST(cah.rajada_vento_10m           AS SQL_VARIANT)),
            ('temperatura_solo_0cm',       CAST(cah.temperatura_solo_0cm       AS SQL_VARIANT)),
            ('temperatura_solo_6cm',       CAST(cah.temperatura_solo_6cm       AS SQL_VARIANT)),
            ('temperatura_solo_18cm',      CAST(cah.temperatura_solo_18cm      AS SQL_VARIANT)),
            ('temperatura_solo_54cm',      CAST(cah.temperatura_solo_54cm      AS SQL_VARIANT)),
            ('umidade_solo_0_1cm',         CAST(cah.umidade_solo_0_1cm         AS SQL_VARIANT)),
            ('umidade_solo_1_3cm',         CAST(cah.umidade_solo_1_3cm         AS SQL_VARIANT)),
            ('umidade_solo_3_9cm',         CAST(cah.umidade_solo_3_9cm         AS SQL_VARIANT)),
            ('umidade_solo_9_27cm',        CAST(cah.umidade_solo_9_27cm        AS SQL_VARIANT)),
            ('umidade_solo_27_81cm',       CAST(cah.umidade_solo_27_81cm       AS SQL_VARIANT)),
            ('radiacao_ondas_curtas',      CAST(cah.radiacao_ondas_curtas      AS SQL_VARIANT)),
            ('radiacao_direta',            CAST(cah.radiacao_direta            AS SQL_VARIANT)),
            ('radiacao_difusa',            CAST(cah.radiacao_difusa            AS SQL_VARIANT)),
            ('irradiancia_normal_direta',  CAST(cah.irradiancia_normal_direta  AS SQL_VARIANT)),
            ('radiacao_terrestre',         CAST(cah.radiacao_terrestre         AS SQL_VARIANT)),
            ('duracao_insolacao',          CAST(cah.duracao_insolacao          AS SQL_VARIANT)),
            ('evapotranspiracao',          CAST(cah.evapotranspiracao          AS SQL_VARIANT)),
            ('evapotranspiracao_et0',      CAST(cah.evapotranspiracao_et0      AS SQL_VARIANT))
    ) AS v(Indicador, Valor)
    WHERE cah.dt_carga >= (
        SELECT TOP 1 dt_inicio
        FROM dbo.etl_execucao
        WHERE modo = 'incremental'
        ORDER BY dt_inicio DESC
    )
    GROUP BY v.Indicador
)

SELECT CASE
           -- conta as colunas vazias; sem linha nenhuma, SUM da NULL e cai no ELSE
           WHEN SUM(CASE WHEN cco.nao_nulos = 0 THEN 1 ELSE 0 END) = 0 THEN 1
           ELSE 0
       END AS conferencia
FROM conferir_colunas cco;
