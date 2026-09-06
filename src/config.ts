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

  return {
    supabaseUrl: required(env, "MATRIX_SUPABASE_URL").replace(/\/$/, ""),
    dbAdminKey: required(env, "MATRIX_DB_ADMIN_KEY"),
    clients: {
      attualplay: {
        id: "attualplay",
        projectKey: "attualplay",
        publishableKey,
        allowedOrigins,
        scopes: ["events:write"],
      },
    },
    maxBodyBytes: Number(env.MATRIX_MAX_BODY_BYTES ?? 262144),
    maxBatchSize: Math.min(Number(env.MATRIX_MAX_BATCH_SIZE ?? 100), 100),
  };
}
