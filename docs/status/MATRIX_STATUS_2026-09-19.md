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
- concluir M4 ponta a ponta no AttualPlay;
- confirmar/monitorar telemetria de producao do AttualPlay;
- criar namespace/capabilities Matrix read-only no ATLAS quando a superficie cliente estiver disponivel;
- qualquer ativacao futura de marketing exige gate separado.

## Conclusao

MATRIX ATTUAL M5 CORPORATE CATALOG v2: CONCLUIDA E VALIDADA EM PRODUCAO.
