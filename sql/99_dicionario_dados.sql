/* =============================================================================
   99_dicionario_dados.sql  -  Dicionario de dados como propriedade estendida
   Numerado 99 para rodar sempre por ultimo no deploy.sh: documenta tabelas
   criadas pelos scripts anteriores. Tabela nova = texto novo aqui + rodar de novo.
   Grava MS_Description em cada tabela e coluna do banco. A documentacao vive no
   proprio banco: aparece no SSMS (Propriedades da coluna), viaja no backup e se
   consulta por sys.extended_properties - o .md do repositorio e gerado dela.

   Como esta montado:
   - @tabelas: uma descricao por tabela.
   - @colunas: uma descricao por coluna, ligada a tabelas por PADRAO (LIKE).
     Colunas que se repetem nas fatos (temperatura_2m, dt_carga...) sao escritas
     uma vez, com o padrao 'fact[_]%'. Quando o sentido muda no grao diario
     (duracao_insolacao: segundos na hora x no dia), uma linha com padrao mais
     especifico e prioridade menor vence - ROW_NUMBER por (tabela, coluna).
   - Idempotente: se a propriedade ja existe, atualiza; senao, cria. Pode rodar
     de novo sempre que um texto mudar.

   Unidades conferidas nos blocos hourly_units/daily_units da propria API
   (docs/amostras-api) e nos comentarios do DDL (04 a 07).

   Semantica temporal da Open-Meteo, a pergunta que mais muda a leitura:
   - valores INSTANTANEOS na hora H: temperatura, umidade, pressao, nuvens,
     vento (velocidade e direcao), solo, visibilidade, codigo do tempo;
   - valores da HORA ANTERIOR (H-1 a H): chuva/precipitacao/neve (soma),
     radiacoes (media), insolacao (segundos), evapotranspiracao (soma),
     rajada (maximo). Por isso a primeira hora de 1940 vem nula nessas colunas:
     nao existe hora anterior para acumular.
   ============================================================================= */
USE ClimaRMBH;
GO
SET NOCOUNT ON;

DECLARE @tabelas TABLE (tabela SYSNAME NOT NULL PRIMARY KEY, descricao NVARCHAR(2000) NOT NULL);
DECLARE @colunas TABLE (padrao SYSNAME NOT NULL, prioridade TINYINT NOT NULL, coluna SYSNAME NOT NULL,
                        descricao NVARCHAR(2000) NOT NULL);

/* ---------------------------------------------------------------------------
   Tabelas
   --------------------------------------------------------------------------- */
