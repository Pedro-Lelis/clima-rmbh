/* Regra: os valores da ultima carga incremental precisam ser fisicamente possiveis
   e coerentes entre si. Devolve uma linha com uma coluna por familia de regras:
   1 = nenhuma linha viola, 0 = alguma viola. O SQLCheckOperator falha se qualquer
   coluna for 0, e o log mostra o registro inteiro - da para ver qual familia quebrou.

   Limites fisicos usam recordes mundiais, nao o clima de BH: valor real nunca passa
   deles, mas erro de pipeline passa (temperatura em Kelvin ~295, em Fahrenheit ~95,
   vento em outra unidade, coluna trocada no de-para). Plausibilidade regional fica
   fora da DAG, para nao virar alarme falso no primeiro dia extremo.

   Coerencias tem tolerancia, calibrada na exploracao de 10/11/2026:
   - precipitacao e radiacao: na ponta do horizonte de previsao a soma das partes
     difere do total por arredondamento (0,01 mm; 0,1 W/m2);
   - orvalho: o modelo de previsao chega a dar ponto de orvalho ate 0,7 C acima da
     temperatura. Igualdade e valida (ar saturado); so o excesso grande e defeito.

   Coerencias valem so ate 3 dias a frente (horas realizadas + inicio da previsao).
   Em 13/11/2026, a propria API devolveu para 26/11 (13 dias a frente), das 06h as
   09h, radiacao difusa = 0 em plena manha e direta maior que a total - fisicamente
   impossivel, confirmado chamando a API direto, sem o pipeline. A previsao de longo
   prazo pode vir inconsistente na fonte; erro do nosso pipeline (coluna trocada,
   unidade) apareceria tambem no realizado. Os limites fisicos valem para todas as
   linhas.

   NULL nao viola nenhuma regra (a comparacao nao da verdadeiro): nulos sao da
   checar_nulos. Sem linha nenhuma, cada SUM da NULL e todas as colunas viram 0. */
