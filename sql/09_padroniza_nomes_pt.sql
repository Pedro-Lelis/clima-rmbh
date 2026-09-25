/* =============================================================================
   09_padroniza_nomes_pt.sql  -  Colunas de medida para portugues

   Ate aqui as colunas de medida tinham o nome exato da variavel na Open-Meteo
   (temperature_2m, wind_gusts_10m...), enquanto chaves e dimensoes ja estavam
   em portugues. Este script uniformiza tudo em portugues.

   O QUE MUDA FORA DAQUI: com o nome traduzido, a ingestao deixa de casar
   variavel com coluna automaticamente. O de-para passa a viver em
   ingestao/nomes.py, e toda variavel nova pedida a API tem de ser cadastrada
   la - senao a carga a ignora em silencio.

   sp_rename troca apenas o nome: dados, indices, chaves e constraints seguem
   apontando para a mesma coluna, sem reescrita de pagina. E uma operacao de
   metadados, rapida mesmo com milhoes de linhas - mas exige que ninguem esteja
   gravando: PARE O CRON DO BACKFILL ANTES DE RODAR.

   Idempotente: so renomeia o que ainda estiver com o nome antigo.
   ============================================================================= */

USE ClimaRMBH;
GO

SET NOCOUNT ON;
GO


/* ---------- fact_clima_historico_hora (36 colunas) ---------- */
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'temperature_2m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.temperature_2m', N'temperatura_2m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'relative_humidity_2m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.relative_humidity_2m', N'umidade_relativa_2m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'dew_point_2m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.dew_point_2m', N'ponto_orvalho_2m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'apparent_temperature') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.apparent_temperature', N'sensacao_termica', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'vapour_pressure_deficit') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.vapour_pressure_deficit', N'deficit_pressao_vapor', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'precipitation') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.precipitation', N'precipitacao', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'rain') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.rain', N'chuva', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'snowfall') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.snowfall', N'neve', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'weather_code') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.weather_code', N'codigo_tempo', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'is_day') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.is_day', N'eh_dia', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'pressure_msl') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.pressure_msl', N'pressao_nivel_mar', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'surface_pressure') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.surface_pressure', N'pressao_superficie', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'cloud_cover') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.cloud_cover', N'cobertura_nuvens', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'cloud_cover_low') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.cloud_cover_low', N'cobertura_nuvens_baixa', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'cloud_cover_mid') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.cloud_cover_mid', N'cobertura_nuvens_media', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'cloud_cover_high') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.cloud_cover_high', N'cobertura_nuvens_alta', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'wind_speed_10m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.wind_speed_10m', N'velocidade_vento_10m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'wind_speed_100m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.wind_speed_100m', N'velocidade_vento_100m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'wind_direction_10m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.wind_direction_10m', N'direcao_vento_10m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'wind_direction_100m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.wind_direction_100m', N'direcao_vento_100m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'wind_gusts_10m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.wind_gusts_10m', N'rajada_vento_10m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'soil_temperature_0_to_7cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.soil_temperature_0_to_7cm', N'temperatura_solo_0_7cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'soil_temperature_7_to_28cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.soil_temperature_7_to_28cm', N'temperatura_solo_7_28cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'soil_temperature_28_to_100cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.soil_temperature_28_to_100cm', N'temperatura_solo_28_100cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'soil_temperature_100_to_255cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.soil_temperature_100_to_255cm', N'temperatura_solo_100_255cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'soil_moisture_0_to_7cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.soil_moisture_0_to_7cm', N'umidade_solo_0_7cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'soil_moisture_7_to_28cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.soil_moisture_7_to_28cm', N'umidade_solo_7_28cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'soil_moisture_28_to_100cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.soil_moisture_28_to_100cm', N'umidade_solo_28_100cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'soil_moisture_100_to_255cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.soil_moisture_100_to_255cm', N'umidade_solo_100_255cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'shortwave_radiation') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.shortwave_radiation', N'radiacao_ondas_curtas', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'direct_radiation') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.direct_radiation', N'radiacao_direta', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'diffuse_radiation') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.diffuse_radiation', N'radiacao_difusa', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'direct_normal_irradiance') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.direct_normal_irradiance', N'irradiancia_normal_direta', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'terrestrial_radiation') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.terrestrial_radiation', N'radiacao_terrestre', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'sunshine_duration') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.sunshine_duration', N'duracao_insolacao', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_hora', N'et0_fao_evapotranspiration') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_hora.et0_fao_evapotranspiration', N'evapotranspiracao_et0', N'COLUMN';
GO

