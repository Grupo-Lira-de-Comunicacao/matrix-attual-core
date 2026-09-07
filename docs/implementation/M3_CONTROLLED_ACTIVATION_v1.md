# Matrix Attual — M3 Controlled Activation v1

## Status

M3 turns the M2 shadow output into a **quality-gated, consent-gated personalization capability** without enabling broad marketing or autonomous external actions.

## Principles

1. Analytics consent does not imply personalization consent.
2. Personalization is opt-in and requires adult confirmation in the AttualPlay pilot.
3. Marketing remains disabled in M3 v1.
4. n8n external actions remain disabled in M3 v1.
5. Anonymous profiles can receive in-app topic recommendations, but cannot silently enrich CRM.
6. Downstream signals require an identified Matrix person and a separately eligible action path.
7. No sensitive-trait inference is introduced.

## M3A — Observability and quality gate

Migration `020_matrix_m3_controlled_activation.sql` creates:

- `matrix_m3_policies`;
- `matrix_m3_decisions`;
- `matrix_m3_quality_snapshots`;
- `matrix_m3_action_outbox`;
- `matrix_m3_observability_current`;
- `matrix_run_m3_control()`;
- cron job `matrix-m3-control-v1`.

The initial AttualPlay quality policy is `m3-policy-v1`:

- minimum top score: `1.5`;
- minimum confidence: `0.35`;
- minimum signal count: `2`;
- maximum recommendation age: `24h`.

A recommendation is not eligible merely because M2 generated it. It must pass this policy first.

Observability captures 24-hour windows for:

- consented analytics events;
- personalization opt-in events;
- active anonymous profiles;
- active interest scores;
- shadow recommendations;
- eligible M3 decisions;
- recommendation shown/clicked events;
- click-through rate;
- invalidations;
- DLQ pending count.

## M3B — User-facing personalization

The public endpoint is:

`POST /v1/recommendations/query`

The endpoint requires the AttualPlay publishable client and all three affirmative states:

- `analytics=true`;
- `personalization=true`;
- `adult_confirmed=true`.

It returns only an M3-eligible recommendation. The response is restricted to safe topic-level fields such as topic key/label, rank, score, confidence and signal count.

The endpoint explicitly rejects `marketing=true`; personalization consent is not converted into marketing authorization.

## M3C — Attual One readiness

`matrix_m3_action_outbox` is the controlled handoff boundary. It only accepts rows with a real `person_id`.

The current AttualPlay M2 pilot is anonymous-first, so it does not silently create CRM enrichment. Future identified signals must cross a legitimate identity-linking boundary before Attual One can consume them.

## M3D — n8n readiness

The outbox supports destination `n8n`, but `n8n_external_actions_enabled=false` in `m3-policy-v1`.

This means M3 establishes the auditable integration boundary without authorizing outbound user messaging or campaign actions.

## M3E — Commercial safety

`marketing_enabled=false` is a policy invariant in M3 v1.

Commercial activation requires a later, separate purpose, consent/legal-basis review and explicit policy version. M3 does not infer marketing permission from analytics or personalization.

## Event API correction discovered during M3

The AttualPlay consent snapshot already sends `adult_confirmed`, and M2 correctly requires that field, but the M1 Zod envelope did not allow the field because the consent object is strict. M3 fixes the API schema to accept `adult_confirmed` explicitly and adds regression coverage.

## Feedback loop

The Event Catalog already contains:

- `recommendation_shown`;
- `recommendation_clicked`;
- `recommendation_dismissed`;
- `preference_updated`.

AttualPlay uses these events after explicit personalization opt-in so M3 can measure whether shadow recommendations correlate with later behavior.

## Definition of done

M3 v1 is complete when:

1. migration 020 is applied;
2. `matrix-m3-control-v1` exists exactly once;
3. quality policy is seeded and marketing/n8n external actions are false;
4. adult confirmation is accepted by the Event API;
5. recommendation query requires explicit personalization opt-in;
6. only quality-gated recommendations are returned;
7. AttualPlay offers independent personalization consent and can revoke it;
8. recommendation shown/clicked feedback is recorded only under analytics consent;
9. anonymous recommendations do not create Attual One/CRM actions;
10. downstream outbox remains suppressed unless future identified-person requirements are met;
11. `/health` and `/ready` remain healthy;
12. production smoke proves consent denial returns no recommendation and opt-in returns only threshold-qualified output.

## Explicitly outside M3 v1

- sensitive-trait inference;
- automatic identity stitching;
- broad marketing campaigns;
- WhatsApp/email/push automation to anonymous profiles;
- autonomous n8n external actions;
- LLM/ML ranking.
