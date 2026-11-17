/* =============================================================================
   13_vet_analogos.sql  -  Dias analogos dos proximos dias previstos (producao)

   Para cada municipio e cada um dos proximos 7 dias da previsao: o vetor do
   dia previsto (mesma regua do historico, vet_regua) e os 10 dias do historico
   mais proximos dele por VECTOR_DISTANCE euclidiana. O painel mostra o que
   aconteceu nos dias seguintes a esses analogos - o "metodo dos analogos".

   Decisoes:
   - So 7 dias a frente: alem disso a previsao e pouco confiavel (e ja veio
     fisicamente inconsistente na fonte - caso de 13/11/2026 no README).
   - Um analogo por ano: dias vizinhos da mesma onda de calor ou da mesma frente
     contariam a mesma historia varias vezes (no teste, 3 dos 10 eram de 1963).
   - Fora os ultimos 30 dias do historico: seriam o proprio episodio em curso.
   - A tabela guarda so o calculo mais recente: a procedure troca tudo numa
     transacao, e o painel nunca ve a tabela pela metade.

   Busca exata (compara com os ~190 mil vetores): 7 dias x 6 municipios x ~32
   mil dias = ~1,3 milhao de distancias, segundos. Um indice vetorial (DiskANN,
   ainda em preview no SQL Server 2025) so faria sentido em outra escala.
   ============================================================================= */

USE ClimaRMBH;
GO

IF OBJECT_ID(N'dbo.vet_analogos', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.vet_analogos
    (
        municipio_id       INT           NOT NULL,
        data_id_prevista   INT           NOT NULL,   -- dia previsto (AAAAMMDD)
        posicao            TINYINT       NOT NULL,   -- 1 = o mais parecido
        data_id_analogo    INT           NOT NULL,   -- dia do historico
        distancia          FLOAT         NOT NULL,   -- euclidiana nos z-scores
        antecedencia_dias  TINYINT       NOT NULL,   -- 0 = hoje ... 6
        dt_calculo         DATETIME2(3)  NOT NULL
            CONSTRAINT DF_vet_analogos_dt DEFAULT (SYSDATETIME()),
        CONSTRAINT PK_vet_analogos PRIMARY KEY CLUSTERED (municipio_id, data_id_prevista, posicao),
        CONSTRAINT FK_van_municipio FOREIGN KEY (municipio_id)     REFERENCES dbo.dim_municipio (municipio_id),
        CONSTRAINT FK_van_prevista  FOREIGN KEY (data_id_prevista) REFERENCES dbo.dim_data (data_id),
        CONSTRAINT FK_van_analogo   FOREIGN KEY (data_id_analogo)  REFERENCES dbo.dim_data (data_id)
    );
END
GO

CREATE OR ALTER PROCEDURE dbo.calcular_dias_analogos
    @dias_a_frente TINYINT = 7,
    @analogos      TINYINT = 10
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @hoje          DATE = CAST(GETDATE() AS DATE);
    DECLARE @primeiro_dia  INT  = CONVERT(INT, CONVERT(CHAR(8), @hoje, 112));
    DECLARE @ultimo_dia    INT  = CONVERT(INT, CONVERT(CHAR(8), DATEADD(DAY, @dias_a_frente - 1, @hoje), 112));
    DECLARE @limite_hist   INT  = CONVERT(INT, CONVERT(CHAR(8), DATEADD(DAY, -30, @hoje), 112));

    -- 1) vetor de cada dia previsto, com a MESMA regua do historico
    CREATE TABLE #previsto
    (
        municipio_id INT       NOT NULL,
        data_id      INT       NOT NULL,
        vetor        VECTOR(6) NOT NULL,
        PRIMARY KEY (municipio_id, data_id)
    );

    INSERT INTO #previsto (municipio_id, data_id, vetor)
    SELECT
        f.municipio_id,
        f.data_id,
        CAST(JSON_ARRAY(
            (f.temperatura_2m_max          - r.media_temp_max)        / r.desvio_temp_max,
            (f.temperatura_2m_min          - r.media_temp_min)        / r.desvio_temp_min,
            (LOG(1 + f.precipitacao_total) - r.media_log_chuva)       / r.desvio_log_chuva,
            (LOG(1 + f.horas_precipitacao) - r.media_log_horas_chuva) / r.desvio_log_horas_chuva,
            (f.velocidade_vento_10m_max    - r.media_vento_max)       / r.desvio_vento_max,
            (f.radiacao_ondas_curtas_total - r.media_radiacao)        / r.desvio_radiacao
        ) AS VECTOR(6))
    FROM dbo.fact_clima_atual_dia f
    CROSS JOIN dbo.vet_regua r
    WHERE f.data_id BETWEEN @primeiro_dia AND @ultimo_dia
      -- JSON_ARRAY descarta NULL (viraria array de 5 e o CAST falharia)
      AND f.temperatura_2m_max          IS NOT NULL
      AND f.temperatura_2m_min          IS NOT NULL
      AND f.precipitacao_total          IS NOT NULL
      AND f.horas_precipitacao          IS NOT NULL
      AND f.velocidade_vento_10m_max    IS NOT NULL
      AND f.radiacao_ondas_curtas_total IS NOT NULL;

    -- 2) distancia de cada dia previsto a cada dia do historico do mesmo municipio
    WITH candidatos AS (
        SELECT
            p.municipio_id,
            p.data_id                                          AS data_id_prevista,
            h.data_id                                          AS data_id_analogo,
            VECTOR_DISTANCE('euclidean', h.vetor, p.vetor)     AS distancia,
            ROW_NUMBER() OVER (PARTITION BY p.municipio_id, p.data_id, h.data_id / 10000   -- ano do analogo
                               ORDER BY VECTOR_DISTANCE('euclidean', h.vetor, p.vetor)) AS ordem_no_ano
        FROM #previsto p
        JOIN dbo.vet_historico_dia h
          ON h.municipio_id = p.municipio_id
        WHERE h.data_id < @limite_hist
    ),
    -- 3) o melhor de cada ano, e depois os N melhores entre eles
    ranqueado AS (
        SELECT municipio_id, data_id_prevista, data_id_analogo, distancia,
               ROW_NUMBER() OVER (PARTITION BY municipio_id, data_id_prevista ORDER BY distancia) AS posicao
        FROM candidatos
        WHERE ordem_no_ano = 1
    )
    SELECT municipio_id, data_id_prevista, posicao, data_id_analogo, distancia
    INTO #resultado
    FROM ranqueado
    WHERE posicao <= @analogos;

    -- 4) troca o calculo anterior pelo novo, de uma vez
    BEGIN TRANSACTION;

    DELETE FROM dbo.vet_analogos;   -- DELETE e nao TRUNCATE: TRUNCATE exige ALTER na tabela

    INSERT INTO dbo.vet_analogos
        (municipio_id, data_id_prevista, posicao, data_id_analogo, distancia, antecedencia_dias)
    SELECT municipio_id, data_id_prevista, posicao, data_id_analogo, distancia,
           DATEDIFF(DAY, @hoje, CONVERT(DATE, CONVERT(CHAR(8), data_id_prevista), 112))
    FROM #resultado;

    DECLARE @gravados INT = @@ROWCOUNT;

    COMMIT TRANSACTION;

    -- aparece no log da tarefa: 420 = 6 municipios x 7 dias x 10 analogos
    SELECT @gravados AS analogos_gravados;
