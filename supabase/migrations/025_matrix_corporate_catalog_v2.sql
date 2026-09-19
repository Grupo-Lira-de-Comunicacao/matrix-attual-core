begin;

-- Matrix Corporate Catalog v2 — 2026-09-19
-- Reconciles corporate context only. No operational datasets are copied.

with tenant as (
  select id from public.matrix_tenants where key = 'grupo-lira'
), contextual as (
  select d.id
  from public.matrix_source_domains d
  join tenant t on t.id = d.tenant_id
  where d.domain_key = 'contextual'
)
insert into public.matrix_entities
  (tenant_id, entity_type, external_key, name, status, slug, code, nucleus, source_domain_id, short_description, metadata)
select tenant.id, s.entity_type, 'catalog:' || s.slug, s.name, 'active', s.slug, s.code, s.nucleus,
       contextual.id, s.description,
       jsonb_build_object('catalog_version','v2','corporate_catalog',true,'consolidated_at','2026-09-19')
from tenant
cross join contextual
cross join (values
  ('organizational_unit','matrix-attual','SYS-001','Matrix Attual','corporativo','Camada de inteligencia, contexto e integracao do Grupo Lira.'),
  ('organizational_unit','nucleo-midia','NUC-001','Midia','midia','Nucleo corporativo de midia.'),
  ('organizational_unit','nucleo-servicos','NUC-002','Servicos','servicos','Nucleo corporativo de servicos.'),
  ('organizational_unit','nucleo-negocios','NUC-003','Negocios','negocios','Nucleo corporativo de negocios.'),
  ('organizational_unit','nucleo-cultura-entretenimento','NUC-004','Cultura e Entretenimento','cultura-entretenimento','Eixo corporativo de cultura e entretenimento.'),
  ('organizational_unit','nucleo-tecnologia','NUC-005','Tecnologia','tecnologia','Nucleo corporativo de tecnologia e plataformas.'),
  ('organizational_unit','nucleo-terceiro-setor','NUC-006','Terceiro Setor','terceiro-setor','Nucleo de iniciativas e organizacoes do terceiro setor.'),
  ('brand','caçapava-news','BR-012','Caçapava News','midia','Marca editorial e noticiosa regional.'),
  ('project','novelas-verticais','PR-001','Novelas Verticais','cultura-entretenimento','Projeto de dramaturgia vertical do ecossistema Attual.'),
  ('project','premio-attual','PR-002','Premio Attual','cultura-entretenimento','Projeto de reconhecimento e premiacao do ecossistema Attual.'),
  ('project','femac-sp','PR-003','FEMAC SP','cultura-entretenimento','Festival de Musica Autoral de Caçapava.'),
  ('project','fepac-conecta','PR-004','FEPAC Conecta','cultura-entretenimento','Feira de Empreendedorismo de Caçapava.'),
  ('project','miss-caçapava','PR-005','Miss Caçapava','cultura-entretenimento','Projeto cultural e de evento do ecossistema.'),
  ('project','taiada-fashion','PR-006','Taiada Fashion','cultura-entretenimento','Projeto de moda e evento do ecossistema.'),
  ('platform','plataforma-attual','SYS-002','Plataforma Attual','tecnologia','Plataforma operacional do Grupo Lira; identificadores tecnicos legados podem usar attual-one.'),
  ('platform','lira-technology','SYS-003','Lira Technology','tecnologia','Nucleo/plataforma tecnica do Grupo Lira.'),
  ('platform','atlas','SYS-004','ATLAS Control Plane GL v4','tecnologia','Control plane de governanca e execucao tecnica.'),
  ('organization','acca-sinal-livre','ORG-001','ACCA - Sinal Livre','terceiro-setor','Associacao Comunitaria de Comunicacao Audiovisual.')
) as s(entity_type,slug,code,name,nucleus,description)
on conflict (tenant_id, slug) do update set
  entity_type = excluded.entity_type,
  external_key = excluded.external_key,
  name = excluded.name,
  status = 'active',
  code = excluded.code,
  nucleus = excluded.nucleus,
  source_domain_id = excluded.source_domain_id,
  short_description = excluded.short_description,
  metadata = public.matrix_entities.metadata || excluded.metadata,
  updated_at = now();

-- Root -> Matrix
with tenant as (
  select id from public.matrix_tenants where key='grupo-lira'
), root as (
  select e.id,e.tenant_id from public.matrix_entities e join tenant t on t.id=e.tenant_id
  where e.slug='grupo-lira-de-comunicacao'
), matrix as (
  select e.id,e.tenant_id from public.matrix_entities e join tenant t on t.id=e.tenant_id
  where e.slug='matrix-attual'
)
update public.matrix_entities e
set parent_entity_id = root.id, updated_at = now()
from root, matrix
where e.id = matrix.id and e.tenant_id = root.tenant_id
  and e.parent_entity_id is distinct from root.id;

-- Matrix -> nuclei
with tenant as (
  select id from public.matrix_tenants where key='grupo-lira'
), matrix as (
  select e.id,e.tenant_id from public.matrix_entities e join tenant t on t.id=e.tenant_id
  where e.slug='matrix-attual'
)
update public.matrix_entities e
set parent_entity_id = matrix.id, updated_at = now()
from matrix
where e.tenant_id = matrix.tenant_id
  and e.slug in (
    'nucleo-midia','nucleo-servicos','nucleo-negocios',
    'nucleo-cultura-entretenimento','nucleo-tecnologia','nucleo-terceiro-setor'
  )
  and e.parent_entity_id is distinct from matrix.id;

-- Nucleus -> entities
with tenant as (
  select id from public.matrix_tenants where key='grupo-lira'
), nuclei as (
  select e.id,e.tenant_id,e.slug
  from public.matrix_entities e join tenant t on t.id=e.tenant_id
  where e.slug in (
    'nucleo-midia','nucleo-servicos','nucleo-negocios',
    'nucleo-cultura-entretenimento','nucleo-tecnologia','nucleo-terceiro-setor'
  )
), mapping(child_slug,parent_slug) as (
  values
    ('tv-attual','nucleo-midia'),
    ('radio-attual','nucleo-midia'),
    ('attualplay','nucleo-midia'),
    ('revista-attual','nucleo-midia'),
    ('caçapava-news','nucleo-midia'),
    ('att-comunica','nucleo-servicos'),
    ('studio-lira','nucleo-servicos'),
    ('casting-attual-360','nucleo-servicos'),
    ('lava-laundry-vale','nucleo-negocios'),
    ('bellalucci','nucleo-negocios'),
    ('attual-records','nucleo-cultura-entretenimento'),
    ('attual-experience','nucleo-cultura-entretenimento'),
    ('novelas-verticais','nucleo-cultura-entretenimento'),
    ('premio-attual','nucleo-cultura-entretenimento'),
    ('femac-sp','nucleo-cultura-entretenimento'),
    ('fepac-conecta','nucleo-cultura-entretenimento'),
    ('miss-caçapava','nucleo-cultura-entretenimento'),
    ('taiada-fashion','nucleo-cultura-entretenimento'),
    ('plataforma-attual','nucleo-tecnologia'),
    ('lira-technology','nucleo-tecnologia'),
    ('atlas','nucleo-tecnologia'),
    ('acca-sinal-livre','nucleo-terceiro-setor')
)
update public.matrix_entities child
set parent_entity_id = parent.id, updated_at = now()
from mapping m
join nuclei parent on parent.slug = m.parent_slug
where child.tenant_id = parent.tenant_id
  and child.slug = m.child_slug
  and child.parent_entity_id is distinct from parent.id;

commit;