INSERT INTO @tabelas (tabela, descricao) VALUES
(N'dim_municipio', N'Municípios monitorados, um por linha (fase 1: Ibirité, Belo Horizonte, Contagem, Betim, Nova Lima e Sabará). As coordenadas são da sede municipal e são o ponto consultado na API; cada município cai num ponto de grade diferente do modelo.'),
(N'dim_data', N'Calendário de 1940-01-01 a 2035-12-31, um dia por linha. Chave data_id = AAAAMMDD. Nomes em português e estações do hemisfério sul, sem depender do idioma do login.'),
(N'fact_clima_historico_hora', N'Histórico horário de 1940 até hoje − 6 dias, da reanálise ERA5 (Open-Meteo /v1/archive). Reanálise é modelo numérico ajustado a observações, em grade de ~9-25 km: não é leitura de estação no ponto exato. Cresce uma vez por dia (DAG clima_historico); o atraso de ~6 dias é o da publicação do ERA5.'),
(N'fact_clima_historico_dia', N'Agregados diários do histórico ERA5 (/v1/archive), calculados pela própria API no fuso de Brasília. Mesma origem e mesmo atraso da fact_clima_historico_hora.'),
(N'fact_clima_atual_hora', N'Dados horários do modelo de previsão da Open-Meteo (/v1/forecast): a cada hora, a janela de 7 dias passados + 16 de previsão é reescrita (DAG clima_incremental). A previsão de uma hora é sobrescrita quando a hora passa - esta tabela não guarda previsões antigas. Horas que saem da janela ficam com o último valor gravado. Origem diferente do histórico: não misturar as duas séries sem dizer. Previsões além de ~3 dias podem vir fisicamente inconsistentes na fonte (caso de 13/11/2026 no README).'),
(N'fact_clima_atual_dia', N'Agregados diários do modelo de previsão (/v1/forecast), na mesma janela de 7 dias passados + 16 de previsão, reescrita a cada hora.'),
(N'fact_previsao_snapshot_dia', N'Foto diária da previsão: uma vez por dia, copia da fact_clima_atual_dia os dias ainda previstos (hoje + 15), depois que as checagens de qualidade aprovam a carga. Como a previsão é sobrescrita na origem, só esta tabela permite medir quanto ela erra conforme a antecedência. Começou a ser gravada em novembro de 2026: não há fotos anteriores.'),
(N'etl_execucao', N'Log de cada execução da ingestão (backfill ou incremental), uma linha por execução. As checagens de qualidade usam o dt_inicio da última execução incremental para isolar a última carga.'),
(N'etl_backfill_ano', N'Progresso do backfill histórico por município × ano. Permite parar (cota da API esgotada) e retomar de onde parou. O ano corrente nunca conta como concluído: é buscado de novo a cada execução, só com os dias novos.'),
(N'stg_clima_historico_hora', N'Área de passagem da ingestão: recebe o lote da API, é zerada (TRUNCATE) a cada carga e um MERGE leva os dados para a fact_clima_historico_hora. Não consultar.'),
(N'stg_clima_historico_dia', N'Área de passagem da ingestão: recebe o lote da API, é zerada (TRUNCATE) a cada carga e um MERGE leva os dados para a fact_clima_historico_dia. Não consultar.'),
(N'stg_clima_atual_hora', N'Área de passagem da ingestão: recebe o lote da API, é zerada (TRUNCATE) a cada carga e um MERGE leva os dados para a fact_clima_atual_hora. Não consultar.'),
(N'stg_clima_atual_dia', N'Área de passagem da ingestão: recebe o lote da API, é zerada (TRUNCATE) a cada carga e um MERGE leva os dados para a fact_clima_atual_dia. Não consultar.');

/* ---------------------------------------------------------------------------
   dim_municipio
   --------------------------------------------------------------------------- */
INSERT INTO @colunas (padrao, prioridade, coluna, descricao) VALUES
(N'dim_municipio', 0, N'municipio_id', N'Chave substituta do município, referenciada pelas fatos e pela etl_backfill_ano.'),
(N'dim_municipio', 0, N'codigo_ibge',  N'Código IBGE do município (7 dígitos). Chave natural, única.'),
(N'dim_municipio', 0, N'nome',         N'Nome oficial do município, com acentos.'),
(N'dim_municipio', 0, N'uf',           N'Sigla da unidade da federação.'),
(N'dim_municipio', 0, N'latitude',     N'Latitude da sede municipal, em graus decimais (negativa = hemisfério sul). Ponto consultado na API.'),
(N'dim_municipio', 0, N'longitude',    N'Longitude da sede municipal, em graus decimais (negativa = oeste). Ponto consultado na API.'),
(N'dim_municipio', 0, N'elevacao_m',   N'Altitude da sede, em metros, conferida na API de geocoding da Open-Meteo.'),
(N'dim_municipio', 0, N'ativo',        N'1 = município entra na coleta; 0 = fora da coleta, sem apagar o histórico já gravado.'),
(N'dim_municipio', 0, N'dt_carga',     N'Data e hora em que a linha foi criada.');

/* ---------------------------------------------------------------------------
   dim_data
   --------------------------------------------------------------------------- */
