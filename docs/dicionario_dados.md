# Dicionário de dados — ClimaRMBH

Gerado das descrições gravadas no próprio banco (`sql/99_dicionario_dados.sql`) por `docs/gerar_dicionario_dados.sql`. Não editar à mão.

Valores **instantâneos** na hora H: temperatura, umidade, pressão, nuvens, vento, solo, visibilidade. Valores da **hora anterior** (H−1 a H): chuva, radiação, insolação, evapotranspiração, rajada.

## dim_data

Calendário de 1940-01-01 a 2035-12-31, um dia por linha. Chave data_id = AAAAMMDD. Nomes em português e estações do hemisfério sul, sem depender do idioma do login.

| Coluna | Tipo | Nulo | Chave | Descrição |
|---|---|---|---|---|
| `data_id` | int | não | PK | Chave do dia no formato AAAAMMDD (ex.: 20261113). Inteiro pequeno, legível e naturalmente ordenado. |
| `data` | date | não |  | O dia, como DATE. Único. |
| `ano` | smallint | não |  | Ano. |
| `trimestre` | tinyint | não |  | Trimestre do ano, de 1 a 4. |
| `mes` | tinyint | não |  | Mês, de 1 a 12. |
| `nome_mes` | nvarchar(12) | não |  | Nome do mês em português (Janeiro … Dezembro). |
| `nome_mes_abrev` | nvarchar(3) | não |  | Nome do mês abreviado em minúsculas (jan … dez). |
| `ano_mes` | int | não |  | Ano e mês como número AAAAMM. Use como coluna de ordenação de ano_mes_nome no Power BI. |
| `ano_mes_nome` | nvarchar(12) | não |  | Ano e mês para exibição (ex.: ago/2026). Ordene por ano_mes. |
| `dia` | tinyint | não |  | Dia do mês, de 1 a 31. |
| `dia_do_ano` | smallint | não |  | Dia do ano, de 1 a 366. |
| `semana_iso` | tinyint | não |  | Semana do ano no padrão ISO 8601 (semana começa na segunda-feira; a semana 1 contém a primeira quinta-feira do ano). |
| `num_dia_semana` | tinyint | não |  | Dia da semana, 1 = domingo … 7 = sábado. Calculado sem depender do SET DATEFIRST do servidor. |
| `nome_dia_semana` | nvarchar(15) | não |  | Nome do dia da semana em português. |
| `eh_fim_de_semana` | bit | não |  | 1 = sábado ou domingo. |
| `estacao` | nvarchar(10) | não |  | Estação do ano no hemisfério sul, por data-limite fixa: verão a partir de 21/12, outono de 21/03, inverno de 21/06, primavera de 23/09. Aproximação: as datas astronômicas variam um dia de ano para ano. |
| `primeiro_dia_mes` | date | não |  | Primeiro dia do mês desta data. |
| `ultimo_dia_mes` | date | não |  | Último dia do mês desta data. |

## dim_municipio

Municípios monitorados, um por linha (fase 1: Ibirité, Belo Horizonte, Contagem, Betim, Nova Lima e Sabará). As coordenadas são da sede municipal e são o ponto consultado na API; cada município cai num ponto de grade diferente do modelo.

| Coluna | Tipo | Nulo | Chave | Descrição |
|---|---|---|---|---|
| `municipio_id` | int | não | PK | Chave substituta do município, referenciada pelas fatos e pela etl_backfill_ano. |
| `codigo_ibge` | int | não |  | Código IBGE do município (7 dígitos). Chave natural, única. |
| `nome` | nvarchar(60) | não |  | Nome oficial do município, com acentos. |
| `uf` | char(2) | não |  | Sigla da unidade da federação. |
| `latitude` | decimal(9,6) | não |  | Latitude da sede municipal, em graus decimais (negativa = hemisfério sul). Ponto consultado na API. |
| `longitude` | decimal(9,6) | não |  | Longitude da sede municipal, em graus decimais (negativa = oeste). Ponto consultado na API. |
| `elevacao_m` | decimal(6,1) | sim |  | Altitude da sede, em metros, conferida na API de geocoding da Open-Meteo. |
| `ativo` | bit | não |  | 1 = município entra na coleta; 0 = fora da coleta, sem apagar o histórico já gravado. |
| `dt_carga` | datetime2(3) | não |  | Data e hora em que a linha foi criada. |

## fact_clima_atual_dia

Agregados diários do modelo de previsão (/v1/forecast), na mesma janela de 7 dias passados + 16 de previsão, reescrita a cada hora.

