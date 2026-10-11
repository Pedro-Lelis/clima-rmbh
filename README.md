# Histórico de Clima Dinâmico (RMBH)

Pipeline de dados ponta a ponta: a **API Open-Meteo** alimenta continuamente um
banco analítico em **SQL Server 2025** (star schema), com a coleta orquestrada
pelo **Apache Airflow** numa VPS Linux e painel final em **Power BI**. Cobre
Ibirité, Belo Horizonte e municípios vizinhos da RMBH, de 1940 até hoje.

Projeto de portfólio: ingestão de uma fonte real e viva, modelagem dimensional,
administração do banco, orquestração, qualidade de dados e BI.

## Estado

| Etapa | Situação |
|---|---|
| VPS Contabo (Ubuntu 24.04): SSH só por chave, firewall `ufw` | concluída |
| Acesso ao banco e ao Airflow só pela rede privada Tailscale | concluída |
| SQL Server 2025 Developer, `max server memory` = 4 GB | concluída |
| Modelagem: star schema, 2 dimensões + 4 fatos | concluída |
| Backfill histórico 1940 → hoje (~4,5 milhões de linhas horárias, ~190 mil diárias) | concluído |
| Orquestração com Airflow 3: coleta incremental de hora em hora | em operação |
| Deploy por Git: a VPS roda um clone deste repositório | concluído |
| Checagens de qualidade de dados | em andamento |
| Painel Power BI | planejado |

## Arquitetura

```
                 ┌──────────────────────── VPS Ubuntu 24.04 ─────────────────────────┐
                 │                                                                     │
 Open-Meteo ─────┼─▶ ingestao.py ──▶ stg_* ──MERGE──▶ fact_* / dim_*   (SQL Server)    │
 /v1/archive     │       ▲                                                             │
 /v1/forecast    │       │ dispara                                                     │
                 │   Airflow 3 (DAG clima_incremental, de hora em hora)                │
                 │   cron      (histórico, a cada 6 h)                                 │
                 │       │ estado interno                                              │
                 │       ▼                                                             │
                 │   PostgreSQL (metadados do Airflow)                                 │
                 └───────────────────────────── Tailscale ─────────────────────────────┘
                                                    │
                                    SSMS · Power BI · interface do Airflow
```

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
* **Fuso dos dados**: a API é chamada com `timezone=America/Sao_Paulo`, que na
  Open-Meteo equivale a **UTC-3 fixo** — verificado em 2018-11-04, virada do
  antigo horário de verão: a série voltou com 24 horas, sem hora repetida nem
  faltante. Por isso `(data_id, hora)` é chave segura.
* `eh_previsao` nas tabelas de clima atual separa o que já foi observado do que
  ainda é projeção — permite medir, depois, o **erro da previsão** contra o
  realizado. É um gancho de análise que sai de graça do desenho.

## Escopo geográfico (fase 1)

Ibirité, Belo Horizonte, Contagem, Betim, Nova Lima e Sabará. Códigos IBGE
conferidos na API de localidades do IBGE; coordenadas e altitude na API de
geocoding da própria Open-Meteo. Os seis caem em pontos de grade distintos da
reanálise, então cada município tem série própria. Expansível: basta inserir
linhas em `dim_municipio` — nada mais no schema depende da lista.

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
* **Ano corrente sempre aberto.** O ano em curso nunca é marcado como concluído
  (fica `parcial`): cada rodada pede à API só os dias novos que o ERA5 publicou,
  com 3 dias de sobreposição para absorver revisões da reanálise.
* **Três tipos de falha, três respostas.** Falha de rede e erro 5xx são
  temporários: espera exponencial e nova tentativa. Erro 429 é cota esgotada:
  espera 65 s uma vez (resolve o limite por minuto) e, se persistir, a execução
  para limpa com status `parcial`. Qualquer outro 4xx é erro de parâmetro e
  falha na hora, sem insistir.
* **De-para explícito e verificado.** As colunas estão em português e as
  variáveis da API em inglês; `nomes.py` liga os dois lados, e a ingestão carrega
  o que tiver tradução *e* coluna correspondente.
  `python ingestao/verificar_mapeamento.py` confere esse encaixe offline, contra
  as amostras de payload em `docs/`, e acusa três defeitos distintos: variável
  sem tradução, tradução sem coluna, e coluna órfã.

### O que custou o backfill (medido)

Uma chamada = 1 ano × 6 municípios × 36 variáveis horárias → 10 MB de JSON,
52.560 linhas horárias e 2.190 diárias, em **11,2 s** rodando na VPS (chamada da
API + staging + `MERGE`).

