import { describe, expect, it, vi } from "vitest";
import { SupabaseMatrixRepository } from "../db.js";

const project = { tenantId: "11111111-1111-4111-8111-111111111111", projectId: "22222222-2222-4222-8222-222222222222", projectKey: "attualplay" };
const consent = { analytics: true, personalization: true, adult_confirmed: true, marketing: false as const, policy_version: "test-policy" };

function setup() {
  // Simulate the loser of a concurrent conditional UPDATE, which returns no row.
  const builder = {
    update: vi.fn(), eq: vi.fn(), gt: vi.fn(), select: vi.fn(),
    maybeSingle: vi.fn().mockResolvedValue({ data: null, error: null }),
  };
  for (const key of ["update", "eq", "gt", "select"] as const) builder[key].mockReturnValue(builder);
  const from = vi.fn().mockReturnValue(builder);
  const repository = Object.create(SupabaseMatrixRepository.prototype) as SupabaseMatrixRepository;
  Object.defineProperty(repository, "db", { value: { from } });
  return { repository, from, builder };
}

describe("M4 conditional one-time claim", () => {
  it("rejects a lost claim before any link, consent, profile or session writes", async () => {
    const { repository, from, builder } = setup();
    await expect(repository.consumeIdentityBridge(project, "anon-test", "M4-TEST-12345678", consent, "test-correlation")).rejects.toThrow("invalid or expired");
    expect(from).toHaveBeenCalledTimes(1);
    expect(from).toHaveBeenCalledWith("matrix_identity_bridge_tokens");
    expect(builder.update).toHaveBeenCalledWith(expect.objectContaining({ status: "consumed" }));
    expect(builder.eq).toHaveBeenCalledWith("tenant_id", project.tenantId);
    expect(builder.eq).toHaveBeenCalledWith("project_id", project.projectId);
    expect(builder.eq).toHaveBeenCalledWith("status", "pending");
    expect(builder.gt).toHaveBeenCalledWith("expires_at", expect.any(String));
    expect(builder.update.mock.invocationCallOrder[0]).toBeLessThan(builder.select.mock.invocationCallOrder[0]);
  });
  it("does not touch the database when analytics consent is not granted", async () => {
    const { repository, from } = setup();
    await expect(repository.consumeIdentityBridge(project, "anon-test", "M4-TEST-12345678", { ...consent, analytics: false, personalization: false }, "test-correlation")).rejects.toThrow("consent");
    expect(from).not.toHaveBeenCalled();
  });
});