| Coluna | Tipo | Nulo | Chave | Descrição |
|---|---|---|---|---|
| `municipio_id` | int | não | PK | Município (FK para dim_municipio). |
| `data_id` | int | não | PK | Dia, no fuso de Brasília (FK para dim_data, AAAAMMDD). |
| `codigo_tempo` | smallint | sim |  | Condição do tempo mais severa do dia, pelo código WMO de 0 a 99 (ver codigo_tempo das tabelas horárias). |
| `temperatura_2m_max` | decimal(5,2) | sim |  | Temperatura máxima do ar a 2 m no dia, em °C. |
| `temperatura_2m_min` | decimal(5,2) | sim |  | Temperatura mínima do ar a 2 m no dia, em °C. |
| `temperatura_2m_media` | decimal(5,2) | sim |  | Temperatura média do ar a 2 m no dia, em °C (média das 24 horas). |
| `sensacao_termica_max` | decimal(5,2) | sim |  | Sensação térmica máxima do dia, em °C. |
| `sensacao_termica_min` | decimal(5,2) | sim |  | Sensação térmica mínima do dia, em °C. |
| `sensacao_termica_media` | decimal(5,2) | sim |  | Sensação térmica média do dia, em °C. |
| `nascer_sol` | datetime2(0) | sim |  | Data e hora local do nascer do sol. |
| `por_sol` | datetime2(0) | sim |  | Data e hora local do pôr do sol. |
| `duracao_dia_claro` | decimal(8,1) | sim |  | Duração do dia claro, em segundos, entre o nascer e o pôr do sol (astronômica, não depende de nuvens). Compare com duracao_insolacao para ver quanto do dia teve sol. |
| `duracao_insolacao` | decimal(8,1) | sim |  | Segundos de sol no dia, pela definição da WMO (radiação direta normal acima de 120 W/m²). Divida por 3.600 para horas. |
| `indice_uv_max` | decimal(4,2) | sim |  | Índice ultravioleta máximo do dia (adimensional). |
| `precipitacao_total` | decimal(7,2) | sim |  | Precipitação total do dia, em mm (chuva + pancadas + equivalente em água da neve). |
| `chuva_total` | decimal(7,2) | sim |  | Chuva no dia, em mm. No modelo de previsão, sem as pancadas convectivas (ficam em pancadas_chuva_total); no ERA5, toda a chuva. |
| `pancadas_chuva_total` | decimal(7,2) | sim |  | Pancadas de chuva convectivas no dia, em mm. Só no modelo de previsão. |
| `neve_total` | decimal(7,2) | sim |  | Neve no dia, em cm de neve. Sempre 0 na RMBH. |
| `horas_precipitacao` | decimal(4,1) | sim |  | Número de horas do dia com precipitação. |
| `probabilidade_precipitacao_max` | tinyint | sim |  | Maior probabilidade horária de precipitação do dia, em %. |
| `velocidade_vento_10m_max` | decimal(6,2) | sim |  | Velocidade máxima do vento a 10 m no dia, em km/h. |
| `rajada_vento_10m_max` | decimal(6,2) | sim |  | Rajada máxima a 10 m no dia, em km/h. |
| `direcao_vento_10m_dominante` | smallint | sim |  | Direção dominante de onde o vento soprou no dia, a 10 m, em graus (0 e 360 = norte). |
| `radiacao_ondas_curtas_total` | decimal(7,3) | sim |  | Energia solar global recebida no dia no plano horizontal, em MJ/m² (soma, não média: unidade diferente da coluna horária). |
| `evapotranspiracao_et0` | decimal(6,3) | sim |  | Evapotranspiração de referência ET0 (FAO-56), em mm no dia. |
| `eh_previsao` | bit | não |  | 1 = o dia ainda não tinha terminado na última coleta (o dia corrente conta como previsão, porque parte dele ainda é previsto); 0 = dia encerrado. A linha é sobrescrita a cada coleta. |
| `dt_carga` | datetime2(3) | não |  | Data e hora do último MERGE que gravou ou atualizou a linha, no relógio do servidor (Brasília desde 31/10/2026; antes, horário europeu). As checagens de qualidade usam esta coluna para isolar a última carga. |

## fact_clima_atual_hora

Dados horários do modelo de previsão da Open-Meteo (/v1/forecast): a cada hora, a janela de 7 dias passados + 16 de previsão é reescrita (DAG clima_incremental). A previsão de uma hora é sobrescrita quando a hora passa - esta tabela não guarda previsões antigas. Horas que saem da janela ficam com o último valor gravado. Origem diferente do histórico: não misturar as duas séries sem dizer. Previsões além de ~3 dias podem vir fisicamente inconsistentes na fonte (caso de 13/11/2026 no README).

