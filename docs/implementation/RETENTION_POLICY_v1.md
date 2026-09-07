# Matrix Attual — Retention Policy v1

Version: `matrix-retention-v1-2026-09-06`

## Scope

This policy closes the M1 analytics pilot with bounded retention for raw/pseudonymous AttualPlay telemetry. It does not authorize marketing, individual personalization, sensitive-data processing, or expansion to other Matrix projects.

## Retention windows

- Raw Matrix events: **90 days** from `received_at`.
- Anonymous browser profiles: **90 days after last activity**; each valid analytics event renews `expires_at` to 90 days from the latest activity.
- Dead-letter event payloads: **90 days maximum**.
- Anonymous recommendations: deleted when expired or older than the 90-day anonymous inactivity window.
- Operational Matrix audit log: **365 days**.

These are Grupo Lira operational minimization choices for this M1, not a statement that the LGPD mandates one universal number of days for analytics.

## Daily cleanup

Migration `016_matrix_retention_policy.sql` enables Supabase Cron (`pg_cron`) and schedules `matrix-retention-daily-v1` at `03:17 UTC` every day.

The database function `public.matrix_run_retention()`:

1. deletes recommendation feedback and interest evidence that reference raw events due for disposal;
2. deletes event invalidations for the same expired events;
3. deletes raw events older than the configured window;
4. deletes stale DLQ payloads;
5. deletes expired/stale anonymous recommendations;
6. deletes stale anonymous identity links when no retained event depends on them;
7. deletes anonymous profiles only when no retained event, recommendation, or identity link still references them;
8. deletes audit rows older than 365 days;
9. writes a new non-sensitive audit entry with deletion counts and the policy version.

## Access and safety

`matrix_run_retention()` is `SECURITY DEFINER` but execution is explicitly revoked from `public`, `anon`, `authenticated`, and `service_role`. It is intended to run only from the database-owned scheduled job or an explicitly governed database administration session.

The function refuses retention windows below these safety floors:

- events/anonymous/DLQ: 30 days;
- audit log: 90 days.

This prevents an accidental call from turning the retention routine into an immediate bulk-delete mechanism.

## AttualPlay privacy behavior

AttualPlay remains opt-in:

- analytics is denied by default;
- tracking sends no analytics event until the user explicitly accepts and confirms 18+;
- rejecting analytics does not disable TV, radio, programming, chat, or participation;
- revocation stops future events and removes local analytics identifiers;
- marketing and individual personalization remain disabled in this M1.

The public privacy notice must disclose the 90-day raw analytics/anonymous retention window and the 365-day technical audit window before this migration is treated as the completed production policy.

## Rollback

If the scheduled cleanup must be stopped without altering retained data:

```sql
select cron.unschedule('matrix-retention-daily-v1');
```

Stopping the cron does not restore data already lawfully disposed by previous successful runs. Database backup/PITR policy is separate from application-level retention and should be governed independently.
