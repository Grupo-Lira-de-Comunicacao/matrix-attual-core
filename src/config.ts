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

  const attualOneIntegrationSecret = required(env, "MATRIX_ATTUAL_ONE_INTEGRATION_SECRET");
  const m4InternalKey = required(env, "MATRIX_M4_INTERNAL_KEY");
  if (attualOneIntegrationSecret.length < 24 || m4InternalKey.length < 24) {
    throw new Error("M4 server-only keys are too short");
  }

  return {
    supabaseUrl: required(env, "MATRIX_SUPABASE_URL").replace(/\/$/, ""),
    dbAdminKey: required(env, "MATRIX_DB_ADMIN_KEY"),
    attualOneIntegrationSecret,
    attualOneSignalUrl: required(env, "MATRIX_ATTUAL_ONE_SIGNAL_URL"),
    attualOneLinkCallbackUrl: required(env, "MATRIX_ATTUAL_ONE_LINK_CALLBACK_URL"),
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
