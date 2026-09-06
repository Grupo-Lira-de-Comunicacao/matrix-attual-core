import { timingSafeEqual } from "node:crypto";
import type { PublicClientConfig, RuntimeConfig } from "./config.js";

export class AuthError extends Error {
  constructor(public status: 401 | 403, message: string) {
    super(message);
  }
}

function equal(a: string, b: string): boolean {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}

export function authenticatePublicClient(headers: Headers, config: RuntimeConfig): PublicClientConfig {
  const clientId = String(headers.get("x-matrix-client") ?? "").trim();
  const providedKey = String(headers.get("x-matrix-key") ?? "").trim();
  if (!clientId || !providedKey) throw new AuthError(401, "Matrix client credentials are required");

  const client = config.clients[clientId];
  if (!client || !equal(providedKey, client.publishableKey)) {
    throw new AuthError(401, "Invalid Matrix client credentials");
  }
  if (!client.scopes.includes("events:write")) throw new AuthError(403, "Client cannot write events");

  const origin = String(headers.get("origin") ?? "").trim().replace(/\/$/, "");
  if (origin && !client.allowedOrigins.includes(origin)) throw new AuthError(403, "Origin is not allowed");
  return client;
}