| Coluna | Tipo | Nulo | Chave | Descrição |
|---|---|---|---|---|
| `municipio_id` | int | não | PK | Município (FK para dim_municipio). |
| `data_id` | int | não | PK | Dia, no fuso de Brasília (FK para dim_data, AAAAMMDD). |
| `hora` | tinyint | não | PK | Hora local, de 0 a 23, em UTC−3 fixo. A API não aplica horário de verão, então nenhuma hora se repete ou falta. |
| `data_hora_local` | datetime2(0) | não |  | Dia e hora combinados (data_id + hora), para eixo de tempo contínuo no Power BI. |
| `temperatura_2m` | decimal(5,2) | sim |  | Temperatura do ar a 2 m do solo, em °C. Valor instantâneo na hora. |
| `umidade_relativa_2m` | decimal(5,2) | sim |  | Umidade relativa do ar a 2 m, em %. Instantânea. |
| `ponto_orvalho_2m` | decimal(5,2) | sim |  | Ponto de orvalho a 2 m, em °C: temperatura em que o ar saturaria e formaria orvalho. Igual à temperatura = ar saturado. O modelo de previsão chega a dar até 0,7 °C acima da temperatura, o que não é físico. |
| `sensacao_termica` | decimal(5,2) | sim |  | Sensação térmica, em °C: temperatura percebida, combinando vento, umidade e radiação solar. Instantânea. |
| `deficit_pressao_vapor` | decimal(6,3) | sim |  | Déficit de pressão de vapor, em kPa: quanto falta de vapor para o ar saturar. Acima de ~1,6 as plantas transpiram mais; abaixo de ~0,4, menos. Instantâneo. |
| `precipitacao` | decimal(6,2) | sim |  | Precipitação total da hora anterior, em mm (chuva + pancadas + equivalente em água da neve). 1 mm = 1 litro por m². |
| `chuva` | decimal(6,2) | sim |  | Chuva na hora anterior, em mm. No modelo de previsão, só a de sistemas de grande escala (a convectiva fica em pancadas_chuva); no ERA5, que não separa, toda a chuva. |
| `pancadas_chuva` | decimal(6,2) | sim |  | Pancadas de chuva convectivas (de nuvens de tempestade) na hora anterior, em mm. Só no modelo de previsão; o ERA5 não separa. |
| `neve` | decimal(6,2) | sim |  | Neve na hora anterior, em cm de neve (não mm de água). Sempre 0 na RMBH; mantida por fidelidade ao payload. |
| `probabilidade_precipitacao` | tinyint | sim |  | Probabilidade de mais de 0,1 mm de precipitação na hora anterior, em %. Vem de um conjunto de simulações do modelo (ensemble), em grade mais grossa (~25 km). |
| `codigo_tempo` | smallint | sim |  | Condição do tempo na hora, pelo código WMO de 0 a 99 (0 = céu limpo, 1-3 = parcialmente nublado a encoberto, 45-48 = nevoeiro, 51-67 = garoa e chuva, 80-82 = pancadas, 95-99 = trovoada). |
| `eh_dia` | bit | sim |  | 1 = há luz do dia na hora (sol acima do horizonte); 0 = noite. |
| `visibilidade` | decimal(9,1) | sim |  | Visibilidade horizontal, em metros. Instantânea. |
| `indice_uv` | decimal(4,2) | sim |  | Índice ultravioleta (adimensional). Acima de 8 = risco muito alto. |
| `pressao_nivel_mar` | decimal(6,1) | sim |  | Pressão atmosférica reduzida ao nível do mar, em hPa. É a usada em meteorologia para comparar lugares de altitudes diferentes. |
| `pressao_superficie` | decimal(6,1) | sim |  | Pressão atmosférica na superfície, em hPa. Menor que a do nível do mar, porque cai com a altitude (a RMBH fica a ~740-950 m). |
| `cobertura_nuvens` | decimal(5,2) | sim |  | Fração do céu coberta por nuvens, em %, somando todas as camadas. |
| `cobertura_nuvens_baixa` | decimal(5,2) | sim |  | Cobertura de nuvens baixas e nevoeiro, até 3 km de altitude, em %. |
| `cobertura_nuvens_media` | decimal(5,2) | sim |  | Cobertura de nuvens médias, de 3 a 8 km de altitude, em %. |
| `cobertura_nuvens_alta` | decimal(5,2) | sim |  | Cobertura de nuvens altas, acima de 8 km, em %. |
| `velocidade_vento_10m` | decimal(6,2) | sim |  | Velocidade do vento a 10 m do solo, em km/h. Instantânea. |
| `velocidade_vento_100m` | decimal(6,2) | sim |  | Velocidade do vento a 100 m do solo (altura de turbina eólica), em km/h. Instantânea. |
| `direcao_vento_10m` | smallint | sim |  | Direção de onde o vento sopra a 10 m, em graus (0 e 360 = norte, 90 = leste, 180 = sul, 270 = oeste). |
| `direcao_vento_100m` | smallint | sim |  | Direção de onde o vento sopra a 100 m, em graus (0 e 360 = norte). |
| `rajada_vento_10m` | decimal(6,2) | sim |  | Rajada de vento a 10 m: velocidade máxima na hora anterior, em km/h. |
| `temperatura_solo_0cm` | decimal(5,2) | sim |  | Temperatura da superfície do solo, em °C (profundidades do modelo de previsão, diferentes do ERA5). Nula nas últimas ~26 h do horizonte de previsão. |
| `temperatura_solo_6cm` | decimal(5,2) | sim |  | Temperatura do solo a 6 cm, em °C. Nula nas últimas ~26 h do horizonte de previsão. |
| `temperatura_solo_18cm` | decimal(5,2) | sim |  | Temperatura do solo a 18 cm, em °C. Nula nas últimas ~26 h do horizonte de previsão. |
| `temperatura_solo_54cm` | decimal(5,2) | sim |  | Temperatura do solo a 54 cm, em °C. Nula nas últimas ~26 h do horizonte de previsão. |
| `umidade_solo_0_1cm` | decimal(5,3) | sim |  | Umidade do solo na camada de 0 a 1 cm, fração volumétrica de 0 a 1 (m³/m³). Nula nas últimas ~26 h do horizonte de previsão. |
| `umidade_solo_1_3cm` | decimal(5,3) | sim |  | Umidade do solo na camada de 1 a 3 cm, fração volumétrica de 0 a 1 (m³/m³). Nula nas últimas ~26 h do horizonte de previsão. |
| `umidade_solo_3_9cm` | decimal(5,3) | sim |  | Umidade do solo na camada de 3 a 9 cm, fração volumétrica de 0 a 1 (m³/m³). Nula nas últimas ~26 h do horizonte de previsão. |
| `umidade_solo_9_27cm` | decimal(5,3) | sim |  | Umidade do solo na camada de 9 a 27 cm, fração volumétrica de 0 a 1 (m³/m³). Nula nas últimas ~26 h do horizonte de previsão. |
| `umidade_solo_27_81cm` | decimal(5,3) | sim |  | Umidade do solo na camada de 27 a 81 cm, fração volumétrica de 0 a 1 (m³/m³). Nula nas últimas ~26 h do horizonte de previsão. |
| `radiacao_ondas_curtas` | decimal(7,2) | sim |  | Radiação solar global no plano horizontal (GHI), em W/m², média da hora anterior. É a soma de radiacao_direta + radiacao_difusa. |
| `radiacao_direta` | decimal(7,2) | sim |  | Parte da radiação solar que chega em linha reta do sol, medida no plano horizontal, em W/m², média da hora anterior. |
| `radiacao_difusa` | decimal(7,2) | sim |  | Parte da radiação solar espalhada pelas nuvens e pela atmosfera, no plano horizontal, em W/m², média da hora anterior. Em céu encoberto, quase toda a radiação é difusa. |
| `irradiancia_normal_direta` | decimal(7,2) | sim |  | Radiação direta num plano perpendicular aos raios do sol (DNI), em W/m², média da hora anterior. É maior que radiacao_direta, que é medida no plano horizontal; é a que interessa a painéis solares que seguem o sol. |
| `radiacao_terrestre` | decimal(7,2) | sim |  | Apesar do nome (terrestrial_radiation na API), é a radiação solar no TOPO DA ATMOSFERA (extraterrestre), em W/m², média da hora anterior - antes de nuvens e ar. Depende só da posição do sol (máximo ~1.413 W/m²). Útil como teto: radiacao_ondas_curtas nunca passa dela. |
| `duracao_insolacao` | decimal(8,1) | sim |  | Segundos de sol na hora anterior (0 a 3.600), pela definição da WMO: tempo em que a radiação direta normal passa de 120 W/m². |
| `evapotranspiracao` | decimal(6,3) | sim |  | Evapotranspiração real assumida pelo modelo de previsão para o local (solo + plantas, considerando a água disponível no solo), em mm na hora anterior. Pode ser negativa (orvalho). |
| `evapotranspiracao_et0` | decimal(6,3) | sim |  | Evapotranspiração de referência ET0 (FAO-56), em mm na hora anterior: quanto um gramado bem irrigado perderia de água. Padrão em agronomia para irrigação; não depende da água disponível no solo. |
| `eh_previsao` | bit | não |  | 1 = a hora ainda estava no futuro na última coleta (valor previsto); 0 = já tinha passado (valor do modelo para uma hora realizada). A linha é sobrescrita a cada coleta: a previsão original de uma hora que já passou não fica guardada. |
| `dt_carga` | datetime2(3) | não |  | Data e hora do último MERGE que gravou ou atualizou a linha, no relógio do servidor (Brasília desde 31/10/2026; antes, horário europeu). As checagens de qualidade usam esta coluna para isolar a última carga. |

