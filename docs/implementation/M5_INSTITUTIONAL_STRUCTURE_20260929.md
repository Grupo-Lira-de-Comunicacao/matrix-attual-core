# MATRIX — Estrutura institucional 2026-09-29

Status: preparada em branch para revisão, testes e aplicação governada. **Não equivale a migração executada em produção**.

## Autoridade

Decisão canônica `GL-ESTRUTURA-20260929`. Fonte:
https://drive.google.com/file/d/1cA9po2rYAsf1vPjyCo-0O0ttWAMAM46m/view

Esta definição prevalece sobre organogramas históricos da MATRIX. MATRIX e ATLAS continuam componentes técnicos, sem nível intermediário no organograma institucional.

## Os quatro pilares aprovados

- MÍDIA — TV Attual, Rádio Attual.
- COMUNICAÇÃO E PRODUÇÃO — ATT Comunica, Studio Lira, Attual Records.
- CULTURA, EVENTOS E PROJETOS — FEMAC-SP, Miss Caçapava, Taiada Fashion.
- TECNOLOGIA E INOVAÇÃO — Lira Technology, com as sete plataformas: ATTUAL ONE, ATTUAL AUTOPILOT, ATTUAL DISPLAY / INDOOR, ATTUAL CONECTA IMÓVEIS, CASTING 360, TV ATTUAL APP e ATTUAL CONECTA SOCIAL.

Todos os quatro pilares são subordinados diretamente ao Grupo Lira. As sete plataformas se subordinam à Lira Technology.

## Preservação de dados e sistemas

O catálogo legado é contexto técnico. Entidades não citadas no organograma não serão apagadas, desativadas ou artificialmente incluídas na estrutura institucional. A migração mantém UUIDs, dados comerciais, eventos, identidade, consentimentos, os pipelines e todos os projetos anteriores.

As entidades institucionais passam a ter `metadata.institutional_chart=true` e a decisão `GL-ESTRUTURA-20260929`. As unidades antigas permanecem com `metadata.institutional_chart=false`, sem remoção de relacionamentos legados. A entidade `matrix-attual` deixa de ser filha institucional do Grupo Lira (raiz técnica separada). O antigo registro `casting-attual-360` mantém seu slug e UUID, com nome de exibição oficial CASTING 360.

## Rollout obrigatório

1. Confirmar hash da revisão, banco/projeto alvo `fdmvvxsdfanqarokastv` e aprovação N4 vigente.
2. Confirmar recuperação/backup do projeto MATRIX e histórico das migrations 023, 024 e 025.
3. Executar tests/CI e revisar qualquer diferença de contagem em 30 entidades preexistentes.
4. Aplicar **somente** `supabase/migrations/026_matrix_institutional_structure_20260929.sql` de forma transacional, no tenant `grupo-lira`.
5. Comprovar 38 entidades (30 anteriores + 8 novas), quatro pilares diretos e sete plataformas na Lira Technology.
6. Confirmar `matrix.health`, `matrix.ready`, M4 consentimento/marketing intacto e que nenhum sistema operacional tenha sido alterado.
7. Se uma condição falhar, interromper. A migração já usa `BEGIN/COMMIT` e verifica os totais antes de confirmar; rollback posterior requer nova migration explícita e restore governado, não exclusão manual.

## Política

- Não mexer em RLS, permissões anon/authenticated, token, PII ou Source of Truth.
- Nunca ativar marketing ou ações n8n externas para promover esta mudança.
- Não mesclar ou aplicar automaticamente até validação da governança e do escopo.