INSERT INTO @colunas (padrao, prioridade, coluna, descricao) VALUES
(N'dim_data', 0, N'data_id',          N'Chave do dia no formato AAAAMMDD (ex.: 20261113). Inteiro pequeno, legível e naturalmente ordenado.'),
(N'dim_data', 0, N'data',             N'O dia, como DATE. Único.'),
(N'dim_data', 0, N'ano',              N'Ano.'),
(N'dim_data', 0, N'trimestre',        N'Trimestre do ano, de 1 a 4.'),
(N'dim_data', 0, N'mes',              N'Mês, de 1 a 12.'),
(N'dim_data', 0, N'nome_mes',         N'Nome do mês em português (Janeiro … Dezembro).'),
(N'dim_data', 0, N'nome_mes_abrev',   N'Nome do mês abreviado em minúsculas (jan … dez).'),
(N'dim_data', 0, N'ano_mes',          N'Ano e mês como número AAAAMM. Use como coluna de ordenação de ano_mes_nome no Power BI.'),
(N'dim_data', 0, N'ano_mes_nome',     N'Ano e mês para exibição (ex.: ago/2026). Ordene por ano_mes.'),
(N'dim_data', 0, N'dia',              N'Dia do mês, de 1 a 31.'),
(N'dim_data', 0, N'dia_do_ano',       N'Dia do ano, de 1 a 366.'),
(N'dim_data', 0, N'semana_iso',       N'Semana do ano no padrão ISO 8601 (semana começa na segunda-feira; a semana 1 contém a primeira quinta-feira do ano).'),
(N'dim_data', 0, N'num_dia_semana',   N'Dia da semana, 1 = domingo … 7 = sábado. Calculado sem depender do SET DATEFIRST do servidor.'),
(N'dim_data', 0, N'nome_dia_semana',  N'Nome do dia da semana em português.'),
(N'dim_data', 0, N'eh_fim_de_semana', N'1 = sábado ou domingo.'),
(N'dim_data', 0, N'estacao',          N'Estação do ano no hemisfério sul, por data-limite fixa: verão a partir de 21/12, outono de 21/03, inverno de 21/06, primavera de 23/09. Aproximação: as datas astronômicas variam um dia de ano para ano.'),
(N'dim_data', 0, N'primeiro_dia_mes', N'Primeiro dia do mês desta data.'),
(N'dim_data', 0, N'ultimo_dia_mes',   N'Último dia do mês desta data.');

/* ---------------------------------------------------------------------------
   etl_execucao e etl_backfill_ano
   --------------------------------------------------------------------------- */
INSERT INTO @colunas (padrao, prioridade, coluna, descricao) VALUES
(N'etl_execucao', 0, N'execucao_id', N'Identificador sequencial da execução.'),
(N'etl_execucao', 0, N'modo',        N'Tipo de carga: backfill (histórico, /v1/archive) ou incremental (previsão, /v1/forecast).'),
(N'etl_execucao', 0, N'parametros',  N'Período ou argumentos pedidos, para rastreio.'),
(N'etl_execucao', 0, N'dt_inicio',   N'Início da execução, no relógio do servidor (Brasília desde 31/10/2026; antes, horário europeu).'),
(N'etl_execucao', 0, N'dt_fim',      N'Fim da execução. NULL enquanto está rodando ou se o processo morreu no meio.'),
(N'etl_execucao', 0, N'status',      N'rodando, sucesso, parcial (parou na cota da API com o progresso salvo; sai com código 0, então a tarefa fica verde no Airflow) ou erro.'),
(N'etl_execucao', 0, N'linhas_hora', N'Linhas horárias enviadas ao MERGE nesta execução.'),
(N'etl_execucao', 0, N'linhas_dia',  N'Linhas diárias enviadas ao MERGE nesta execução.'),
(N'etl_execucao', 0, N'mensagem',    N'Mensagem de erro ou de parada por cota, quando houver.'),

(N'etl_backfill_ano', 0, N'municipio_id', N'Município (FK para dim_municipio).'),
(N'etl_backfill_ano', 0, N'ano',          N'Ano carregado.'),
(N'etl_backfill_ano', 0, N'status',       N'sucesso = ano completo, não é buscado de novo; parcial = ano corrente, buscado a cada execução até virar o ano.'),
(N'etl_backfill_ano', 0, N'linhas_hora',  N'Linhas horárias da última gravação deste município e ano. No ano corrente, é só a ponta buscada na última execução, não o total do ano.'),
(N'etl_backfill_ano', 0, N'linhas_dia',   N'Linhas diárias da última gravação deste município e ano (no ano corrente, só a ponta mais recente).'),
(N'etl_backfill_ano', 0, N'dt_conclusao', N'Data e hora da última gravação deste município e ano.');

/* ---------------------------------------------------------------------------
   Fatos - colunas tecnicas
   --------------------------------------------------------------------------- */