## fact_clima_historico_dia

Agregados diários do histórico ERA5 (/v1/archive), calculados pela própria API no fuso de Brasília. Mesma origem e mesmo atraso da fact_clima_historico_hora.

| Coluna | Tipo | Nulo | Chave | Descrição |
|---|---|---|---|---|
| `municipio_id` | int | não | PK | Município (FK para dim_municipio). |
| `data_id` | int | não | PK | Dia, no fuso de Brasília (FK para dim_data, AAAAMMDD). |
| `codigo_tempo` | smallint | sim |  | Condição do tempo mais severa do dia, pelo código WMO de 0 a 99 (ver codigo_tempo das tabelas horárias). |
| `temperatura_2m_max` | decimal(5,2) | sim |  | Temperatura máxima do ar a 2 m no dia, em °C. |
| `temperatura_2m_min` | decimal(5,2) | sim |  | Temperatura mínima do ar a 2 m no dia, em °C. |
| `temperatura_2m_media` | decimal(5,2) | sim |  | Temperatura média do ar a 2 m no dia, em °C (média das 24 horas). |
| `sensacao_termica_max` | decimal(5,2) | sim |  | Sensação térmica máxima do dia, em °C. |
| `sensacao_termica_min` | decimal(5,2) | sim |  | Sensação térmica mínima do dia, em °C. |
| `sensacao_termica_media` | decimal(5,2) | sim |  | Sensação térmica média do dia, em °C. |
| `nascer_sol` | datetime2(0) | sim |  | Data e hora local do nascer do sol. |
| `por_sol` | datetime2(0) | sim |  | Data e hora local do pôr do sol. |
| `duracao_dia_claro` | decimal(8,1) | sim |  | Duração do dia claro, em segundos, entre o nascer e o pôr do sol (astronômica, não depende de nuvens). Compare com duracao_insolacao para ver quanto do dia teve sol. |
| `duracao_insolacao` | decimal(8,1) | sim |  | Segundos de sol no dia, pela definição da WMO (radiação direta normal acima de 120 W/m²). Divida por 3.600 para horas. |
| `precipitacao_total` | decimal(7,2) | sim |  | Precipitação total do dia, em mm (chuva + pancadas + equivalente em água da neve). |
| `chuva_total` | decimal(7,2) | sim |  | Chuva no dia, em mm. No modelo de previsão, sem as pancadas convectivas (ficam em pancadas_chuva_total); no ERA5, toda a chuva. |
| `neve_total` | decimal(7,2) | sim |  | Neve no dia, em cm de neve. Sempre 0 na RMBH. |
| `horas_precipitacao` | decimal(4,1) | sim |  | Número de horas do dia com precipitação. |
| `velocidade_vento_10m_max` | decimal(6,2) | sim |  | Velocidade máxima do vento a 10 m no dia, em km/h. |
| `rajada_vento_10m_max` | decimal(6,2) | sim |  | Rajada máxima a 10 m no dia, em km/h. |
| `direcao_vento_10m_dominante` | smallint | sim |  | Direção dominante de onde o vento soprou no dia, a 10 m, em graus (0 e 360 = norte). |
| `radiacao_ondas_curtas_total` | decimal(7,3) | sim |  | Energia solar global recebida no dia no plano horizontal, em MJ/m² (soma, não média: unidade diferente da coluna horária). |
| `evapotranspiracao_et0` | decimal(6,3) | sim |  | Evapotranspiração de referência ET0 (FAO-56), em mm no dia. |
| `dt_carga` | datetime2(3) | não |  | Data e hora do último MERGE que gravou ou atualizou a linha, no relógio do servidor (Brasília desde 31/10/2026; antes, horário europeu). As checagens de qualidade usam esta coluna para isolar a última carga. |

