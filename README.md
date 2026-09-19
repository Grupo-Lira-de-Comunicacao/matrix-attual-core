# Matrix Attual Core

Nucleo tecnico da Matrix Attual: identidade, consentimento, eventos, relacionamento contextual, interesses, recomendacoes, memoria corporativa e auditoria do ecossistema Grupo Lira.

## Status consolidado — 2026-09-19

**Fase funcional implementada no repositorio:** M0–M5.  
**Runtime atual observado:** Vercel, projeto `matrix-attual-core`, producao READY.  
**Supabase alvo:** `matrixattual` (`fdmvvxsdfanqarokastv`).  
**Read-back atual do banco:** pendente de conexao administrativa ao projeto Matrix; a presenca das migrations no Git e o CI verde nao substituem a verificacao do schema aplicado.

### Estado por marco

- M0 Foundation: historicamente aplicada e validada em 2026-09-06.
- M1 Event API: implementada.
- M2 Shadow Intelligence: contratos, migrations e engine versionados.
- M3 Controlled Activation: backend implementado e cliente AttualPlay M3 promovido a producao.
- M4 Identity Bridge: backend implementado; ativacao ponta a ponta deve permanecer controlada ate validacao de producao.
- M5 Corporate Catalog: implementado; consolidacao corporativa v2 proposta pela migration `025`.

## Principios

1. Matrix e camada de inteligencia, contexto, identidade contextual e memoria relacional.
2. Matrix nao e ERP, CRM, document store, secret manager nem control plane.
3. ATLAS governa execucao, infraestrutura, capabilities e auditoria operacional.
4. ATTUAL CRM e a fonte de verdade comercial.
5. Plataforma Attual e a fonte de verdade operacional/transacional.
6. Google Drive e a memoria documental.
7. GitHub e a memoria tecnica.
8. n8n orquestra processos; nao e Event Store nem Identity Store.
9. Infisical guarda segredos e credenciais.
10. Vercel e o runtime atual da API Matrix; o runbook VPS permanece como opcao de contingencia/migracao controlada.

## Arquitetura

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
AttualPlay / Plataforma Attual / ATTUAL CRM / outras verticais

ATLAS governa infraestrutura, capabilities, auditoria e operacao.
Infisical guarda segredos.
```

## Governanca de dados

- `tenant_id` e `project_id` desde a fundacao;
- eventos append-only e idempotentes;
- consentimento separado para analytics e personalizacao;
- marketing permanece desabilitado nos marcos M2–M4;
- nenhuma inferencia de atributos sensiveis;
- RLS deny-by-default nas tabelas Matrix;
- retencao configurada para minimizar telemetria pseudonima;
- identidade M4 exige ligacao explicita, auditavel e revogavel;
- nenhum segredo deve ser commitado neste repositorio.

## Catalogo corporativo

M5 usa `matrix_entities` e `matrix_relationships` como memoria corporativa contextual, sem duplicar os datasets operacionais de outros sistemas.

A consolidacao v2 de 2026-09-19 organiza:

- Grupo Lira de Comunicacao;
- Matrix Attual;
- Midia;
- Servicos;
- Negocios;
- Cultura e Entretenimento;
- Tecnologia;
- Terceiro Setor;
- marcas, plataformas e projetos atuais do ecossistema.

Detalhes: `docs/implementation/M5_CORPORATE_CATALOG_v2.md`.

## Runtime

### Canonico atual
Vercel / projeto `matrix-attual-core`.

### Alternativa controlada
O documento `docs/implementation/VPS_RUNTIME_RUNBOOK_v1.md` descreve um runtime em VPS 02. Ele deve ser tratado como runbook de contingencia/migracao e nao como prova de que a producao atual roda na VPS.

## Supabase alvo

- project: `matrixattual`
- project_ref: `fdmvvxsdfanqarokastv`
- credenciais administrativas: somente server-side e por fonte governada.

A aplicacao de migrations em producao deve ser comprovada por read-back do banco. O workflow de CI valida contratos, testes e build, mas nao aplica automaticamente migrations.

## Proximos gates

1. read-back das migrations `001`–`025` no Supabase Matrix;
2. aplicar `025` somente apos validacao de schema e backup adequado;
3. confirmar flags/configuracao Matrix do AttualPlay em producao;
4. validar M4 ponta a ponta antes de promocao ampla;
5. adicionar observabilidade Matrix read-only ao ATLAS quando a superficie cliente permitir;
6. manter marketing e acoes externas automaticas desligados ate gate separado.