SELECT
    CASE WHEN SUM(CASE WHEN fca.umidade_relativa_2m        NOT BETWEEN 0 AND 100
                         OR fca.cobertura_nuvens           NOT BETWEEN 0 AND 100
                         OR fca.cobertura_nuvens_baixa     NOT BETWEEN 0 AND 100
                         OR fca.cobertura_nuvens_media     NOT BETWEEN 0 AND 100
                         OR fca.cobertura_nuvens_alta      NOT BETWEEN 0 AND 100
                         OR fca.probabilidade_precipitacao NOT BETWEEN 0 AND 100
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS percentuais_0_100,

    -- recordes: -89,2 C e 56,7 C
    CASE WHEN SUM(CASE WHEN fca.temperatura_2m   NOT BETWEEN -90 AND 60
                         OR fca.ponto_orvalho_2m NOT BETWEEN -90 AND 60
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS temperaturas_ar,

    -- a sensacao termica passa da temperatura real nos extremos
    CASE WHEN SUM(CASE WHEN fca.sensacao_termica NOT BETWEEN -100 AND 80
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS sensacao_termica,

    -- a superficie do solo ja passou de 90 C
    CASE WHEN SUM(CASE WHEN fca.temperatura_solo_0cm  NOT BETWEEN -90 AND 100
                         OR fca.temperatura_solo_6cm  NOT BETWEEN -90 AND 100
                         OR fca.temperatura_solo_18cm NOT BETWEEN -90 AND 100
                         OR fca.temperatura_solo_54cm NOT BETWEEN -90 AND 100
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS temperaturas_solo,

    -- fracao volumetrica (m3 de agua por m3 de solo), nao porcentagem
    CASE WHEN SUM(CASE WHEN fca.umidade_solo_0_1cm   NOT BETWEEN 0 AND 1
                         OR fca.umidade_solo_1_3cm   NOT BETWEEN 0 AND 1
                         OR fca.umidade_solo_3_9cm   NOT BETWEEN 0 AND 1
                         OR fca.umidade_solo_9_27cm  NOT BETWEEN 0 AND 1
                         OR fca.umidade_solo_27_81cm NOT BETWEEN 0 AND 1
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS umidade_solo_0_1,

    -- recordes ao nivel do mar: 870 e 1084 hPa; BH fica a ~900 m
    CASE WHEN SUM(CASE WHEN fca.pressao_nivel_mar  NOT BETWEEN 870 AND 1085
                         OR fca.pressao_superficie NOT BETWEEN 500 AND 1085
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS pressoes,

    -- km/h; maior rajada registrada: 408 km/h
    CASE WHEN SUM(CASE WHEN fca.velocidade_vento_10m  NOT BETWEEN 0 AND 410
                         OR fca.velocidade_vento_100m NOT BETWEEN 0 AND 410
                         OR fca.rajada_vento_10m      NOT BETWEEN 0 AND 410
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS vento,

    -- graus; 0 e 360 aparecem os dois e significam norte
    CASE WHEN SUM(CASE WHEN fca.direcao_vento_10m  NOT BETWEEN 0 AND 360
                         OR fca.direcao_vento_100m NOT BETWEEN 0 AND 360
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS direcao_vento,

    -- evapotranspiracao (do modelo) fica de fora: em tese pode ser negativa (orvalho)
    CASE WHEN SUM(CASE WHEN fca.precipitacao              < 0
                         OR fca.chuva                     < 0
                         OR fca.pancadas_chuva            < 0
                         OR fca.neve                      < 0
                         OR fca.deficit_pressao_vapor     < 0
                         OR fca.visibilidade              < 0
                         OR fca.indice_uv                 < 0
                         OR fca.evapotranspiracao_et0     < 0
                         OR fca.radiacao_direta           < 0
                         OR fca.radiacao_difusa           < 0
                         OR fca.irradiancia_normal_direta < 0
                         OR fca.radiacao_ondas_curtas     < 0
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS nao_negativos,

    -- radiacao_terrestre e a do topo da atmosfera (extraterrestre): max. ~1413 W/m2
    CASE WHEN SUM(CASE WHEN fca.radiacao_terrestre NOT BETWEEN 0 AND 1420
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS radiacao_topo,

    -- segundos de sol dentro de uma hora
    CASE WHEN SUM(CASE WHEN fca.duracao_insolacao NOT BETWEEN 0 AND 3600
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS insolacao,

    -- tabela de codigos WMO
    CASE WHEN SUM(CASE WHEN fca.codigo_tempo NOT BETWEEN 0 AND 99
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS codigo_tempo,

    -- coerencias: so dentro da janela confiavel (ver cabecalho)
    -- precipitacao = chuva + pancadas + neve
    CASE WHEN SUM(CASE WHEN fca.data_hora_local < DATEADD(DAY, 3, GETDATE())
                        AND ABS((fca.chuva + fca.pancadas_chuva + fca.neve) - fca.precipitacao) > 0.1
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS coerencia_precipitacao,

    -- ondas curtas = direta + difusa
    CASE WHEN SUM(CASE WHEN fca.data_hora_local < DATEADD(DAY, 3, GETDATE())
                        AND ABS((fca.radiacao_direta + fca.radiacao_difusa) - fca.radiacao_ondas_curtas) > 1
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS coerencia_radiacoes,

    -- ponto de orvalho nao passa da temperatura (igual = ar saturado)
    CASE WHEN SUM(CASE WHEN fca.data_hora_local < DATEADD(DAY, 3, GETDATE())
                        AND fca.ponto_orvalho_2m - fca.temperatura_2m > 1.0
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS coerencia_orvalho,

    -- o que chega ao chao nao passa do que chega ao topo da atmosfera
    CASE WHEN SUM(CASE WHEN fca.data_hora_local < DATEADD(DAY, 3, GETDATE())
                        AND fca.radiacao_ondas_curtas - fca.radiacao_terrestre > 1
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS coerencia_radiacao_topo

FROM dbo.fact_clima_atual_hora fca
WHERE fca.dt_carga >= (SELECT TOP 1 dt_inicio
                       FROM dbo.etl_execucao
                       WHERE modo = 'incremental'
                       ORDER BY dt_inicio DESC);
