# Matrix Attual M6.1 — ATTUAL CRM Read-only V1

Data: 2026-09-19  
Status: ATIVO EM PRODUÇÃO

## Objetivo

Dar à Matrix visão comercial agregada do Grupo Lira sem transformar a Matrix em CRM e sem copiar dados pessoais.

## Arquitetura

```text
ATTUAL CRM Supabase
       |
       | read-only / fixed aggregate queries
       v
ATLAS Credential Broker
       |
       v
matrix.crm.snapshot
       |
       v
Matrix / agentes autorizados
(contexto agregado)
```

## Capability

`matrix.crm.snapshot`

Contrato:
- no arguments;
- N1;
- automatic;
- read-only;
- aggregate-only;
- no PII;
- no person identifiers;
- no external actions.

## Fonte

CRM project ref:
`hcheyicbontucxotswgh`

O acesso é resolvido pelo Credential Broker. Credenciais não são retornadas pela capability.

## Dados expostos

Permitidos:
- organização institucional;
- contagens agregadas de contatos;
- contagens e status agregados de leads;
- valor agregado de pipeline;
- contagens agregadas de tarefas;
- distribuição agregada por etapa;
- timestamps de atualização agregados.

Proibidos:
- nomes de contatos;
- e-mails;
- telefones;
- CPF;
- data de nascimento;
- WhatsApp identity;
- conteúdo de mensagens/conversas;
- notas;
- custom fields;
- source metadata;
- IDs de contatos/leads/pessoas.

## Prova de produção

ATLAS production SHA:
`f7e9618b0d2f9432c3306b4430541ac29bb60adf`

A capability foi descrita pelo catálogo como:
- available=true;
- atlas_level=N1;
- automatic=true;
- requires_approval=false;
- typed_contract_available=true;
- universally_executable=true.

Execução real do handler:
- native_typed_api=true;
- health=ok;
- read_only=true;
- contains_personal_data=false;
- contains_user_identifiers=false;
- marketing_enabled=false;
- external_actions_enabled=false.

## Snapshot de referência

Em 2026-09-19:
- contatos: 736;
- leads: 736;
- abertos: 690;
- ganhos: 28;
- perdidos: 18;
- pipeline aberto: R$ 89.400,00;
- tarefas: 4;
- abertas: 4;
- vencidas: 4.

Estágios:
- Novo lead 342;
- Contato iniciado 198;
- Qualificado 0;
- Diagnóstico 0;
- Proposta 96;
- Negociação 54;
- Aprovado 0;
- Ganho 28;
- Perdido 18.

Esses números permanecem propriedade operacional do ATTUAL CRM e não são persistidos pela Matrix como cópia autoritativa.

## Segurança

- Supabase Management API read-only;
- query fixa no código;
- teste anti-PII;
- teste anti-SQL mutation;
- Credential Broker;
- nenhum segredo no output;
- nenhuma ação externa;
- marketing=false.

## Próxima etapa

M6.2 deve adicionar observabilidade/tendência agregada antes de qualquer integração de escrita.

Qualquer capacidade que crie ou modifique lead, tarefa, oportunidade, mensagem ou campanha exige outro contrato e outro gate.
