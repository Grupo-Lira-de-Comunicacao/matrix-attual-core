import { afterEach, describe, expect, it, vi } from "vitest";
import { createApp } from "../app.js";
import type {
  MatrixRepository,
  ProjectRef,
  EventRow,
  InsertResult,
  PersonalizedRecommendation,
  M4ConsentChoice,
  PendingSignal,
} from "../db.js";
import type { RuntimeConfig } from "../config.js";

class FakeRepository implements MatrixRepository {
  lastRow: EventRow | null = null;
  serverConsent = true;
  personTokenValid = true;
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
  async resolvePersonToken() { return this.personTokenValid ? "44444444-4444-4444-8444-444444444444" : null; }
  async hasCurrentPersonConsent() { return this.serverConsent; }
  async insertEvent(row: EventRow): Promise<InsertResult> {
    this.lastRow = row;
    return { eventId: row.id, duplicate: false };
  }
  async getEligibleRecommendation() { return this.recommendation; }
  async getEligiblePersonRecommendation() { return this.serverConsent ? this.recommendation : null; }
  async createIdentityBridge() {
    return {
      bridge_code: "M4-ABCDEF1234567890",
      matrix_person_id: "44444444-4444-4444-8444-444444444444",
      expires_at: "2026-09-07T13:10:00Z",
    };
  }
  async consumeIdentityBridge(_project: ProjectRef, _anonymousId: string, _bridgeCode: string, _consent: M4ConsentChoice) {
    return {
      matrix_person_id: "44444444-4444-4444-8444-444444444444",
      person_token: "mps_test_person_session_1234567890",
      expires_at: "2026-10-07T13:00:00Z",
    };
  }
  async syncPersonConsent(_project: ProjectRef, _personToken: string, consent: M4ConsentChoice) {
    if (!this.personTokenValid) return null;
    return {
      matrix_person_id: "44444444-4444-4444-8444-444444444444",
      analytics: consent.analytics,
      personalization: consent.analytics && consent.personalization,
      policy_version: consent.policy_version,
    };
  }
  async unlinkPerson() {
    return this.personTokenValid ? { matrix_person_id: "44444444-4444-4444-8444-444444444444" } : null;
  }
  async listPendingAttualOneSignals(): Promise<PendingSignal[]> { return []; }
  async markSignalDelivered() {}
  async markSignalFailed() {}
  async m4Observability() { return { active_identity_links: 1, n8n_executable_rows: 0, marketing_enabled: false }; }
}

