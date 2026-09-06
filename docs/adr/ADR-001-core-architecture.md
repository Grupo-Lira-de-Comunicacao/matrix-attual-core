# ADR-001 — Core modular e orientado a eventos

**Status:** Accepted for M0

## Contexto

A Matrix Attual precisa conectar varios produtos do Grupo Lira sem transformar cada dominio em dependente do banco ou codigo dos demais.

## Decisao

O MVP sera um **modular monolith** com contratos claros e integracao orientada a eventos. O banco inicial sera PostgreSQL/Supabase dedicado.

Produtos de dominio continuam independentes e se integram por API/eventos.

## Consequencias

### Positivas

- menor complexidade operacional;
- deploy e debugging simples;
- baixo custo inicial;
- evolucao futura para servicos separados quando houver necessidade real.

### Restricoes

- nao acessar diretamente banco privado de outro produto;
- nao adicionar Kafka, Neo4j ou data warehouse sem metrica que justifique;
- eventos validos sao append-only;
- recomendacoes relevantes precisam de explicabilidade;
- segredos ficam fora do repositorio.
