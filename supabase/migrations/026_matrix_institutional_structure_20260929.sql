begin;

-- 026 / GL-ESTRUTURA-20260929
-- Institutional hierarchy is distinct from the Matrix technical/context graph.
-- No person records, consent changes, deletions, marketing or external actions.

do $$
begin
  if (select count(*) from public.matrix_tenants where key = 'grupo-lira') <> 1 then
    raise exception 'Matrix institutional migration: canonical tenant missing/ambiguous';
  end if;
  if (select count(*)
      from public.matrix_entities e
      join public.matrix_tenants t on t.id = e.tenant_id
      where t.key = 'grupo-lira' and e.slug in
      ('grupo-lira-de-comunicacao', 'matrix-attual', 'nucleo-midia',
       'lira-technology', 'tv-attual', 'radio-attual', 'att-comunica',
       'studio-lira', 'attual-records', 'femac-sp', 'miss-caçapava',
       'taiada-fashion', 'casting-attual-360')) <> 13 then
    raise exception 'Matrix institutional migration: expected baseline entities missing';
  end if;
end $$;

-- Add only approved new institutional units and previously unregistered platforms.
-- UUIDs and records of pre-existing entities are preserved.
with tenant as (
  select id from public.matrix_tenants where key = 'grupo-lira'
), contextual as (
  select d.id
  from public.matrix_source_domains d
  join tenant t on t.id = d.tenant_id
  where d.domain_key = 'contextual'
), incoming(entity_type, slug, code, name, nucleus, description) as (
  values
    ('organizational_unit','nucleo-comunicacao-producao','NUC-007',
      'Comunicação e Produção','comunicacao-producao','Pilar institucional aprovado em 29/09/2026'),
    ('organizational_unit','nucleo-cultura-eventos-projetos','NUC-008',
      'Cultura, Eventos e Projetos','cultura-eventos-projetos','Pilar institucional aprovado em 29/09/2026'),
    ('platform','attual-one','SYS-005',
      'ATTUAL ONE','tecnologia','Plataforma sob Lira Technology'),
    ('platform','attual-autopilot','SYS-006',
      'ATTUAL AUTOPILOT','tecnologia','Plataforma sob Lira Technology'),
    ('platform','attual-display-indoor','SYS-007',
      'ATTUAL DISPLAY / INDOOR','tecnologia','Plataforma sob Lira Technology'),
    ('platform','attual-conecta-imoveis','SYS-008',
      'ATTUAL CONECTA IMÓVEIS','tecnologia','Plataforma sob Lira Technology'),
    ('platform','tv-attual-app','SYS-009',
      'TV ATTUAL APP','tecnologia','Plataforma sob Lira Technology'),
    ('platform','attual-conecta-social','SYS-010',
      'ATTUAL CONECTA SOCIAL','tecnologia','Plataforma sob Lira Technology')
)
insert into public.matrix_entities (
  tenant_id, entity_type, external_key, name, status,
  slug, code, nucleus, source_domain_id, short_description, metadata
)
select tenant.id, i.entity_type, 'catalog:' || i.slug, i.name, 'active',
       i.slug, i.code, i.nucleus, contextual.id, i.description,
       jsonb_build_object(
         'institutional_chart', true,
         'institutional_decision', 'GL-ESTRUTURA-20260929',
         'institutional_revision', '2026-09-29'
       )
from tenant cross join contextual cross join incoming i
on conflict (tenant_id, slug) do update set
  name = excluded.name,
  short_description = excluded.short_description,
  metadata = public.matrix_entities.metadata || excluded.metadata,
  updated_at = now();

-- MATRIX is a separate technical/contextual root, NOT an organizational parent.
-- Legacy technical nuclei and non-listed initiatives remain intact.
with tenant as (select id from public.matrix_tenants where key = 'grupo-lira')
update public.matrix_entities e
set parent_entity_id = null,
    metadata = e.metadata || jsonb_build_object(
      'institutional_chart', false,
      'catalog_role', 'technical_context',
      'institutional_decision', 'GL-ESTRUTURA-20260929'
    ),
    updated_at = now()
from tenant t
where e.tenant_id = t.id and e.slug = 'matrix-attual';

