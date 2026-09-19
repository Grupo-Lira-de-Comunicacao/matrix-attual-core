# Matrix Attual M5 — Corporate Catalog v2

Status: consolidation contract — 2026-09-19.

## Objective

Reconcile the M5 corporate memory with the current Grupo Lira architecture without turning Matrix into an ERP, CRM, document store or mandatory event bus.

## Canonical organizational model

```text
GRUPO LIRA DE COMUNICACAO
        |
        v
    MATRIX ATTUAL
 Inteligencia • Contexto • Integracao
        |
 +------+------+------+------+------+
 |      |      |      |      |      |
Midia Servicos Negocios Cultura Tecnologia Terceiro Setor
```

Matrix is an organizational/context layer and does not replace the operating systems of the entities below it.

## Source of truth by domain

- Matrix / Supabase Matrix: technical identity, consent, contextual relations, permitted events, interests, evidence, scores, recommendations and corporate context.
- ATTUAL CRM: leads, contacts, companies, opportunities, proposals, tasks and commercial relationship.
- Plataforma Attual: operational companies, catalog, orders, inventory, operational customers, payments, store and modules. Existing technical identifiers may still use `attual-one`.
- Google Drive: contracts, proposals, reports, briefs, presentations, minutes and institutional documents.
- GitHub: code, migrations, architecture, policies, runbooks and API contracts.
- ATLAS: governed execution, workers, capabilities and operational audit.
- n8n: process automation and orchestration only.
- Infisical: secrets and credentials only.
- Vercel: current Matrix API runtime/delivery.

## Hierarchy v2

### Corporate
- GL-001 Grupo Lira de Comunicacao
- SYS-001 Matrix Attual

### Midia
- BR-001 TV Attual
- BR-002 Radio Attual
- BR-003 AttualPlay
- BR-004 Revista Attual
- BR-012 Caçapava News

### Servicos
- BR-005 ATT Comunica
- BR-006 Studio Lira
- BR-007 Casting Attual 360

### Negocios
- BR-010 LAVA - Laundry Vale
- BR-011 Bellalucci

### Cultura e Entretenimento
- BR-008 Attual Records
- BR-009 Attual Experience
- PR-001 Novelas Verticais
- PR-002 Premio Attual
- PR-003 FEMAC SP
- PR-004 FEPAC Conecta
- PR-005 Miss Caçapava
- PR-006 Taiada Fashion

### Tecnologia
- SYS-002 Plataforma Attual
- SYS-003 Lira Technology
- SYS-004 ATLAS Control Plane GL v4

### Terceiro Setor
- ORG-001 ACCA - Sinal Livre

## AttualPlay parent decision

AttualPlay remains a sibling corporate platform inside the Midia nucleus. Google Drive may organize AttualPlay documents under the TV Attual folder for practical file management; Drive folder nesting is not the authority for corporate parentage.

## Attual Experience

Attual Experience remains active in the Matrix catalog because it is an approved corporate initiative even when the current Drive tree does not yet expose a dedicated folder. This discrepancy should be solved by documentation/Drive organization, not by silently retiring the Matrix entity.

## Runtime decision

The current observed Matrix production is Vercel project `matrix-attual-core` in READY state. The VPS runtime document remains a contingency/migration runbook. Moving the canonical runtime to VPS would require a separate controlled deployment decision.

## Safe migration policy

Migration `025_matrix_corporate_catalog_v2.sql`:

- upserts entities and nuclei;
- reparents the current catalog to Matrix/nucleus nodes;
- does not delete operational entities;
- does not activate marketing;
- does not grant browser access;
- does not alter M2/M3/M4 consent policy;
- does not apply automatically through CI.

## Validation required before database apply

1. establish administrative/read-only access to Supabase project `matrixattual`;
2. read back applied migrations;
3. confirm migrations 023 and 024 exist in the target database;
4. inspect current entity slugs for conflicts;
5. take/confirm recoverability appropriate to the database;
6. apply 025 through a governed path;
7. read back hierarchy and source domains;
8. verify Matrix API `/health` and `/ready`.

## Safety invariants

1. Do not duplicate operational datasets into Matrix.
2. Do not create a dedicated graph database.
3. Keep `matrix_relationships` as the relation layer.
4. Keep catalog/source registry inaccessible to anonymous/authenticated browser roles.
5. Do not infer identity links or marketing permissions from corporate relations.
6. Marketing and external autonomous actions remain disabled until a separate gate.
