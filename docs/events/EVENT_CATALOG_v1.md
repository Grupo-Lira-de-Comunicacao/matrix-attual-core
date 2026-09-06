# MATRIX ATTUAL — Event Catalog v1

## Regra
Somente eventos registrados neste catalogo podem entrar em producao. Eventos carregam o minimo necessario e nunca devem conter senha, token, service role, CPF, conteudo de conversa privada ou dados sensiveis sem contrato especifico.

## Envelope obrigatorio
- `event_id` UUID
- `event_type`
- `occurred_at`
- `project_key`
- `idempotency_key`
- `source`
- `schema_version=1`
- `anonymous_id` ou identidade resolvida quando aplicavel
- `object.type` / `object.id` quando houver objeto
- `properties` allowlisted
- `context` minimizado

## AttualPlay — eventos iniciais
| Evento | Finalidade | Propriedades permitidas |
|---|---|---|
| `session_started` | sessao/retorno | `entry_path`, `referrer_class` |
| `page_viewed` | navegacao | `path`, `page_type` |
| `content_viewed` | interesse editorial | `content_id`, `content_type` |
| `content_progressed` | profundidade | `content_id`, `progress_bucket` (25/50/75) |
| `content_completed` | conclusao | `content_id`, `completion_ratio` |
| `program_viewed` | afinidade programa | `program_key` |
| `tv_started` | consumo live | `channel_key` |
| `tv_stopped` | fim consumo live | `channel_key`, `watch_seconds_bucket` |
| `radio_started` | consumo radio | `station_key` |
| `radio_stopped` | fim consumo radio | `station_key`, `listen_seconds_bucket` |
| `cta_clicked` | intencao | `cta_key`, `object_id` |
| `contact_started` | relacionamento | `channel` |
| `recommendation_shown` | avaliacao | `recommendation_id` |
| `recommendation_clicked` | avaliacao | `recommendation_id`, `item_rank` |
| `recommendation_dismissed` | feedback negativo | `recommendation_id` |
| `preference_updated` | preferencia explicita | `topic_key`, `preference` |

## Regras de volume
- progresso somente 25/50/75%;
- heartbeat TV/radio no maximo a cada 5 minutos e apenas se necessario;
- preferir batch ate 100 eventos;
- duplicatas sao tratadas por `idempotency_key`.

## Governanca
Novo evento exige PR com owner, finalidade, propriedades, classificacao de sensibilidade, retencao e testes de schema.
