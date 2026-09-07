# Matrix M4 — Identity Bridge and Consented Downstream Activation

## Status

Implementation candidate for controlled production activation. M4 does not enable marketing and does not enable autonomous external actions.

## Objective

M4 adds an explicit, auditable bridge between an authenticated ATTUAL ONE customer account and a Matrix person identity, while preserving the privacy and quality controls introduced in M2 and M3.

The bridge exists only after an intentional user action. Matrix does not perform hidden identity stitching, does not infer a person from anonymous behavior and does not receive ATTUAL ONE PII as part of the bridge.

## Identity flow

1. An authenticated ATTUAL ONE account requests a one-time Matrix bridge code server-to-server.
2. ATTUAL ONE sends only an opaque external account reference; Matrix hashes it before persistence.
3. The user enters or confirms the one-time code in AttualPlay.
4. Matrix consumes the code once, creates an explicit identity link to the current anonymous profile and issues a revocable opaque person-session token.
5. AttualPlay stores only the opaque Matrix session token. It does not store Matrix database identifiers or secret integration credentials.
6. ATTUAL ONE receives a server-only link callback containing the Matrix person UUID and records the explicit account/person association in its private tables.

## Consent model

Identified use requires server-side consent records in Matrix.

- analytics must be explicitly granted;
- adult confirmation must be true;
- personalization may be granted or denied independently after analytics is granted;
- marketing is always false in M4;
- revocation is written to the Matrix consent ledger;
- analytics revocation also revokes the active identity session and suppresses pending downstream eligibility;
- personalization revocation keeps analytics available but prevents identified recommendations and qualified downstream signals.

Browser consent remains a user control, but identified processing is never authorized only by a browser field. The server ledger is the authoritative gate for identified subjects.

## Recommendation promotion

M4 does not invent a second recommendation engine. It promotes only context that already passed M3 quality gates.

An anonymous M3 recommendation can be promoted to an identified Matrix person only when all of the following are true:

- the explicit anonymous-profile/person link is active;
- the link was created through the ATTUAL ONE bridge;
- current server-side analytics consent is granted;
- current server-side personalization consent is granted;
- the source M3 decision is still eligible and unexpired.

Promoted recommendations remain `topic_affinity_shadow`; they do not authorize marketing, messaging or campaign execution.

## ATTUAL ONE downstream signal

M4 may produce one governed `qualified_interest_signal` for ATTUAL ONE after the identified recommendation is eligible.

The payload is deliberately narrow:

- Matrix person UUID;
- topic key;
- deterministic score;
- confidence;
- signal count;
- policy version;
- timestamps and idempotency key;
- `purpose=personalization`;
- `marketing_allowed=false`;
- `external_action_allowed=false`.

Name, email, phone, CPF, chat content, payment details and sensitive attributes are not part of the signal payload.

ATTUAL ONE stores the signal in a private inbox. It can associate the signal with a customer only when the explicit Matrix-person/account link exists and is active. An unlinked signal remains isolated. Revoked links suppress pending use.

## n8n boundary

n8n remains observe-only in M4. The Matrix control function suppresses executable n8n rows and migration self-validation fails if an n8n row exists in an executable pending/processing state.

There is no autonomous WhatsApp, e-mail, campaign or commercial action in M4.

## Security controls

- one-time bridge codes are hashed and expire;
- person-session tokens are hashed, revocable and expiring;
- integration credentials remain server-side;
- public Matrix clients receive only the scopes needed for events, recommendations, explicit identity link/unlink and consent synchronization;
- M4 control execution is revoked from public, anon, authenticated and service_role;
- RLS is enabled on new Matrix tables;
- ATTUAL ONE private bridge/link tables are inaccessible to browser roles;
- downstream delivery is idempotent;
- revocation and unlink are audited;
- marketing and external commercial action flags are hard-disabled.

## Observability

`matrix_m4_observability_current` reports the current M4 operational state, including active identity links, active person sessions, ATTUAL ONE pending/delivered rows and executable n8n rows. A healthy M4 state requires `n8n_executable_rows = 0` and `marketing_enabled = false`.

The `matrix_run_m4_control()` audit record also reports promotions, downstream rows touched, suppressions after revocation/unlink, marketing state, n8n state and hidden-stitching state.

## Production acceptance criteria

M4 can be declared complete only after all of these are proven in production:

1. migrations 021 and 022 are recorded;
2. Matrix `/health` and `/ready` return healthy status;
3. an ATTUAL ONE authenticated test account can obtain a one-time bridge code;
4. the code can be consumed once from AttualPlay and cannot be reused;
5. Matrix creates an explicit person link and revocable session without receiving PII in the bridge request;
6. server-side analytics and personalization consent are recorded;
7. an M3-eligible anonymous context can be promoted to the identified person;
8. a qualified signal can reach the ATTUAL ONE inbox idempotently;
9. the signal links to a customer only through the explicit ATTUAL ONE account/person association;
10. personalization revocation suppresses new identified recommendations/signals;
11. analytics revocation or unlink revokes the person session and suppresses pending downstream rows;
12. marketing remains disabled;
13. n8n has zero executable external-action rows;
14. synthetic smoke fixtures are removed or invalidated after validation;
15. relevant audit evidence exists for bridge, consent, delivery and revocation.

## Rollback boundary

If M4 validation fails, the safe rollback is to disable M4 delivery/cron behavior, revoke active synthetic test sessions and suppress pending M4 outbox rows while preserving audit evidence. M2/M3 anonymous analytics and consent-gated in-app personalization can remain operational independently.
