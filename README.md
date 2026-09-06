# Matrix Attual Core

Nucleo tecnico privado da Matrix Attual: identidade, eventos, relacionamento, consentimento, interesses, recomendacoes e auditoria do ecossistema Grupo Lira.

## Status

**Fase atual:** M1 — Event API / piloto AttualPlay  
**M0 Foundation:** aplicada e validada no Supabase `matrixattual` em 2026-09-06.

## Fundacao M0 concluida

- arquitetura modular/event-driven;
- Supabase migrations `001` a `014` aplicadas;
- isolamento por tenant/project;
- identidade e perfis anonimos;
- Consent Registry;
- catalogo de conteudo/topics;
- Event Store idempotente;
- Attual Graph;
- Interest Engine data model;
- Recommendation Engine data model;
- segments/campaigns;
- audit/DLQ;
- RLS deny-by-default nas tabelas Matrix;
- Event Catalog v1;
- OpenAPI v1;
- Data Contract AttualPlay v1.

## M1 em implementacao

- `GET /health` e `GET /ready`;
- `GET /v1/event-types`;
- `POST /v1/events`;
- `POST /v1/events/batch`;
- cliente publicavel `attualplay` com origem allowlisted;
- validacao estrita por Event Catalog;
- minimizacao de contexto/propriedades;
- perfil anonimo persistido somente por hash;
- idempotencia e `correlation_id` ponta a ponta;
- CI com typecheck e testes unitarios.

## Supabase alvo

- project: `matrixattual`
- project_ref: `fdmvvxsdfanqarokastv`
- credential: resolvida pelo ATLAS via Account Registry -> Credential Broker -> Infisical

Nenhum segredo deve ser commitado neste repositorio. Credenciais administrativas do banco existem somente no runtime server-side da API.

## Proximo gate

1. CI verde da PR M1;
2. provisionar runtime/API;
3. injetar configuracao pelo ATLAS/Infisical;
4. smoke test sintetico;
5. integrar AttualPlay atras de feature flag;
6. validar latencia/erro e habilitar gradualmente.

Detalhes: `docs/implementation/EVENT_API_M1.md`.
