/* =============================================================================
   02_dim_municipio.sql  -  Dimensao Municipio (+ carga inicial)
   Grao: 1 linha por municipio monitorado.
   ============================================================================= */

USE ClimaRMBH;
GO

IF OBJECT_ID(N'dbo.dim_municipio', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.dim_municipio
    (
        municipio_id   INT            IDENTITY(1,1) NOT NULL,   -- surrogate key
        codigo_ibge    INT            NOT NULL,                 -- chave natural (7 digitos)
        nome           NVARCHAR(60)   NOT NULL,
        uf             CHAR(2)        NOT NULL,
        latitude       DECIMAL(9,6)   NOT NULL,                 -- sede municipal
        longitude      DECIMAL(9,6)   NOT NULL,
        elevacao_m     DECIMAL(6,1)   NULL,                     -- altitude informada pela API
        ativo          BIT            NOT NULL CONSTRAINT DF_dim_municipio_ativo DEFAULT (1),
        dt_carga       DATETIME2(3)   NOT NULL CONSTRAINT DF_dim_municipio_dt_carga DEFAULT (SYSDATETIME()),

        CONSTRAINT PK_dim_municipio        PRIMARY KEY CLUSTERED (municipio_id),
        CONSTRAINT UQ_dim_municipio_ibge   UNIQUE (codigo_ibge),
        CONSTRAINT CK_dim_municipio_lat    CHECK (latitude  BETWEEN -90  AND 90),
        CONSTRAINT CK_dim_municipio_lon    CHECK (longitude BETWEEN -180 AND 180)
    );
END
GO

/* -----------------------------------------------------------------------------
   Carga inicial - escopo da fase 1: Ibirite, BH e 4 vizinhos da RMBH.
   Codigos IBGE conferidos na API de localidades do IBGE.
   Coordenadas e elevacao conferidas na API de geocoding da Open-Meteo
   (mesma familia da API de dados -> reduz divergencia de ponto de grade).
   MERGE = script idempotente: pode rodar de novo sem duplicar.
   ----------------------------------------------------------------------------- */
MERGE dbo.dim_municipio AS destino
USING (VALUES
    (3129806, N'Ibirité',        'MG', -20.021940, -44.058890, 883.0),
    (3106200, N'Belo Horizonte', 'MG', -19.920830, -43.937780, 888.0),
    (3118601, N'Contagem',       'MG', -19.931700, -44.053600, 945.0),
    (3106705, N'Betim',          'MG', -19.967800, -44.198300, 834.0),
    (3144805, N'Nova Lima',      'MG', -19.985600, -43.846700, 744.0),
    (3156700, N'Sabará',         'MG', -19.886390, -43.806670, 737.0)
) AS origem (codigo_ibge, nome, uf, latitude, longitude, elevacao_m)
    ON destino.codigo_ibge = origem.codigo_ibge
WHEN MATCHED THEN
    UPDATE SET destino.nome       = origem.nome,
               destino.uf         = origem.uf,
               destino.latitude   = origem.latitude,
               destino.longitude  = origem.longitude,
               destino.elevacao_m = origem.elevacao_m
WHEN NOT MATCHED BY TARGET THEN
    INSERT (codigo_ibge, nome, uf, latitude, longitude, elevacao_m)
    VALUES (origem.codigo_ibge, origem.nome, origem.uf, origem.latitude, origem.longitude, origem.elevacao_m);
GO

SELECT municipio_id, codigo_ibge, nome, uf, latitude, longitude, elevacao_m, ativo
FROM dbo.dim_municipio
ORDER BY nome;
GO
