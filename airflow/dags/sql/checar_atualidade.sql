/* Regra: o dado historico (ERA5) de cada municipio precisa estar em dia.
   Devolve uma linha: 1 = todos em dia, 0 = algum atrasado ou sem dado.

   Por que hoje - 7: o backfill pede ate hoje - 6 (ATRASO_ARCHIVE_DIAS = 6 no
   ingestao.py), entao uma carga boa deixa o ultimo registro em hoje - 6. O dia a
   mais tolera um atraso pontual do ERA5 sem alarme falso, e ainda pega quando a
   carga para de avancar. Se a constante mudar no script, este limite muda junto.

   - Parte da dim_municipio com LEFT JOIN: municipio sem nenhuma linha continua
     no resultado, em vez de sumir.
   - temperatura_2m IS NOT NULL no ON: dia que o ERA5 ainda nao publicou pode vir
     com as horas nulas; linha sem dado real nao conta como atualizada. No WHERE,
     o filtro desfaria o LEFT JOIN.
   - IS NULL no CASE: o MAX de um municipio sem linhas e NULL, e NULL < data nao
     da verdadeiro. Sem esse teste, o municipio vazio passaria como em dia. */
WITH ultimo_por_municipio AS (
    SELECT
        dmm.municipio_id,
        CAST(MAX(fhh.data_hora_local) AS DATE) AS ultimo_registro
    FROM dbo.dim_municipio dmm
    LEFT JOIN dbo.fact_clima_historico_hora fhh
           ON fhh.municipio_id = dmm.municipio_id
          AND fhh.temperatura_2m IS NOT NULL
    GROUP BY dmm.municipio_id
)
SELECT
    CASE WHEN SUM(CASE WHEN upm.ultimo_registro < DATEADD(DAY, -7, CAST(GETDATE() AS DATE))
                         OR upm.ultimo_registro IS NULL
                       THEN 1 ELSE 0 END) = 0
         THEN 1 ELSE 0 END AS conferencia
FROM ultimo_por_municipio upm;