## fact_clima_historico_hora

Histórico horário de 1940 até hoje − 6 dias, da reanálise ERA5 (Open-Meteo /v1/archive). Reanálise é modelo numérico ajustado a observações, em grade de ~9-25 km: não é leitura de estação no ponto exato. Cresce uma vez por dia (DAG clima_historico); o atraso de ~6 dias é o da publicação do ERA5.

| Coluna | Tipo | Nulo | Chave | Descrição |
|---|---|---|---|---|
| `municipio_id` | int | não | PK | Município (FK para dim_municipio). |
| `data_id` | int | não | PK | Dia, no fuso de Brasília (FK para dim_data, AAAAMMDD). |
| `hora` | tinyint | não | PK | Hora local, de 0 a 23, em UTC−3 fixo. A API não aplica horário de verão, então nenhuma hora se repete ou falta. |
| `data_hora_local` | datetime2(0) | não |  | Dia e hora combinados (data_id + hora), para eixo de tempo contínuo no Power BI. |
| `temperatura_2m` | decimal(5,2) | sim |  | Temperatura do ar a 2 m do solo, em °C. Valor instantâneo na hora. |
| `umidade_relativa_2m` | decimal(5,2) | sim |  | Umidade relativa do ar a 2 m, em %. Instantânea. |
| `ponto_orvalho_2m` | decimal(5,2) | sim |  | Ponto de orvalho a 2 m, em °C: temperatura em que o ar saturaria e formaria orvalho. Igual à temperatura = ar saturado. O modelo de previsão chega a dar até 0,7 °C acima da temperatura, o que não é físico. |
| `sensacao_termica` | decimal(5,2) | sim |  | Sensação térmica, em °C: temperatura percebida, combinando vento, umidade e radiação solar. Instantânea. |
| `deficit_pressao_vapor` | decimal(6,3) | sim |  | Déficit de pressão de vapor, em kPa: quanto falta de vapor para o ar saturar. Acima de ~1,6 as plantas transpiram mais; abaixo de ~0,4, menos. Instantâneo. |
| `precipitacao` | decimal(6,2) | sim |  | Precipitação total da hora anterior, em mm (chuva + pancadas + equivalente em água da neve). 1 mm = 1 litro por m². |
| `chuva` | decimal(6,2) | sim |  | Chuva na hora anterior, em mm. No modelo de previsão, só a de sistemas de grande escala (a convectiva fica em pancadas_chuva); no ERA5, que não separa, toda a chuva. |
| `neve` | decimal(6,2) | sim |  | Neve na hora anterior, em cm de neve (não mm de água). Sempre 0 na RMBH; mantida por fidelidade ao payload. |
| `codigo_tempo` | smallint | sim |  | Condição do tempo na hora, pelo código WMO de 0 a 99 (0 = céu limpo, 1-3 = parcialmente nublado a encoberto, 45-48 = nevoeiro, 51-67 = garoa e chuva, 80-82 = pancadas, 95-99 = trovoada). |
| `eh_dia` | bit | sim |  | 1 = há luz do dia na hora (sol acima do horizonte); 0 = noite. |
| `pressao_nivel_mar` | decimal(6,1) | sim |  | Pressão atmosférica reduzida ao nível do mar, em hPa. É a usada em meteorologia para comparar lugares de altitudes diferentes. |
| `pressao_superficie` | decimal(6,1) | sim |  | Pressão atmosférica na superfície, em hPa. Menor que a do nível do mar, porque cai com a altitude (a RMBH fica a ~740-950 m). |
| `cobertura_nuvens` | decimal(5,2) | sim |  | Fração do céu coberta por nuvens, em %, somando todas as camadas. |
| `cobertura_nuvens_baixa` | decimal(5,2) | sim |  | Cobertura de nuvens baixas e nevoeiro, até 3 km de altitude, em %. |
| `cobertura_nuvens_media` | decimal(5,2) | sim |  | Cobertura de nuvens médias, de 3 a 8 km de altitude, em %. |
| `cobertura_nuvens_alta` | decimal(5,2) | sim |  | Cobertura de nuvens altas, acima de 8 km, em %. |
| `velocidade_vento_10m` | decimal(6,2) | sim |  | Velocidade do vento a 10 m do solo, em km/h. Instantânea. |
| `velocidade_vento_100m` | decimal(6,2) | sim |  | Velocidade do vento a 100 m do solo (altura de turbina eólica), em km/h. Instantânea. |
| `direcao_vento_10m` | smallint | sim |  | Direção de onde o vento sopra a 10 m, em graus (0 e 360 = norte, 90 = leste, 180 = sul, 270 = oeste). |
| `direcao_vento_100m` | smallint | sim |  | Direção de onde o vento sopra a 100 m, em graus (0 e 360 = norte). |
| `rajada_vento_10m` | decimal(6,2) | sim |  | Rajada de vento a 10 m: velocidade máxima na hora anterior, em km/h. |
| `temperatura_solo_0_7cm` | decimal(5,2) | sim |  | Temperatura média do solo na camada de 0 a 7 cm, em °C (camadas do ERA5). |
| `temperatura_solo_7_28cm` | decimal(5,2) | sim |  | Temperatura média do solo na camada de 7 a 28 cm, em °C (camadas do ERA5). |
| `temperatura_solo_28_100cm` | decimal(5,2) | sim |  | Temperatura média do solo na camada de 28 a 100 cm, em °C (camadas do ERA5). |
| `temperatura_solo_100_255cm` | decimal(5,2) | sim |  | Temperatura média do solo na camada de 100 a 255 cm, em °C (camadas do ERA5). |
| `umidade_solo_0_7cm` | decimal(5,3) | sim |  | Umidade do solo na camada de 0 a 7 cm, como fração volumétrica (m³ de água por m³ de solo, de 0 a 1; 0,30 = 30%). Camadas do ERA5. |
| `umidade_solo_7_28cm` | decimal(5,3) | sim |  | Umidade do solo na camada de 7 a 28 cm, fração volumétrica de 0 a 1 (m³/m³). Camadas do ERA5. |
| `umidade_solo_28_100cm` | decimal(5,3) | sim |  | Umidade do solo na camada de 28 a 100 cm, fração volumétrica de 0 a 1 (m³/m³). Camadas do ERA5. |
| `umidade_solo_100_255cm` | decimal(5,3) | sim |  | Umidade do solo na camada de 100 a 255 cm, fração volumétrica de 0 a 1 (m³/m³). Camadas do ERA5. |
| `radiacao_ondas_curtas` | decimal(7,2) | sim |  | Radiação solar global no plano horizontal (GHI), em W/m², média da hora anterior. É a soma de radiacao_direta + radiacao_difusa. |
| `radiacao_direta` | decimal(7,2) | sim |  | Parte da radiação solar que chega em linha reta do sol, medida no plano horizontal, em W/m², média da hora anterior. |
| `radiacao_difusa` | decimal(7,2) | sim |  | Parte da radiação solar espalhada pelas nuvens e pela atmosfera, no plano horizontal, em W/m², média da hora anterior. Em céu encoberto, quase toda a radiação é difusa. |
| `irradiancia_normal_direta` | decimal(7,2) | sim |  | Radiação direta num plano perpendicular aos raios do sol (DNI), em W/m², média da hora anterior. É maior que radiacao_direta, que é medida no plano horizontal; é a que interessa a painéis solares que seguem o sol. |
| `radiacao_terrestre` | decimal(7,2) | sim |  | Apesar do nome (terrestrial_radiation na API), é a radiação solar no TOPO DA ATMOSFERA (extraterrestre), em W/m², média da hora anterior - antes de nuvens e ar. Depende só da posição do sol (máximo ~1.413 W/m²). Útil como teto: radiacao_ondas_curtas nunca passa dela. |
| `duracao_insolacao` | decimal(8,1) | sim |  | Segundos de sol na hora anterior (0 a 3.600), pela definição da WMO: tempo em que a radiação direta normal passa de 120 W/m². |
| `evapotranspiracao_et0` | decimal(6,3) | sim |  | Evapotranspiração de referência ET0 (FAO-56), em mm na hora anterior: quanto um gramado bem irrigado perderia de água. Padrão em agronomia para irrigação; não depende da água disponível no solo. |
| `dt_carga` | datetime2(3) | não |  | Data e hora do último MERGE que gravou ou atualizou a linha, no relógio do servidor (Brasília desde 31/10/2026; antes, horário europeu). As checagens de qualidade usam esta coluna para isolar a última carga. |

