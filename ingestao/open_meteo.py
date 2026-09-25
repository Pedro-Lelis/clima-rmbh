"""Cliente da API Open-Meteo.

Duas particularidades que moldam este módulo:

1. A API aceita várias coordenadas numa única chamada (separadas por vírgula) e
   responde com uma *lista* na mesma ordem em que as coordenadas foram enviadas.
   As lat/lon que voltam são as do ponto de grade, não as que enviamos - por isso
   o casamento com o município é feito por POSIÇÃO, nunca por coordenada.

2. `timezone=America/Sao_Paulo` equivale, na Open-Meteo, a UTC-3 fixo: mesmo em
   2018-11-04 (virada do antigo horário de verão) a série veio com 24 horas.
   Isso é o que permite usar (data, hora) como chave.
"""

from __future__ import annotations

import time
from typing import Any

import requests

URL_ARCHIVE = "https://archive-api.open-meteo.com/v1/archive"
URL_FORECAST = "https://api.open-meteo.com/v1/forecast"
FUSO = "America/Sao_Paulo"

# Variáveis pedidas em cada endpoint. Os nomes são idênticos aos das colunas
# das tabelas fato - o de-para é o próprio nome.
HORA_ARCHIVE = [
    "temperature_2m", "relative_humidity_2m", "dew_point_2m", "apparent_temperature",
    "precipitation", "rain", "snowfall", "weather_code", "pressure_msl",
    "surface_pressure", "cloud_cover", "cloud_cover_low", "cloud_cover_mid",
    "cloud_cover_high", "et0_fao_evapotranspiration", "vapour_pressure_deficit",
    "wind_speed_10m", "wind_speed_100m", "wind_direction_10m", "wind_direction_100m",
    "wind_gusts_10m", "soil_temperature_0_to_7cm", "soil_temperature_7_to_28cm",
    "soil_temperature_28_to_100cm", "soil_temperature_100_to_255cm",
    "soil_moisture_0_to_7cm", "soil_moisture_7_to_28cm", "soil_moisture_28_to_100cm",
    "soil_moisture_100_to_255cm", "shortwave_radiation", "direct_radiation",
    "diffuse_radiation", "direct_normal_irradiance", "terrestrial_radiation",
    "sunshine_duration", "is_day",
]

DIA_ARCHIVE = [
    "weather_code", "temperature_2m_max", "temperature_2m_min", "temperature_2m_mean",
    "apparent_temperature_max", "apparent_temperature_min", "apparent_temperature_mean",
    "sunrise", "sunset", "daylight_duration", "sunshine_duration", "precipitation_sum",
    "rain_sum", "snowfall_sum", "precipitation_hours", "wind_speed_10m_max",
    "wind_gusts_10m_max", "wind_direction_10m_dominant", "shortwave_radiation_sum",
    "et0_fao_evapotranspiration",
]

HORA_FORECAST = HORA_ARCHIVE[:] + [
    "showers", "precipitation_probability", "visibility", "uv_index", "evapotranspiration",
    "soil_temperature_0cm", "soil_temperature_6cm", "soil_temperature_18cm",
    "soil_temperature_54cm", "soil_moisture_0_to_1cm", "soil_moisture_1_to_3cm",
    "soil_moisture_3_to_9cm", "soil_moisture_9_to_27cm", "soil_moisture_27_to_81cm",
]
# o modelo de previsão usa outras profundidades de solo que o ERA5
for _v in ["soil_temperature_0_to_7cm", "soil_temperature_7_to_28cm",
           "soil_temperature_28_to_100cm", "soil_temperature_100_to_255cm",
           "soil_moisture_0_to_7cm", "soil_moisture_7_to_28cm",
           "soil_moisture_28_to_100cm", "soil_moisture_100_to_255cm"]:
    HORA_FORECAST.remove(_v)

DIA_FORECAST = DIA_ARCHIVE[:] + ["uv_index_max", "showers_sum", "precipitation_probability_max"]


class ErroOpenMeteo(RuntimeError):
    pass


