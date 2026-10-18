#!/usr/bin/env bash
# Tabela de referência de custos (qualidade x duração -> créditos e valor) mostrada ao perguntar o teto de gastos.

_rt() { python3 "$ROOT/scripts/reference_table.py" "$@"; }

test_table_has_credits_for_each_quality_and_duration() {
  local out; out=$(_rt --duracoes 5,15) || _fail "tabela falhou"
  assert_contains "$out" "480p" "480p"; assert_contains "$out" "720p" "720p"; assert_contains "$out" "1080p" "1080p"
  # taxas cotadas com get_cost em 2026-10-18: 3, 7 e 16 créditos por segundo
  assert_contains "$out" "| 480p | 5 s | 15 |" "480p 5 s = 15 créditos"
  assert_contains "$out" "| 720p | 15 s | 105 |" "720p 15 s = 105 créditos"
  assert_contains "$out" "| 1080p | 15 s | 240 |" "1080p 15 s = 240 créditos"
}

test_table_shows_dollars_with_a_comma_and_rounds_half_up() {
  local out; out=$(_rt --duracoes 15) || _fail "tabela falhou"
  assert_contains "$out" "US\$ 2,48" "45 créditos x 0,055 = 2,475 arredondado para cima"
}

test_table_adds_reais_only_when_the_user_gives_the_exchange_rate() {
  local out; out=$(_rt --duracoes 15) || _fail "tabela falhou"
  case "$out" in *"R\$"*) _fail "mostrou reais sem cotação do dólar";; esac
  out=$(_rt --duracoes 15 --cotacao-dolar 5,50) || _fail "tabela com cotação falhou"
  assert_contains "$out" "R\$ 13,61" "45 x 0,055 x 5,50 = 13,6125"
  _rt --duracoes 15 --cotacao-dolar abc >/dev/null 2>&1 && _fail "cotação inválida aceita"
  _rt --duracoes 15 --cotacao-dolar 0 >/dev/null 2>&1 && _fail "cotação zero aceita"
}

test_table_validates_durations_and_states_its_source_and_date() {
  _rt --duracoes 3 >/dev/null 2>&1 && _fail "duração abaixo de 4 s aceita"
  _rt --duracoes 31 >/dev/null 2>&1 && _fail "duração acima de 30 s aceita"
  _rt --duracoes x >/dev/null 2>&1 && _fail "duração inválida aceita"
  local out; out=$(_rt) || _fail "tabela padrão falhou"
  assert_contains "$out" "2026-10-18" "data da consulta"
  assert_contains "$out" "get_cost" "diz como foi obtido e como conferir"
  assert_contains "$out" "aproximad" "avisa que o valor em dinheiro é aproximado"
}

test_pipeline_skill_shows_the_table_before_asking_for_the_ceiling() {
  local s; s=$(cat "$ROOT/skills/content-pipeline/SKILL.md")
  assert_contains "$s" "reference_table.py" "usa o script da tabela"
  assert_contains "$s" "cotação do dólar" "pergunta a cotação para mostrar em reais"
  assert_contains "$s" "get_cost" "confere o preço atual antes de gerar"
}

test_price_data_file_is_consistent() {
  python3 - "$ROOT/data/precos-higgsfield.json" <<'PY' || _fail "data/precos-higgsfield.json inválido"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["modelo"] == "seedance_2_5"
assert set(d["creditos_por_segundo"]) == {"480p", "720p", "1080p"}
assert all(v > 0 for v in d["creditos_por_segundo"].values())
assert 0 < d["preco_credito_usd"]["minimo"] <= d["preco_credito_usd"]["referencia"] <= d["preco_credito_usd"]["maximo"]
assert d["consultado_em"]
PY
}