**O limite não foi tempo, foi cota.** Na Open-Meteo uma requisição vale 1
chamada como base, mas conta como várias quando passa de 10 variáveis ou 2
semanas de período. Cada ano de backfill custou **≈ 876 chamadas**; com o plano
gratuito (10.000/dia) couberam ~11 anos por dia, e os 86 anos levaram **~8 dias**
de execuções agendadas, cada uma avançando até a cota acabar e retomando na
seguinte.

## Orquestração com Airflow

A coleta incremental é a DAG [`clima_incremental`](airflow/dags/clima_incremental.py):

* roda no minuto 10 de cada hora, **no horário de Brasília**
  (`DEFAULT_TIMEZONE=America/Sao_Paulo`);
* `max_active_runs=1`: duas execuções nunca se sobrepõem, mesmo que uma atrase;
* 2 novas tentativas com 5 minutos de intervalo, somadas às novas tentativas que
  a própria ingestão já faz contra a API;
* uma tarefa `BashOperator` que executa a ingestão no ambiente Python dela — o
  Airflow tem o seu próprio, e as dependências dos dois não se misturam.

Decisões de infraestrutura:

* **Metadados no PostgreSQL**, não no SQL Server: desde o Airflow 2.9 o SQL Server
  não é suportado como banco de metadados (as DAGs continuam lendo e gravando nele
  normalmente). O PostgreSQL escuta só em `localhost`.
* **`LocalExecutor` com `PARALLELISM=4`**: o padrão de 32 workers era exagero para
  uma ou duas tarefas por hora numa máquina de 8 GB.
* **Serviços do systemd** a partir de um único template,
  [`airflow/systemd/airflow@.service`](airflow/systemd/airflow@.service): cada
  componente (`api-server`, `scheduler`, `dag-processor`, `triggerer`) é uma
  instância que sobe no boot, reinicia em caso de falha e para por inteiro —
  sem deixar processos órfãos.
* **As DAGs vivem neste repositório** (`DAGS_FOLDER` aponta para o clone na VPS):
  uma DAG nova chega ao Airflow com `git pull`.

O backfill do histórico ainda roda pelo cron, a cada 6 horas; a próxima DAG o
substitui.

## Acesso e segurança

