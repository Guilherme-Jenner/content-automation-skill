# Fase 3c — Variantes do modo gerado (1 a 5 vídeos finais a partir dos mesmos clipes)

**Objetivo:** montar de 1 a 5 vídeos finais diferentes a partir dos clipes JÁ gerados (custo zero), cada um com sua seleção/ordem de cenas, suas legendas, seu estilo e, opcionalmente, sua trilha. Aprovação por variante.

**Decisões (minhas, a confirmar):**
- Variante = recombinação dos clipes existentes. Gerar clipes NOVOS custa crédito e continua sendo a skill `generate-clips` (com teto); aqui nunca se gasta crédito e não se toca no orçamento.
- O gancho de uma variante é a PRIMEIRA legenda da primeira cena (derivado, nunca declarado à parte). Ganchos devem diferir; repetir exige `gancho_repetido: true` + `justificativa_gancho`, como no modo gravado.
- Uma variante é derivada num gen-plan próprio (mesmas cenas escolhidas, na ordem escolhida, mesmos prompts → mesma chave de orçamento), então `clips_manifest.py verify`, `assemble-clips.sh` e `edit-generated.sh` funcionam sem alteração.
- Limite 1–5, ids seguros (letras, números, _ e -; sem diferença de caixa), variantes idênticas recusadas, cena só uma vez por variante.
- Lote: tudo é validado ANTES de produzir qualquer arquivo; uma variante que falha não impede as outras; saída `final-<id>.mp4` + `.srt`.

**Arquivos:** `schemas/gen-variants-plan.schema.json`, `scripts/validate_gen_variants.py`, `scripts/gen_variant_info.py`, `scripts/run-gen-variants.sh`, testes `tests/test_gen_variants*.sh`; atualizar `skills/edit-generated`, `skills/content-pipeline`, docs.

**Formato:** `{"quantidade":2,"variantes":[{"id":"A","cenas":["c1","c2","c3"],"legendas":{<captions-plan>},"musica":"caminho opcional (relativo ao plano)","volume_db":-18,"aprovada":true,"gancho_repetido":false,"justificativa_gancho":"","achados":["..."]}]}`

**Tarefas (TDD, uma suíte por tarefa):** 1 validador+schema; 2 derivação (gen_variant_info.py); 3 run-gen-variants.sh; 4 skills e docs; revisão independente.