/* ---------- fact_clima_historico_dia (20 colunas) ---------- */
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'weather_code') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.weather_code', N'codigo_tempo', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'temperature_2m_max') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.temperature_2m_max', N'temperatura_2m_max', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'temperature_2m_min') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.temperature_2m_min', N'temperatura_2m_min', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'temperature_2m_mean') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.temperature_2m_mean', N'temperatura_2m_media', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'apparent_temperature_max') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.apparent_temperature_max', N'sensacao_termica_max', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'apparent_temperature_min') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.apparent_temperature_min', N'sensacao_termica_min', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'apparent_temperature_mean') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.apparent_temperature_mean', N'sensacao_termica_media', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'sunrise') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.sunrise', N'nascer_sol', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'sunset') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.sunset', N'por_sol', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'daylight_duration') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.daylight_duration', N'duracao_dia_claro', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'sunshine_duration') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.sunshine_duration', N'duracao_insolacao', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'precipitation_sum') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.precipitation_sum', N'precipitacao_total', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'rain_sum') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.rain_sum', N'chuva_total', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'snowfall_sum') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.snowfall_sum', N'neve_total', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'precipitation_hours') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.precipitation_hours', N'horas_precipitacao', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'wind_speed_10m_max') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.wind_speed_10m_max', N'velocidade_vento_10m_max', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'wind_gusts_10m_max') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.wind_gusts_10m_max', N'rajada_vento_10m_max', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'wind_direction_10m_dominant') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.wind_direction_10m_dominant', N'direcao_vento_10m_dominante', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'shortwave_radiation_sum') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.shortwave_radiation_sum', N'radiacao_ondas_curtas_total', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_historico_dia', N'et0_fao_evapotranspiration') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_historico_dia.et0_fao_evapotranspiration', N'evapotranspiracao_et0', N'COLUMN';
GO

/* ---------- fact_clima_atual_hora (42 colunas) ---------- */
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'temperature_2m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.temperature_2m', N'temperatura_2m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'relative_humidity_2m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.relative_humidity_2m', N'umidade_relativa_2m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'dew_point_2m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.dew_point_2m', N'ponto_orvalho_2m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'apparent_temperature') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.apparent_temperature', N'sensacao_termica', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'vapour_pressure_deficit') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.vapour_pressure_deficit', N'deficit_pressao_vapor', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'precipitation') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.precipitation', N'precipitacao', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'rain') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.rain', N'chuva', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'showers') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.showers', N'pancadas_chuva', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'snowfall') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.snowfall', N'neve', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'precipitation_probability') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.precipitation_probability', N'probabilidade_precipitacao', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'weather_code') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.weather_code', N'codigo_tempo', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'is_day') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.is_day', N'eh_dia', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'visibility') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.visibility', N'visibilidade', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'uv_index') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.uv_index', N'indice_uv', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'pressure_msl') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.pressure_msl', N'pressao_nivel_mar', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'surface_pressure') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.surface_pressure', N'pressao_superficie', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'cloud_cover') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.cloud_cover', N'cobertura_nuvens', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'cloud_cover_low') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.cloud_cover_low', N'cobertura_nuvens_baixa', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'cloud_cover_mid') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.cloud_cover_mid', N'cobertura_nuvens_media', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'cloud_cover_high') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.cloud_cover_high', N'cobertura_nuvens_alta', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'wind_speed_10m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.wind_speed_10m', N'velocidade_vento_10m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'wind_speed_100m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.wind_speed_100m', N'velocidade_vento_100m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'wind_direction_10m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.wind_direction_10m', N'direcao_vento_10m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'wind_direction_100m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.wind_direction_100m', N'direcao_vento_100m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'wind_gusts_10m') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.wind_gusts_10m', N'rajada_vento_10m', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'soil_temperature_0cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.soil_temperature_0cm', N'temperatura_solo_0cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'soil_temperature_6cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.soil_temperature_6cm', N'temperatura_solo_6cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'soil_temperature_18cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.soil_temperature_18cm', N'temperatura_solo_18cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'soil_temperature_54cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.soil_temperature_54cm', N'temperatura_solo_54cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'soil_moisture_0_to_1cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.soil_moisture_0_to_1cm', N'umidade_solo_0_1cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'soil_moisture_1_to_3cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.soil_moisture_1_to_3cm', N'umidade_solo_1_3cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'soil_moisture_3_to_9cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.soil_moisture_3_to_9cm', N'umidade_solo_3_9cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'soil_moisture_9_to_27cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.soil_moisture_9_to_27cm', N'umidade_solo_9_27cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'soil_moisture_27_to_81cm') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.soil_moisture_27_to_81cm', N'umidade_solo_27_81cm', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'shortwave_radiation') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.shortwave_radiation', N'radiacao_ondas_curtas', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'direct_radiation') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.direct_radiation', N'radiacao_direta', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'diffuse_radiation') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.diffuse_radiation', N'radiacao_difusa', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'direct_normal_irradiance') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.direct_normal_irradiance', N'irradiancia_normal_direta', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'terrestrial_radiation') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.terrestrial_radiation', N'radiacao_terrestre', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'sunshine_duration') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.sunshine_duration', N'duracao_insolacao', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'evapotranspiration') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.evapotranspiration', N'evapotranspiracao', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_hora', N'et0_fao_evapotranspiration') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_hora.et0_fao_evapotranspiration', N'evapotranspiracao_et0', N'COLUMN';
GO

