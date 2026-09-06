import { describe, expect, it } from "vitest";
import { createApp } from "../app.js";
import type { MatrixRepository, ProjectRef, EventRow, InsertResult } from "../db.js";
import type { RuntimeConfig } from "../config.js";

class FakeRepository implements MatrixRepository {
  lastRow: EventRow | null = null;
  async ready() { return true; }
  async resolveProject(projectKey: string): Promise<ProjectRef> {
    return { tenantId: "11111111-1111-4111-8111-111111111111", projectId: "22222222-2222-4222-8222-222222222222", projectKey };
  }
  async upsertAnonymous() { return "33333333-3333-4333-8333-333333333333"; }
  async resolvePersonToken() { return null; }
  async insertEvent(row: EventRow): Promise<InsertResult> {
    this.lastRow = row;
    return { eventId: row.id, duplicate: false };
  }
}

const config: RuntimeConfig = {
  supabaseUrl: "https://example.invalid",
  dbAdminKey: "not-used-in-test",
  maxBodyBytes: 262144,
  maxBatchSize: 100,
  clients: {
    attualplay: {
      id: "attualplay",
      projectKey: "attualplay",
      publishableKey: "mat_pk_test_1234567890",
      allowedOrigins: ["https://app.example.test"],
      scopes: ["events:write"],
    },
  },
};

const event = {
  event_id: "6abda5c7-6ec0-4bd6-97b4-9e9d3e58f4b3",
  event_type: "content_viewed",
  occurred_at: "2026-09-06T17:30:00Z",
  project_key: "attualplay",
  anonymous_id: "anon-123456",
  properties: { content_id: "content-42", content_type: "article" },
  context: { device_class: "mobile" },
  consent: { essential: true, analytics: true },
  idempotency_key: "attualplay:session-1:content-42:view",
};

describe("Matrix Event API", () => {
  it("ingests a valid event and assigns source from the client", async () => {
    const repository = new FakeRepository();
    const app = createApp({ config, repository });
    const response = await app.request("/v1/events", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-matrix-client": "attualplay",
        "x-matrix-key": "mat_pk_test_1234567890",
        origin: "https://app.example.test",
      },
      body: JSON.stringify(event),
    });
    expect(response.status).toBe(200);
    expect(repository.lastRow?.source).toBe("attualplay");
    expect(repository.lastRow?.anonymous_profile_id).toBeTruthy();
  });

  it("rejects a bad client key", async () => {
    const app = createApp({ config, repository: new FakeRepository() });
    const response = await app.request("/v1/events", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-matrix-client": "attualplay",
        "x-matrix-key": "wrong-key-value-12345",
        origin: "https://app.example.test",
      },
      body: JSON.stringify(event),
    });
    expect(response.status).toBe(401);
  });

  it("rejects a browser origin outside the allowlist", async () => {
    const app = createApp({ config, repository: new FakeRepository() });
    const response = await app.request("/v1/events", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-matrix-client": "attualplay",
        "x-matrix-key": "mat_pk_test_1234567890",
        origin: "https://evil.example",
      },
      body: JSON.stringify(event),
    });
    expect(response.status).toBe(403);
  });
});
