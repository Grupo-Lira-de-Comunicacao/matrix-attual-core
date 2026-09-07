# Matrix Attual M5 — Corporate Catalog v1

Status: implementation contract.

## Objective

Formalize the Matrix-centric V2 corporate memory layer after M4, without turning Matrix into an ERP, CRM, document store or mandatory event bus.

## Source-of-truth by domain

- Matrix / Supabase Matrix: technical identity, consent, contextual relations, permitted events, interests, evidence, scores, recommendations and qualified signals.
- ATTUAL CRM: leads, contacts, companies, opportunities, proposals, tasks and commercial relationship.
- ATTUAL ONE: operational companies, catalog, orders, inventory, operational customers, payments, store and modules.
- Google Drive: contracts, proposals, reports, briefs, presentations, minutes and institutional documents.
- GitHub: code, migrations, architecture, policies, runbooks and API contracts.
- VPS / ATLAS: governed execution, workers, integrations and capabilities.
- n8n: process automation and orchestration only.
- Infisical: secrets and credentials only.
- Vercel: application runtime and delivery only.

## Corporate catalog

The existing `matrix_entities` table is the canonical base for the corporate catalog. M5 extends it instead of creating a parallel catalog.

Technical identity rule:

`UUID primary key + stable slug + optional human code`

Minimum fields:

- official name (`name`)
- entity type
- parent entity
- Grupo Lira nucleus
- status
- responsible reference
- canonical domain/URL
- repository/system reference
- short description
- objective
- audience
- relations through `matrix_relationships`
- next action
- history/notes
- source-of-truth domain

## Initial entity types

The first useful graph remains small: PERSON, ORGANIZATION, BRAND, PROJECT, CONTENT and CAMPAIGN. The catalog may also classify platforms, programs, products, events and assets when those are real corporate objects; it must not create a dedicated graph database.

## Minimal friendly catalog

- GL-001 Grupo Lira de Comunicacao
- BR-001 TV Attual
- BR-002 Radio Attual
- BR-003 AttualPlay
- BR-004 Revista Attual
- BR-005 ATT Comunica
- BR-006 Studio Lira
- BR-007 Casting Attual 360
- BR-008 Attual Records
- BR-009 Attual Experience
- BR-010 LAVA - Laundry Vale
- BR-011 Bellalucci

These codes are not primary keys.

## Safety rules

1. Do not duplicate operational datasets into Matrix.
2. Do not create a dedicated graph database at this stage.
3. Keep `matrix_relationships` as the relation layer.
4. Keep internal catalog/source registry inaccessible to anonymous and authenticated browser roles.
5. Do not infer hidden identity links or marketing permissions from corporate relationships.
6. Add only relationships that are actually used.
