# MATRIX ATTUAL — STATUS FINAL DE CONSOLIDACAO

Data: 2026-09-19  
Escopo: Grupo Lira de Comunicacao / Matrix Attual  
Status: CONCLUIDO — M5 CORPORATE CATALOG v2 EM PRODUCAO

## Resultado

A consolidacao da Matrix Attual foi concluida de ponta a ponta no escopo M5 v2.

## GitHub

PR #14 foi validada e mesclada.

Baseline de consolidacao:
`59a8e7e39bc6afc0f0043804845dadd17ac77043`

O CI passou por:
- verificacao de segredos obvios;
- sequencia de migrations 001–025;
- contratos de retencao;
- M2;
- M3;
- M4;
- M5;
- contratos obrigatorios;
- typecheck;
- testes unitarios;
- build da aplicacao;
- build Docker.

O repositorio permanece publico por decisao operacional.

## Supabase Matrix

Projeto:
`matrixattual`

Project ref:
`fdmvvxsdfanqarokastv`

O acesso de producao foi obtido pelo caminho governado:

`ATLAS -> Credential Broker -> Supabase Management API`

Nenhuma credencial foi impressa ou registrada na evidencia.

### Historico real

Read-back confirmou:
- matrix_m0_foundation_v1
- matrix_015_service_role_grants
- 016_matrix_retention_policy
- 017_matrix_m2_shadow_intelligence
- 018_matrix_m2_shadow_uuid_hotfix
- 019_matrix_m2_shadow_smoke
- 020_matrix_m3_controlled_activation
- 021_matrix_m4_identity_bridge
- 022_matrix_m4_api_grants_and_guards

M5 ainda nao estava no banco. Foram entao aplicadas, nessa ordem:
- 023_matrix_corporate_catalog
- 024_matrix_corporate_catalog_seed
- 025_matrix_corporate_catalog_v2

As tres migrations foram verificadas por Git blob contra o SHA aprovado antes da aplicacao.

## Catalogo M5 v2

Read-back final:
- 30 entidades corporativas;
- 9 dominios de source-of-truth;
- Matrix Attual subordinada ao Grupo Lira;
- seis nucleos subordinados a Matrix;
- marcas, plataformas, projetos e ACCA corretamente associados aos nucleos.

Nucleos:
- Midia
- Servicos
- Negocios
- Cultura e Entretenimento
- Tecnologia
- Terceiro Setor

AttualPlay permanece como plataforma irma dentro de Midia.

## Source-of-truth

Ativos:
- contextual -> Matrix
- relationship -> ATTUAL CRM
- operations -> Attual One / Plataforma Attual
- documents -> Google Drive
- technical -> GitHub
- execution -> ATLAS
- automation -> n8n
- secrets -> Infisical
- runtime -> Vercel

## Seguranca

Read-back confirmou:
- RLS ativo em matrix_source_domains;
- anon sem SELECT;
- authenticated sem SELECT;
- M3 personalization_requires_opt_in = true;
- M3 downstream_requires_identified_person = true;
- marketing_enabled = false;
- n8n_external_actions_enabled = false.

Jobs ativos:
- matrix-retention-daily-v1
- matrix-m2-shadow-v1
- matrix-m3-control-v1

M4:
- person_sessions = 0;
- bridge_tokens = 0.

Isso e consistente com M4 ainda nao promovido amplamente no cliente.

## Runtime

Vercel:
- projeto: matrix-attual-core;
- producao READY;
- endpoint /health = HTTP 200;
- endpoint /ready = HTTP 200.

A metadata de health foi atualizada de M4/v0.4.0 para M5/v0.5.0 como parte do fechamento documental/operacional.

## Google Drive

A pasta institucional MATRIX ATTUAL foi populada com:
1. Arquitetura e Governanca;
2. Status de Consolidacao;
3. Catalogo Corporativo v2.

## ATLAS

ATLAS permaneceu com governanca preservada:
- Objective Scope;
- N4_ROOT;
- confirmacao APROVO;
- Credential Broker;
- nenhum shell automatico irrestrito;
- nenhum acesso a VPS1.

## Pendencias fora deste fechamento

Nao bloqueiam M5 v2:
- executar a primeira validacao M4 ponta a ponta com uma conta humana autenticada e consentimento explicito;
- observar os primeiros eventos reais consentidos do AttualPlay;
- qualquer ativacao futura de marketing exige gate separado.

## Conclusao

MATRIX ATTUAL M5 CORPORATE CATALOG v2: CONCLUIDA E VALIDADA EM PRODUCAO.


## Atualizacao M4 server-to-server — 2026-09-19

O ciclo seguinte ao M5 confirmou que AttualPlay e Attual One ja possuem o codigo M4 necessario em producao. A capacidade de telemetria do AttualPlay foi habilitada com `VITE_MATRIX_TRACKING_ENABLED=true`, mantendo `VITE_MATRIX_ANALYTICS_DEFAULT=denied`, personalizacao opt-in e marketing desabilitado.

Tambem foram provisionadas, como variaveis sensiveis de producao na Vercel, as credenciais server-to-server do M4 e a chave interna de observabilidade. As URLs de sinais e callback permanecem restritas aos endpoints M4 ja revisados do Attual One.

Esta atualizacao documental força novo deployment do runtime para carregar as variaveis provisionadas. Nenhuma regra de consentimento, marketing ou acao externa foi ampliada.


## Fechamento técnico adicional — 2026-09-19

### Capabilities Matrix no ATLAS

Confirmadas como disponíveis, N1, automáticas, read-only, tipadas e universalmente executáveis:

- `matrix.health`
- `matrix.ready`
- `matrix.catalog.list`
- `matrix.m4.status`
- `matrix.telemetry.status`

Logo, não há mais implantação pendente de namespace Matrix no catálogo ATLAS.

### Telemetria AttualPlay

A capacidade técnica de tracking está ativa em produção, com:

- `VITE_MATRIX_TRACKING_ENABLED=true`;
- analytics negado por padrão;
- confirmação 18+ obrigatória para analytics;
- personalização em opt-in separado;
- marketing desabilitado.

O read-back final permaneceu sem novos eventos nas 24h e sem sessões M4, demonstrando que a ativação técnica não concede consentimento automaticamente.

### M4 canonical endpoint

O host canônico do ATTUAL ONE para integração M4 é `https://app.attualone.com.br`.

Endpoints:

- `POST /api/integrations/matrix/links`
- `POST /api/integrations/matrix/signals`

Provas:

- o host canônico responde HTTP 401 a probes POST sem credencial;
- `https://attualone.com.br` responde HTTP 307 redirecionando para `app.attualone.com.br`;
- o hostname histórico `attual-one-platform.vercel.app` respondeu HTTP 404 e foi removido da configuração Matrix;
- os dois environment URLs da Matrix foram corrigidos sem alterar segredos.

### Limite humano restante

Tudo que pode ser validado sem personificar um usuário está concluído. A única prova funcional não executada é a jornada humana M4 completa, que deve partir de uma conta autenticada e de consentimento explícito real.
