# Matrix Attual — M2 Shadow Intelligence v1

## Status

M2 introduces deterministic interest scoring and explainable recommendations for AttualPlay in **shadow mode**.

Shadow mode means the engine can learn and evaluate internally, but its output is **not shown to the user**, does not reorder the app, does not trigger notifications, does not activate marketing and does not write to Attual One/CRM or n8n.

## Privacy boundary

M2 is anonymous-first.

- AttualPlay analytics remains opt-in and restricted to users who confirmed 18+.
- The engine processes only events whose consent snapshot has `analytics=true` and `adult_confirmed=true`.
- `anonymous_profile_id` is the default subject for the AttualPlay pilot.
- M2 does not create a `matrix_people` row merely to score an anonymous profile.
- No inference of sensitive traits is performed.
- Invalidated events stop contributing on the next engine run.
- Existing M1 retention remains authoritative: raw analytics/evidence is bounded by the 90-day data lifecycle.

## Engine version

`m2-shadow-rules-v1`

The engine is rule-based. There is no LLM/ML model deciding interests in M2 v1.

## Signal rules

The first rule set is intentionally conservative and only infers observable media-format affinity:

| Signal | Topic | Base contribution |
| --- | --- | ---: |
| TV started | `tv-ao-vivo` | 1.00 |
| TV started | `audiovisual` | 0.50 |
| TV stopped 0–30s | `tv-ao-vivo` | 0.25 |
| TV stopped 31–120s | `tv-ao-vivo` | 0.75 |
| TV stopped 121–300s | `tv-ao-vivo` | 1.50 |
| TV stopped 300s+ | `tv-ao-vivo` | 2.50 |
| Radio started | `radio` | 1.00 |
| Radio started | `musica` | 0.50 |
| Radio stopped 0–30s | `radio` | 0.25 |
| Radio stopped 31–120s | `radio` | 0.75 |
| Radio stopped 121–300s | `radio` | 1.50 |
| Radio stopped 300s+ | `radio` | 2.50 |
| Programação viewed | `programacao` | 1.00 |
| Programação viewed | `eventos` | 0.25 |
| Participation/chat area viewed | `participacao` | 1.00 |

The engine deliberately does **not** infer politics, health, religion, income, sexuality, or other sensitive/personal characteristics from generic TV/radio usage.

## Interest Engine

`matrix_interest_scores` now supports either a known `person_id` or an `anonymous_profile_id`, but never both for the same score row.

Every score is backed by `matrix_interest_evidence`, which records:

- source event;
- contribution;
- deterministic `reason_code`;
- calculation engine version.

Score v1 is the sum of valid contributions still present inside the retained evidence window. Confidence is deterministic and capped at `0.95` based on signal count and accumulated contribution.

## Recommendation Engine

The Recommendation Engine writes `topic_affinity_shadow` records to `matrix_recommendations`.

Each recommendation contains:

- top 3 topics;
- score;
- confidence;
- signal count;
- engine version;
- human-readable reason;
- source signals.

Items are stored as `object_type=topic`. M2 does not yet recommend specific programs/articles to users.

Recommendations are internal, status `shadow`, expire after 24 hours, and are regenerated only when needed.

## Processing and idempotency

`matrix_m2_event_state` records which event was handled by which engine version. A new engine version can replay events without corrupting v1 state.

The database-owned function is:

`matrix_run_m2_shadow(now(), event_limit)`

It runs every 10 minutes through Supabase Cron / `pg_cron` as job:

`matrix-m2-shadow-v1`

The function is revoked from `public`, `anon`, `authenticated` and `service_role`; it is not a public RPC surface.

## Invalidation behavior

If an event is invalidated:

1. its interest evidence is deleted on the next M2 run;
2. affected scores are recomputed;
3. empty scores are deleted;
4. stale shadow recommendations are superseded.

This makes synthetic smoke tests reversible and preserves the append-only event + invalidation model.

## Audit

Each run writes a non-sensitive `m2.shadow.run` entry to `matrix_audit_log` with aggregate counters only:

- events processed;
- evidence added;
- invalidated evidence removed;
- active scores;
- recommendations generated;
- `personalization_exposed=false`;
- `marketing_enabled=false`.

## Definition of done for M2

M2 is complete when all of the following are true in production:

1. migration 017 applied;
2. anonymous interest score supported without creating person identity;
3. 15 deterministic AttualPlay rules seeded;
4. cron job present exactly once;
5. engine function unavailable to client/service roles;
6. consented synthetic events create the expected scores/evidence;
7. a top-3 shadow recommendation is generated with explanation;
8. invalidating synthetic events removes their influence after rerun;
9. Matrix `/health` and `/ready` remain healthy;
10. no recommendation is exposed to AttualPlay and no CRM/n8n/marketing action is triggered.

## What M2 does not do

M2 does not include:

- user-facing “Para você” UI;
- automated campaigns;
- CRM enrichment;
- n8n actions;
- notifications;
- identity stitching without an explicit legitimate linkage event;
- machine-learning ranking.

Those belong to a later activation milestone after shadow quality is measured.