const config: RuntimeConfig = {
  supabaseUrl: "https://example.invalid",
  dbAdminKey: "not-used-in-test",
  maxBodyBytes: 262144,
  maxBatchSize: 100,
  attualOneIntegrationSecret: "test-attual-one-secret-1234567890",
  attualOneSignalUrl: "https://one.example.test/api/integrations/matrix/signals",
  attualOneLinkCallbackUrl: "https://one.example.test/api/integrations/matrix/links",
  m4InternalKey: "test-m4-internal-key-123456789012",
  clients: {
    attualplay: {
      id: "attualplay",
      projectKey: "attualplay",
      publishableKey: "mat_pk_test_1234567890",
      allowedOrigins: ["https://app.example.test"],
      scopes: ["events:write", "recommendations:read", "identity:link", "consent:write"],
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
    policy_version: "attualplay-privacy-v4-2026-09-07",
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

afterEach(() => vi.restoreAllMocks());

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

  it("rejects identified analytics events if server-side consent is withdrawn", async () => {
    const repository = new FakeRepository();
    repository.serverConsent = false;
    const app = createApp({ config, repository });
    const response = await app.request("/v1/events", {
      method: "POST",
      headers: headers(),
      body: JSON.stringify({ ...event, person_token: "mps_test_person_session_1234567890" }),
    });
    expect(response.status).toBe(403);
    expect(repository.lastRow).toBeNull();
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

  it("supports a person-session recommendation query with server-side consent", async () => {
    const app = createApp({ config, repository: new FakeRepository() });
    const response = await app.request("/v1/recommendations/query", {
      method: "POST",
      headers: headers(),
      body: JSON.stringify({ ...recommendationQuery, anonymous_id: undefined, person_token: "mps_test_person_session_1234567890" }),
    });
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.policy.server_side_consent).toBe(true);
    expect(body.recommendation?.items?.[0]?.topic_key).toBe("radio");
  });

  it("links identity only through an explicit one-time bridge and keeps marketing false", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(Response.json({ accepted: true, matrix_person_id: "44444444-4444-4444-8444-444444444444", link_status: "linked", marketing_enabled: false, external_action_enabled: false }));
    const app = createApp({ config, repository: new FakeRepository() });
    const response = await app.request("/v1/identity/link", {
      method: "POST",
      headers: headers(),
      body: JSON.stringify({
        project_key: "attualplay",
        anonymous_id: "anon-123456",
        bridge_code: "M4-ABCDEF1234567890",
        consent: recommendationQuery.consent,
      }),
    });
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.identity.person_token).toMatch(/^mps_/);
    expect(body.consent.marketing).toBe(false);
    expect(body.attual_one_link_status).toBe("linked");
  });

  it("rejects a bridge link without explicit adult analytics consent before repository mutation", async () => {
    const repository = new FakeRepository();
    const consume = vi.spyOn(repository, "consumeIdentityBridge");
    const app = createApp({ config, repository });
    const response = await app.request("/v1/identity/link", {
      method: "POST",
      headers: headers(),
      body: JSON.stringify({
        project_key: "attualplay",
        anonymous_id: "anon-123456",
        bridge_code: "M4-ABCDEF1234567890",
        consent: { ...recommendationQuery.consent, analytics: false, personalization: false, adult_confirmed: false },
      }),
    });
    expect(response.status).toBe(400);
    expect(consume).not.toHaveBeenCalled();
  });

  it("syncs identified consent and rejects marketing authorization", async () => {
    const app = createApp({ config, repository: new FakeRepository() });
    const response = await app.request("/v1/consents", {
      method: "POST",
      headers: headers(),
      body: JSON.stringify({
        project_key: "attualplay",
        person_token: "mps_test_person_session_1234567890",
        consent: { ...recommendationQuery.consent, marketing: false },
      }),
    });
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.consent.personalization).toBe(true);
    expect(body.consent.marketing).toBe(false);
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


describe("M4 downstream receipts at the API boundary", () => {
  it("keeps local revocation pending when One has not confirmed its effects", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValueOnce(Response.json({ accepted: true }));
    const app = createApp({ config, repository: new FakeRepository() });
    const response = await app.request("/v1/identity/unlink", {
      method: "POST",
      headers: headers(),
      body: JSON.stringify({ project_key: "attualplay", person_token: "mps_test_person_session_1234567890" }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ unlinked: true, attual_one_link_status: "revoked_callback_pending" });
  });

  it("records only the matching active receipt as a delivered signal", async () => {
    const repo = new FakeRepository();
    vi.spyOn(repo, "listPendingAttualOneSignals").mockResolvedValue([
      { id: "fixture-1", idempotency_key: "fixture-signal-1", payload: {}, attempts: 0 },
      { id: "fixture-2", idempotency_key: "fixture-signal-2", payload: {}, attempts: 0 },
      { id: "fixture-3", idempotency_key: "fixture-signal-3", payload: {}, attempts: 0 },
    ]);
    const delivered = vi.spyOn(repo, "markSignalDelivered");
    const failed = vi.spyOn(repo, "markSignalFailed");
    vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(Response.json({ accepted: true, duplicate: true, signal_key: "fixture-signal-1", processing_status: "linked" }))
      .mockResolvedValueOnce(new Response(null, { status: 409 }))
      .mockResolvedValueOnce(Response.json({ accepted: true, duplicate: false, signal_key: "fixture-signal-3", processing_status: "suppressed" }));
    const app = createApp({ config, repository: repo });
    const response = await app.request("/v1/internal/m4/dispatch", {
      method: "POST",
      headers: { authorization: `Bearer ${config.m4InternalKey}` },
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ delivered: 1, failed: 2, marketing_enabled: false, n8n_external_actions_enabled: false });
    expect(delivered).toHaveBeenCalledExactlyOnceWith("fixture-1");
    expect(failed).toHaveBeenCalledWith("fixture-2", "attual_one_http_409");
    expect(failed).toHaveBeenCalledWith("fixture-3", "attual_one_unconfirmed_receipt");
  });
});