END
GO

/* -----------------------------------------------------------------------------
   Pagina 4 do painel: cada analogo com o tempo que fez nele e o que veio
   nos 3 dias seguintes - a resposta do metodo dos analogos.
   data_id = dia PREVISTO (liga com bi.vw_data e com bi.vw_previsao_dia);
   o dia analogo vem como colunas proprias, sem relacao no modelo.
   ----------------------------------------------------------------------------- */
CREATE OR ALTER VIEW bi.vw_dias_analogos
AS
SELECT
    va.municipio_id,
    va.data_id_prevista                         AS data_id,
    va.antecedencia_dias,
    va.posicao,
    CAST(va.distancia AS DECIMAL(6,3))          AS distancia,
    da.data                                     AS data_analogo,
    da.ano                                      AS ano_analogo,
    da.estacao                                  AS estacao_analogo,
    -- o tempo que fez no dia analogo
    h.temperatura_2m_max,
    h.temperatura_2m_min,
    h.precipitacao_total,
    h.velocidade_vento_10m_max,
    h.radiacao_ondas_curtas_total,
    -- o que aconteceu depois
    seguintes.chuva_3_dias,
    seguintes.dias_com_chuva_3_dias,
    seguintes.temp_max_media_3_dias,
    va.dt_calculo
FROM dbo.vet_analogos va
JOIN dbo.dim_data da
  ON da.data_id = va.data_id_analogo
JOIN dbo.fact_clima_historico_dia h
  ON h.municipio_id = va.municipio_id
 AND h.data_id      = va.data_id_analogo
OUTER APPLY (
    SELECT SUM(hs.precipitacao_total)                                    AS chuva_3_dias,
           SUM(CASE WHEN hs.precipitacao_total >= 1 THEN 1 ELSE 0 END)   AS dias_com_chuva_3_dias,
           CAST(AVG(hs.temperatura_2m_max) AS DECIMAL(5,2))              AS temp_max_media_3_dias
    FROM dbo.fact_clima_historico_dia hs
    JOIN dbo.dim_data ds ON ds.data_id = hs.data_id
    WHERE hs.municipio_id = va.municipio_id
      AND ds.data BETWEEN DATEADD(DAY, 1, da.data) AND DATEADD(DAY, 3, da.data)
) seguintes;
GO

/* -----------------------------------------------------------------------------
   Permissao para a DAG: um login so para os vetores.
   O LOGIN e criado a mao, com a senha do Bitwarden (nunca neste arquivo):
     CREATE LOGIN svc_airflow_vetor WITH PASSWORD = '<SENHA>', CHECK_POLICY = ON;
   So EXECUTE nas duas procedures: por encadeamento de propriedade (procedure e
   tabelas com o mesmo dono), o login le e grava as tabelas so atraves delas,
   sem permissao direta em nenhuma.
   ----------------------------------------------------------------------------- */
IF SUSER_ID(N'svc_airflow_vetor') IS NOT NULL
BEGIN
    IF USER_ID(N'svc_airflow_vetor') IS NULL
        CREATE USER svc_airflow_vetor FOR LOGIN svc_airflow_vetor;

    GRANT EXECUTE ON dbo.atualizar_vetores_historico TO svc_airflow_vetor;
    GRANT EXECUTE ON dbo.calcular_dias_analogos      TO svc_airflow_vetor;
END
ELSE
    PRINT 'Login svc_airflow_vetor ainda nao existe: crie e rode este script de novo.';
GO
