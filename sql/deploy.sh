#!/usr/bin/env bash
# =============================================================================
# deploy.sh - aplica todos os scripts do schema, na ordem numerica, no SQL Server.
#
# Uso (na VPS, dentro da pasta sql/):
#   export SA_PASSWORD='...'      # nunca deixe a senha em arquivo versionado
#   ./deploy.sh
#
# -C       : confia no certificado autoassinado do servidor
# -f 65001 : arquivos em UTF-8 (acentos de "Sabara", "Marco" etc.)
# -b       : aborta no primeiro erro, em vez de seguir com o schema pela metade
# =============================================================================
set -euo pipefail

: "${SA_PASSWORD:?defina a variavel de ambiente SA_PASSWORD antes de rodar}"
SERVIDOR="${SQL_SERVER:-localhost}"
SQLCMD="${SQLCMD:-/opt/mssql-tools18/bin/sqlcmd}"

for arquivo in $(ls -1 [0-9][0-9]_*.sql | sort); do
    echo ">>> $arquivo"
    "$SQLCMD" -S "$SERVIDOR" -U sa -P "$SA_PASSWORD" -C -b -f 65001 -i "$arquivo"
done

echo
echo "Schema aplicado. Conferindo:"
"$SQLCMD" -S "$SERVIDOR" -U sa -P "$SA_PASSWORD" -C -f 65001 -d ClimaRMBH -Q \
  "SELECT t.name AS tabela, SUM(p.rows) AS linhas
     FROM sys.tables t
     JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
    GROUP BY t.name ORDER BY t.name;"
