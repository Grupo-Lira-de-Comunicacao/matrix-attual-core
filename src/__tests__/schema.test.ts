import { describe, expect, it } from "vitest";
import { parseEventEnvelope } from "../events/schema.js";

const base = {
  event_id: "6abda5c7-6ec0-4bd6-97b4-9e9d3e58f4b3",
  event_type: "content_progressed",
  occurred_at: "2026-09-06T17:30:00Z",
  project_key: "attualplay",
  anonymous_id: "anon-123456",
  properties: { content_id: "content-42", progress_bucket: 50 },
  context: { device_class: "mobile", app_version: "1.0.0" },
  consent: { essential: true, analytics: true, personalization: false },
  idempotency_key: "attualplay:session-1:content-42:50",
};

describe("EventEnvelope v1", () => {
  it("accepts an allowlisted AttualPlay event", () => {
    expect(parseEventEnvelope(base).event_type).toBe("content_progressed");
  });

  it("rejects an unregistered event type", () => {
    expect(() => parseEventEnvelope({ ...base, event_type: "mouse_moved" })).toThrow(/Event Catalog/i);
  });

  it("rejects properties outside the event allowlist", () => {
    expect(() => parseEventEnvelope({ ...base, properties: { ...base.properties, email: "x@example.com" } })).toThrow(/not allowed/i);
  });

  it("rejects noncanonical progress buckets", () => {
    expect(() => parseEventEnvelope({ ...base, properties: { content_id: "content-42", progress_bucket: 30 } })).toThrow(/25, 50 or 75/i);
  });

  it("requires an anonymous or resolved subject", () => {
    const { anonymous_id: _anonymous, ...withoutSubject } = base;
    expect(() => parseEventEnvelope(withoutSubject)).toThrow(/anonymous_id or person_token/i);
  });

  it("rejects context outside the minimization allowlist", () => {
    expect(() => parseEventEnvelope({ ...base, context: { ...base.context, ip_address: "127.0.0.1" } })).toThrow(/context property is not allowlisted/i);
  });
});
