insert into public.matrix_tenants (key, name, status)
values ('grupo-lira', 'Grupo Lira de Comunicacao', 'active')
on conflict (key) do update set name = excluded.name, status = excluded.status, updated_at = now();

with tenant as (
  select id from public.matrix_tenants where key = 'grupo-lira'
)
insert into public.matrix_projects (tenant_id, project_key, name, project_type, status, atlas_project_id)
select tenant.id, seed.project_key, seed.name, seed.project_type, 'active', seed.atlas_project_id
from tenant
cross join (values
  ('tv-attual', 'TV Attual', 'media', 'tv-attual'),
  ('attualplay', 'AttualPlay', 'media-app', 'attualplay'),
  ('attual-one', 'Attual One', 'crm-platform', 'attual-one')
) as seed(project_key, name, project_type, atlas_project_id)
on conflict (tenant_id, project_key) do update
set name = excluded.name,
    project_type = excluded.project_type,
    status = excluded.status,
    atlas_project_id = excluded.atlas_project_id,
    updated_at = now();

with tenant as (
  select id from public.matrix_tenants where key = 'grupo-lira'
)
insert into public.matrix_topics (tenant_id, key, label)
select tenant.id, seed.key, seed.label
from tenant
cross join (values
  ('noticias','Noticias'),
  ('politica-local','Politica local'),
  ('economia','Economia'),
  ('empreendedorismo','Empreendedorismo'),
  ('carreira','Carreira'),
  ('mulheres','Mulheres'),
  ('saude','Saude'),
  ('beleza','Beleza'),
  ('cultura','Cultura'),
  ('musica','Musica'),
  ('audiovisual','Audiovisual'),
  ('educacao','Educacao'),
  ('esportes','Esportes'),
  ('tecnologia','Tecnologia'),
  ('eventos','Eventos'),
  ('turismo','Turismo'),
  ('gastronomia','Gastronomia'),
  ('imoveis','Imoveis')
) as seed(key, label)
on conflict (tenant_id, key) do update set label = excluded.label, status = 'active';