INSERT INTO @colunas (padrao, prioridade, coluna, descricao) VALUES
(N'fact[_]%',      2, N'municipio_id',    N'Município (FK para dim_municipio).'),
(N'fact[_]%',      2, N'data_id',         N'Dia, no fuso de Brasília (FK para dim_data, AAAAMMDD).'),
(N'fact[_]%',      2, N'hora',            N'Hora local, de 0 a 23, em UTC−3 fixo. A API não aplica horário de verão, então nenhuma hora se repete ou falta.'),
(N'fact[_]%',      2, N'data_hora_local', N'Dia e hora combinados (data_id + hora), para eixo de tempo contínuo no Power BI.'),
(N'fact[_]%',      2, N'dt_carga',        N'Data e hora do último MERGE que gravou ou atualizou a linha, no relógio do servidor (Brasília desde 31/10/2026; antes, horário europeu). As checagens de qualidade usam esta coluna para isolar a última carga.'),
(N'fact[_]%',      2, N'eh_previsao',     N'1 = a hora ainda estava no futuro na última coleta (valor previsto); 0 = já tinha passado (valor do modelo para uma hora realizada). A linha é sobrescrita a cada coleta: a previsão original de uma hora que já passou não fica guardada.'),
(N'fact[_]%[_]dia', 1, N'eh_previsao',    N'1 = o dia ainda não tinha terminado na última coleta (o dia corrente conta como previsão, porque parte dele ainda é previsto); 0 = dia encerrado. A linha é sobrescrita a cada coleta.');

/* ---------------------------------------------------------------------------
   fact_previsao_snapshot_dia - colunas proprias (as medidas herdam o texto
   das diarias pelo padrao 'fact[_]%[_]dia')
   --------------------------------------------------------------------------- */
INSERT INTO @colunas (padrao, prioridade, coluna, descricao) VALUES
(N'fact_previsao_snapshot_dia', 0, N'data_coleta',       N'Dia em que a previsão foi fotografada, tirado do dt_carga da linha copiada (não do relógio da tarefa).'),
(N'fact_previsao_snapshot_dia', 0, N'data_id',           N'Dia PREVISTO (FK para dim_data, AAAAMMDD). Cruze com o mesmo data_id da fact_clima_atual_dia (eh_previsao = 0) para comparar com o realizado.'),
(N'fact_previsao_snapshot_dia', 0, N'antecedencia_dias', N'Dias entre a coleta e o dia previsto: 0 = o próprio dia da coleta (ainda parcialmente previsto) … 15 = último dia do horizonte.'),
(N'fact_previsao_snapshot_dia', 0, N'dt_carga_origem',   N'dt_carga da linha copiada da fact_clima_atual_dia: qual carga incremental gerou esta previsão.'),
(N'fact_previsao_snapshot_dia', 0, N'dt_snapshot',       N'Data e hora em que a foto foi gravada.');

/* ---------------------------------------------------------------------------
   Fatos horarias - medidas
   --------------------------------------------------------------------------- */
