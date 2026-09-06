alter table public.matrix_tenants enable row level security;
alter table public.matrix_projects enable row level security;
alter table public.matrix_people enable row level security;
alter table public.matrix_identities enable row level security;
alter table public.matrix_anonymous_profiles enable row level security;
alter table public.matrix_identity_links enable row level security;
alter table public.matrix_consents enable row level security;
alter table public.matrix_consent_events enable row level security;
alter table public.matrix_entities enable row level security;
alter table public.matrix_topics enable row level security;
alter table public.matrix_content enable row level security;
alter table public.matrix_content_topics enable row level security;
alter table public.matrix_events enable row level security;
alter table public.matrix_event_invalidations enable row level security;
alter table public.matrix_relationships enable row level security;
alter table public.matrix_interest_scores enable row level security;
alter table public.matrix_interest_evidence enable row level security;
alter table public.matrix_segments enable row level security;
alter table public.matrix_segment_memberships enable row level security;
alter table public.matrix_recommendations enable row level security;
alter table public.matrix_recommendation_items enable row level security;
alter table public.matrix_recommendation_feedback enable row level security;
alter table public.matrix_campaigns enable row level security;
alter table public.matrix_campaign_memberships enable row level security;
alter table public.matrix_api_clients enable row level security;
alter table public.matrix_audit_log enable row level security;
alter table public.matrix_processing_checkpoints enable row level security;
alter table public.matrix_dead_letter_events enable row level security;

-- V1 intentionally defines no broad anon/authenticated policies.
-- Application access must go through trusted backend/Edge Functions using scoped authorization.
-- Public catalog/read policies will be added only with explicit data-contract requirements.
