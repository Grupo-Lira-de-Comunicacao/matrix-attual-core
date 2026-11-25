import { describe, expect, it, vi } from "vitest";
import { SupabaseMatrixRepository } from "../db.js";

const project = { tenantId: "11111111-1111-4111-8111-111111111111", projectId: "22222222-2222-4222-8222-222222222222", projectKey: "attualplay" };
const consent = { analytics: true, personalization: true, adult_confirmed: true, marketing: false as const, policy_version: "test-policy" };
const correlation = "33333333-3333-4333-8333-333333333333";
function setup(data: unknown = null, error: unknown = null) {
  const rpc = vi.fn().mockResolvedValue({data,error});
  const from = vi.fn();
  const repository = Object.create(SupabaseMatrixRepository.prototype) as SupabaseMatrixRepository;
  Object.defineProperty(repository, "db", { value: { rpc, from } });
  return {repository,rpc,from};
}
describe("M4 atomic one-time bridge", () => {
  it("issues a session only after a single scoped database transaction and sends hashes only", async () => {
    const { repository, rpc, from } = setup({matrix_person_id: correlation,expires_at:"2026-12-25T20:00:00Z"});
    const result = await repository.consumeIdentityBridge(project,"anon-fixture","M4-FIXTURE-12345678",consent,correlation);
    expect(rpc).toHaveBeenCalledExactlyOnceWith("matrix_m4_consume_bridge",{
      p_tenant_id:project.tenantId,p_project_id:project.projectId,
      p_bridge_hash:expect.stringMatching(/^[a-f0-9]{64}$/),
      p_anonymous_hash:expect.stringMatching(/^[a-f0-9]{64}$/),
      p_session_hash:expect.stringMatching(/^[a-f0-9]{64}$/),p_consent:consent,p_correlation_id:correlation,
    });
    expect(result.person_token).toMatch(/^mps_/);
    expect(from).not.toHaveBeenCalled();
  });
  it("returns no session when the single-use claim is lost", async () => {
    const {repository,rpc,from}=setup();
    await expect(repository.consumeIdentityBridge(project,"anon-fixture","M4-FIXTURE-12345678",consent,correlation)).rejects.toThrow("invalid or expired");
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(from).not.toHaveBeenCalled();
  });
  it("returns no session when the transaction errors", async () => {
    const {repository,from}=setup(null,{code:"test-rollback"});
    await expect(repository.consumeIdentityBridge(project,"anon-fixture","M4-FIXTURE-12345678",consent,correlation)).rejects.toThrow("could not be committed");
    expect(from).not.toHaveBeenCalled();
  });
  it("makes no RPC without explicit adult analytics consent", async () => {
    const {repository,rpc}=setup();
    await expect(repository.consumeIdentityBridge(project,"anon-fixture","M4-FIXTURE-12345678",{...consent,analytics:false},correlation)).rejects.toThrow("consent");
    expect(rpc).not.toHaveBeenCalled();
  });
});
