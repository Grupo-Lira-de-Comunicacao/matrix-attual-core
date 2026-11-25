import { expect, it, vi } from "vitest";
import { SupabaseMatrixRepository } from "../db.js";

it("does not treat a known revoked M4 session as a normal or legacy token", async () => {
  const expired = { data: { id: "fixture-id", person_id: "fixture-person", status: "revoked",
    expires_at: "2099-01-01T00:00:00.000Z" }, error: null };
  const q = { select: vi.fn(), eq: vi.fn(), maybeSingle: vi.fn().mockResolvedValue(expired) };
  q.select.mockReturnValue(q);
  q.eq.mockReturnValue(q);
  const from = vi.fn().mockReturnValue(q);
  const repo = Object.create(SupabaseMatrixRepository.prototype) as SupabaseMatrixRepository;
  Object.defineProperty(repo, "db", { value: { from } });
  await expect(repo.resolvePersonToken({ tenantId: "test-tenant", projectId: "test-project", projectKey: "attualplay" }, "fixture-token")).resolves.toBeNull();
  expect(from).toHaveBeenCalledExactlyOnceWith("matrix_person_sessions");
});
