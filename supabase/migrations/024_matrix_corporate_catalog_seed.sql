begin;

with tenant as (select id from public.matrix_tenants where key = 'grupo-lira')
insert into public.matrix_source_domains (tenant_id, domain_key, name, owner_system, authority_scope, source_reference)
select tenant.id, s.domain_key, s.name, s.owner_system, s.authority_scope, s.source_reference
from tenant cross join (values
  ('contextual','Memoria contextual','matrix','identity, consent, relations and intelligence','Supabase Matrix'),
  ('relationship','Relacionamento comercial','attual-crm','leads, contacts, companies, opportunities and tasks','ATTUAL CRM'),
  ('operations','Operacao','attual-one','business operations and transactional modules','ATTUAL ONE'),
  ('documents','Memoria documental','google-drive','institutional and documentary knowledge','Google Drive'),
  ('technical','Memoria tecnica','github','code and technical contracts','GitHub'),
  ('execution','Governanca e execucao tecnica','atlas','capabilities, workers and governed execution','VPS / ATLAS'),
  ('automation','Automacao','n8n','process orchestration only','n8n'),
  ('secrets','Segredos e credenciais','infisical','secrets only','Infisical'),
  ('runtime','Runtime de aplicacoes','vercel','application runtime and delivery','Vercel')
) as s(domain_key,name,owner_system,authority_scope,source_reference)
on conflict (tenant_id, domain_key) do update set
  name=excluded.name, owner_system=excluded.owner_system, authority_scope=excluded.authority_scope,
  source_reference=excluded.source_reference, status='active', updated_at=now();

with tenant as (select id from public.matrix_tenants where key='grupo-lira'),
contextual as (select d.id from public.matrix_source_domains d join tenant t on t.id=d.tenant_id where d.domain_key='contextual')
insert into public.matrix_entities (tenant_id, entity_type, external_key, name, status, slug, code, nucleus, source_domain_id, short_description, metadata)
select tenant.id, s.entity_type, 'catalog:'||s.slug, s.name, s.status, s.slug, s.code, s.nucleus, contextual.id, s.description,
       jsonb_build_object('catalog_version','v1','corporate_catalog',true)
from tenant cross join contextual cross join (values
 ('organization','grupo-lira-de-comunicacao','GL-001','Grupo Lira de Comunicacao','active','corporativo','Organizacao controladora e governanca do ecossistema.'),
 ('brand','tv-attual','BR-001','TV Attual','active','midia','Marca e operacao de televisao do Grupo Lira.'),
 ('brand','radio-attual','BR-002','Radio Attual','active','midia','Marca e operacao de radio do Grupo Lira.'),
 ('platform','attualplay','BR-003','AttualPlay','active','midia','Plataforma digital de conteudo e audiencia.'),
 ('brand','revista-attual','BR-004','Revista Attual','active','midia','Produto editorial premium regional.'),
 ('brand','att-comunica','BR-005','ATT Comunica','active','servicos','Agencia de publicidade, marketing, branding, conteudo e performance.'),
 ('brand','studio-lira','BR-006','Studio Lira','active','servicos','Unidade de producao audiovisual e conteudo.'),
 ('platform','casting-attual-360','BR-007','Casting Attual 360','active','servicos','Operacao e plataforma de casting, talentos e oportunidades.'),
 ('brand','attual-records','BR-008','Attual Records','active','cultura-entretenimento','Selo musical e nucleo artistico.'),
 ('project','attual-experience','BR-009','Attual Experience','active','cultura-entretenimento','Projeto de experiencias e eventos do ecossistema Attual.'),
 ('brand','lava-laundry-vale','BR-010','LAVA - Laundry Vale','active','negocios','Marca e operacao independente de lavanderia.'),
 ('brand','bellalucci','BR-011','Bellalucci','active','negocios','Marca de moda e estilo do portfolio do Grupo Lira.')
) as s(entity_type,slug,code,name,status,nucleus,description)
on conflict (tenant_id, slug) do update set entity_type=excluded.entity_type, external_key=excluded.external_key,
 name=excluded.name, status=excluded.status, code=excluded.code, nucleus=excluded.nucleus,
 source_domain_id=excluded.source_domain_id, short_description=excluded.short_description,
 metadata=public.matrix_entities.metadata||excluded.metadata, updated_at=now();

with tenant as (select id from public.matrix_tenants where key='grupo-lira'),
root as (select e.id,e.tenant_id from public.matrix_entities e join tenant t on t.id=e.tenant_id where e.slug='grupo-lira-de-comunicacao')
update public.matrix_entities e set parent_entity_id=root.id, updated_at=now()
from root where e.tenant_id=root.tenant_id and e.slug in
('tv-attual','radio-attual','attualplay','revista-attual','att-comunica','studio-lira','casting-attual-360','attual-records','attual-experience','lava-laundry-vale','bellalucci')
and e.parent_entity_id is distinct from root.id;

commit;