* **Banco e Airflow fora da internet.** As portas 1433 (SQL Server) e 8080
  (interface do Airflow) só aceitam conexões pela interface da rede privada
  [Tailscale](https://tailscale.com). SSMS, Power BI e navegador conectam pelo IP
  privado da VPS na Tailscale.
* **SSH só por chave.** O login por senha está desligado em
  `/etc/ssh/sshd_config.d/00-hardening.conf`. O prefixo `00-` importa: a imagem
  da Contabo traz um `50-cloud-init.conf` com `PasswordAuthentication yes`, e no
  sshd vale a primeira ocorrência de cada diretiva — uma edição no arquivo
  principal era silenciosamente ignorada.
* **Nenhum segredo no repositório.** As senhas vivem só nos arquivos de ambiente
  da VPS (`.env` da ingestão e `airflow.env`, ambos `chmod 600` e fora do Git); o
  repositório traz apenas `.env.exemplo`.
* **Login do Airflow.** O Airflow 3 usa por padrão o `SimpleAuthManager`, que
  guarda a senha do administrador em texto num arquivo local (`chmod 600`). É
  aceitável aqui porque a interface só é alcançável pela rede privada; num
  ambiente compartilhado, o caminho seria um gerenciador de autenticação de
  verdade (FAB ou Keycloak).

## Passo a passo

**1. Acesso.** Instale o Tailscale na VPS e na máquina local, com a mesma conta,
e desative a expiração de chave da VPS no painel. No firewall da VPS:

```bash
sudo ufw allow in on tailscale0 to any port 1433 proto tcp && sudo ufw allow in on tailscale0 to any port 8080 proto tcp
```

**2. Schema.** No SSMS, conectado a `<IP_TAILSCALE_DA_VPS>`, execute os arquivos
de `sql/` em ordem numérica. Na VPS, o equivalente é
`export SA_PASSWORD='...' && ./sql/deploy.sh`.

**3. Código na VPS.**

```bash
git clone https://github.com/Pedro-Lelis/clima-rmbh.git ~/clima
```

**4. Ambiente da ingestão.** O Ubuntu 24.04 recusa `pip install` no Python do
sistema (PEP 668); o virtualenv isola as dependências do projeto:

```bash
sudo apt install -y python3-venv unixodbc-dev && cd ~/clima/ingestao && python3 -m venv .venv && ./.venv/bin/pip install -r requirements.txt
```

**5. Credenciais da ingestão.** A senha fica entre aspas simples no `.env`,
porque o arquivo é lido pelo shell:

```bash
cd ~/clima/ingestao && cp .env.exemplo .env && nano .env && chmod 600 .env
```

**6. Teste curto** — um ano só, valida a gravação de ponta a ponta:

```bash
cd ~/clima/ingestao && set -a && . ./.env && set +a && ./.venv/bin/python ingestao.py backfill --inicio 2025 --fim 2025
```

**7. Histórico agendado.** O crontab segue o fuso da VPS:

```bash
crontab ~/clima/ingestao/clima-backfill.cron
```

**8. Airflow.**

Banco de metadados — crie, no `psql` como usuário `postgres`, um usuário
`airflow` e um banco `airflow_meta` **com `OWNER airflow`** (a partir do
PostgreSQL 15, só o dono do banco cria tabelas no schema `public`):

```bash
sudo apt install -y postgresql
```

Instalação num ambiente próprio, com o arquivo de *constraints* oficial (as
versões testadas juntas):

```bash
mkdir -p ~/airflow && cd ~/airflow && python3 -m venv .venv && ./.venv/bin/pip install "apache-airflow[postgres]==3.3.2" --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-3.3.2/constraints-3.12.txt"
```

Configuração em `~/airflow/airflow.env` (`chmod 600`). A senha do PostgreSQL vai
**codificada para URL** (`@` vira `%40`, e assim por diante):

```
AIRFLOW_HOME=/home/<usuario>/airflow
AIRFLOW__CORE__EXECUTOR=LocalExecutor
AIRFLOW__CORE__PARALLELISM=4
AIRFLOW__CORE__LOAD_EXAMPLES=False
AIRFLOW__CORE__DAGS_FOLDER=/home/<usuario>/clima/airflow/dags
AIRFLOW__CORE__DEFAULT_TIMEZONE=America/Sao_Paulo
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN='postgresql+psycopg2://airflow:<SENHA_CODIFICADA>@localhost:5432/airflow_meta'
```

Tabelas do Airflow e serviços:

```bash
set -a && . ~/airflow/airflow.env && set +a && ~/airflow/.venv/bin/airflow db migrate
```

```bash
sudo cp ~/clima/airflow/systemd/airflow@.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now airflow@api-server airflow@scheduler airflow@dag-processor airflow@triggerer
```

Toda DAG nova nasce pausada: dispare uma execução manual, confira o log da tarefa
e só então despause.

**9. Atualizações.** Toda mudança chega pelo Git:

```bash
cd ~/clima && git pull
```

Se o arquivo do systemd mudou, copie de novo e rode `daemon-reload`; se o
`.cron` mudou, reinstale o crontab.

## Lições aprendidas

* **`SELECT … INTO` copia nulabilidade, mas não `DEFAULT`** — as stagings
  nasceram com `dt_carga NOT NULL` sem default, e a primeira carga falhou.
* **`fast_executemany` deduz o tipo pela primeira linha** — um `NULL` ali faz o
  driver assumir texto. Resolvido declarando os tipos com `setinputsizes`.
* **Cota de API pode ser ponderada** — o gargalo do backfill foi a cota, não o
  tempo.
* **`NULL` não é zero** — as primeiras horas de 1940 vêm nulas nas variáveis
  acumuladas (chuva, radiação, rajada). Trocar por 0 registraria dia seco num dia
  chuvoso.
* **Processos de um terminal não sobrevivem ao terminal** — o `airflow standalone`
  deixou 32 workers órfãos ao fechar a sessão SSH, e eles ignoravam `SIGTERM`.
  Serviços do systemd resolvem isso por construção.
* **Commit publicado não se edita** — corrige-se com um commit novo.

## Ressalva sobre os dados

Open-Meteo entrega **reanálise e modelo numérico** em grade de ~9-25 km, não
leitura de estação física no ponto exato do município. É o dado certo para série
histórica longa e homogênea, e essa distinção deve aparecer no painel.

## Roteiro

**Para fechar a v1:** checagens de qualidade como tarefa da DAG · DAG do
histórico (aposenta o cron) · backup com restore testado · dicionário de dados ·
painel Power BI.

**Fase 2:** busca de "dias análogos" com o tipo `VECTOR` do SQL Server 2025 · API
para servir os dados, em container Docker · avaliação do Metabase como
alternativa ao Power BI · extensão com qualidade do ar (PM2.5, PM10, ozônio,
pólen).

## Estrutura

```
sql/        DDL numerado (01..09) + deploy.sh
ingestao/   open_meteo.py (API) · nomes.py (de-para) · banco.py (staging + MERGE)
            ingestao.py (CLI) · verificar_mapeamento.py · .env.exemplo
            clima-backfill.cron
airflow/    dags/clima_incremental.py · systemd/airflow@.service
docs/       amostras de payload da API
```
