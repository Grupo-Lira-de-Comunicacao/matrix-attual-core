import { createHash, randomBytes } from "node:crypto";
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

export type M4ConsentChoice = {
  analytics: boolean;
  personalization: boolean;
  adult_confirmed: boolean;
  marketing: false;
  policy_version: string;
};

export type IdentityBridgeIssue = {
  bridge_code: string;
  matrix_person_id: string;
  expires_at: string;
};

export type IdentityLinkResult = {
  matrix_person_id: string;
  person_token: string;
  expires_at: string;
};

export type PersonConsentResult = {
  matrix_person_id: string;
  analytics: boolean;
  personalization: boolean;
  policy_version: string;
};

export type PendingSignal = {
  id: string;
  idempotency_key: string;
  payload: Record<string, unknown>;
  attempts: number;
};

export interface MatrixRepository {
  resolveProject(projectKey: string): Promise<ProjectRef>;
  upsertAnonymous(project: ProjectRef, anonymousId: string): Promise<string>;
  resolvePersonToken(project: ProjectRef, personToken: string): Promise<string | null>;
  hasCurrentPersonConsent(personId: string, purpose: "analytics" | "personalization"): Promise<boolean>;
  insertEvent(row: EventRow): Promise<InsertResult>;
  getEligibleRecommendation(project: ProjectRef, anonymousId: string): Promise<PersonalizedRecommendation | null>;
  getEligiblePersonRecommendation(project: ProjectRef, personToken: string): Promise<PersonalizedRecommendation | null>;
  createIdentityBridge(project: ProjectRef, externalAccountRef: string, correlationId: string): Promise<IdentityBridgeIssue>;
  consumeIdentityBridge(project: ProjectRef, anonymousId: string, bridgeCode: string, consent: M4ConsentChoice, correlationId: string): Promise<IdentityLinkResult>;
  syncPersonConsent(project: ProjectRef, personToken: string, consent: M4ConsentChoice, correlationId: string): Promise<PersonConsentResult | null>;
  unlinkPerson(project: ProjectRef, personToken: string, correlationId: string): Promise<{ matrix_person_id: string } | null>;
  listPendingAttualOneSignals(limit: number): Promise<PendingSignal[]>;
  markSignalDelivered(id: string): Promise<void>;
  markSignalFailed(id: string, safeError: string): Promise<void>;
  m4Observability(): Promise<Record<string, unknown> | null>;
  ready(): Promise<boolean>;
}

const ANONYMOUS_RETENTION_DAYS = 90;
const PERSON_SESSION_DAYS = 30;
const BRIDGE_TTL_MINUTES = 10;

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function randomOpaque(prefix: string, bytes = 24): string {
  return `${prefix}${randomBytes(bytes).toString("base64url")}`;
}

