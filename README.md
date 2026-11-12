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
| Orquestração com Airflow 3: incremental de hora em hora, histórico diário | em operação |
| Backup diário com verificação, cópia no Google Drive e restore testado | em operação |
| Alerta de falha das DAGs pelo Telegram | em operação |
| Deploy por Git: a VPS roda um clone deste repositório | concluído |
| Checagens de qualidade: completude, nulos, faixas de valores e atualidade | em operação |
| Painel Power BI | planejado |

## Arquitetura

```
                 ┌───────────────────────── VPS Ubuntu 24.04 ──────────────────────────┐
                 │                                                                     │
 Open-Meteo ─────┼─▶ ingestao.py ──▶ stg_* ──MERGE──▶ fact_* / dim_*   (SQL Server)    │
 /v1/archive     │       ▲                                                             │
 /v1/forecast    │       │ dispara                                                     │
                 │   Airflow 3                                                         │
                 │     clima_incremental   de hora em hora, + 3 checagens de qualidade │
                 │     clima_historico     diária, ERA5 + checagem de atualidade       │
                 │     manutencao_backup   diária: BACKUP ─▶ VERIFYONLY ─▶ rclone ─────┼──▶ Google Drive
                 │     falha em qualquer tarefa ───────────────────────────────────────┼──▶ Telegram
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
reanálise, então cada município tem série própria — conferido nos dados: nos
dias com chuva, Belo Horizonte e Betim registram o mesmo total em só 6% deles.
Expansível: basta inserir
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

Duas DAGs de coleta e uma de manutenção. A coleta incremental é a DAG
[`clima_incremental`](airflow/dags/clima_incremental.py):

* roda no minuto 10 de cada hora, **no horário de Brasília**
  (`DEFAULT_TIMEZONE=America/Sao_Paulo`);
* `max_active_runs=1`: duas execuções nunca se sobrepõem, mesmo que uma atrase;
* 2 novas tentativas com 5 minutos de intervalo, somadas às novas tentativas que
  a própria ingestão já faz contra a API;
* uma tarefa `BashOperator` que executa a ingestão no ambiente Python dela — o
  Airflow tem o seu próprio, e as dependências dos dois não se misturam;
* três checagens de qualidade em paralelo logo depois da carga — completude,
  nulos e faixas de valores (abaixo).

### Checagem de completude

A tarefa `checar_completude` é um `SQLCheckOperator` que roda
[`checar_completude.sql`](airflow/dags/sql/checar_completude.sql) com um login só
de leitura. Ela conta, para cada município, as linhas gravadas desde o início da
última execução incremental e exige 552 — (7 dias passados + 16 de previsão) ×
24 horas. Devolve uma linha só: 1 passa, qualquer outra coisa falha a tarefa.

* **Parte da `dim_municipio`, não da fato**, com `LEFT JOIN` e o filtro de data
  no `ON`: um município sem nenhuma linha aparece com 0 em vez de sumir do
  resultado. No `WHERE`, o filtro desfaria o `LEFT JOIN`.
* **Conta os municípios errados e compara com 0.** Comparar a soma das linhas com
  um total fixo deixaria um município com horas a menos compensar outro com
  horas a mais, e quebraria ao entrar um município novo.
* **Não filtra a execução por `status`.** Quando a cota da API acaba, a ingestão
  para limpa com status `parcial` e código de saída 0 — para o Airflow, tarefa
  verde. Filtrar `sucesso` faria a checagem conferir a carga anterior, completa,
  e o buraco passaria em silêncio.
* **Sem novas tentativas**: uma checagem que falha não melhora ao repetir.
* Testada nos três cenários: tudo certo, tudo faltando e **um município errado
  no meio dos certos** — o caso que uma lógica invertida deixa passar.

As duas checagens seguintes seguem o mesmo padrão: olham só a última carga,
contam o que está errado e comparam com 0, sem novas tentativas e testadas nos
mesmos três cenários.

### Checagem de nulos

A tarefa `checar_nulos` roda [`checar_nulos.sql`](airflow/dags/sql/checar_nulos.sql):
desfaz as 42 colunas de medida em linhas com `CROSS APPLY (VALUES …)` — cada valor
convertido para `SQL_VARIANT`, já que os tipos diferem — e conta os valores
preenchidos de cada coluna. Falha se alguma coluna vier **100% nula**.

* **Por que não "nenhum nulo"**: as 9 colunas de solo vêm nulas, legitimamente,
  nas últimas ~26 horas do horizonte de previsão. Exigir zero nulos daria alarme
  a toda hora; uma coluna inteira vazia é que indica defeito — campo renomeado na
  API, de-para quebrado.
* **Uma passada só pela tabela**, em vez de uma consulta por coluna.

### Checagem de faixas

A tarefa `checar_faixas` roda [`checar_faixas.sql`](airflow/dags/sql/checar_faixas.sql)
e devolve uma linha com uma coluna por família de regras (16 ao todo). Quando
falha, o log mostra a linha inteira, e dá para ver qual família quebrou.

* **Limites físicos vêm de recordes mundiais**, não do clima de BH: um valor real
  nunca passa deles, mas um erro de pipeline passa — temperatura em Kelvin, vento
  em outra unidade, coluna trocada no de-para. Plausibilidade regional fica fora
  da DAG, para não virar alarme no primeiro dia extremo.
* **Coerência entre colunas**: chuva + pancadas + neve = precipitação; radiação
  direta + difusa = ondas curtas; ponto de orvalho não passa da temperatura; o
  que chega ao chão não passa do que chega ao topo da atmosfera.
* **Tolerâncias medidas, não chutadas**: a exploração mostrou que o modelo de
  previsão chega a dar ponto de orvalho 0,7 °C acima da temperatura, e que as
  somas divergem por arredondamento na ponta do horizonte.

**Primeiro alarme real (12/11/2026).** A `coerencia_radiacoes` falhou às 00:10,
01:10 e 02:10, e passou sozinha a partir das 03:10. A staging é zerada a cada
carga e o `MERGE` sobrescreve a fato, então os valores daquelas horas já não
existiam para conferir. A investigação foi pelo que restou: na carga seguinte, a
maior divergência entre direta + difusa e ondas curtas era **0,00 em todos os 23
dias e nos 6 municípios**. O ruído normal é zero e a tolerância (1 W/m²) tem
folga total; o erro foi uma inconsistência transitória na própria Open-Meteo,
corrigida na fonte em ~3 horas. A regra ficou como estava. Se repetir, o próximo
passo é guardar as linhas que violaram numa tabela de quarentena antes do
`MERGE` seguinte, para medir o tamanho real do erro.

### Histórico

A DAG [`clima_historico`](airflow/dags/clima_historico.py) roda `ingestao.py
backfill` uma vez por dia, às 04h20 — longe do backup (03h30) e do incremental
(minuto 10). Ela substituiu o cron que fez a carga de 1940 em diante.

* **Uma vez por dia basta.** O cron rodava a cada 6 horas por causa da cota,
  durante os 86 anos de backfill. Com o histórico completo, cada execução pula os
  anos já carregados e busca só a ponta nova do ano corrente — alguns dias, uma
  fração da cota.
* **Sem `catchup` por ano.** O progresso já é controlado pela `etl_backfill_ano`;
  dar ao Airflow um controle paralelo do mesmo estado (uma execução por ano) só
  criaria duas fontes de verdade para discordar.
* **Troca sem sobreposição.** O cron e a DAG gravam na mesma staging, e duas
  cargas simultâneas misturariam as linhas. A ordem foi: conferir que nenhum
  backfill estava rodando, tirar a linha do crontab, e só então despausar a DAG.

A tarefa `checar_atualidade` roda
[`checar_atualidade.sql`](airflow/dags/sql/checar_atualidade.sql) depois da carga.
O ERA5 sai com atraso e a ingestão pede só até hoje − 6, então uma carga boa
deixa o último registro em hoje − 6; a checagem exige que nenhum município esteja
antes de **hoje − 7**, um dia de tolerância para atraso pontual da fonte.

* **Hora sem dado não conta.** Um dia que o ERA5 ainda não publicou pode chegar
  com as medidas nulas; o `MAX` só considera horas com `temperatura_2m`
  preenchida.
* **`MAX` de nada é `NULL`, não 0.** Diferente do `COUNT` da completude, o `MAX`
  de um município sem linhas devolve `NULL`, e `NULL < data` não é verdadeiro —
  sem um `IS NULL` explícito, o município vazio passaria como em dia. Um teste
  dedicado a esse caso confirmou a regra.
* **A checagem depende da carga** (`carregar >> checar`). Sem a dependência, as
  duas rodariam juntas e a checagem conferiria os dados de ontem — que, com um dia
  de tolerância, passariam.

### Backup

A DAG [`manutencao_backup`](airflow/dags/manutencao_backup.py) roda todo dia às
03h30, sem custo extra de hospedagem:

1. `BACKUP DATABASE … WITH INIT, COMPRESSION, CHECKSUM` — 1,1 GB de dados viram
   um arquivo de ~330 MB;
2. `RESTORE VERIFYONLY … WITH CHECKSUM` — confere o arquivo antes de confiar nele;
3. `rclone copy` para uma pasta no Google Drive;
4. limpeza por idade: 2 cópias na VPS, 7 no Drive.

Cada passo só roda se o anterior der certo — a limpeza nunca apaga cópia antiga
sem que a nova tenha chegado ao Drive.

* **`INIT`** evita que duas execuções no mesmo dia empilhem dois backups no mesmo
  arquivo (o `VERIFYONLY` conferiria só o primeiro).
* **`autocommit` e mensagens consumidas.** O SQL Server não aceita `BACKUP`
  dentro de transação, e manda o progresso como mensagens que o pyodbc precisa
  ler até o fim — senão a conexão pode fechar com o backup pela metade.
* **Restore testado de verdade**: uma cópia baixada do Drive foi restaurada como
  outro banco e conferida contra o original, contagem a contagem. Backup que
  nunca foi restaurado é só uma hipótese.

### Alerta de falha

Qualquer tarefa que falhe de vez, depois das novas tentativas, manda uma mensagem
pelo Telegram ([`comum/alertas.py`](airflow/dags/comum/alertas.py), ligado como
`on_failure_callback` em todas as DAGs). O envio tem tempo limite e uma segunda
tentativa, e o log registra só o tipo de erro — a mensagem de erro da biblioteca
traz a URL, e a URL traz o token do bot.

Limite conhecido: se a VPS ou o scheduler caírem, nenhuma tarefa roda e nenhum
alerta sai. Cobrir esse caso exige um monitor externo, que estranhe a *ausência*
de sinal.

### Infraestrutura

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
  uma DAG nova chega ao Airflow com `git pull`. O `.airflowignore` tira a pasta
  `comum/` (código compartilhado, sem DAG) da varredura.
* **Conexões e variáveis por ambiente** (`AIRFLOW_CONN_*`, `AIRFLOW_VAR_*` no
  `airflow.env`), não pela interface: ficam fora do banco de metadados e fora do
  Git. O driver ODBC vai em `hook_params` na própria tarefa.
* **Servidor no fuso de Brasília** (`America/Sao_Paulo`), o mesmo dos dados: a
  imagem da VPS veio no horário europeu, e a ingestão comparava horas de
  Brasília com o relógio da máquina para decidir o que era previsão.

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
* **Um login por função, com o mínimo de permissão.** O Airflow não usa o `sa`:
  a checagem roda com um login que só lê (`db_datareader`), e o backup com um
  que só faz backup (`db_backupoperator`, mais `CREATE ANY DATABASE`, exigido
  pelo `RESTORE VERIFYONLY`).
* **Acesso restrito ao Drive.** O rclone usa um app OAuth próprio, com o escopo
  `drive.file`: ele enxerga só os arquivos que ele mesmo criou, não o Drive
  inteiro.
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

**7. Fuso da VPS.** A ingestão decide o que é previsão comparando as horas de
Brasília com o relógio da máquina — acerte-o para o mesmo fuso dos dados:

```bash
sudo timedatectl set-timezone America/Sao_Paulo
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