class LimiteApiAtingido(ErroOpenMeteo):
    """Cota da API esgotada (HTTP 429).

    Nao e falha: e o teto de uso do plano gratuito. Uma requisicao vale 1
    chamada como base, mas acima de 10 variaveis ou 2 semanas ela conta como
    varias - nossa chamada de 1 ano x 6 municipios x ~56 variaveis vale ~876.
    Com 5.000/hora e 10.000/dia, cabem ~11 anos de backfill por dia.

    Por isso o backfill nao insiste quando recebe 429: ele para limpo e o
    controle em etl_backfill_ano faz a proxima execucao continuar de onde parou.
    """


def _chamar(url: str, params: dict[str, Any], tentativas: int = 4,
            espera_inicial: float = 5.0, timeout: int = 180) -> list[dict]:
    """Chama a API com backoff exponencial.

    Três desfechos diferentes, de propósito:
      - 5xx e falha de rede: temporários, espera e tenta de novo;
      - 429: cota. Espera 65s uma vez (resolve o limite POR MINUTO) e, se
        persistir, levanta LimiteApiAtingido - o limite é por hora ou por dia e
        insistir só queima tempo;
      - demais 4xx: erro de parâmetro, falha na hora sem repetir.
    """
    ja_esperou_cota = False
    espera = espera_inicial
    ultimo_erro = ""
    for tentativa in range(1, tentativas + 1):
        try:
            resp = requests.get(url, params=params, timeout=timeout)
        except requests.RequestException as exc:
            ultimo_erro = f"falha de rede: {exc}"
        else:
            if resp.status_code == 200:
                dados = resp.json()
                return dados if isinstance(dados, list) else [dados]
            if resp.status_code == 429:
                if ja_esperou_cota or tentativa == tentativas:
                    raise LimiteApiAtingido(
                        "cota da Open-Meteo esgotada (limite por hora ou por dia)")
                ja_esperou_cota = True
                print("    ! cota momentanea atingida (429) - aguardando 65s", flush=True)
                time.sleep(65)
                continue
            if resp.status_code < 500:
                motivo = ""
                try:
                    motivo = resp.json().get("reason", "")
                except Exception:
                    motivo = resp.text[:300]
                raise ErroOpenMeteo(f"HTTP {resp.status_code}: {motivo}")
            ultimo_erro = f"HTTP {resp.status_code}"

        if tentativa < tentativas:
            print(f"    ! {ultimo_erro} - nova tentativa em {espera:.0f}s "
                  f"({tentativa}/{tentativas - 1})", flush=True)
            time.sleep(espera)
            espera *= 3
    raise ErroOpenMeteo(f"desisti após {tentativas} tentativas ({ultimo_erro})")


def buscar_historico(latitudes: list[float], longitudes: list[float],
                     data_inicio: str, data_fim: str) -> list[dict]:
    """Bloco histórico (/v1/archive), reanálise ERA5."""
    return _chamar(URL_ARCHIVE, {
        "latitude": ",".join(str(v) for v in latitudes),
        "longitude": ",".join(str(v) for v in longitudes),
        "start_date": data_inicio,
        "end_date": data_fim,
        "hourly": ",".join(HORA_ARCHIVE),
        "daily": ",".join(DIA_ARCHIVE),
        "timezone": FUSO,
    })


def buscar_atual(latitudes: list[float], longitudes: list[float],
                 dias_passados: int = 7, dias_previsao: int = 16) -> list[dict]:
    """Bloco atual/previsão (/v1/forecast).

    `past_days` traz de volta os dias recentes já realizados: é o que fecha a
    lacuna do ERA5, que sai com alguns dias de atraso.
    """
    return _chamar(URL_FORECAST, {
        "latitude": ",".join(str(v) for v in latitudes),
        "longitude": ",".join(str(v) for v in longitudes),
        "hourly": ",".join(HORA_FORECAST),
        "daily": ",".join(DIA_FORECAST),
        "timezone": FUSO,
        "past_days": dias_passados,
        "forecast_days": dias_previsao,
    })
