import pendulum
from airflow.sdk import DAG
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.providers.standard.operators.bash import BashOperator
from comum.alertas import avisar_falha

def esvaziar_mensagens_sql(cursor):
    """
    Consome as mensagens de progresso do SQL Server (ex: Processed N pages)
    para evitar que o pyodbc feche a conexão antes do fim do backup.
    """
    if cursor.description is not None:
        cursor.fetchall()
    while cursor.nextset():
        pass
    

documentacao_dag = """
### Manutenção de Backup (ClimaRMBH)
Faz o backup diário do banco de dados e valida a integridade (CHECKSUM). 
Em seguida, sobe para o Google Drive e limpa os arquivos antigos da VPS e da nuvem.
"""

argumentos_padrao = {
    "on_failure_callback": avisar_falha,
}

with DAG(
    dag_id="manutencao_backup",
    schedule="30 3 * * *",
    start_date=pendulum.datetime(2026, 10, 25, tz="America/Sao_Paulo"),
    catchup=False,
    default_args=argumentos_padrao,
    max_active_runs=1,
    tags=["manutencao", "sqlserver"],
    doc_md=documentacao_dag,
):

    gerar_backup = SQLExecuteQueryOperator(
        task_id="gerar_backup",
        conn_id="clima_sqlserver_backup",
        sql="BACKUP DATABASE ClimaRMBH TO DISK = '/var/opt/mssql/backup/ClimaRMBH_{{ ds_nodash }}.bak' WITH INIT, COMPRESSION, CHECKSUM;",
        autocommit=True,
        hook_params={"driver": "ODBC Driver 18 for SQL Server"},
        handler=esvaziar_mensagens_sql,
    )
    
    validar_backup = SQLExecuteQueryOperator(
        task_id="validar_backup",
        conn_id="clima_sqlserver_backup",
        sql="RESTORE VERIFYONLY FROM DISK = '/var/opt/mssql/backup/ClimaRMBH_{{ ds_nodash }}.bak' WITH CHECKSUM;",
        autocommit=True,
        hook_params={"driver": "ODBC Driver 18 for SQL Server"},
        handler=esvaziar_mensagens_sql,
    )
    
    enviar_drive = BashOperator(
        task_id="enviar_drive",
        bash_command="rclone copy /var/opt/mssql/backup/ClimaRMBH_{{ ds_nodash }}.bak clima_drive:backups-clima",
        retries=3,
        retry_delay=pendulum.duration(minutes=5),
    )
    
    limpar_antigos = BashOperator(
        task_id="limpar_antigos",
        bash_command='find /var/opt/mssql/backup/ -name "ClimaRMBH_*.bak" -type f -mtime +1 -delete && rclone delete clima_drive:backups-clima --min-age 7d --include "ClimaRMBH_*.bak"',
    )
    
    gerar_backup >> validar_backup >> enviar_drive >> limpar_antigos