INSERT INTO @colunas (padrao, prioridade, coluna, descricao) VALUES
-- temperatura e umidade (instantaneas)
(N'fact[_]%', 2, N'temperatura_2m',        N'Temperatura do ar a 2 m do solo, em °C. Valor instantâneo na hora.'),
(N'fact[_]%', 2, N'umidade_relativa_2m',   N'Umidade relativa do ar a 2 m, em %. Instantânea.'),
(N'fact[_]%', 2, N'ponto_orvalho_2m',      N'Ponto de orvalho a 2 m, em °C: temperatura em que o ar saturaria e formaria orvalho. Igual à temperatura = ar saturado. O modelo de previsão chega a dar até 0,7 °C acima da temperatura, o que não é físico.'),
(N'fact[_]%', 2, N'sensacao_termica',      N'Sensação térmica, em °C: temperatura percebida, combinando vento, umidade e radiação solar. Instantânea.'),
(N'fact[_]%', 2, N'deficit_pressao_vapor', N'Déficit de pressão de vapor, em kPa: quanto falta de vapor para o ar saturar. Acima de ~1,6 as plantas transpiram mais; abaixo de ~0,4, menos. Instantâneo.'),
-- precipitacao (soma da hora anterior)
(N'fact[_]%', 2, N'precipitacao',          N'Precipitação total da hora anterior, em mm (chuva + pancadas + equivalente em água da neve). 1 mm = 1 litro por m².'),
(N'fact[_]%', 2, N'chuva',                 N'Chuva na hora anterior, em mm. No modelo de previsão, só a de sistemas de grande escala (a convectiva fica em pancadas_chuva); no ERA5, que não separa, toda a chuva.'),
(N'fact[_]%', 2, N'pancadas_chuva',        N'Pancadas de chuva convectivas (de nuvens de tempestade) na hora anterior, em mm. Só no modelo de previsão; o ERA5 não separa.'),
(N'fact[_]%', 2, N'neve',                  N'Neve na hora anterior, em cm de neve (não mm de água). Sempre 0 na RMBH; mantida por fidelidade ao payload.'),
(N'fact[_]%', 2, N'probabilidade_precipitacao', N'Probabilidade de mais de 0,1 mm de precipitação na hora anterior, em %. Vem de um conjunto de simulações do modelo (ensemble), em grade mais grossa (~25 km).'),
-- condicao do tempo
(N'fact[_]%', 2, N'codigo_tempo',          N'Condição do tempo na hora, pelo código WMO de 0 a 99 (0 = céu limpo, 1-3 = parcialmente nublado a encoberto, 45-48 = nevoeiro, 51-67 = garoa e chuva, 80-82 = pancadas, 95-99 = trovoada).'),
(N'fact[_]%', 2, N'eh_dia',                N'1 = há luz do dia na hora (sol acima do horizonte); 0 = noite.'),
(N'fact[_]%', 2, N'visibilidade',          N'Visibilidade horizontal, em metros. Instantânea.'),
(N'fact[_]%', 2, N'indice_uv',             N'Índice ultravioleta (adimensional). Acima de 8 = risco muito alto.'),
-- pressao e nuvens (instantaneas)
(N'fact[_]%', 2, N'pressao_nivel_mar',     N'Pressão atmosférica reduzida ao nível do mar, em hPa. É a usada em meteorologia para comparar lugares de altitudes diferentes.'),
(N'fact[_]%', 2, N'pressao_superficie',    N'Pressão atmosférica na superfície, em hPa. Menor que a do nível do mar, porque cai com a altitude (a RMBH fica a ~740-950 m).'),
(N'fact[_]%', 2, N'cobertura_nuvens',      N'Fração do céu coberta por nuvens, em %, somando todas as camadas.'),
(N'fact[_]%', 2, N'cobertura_nuvens_baixa', N'Cobertura de nuvens baixas e nevoeiro, até 3 km de altitude, em %.'),
(N'fact[_]%', 2, N'cobertura_nuvens_media', N'Cobertura de nuvens médias, de 3 a 8 km de altitude, em %.'),
(N'fact[_]%', 2, N'cobertura_nuvens_alta',  N'Cobertura de nuvens altas, acima de 8 km, em %.'),
-- vento
(N'fact[_]%', 2, N'velocidade_vento_10m',  N'Velocidade do vento a 10 m do solo, em km/h. Instantânea.'),
(N'fact[_]%', 2, N'velocidade_vento_100m', N'Velocidade do vento a 100 m do solo (altura de turbina eólica), em km/h. Instantânea.'),
(N'fact[_]%', 2, N'direcao_vento_10m',     N'Direção de onde o vento sopra a 10 m, em graus (0 e 360 = norte, 90 = leste, 180 = sul, 270 = oeste).'),
(N'fact[_]%', 2, N'direcao_vento_100m',    N'Direção de onde o vento sopra a 100 m, em graus (0 e 360 = norte).'),
(N'fact[_]%', 2, N'rajada_vento_10m',      N'Rajada de vento a 10 m: velocidade máxima na hora anterior, em km/h.'),
-- solo: ERA5 (historico), camadas
(N'fact[_]%', 2, N'temperatura_solo_0_7cm',     N'Temperatura média do solo na camada de 0 a 7 cm, em °C (camadas do ERA5).'),
(N'fact[_]%', 2, N'temperatura_solo_7_28cm',    N'Temperatura média do solo na camada de 7 a 28 cm, em °C (camadas do ERA5).'),
(N'fact[_]%', 2, N'temperatura_solo_28_100cm',  N'Temperatura média do solo na camada de 28 a 100 cm, em °C (camadas do ERA5).'),
(N'fact[_]%', 2, N'temperatura_solo_100_255cm', N'Temperatura média do solo na camada de 100 a 255 cm, em °C (camadas do ERA5).'),
(N'fact[_]%', 2, N'umidade_solo_0_7cm',     N'Umidade do solo na camada de 0 a 7 cm, como fração volumétrica (m³ de água por m³ de solo, de 0 a 1; 0,30 = 30%). Camadas do ERA5.'),
(N'fact[_]%', 2, N'umidade_solo_7_28cm',    N'Umidade do solo na camada de 7 a 28 cm, fração volumétrica de 0 a 1 (m³/m³). Camadas do ERA5.'),
(N'fact[_]%', 2, N'umidade_solo_28_100cm',  N'Umidade do solo na camada de 28 a 100 cm, fração volumétrica de 0 a 1 (m³/m³). Camadas do ERA5.'),
(N'fact[_]%', 2, N'umidade_solo_100_255cm', N'Umidade do solo na camada de 100 a 255 cm, fração volumétrica de 0 a 1 (m³/m³). Camadas do ERA5.'),
-- solo: modelo de previsao, profundidades e camadas diferentes do ERA5
(N'fact[_]%', 2, N'temperatura_solo_0cm',  N'Temperatura da superfície do solo, em °C (profundidades do modelo de previsão, diferentes do ERA5). Nula nas últimas ~26 h do horizonte de previsão.'),
(N'fact[_]%', 2, N'temperatura_solo_6cm',  N'Temperatura do solo a 6 cm, em °C. Nula nas últimas ~26 h do horizonte de previsão.'),
(N'fact[_]%', 2, N'temperatura_solo_18cm', N'Temperatura do solo a 18 cm, em °C. Nula nas últimas ~26 h do horizonte de previsão.'),
(N'fact[_]%', 2, N'temperatura_solo_54cm', N'Temperatura do solo a 54 cm, em °C. Nula nas últimas ~26 h do horizonte de previsão.'),
(N'fact[_]%', 2, N'umidade_solo_0_1cm',   N'Umidade do solo na camada de 0 a 1 cm, fração volumétrica de 0 a 1 (m³/m³). Nula nas últimas ~26 h do horizonte de previsão.'),
(N'fact[_]%', 2, N'umidade_solo_1_3cm',   N'Umidade do solo na camada de 1 a 3 cm, fração volumétrica de 0 a 1 (m³/m³). Nula nas últimas ~26 h do horizonte de previsão.'),
(N'fact[_]%', 2, N'umidade_solo_3_9cm',   N'Umidade do solo na camada de 3 a 9 cm, fração volumétrica de 0 a 1 (m³/m³). Nula nas últimas ~26 h do horizonte de previsão.'),
(N'fact[_]%', 2, N'umidade_solo_9_27cm',  N'Umidade do solo na camada de 9 a 27 cm, fração volumétrica de 0 a 1 (m³/m³). Nula nas últimas ~26 h do horizonte de previsão.'),
(N'fact[_]%', 2, N'umidade_solo_27_81cm', N'Umidade do solo na camada de 27 a 81 cm, fração volumétrica de 0 a 1 (m³/m³). Nula nas últimas ~26 h do horizonte de previsão.'),
-- radiacao (media da hora anterior)
(N'fact[_]%', 2, N'radiacao_ondas_curtas',     N'Radiação solar global no plano horizontal (GHI), em W/m², média da hora anterior. É a soma de radiacao_direta + radiacao_difusa.'),
(N'fact[_]%', 2, N'radiacao_direta',           N'Parte da radiação solar que chega em linha reta do sol, medida no plano horizontal, em W/m², média da hora anterior.'),
(N'fact[_]%', 2, N'radiacao_difusa',           N'Parte da radiação solar espalhada pelas nuvens e pela atmosfera, no plano horizontal, em W/m², média da hora anterior. Em céu encoberto, quase toda a radiação é difusa.'),
(N'fact[_]%', 2, N'irradiancia_normal_direta', N'Radiação direta num plano perpendicular aos raios do sol (DNI), em W/m², média da hora anterior. É maior que radiacao_direta, que é medida no plano horizontal; é a que interessa a painéis solares que seguem o sol.'),
(N'fact[_]%', 2, N'radiacao_terrestre',        N'Apesar do nome (terrestrial_radiation na API), é a radiação solar no TOPO DA ATMOSFERA (extraterrestre), em W/m², média da hora anterior - antes de nuvens e ar. Depende só da posição do sol (máximo ~1.413 W/m²). Útil como teto: radiacao_ondas_curtas nunca passa dela.'),
(N'fact[_]%', 2, N'duracao_insolacao',         N'Segundos de sol na hora anterior (0 a 3.600), pela definição da WMO: tempo em que a radiação direta normal passa de 120 W/m².'),
-- evapotranspiracao (soma da hora anterior)
(N'fact[_]%', 2, N'evapotranspiracao',     N'Evapotranspiração real assumida pelo modelo de previsão para o local (solo + plantas, considerando a água disponível no solo), em mm na hora anterior. Pode ser negativa (orvalho).'),
(N'fact[_]%', 2, N'evapotranspiracao_et0', N'Evapotranspiração de referência ET0 (FAO-56), em mm na hora anterior: quanto um gramado bem irrigado perderia de água. Padrão em agronomia para irrigação; não depende da água disponível no solo.');

