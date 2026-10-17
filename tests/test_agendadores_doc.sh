#!/usr/bin/env bash
# O documento de pesquisa dos agendadores cita fontes com data, não afirma o que não foi verificado e traz o checklist

DOC="$ROOT/docs/agendadores.md"

test_doc_lists_candidates_with_sources_and_access_date() {
  local s; assert_file_exists "$DOC"; s=$(cat "$DOC")
  assert_contains "$s" "Metricool" "candidato"
  assert_contains "$s" "Planoly" "candidato"
  assert_contains "$s" "PostEverywhere" "candidato"
  assert_contains "$s" "Publora" "candidato"
  assert_contains "$s" "Acessado em 2026-10-17" "data de acesso das fontes"
  [ "$(grep -o 'https://[^ )>]*' "$DOC" | sort -u | wc -l)" -ge 5 ] || _fail "esperava ao menos 5 fontes distintas com URL"
}

test_doc_is_honest_about_what_is_not_verified() {
  local s; s=$(cat "$DOC")
  assert_contains "$s" "não verificado" "marca o que não foi verificado"
  assert_contains "$s" "descrição de terceiros" "trata as descrições como dados de terceiros"
  assert_contains "$s" "nada foi instalado" "declara que nada foi instalado, conectado ou publicado"
}

test_doc_has_a_validation_checklist_with_the_key_questions() {
  local s; s=$(cat "$DOC")
  [ "$(grep -c '^- \[ \]' "$DOC")" -ge 8 ] || _fail "esperava ao menos 8 itens no checklist"
  assert_contains "$s" "URL pública" "pergunta sobre arquivo local x URL pública"
  assert_contains "$s" "data e hora" "pergunta sobre data/hora"
  assert_contains "$s" "perfis" "pergunta sobre os perfis do sócio"
  assert_contains "$s" "conta de teste" "valida em conta de teste"
}
