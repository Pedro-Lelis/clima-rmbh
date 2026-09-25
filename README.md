# Histórico de Clima Dinâmico (RMBH)

Banco analítico em **SQL Server 2025 Developer** (VPS Contabo, Ubuntu) alimentado
continuamente pela **API Open-Meteo**, com painel final em **Power BI**.
Projeto de portfólio: praticar SQL Server (DBA) + BI sobre uma fonte real e viva.

## Estado

| Etapa | Situação |
|---|---|
| VPS provisionada e endurecida (SSH por chave, `ufw`) | concluída |
| SQL Server instalado, `max server memory` = 6 GB, porta 1433 | concluída |
| Modelagem: star schema, 2 dimensões + 4 fatos | concluída |
| **DDL completo (`sql/`)** | **escrito, falta aplicar no servidor** |
| **Ingestão: backfill + incremental (`ingestao/`)** | **escrita, falta rodar na VPS** |
| Painel Power BI | pendente |

## Modelo de dados

```
                 dim_municipio                      dim_data
                (municipio_id)                      (data_id)
                       |                                |
        +--------------+----------------+---------------+--------------+
        |              |                |               |              |
fact_clima_historico_hora   fact_clima_historico_dia   fact_clima_atual_hora   fact_clima_atual_dia
      /v1/archive                /v1/archive               /v1/forecast            /v1/forecast
    município x dia x hora     município x dia        município x dia x hora    município x dia
```

Quatro fatos, não uma: **origem** (reanálise histórica × modelo de previsão) e
**grão** (hora × dia) são dimensões diferentes do problema.

* **Grão separado** — somar/mediar linhas horárias e diárias na mesma tabela
  distorce qualquer agregação, porque a contagem de linhas por município/dia
  seria diferente entre os dois tipos de registro.
* **Origem separada** — não é só metadado. As profundidades de solo *mudam* entre
  as fontes: o ERA5 (histórico) mede camadas de 0-7 / 7-28 / 28-100 / 100-255 cm,
  o modelo de previsão mede temperatura em 0 / 6 / 18 / 54 cm e umidade em
  0-1 / 1-3 / 3-9 / 9-27 / 27-81 cm. Além disso o forecast traz medidas que o
  archive não tem (visibilidade, índice UV, probabilidade de chuva) e seus valores
  são *revisados* a cada coleta, enquanto a reanálise é estável.

### Decisões de modelagem

* `dim_data.data_id` é `AAAAMMDD` (*smart key*): inteiro pequeno, legível e já
  ordenado. Carregada de 1940 (início do ERA5) a 2035 (folga para previsões).
* **Tudo em português**, incluindo as colunas de medida (`temperatura_2m`,
  `rajada_vento_10m`, `evapotranspiracao_et0`). Sem acento: nome acentuado é
  válido no SQL Server, mas atrapalha script, driver e exportação — o rótulo com
  acento é trabalho do Power BI. O preço dessa escolha é o de-para em
  [`ingestao/nomes.py`](ingestao/nomes.py), fonte única da tradução: variável
  nova pedida à API precisa ser cadastrada lá, senão a carga a ignora em
  silêncio. `verificar_mapeamento.py` existe para acusar esse esquecimento.
* `DECIMAL` em vez de `FLOAT`: os valores chegam com 1-3 casas decimais e somas de
  chuva/radiação precisam ser exatas e reproduzíveis.
* PK composta pelas chaves naturais (`municipio_id, data_id[, hora]`), sem
  surrogate nas fatos — é o que torna a carga **idempotente**: reprocessar o mesmo
  período atualiza a linha em vez de duplicá-la.
* Índice extra `(data_id, municipio_id)` cobre o filtro típico do painel
  ("um período, todos os municípios"), oposto à ordem da PK.
* **Fuso**: a API é chamada com `timezone=America/Sao_Paulo`, que na Open-Meteo
  equivale a **UTC-3 fixo** — verificado em 2018-11-04, virada do antigo horário
  de verão: a série voltou com 24 horas, sem hora repetida nem faltante. Por isso
  `(data_id, hora)` é chave segura.
* `eh_previsao` nas tabelas de clima atual separa o que já foi observado do que
  ainda é projeção — permite medir, depois, o **erro da previsão** contra o
  realizado. É um gancho de análise que sai de graça do desenho.

## Escopo geográfico (fase 1)

Ibirité, Belo Horizonte, Contagem, Betim, Nova Lima e Sabará. Códigos IBGE
conferidos na API de localidades do IBGE; coordenadas e altitude na API de
geocoding da própria Open-Meteo. Expansível: basta inserir linhas em
`dim_municipio` — nada mais no schema depende da lista.

## Ingestão

Dois modos, um script:

```bash
python ingestao.py backfill        # /v1/archive, 1940 -> hoje, ano a ano, retomável
python ingestao.py incremental     # /v1/forecast, últimos 7 dias + 16 à frente
```

