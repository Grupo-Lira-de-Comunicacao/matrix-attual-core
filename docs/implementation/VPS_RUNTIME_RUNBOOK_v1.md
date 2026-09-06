# Matrix Attual — VPS Runtime Runbook v1

## Objetivo
Executar a Event API da Matrix Attual na VPS 02 mantendo `Grupo-Lira-de-Comunicacao/matrix-attual-core` privado e sem expor a porta do container diretamente na internet.

## Runtime
- container: `matrix-attual-api`
- porta interna: `8787`
- bind no host: `127.0.0.1:8787`
- banco: Supabase Matrix (`fdmvvxsdfanqarokastv`)
- segredos: nunca no Git; materializados somente no host a partir de fontes governadas
- reverse proxy/TLS: camada externa separada; apontar somente para `127.0.0.1:8787`

## Variáveis obrigatórias
`/etc/matrix-attual/matrix.env` deve conter somente no host:

- `MATRIX_SUPABASE_URL=https://fdmvvxsdfanqarokastv.supabase.co`
- `MATRIX_DB_ADMIN_KEY=<Supabase sb_secret server-side>`
- `MATRIX_ATTUALPLAY_PUBLIC_KEY=<client key de baixa autoridade>`
- `MATRIX_ALLOWED_ORIGINS=https://app.tvattual.com.br,https://tv-attual-app.vercel.app`
- `MATRIX_MAX_BODY_BYTES=262144`
- `MATRIX_MAX_BATCH_SIZE=100`

Permissão recomendada do arquivo: `0600`, diretório `0700`. Nunca registrar os valores em logs, PRs, chat, Drive ou evidências.

## Build e implantação
1. Fixar um SHA Git aprovado e verificado.
2. Obter o código privado via identidade GitHub governada do ATLAS.
3. Construir `matrix-attual-api:<sha-curto>` pelo `Dockerfile` do repositório.
4. Validar a imagem antes de substituir a anterior.
5. Subir por `deploy/docker-compose.yml` com bind apenas em loopback.
6. Validar `GET http://127.0.0.1:8787/health` e `/ready`.
7. Executar smoke event sintético com `analytics=false` e invalidá-lo em `matrix_event_invalidations`.
8. Somente depois configurar reverse proxy/TLS e um hostname estável.
9. O AttualPlay permanece com tracking desligado até um gate específico de ativação.

## Segurança
- `read_only: true` no container;
- `cap_drop: ALL`;
- `no-new-privileges:true`;
- sem `docker.sock`;
- sem volumes sensíveis;
- sem banco local;
- sem porta `0.0.0.0:8787`;
- chave Supabase secret apenas server-side;
- chave do AttualPlay tem somente escopo lógico `events:write`.

## Health / Ready
- `/health`: processo da API vivo;
- `/ready`: configuração e dependências prontas para ingestão.

Um deploy só é considerado válido quando ambos retornarem HTTP 200.

## Rollback
Manter uma imagem anterior verificada até o novo runtime passar no smoke test. Em falha:

1. parar `matrix-attual-api` candidato;
2. restaurar a tag/imagem anterior;
3. subir novamente com o mesmo arquivo de ambiente;
4. validar `/health` e `/ready`;
5. registrar evidência do rollback.

Nenhuma migration de banco faz parte deste deploy de runtime.

## Gate de produção
Publicar hostname/TLS e ativar `VITE_MATRIX_TRACKING_ENABLED=true` no AttualPlay são decisões separadas e exigem validação própria. O código do piloto mantém tracking e analytics desligados por padrão.