## fact_previsao_snapshot_dia

Foto diária da previsão: uma vez por dia, copia da fact_clima_atual_dia os dias ainda previstos (hoje + 15), depois que as checagens de qualidade aprovam a carga. Como a previsão é sobrescrita na origem, só esta tabela permite medir quanto ela erra conforme a antecedência. Começou a ser gravada em novembro de 2026: não há fotos anteriores.

| Coluna | Tipo | Nulo | Chave | Descrição |
|---|---|---|---|---|
| `data_coleta` | date | não | PK | Dia em que a previsão foi fotografada, tirado do dt_carga da linha copiada (não do relógio da tarefa). |
| `municipio_id` | int | não | PK | Município (FK para dim_municipio). |
| `data_id` | int | não | PK | Dia PREVISTO (FK para dim_data, AAAAMMDD). Cruze com o mesmo data_id da fact_clima_atual_dia (eh_previsao = 0) para comparar com o realizado. |
| `antecedencia_dias` | tinyint | não |  | Dias entre a coleta e o dia previsto: 0 = o próprio dia da coleta (ainda parcialmente previsto) … 15 = último dia do horizonte. |
| `codigo_tempo` | smallint | sim |  | Condição do tempo mais severa do dia, pelo código WMO de 0 a 99 (ver codigo_tempo das tabelas horárias). |
| `temperatura_2m_max` | decimal(5,2) | sim |  | Temperatura máxima do ar a 2 m no dia, em °C. |
| `temperatura_2m_min` | decimal(5,2) | sim |  | Temperatura mínima do ar a 2 m no dia, em °C. |
| `precipitacao_total` | decimal(7,2) | sim |  | Precipitação total do dia, em mm (chuva + pancadas + equivalente em água da neve). |
| `horas_precipitacao` | decimal(4,1) | sim |  | Número de horas do dia com precipitação. |
| `probabilidade_precipitacao_max` | tinyint | sim |  | Maior probabilidade horária de precipitação do dia, em %. |
| `velocidade_vento_10m_max` | decimal(6,2) | sim |  | Velocidade máxima do vento a 10 m no dia, em km/h. |
| `dt_carga_origem` | datetime2(3) | não |  | dt_carga da linha copiada da fact_clima_atual_dia: qual carga incremental gerou esta previsão. |
| `dt_snapshot` | datetime2(3) | não |  | Data e hora em que a foto foi gravada. |

