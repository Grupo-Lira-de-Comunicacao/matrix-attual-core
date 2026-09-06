# Matrix Attual Core

Nucleo tecnico privado da Matrix Attual: identidade, eventos, relacionamento, consentimento, interesses, recomendacoes e auditoria do ecossistema Grupo Lira.

## Status

**Fase:** M0 Foundation  
**Branch de trabalho:** `codex/matrix-foundation-m0`

## Entregas M0

- arquitetura modular/event-driven;
- Supabase migrations `001` a `014` preparadas;
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
- RLS deny-by-default;
- Event Catalog v1;
- OpenAPI v1;
- Data Contract AttualPlay v1;
- CI basico de contratos e secret scanning.

## Supabase alvo

- project: `matrixattual`
- project_ref: `fdmvvxsdfanqarokastv`
- credential: resolvida pelo ATLAS via Account Registry -> Credential Broker -> Infisical

Nenhum segredo deve ser commitado neste repositorio.

## Proximo gate

1. ATLAS runtime assimilar o Account Registry atualizado;
2. validar `supabase.project.get` via credencial `matrixattual`;
3. revisar backup/preconditions;
4. aplicar migrations via `supabase.migration.apply` (N4 / `APROVO`);
5. rodar Supabase security/performance advisors;
6. iniciar Event API + SDK AttualPlay.