function recommendationFromRows(
  decision: Record<string, unknown>,
  recommendation: Record<string, unknown>,
): PersonalizedRecommendation | null {
  const signals = Array.isArray(recommendation.source_signals) ? recommendation.source_signals : [];
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
    recommendation_id: String(recommendation.id),
    reason_text: String(recommendation.reason_text ?? "Recomendação baseada no uso consentido do AttualPlay.").slice(0, 300),
    generated_at: String(recommendation.generated_at),
    expires_at: recommendation.expires_at ? String(recommendation.expires_at) : null,
    policy_version: String(decision.policy_version ?? "m3-policy-v1"),
    items,
  };
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
    const now = new Date().toISOString();
    const session = await this.db
      .from("matrix_person_sessions")
      .select("id,person_id")
      .eq("tenant_id", project.tenantId)
      .eq("project_id", project.projectId)
      .eq("token_hash", sha256(personToken))
      .eq("status", "active")
      .gt("expires_at", now)
      .maybeSingle();
    if (!session.error && session.data?.person_id) {
      await this.db.from("matrix_person_sessions").update({ last_seen_at: now }).eq("id", session.data.id);
      return String(session.data.person_id);
    }
    if (session.error) throw new Error("person session resolution failed");

    const legacy = await this.db
      .from("matrix_identities")
      .select("person_id")
      .eq("tenant_id", project.tenantId)
      .eq("identity_type", "person_token")
      .eq("normalized_hash", sha256(personToken))
      .eq("verified", true)
      .maybeSingle();
    if (legacy.error) throw new Error("person token resolution failed");
    return legacy.data?.person_id ?? null;
  }

  async hasCurrentPersonConsent(personId: string, purpose: "analytics" | "personalization"): Promise<boolean> {
    const result = await this.db.rpc("matrix_current_person_consent", { p_person_id: personId, p_purpose: purpose });
    if (result.error) throw new Error("server-side consent lookup failed");
    return result.data === true;
  }

  private async appendConsent(
    project: ProjectRef,
    personId: string,
    purpose: "analytics" | "personalization",
    granted: boolean,
    consent: M4ConsentChoice,
    correlationId: string,
  ): Promise<void> {
    const now = new Date().toISOString();
    const status = granted ? "granted" : "withdrawn";
    const row = await this.db
      .from("matrix_consents")
      .insert({
        tenant_id: project.tenantId,
        person_id: personId,
        anonymous_profile_id: null,
        purpose,
        channel: "attualplay",
        status,
        legal_basis: "consent",
        source: "attualplay-m4",
        policy_version: consent.policy_version,
        granted_at: granted ? now : null,
        withdrawn_at: granted ? null : now,
        metadata: {
          adult_confirmed: consent.adult_confirmed,
          marketing: false,
          m4_identity_explicit: true,
        },
        created_at: now,
      })
      .select("id")
      .single();
    if (row.error || !row.data?.id) throw new Error("server-side consent could not be persisted");

    const event = await this.db.from("matrix_consent_events").insert({
      consent_id: row.data.id,
      action: granted ? "granted" : "withdrawn",
      previous_status: null,
      new_status: status,
      occurred_at: now,
      actor_type: "person",
      actor_id: personId,
      correlation_id: correlationId,
      metadata: { source: "attualplay-m4", policy_version: consent.policy_version },
    });
    if (event.error) throw new Error("consent ledger event could not be persisted");
  }

  private async persistConsent(project: ProjectRef, personId: string, consent: M4ConsentChoice, correlationId: string): Promise<PersonConsentResult> {
    const analytics = consent.analytics === true && consent.adult_confirmed === true;
    const personalization = analytics && consent.personalization === true;
    await this.appendConsent(project, personId, "analytics", analytics, consent, correlationId);
    await this.appendConsent(project, personId, "personalization", personalization, consent, correlationId);
    return { matrix_person_id: personId, analytics, personalization, policy_version: consent.policy_version };
  }

  private async audit(action: string, targetType: string, actorId: string, correlationId: string, metadata: Record<string, unknown>): Promise<void> {
    const inserted = await this.db.from("matrix_audit_log").insert({
      actor_type: "system",
      actor_id: actorId,
      action,
      target_type: targetType,
      correlation_id: correlationId,
      result: "ok",
      metadata,
      created_at: new Date().toISOString(),
    });
    if (inserted.error) throw new Error("M4 audit record failed");
  }

  async createIdentityBridge(project: ProjectRef, externalAccountRef: string, correlationId: string): Promise<IdentityBridgeIssue> {
    const externalRefHash = sha256(externalAccountRef);
    let identity = await this.db
      .from("matrix_identities")
      .select("id,person_id")
      .eq("tenant_id", project.tenantId)
      .eq("identity_type", "attual_one_account_ref")
      .eq("normalized_hash", externalRefHash)
      .maybeSingle();
    if (identity.error) throw new Error("Attual One identity lookup failed");

    let personId = identity.data?.person_id ? String(identity.data.person_id) : "";
    let identityId = identity.data?.id ? String(identity.data.id) : "";
    if (!personId) {
      const person = await this.db
        .from("matrix_people")
        .insert({ tenant_id: project.tenantId, status: "active", locale: "pt-BR" })
        .select("id")
        .single();
      if (person.error || !person.data?.id) throw new Error("Matrix person could not be created");
      personId = String(person.data.id);

      const createdIdentity = await this.db
        .from("matrix_identities")
        .insert({
          tenant_id: project.tenantId,
          person_id: personId,
          identity_type: "attual_one_account_ref",
          normalized_hash: externalRefHash,
          encrypted_value: null,
          verified: true,
          source_project_id: project.projectId,
        })
        .select("id")
        .single();
      if (createdIdentity.error || !createdIdentity.data?.id) throw new Error("Attual One identity could not be registered");
      identityId = String(createdIdentity.data.id);
    }

    await this.db
      .from("matrix_identity_bridge_tokens")
      .update({ status: "revoked" })
      .eq("project_id", project.projectId)
      .eq("external_ref_hash", externalRefHash)
      .eq("status", "pending");

    const bridgeCode = randomOpaque("M4-", 12).toUpperCase();
    const expiresAt = new Date(Date.now() + BRIDGE_TTL_MINUTES * 60 * 1000).toISOString();
    const bridge = await this.db.from("matrix_identity_bridge_tokens").insert({
      tenant_id: project.tenantId,
      project_id: project.projectId,
      person_id: personId,
      identity_id: identityId,
      external_system: "attual_one",
      external_ref_hash: externalRefHash,
      bridge_code_hash: sha256(bridgeCode),
      status: "pending",
      expires_at: expiresAt,
      correlation_id: correlationId,
    });
    if (bridge.error) throw new Error("identity bridge code could not be issued");

    await this.audit("m4.identity.bridge_issued", "matrix_identity_bridge", "attual-one", correlationId, {
      project_id: project.projectId,
      person_id: personId,
      external_system: "attual_one",
      expires_at: expiresAt,
      pii_received: false,
      marketing_enabled: false,
    });

    return { bridge_code: bridgeCode, matrix_person_id: personId, expires_at: expiresAt };
  }

  async consumeIdentityBridge(project: ProjectRef, anonymousId: string, bridgeCode: string, consent: M4ConsentChoice, correlationId: string): Promise<IdentityLinkResult> {
    const now = new Date().toISOString();
    const bridge = await this.db
      .from("matrix_identity_bridge_tokens")
      .select("id,person_id,external_system,external_ref_hash,expires_at")
      .eq("project_id", project.projectId)
      .eq("bridge_code_hash", sha256(bridgeCode))
      .eq("status", "pending")
      .gt("expires_at", now)
      .maybeSingle();
    if (bridge.error) throw new Error("identity bridge lookup failed");
    if (!bridge.data?.id || !bridge.data.person_id) throw new Error("identity bridge is invalid or expired");

    const personId = String(bridge.data.person_id);
    const anonymousProfileId = await this.upsertAnonymous(project, anonymousId);

    const linked = await this.db.from("matrix_identity_links").upsert({
      tenant_id: project.tenantId,
      project_id: project.projectId,
      anonymous_profile_id: anonymousProfileId,
      person_id: personId,
      link_reason: "explicit_attual_one_bridge",
      confidence: 1,
      link_status: "active",
      external_system: "attual_one",
      external_ref_hash: bridge.data.external_ref_hash,
      verified_at: now,
      revoked_at: null,
      metadata: { explicit_user_action: true, hidden_stitching: false, correlation_id: correlationId },
    }, { onConflict: "anonymous_profile_id,person_id" });
    if (linked.error) throw new Error("explicit identity link could not be persisted");

    await this.persistConsent(project, personId, consent, correlationId);

    const personToken = randomOpaque("mps_", 32);
    const expiresAt = new Date(Date.now() + PERSON_SESSION_DAYS * 24 * 60 * 60 * 1000).toISOString();
    const session = await this.db.from("matrix_person_sessions").insert({
      tenant_id: project.tenantId,
      project_id: project.projectId,
      person_id: personId,
      anonymous_profile_id: anonymousProfileId,
      bridge_id: bridge.data.id,
      token_hash: sha256(personToken),
      status: "active",
      issued_at: now,
      expires_at: expiresAt,
      last_seen_at: now,
      correlation_id: correlationId,
    });
    if (session.error) throw new Error("person session could not be created");

    const consumed = await this.db
      .from("matrix_identity_bridge_tokens")
      .update({ status: "consumed", consumed_at: now })
      .eq("id", bridge.data.id)
      .eq("status", "pending");
    if (consumed.error) throw new Error("identity bridge could not be consumed");

    await this.audit("m4.identity.linked", "matrix_identity_link", "attualplay", correlationId, {
      project_id: project.projectId,
      person_id: personId,
      anonymous_profile_id: anonymousProfileId,
      external_system: "attual_one",
      explicit_user_action: true,
      hidden_stitching: false,
      session_expires_at: expiresAt,
    });

    return { matrix_person_id: personId, person_token: personToken, expires_at: expiresAt };
  }

  async syncPersonConsent(project: ProjectRef, personToken: string, consent: M4ConsentChoice, correlationId: string): Promise<PersonConsentResult | null> {
    const personId = await this.resolvePersonToken(project, personToken);
    if (!personId) return null;
    const result = await this.persistConsent(project, personId, consent, correlationId);
    await this.audit("m4.consent.synced", "matrix_consent", "attualplay", correlationId, {
      project_id: project.projectId,
      person_id: personId,
      analytics: result.analytics,
      personalization: result.personalization,
      marketing: false,
      policy_version: consent.policy_version,
    });
    return result;
  }

  async unlinkPerson(project: ProjectRef, personToken: string, correlationId: string): Promise<{ matrix_person_id: string } | null> {
    const personId = await this.resolvePersonToken(project, personToken);
    if (!personId) return null;
    const now = new Date().toISOString();

    const sessions = await this.db
      .from("matrix_person_sessions")
      .update({ status: "revoked", revoked_at: now })
      .eq("tenant_id", project.tenantId)
      .eq("project_id", project.projectId)
      .eq("person_id", personId)
      .eq("status", "active");
    if (sessions.error) throw new Error("person sessions could not be revoked");

    const links = await this.db
      .from("matrix_identity_links")
      .update({ link_status: "revoked", revoked_at: now })
      .eq("tenant_id", project.tenantId)
      .eq("project_id", project.projectId)
      .eq("person_id", personId)
      .eq("external_system", "attual_one")
      .eq("link_status", "active");
    if (links.error) throw new Error("identity link could not be revoked");

    const withdrawn: M4ConsentChoice = {
      analytics: false,
      personalization: false,
      adult_confirmed: false,
      marketing: false,
      policy_version: "attualplay-privacy-v4-2026-09-07",
    };
    await this.persistConsent(project, personId, withdrawn, correlationId);
    await this.audit("m4.identity.unlinked", "matrix_identity_link", "attualplay", correlationId, {
      project_id: project.projectId,
      person_id: personId,
      external_system: "attual_one",
      marketing: false,
    });
    return { matrix_person_id: personId };
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
    return recommendationFromRows(decision.data as Record<string, unknown>, recommendation.data as Record<string, unknown>);
  }

  async getEligiblePersonRecommendation(project: ProjectRef, personToken: string): Promise<PersonalizedRecommendation | null> {
    const personId = await this.resolvePersonToken(project, personToken);
    if (!personId) return null;
    const [analytics, personalization] = await Promise.all([
      this.hasCurrentPersonConsent(personId, "analytics"),
      this.hasCurrentPersonConsent(personId, "personalization"),
    ]);
    if (!analytics || !personalization) return null;

    const decision = await this.db
      .from("matrix_m3_decisions")
      .select("recommendation_id,policy_version,expires_at")
      .eq("project_id", project.projectId)
      .eq("person_id", personId)
      .eq("decision_status", "eligible")
      .gt("expires_at", new Date().toISOString())
      .order("evaluated_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (decision.error) throw new Error("M4 person recommendation decision lookup failed");
    if (!decision.data?.recommendation_id) return null;

    const recommendation = await this.db
      .from("matrix_recommendations")
      .select("id,reason_text,generated_at,expires_at,source_signals")
      .eq("id", decision.data.recommendation_id)
      .eq("project_id", project.projectId)
      .eq("person_id", personId)
      .eq("recommendation_type", "topic_affinity_shadow")
      .eq("status", "shadow")
      .maybeSingle();
    if (recommendation.error) throw new Error("M4 person recommendation lookup failed");
    if (!recommendation.data) return null;
    return recommendationFromRows(decision.data as Record<string, unknown>, recommendation.data as Record<string, unknown>);
  }

  async listPendingAttualOneSignals(limit: number): Promise<PendingSignal[]> {
    const result = await this.db
      .from("matrix_m3_action_outbox")
      .select("id,idempotency_key,payload,attempts")
      .eq("destination", "attual_one")
      .in("status", ["pending", "failed"])
      .lte("available_at", new Date().toISOString())
      .gt("expires_at", new Date().toISOString())
      .order("created_at", { ascending: true })
      .limit(Math.max(1, Math.min(limit, 100)));
    if (result.error) throw new Error("M4 outbox read failed");
    return (result.data ?? []).map((row) => ({
      id: String(row.id),
      idempotency_key: String(row.idempotency_key),
      payload: row.payload && typeof row.payload === "object" && !Array.isArray(row.payload) ? row.payload as Record<string, unknown> : {},
      attempts: Number(row.attempts ?? 0),
    }));
  }

  async markSignalDelivered(id: string): Promise<void> {
    const result = await this.db.from("matrix_m3_action_outbox").update({
      status: "delivered",
      delivered_at: new Date().toISOString(),
      last_error: null,
      updated_at: new Date().toISOString(),
    }).eq("id", id);
    if (result.error) throw new Error("M4 outbox delivery acknowledgement failed");
  }

  async markSignalFailed(id: string, safeError: string): Promise<void> {
    const current = await this.db.from("matrix_m3_action_outbox").select("attempts").eq("id", id).maybeSingle();
    if (current.error) throw new Error("M4 outbox retry read failed");
    const attempts = Number(current.data?.attempts ?? 0) + 1;
    const delayMinutes = Math.min(60, Math.max(1, 2 ** Math.min(attempts, 5)));
    const result = await this.db.from("matrix_m3_action_outbox").update({
      status: "failed",
      attempts,
      last_error: safeError.slice(0, 240),
      available_at: new Date(Date.now() + delayMinutes * 60 * 1000).toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", id);
    if (result.error) throw new Error("M4 outbox failure acknowledgement failed");
  }

  async m4Observability(): Promise<Record<string, unknown> | null> {
    const result = await this.db.from("matrix_m4_observability_current").select("*").limit(1).maybeSingle();
    if (result.error) throw new Error("M4 observability lookup failed");
    return result.data as Record<string, unknown> | null;
  }
}
