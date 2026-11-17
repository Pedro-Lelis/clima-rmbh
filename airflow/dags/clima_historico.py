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
### Carga Histórica de Clima (RMBH)
Busca a ponta do ano corrente da reanálise ERA5 na **API Open-Meteo**.
Roda uma vez ao dia, de madrugada, inserindo os dados de forma idempotente via `MERGE`.
Após a carga, uma checagem de atualidade: o último registro de cada município não pode ser anterior a hoje − 7 dias
(o script busca até hoje − 6, e o dia a mais tolera atraso pontual do ERA5).
Em paralelo, atualiza os vetores do histórico e calcula os **dias análogos** dos próximos 7 dias previstos
(`VECTOR_DISTANCE` no SQL Server 2025).
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
    
    # vetores dos dias novos (e dos recarregados) antes de buscar os analogos
    atualizar_vetores = SQLExecuteQueryOperator(
        task_id="atualizar_vetores",
        conn_id="clima_sqlserver_vetor",
        sql="EXEC dbo.atualizar_vetores_historico;",
        hook_params={"driver": "ODBC Driver 18 for SQL Server"},
        autocommit=True,
        show_return_value_in_logs=True,  # o SELECT final da procedure aparece no log
    )

    # usa a previsao da carga incremental das 04:10
    calcular_analogos = SQLExecuteQueryOperator(
        task_id="calcular_analogos",
        conn_id="clima_sqlserver_vetor",
        sql="EXEC dbo.calcular_dias_analogos;",
        hook_params={"driver": "ODBC Driver 18 for SQL Server"},
        autocommit=True,
        show_return_value_in_logs=True,  # o SELECT final da procedure aparece no log
    )

    carregar_historico >> checar_atualidade
    carregar_historico >> atualizar_vetores >> calcular_analogos