import pendulum
from airflow.sdk import DAG
from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.common.sql.operators.sql import SQLCheckOperator
from comum.alertas import avisar_falha

argumentos_padrao = {
    "retries": 2,
    "retry_delay": pendulum.duration(minutes=5),
    "on_failure_callback": avisar_falha,
}

documentacao_dag = """
### Ingestão Incremental de Clima (RMBH)
Coleta contínua de dados da **API Open-Meteo** para 6 municípios.
Busca os últimos 7 dias e 16 dias à frente, atualizando o **SQL Server** via `MERGE` idempotente.
Após a carga, confere se vieram as 552 horas (23 dias × 24) de cada município.
"""

with DAG(
    dag_id="clima_incremental",
    schedule="10 * * * *",
    start_date=pendulum.datetime(2026, 9, 26, tz="America/Sao_Paulo"),
    catchup=False,
    default_args=argumentos_padrao,
    tags=["clima"],
    max_active_runs=1,
    doc_md=documentacao_dag,
):

    carregar = BashOperator(
        task_id="carregar_incremental",
        bash_command="cd /home/pedro/clima/ingestao && set -a && . ./.env && set +a && ./.venv/bin/python ingestao.py incremental",
    )
    
    checar_completude = SQLCheckOperator(
        task_id="checar_completude",
        conn_id="clima_sqlserver",
        sql="sql/checar_completude.sql",
        hook_params={"driver": "ODBC Driver 18 for SQL Server"},
        retries=0,
    )
    
    checar_nulos = SQLCheckOperator(
        task_id="checar_nulos",
        conn_id="clima_sqlserver",
        sql="sql/checar_nulos.sql",
        hook_params={"driver": "ODBC Driver 18 for SQL Server"},
        retries=0,
    )
    
    carregar >> [checar_completude, checar_nulos]