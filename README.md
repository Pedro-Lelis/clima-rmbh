# Histórico de Clima Dinâmico (RMBH)

Banco analítico em **SQL Server 2025 Developer** (VPS Contabo, Ubuntu 24.04)
alimentado continuamente pela **API Open-Meteo**, com painel final em **Power BI**.
Projeto de portfólio de dados ponta a ponta: ingestão de uma fonte real e viva,
modelagem dimensional, administração do banco, qualidade de dados e BI.

## Estado

| Etapa | Situação |
|---|---|
| VPS Contabo: SSH só por chave, firewall `ufw` | concluída |
| Acesso ao banco pela rede privada Tailscale (porta 1433 fechada para a internet) | concluída |
| SQL Server 2025 Developer, `max server memory` = 6 GB | concluída |
| Modelagem: star schema, 2 dimensões + 4 fatos | concluída |
| Backfill histórico 1940 → hoje (~4,5 milhões de linhas horárias, ~190 mil diárias) | concluído |
| Coleta contínua: previsão de hora em hora, histórico a cada 6 h | em operação |
| Deploy por Git: a VPS roda um clone deste repositório | concluído |
| Checagens de qualidade de dados | em andamento |
| Orquestração com Airflow | planejada |
| Painel Power BI | planejado |

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

## Acesso e segurança

* **Banco fora da internet.** A porta 1433 só aceita conexões pela interface da
  rede privada [Tailscale](https://tailscale.com) (`ufw allow in on tailscale0`).
  SSMS e Power BI conectam pelo IP privado da VPS na Tailscale.
* **SSH só por chave.** O login por senha está desligado em
  `/etc/ssh/sshd_config.d/00-hardening.conf`. O prefixo `00-` importa: a imagem
  da Contabo traz um `50-cloud-init.conf` com `PasswordAuthentication yes`, e no
  sshd vale a primeira ocorrência de cada diretiva — uma edição no arquivo
  principal era silenciosamente ignorada.
* **Nenhum segredo no repositório.** A senha do banco vive só no `.env` da VPS
  (`chmod 600`, fora do Git); o repositório traz apenas `.env.exemplo`.

## Passo a passo

**1. Acesso.** Instale o Tailscale na VPS e na máquina local, com a mesma conta,
e desative a expiração de chave da VPS no painel. No firewall da VPS:

```bash
sudo ufw allow in on tailscale0 to any port 1433 proto tcp
```

**2. Schema.** No SSMS, conectado a `<IP_TAILSCALE_DA_VPS>`, execute os arquivos
de `sql/` em ordem numérica. Na VPS, o equivalente é
`export SA_PASSWORD='...' && ./sql/deploy.sh`.

**3. Código na VPS.**

```bash
git clone https://github.com/Pedro-Lelis/clima-rmbh.git ~/clima
```

**4. Ambiente Python.** O Ubuntu 24.04 recusa `pip install` no Python do sistema
(PEP 668); o virtualenv isola as dependências do projeto:

```bash
sudo apt install -y python3-venv unixodbc-dev && cd ~/clima/ingestao && python3 -m venv .venv && ./.venv/bin/pip install -r requirements.txt
```

**5. Credenciais.** A senha fica entre aspas simples no `.env`, porque o arquivo
é lido pelo shell:

```bash
cd ~/clima/ingestao && cp .env.exemplo .env && nano .env && chmod 600 .env
```

**6. Teste curto** — um ano só, valida a gravação de ponta a ponta:

```bash
cd ~/clima/ingestao && set -a && . ./.env && set +a && ./.venv/bin/python ingestao.py backfill --inicio 2025 --fim 2025
```

**7. Agendamento.** Instala os dois crons de uma vez (instalar um sozinho
apagaria o outro). Os horários seguem o fuso da VPS:

```bash
cd ~/clima/ingestao && cat clima-backfill.cron clima-incremental.cron | crontab -
```

**8. Atualizações.** Toda mudança chega pelo Git; se algum `.cron` mudou,
reinstale o crontab:

```bash
cd ~/clima && git pull
```

## Ressalva sobre os dados

Open-Meteo entrega **reanálise e modelo numérico** em grade de ~9-25 km, não
leitura de estação física no ponto exato do município. É o dado certo para série
histórica longa e homogênea, e essa distinção deve aparecer no painel.

## Estrutura

```
sql/        DDL numerado (01..09) + deploy.sh
ingestao/   open_meteo.py (API) · nomes.py (de-para) · banco.py (staging + MERGE)
            ingestao.py (CLI) · verificar_mapeamento.py · .env.exemplo
            clima-backfill.cron · clima-incremental.cron
docs/       amostras de payload da API
```
