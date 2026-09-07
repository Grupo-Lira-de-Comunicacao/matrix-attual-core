import { createHash } from "node:crypto";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { RuntimeConfig } from "./config.js";

export type ProjectRef = {
  tenantId: string;
  projectId: string;
  projectKey: string;
};

export type EventRow = {
  id: string;
  tenant_id: string;
  project_id: string;
  person_id: string | null;
  anonymous_profile_id: string | null;
  event_type: string;
  object_type: string | null;
  object_id: string | null;
  occurred_at: string;
  session_id: string | null;
  correlation_id: string;
  source: string;
  schema_version: number;
  consent_snapshot: Record<string, unknown>;
  properties: Record<string, unknown>;
  context: Record<string, unknown>;
  idempotency_key: string;
};

export type InsertResult = { eventId: string; duplicate: boolean };

export type PersonalizedTopic = {
  rank: number;
  topic_key: string;
  topic_label: string;
  score: number;
  confidence: number;
  signal_count: number;
};

export type PersonalizedRecommendation = {
  recommendation_id: string;
  reason_text: string;
  generated_at: string;
  expires_at: string | null;
  policy_version: string;
  items: PersonalizedTopic[];
};

export interface MatrixRepository {
  resolveProject(projectKey: string): Promise<ProjectRef>;
  upsertAnonymous(project: ProjectRef, anonymousId: string): Promise<string>;
  resolvePersonToken(project: ProjectRef, personToken: string): Promise<string | null>;
  insertEvent(row: EventRow): Promise<InsertResult>;
  getEligibleRecommendation(project: ProjectRef, anonymousId: string): Promise<PersonalizedRecommendation | null>;
  ready(): Promise<boolean>;
}

const ANONYMOUS_RETENTION_DAYS = 90;

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

export class SupabaseMatrixRepository implements MatrixRepository {
  private readonly db: SupabaseClient;

  constructor(config: RuntimeConfig) {
    this.db = createClient(config.supabaseUrl, config.dbAdminKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { "X-Matrix-Component": "event-api" } },
    });
  }

  async ready(): Promise<boolean> {
    const { data, error } = await this.db.from("matrix_tenants").select("id").eq("key", "grupo-lira").limit(1);
    return !error && Array.isArray(data) && data.length === 1;
  }

  async resolveProject(projectKey: string): Promise<ProjectRef> {
    const tenant = await this.db.from("matrix_tenants").select("id").eq("key", "grupo-lira").eq("status", "active").single();
    if (tenant.error || !tenant.data) throw new Error("matrix tenant is unavailable");

    const project = await this.db
      .from("matrix_projects")
      .select("id,tenant_id,project_key,status")
      .eq("tenant_id", tenant.data.id)
      .eq("project_key", projectKey)
      .eq("status", "active")
      .single();
    if (project.error || !project.data) throw new Error("matrix project is unavailable");

    return { tenantId: project.data.tenant_id, projectId: project.data.id, projectKey: project.data.project_key };
  }

  async upsertAnonymous(project: ProjectRef, anonymousId: string): Promise<string> {
    const now = new Date();
    const expiresAt = new Date(now.getTime() + ANONYMOUS_RETENTION_DAYS * 24 * 60 * 60 * 1000);
    const result = await this.db
      .from("matrix_anonymous_profiles")
      .upsert(
        {
          tenant_id: project.tenantId,
          project_id: project.projectId,
          anonymous_key_hash: sha256(anonymousId),
          last_seen_at: now.toISOString(),
          expires_at: expiresAt.toISOString(),
        },
        { onConflict: "tenant_id,project_id,anonymous_key_hash" },
      )
      .select("id")
      .single();
    if (result.error || !result.data) throw new Error("anonymous profile could not be resolved");
    return result.data.id;
  }

  async resolvePersonToken(project: ProjectRef, personToken: string): Promise<string | null> {
    const result = await this.db
      .from("matrix_identities")
      .select("person_id")
      .eq("tenant_id", project.tenantId)
      .eq("identity_type", "person_token")
      .eq("normalized_hash", sha256(personToken))
      .eq("verified", true)
      .maybeSingle();
    if (result.error) throw new Error("person token resolution failed");
    return result.data?.person_id ?? null;
  }

  async insertEvent(row: EventRow): Promise<InsertResult> {
    const inserted = await this.db.from("matrix_events").insert(row).select("id").single();
    if (!inserted.error && inserted.data) return { eventId: inserted.data.id, duplicate: false };

    if (inserted.error?.code === "23505") {
      const existing = await this.db
        .from("matrix_events")
        .select("id")
        .eq("tenant_id", row.tenant_id)
        .eq("project_id", row.project_id)
        .eq("idempotency_key", row.idempotency_key)
        .maybeSingle();
      if (!existing.error && existing.data?.id) return { eventId: existing.data.id, duplicate: true };
      throw new Error("event id conflict");
    }
    throw new Error(`event insert failed${inserted.error?.code ? ` (${inserted.error.code})` : ""}`);
  }

  async getEligibleRecommendation(project: ProjectRef, anonymousId: string): Promise<PersonalizedRecommendation | null> {
    const profile = await this.db
      .from("matrix_anonymous_profiles")
      .select("id")
      .eq("tenant_id", project.tenantId)
      .eq("project_id", project.projectId)
      .eq("anonymous_key_hash", sha256(anonymousId))
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();
    if (profile.error) throw new Error("anonymous recommendation profile lookup failed");
    if (!profile.data?.id) return null;

    const decision = await this.db
      .from("matrix_m3_decisions")
      .select("recommendation_id,policy_version,expires_at")
      .eq("project_id", project.projectId)
      .eq("anonymous_profile_id", profile.data.id)
      .eq("decision_status", "eligible")
      .gt("expires_at", new Date().toISOString())
      .order("evaluated_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (decision.error) throw new Error("M3 recommendation decision lookup failed");
    if (!decision.data?.recommendation_id) return null;

    const recommendation = await this.db
      .from("matrix_recommendations")
      .select("id,reason_text,generated_at,expires_at,source_signals")
      .eq("id", decision.data.recommendation_id)
      .eq("project_id", project.projectId)
      .eq("recommendation_type", "topic_affinity_shadow")
      .eq("status", "shadow")
      .maybeSingle();
    if (recommendation.error) throw new Error("M3 recommendation lookup failed");
    if (!recommendation.data) return null;

    const signals = Array.isArray(recommendation.data.source_signals) ? recommendation.data.source_signals : [];
    const items: PersonalizedTopic[] = signals.slice(0, 3).flatMap((raw: unknown, index: number) => {
      if (!raw || typeof raw !== "object") return [];
      const item = raw as Record<string, unknown>;
      const topicKey = String(item.topic_key ?? "").slice(0, 80);
      const topicLabel = String(item.topic_label ?? topicKey).slice(0, 120);
      const score = Number(item.score ?? 0);
      const confidence = Number(item.confidence ?? 0);
      const signalCount = Number(item.signal_count ?? 0);
      if (!topicKey || !Number.isFinite(score) || !Number.isFinite(confidence) || !Number.isFinite(signalCount)) return [];
      return [{ rank: index + 1, topic_key: topicKey, topic_label: topicLabel, score, confidence, signal_count: signalCount }];
    });
    if (!items.length) return null;

    return {
      recommendation_id: recommendation.data.id,
      reason_text: String(recommendation.data.reason_text ?? "Recomendação baseada no uso consentido do AttualPlay.").slice(0, 300),
      generated_at: recommendation.data.generated_at,
      expires_at: recommendation.data.expires_at,
      policy_version: decision.data.policy_version,
      items,
    };
  }
}
