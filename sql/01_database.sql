/* =============================================================================
   01_database.sql  -  Criacao do banco
   Projeto: Historico de Clima Dinamico (RMBH)
   SGBD...: SQL Server 2025 Developer (VPS Contabo, Ubuntu)
   Executar conectado ao master, com o usuario sa.
   ============================================================================= */

USE master;
GO

IF DB_ID(N'ClimaRMBH') IS NULL
BEGIN
    CREATE DATABASE ClimaRMBH;
END
GO

/* Recovery SIMPLE: e um banco analitico, reconstruivel a partir da API.
   Nao precisamos de recuperacao point-in-time e evitamos o log transacional
   crescer sem controle durante o backfill historico (carga em massa). */
ALTER DATABASE ClimaRMBH SET RECOVERY SIMPLE;
GO

/* Portugues do Brasil para ordenacao/comparacao de texto com acento,
   case-insensitive e accent-insensitive: 'Sabara' = 'Sabará'. */
ALTER DATABASE ClimaRMBH COLLATE Latin1_General_CI_AI;
GO

USE ClimaRMBH;
GO

PRINT 'Banco ClimaRMBH pronto.';
GO