O provider ODBC, para as tarefas que falam direto com o SQL Server:

```bash
~/airflow/.venv/bin/pip install apache-airflow-providers-odbc --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-3.3.2/constraints-3.12.txt"
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
AIRFLOW_CONN_CLIMA_SQLSERVER='{"conn_type":"odbc","host":"localhost","schema":"ClimaRMBH","login":"<LOGIN_LEITURA>","password":"<SENHA>","extra":{"TrustServerCertificate":"yes"}}'
AIRFLOW_CONN_CLIMA_SQLSERVER_BACKUP='{"conn_type":"odbc","host":"localhost","schema":"ClimaRMBH","login":"<LOGIN_BACKUP>","password":"<SENHA>","extra":{"TrustServerCertificate":"yes"}}'
AIRFLOW_VAR_TELEGRAM_TOKEN='<TOKEN_DO_BOT>'
AIRFLOW_VAR_TELEGRAM_CHAT_ID='<CHAT_ID>'
```

O token vem do @BotFather; o `chat_id`, de `getUpdates` na API do bot, depois de
mandar uma mensagem a ele. Com `token` no nome, o Airflow esconde o valor nos
logs.

Tabelas do Airflow e serviços:

```bash
set -a && . ~/airflow/airflow.env && set +a && ~/airflow/.venv/bin/airflow db migrate
```

