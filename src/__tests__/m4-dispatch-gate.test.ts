import { describe, expect, it, vi } from "vitest";
import { SupabaseMatrixRepository } from "../db.js";

const fixture = {
  tenant_id: "tenant-fixture", project_id: "project-fixture", person_id: "person-fixture",
  decision_id: "decision-fixture", idempotency_key: "key-fixture",
  payload: { matrix_person_id: "person-fixture", signal_key: "key-fixture",
    policy_version: "m3-policy-v1", purpose: "personalization",
    marketing_allowed: false, external_action_allowed: false },
};

function repoWith(analytics = true, personalization = true, linkPresent = true) {
  const query = (data: unknown) => {
    const q = { select: vi.fn(), eq: vi.fn(), in: vi.fn(), lte: vi.fn(), gt: vi.fn(), limit: vi.fn(), maybeSingle: vi.fn().mockResolvedValue({ data, error: null }) };
    for (const key of ["select", "eq", "in", "lte", "gt", "limit"] as const) q[key].mockReturnValue(q);
    return q;
  };
  const tables = {
    matrix_m3_action_outbox: query(fixture),
    matrix_m3_decisions: query({ id: "decision-fixture" }),
    matrix_m3_policies: query({ id: "policy-fixture" }),
    matrix_identity_links: query(linkPresent ? { id: "link-fixture" } : null),
  };
  const repo = Object.create(SupabaseMatrixRepository.prototype) as SupabaseMatrixRepository;
  Object.defineProperty(repo, "db", { value: { from: (table: keyof typeof tables) => tables[table] } });
  vi.spyOn(repo, "hasCurrentPersonConsent").mockResolvedValueOnce(analytics).mockResolvedValueOnce(personalization);
  return { repo, tables };
}

describe("pre-dispatch consent and governance", () => {
  it("scopes the live link, decision and policy to a tenant and project", async () => {
    const { repo, tables } = repoWith();
    await expect(repo.getSignalDispatchGate("row-fixture")).resolves.toBe("allowed");
    for (const table of [tables.matrix_identity_links, tables.matrix_m3_decisions, tables.matrix_m3_policies]) {
      expect(table.eq).toHaveBeenCalledWith("tenant_id", fixture.tenant_id);
      expect(table.eq).toHaveBeenCalledWith("project_id", fixture.project_id);
    }
    expect(tables.matrix_m3_policies.eq).toHaveBeenCalledWith("marketing_enabled", false);
    expect(tables.matrix_m3_policies.eq).toHaveBeenCalledWith("n8n_external_actions_enabled", false);
  });
  it("does not allow dispatch when an active link or a required consent is absent", async () => {
    for (const [analytics, personalization, link] of [[false, true, true], [true, false, true], [true, true, false]]) {
      await expect(repoWith(analytics, personalization, link).repo.getSignalDispatchGate("row-fixture")).resolves.toBe("ineligible");
    }
  });
});
