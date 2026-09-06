# Matrix Attual — M0 Execution Plan

## Estado
Fundacao de codigo pronta. Nenhuma migration aplicada ainda ao Supabase.

## Sequencia de execucao
1. Confirmar runtime do ATLAS no SHA que contem o Account Registry da Matrix.
2. Resolver a credencial `vault:atlas-operator/supabase/matrixattual/SUPABASE_ACCESS_TOKEN` pelo Credential Broker sem expor o valor.
3. Executar `supabase.project.get` para `fdmvvxsdfanqarokastv`.
4. Confirmar projeto ACTIVE_HEALTHY e regiao `sa-east-1`.
5. Obter evidencia/backup aplicavel antes de DDL.
6. Aplicar migrations 001–014 via capability governada `supabase.migration.apply`.
7. Executar queries de verificacao de schema e RLS.
8. Rodar Supabase security advisors e performance advisors.
9. Corrigir qualquer finding critico antes do Event API.
10. Iniciar Event API + SDK AttualPlay em nova PR.

## Gate
A etapa 6 e N4 e requer confirmacao literal `APROVO` segundo a Capability Matrix do ATLAS.
