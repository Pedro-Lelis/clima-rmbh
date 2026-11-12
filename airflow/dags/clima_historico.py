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
### Carga Histórica de Clima (RMBH)
Busca a ponta do ano corrente da reanálise ERA5 na **API Open-Meteo**.
Roda uma vez ao dia, de madrugada, inserindo os dados de forma idempotente via `MERGE`.
Após a carga, uma checagem de atualidade: o último registro de cada município não pode ser anterior a hoje − 7 dias
(o script busca até hoje − 6, e o dia a mais tolera atraso pontual do ERA5).
"""

with DAG(
    dag_id="clima_historico",
    schedule="20 4 * * *",  # 04:20 de Brasília: longe do backup (03:30) e do incremental (minuto 10)
    start_date=pendulum.datetime(2026, 11, 10, tz="America/Sao_Paulo"),
    catchup=False,
    default_args=argumentos_padrao,
    tags=["clima", "historico"],
    max_active_runs=1,
    doc_md=documentacao_dag,
):

    carregar_historico = BashOperator(
        task_id="carregar_historico",
        bash_command="cd /home/pedro/clima/ingestao && set -a && . ./.env && set +a && ./.venv/bin/python ingestao.py backfill",
    )
    
    checar_atualidade = SQLCheckOperator(
        task_id="checar_atualidade",
        conn_id="clima_sqlserver",
        sql="sql/checar_atualidade.sql",
        hook_params={"driver": "ODBC Driver 18 for SQL Server"},
        retries=0,
    )
    
    carregar_historico >> checar_atualidade