/* ---------------------------------------------------------------------------
   Fatos diarias - medidas (agregados calculados pela API no fuso de Brasilia)
   --------------------------------------------------------------------------- */
INSERT INTO @colunas (padrao, prioridade, coluna, descricao) VALUES
(N'fact[_]%[_]dia', 1, N'codigo_tempo',          N'Condição do tempo mais severa do dia, pelo código WMO de 0 a 99 (ver codigo_tempo das tabelas horárias).'),
(N'fact[_]%[_]dia', 1, N'duracao_insolacao',     N'Segundos de sol no dia, pela definição da WMO (radiação direta normal acima de 120 W/m²). Divida por 3.600 para horas.'),
(N'fact[_]%[_]dia', 1, N'evapotranspiracao_et0', N'Evapotranspiração de referência ET0 (FAO-56), em mm no dia.'),
(N'fact[_]%', 2, N'temperatura_2m_max',     N'Temperatura máxima do ar a 2 m no dia, em °C.'),
(N'fact[_]%', 2, N'temperatura_2m_min',     N'Temperatura mínima do ar a 2 m no dia, em °C.'),
(N'fact[_]%', 2, N'temperatura_2m_media',   N'Temperatura média do ar a 2 m no dia, em °C (média das 24 horas).'),
(N'fact[_]%', 2, N'sensacao_termica_max',   N'Sensação térmica máxima do dia, em °C.'),
(N'fact[_]%', 2, N'sensacao_termica_min',   N'Sensação térmica mínima do dia, em °C.'),
(N'fact[_]%', 2, N'sensacao_termica_media', N'Sensação térmica média do dia, em °C.'),
(N'fact[_]%', 2, N'nascer_sol',             N'Data e hora local do nascer do sol.'),
(N'fact[_]%', 2, N'por_sol',                N'Data e hora local do pôr do sol.'),
(N'fact[_]%', 2, N'duracao_dia_claro',      N'Duração do dia claro, em segundos, entre o nascer e o pôr do sol (astronômica, não depende de nuvens). Compare com duracao_insolacao para ver quanto do dia teve sol.'),
(N'fact[_]%', 2, N'indice_uv_max',          N'Índice ultravioleta máximo do dia (adimensional).'),
(N'fact[_]%', 2, N'precipitacao_total',     N'Precipitação total do dia, em mm (chuva + pancadas + equivalente em água da neve).'),
(N'fact[_]%', 2, N'chuva_total',            N'Chuva no dia, em mm. No modelo de previsão, sem as pancadas convectivas (ficam em pancadas_chuva_total); no ERA5, toda a chuva.'),
(N'fact[_]%', 2, N'pancadas_chuva_total',   N'Pancadas de chuva convectivas no dia, em mm. Só no modelo de previsão.'),
(N'fact[_]%', 2, N'neve_total',             N'Neve no dia, em cm de neve. Sempre 0 na RMBH.'),
(N'fact[_]%', 2, N'horas_precipitacao',     N'Número de horas do dia com precipitação.'),
(N'fact[_]%', 2, N'probabilidade_precipitacao_max', N'Maior probabilidade horária de precipitação do dia, em %.'),
(N'fact[_]%', 2, N'velocidade_vento_10m_max',       N'Velocidade máxima do vento a 10 m no dia, em km/h.'),
(N'fact[_]%', 2, N'rajada_vento_10m_max',           N'Rajada máxima a 10 m no dia, em km/h.'),
(N'fact[_]%', 2, N'direcao_vento_10m_dominante',    N'Direção dominante de onde o vento soprou no dia, a 10 m, em graus (0 e 360 = norte).'),
(N'fact[_]%', 2, N'radiacao_ondas_curtas_total',    N'Energia solar global recebida no dia no plano horizontal, em MJ/m² (soma, não média: unidade diferente da coluna horária).');