/* ---------- fact_clima_atual_dia (23 colunas) ---------- */
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'weather_code') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.weather_code', N'codigo_tempo', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'temperature_2m_max') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.temperature_2m_max', N'temperatura_2m_max', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'temperature_2m_min') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.temperature_2m_min', N'temperatura_2m_min', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'temperature_2m_mean') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.temperature_2m_mean', N'temperatura_2m_media', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'apparent_temperature_max') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.apparent_temperature_max', N'sensacao_termica_max', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'apparent_temperature_min') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.apparent_temperature_min', N'sensacao_termica_min', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'apparent_temperature_mean') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.apparent_temperature_mean', N'sensacao_termica_media', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'sunrise') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.sunrise', N'nascer_sol', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'sunset') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.sunset', N'por_sol', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'daylight_duration') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.daylight_duration', N'duracao_dia_claro', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'sunshine_duration') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.sunshine_duration', N'duracao_insolacao', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'uv_index_max') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.uv_index_max', N'indice_uv_max', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'precipitation_sum') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.precipitation_sum', N'precipitacao_total', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'rain_sum') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.rain_sum', N'chuva_total', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'showers_sum') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.showers_sum', N'pancadas_chuva_total', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'snowfall_sum') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.snowfall_sum', N'neve_total', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'precipitation_hours') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.precipitation_hours', N'horas_precipitacao', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'precipitation_probability_max') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.precipitation_probability_max', N'probabilidade_precipitacao_max', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'wind_speed_10m_max') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.wind_speed_10m_max', N'velocidade_vento_10m_max', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'wind_gusts_10m_max') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.wind_gusts_10m_max', N'rajada_vento_10m_max', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'wind_direction_10m_dominant') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.wind_direction_10m_dominant', N'direcao_vento_10m_dominante', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'shortwave_radiation_sum') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.shortwave_radiation_sum', N'radiacao_ondas_curtas_total', N'COLUMN';
IF COL_LENGTH(N'dbo.fact_clima_atual_dia', N'et0_fao_evapotranspiration') IS NOT NULL
    EXEC sp_rename N'dbo.fact_clima_atual_dia.et0_fao_evapotranspiration', N'evapotranspiracao_et0', N'COLUMN';
GO

/* ---------- stagings ----------
   Elas foram criadas com SELECT TOP 0 * INTO a partir das fatos, entao ainda
   carregam os nomes antigos. Como sao area de passagem e nascem vazias,
   recriar sai mais barato e mais seguro que renomear coluna a coluna. */
IF OBJECT_ID(N'dbo.stg_clima_historico_hora', N'U') IS NOT NULL DROP TABLE dbo.stg_clima_historico_hora;
IF OBJECT_ID(N'dbo.stg_clima_historico_dia',  N'U') IS NOT NULL DROP TABLE dbo.stg_clima_historico_dia;
IF OBJECT_ID(N'dbo.stg_clima_atual_hora',     N'U') IS NOT NULL DROP TABLE dbo.stg_clima_atual_hora;
IF OBJECT_ID(N'dbo.stg_clima_atual_dia',      N'U') IS NOT NULL DROP TABLE dbo.stg_clima_atual_dia;
GO

SELECT TOP 0 * INTO dbo.stg_clima_historico_hora FROM dbo.fact_clima_historico_hora;
SELECT TOP 0 * INTO dbo.stg_clima_historico_dia  FROM dbo.fact_clima_historico_dia;
SELECT TOP 0 * INTO dbo.stg_clima_atual_hora     FROM dbo.fact_clima_atual_hora;
SELECT TOP 0 * INTO dbo.stg_clima_atual_dia      FROM dbo.fact_clima_atual_dia;
GO

/* dt_carga de novo fora: SELECT INTO copia o NOT NULL, nao copia o DEFAULT */
ALTER TABLE dbo.stg_clima_historico_hora DROP COLUMN dt_carga;
ALTER TABLE dbo.stg_clima_historico_dia  DROP COLUMN dt_carga;
ALTER TABLE dbo.stg_clima_atual_hora     DROP COLUMN dt_carga;
ALTER TABLE dbo.stg_clima_atual_dia      DROP COLUMN dt_carga;
GO

/* Conferencia: nenhuma coluna deve sobrar com nome em ingles. */
SELECT t.name AS tabela, c.name AS coluna
  FROM sys.columns c
  JOIN sys.tables  t ON t.object_id = c.object_id
 WHERE t.name LIKE 'fact[_]%'
   AND c.name COLLATE Latin1_General_CS_AS LIKE '%[_]%'
   AND (c.name LIKE 'temperature%' OR c.name LIKE 'wind%' OR c.name LIKE 'soil%'
     OR c.name LIKE 'cloud%' OR c.name LIKE 'precipitation%' OR c.name LIKE '%radiation%')
 ORDER BY t.name, c.name;
GO

PRINT 'Colunas padronizadas em portugues.';
GO
