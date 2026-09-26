import pendulum
from airflow.sdk import DAG
from airflow.providers.standard.operators.bash import BashOperator

argumentos_padrao = {
    "retries": 2,
    "retry_delay": pendulum.duration(minutes=5),
}

documentacao_dag = """
### Ingestão Incremental de Clima (RMBH)
Coleta contínua de dados da **API Open-Meteo** para 6 municípios.
Busca os últimos 7 dias e 16 dias à frente, atualizando o **SQL Server** via `MERGE` idempotente.
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