/* ---------------------------------------------------------------------------
   Aplicacao
   --------------------------------------------------------------------------- */
DECLARE @alvo TABLE (id INT IDENTITY(1,1) PRIMARY KEY, objeto_id INT NOT NULL, coluna_id INT NOT NULL,
                     tabela SYSNAME NOT NULL, coluna SYSNAME NULL, descricao NVARCHAR(2000) NOT NULL);

-- nivel de tabela (coluna_id = 0)
INSERT INTO @alvo (objeto_id, coluna_id, tabela, coluna, descricao)
SELECT t.object_id, 0, t.name, NULL, tb.descricao
FROM sys.tables t
JOIN @tabelas tb ON tb.tabela = t.name
WHERE t.schema_id = SCHEMA_ID(N'dbo');

-- nivel de coluna: vence a descricao de menor prioridade (mais especifica)
INSERT INTO @alvo (objeto_id, coluna_id, tabela, coluna, descricao)
SELECT objeto_id, coluna_id, tabela, coluna, descricao
FROM (
    SELECT t.object_id AS objeto_id, c.column_id AS coluna_id, t.name AS tabela, c.name AS coluna,
           d.descricao,
           ROW_NUMBER() OVER (PARTITION BY t.object_id, c.column_id ORDER BY d.prioridade) AS ordem
    FROM sys.tables t
    JOIN sys.columns c ON c.object_id = t.object_id
    JOIN @colunas d    ON d.coluna = c.name AND t.name LIKE d.padrao
    WHERE t.schema_id = SCHEMA_ID(N'dbo')
) escolhida
WHERE ordem = 1;

