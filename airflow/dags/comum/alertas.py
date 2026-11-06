import logging
import time
import requests
from airflow.sdk import Variable

log = logging.getLogger(__name__)

def avisar_falha(context):
    bot_token = Variable.get("telegram_token")
    chat_id = Variable.get("telegram_chat_id")
    
    ti = context["ti"]
    mensagem = f"⚠️ Falha no Airflow!\nDAG: {ti.dag_id}\nTarefa: {ti.task_id}\nRun ID: {ti.run_id}"
    
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    payload = {
        "chat_id": chat_id,
        "text": mensagem
    }
    
    for tentativa in range(2):
        try:
            resposta = requests.post(url, json=payload, timeout=10)
            
            if resposta.ok:
                return 
            else:
                log.error(f"Telegram recusou o alerta. Status: {resposta.status_code}")
                
        except Exception as e:
            log.error(f"Erro de rede ao contatar o Telegram: {type(e).__name__}")
        
        time.sleep(5)