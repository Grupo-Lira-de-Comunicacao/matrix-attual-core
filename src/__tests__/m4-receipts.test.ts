import assert from "node:assert/strict";
import { it as test } from "vitest";
import { hasLinkReceipt, hasSignalReceipt } from "../m4-receipts.js";

const signalKey = "m4-fixture-signal-001";
const signal = { accepted: true, duplicate: false, signal_key: signalKey, processing_status: "linked" };
const person = "11111111-1111-4111-8111-111111111111";
const revocation = { accepted: true, matrix_person_id: person, link_status: "revoked", marketing_enabled: false, external_action_enabled: false };

test("acknowledges a persisted linked signal or confirmed duplicate for the same key", async () => {
  assert.equal(await hasSignalReceipt(Response.json(signal, { status: 201 }), signalKey), true);
  assert.equal(await hasSignalReceipt(Response.json({ ...signal, duplicate: true }), signalKey), true);
});

test("does not count generic conflicts, transient responses, invalid receipts, or inactive records as delivery", async () => {
  const invalid = [
    Response.json(signal, { status: 409 }),
    new Response(null, { status: 204 }),
    new Response("not json"),
    Response.json({ accepted: true, duplicate: true, signal_key: signalKey }),
    Response.json({ ...signal, signal_key: "different" }),
    Response.json({ ...signal, processing_status: "unlinked" }),
    Response.json({ ...signal, processing_status: "suppressed" }),
  ];
  for (const response of invalid) assert.equal(await hasSignalReceipt(response, signalKey), false);
});

test("confirms revocation only with the correct subject, state and disabled action flags", async () => {
  assert.equal(await hasLinkReceipt(Response.json(revocation), person, "revoked"), true);
  assert.equal(await hasLinkReceipt(Response.json({ ...revocation, link_status: "linked" }), person, "revoked"), false);
  assert.equal(await hasLinkReceipt(Response.json({ ...revocation, marketing_enabled: true }), person, "revoked"), false);
  assert.equal(await hasLinkReceipt(Response.json({ ...revocation, external_action_enabled: true }), person, "revoked"), false);
  assert.equal(await hasLinkReceipt(Response.json({ ...revocation, matrix_person_id: "different" }), person, "revoked"), false);
  assert.equal(await hasLinkReceipt(Response.json(revocation, { status: 503 }), person, "revoked"), false);
});
