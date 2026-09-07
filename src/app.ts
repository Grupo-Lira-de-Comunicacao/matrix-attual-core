import { randomUUID } from "node:crypto";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { z, ZodError } from "zod";
import { authenticatePublicClient, AuthError } from "./auth.js";
import { loadConfig, type RuntimeConfig } from "./config.js";
import { SupabaseMatrixRepository, type MatrixRepository } from "./db.js";
import { EVENT_TYPES } from "./events/catalog.js";
import { ingestBatch, ingestOne } from "./service.js";

export type AppOptions = {
  config?: RuntimeConfig;
  repository?: MatrixRepository;
};

const recommendationQuerySchema = z.object({
  project_key: z.string().min(2).max(100),
  anonymous_id: z.string().min(3).max(200),
  consent: z.object({
    analytics: z.literal(true),
    personalization: z.literal(true),
    adult_confirmed: z.literal(true),
    marketing: z.boolean().optional(),
    policy_version: z.string().min(3).max(80),
  }).strict(),
}).strict();

function requestCorrelationId(headers: Headers): string {
  const value = String(headers.get("x-correlation-id") ?? "").trim();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
    ? value
    : randomUUID();
}

async function parseJsonBody(request: Request, maxBodyBytes: number): Promise<unknown> {
  const raw = await request.text();
  if (Buffer.byteLength(raw, "utf8") > maxBodyBytes) {
    const error = new Error("request body exceeds Matrix limit");
    Object.assign(error, { status: 413 });
    throw error;
  }
  try {
    return JSON.parse(raw);
  } catch {
    const error = new Error("invalid JSON body");
    Object.assign(error, { status: 400 });
    throw error;
  }
}

export function createApp(options: AppOptions = {}) {
  const config = options.config ?? loadConfig();
  const repository = options.repository ?? new SupabaseMatrixRepository(config);
  const allowedOrigins = new Set(Object.values(config.clients).flatMap((client) => client.allowedOrigins));
  const app = new Hono();

  const publicCors = cors({
    origin: (origin) => (allowedOrigins.has(origin.replace(/\/$/, "")) ? origin : undefined),
    allowMethods: ["POST", "OPTIONS"],
    allowHeaders: ["Content-Type", "X-Matrix-Client", "X-Matrix-Key", "X-Correlation-Id"],
    exposeHeaders: ["X-Correlation-Id"],
    maxAge: 600,
  });

  app.use("/v1/events*", publicCors);
  app.use("/v1/recommendations*", publicCors);

  app.get("/health", (c) => c.json({ status: "ok", service: "matrix-event-api", version: "0.3.0" }));

  app.get("/ready", async (c) => {
    const ready = await repository.ready();
    return c.json({ status: ready ? "ready" : "not_ready" }, ready ? 200 : 503);
  });

  app.get("/v1/event-types", (c) => c.json({ version: 1, event_types: EVENT_TYPES }));

  app.post("/v1/recommendations/query", async (c) => {
    const cid = requestCorrelationId(c.req.raw.headers);
    c.header("X-Correlation-Id", cid);
    try {
      const client = authenticatePublicClient(c.req.raw.headers, config, "recommendations:read");
      const body = recommendationQuerySchema.parse(await parseJsonBody(c.req.raw, config.maxBodyBytes));
      if (body.project_key !== client.projectKey) {
        return c.json({ error: { code: "project_scope_mismatch", message: "recommendation project does not match client scope", correlation_id: cid } }, 403);
      }
      if (body.consent.marketing === true) {
        return c.json({ error: { code: "marketing_not_enabled", message: "M3 personalization does not authorize marketing", correlation_id: cid } }, 403);
      }
      const project = await repository.resolveProject(body.project_key);
      const recommendation = await repository.getEligibleRecommendation(project, body.anonymous_id);
      return c.json({ recommendation, policy: { personalization_opt_in: true, marketing_enabled: false }, correlation_id: cid }, 200);
    } catch (error) {
      if (error instanceof AuthError) {
        return c.json({ error: { code: "unauthorized", message: error.message, correlation_id: cid } }, error.status);
      }
      if (error instanceof ZodError) {
        return c.json({ error: { code: "personalization_consent_required", message: "analytics, personalization and adult confirmation must be explicitly granted", correlation_id: cid } }, 403);
      }
      return c.json({ error: { code: "recommendation_query_failed", message: "recommendation query failed", correlation_id: cid } }, 500);
    }
  });

  app.post("/v1/events", async (c) => {
    const cid = requestCorrelationId(c.req.raw.headers);
    c.header("X-Correlation-Id", cid);
    try {
      const client = authenticatePublicClient(c.req.raw.headers, config, "events:write");
      const body = await parseJsonBody(c.req.raw, config.maxBodyBytes);
      const result = await ingestOne(repository, client, body, cid);
      return c.json(result, 200);
    } catch (error) {
      if (error instanceof AuthError) {
        return c.json({ error: { code: "unauthorized", message: error.message, correlation_id: cid } }, error.status);
      }
      if (error instanceof ZodError) {
        return c.json({ error: { code: "invalid_event", message: error.issues[0]?.message ?? "invalid event", correlation_id: cid } }, 400);
      }
      const status = Number((error as { status?: number })?.status ?? 500);
      const safeStatus = status === 413 ? 413 : status === 400 ? 400 : 500;
      const message = safeStatus === 500 ? "event ingestion failed" : String((error as Error)?.message ?? "request failed");
      return c.json({ error: { code: safeStatus === 413 ? "payload_too_large" : "ingest_failed", message, correlation_id: cid } }, safeStatus);
    }
  });

  app.post("/v1/events/batch", async (c) => {
    const cid = requestCorrelationId(c.req.raw.headers);
    c.header("X-Correlation-Id", cid);
    try {
      const client = authenticatePublicClient(c.req.raw.headers, config, "events:write");
      const body = await parseJsonBody(c.req.raw, config.maxBodyBytes);
      const events = (body as { events?: unknown[] })?.events;
      if (!Array.isArray(events) || events.length < 1 || events.length > config.maxBatchSize) {
        return c.json({ error: { code: "invalid_batch", message: `events must contain 1-${config.maxBatchSize} items`, correlation_id: cid } }, 400);
      }
      const results = await ingestBatch(repository, client, events, cid);
      return c.json({ accepted: results.length, duplicates: results.filter((item) => item.duplicate).length, correlation_id: cid, results }, 200);
    } catch (error) {
      if (error instanceof AuthError) {
        return c.json({ error: { code: "unauthorized", message: error.message, correlation_id: cid } }, error.status);
      }
      if (error instanceof ZodError) {
        return c.json({ error: { code: "invalid_event", message: error.issues[0]?.message ?? "invalid event", correlation_id: cid } }, 400);
      }
      const status = Number((error as { status?: number })?.status ?? 500);
      const safeStatus = status === 413 ? 413 : 500;
      return c.json({ error: { code: safeStatus === 413 ? "payload_too_large" : "batch_ingestion_failed", message: safeStatus === 500 ? "batch ingestion failed" : String((error as Error)?.message), correlation_id: cid } }, safeStatus);
    }
  });

  app.notFound((c) => c.json({ error: { code: "not_found", message: "route not found", correlation_id: randomUUID() } }, 404));
  return app;
}
