/* =============================================================================
   03_dim_data.sql  -  Dimensao Data (+ carga)
   Grao: 1 linha por dia.
   Chave: data_id = AAAAMMDD (smart key) - inteiro pequeno, legivel e
          naturalmente ordenado; e o padrao classico de dimensao de data em DW.
   Periodo carregado: 1940-01-01 (inicio da reanalise ERA5) ate 2035-12-31
                      (folga para a janela de previsao). ~35 mil linhas.
   ============================================================================= */

USE ClimaRMBH;
GO

IF OBJECT_ID(N'dbo.dim_data', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.dim_data
    (
        data_id           INT           NOT NULL,        -- AAAAMMDD
        data              DATE          NOT NULL,
        ano               SMALLINT      NOT NULL,
        trimestre         TINYINT       NOT NULL,
        mes               TINYINT       NOT NULL,
        nome_mes          NVARCHAR(12)  NOT NULL,
        nome_mes_abrev    NVARCHAR(3)   NOT NULL,
        ano_mes           INT           NOT NULL,         -- AAAAMM (ordenacao no Power BI)
        ano_mes_nome      NVARCHAR(12)  NOT NULL,         -- 'ago/2026'
        dia               TINYINT       NOT NULL,
        dia_do_ano        SMALLINT      NOT NULL,
        semana_iso        TINYINT       NOT NULL,
        num_dia_semana    TINYINT       NOT NULL,         -- 1 = domingo ... 7 = sabado
        nome_dia_semana   NVARCHAR(15)  NOT NULL,
        eh_fim_de_semana  BIT           NOT NULL,
        estacao           NVARCHAR(10)  NOT NULL,         -- hemisferio SUL
        primeiro_dia_mes  DATE          NOT NULL,
        ultimo_dia_mes    DATE          NOT NULL,

        CONSTRAINT PK_dim_data      PRIMARY KEY CLUSTERED (data_id),
        CONSTRAINT UQ_dim_data_data UNIQUE (data)
    );
END
GO

/* -----------------------------------------------------------------------------
   Carga. Idempotente: so insere os dias que ainda nao existem.
   Gerador de numeros por CROSS JOIN (tally) - mais rapido que CTE recursiva
   e sem depender de MAXRECURSION.
   Nomes de mes/dia sao escritos com CASE em vez de DATENAME: assim o resultado
   nao depende do idioma do login que executar o script.
   ----------------------------------------------------------------------------- */
DECLARE @data_inicio DATE = '1940-01-01';
DECLARE @data_fim    DATE = '2035-12-31';

;WITH L0 AS (SELECT 1 AS c UNION ALL SELECT 1),
      L1 AS (SELECT 1 AS c FROM L0 a CROSS JOIN L0 b),
      L2 AS (SELECT 1 AS c FROM L1 a CROSS JOIN L1 b),
      L3 AS (SELECT 1 AS c FROM L2 a CROSS JOIN L2 b),
      L4 AS (SELECT 1 AS c FROM L3 a CROSS JOIN L3 b),   -- 65.536 linhas
      numeros AS (SELECT TOP (DATEDIFF(DAY, @data_inicio, @data_fim) + 1)
                         ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
                  FROM L4),
      datas AS (SELECT DATEADD(DAY, n, @data_inicio) AS d FROM numeros)
INSERT INTO dbo.dim_data
(
    data_id, data, ano, trimestre, mes, nome_mes, nome_mes_abrev, ano_mes, ano_mes_nome,
    dia, dia_do_ano, semana_iso, num_dia_semana, nome_dia_semana, eh_fim_de_semana,
    estacao, primeiro_dia_mes, ultimo_dia_mes
)
SELECT
    CONVERT(INT, CONVERT(CHAR(8), d, 112))                                  AS data_id,
    d                                                                       AS data,
    YEAR(d)                                                                 AS ano,
    DATEPART(QUARTER, d)                                                    AS trimestre,
    MONTH(d)                                                                AS mes,
    CASE MONTH(d) WHEN 1 THEN N'Janeiro'  WHEN 2 THEN N'Fevereiro' WHEN 3 THEN N'Março'
                  WHEN 4 THEN N'Abril'    WHEN 5 THEN N'Maio'      WHEN 6 THEN N'Junho'
                  WHEN 7 THEN N'Julho'    WHEN 8 THEN N'Agosto'    WHEN 9 THEN N'Setembro'
                  WHEN 10 THEN N'Outubro' WHEN 11 THEN N'Novembro' ELSE N'Dezembro' END AS nome_mes,
    CASE MONTH(d) WHEN 1 THEN N'jan' WHEN 2 THEN N'fev' WHEN 3 THEN N'mar'
                  WHEN 4 THEN N'abr' WHEN 5 THEN N'mai' WHEN 6 THEN N'jun'
                  WHEN 7 THEN N'jul' WHEN 8 THEN N'ago' WHEN 9 THEN N'set'
                  WHEN 10 THEN N'out' WHEN 11 THEN N'nov' ELSE N'dez' END   AS nome_mes_abrev,
    YEAR(d) * 100 + MONTH(d)                                                AS ano_mes,
    CASE MONTH(d) WHEN 1 THEN N'jan' WHEN 2 THEN N'fev' WHEN 3 THEN N'mar'
                  WHEN 4 THEN N'abr' WHEN 5 THEN N'mai' WHEN 6 THEN N'jun'
                  WHEN 7 THEN N'jul' WHEN 8 THEN N'ago' WHEN 9 THEN N'set'
                  WHEN 10 THEN N'out' WHEN 11 THEN N'nov' ELSE N'dez' END
        + N'/' + CONVERT(NVARCHAR(4), YEAR(d))                              AS ano_mes_nome,
    DAY(d)                                                                  AS dia,
    DATEPART(DAYOFYEAR, d)                                                  AS dia_do_ano,
    DATEPART(ISO_WEEK, d)                                                   AS semana_iso,
    /* 1900-01-01 foi uma segunda-feira; a conta abaixo independe de SET DATEFIRST */
    (DATEDIFF(DAY, '19000101', d) % 7 + 1) % 7 + 1                          AS num_dia_semana,
    CASE DATEDIFF(DAY, '19000101', d) % 7
         WHEN 0 THEN N'Segunda-feira' WHEN 1 THEN N'Terça-feira'
         WHEN 2 THEN N'Quarta-feira'  WHEN 3 THEN N'Quinta-feira'
         WHEN 4 THEN N'Sexta-feira'   WHEN 5 THEN N'Sábado'
         ELSE N'Domingo' END                                                AS nome_dia_semana,
    CASE WHEN DATEDIFF(DAY, '19000101', d) % 7 IN (5, 6) THEN 1 ELSE 0 END  AS eh_fim_de_semana,
    /* Estacoes do hemisferio sul, por data-limite fixa (aproximacao usual) */
    CASE
        WHEN MONTH(d)*100 + DAY(d) >= 1221 OR MONTH(d)*100 + DAY(d) <= 320 THEN N'Verão'
        WHEN MONTH(d)*100 + DAY(d) <= 620  THEN N'Outono'
        WHEN MONTH(d)*100 + DAY(d) <= 922  THEN N'Inverno'
        ELSE N'Primavera'
    END                                                                     AS estacao,
    DATEFROMPARTS(YEAR(d), MONTH(d), 1)                                     AS primeiro_dia_mes,
    EOMONTH(d)                                                              AS ultimo_dia_mes
FROM datas
WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_data dd WHERE dd.data = datas.d);
GO

SELECT COUNT(*) AS linhas, MIN(data) AS de, MAX(data) AS ate FROM dbo.dim_data;
GO