```bash
sudo cp ~/clima/airflow/systemd/airflow@.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now airflow@api-server airflow@scheduler airflow@dag-processor airflow@triggerer
```

Toda DAG nova nasce pausada: dispare uma execução manual, confira o log da tarefa
e só então despause. Com `catchup=False`, despausar já dispara o último intervalo
agendado que passou.

Num banco novo, o histórico completo (1940 → hoje) sai pela própria
`clima_historico`: cada execução avança até a cota da API acabar e a seguinte
retoma pela `etl_backfill_ano`. Disparos manuais ao longo do dia aceleram a carga.

**9. Backup.** Pasta do SQL Server com o grupo `mssql` herdado pelos arquivos
novos (`2770`), e o usuário do Airflow no grupo, para a limpeza conseguir apagar
cópias antigas — os serviços do Airflow precisam ser reiniciados para ganhar o
grupo:

```bash
sudo mkdir -p /var/opt/mssql/backup && sudo chown mssql:mssql /var/opt/mssql/backup && sudo chmod 2770 /var/opt/mssql/backup && sudo usermod -aG mssql <usuario>
```

Depois, instale o rclone e crie com `rclone config` um remote `clima_drive` para
o Google Drive, usando um client ID próprio (o compartilhado do rclone esbarra
em cota) e o escopo `drive.file`.

