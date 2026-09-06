import { randomUUID } from "node:crypto";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { ZodError } from "zod";
import { authenticatePublicClient, AuthError } from "./auth.js";
import { loadConfig, type RuntimeConfig } from "./config.js";
import { SupabaseMatrixRepository, type MatrixRepository } from "./db.js";
import { EVENT_TYPES } from "./events/catalog.js";
import { ingestBatch, ingestOne } from "./service.js";

export type AppOptions = {
  config?: RuntimeConfig;
  repository?: MatrixRepository;
};

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

  app.use(
    "/v1/events*",
    cors({
      origin: (origin) => (allowedOrigins.has(origin.replace(/\/$/, "")) ? origin : undefined),
      allowMethods: ["POST", "OPTIONS"],
      allowHeaders: ["Content-Type", "X-Matrix-Client", "X-Matrix-Key", "X-Correlation-Id"],
      exposeHeaders: ["X-Correlation-Id"],
      maxAge: 600,
    }),
  );

  app.get("/health", (c) => c.json({ status: "ok", service: "matrix-event-api", version: "0.2.0" }));

  app.get("/ready", async (c) => {
    const ready = await repository.ready();
    return c.json({ status: ready ? "ready" : "not_ready" }, ready ? 200 : 503);
  });

  app.get("/v1/event-types", (c) => c.json({ version: 1, event_types: EVENT_TYPES }));

  app.post("/v1/events", async (c) => {
    const cid = requestCorrelationId(c.req.raw.headers);
    c.header("X-Correlation-Id", cid);
    try {
      const client = authenticatePublicClient(c.req.raw.headers, config);
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
      const client = authenticatePublicClient(c.req.raw.headers, config);
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