-- The four official pillars are direct children of Grupo Lira.
-- Explicitly enumerating the approved children prevents silent restructuring
-- of projects that are not listed in the institutional organogram.
with tenant as (
  select id from public.matrix_tenants where key = 'grupo-lira'
), mapping(child_slug, parent_slug) as (
  values
    ('nucleo-midia','grupo-lira-de-comunicacao'),
    ('nucleo-comunicacao-producao','grupo-lira-de-comunicacao'),
    ('nucleo-cultura-eventos-projetos','grupo-lira-de-comunicacao'),
    ('lira-technology','grupo-lira-de-comunicacao'),
    ('tv-attual','nucleo-midia'),
    ('radio-attual','nucleo-midia'),
    ('att-comunica','nucleo-comunicacao-producao'),
    ('studio-lira','nucleo-comunicacao-producao'),
    ('attual-records','nucleo-comunicacao-producao'),
    ('femac-sp','nucleo-cultura-eventos-projetos'),
    ('miss-caçapava','nucleo-cultura-eventos-projetos'),
    ('taiada-fashion','nucleo-cultura-eventos-projetos'),
    ('attual-one','lira-technology'),
    ('attual-autopilot','lira-technology'),
    ('attual-display-indoor','lira-technology'),
    ('attual-conecta-imoveis','lira-technology'),
    ('casting-attual-360','lira-technology'),
    ('tv-attual-app','lira-technology'),
    ('attual-conecta-social','lira-technology')
)
update public.matrix_entities child
set parent_entity_id = parent.id,
    metadata = child.metadata || jsonb_build_object(
      'institutional_chart', true,
      'institutional_decision', 'GL-ESTRUTURA-20260929',
      'institutional_revision', '2026-09-29'
    ),
    updated_at = now()
from mapping m
join public.matrix_entities parent on parent.slug = m.parent_slug
join tenant t on t.id = parent.tenant_id
where child.tenant_id = t.id and child.slug = m.child_slug;

-- Preserve the same entity/slug/UUID while applying the official display labels.
with tenant as (select id from public.matrix_tenants where key = 'grupo-lira')
update public.matrix_entities e
set name = case e.slug
    when 'lira-technology' then 'Lira Technology'
    when 'nucleo-midia' then 'MÍDIA'
    when 'casting-attual-360' then 'CASTING 360'
    when 'grupo-lira-de-comunicacao' then 'Grupo Lira de Comunicação'
    else e.name end,
    entity_type = case when e.slug = 'lira-technology'
       then 'organizational_unit' else e.entity_type end,
    metadata = e.metadata || jsonb_build_object(
       'institutional_chart', true,
       'institutional_decision', 'GL-ESTRUTURA-20260929'
    ),
    updated_at = now()
from tenant t
where e.tenant_id = t.id
  and e.slug in ('lira-technology','nucleo-midia',
                 'casting-attual-360','grupo-lira-de-comunicacao');

-- Legacy nuclei are technical groupings, not approved corporate pillars.
with tenant as (select id from public.matrix_tenants where key = 'grupo-lira')
update public.matrix_entities e
set metadata = e.metadata || jsonb_build_object(
       'institutional_chart', false,
       'catalog_role', 'legacy_context',
       'institutional_decision', 'GL-ESTRUTURA-20260929'
    ),
    updated_at = now()
from tenant t
where e.tenant_id = t.id and e.slug in (
  'nucleo-servicos','nucleo-negocios','nucleo-cultura-entretenimento',
  'nucleo-tecnologia','nucleo-terceiro-setor',
  'atlas','plataforma-attual',
  'attualplay','revista-attual','caçapava-news',
  'lava-laundry-vale','bellalucci','attual-experience',
  'novelas-verticais','premio-attual','fepac-conecta','acca-sinal-livre'
);

-- Fail closed if the canonical four-pillar / seven-platform structure differs.
do $$
declare
  root_id uuid;
  lira_id uuid;
begin
  select e.id into strict root_id
  from public.matrix_entities e
  join public.matrix_tenants t on t.id = e.tenant_id
  where t.key='grupo-lira' and e.slug='grupo-lira-de-comunicacao';

  select e.id into strict lira_id
  from public.matrix_entities e
  join public.matrix_tenants t on t.id = e.tenant_id
  where t.key='grupo-lira' and e.slug='lira-technology';

  if (select count(*) from public.matrix_entities
      where parent_entity_id = root_id
        and metadata->>'institutional_chart' = 'true') <> 4 then
    raise exception 'Matrix institutional migration: expected four direct pillars';
  end if;
  if (select count(*) from public.matrix_entities
      where parent_entity_id = lira_id
        and metadata->>'institutional_chart' = 'true') <> 7 then
    raise exception 'Matrix institutional migration: expected seven Lira Technology platforms';
  end if;
  if exists (
    select 1 from public.matrix_entities e
    join public.matrix_tenants t on t.id=e.tenant_id
    where t.key='grupo-lira' and e.slug='matrix-attual' and e.parent_entity_id is not null
  ) then
    raise exception 'Matrix institutional migration: technical Matrix cannot be an institutional parent';
  end if;
end $$;

commit;
