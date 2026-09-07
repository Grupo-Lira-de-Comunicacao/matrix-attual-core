import { describe, expect, it } from "vitest";
import { createApp } from "../app.js";
import type { MatrixRepository, ProjectRef, EventRow, InsertResult, PersonalizedRecommendation } from "../db.js";
import type { RuntimeConfig } from "../config.js";

class FakeRepository implements MatrixRepository {
  lastRow: EventRow | null = null;
  recommendation: PersonalizedRecommendation | null = {
    recommendation_id: "55555555-5555-4555-8555-555555555555",
    reason_text: "Afinidade observada em uso consentido.",
    generated_at: "2026-09-07T12:00:00Z",
    expires_at: "2026-09-08T12:00:00Z",
    policy_version: "m3-policy-v1",
    items: [
      { rank: 1, topic_key: "radio", topic_label: "Radio", score: 3.5, confidence: 0.47, signal_count: 2 },
    ],
  };
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
  async getEligibleRecommendation() { return this.recommendation; }
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
      scopes: ["events:write", "recommendations:read"],
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
  consent: { essential: true, analytics: true, personalization: false, marketing: false, adult_confirmed: true },
  idempotency_key: "attualplay:session-1:content-42:view",
};

const recommendationQuery = {
  project_key: "attualplay",
  anonymous_id: "anon-123456",
  consent: {
    analytics: true,
    personalization: true,
    adult_confirmed: true,
    marketing: false,
    policy_version: "attualplay-privacy-v3-2026-09-07",
  },
};

function headers() {
  return {
    "content-type": "application/json",
    "x-matrix-client": "attualplay",
    "x-matrix-key": "mat_pk_test_1234567890",
    origin: "https://app.example.test",
  };
}

describe("Matrix Event API", () => {
  it("ingests a valid event with adult confirmation and assigns source from the client", async () => {
    const repository = new FakeRepository();
    const app = createApp({ config, repository });
    const response = await app.request("/v1/events", {
      method: "POST",
      headers: headers(),
      body: JSON.stringify(event),
    });
    expect(response.status).toBe(200);
    expect(repository.lastRow?.source).toBe("attualplay");
    expect(repository.lastRow?.anonymous_profile_id).toBeTruthy();
    expect(repository.lastRow?.consent_snapshot.adult_confirmed).toBe(true);
  });

  it("returns a quality-gated recommendation only with explicit personalization opt-in", async () => {
    const app = createApp({ config, repository: new FakeRepository() });
    const response = await app.request("/v1/recommendations/query", {
      method: "POST",
      headers: headers(),
      body: JSON.stringify(recommendationQuery),
    });
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.recommendation?.items?.[0]?.topic_key).toBe("radio");
    expect(body.policy.marketing_enabled).toBe(false);
  });

  it("rejects recommendation queries without personalization opt-in", async () => {
    const app = createApp({ config, repository: new FakeRepository() });
    const response = await app.request("/v1/recommendations/query", {
      method: "POST",
      headers: headers(),
      body: JSON.stringify({ ...recommendationQuery, consent: { ...recommendationQuery.consent, personalization: false } }),
    });
    expect(response.status).toBe(403);
  });

  it("rejects a bad client key", async () => {
    const app = createApp({ config, repository: new FakeRepository() });
    const response = await app.request("/v1/events", {
      method: "POST",
      headers: { ...headers(), "x-matrix-key": "wrong-key-value-12345" },
      body: JSON.stringify(event),
    });
    expect(response.status).toBe(401);
  });

  it("rejects a browser origin outside the allowlist", async () => {
    const app = createApp({ config, repository: new FakeRepository() });
    const response = await app.request("/v1/events", {
      method: "POST",
      headers: { ...headers(), origin: "https://evil.example" },
      body: JSON.stringify(event),
    });
    expect(response.status).toBe(403);
  });
});
