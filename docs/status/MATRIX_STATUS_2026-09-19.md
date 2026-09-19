# MATRIX ATTUAL — STATUS DE CONSOLIDACAO

Data: 2026-09-19  
Escopo: Grupo Lira de Comunicacao / Matrix Attual  
Branch de consolidacao: `codex/matrix-consolidation-2026-09-19`

## Executive summary

Matrix Attual is a real implemented platform, not only an institutional concept. The repository contains M0–M5 contracts, 24 existing migrations, API code, consent controls, deterministic interest/recommendation logic, M4 identity bridge code and an M5 corporate catalog.

The consolidation found four main issues:

1. database state after M0 is not currently proven by read-back through the available Supabase connection;
2. repository documentation is stale and still describes M1 as the current phase;
3. M5 corporate catalog predates the current Grupo Lira architecture;
4. runtime documentation points to VPS while the observed current production is Vercel.

## Verified evidence

### GitHub
- repository: `Grupo-Lira-de-Comunicacao/matrix-attual-core`;
- current main before this consolidation: `8d95ef529d6d7ef308f71f63079c4f768944dc40`;
- CI `validate` succeeded on that SHA;
- existing migrations: 001–024;
- M2, M3, M4 and M5 implementation documents are present.

### Vercel
- project: `matrix-attual-core`;
- production state observed: READY;
- framework: Hono;
- current production SHA observed: `8d95ef529d6d7ef308f71f63079c4f768944dc40`.

### AttualPlay
- Matrix telemetry client exists;
- consent defaults to denied;
- personalization is independently gated;
- M3 recommendation UI exists;
- a production deployment exists for M3 opt-in personalization;
- M4 client work exists in preview deployments and must not be treated as fully promoted end to end.

### ATLAS
- ATLAS itself is healthy;
- Matrix is not yet a first-class ATLAS provider/capability namespace;
- current ChatGPT connector surface remains blocked for the universal executor;
- this consolidation does not weaken or bypass ATLAS governance.

### Google Drive
- institutional folder `10_INSTITUCIONAL/MATRIX ATTUAL` exists;
- it was empty at the beginning of this consolidation.

## Supabase limitation

The currently connected Supabase account/tool does not expose project `matrixattual` (`fdmvvxsdfanqarokastv`). Therefore this consolidation does not claim that migrations 015–024 are currently applied in production.

CI verifies repository contracts; it does not apply database migrations.

## Consolidation changes prepared

- README updated from stale M1 wording to current M0–M5 status;
- new M5 v2 corporate contract;
- migration 025 for corporate catalog reconciliation;
- CI migration sequence updated to 001–025;
- explicit runtime decision: Vercel current, VPS contingency;
- explicit separation of Matrix, ATLAS, CRM, Plataforma Attual, Drive, GitHub, n8n and Infisical.

## Database gate

Migration 025 must not be applied until the Matrix Supabase project is reachable for read-back.

## ATLAS gate

Read-only Matrix capabilities are recommended:

- `matrix.health`
- `matrix.ready`
- `matrix.catalog.list`
- `matrix.catalog.entity_get`
- `matrix.m2.status`
- `matrix.m3.observability`
- `matrix.m4.observability`
- `matrix.retention.status`

They should be introduced through the canonical capability path after the current client-surface limitation is resolved or through another governed ATLAS session. No generic shell or bypass is authorized.

## Marketing invariant

Marketing automation, outbound n8n actions and anonymous CRM enrichment remain disabled.

## Remaining external dependency

Administrative visibility/read-back for Supabase project `matrixattual` is the only required dependency to close the database side of this consolidation.
