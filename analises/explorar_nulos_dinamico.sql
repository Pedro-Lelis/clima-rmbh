/* =============================================================================
   explorar_nulos_dinamico.sql  -  Nulos por coluna na ultima carga incremental
   Consulta exploratoria (nao e checagem da DAG): monta um SELECT por coluna a
   partir do catalogo (INFORMATION_SCHEMA.COLUMNS) e executa tudo de uma vez
   com sp_executesql. Lista so as colunas que tem algum nulo.

   Achado de 07/11/2026: so as 9 colunas de solo vieram nulas, 26 horas por
   municipio, nos dois ultimos dias do horizonte de 16 dias - o modelo de
   previsao nao calcula solo ate o fim. Nulo legitimo.

   Pontos para aprofundar depois (SQL dinamico):
   - LEFT(@sql, LEN(@sql) - 10) funciona porque LEN ignora o espaco do fim:
     'UNION ALL ' tem 10 caracteres, mas o corte remove ' UNION ALL' inteiro.
   - Aspa simples dentro da string vira '' (ver ''incremental'').
   - Le a tabela uma vez por coluna; o CROSS APPLY (VALUES ...) le uma vez so.
   - SELECT @sql = @sql + ... nao garante ordem; STRING_AGG ... WITHIN GROUP
     (ORDER BY ORDINAL_POSITION) e a forma documentada.
   - QUOTENAME tambem no schema e na tabela, nao so na coluna.
   - Num SQLCheckOperator, comecar com SET NOCOUNT ON.
   ============================================================================= */

DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql + 'SELECT ''' + COLUMN_NAME + ''' AS Coluna, COUNT(*) as QtdNulos FROM ' + TABLE_SCHEMA + '.' + TABLE_NAME + ' WHERE dbo.fact_clima_atual_hora.dt_carga >= (select top 1 dt_inicio from dbo.etl_execucao
																 where modo = ''incremental''
																 order by dt_inicio desc) and' + QUOTENAME(COLUMN_NAME) + ' IS NULL HAVING COUNT(*) > 0 UNION ALL '
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'fact_clima_atual_hora' AND TABLE_SCHEMA = 'dbo';

IF LEN(@sql) > 0
BEGIN
    SET @sql = LEFT(@sql, LEN(@sql) - 10);
    EXEC sp_executesql @sql;
END