* **Carga idempotente.** Cada lote vai para uma `stg_*` e entra na tabela final
  por um único `MERGE` sobre a chave natural. Rodar de novo o mesmo período
  corrige as linhas, nunca duplica — é o que permite o incremental reescrever a
  semana anterior a cada hora, conforme a previsão vira realizado.
* **Backfill retomável.** `etl_backfill_ano` registra município × ano concluído;
  uma queda no meio dos 86 anos é retomada de onde parou. `etl_execucao` guarda
  o log de cada rodada, com status e contagem de linhas.
* **Resiliente ao limite da API.** 429 e 5xx entram em espera exponencial
  (5s → 15s → 45s → 135s); erro de parâmetro falha na hora, sem insistir.
* **De-para explícito e verificado.** As colunas estão em português e as
  variáveis da API em inglês; `nomes.py` liga os dois lados, e a ingestão carrega
  o que tiver tradução *e* coluna correspondente.
  `python ingestao/verificar_mapeamento.py` confere esse encaixe offline, contra
  as amostras de payload em `docs/`, e acusa três defeitos distintos: variável
  sem tradução, tradução sem coluna, e coluna órfã.

### O que esperar do backfill (medido)

Uma chamada = 1 ano × 6 municípios × 36 variáveis horárias → 10 MB de JSON,
52.560 linhas horárias e 2.190 diárias.

Medido **rodando na VPS**: **11,2 s por ano**, ponta a ponta (chamada da API +
carga na staging + `MERGE`). Da máquina local no Brasil a mesma chamada leva
~90 s, quase tudo latência — a VPS está na Europa, ao lado dos servidores da
Open-Meteo.

**O que limita o backfill não é tempo, é cota.** Na Open-Meteo uma requisição
vale 1 chamada como base, mas conta como várias quando passa de 10 variáveis ou
2 semanas de período. Nossa chamada de 1 ano × 6 municípios × ~56 variáveis vale
**≈ 876 chamadas**. Com o plano gratuito (600/min, 5.000/hora, 10.000/dia),
cabem **~11 anos de backfill por dia** — os 86 anos levam **~8 dias**.

Por isso o backfill é agendado, não disparado de uma vez: cada execução avança o
que a cota permitir e para limpa no 429, com status `parcial` em `etl_execucao` e
saída 0. A execução seguinte retoma pelo `etl_backfill_ano`. Depois que tudo
estiver carregado, as rodadas viram no-op.

Dados de 1940 vêm completos — inclusive solo e radiação, sem coluna vazia.

## Passo a passo

**1. Aplicar o schema** (SSMS do Windows, conectado a `<IP_DA_VPS>`):
abra os arquivos de `sql/` na ordem numérica e execute cada um.
Na VPS, o equivalente é `export SA_PASSWORD='...' && ./deploy.sh`.

**2. Copiar `ingestao/` para a VPS** (do PowerShell, no Windows):

```powershell
scp -i "$env:USERPROFILE\.ssh\id_ed25519" -r "F:\Projeto-weather-history-db\ingestao" pedro@<IP_DA_VPS>:~/clima-ingestao
```

**3. Preparar o ambiente na VPS**. O Ubuntu 24.04 recusa `pip install` no Python
do sistema (PEP 668) — pacote instalado por fora do apt pode quebrar ferramentas
do próprio SO. O virtualenv isola as dependências do projeto:

```bash
sudo apt install -y python3-venv unixodbc-dev build-essential && cd ~/clima-ingestao && python3 -m venv .venv && ./.venv/bin/pip install -r requirements.txt
```

**4. Configurar credenciais** (a senha do `sa` fica só no `.env`, fora do
versionamento):

```bash
cd ~/clima-ingestao && cp .env.exemplo .env && nano .env && chmod 600 .env
```

**5. Teste curto antes dos 86 anos** — um ano só, ~2 minutos, valida a gravação
de ponta a ponta antes de disparar a carga longa:

```bash
cd ~/clima-ingestao && set -a && . ./.env && set +a && ./.venv/bin/python ingestao.py backfill --inicio 2025 --fim 2025
```

**6. Backfill completo**: instalar `clima-backfill.cron` no `crontab -e`. Roda a
cada 6 h, avança até a cota acabar e retoma sozinho; ~8 dias para os 86 anos.
Para acompanhar: `tail -f ~/clima-ingestao/backfill.log`.

**7. Coleta contínua**: instalar `clima-incremental.cron` no `crontab -e`.

## Ressalva sobre os dados

Open-Meteo entrega **reanálise e modelo numérico** em grade de ~9-25 km, não
leitura de estação física no ponto exato do município. É o dado certo para série
histórica longa e homogênea, e essa distinção deve aparecer no painel.

## Estrutura

```
sql/        DDL numerado (01..08) + deploy.sh
ingestao/   open_meteo.py (API) · nomes.py (de-para) · banco.py (staging + MERGE)
            ingestao.py (CLI) · verificar_mapeamento.py · .env.exemplo
            clima-backfill.cron · clima-incremental.cron
docs/       amostras de payload da API
```
