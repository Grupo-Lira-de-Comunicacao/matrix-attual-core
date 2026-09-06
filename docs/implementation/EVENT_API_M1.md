# Matrix Attual — M1 Event API

## Objetivo
Transformar a fundacao M0 em uma porta de entrada segura para telemetria minimizada do ecossistema. O primeiro produtor e o AttualPlay.

## Fluxo MVP

`AttualPlay -> HTTPS Event API -> validacao/autorizacao -> Matrix Event Store -> processamento posterior`

A API aceita somente eventos cadastrados no Event Catalog v1, limita propriedades por tipo de evento, limita contexto, exige idempotencia e nunca recebe credencial administrativa do Supabase no navegador.

## Endpoints implementados
- `GET /health`: processo vivo;
- `GET /ready`: banco Matrix acessivel e tenant `grupo-lira` presente;
- `GET /v1/event-types`: catalogo aceito;
- `POST /v1/events`: ingestao individual;
- `POST /v1/events/batch`: lote de ate 100 eventos.

## Autenticacao do AttualPlay
O browser usa dois identificadores de baixa autoridade:
- `X-Matrix-Client: attualplay`;
- `X-Matrix-Key: <publishable key>`.

A publishable key identifica o produtor, mas nao concede acesso direto ao banco e nao e uma service role. A API ainda exige origem allowlisted e `project_key=attualplay`.

Credenciais administrativas permanecem somente no runtime da API, injetadas por ambiente seguro. Nunca entram no bundle do AttualPlay, GitHub ou eventos.

## Identidade e privacidade
- SDK comeca anonimo;
- `anonymous_id` e convertido em SHA-256 antes de persistir na tabela de perfis anonimos;
- nome, e-mail, telefone, CPF, senha, JWT, dados bancarios/clinicos, conversa privada e biometria sao proibidos na API generica;
- `person_token`, quando existir, e hashado e somente resolve identidades previamente verificadas;
- a API nao cria ligacao pessoa-anonimo apenas por telemetria.

## Consentimento
O evento pode carregar snapshot de `essential`, `analytics`, `personalization`, `marketing` e `policy_version`. O SDK deve respeitar feature flags e a decisao de consentimento antes de enviar.

## Idempotencia
`matrix_events` garante unicidade por tenant + projeto + `idempotency_key`. Reenvio do mesmo evento retorna sucesso com `duplicate=true`, evitando contagem dupla.

## Variaveis de runtime
- `MATRIX_SUPABASE_URL`
- `MATRIX_DB_ADMIN_KEY` — segredo somente server-side;
- `MATRIX_ATTUALPLAY_PUBLIC_KEY` — chave publicavel de baixa autoridade;
- `MATRIX_ALLOWED_ORIGINS` — lista separada por virgula;
- `MATRIX_MAX_BODY_BYTES` — default 256 KiB;
- `MATRIX_MAX_BATCH_SIZE` — maximo 100.

## Gates antes de producao
1. CI verde da PR M1;
2. provisionar projeto/runtime da API;
3. injetar credenciais via Infisical/ATLAS, sem copiar valores em chat;
4. configurar dominio/origem oficial;
5. smoke test com evento sintetico;
6. integrar AttualPlay atras de feature flag;
7. medir P95 e taxa de erro;
8. habilitar gradualmente.

## Rollback
Desligar `MATRIX_TRACKING_ENABLED` no AttualPlay interrompe novos eventos sem afetar TV, radio, navegacao ou conteudo generico. O Event Store permanece preservado para auditoria.