DECLARE @i INT = 1, @total INT = (SELECT COUNT(*) FROM @alvo);
DECLARE @objeto_id INT, @coluna_id INT, @tabela SYSNAME, @coluna SYSNAME, @descricao NVARCHAR(2000);

WHILE @i <= @total
BEGIN
    SELECT @objeto_id = objeto_id, @coluna_id = coluna_id, @tabela = tabela, @coluna = coluna,
           @descricao = descricao
    FROM @alvo WHERE id = @i;

    IF EXISTS (SELECT 1 FROM sys.extended_properties
               WHERE class = 1 AND major_id = @objeto_id AND minor_id = @coluna_id
                 AND name = N'MS_Description')
    BEGIN
        IF @coluna IS NULL
            EXEC sys.sp_updateextendedproperty @name = N'MS_Description', @value = @descricao,
                 @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = @tabela;
        ELSE
            EXEC sys.sp_updateextendedproperty @name = N'MS_Description', @value = @descricao,
                 @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = @tabela,
                 @level2type = N'COLUMN', @level2name = @coluna;
    END
    ELSE
    BEGIN
        IF @coluna IS NULL
            EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = @descricao,
                 @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = @tabela;
        ELSE
            EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = @descricao,
                 @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = @tabela,
                 @level2type = N'COLUMN', @level2name = @coluna;
    END

    SET @i += 1;
END

/* ---------------------------------------------------------------------------
   Conferencia: colunas de dim_, fact_ e etl_ que ficaram sem descricao.
   Tem que voltar vazio. Coluna nova no schema aparece aqui ate ganhar texto.
   (As stagings so tem descricao de tabela: espelham as fatos.)
   --------------------------------------------------------------------------- */
SELECT t.name AS tabela, c.name AS coluna_sem_descricao
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
LEFT JOIN sys.extended_properties ep
       ON ep.class = 1 AND ep.major_id = c.object_id AND ep.minor_id = c.column_id
      AND ep.name = N'MS_Description'
WHERE t.schema_id = SCHEMA_ID(N'dbo')
  AND (t.name LIKE N'dim[_]%' OR t.name LIKE N'fact[_]%' OR t.name LIKE N'etl[_]%')
  AND ep.major_id IS NULL
ORDER BY t.name, c.column_id;

PRINT CONCAT('Descricoes aplicadas: ', @total);
GO
