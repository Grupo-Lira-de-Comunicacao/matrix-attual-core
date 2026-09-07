import { z } from "zod";
import { ALLOWED_CONTEXT_KEYS, EVENT_CATALOG, EVENT_TYPES, type EventType } from "./catalog.js";

const jsonObject = z.record(z.unknown()).default({});

export const eventEnvelopeSchema = z
  .object({
    event_id: z.string().uuid(),
    event_type: z.string().min(3).max(128),
    occurred_at: z.string().datetime({ offset: true }),
    project_key: z.string().min(2).max(100),
    anonymous_id: z.string().min(3).max(200).optional().nullable(),
    person_token: z.string().min(8).max(512).optional().nullable(),
    session_id: z.string().min(1).max(200).optional().nullable(),
    object: z
      .object({
        type: z.string().min(1).max(80),
        id: z.string().min(1).max(200),
      })
      .strict()
      .optional()
      .nullable(),
    properties: jsonObject,
    context: jsonObject,
    consent: z
      .object({
        essential: z.boolean().default(true),
        analytics: z.boolean().optional(),
        personalization: z.boolean().optional(),
        marketing: z.boolean().optional(),
        adult_confirmed: z.boolean().optional(),
        policy_version: z.string().max(80).optional(),
      })
      .strict()
      .optional(),
    idempotency_key: z.string().min(8).max(200),
  })
  .strict()
  .superRefine((event, ctx) => {
    if (!event.anonymous_id && !event.person_token) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["anonymous_id"], message: "anonymous_id or person_token is required" });
    }
    if (!EVENT_TYPES.includes(event.event_type as EventType)) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["event_type"], message: "event_type is not registered in Event Catalog v1" });
      return;
    }

    const allowedProperties = new Set(EVENT_CATALOG[event.event_type as EventType]);
    for (const key of Object.keys(event.properties)) {
      if (!allowedProperties.has(key as never)) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["properties", key], message: `property not allowed for ${event.event_type}` });
      }
    }
    for (const key of Object.keys(event.context)) {
      if (!ALLOWED_CONTEXT_KEYS.has(key)) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["context", key], message: "context property is not allowlisted" });
      }
    }

    if (event.event_type === "content_progressed" && ![25, 50, 75].includes(Number(event.properties.progress_bucket))) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["properties", "progress_bucket"], message: "progress_bucket must be 25, 50 or 75" });
    }
    if (event.event_type === "content_completed") {
      const ratio = Number(event.properties.completion_ratio);
      if (!Number.isFinite(ratio) || ratio < 0.9 || ratio > 1) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, path: ["properties", "completion_ratio"], message: "completion_ratio must be between 0.9 and 1" });
      }
    }
  });

const prohibitedKey = /(^|_)(cpf|password|senha|jwt|token|service_role|service_key|bank|banco|card_number|health|saude|clinical|clinico|diagnosis|diagnostico|message|mensagem|biometric|biometria)(_|$)/i;

function findSensitiveKey(value: unknown, path: string[] = []): string[] | null {
  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index += 1) {
      const found = findSensitiveKey(value[index], [...path, String(index)]);
      if (found) return found;
    }
    return null;
  }
  if (!value || typeof value !== "object") return null;
  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    if (prohibitedKey.test(key)) return [...path, key];
    const found = findSensitiveKey(child, [...path, key]);
    if (found) return found;
  }
  return null;
}

export type EventEnvelope = z.infer<typeof eventEnvelopeSchema>;

export function parseEventEnvelope(input: unknown): EventEnvelope {
  const event = eventEnvelopeSchema.parse(input);
  const sensitive = findSensitiveKey({ properties: event.properties, context: event.context });
  if (sensitive) {
    throw new z.ZodError([
      {
        code: z.ZodIssueCode.custom,
        path: sensitive,
        message: "sensitive/prohibited data key is not accepted by the generic event API",
      },
    ]);
  }
  return event;
}
