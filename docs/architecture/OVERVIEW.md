# Matrix Attual — Architecture Overview

## Objetivo

Construir uma camada comum e multi-projeto para identidade, eventos, relacionamento, contexto, recomendacao e inteligencia, sem transformar os produtos existentes em um monolito unico.

## Fluxo principal

```text
Canais / Produtos
    |
    v
Matrix Edge (SDK + API + Auth)
    |
    v
Identity + Consent + Event Ingestion
    |
    v
Event Store + Catalog + Relationships
    |
    v
Interest Engine + Recommendation Engine
    |
    v
Attual One / AttualPlay / n8n / outras verticais

ATLAS governa infraestrutura, capabilities, auditoria e operacao.
Infisical guarda segredos.
```

## Decisoes v1

1. Modular monolith no MVP.
2. PostgreSQL/Supabase dedicado como data layer.
3. Integracao por APIs e eventos; sem escrita direta no banco de outro produto.
4. `tenant_id` e `project_id` desde o inicio.
5. `person_id` UUID como identidade interna; e-mail e telefone nao sao chave global.
6. Eventos append-only e idempotentes.
7. Recomendacoes devem registrar explicacao, sinais e versao de engine.
8. Regras deterministicas antes de ML complexo.
9. n8n orquestra workflows; nao e Event Store nem Identity Store.
10. Dados sensiveis permanecem isolados por dominio e finalidade.

## Primeira milestone

**M0 — Foundation Ready**

- repositorio criado;
- Supabase dedicado validado via ATLAS Multi-Supabase;
- secrets somente no Infisical;
- migrations base;
- RLS;
- Event API;
- health;
- audit;
- teste E2E de evento.