## etl_backfill_ano

Progresso do backfill histórico por município × ano. Permite parar (cota da API esgotada) e retomar de onde parou. O ano corrente nunca conta como concluído: é buscado de novo a cada execução, só com os dias novos.

| Coluna | Tipo | Nulo | Chave | Descrição |
|---|---|---|---|---|
| `municipio_id` | int | não | PK | Município (FK para dim_municipio). |
| `ano` | smallint | não | PK | Ano carregado. |
| `status` | nvarchar(20) | não |  | sucesso = ano completo, não é buscado de novo; parcial = ano corrente, buscado a cada execução até virar o ano. |
| `linhas_hora` | int | sim |  | Linhas horárias da última gravação deste município e ano. No ano corrente, é só a ponta buscada na última execução, não o total do ano. |
| `linhas_dia` | int | sim |  | Linhas diárias da última gravação deste município e ano (no ano corrente, só a ponta mais recente). |
| `dt_conclusao` | datetime2(3) | não |  | Data e hora da última gravação deste município e ano. |

## etl_execucao

Log de cada execução da ingestão (backfill ou incremental), uma linha por execução. As checagens de qualidade usam o dt_inicio da última execução incremental para isolar a última carga.

| Coluna | Tipo | Nulo | Chave | Descrição |
|---|---|---|---|---|
| `execucao_id` | bigint | não | PK | Identificador sequencial da execução. |
| `modo` | nvarchar(20) | não |  | Tipo de carga: backfill (histórico, /v1/archive) ou incremental (previsão, /v1/forecast). |
| `parametros` | nvarchar(200) | sim |  | Período ou argumentos pedidos, para rastreio. |
| `dt_inicio` | datetime2(3) | não |  | Início da execução, no relógio do servidor (Brasília desde 31/10/2026; antes, horário europeu). |
| `dt_fim` | datetime2(3) | sim |  | Fim da execução. NULL enquanto está rodando ou se o processo morreu no meio. |
| `status` | nvarchar(20) | não |  | rodando, sucesso, parcial (parou na cota da API com o progresso salvo; sai com código 0, então a tarefa fica verde no Airflow) ou erro. |
| `linhas_hora` | int | sim |  | Linhas horárias enviadas ao MERGE nesta execução. |
| `linhas_dia` | int | sim |  | Linhas diárias enviadas ao MERGE nesta execução. |
| `mensagem` | nvarchar(2000) | sim |  | Mensagem de erro ou de parada por cota, quando houver. |