**10. Atualizações.** Toda mudança chega pelo Git:

```bash
cd ~/clima && git pull
```

DAGs e checagens novas entram sozinhas; se o arquivo do systemd mudou, copie de
novo e rode `daemon-reload`.

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
* **O fuso do servidor faz parte dos dados** — com a VPS no horário europeu, a
  ingestão marcava como previsão horas que já tinham passado em Brasília.
* **Checagem precisa ser testada falhando** — e não só com tudo certo ou tudo
  errado: uma versão com a lógica invertida passava nesses dois testes e
  aprovava a carga com um município faltando.
* **Alarme que tocou se investiga antes de mexer na regra** — a checagem de
  faixas falhou três horas seguidas e depois passou sozinha. Medir a folga
  mostrou divergência zero nos dados normais: o erro estava na fonte, não na
  tolerância. Afrouxar a regra só esconderia o próximo.
* **Checagem que falha deveria guardar a evidência** — com staging zerada e
  `MERGE` sobrescrevendo, o dado que disparou o alarme some na carga seguinte.
* **Tolerância pode esconder uma dependência faltando** — sem `carregar >>
  checar`, a checagem de atualidade rodaria antes da carga e aprovaria os dados
  de ontem, porque um dia de atraso está dentro da regra.
* **Troca de agendador: desliga o antigo antes de ligar o novo** — um intervalo
  sem nenhum dos dois não custa nada; os dois juntos gravando na mesma staging,
  sim.
* **Credencial compartilhada tem cota compartilhada** — o client ID padrão do
  rclone devolvia erro de cota no Google; com um app OAuth próprio, o envio
  passou.
* **Commit publicado não se edita** — corrige-se com um commit novo.

## Ressalva sobre os dados

Open-Meteo entrega **reanálise e modelo numérico** em grade de ~9-25 km, não
leitura de estação física no ponto exato do município. É o dado certo para série
histórica longa e homogênea, e essa distinção deve aparecer no painel.

## Roteiro

**Para fechar a v1:** dicionário de dados · painel Power BI.

**Operação:** monitor externo, para avisar se a própria VPS parar · tabela de
quarentena para as linhas que falharem nas checagens.

**Fase 2:** busca de "dias análogos" com o tipo `VECTOR` do SQL Server 2025 · API
para servir os dados, em container Docker · avaliação do Metabase como
alternativa ao Power BI · extensão com qualidade do ar (PM2.5, PM10, ozônio,
pólen).

## Estrutura

```
sql/        DDL numerado (01..09) + deploy.sh
ingestao/   open_meteo.py (API) · nomes.py (de-para) · banco.py (staging + MERGE)
            ingestao.py (CLI) · verificar_mapeamento.py · .env.exemplo
airflow/    dags/clima_incremental.py · clima_historico.py · manutencao_backup.py
            dags/sql/checar_completude.sql · checar_nulos.sql · checar_faixas.sql
                     checar_atualidade.sql
            dags/comum/alertas.py · systemd/airflow@.service
analises/   consultas de exploração (SQL dinâmico)
docs/       amostras de payload da API
```
