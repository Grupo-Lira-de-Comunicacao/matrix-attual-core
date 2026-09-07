import { randomUUID } from "node:crypto";
import type { PublicClientConfig } from "./config.js";
import type { EventRow, MatrixRepository } from "./db.js";
import { parseEventEnvelope, type EventEnvelope } from "./events/schema.js";

export type IngestResult = {
  accepted: true;
  duplicate: boolean;
  event_id: string;
  correlation_id: string;
};

function correlationId(value?: string | null): string {
  const candidate = String(value ?? "").trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(candidate)
    ? candidate
    : randomUUID();
}

export async function ingestOne(
  repository: MatrixRepository,
  client: PublicClientConfig,
  input: unknown,
  requestedCorrelationId?: string | null,
): Promise<IngestResult> {
  const event: EventEnvelope = parseEventEnvelope(input);
  if (event.project_key !== client.projectKey) throw new Error("event project does not match client scope");

  const project = await repository.resolveProject(event.project_key);
  const anonymousProfileId = event.anonymous_id
    ? await repository.upsertAnonymous(project, event.anonymous_id)
    : null;
  const personId = event.person_token
    ? await repository.resolvePersonToken(project, event.person_token)
    : null;

  if (event.person_token && !personId) {
    const error = new Error("person session is invalid or expired");
    Object.assign(error, { status: 401 });
    throw error;
  }
  if (personId && event.consent?.analytics === true) {
    const analyticsGranted = await repository.hasCurrentPersonConsent(personId, "analytics");
    if (!analyticsGranted) {
      const error = new Error("server-side analytics consent is not granted");
      Object.assign(error, { status: 403 });
      throw error;
    }
  }

  const cid = correlationId(requestedCorrelationId);
  const row: EventRow = {
    id: event.event_id,
    tenant_id: project.tenantId,
    project_id: project.projectId,
    person_id: personId,
    anonymous_profile_id: anonymousProfileId,
    event_type: event.event_type,
    object_type: event.object?.type ?? null,
    object_id: event.object?.id ?? null,
    occurred_at: event.occurred_at,
    session_id: event.session_id ?? null,
    correlation_id: cid,
    source: client.id,
    schema_version: 1,
    consent_snapshot: event.consent ?? {},
    properties: event.properties,
    context: event.context,
    idempotency_key: event.idempotency_key,
  };

  const result = await repository.insertEvent(row);
  return {
    accepted: true,
    duplicate: result.duplicate,
    event_id: result.eventId,
    correlation_id: cid,
  };
}

export async function ingestBatch(
  repository: MatrixRepository,
  client: PublicClientConfig,
  inputs: unknown[],
  requestedCorrelationId?: string | null,
): Promise<IngestResult[]> {
  const results: IngestResult[] = [];
  const concurrency = 10;
  for (let offset = 0; offset < inputs.length; offset += concurrency) {
    const chunk = inputs.slice(offset, offset + concurrency);
    const chunkResults = await Promise.all(
      chunk.map((event) => ingestOne(repository, client, event, requestedCorrelationId)),
    );
    results.push(...chunkResults);
  }
  return results;
}
