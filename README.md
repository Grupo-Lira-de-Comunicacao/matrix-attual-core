# Matrix Attual Core

Nucleo tecnico da Matrix Attual: identidade, consentimento, eventos, relacionamento contextual, interesses, recomendacoes, memoria corporativa e auditoria do ecossistema Grupo Lira.

## Status consolidado — 2026-09-19

**Fase funcional em producao:** M0–M5 v2.  
**Runtime atual:** Vercel, projeto `matrix-attual-core`, producao READY.  
**Supabase:** `matrixattual` (`fdmvvxsdfanqarokastv`).  
**Banco verificado por read-back:** sim, em 2026-09-19, via caminho governado ATLAS -> Credential Broker -> Supabase Management API.

### Estado por marco

- M0 Foundation: aplicada e historicamente validada em 2026-09-06.
- M1 Event API: implementada.
- M2 Shadow Intelligence: aplicada; cron `matrix-m2-shadow-v1` ativo.
- M3 Controlled Activation: aplicada; cron `matrix-m3-control-v1` ativo; marketing e acoes externas n8n permanecem desabilitados.
- M4 Identity Bridge: backend aplicado; ativacao cliente ponta a ponta permanece controlada.
- M5 Corporate Catalog v2: migrations 023, 024 e 025 aplicadas e validadas em 2026-09-19.

## Evidencia de producao

Historico do banco apos consolidacao:

- `matrix_m0_foundation_v1`;
- `matrix_015_service_role_grants`;
- `016_matrix_retention_policy`;
- `017_matrix_m2_shadow_intelligence`;
- `018_matrix_m2_shadow_uuid_hotfix`;
- `019_matrix_m2_shadow_smoke`;
- `020_matrix_m3_controlled_activation`;
- `021_matrix_m4_identity_bridge`;
- `022_matrix_m4_api_grants_and_guards`;
- `023_matrix_corporate_catalog`;
- `024_matrix_corporate_catalog_seed`;
- `025_matrix_corporate_catalog_v2`.

O catalogo corporativo v2 possui 30 entidades e 9 dominios de source-of-truth.

## Principios

1. Matrix e camada de inteligencia, contexto, identidade contextual e memoria relacional.
2. Matrix nao e ERP, CRM, document store, secret manager nem control plane.
3. ATLAS governa execucao, infraestrutura, capabilities e auditoria operacional.
4. ATTUAL CRM e a fonte de verdade comercial.
5. Plataforma Attual e a fonte de verdade operacional/transacional.
6. Google Drive e a memoria documental.
7. GitHub e a memoria tecnica.
8. n8n orquestra processos; nao e Event Store nem Identity Store.
9. Infisical guarda segredos e credenciais.
10. Vercel e o runtime atual da API Matrix; o runbook VPS permanece como opcao de contingencia/migracao controlada.

## Arquitetura

```text
Canais / Produtos
    |
    v
Matrix Edge (SDK + API + Auth)
    |
    v
Identity + Consent + Event Ingestion
    |
    v
Event Store + Catalog + Relationships
    |
    v
Interest Engine + Recommendation Engine
    |
    v
AttualPlay / Plataforma Attual / ATTUAL CRM / outras verticais

ATLAS governa infraestrutura, capabilities, auditoria e operacao.
Infisical guarda segredos.
```

## Governanca de dados

- `tenant_id` e `project_id` desde a fundacao;
- eventos append-only e idempotentes;
- consentimento separado para analytics e personalizacao;
- marketing permanece desabilitado;
- acoes externas n8n permanecem desabilitadas no fluxo Matrix;
- nenhuma inferencia de atributos sensiveis;
- RLS ativo no catalogo M5;
- `anon` e `authenticated` nao possuem SELECT em `matrix_source_domains`;
- retencao automatica ativa;
- identidade M4 exige ligacao explicita, auditavel e revogavel;
- nenhum segredo deve ser commitado neste repositorio.

## Catalogo corporativo

M5 usa `matrix_entities` e `matrix_relationships` como memoria corporativa contextual, sem duplicar datasets operacionais.

Hierarquia consolidada:

```text
Grupo Lira de Comunicacao
  -> Matrix Attual
      -> Midia
      -> Servicos
      -> Negocios
      -> Cultura e Entretenimento
      -> Tecnologia
      -> Terceiro Setor
```

AttualPlay permanece como plataforma irma dentro de Midia.

Detalhes: `docs/implementation/M5_CORPORATE_CATALOG_v2.md`.

## Runtime

### Canonico atual
Vercel / projeto `matrix-attual-core`.

### Alternativa controlada
`docs/implementation/VPS_RUNTIME_RUNBOOK_v1.md` e contingencia/migracao, nao o runtime canonico atual.

## Repositorio

O repositorio permanece publico por decisao operacional, compativel com as conexoes atualmente utilizadas. Segredos continuam fora do GitHub.

## Proximos gates

1. concluir M4 ponta a ponta no cliente AttualPlay antes de promocao ampla;
2. confirmar/monitorar telemetria Matrix no AttualPlay em producao;
3. adicionar capabilities Matrix read-only ao ATLAS quando a superficie cliente permitir;
4. manter marketing e acoes externas automaticas desligados ate gate separado.
