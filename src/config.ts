export type PublicClientConfig = {
  id: string;
  projectKey: string;
  publishableKey: string;
  allowedOrigins: string[];
  scopes: readonly string[];
};

export type RuntimeConfig = {
  supabaseUrl: string;
  dbAdminKey: string;
  clients: Record<string, PublicClientConfig>;
  maxBodyBytes: number;
  maxBatchSize: number;
  attualOneIntegrationSecret: string;
  attualOneSignalUrl: string;
  attualOneLinkCallbackUrl: string;
  m4InternalKey: string;
};

function required(env: NodeJS.ProcessEnv, name: string): string {
  const value = String(env[name] ?? "").trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function optional(env: NodeJS.ProcessEnv, name: string): string {
  return String(env[name] ?? "").trim();
}

function parseOrigins(value: string): string[] {
  return value
    .split(",")
    .map((item) => item.trim().replace(/\/$/, ""))
    .filter(Boolean);
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): RuntimeConfig {
  const allowedOrigins = parseOrigins(required(env, "MATRIX_ALLOWED_ORIGINS"));
  if (!allowedOrigins.length) throw new Error("MATRIX_ALLOWED_ORIGINS must contain at least one origin");

  const publishableKey = required(env, "MATRIX_ATTUALPLAY_PUBLIC_KEY");
  if (publishableKey.length < 16) throw new Error("MATRIX_ATTUALPLAY_PUBLIC_KEY is too short");

  // M4 integrations are fail-closed until their server-only credentials are provisioned.
  // Missing M4 variables must not take the already-operational M0-M3 API offline.
  const attualOneIntegrationSecret = optional(env, "MATRIX_ATTUAL_ONE_INTEGRATION_SECRET");
  const m4InternalKey = optional(env, "MATRIX_M4_INTERNAL_KEY");
  const attualOneSignalUrl = optional(env, "MATRIX_ATTUAL_ONE_SIGNAL_URL");
  const attualOneLinkCallbackUrl = optional(env, "MATRIX_ATTUAL_ONE_LINK_CALLBACK_URL");

  if (attualOneIntegrationSecret && attualOneIntegrationSecret.length < 24) {
    throw new Error("MATRIX_ATTUAL_ONE_INTEGRATION_SECRET is too short");
  }
  if (m4InternalKey && m4InternalKey.length < 24) {
    throw new Error("MATRIX_M4_INTERNAL_KEY is too short");
  }

  return {
    supabaseUrl: required(env, "MATRIX_SUPABASE_URL").replace(/\/$/, ""),
    dbAdminKey: required(env, "MATRIX_DB_ADMIN_KEY"),
    attualOneIntegrationSecret,
    attualOneSignalUrl,
    attualOneLinkCallbackUrl,
    m4InternalKey,
    clients: {
      attualplay: {
        id: "attualplay",
        projectKey: "attualplay",
        publishableKey,
        allowedOrigins,
        scopes: ["events:write", "recommendations:read", "identity:link", "consent:write"],
      },
    },
    maxBodyBytes: Number(env.MATRIX_MAX_BODY_BYTES ?? 262144),
    maxBatchSize: Math.min(Number(env.MATRIX_MAX_BATCH_SIZE ?? 100), 100),
  };
}
