"""De-para entre o nome da variavel na Open-Meteo e o nome da coluna no banco.

Este arquivo e a FONTE UNICA da traducao: e ele que alimenta tanto a ingestao
quanto o script que renomeou as colunas (sql/09_padroniza_nomes_pt.sql).

Enquanto as colunas tinham o nome da API, o casamento era automatico e nao
existia lista para manter. Com os nomes em portugues, esse de-para passa a ser
obrigatorio - e toda variavel nova pedida a API precisa entrar aqui junto com a
coluna correspondente, senao ela e silenciosamente ignorada na carga.
`verificar_mapeamento.py` existe justamente para acusar esse esquecimento.

Sem acento de proposito: nome de coluna com acento e valido no SQL Server, mas
vira dor de cabeca em script, driver e exportacao. O rotulo bonito, com acento,
e trabalho da camada de apresentacao (Power BI).
"""

from __future__ import annotations

# ---------------------------------------------------------------------------
# Variaveis horarias
# ---------------------------------------------------------------------------
TRADUCAO: dict[str, str] = {
    # temperatura e umidade
    "temperature_2m": "temperatura_2m",
    "relative_humidity_2m": "umidade_relativa_2m",
    "dew_point_2m": "ponto_orvalho_2m",
    "apparent_temperature": "sensacao_termica",
    "vapour_pressure_deficit": "deficit_pressao_vapor",

    # precipitacao
    "precipitation": "precipitacao",
    "rain": "chuva",
    "showers": "pancadas_chuva",
    "snowfall": "neve",
    "precipitation_probability": "probabilidade_precipitacao",

    # condicao do tempo
    "weather_code": "codigo_tempo",
    "is_day": "eh_dia",
    "visibility": "visibilidade",
    "uv_index": "indice_uv",

    # pressao e nuvens
    "pressure_msl": "pressao_nivel_mar",
    "surface_pressure": "pressao_superficie",
    "cloud_cover": "cobertura_nuvens",
    "cloud_cover_low": "cobertura_nuvens_baixa",
    "cloud_cover_mid": "cobertura_nuvens_media",
    "cloud_cover_high": "cobertura_nuvens_alta",

    # vento
    "wind_speed_10m": "velocidade_vento_10m",
    "wind_speed_100m": "velocidade_vento_100m",
    "wind_direction_10m": "direcao_vento_10m",
    "wind_direction_100m": "direcao_vento_100m",
    "wind_gusts_10m": "rajada_vento_10m",

    # solo - profundidades do ERA5 (historico)
    "soil_temperature_0_to_7cm": "temperatura_solo_0_7cm",
    "soil_temperature_7_to_28cm": "temperatura_solo_7_28cm",
    "soil_temperature_28_to_100cm": "temperatura_solo_28_100cm",
    "soil_temperature_100_to_255cm": "temperatura_solo_100_255cm",
    "soil_moisture_0_to_7cm": "umidade_solo_0_7cm",
    "soil_moisture_7_to_28cm": "umidade_solo_7_28cm",
    "soil_moisture_28_to_100cm": "umidade_solo_28_100cm",
    "soil_moisture_100_to_255cm": "umidade_solo_100_255cm",

    # solo - profundidades do modelo de previsao (atual)
    "soil_temperature_0cm": "temperatura_solo_0cm",
    "soil_temperature_6cm": "temperatura_solo_6cm",
    "soil_temperature_18cm": "temperatura_solo_18cm",
    "soil_temperature_54cm": "temperatura_solo_54cm",
    "soil_moisture_0_to_1cm": "umidade_solo_0_1cm",
    "soil_moisture_1_to_3cm": "umidade_solo_1_3cm",
    "soil_moisture_3_to_9cm": "umidade_solo_3_9cm",
    "soil_moisture_9_to_27cm": "umidade_solo_9_27cm",
    "soil_moisture_27_to_81cm": "umidade_solo_27_81cm",

    # radiacao solar
    "shortwave_radiation": "radiacao_ondas_curtas",
    "direct_radiation": "radiacao_direta",
    "diffuse_radiation": "radiacao_difusa",
    "direct_normal_irradiance": "irradiancia_normal_direta",
    "terrestrial_radiation": "radiacao_terrestre",
    "sunshine_duration": "duracao_insolacao",

    # agua
    "evapotranspiration": "evapotranspiracao",
    "et0_fao_evapotranspiration": "evapotranspiracao_et0",

    # -----------------------------------------------------------------------
    # Variaveis diarias
    # -----------------------------------------------------------------------
    "temperature_2m_max": "temperatura_2m_max",
    "temperature_2m_min": "temperatura_2m_min",
    "temperature_2m_mean": "temperatura_2m_media",
    "apparent_temperature_max": "sensacao_termica_max",
    "apparent_temperature_min": "sensacao_termica_min",
    "apparent_temperature_mean": "sensacao_termica_media",

    "sunrise": "nascer_sol",
    "sunset": "por_sol",
    "daylight_duration": "duracao_dia_claro",
    "uv_index_max": "indice_uv_max",

    "precipitation_sum": "precipitacao_total",
    "rain_sum": "chuva_total",
    "showers_sum": "pancadas_chuva_total",
    "snowfall_sum": "neve_total",
    "precipitation_hours": "horas_precipitacao",
    "precipitation_probability_max": "probabilidade_precipitacao_max",

    "wind_speed_10m_max": "velocidade_vento_10m_max",
    "wind_gusts_10m_max": "rajada_vento_10m_max",
    "wind_direction_10m_dominant": "direcao_vento_10m_dominante",

    "shortwave_radiation_sum": "radiacao_ondas_curtas_total",
}

# Colunas que nao vem da API: chaves, marcadores e auditoria.
COLUNAS_TECNICAS = {
    "municipio_id", "data_id", "hora", "data_hora_local", "eh_previsao", "dt_carga",
}


def coluna_de(variavel: str) -> str | None:
    """Nome da coluna correspondente a uma variavel da API (None se nao mapeada)."""
    return TRADUCAO.get(variavel)
