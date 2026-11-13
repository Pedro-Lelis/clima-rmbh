import pendulum
from airflow.sdk import DAG
from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.common.sql.operators.sql import SQLCheckOperator, SQLExecuteQueryOperator
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
Após a carga, três checagens em paralelo: completude (552 horas por município), nenhuma coluna de medida 100% nula, e valores dentro dos limites físicos e coerentes entre si (coerência só até 3 dias à frente: a previsão de longo prazo pode vir inconsistente na própria fonte).
Com as três verdes, grava a foto diária da previsão (`fact_previsao_snapshot_dia`), uma vez por dia, para medir o erro da previsão por antecedência.
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
    
    checar_faixas = SQLCheckOperator(
        task_id="checar_faixas",
        conn_id="clima_sqlserver",
        sql="sql/checar_faixas.sql",
        hook_params={"driver": "ODBC Driver 18 for SQL Server"},
        retries=0,
    )
    
    # foto diaria da previsao, so de carga validada; grava na primeira hora do dia, depois nao faz nada
    gravar_snapshot = SQLExecuteQueryOperator(
        task_id="gravar_snapshot_previsao",
        conn_id="clima_sqlserver_snapshot",
        sql="sql/gravar_snapshot_previsao.sql",
        hook_params={"driver": "ODBC Driver 18 for SQL Server"},
        autocommit=True,
    )

    carregar >> [checar_completude, checar_nulos, checar_faixas] >> gravar_snapshot