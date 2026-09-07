import { timingSafeEqual } from "node:crypto";
import { z } from "zod";
import type { RuntimeConfig } from "./config.js";
import type { MatrixRepository } from "./db.js";

export const m4ConsentSchema = z.object({
  analytics: z.boolean(),
  personalization: z.boolean(),
  adult_confirmed: z.boolean(),
  marketing: z.literal(false),
  policy_version: z.string().min(3).max(80),
}).strict().superRefine((value, ctx) => {
  if (value.analytics && !value.adult_confirmed) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["adult_confirmed"], message: "adult confirmation is required for analytics" });
  }
  if (value.personalization && !value.analytics) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["personalization"], message: "personalization requires analytics" });
  }
});

export const identityBridgeIssueSchema = z.object({
  project_key: z.string().min(2).max(100),
  external_system: z.literal("attual_one"),
  external_account_ref: z.string().uuid(),
}).strict();

export const identityLinkSchema = z.object({
  project_key: z.string().min(2).max(100),
  anonymous_id: z.string().min(3).max(200),
  bridge_code: z.string().min(12).max(120),
  consent: m4ConsentSchema,
}).strict();

export const consentSyncSchema = z.object({
  project_key: z.string().min(2).max(100),
  person_token: z.string().min(16).max(512),
  consent: m4ConsentSchema,
}).strict();

export const identityUnlinkSchema = z.object({
  project_key: z.string().min(2).max(100),
  person_token: z.string().min(16).max(512),
}).strict();

function equal(left: string, right: string): boolean {
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  return a.length === b.length && timingSafeEqual(a, b);
}

export function authenticateServerBearer(headers: Headers, expected: string): boolean {
  const raw = String(headers.get("authorization") ?? "").trim();
  if (!raw.startsWith("Bearer ")) return false;
  return equal(raw.slice(7), expected);
}

export async function notifyAttualOneLink(
  config: RuntimeConfig,
  matrixPersonId: string,
  linkStatus: "linked" | "revoked",
  correlationId: string,
): Promise<boolean> {
  try {
    const response = await fetch(config.attualOneLinkCallbackUrl, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${config.attualOneIntegrationSecret}`,
        "x-correlation-id": correlationId,
      },
      body: JSON.stringify({
        matrix_person_id: matrixPersonId,
        link_status: linkStatus,
        correlation_id: correlationId,
      }),
      signal: AbortSignal.timeout(8000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

export async function dispatchAttualOneSignals(
  repository: MatrixRepository,
  config: RuntimeConfig,
  limit = 20,
): Promise<{ delivered: number; failed: number }> {
  const pending = await repository.listPendingAttualOneSignals(limit);
  let delivered = 0;
  let failed = 0;

  for (const row of pending) {
    try {
      const response = await fetch(config.attualOneSignalUrl, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${config.attualOneIntegrationSecret}`,
          "idempotency-key": row.idempotency_key,
        },
        body: JSON.stringify(row.payload),
        signal: AbortSignal.timeout(8000),
      });
      if (response.ok || response.status === 409) {
        await repository.markSignalDelivered(row.id);
        delivered += 1;
      } else {
        await repository.markSignalFailed(row.id, `attual_one_http_${response.status}`);
        failed += 1;
      }
    } catch {
      await repository.markSignalFailed(row.id, "attual_one_network_error");
      failed += 1;
    }
  }

  return { delivered, failed };
}
