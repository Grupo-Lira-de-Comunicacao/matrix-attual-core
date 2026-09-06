# Matrix Attual Core

Nucleo tecnico da **Matrix Attual**, arquitetura de identidade, eventos, relacionamento, contexto, recomendacao e inteligencia do ecossistema Grupo Lira / TV Attual.

## Status

**M0 - Foundation em bootstrap.**

Nesta fase, o repositorio concentra os contratos e a fundacao tecnica. Nenhuma migration deve ser aplicada em producao antes da validacao do Account Registry / Credential Broker para o Supabase dedicado da Matrix Attual.

## Componentes previstos

- Identity
- Consent
- Event Ingestion / Event Store
- Catalog / Topics
- Attual Graph / Relationships
- Interest Engine
- Recommendation Engine + Explainability
- Segments
- Audit / Observability
- SDK Web

## Infraestrutura alvo

- GitHub: fonte de verdade do codigo
- Supabase/PostgreSQL: data layer dedicado
- Infisical: segredos
- ATLAS: governanca e operacao
- n8n: automacoes e integracoes
- Vercel: interfaces e APIs quando aplicavel

## Primeiro piloto

**AttualPlay + Attual One**.

## Regra central

A Matrix Attual conecta produtos existentes por contratos, identidade e eventos. Ela nao substitui os sistemas de dominio que ja funcionam.
