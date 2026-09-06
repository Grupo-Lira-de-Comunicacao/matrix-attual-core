# Data Contract v1 — AttualPlay -> Matrix Attual

**Owner produtor:** AttualPlay / TV Attual  
**Consumidor:** Matrix Attual Core  
**Project key:** `attualplay`  
**Tenant:** `grupo-lira`

## Objetivo
Medir consumo e interesse editorial de forma minimizada para gerar analytics e recomendacoes explicaveis.

## Identidade
O SDK inicia anonimo. Ligacao a `person_id` somente ocorre por evidencia forte (ex.: login/cadastro validado pelo backend). Nome, e-mail e telefone nao sao enviados em eventos genericos.

## Consentimento
- `essential`: somente operacao estritamente necessaria;
- `analytics`: telemetria opcional conforme implementacao juridica;
- `personalization`: necessario para perfil persistente/personalizacao quando aplicavel;
- `marketing`: separado de analytics/personalizacao.

O snapshot da decisao vigente acompanha eventos que dependem dessa finalidade.

## Eventos permitidos
Usar exclusivamente os eventos definidos em `docs/events/EVENT_CATALOG_v1.md`.

## Dados proibidos
Senha, JWT, service role, CPF, dados bancarios, dados clinicos, mensagens privadas, inferencias psicologicas/vulnerabilidade e qualquer segredo.

## Retencao inicial proposta
- anonimo: 90 dias;
- identificado comportamental: 13 meses;
- auditoria: 24 meses.

Valores sujeitos a revisao juridica antes de producao plena.

## SLA tecnico MVP
- nenhum evento aceito pode ser perdido;
- P95 ingest < 500 ms;
- recomendacao P95 < 1 s;
- idempotencia obrigatoria.

## Rollback
Feature flags do AttualPlay devem permitir desligar tracking e personalizacao independentemente, preservando experiencia generica.
