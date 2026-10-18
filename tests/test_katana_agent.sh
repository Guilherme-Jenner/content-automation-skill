#!/usr/bin/env bash
# Editor Katana REAL: o Katana é um fluxo autônomo executado pelo AGENTE (ele cota e gasta por conta própria), então os
# scripts só preparam o briefing, respeitam o teto opcional e REGISTRAM o resultado e o gasto. Nada aqui chama o Higgsfield.

_b() { python3 "$ROOT/scripts/budget.py" "$@"; }

# _plan <dir> [expressão python sobre p] → plano de variantes com editor katana (variante 1 aprovada) e bruto.mp4
_plan() {
  mkdir -p "$1"; printf 'bruto' > "$1/bruto.mp4"
  python3 - "$ROOT/tests/data/variants_valid.json" "$1" "${2:-pass}" <<'PY'
import json, os, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))
p["editor"] = "katana"
p["bruto"] = os.path.join(sys.argv[2], "bruto.mp4")
p["variantes"][0]["aprovada"] = True
exec(sys.argv[3])
json.dump(p, open(os.path.join(sys.argv[2], "v.json"), "w", encoding="utf-8"), ensure_ascii=False)
PY
}

_vertical() { # arquivo [duração]
  ffmpeg -v error -y -f lavfi -i "color=c=blue:size=1080x1920:rate=25:duration=${2:-3}" -f lavfi -i "sine=frequency=440:duration=${2:-3}" -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac "$1" </dev/null
}

test_external_spend_without_ceiling_is_recorded() {
  local d out; d="$(mktemp -d)"
  _b init "$d/b.json" sem-teto >/dev/null
  _b externo "$d/b.json" katana-1 37 >/dev/null || _fail "externo falhou"
  out=$(_b status "$d/b.json"); assert_contains "$out" "gasto: 37" "gasto somado"
  assert_eq gasto "$(_b state "$d/b.json" katana-1)" "estado do item"
  _b externo "$d/b.json" katana-1 10 >/dev/null 2>&1 && _fail "mesmo item registrado duas vezes"
  rm -rf "$d"
}

test_external_spend_over_the_ceiling_is_recorded_and_flagged() {
  local d rc; d="$(mktemp -d)"
  _b init "$d/b.json" 50 >/dev/null
  _b externo "$d/b.json" katana-1 30 >/dev/null || _fail "dentro do teto falhou"
  _b externo "$d/b.json" katana-2 30 >/dev/null 2>&1; rc=$?
  assert_eq 3 "$rc" "estouro devolve o código 3"
  assert_contains "$(_b status "$d/b.json")" "gasto: 60" "o gasto efetivo foi registrado mesmo com estouro"
  _b externo "$d/b.json" katana-3 -1 >/dev/null 2>&1 && _fail "gasto negativo aceito"
  rm -rf "$d"
}

test_brief_carries_source_ranges_and_remaining_ceiling() {
  local d out; d="$(mktemp -d)"; _plan "$d"
  _b init "$d/b.json" 100 >/dev/null; _b externo "$d/b.json" outro 40 >/dev/null
  out=$(python3 "$ROOT/scripts/katana_brief.py" "$d/v.json" 1 --budget "$d/b.json") || _fail "briefing falhou"
  assert_eq 60 "$(printf '%s' "$out" | python3 -c "import json,sys; print(json.load(sys.stdin)['limite_creditos'])")" "limite = teto - comprometido"
  assert_contains "$out" "bruto.mp4" "fonte"
  assert_contains "$out" "9:16" "formato pedido"
  assert_contains "$out" "inicio_s" "trechos da variante"
  rm -rf "$d"
}

test_brief_without_ceiling_has_no_limit() {
  local d out; d="$(mktemp -d)"; _plan "$d"; _b init "$d/b.json" sem-teto >/dev/null
  out=$(python3 "$ROOT/scripts/katana_brief.py" "$d/v.json" 1 --budget "$d/b.json") || _fail "briefing falhou"
  assert_eq None "$(printf '%s' "$out" | python3 -c "import json,sys; print(json.load(sys.stdin)['limite_creditos'])")" "sem teto, sem limite"
  assert_contains "$out" "sem limite" "o aviso diz que o Katana define o próprio limite"
  rm -rf "$d"
}

test_brief_refuses_unapproved_variant_wrong_editor_and_unknown_id() {
  local d out; d="$(mktemp -d)"; _plan "$d"; _b init "$d/b.json" sem-teto >/dev/null
  out=$(python3 "$ROOT/scripts/katana_brief.py" "$d/v.json" 2 --budget "$d/b.json" 2>&1) && _fail "variante não aprovada aceita"; assert_contains "$out" "aprovad" "aprovação"
  out=$(python3 "$ROOT/scripts/katana_brief.py" "$d/v.json" 9 --budget "$d/b.json" 2>&1) && _fail "id inexistente aceito"
  _plan "$d" "p['editor']='local'"
  out=$(python3 "$ROOT/scripts/katana_brief.py" "$d/v.json" 1 --budget "$d/b.json" 2>&1) && _fail "editor local aceito"; assert_contains "$out" "katana" "mensagem"
  rm -rf "$d"
}

test_register_copies_the_result_and_records_the_spend() {
  local d; d="$(mktemp -d)"; _plan "$d"; _vertical "$d/baixado.mp4"; _b init "$d/b.json" 100 >/dev/null
  bash "$ROOT/scripts/katana_register.sh" "$d/v.json" 1 "$d/baixado.mp4" "$d/out" --budget "$d/b.json" --gasto 25 --job-ids a1,b2 >/dev/null 2>&1 || _fail "registro falhou"
  assert_file_exists "$d/out/final-1.mp4"
  assert_contains "$(_b status "$d/b.json")" "gasto: 25" "gasto registrado"
  assert_contains "$(cat "$d/out/final-1.katana.json")" "a1" "job ids guardados"
  rm -rf "$d"
}

test_register_refuses_bad_videos_and_existing_outputs_without_spending() {
  local d out; d="$(mktemp -d)"; _plan "$d"; _b init "$d/b.json" 100 >/dev/null
  printf 'nao e video' > "$d/x.mp4"
  out=$(bash "$ROOT/scripts/katana_register.sh" "$d/v.json" 1 "$d/x.mp4" "$d/out" --budget "$d/b.json" --gasto 5 2>&1) && _fail "arquivo inválido aceito"
  ffmpeg -v error -y -f lavfi -i "color=c=red:size=1920x1080:rate=25:duration=3" -an -c:v libx264 -pix_fmt yuv420p "$d/h.mp4" </dev/null
  out=$(bash "$ROOT/scripts/katana_register.sh" "$d/v.json" 1 "$d/h.mp4" "$d/out" --budget "$d/b.json" --gasto 5 2>&1) && _fail "vídeo horizontal aceito"
  assert_contains "$out" "9:16" "pede vertical"
  assert_contains "$(_b status "$d/b.json")" "gasto: 0" "nada foi registrado nas recusas"
  _vertical "$d/ok.mp4"
  bash "$ROOT/scripts/katana_register.sh" "$d/v.json" 1 "$d/ok.mp4" "$d/out" --budget "$d/b.json" --gasto 5 >/dev/null 2>&1 || _fail "registro válido falhou"
  out=$(bash "$ROOT/scripts/katana_register.sh" "$d/v.json" 1 "$d/ok.mp4" "$d/out" --budget "$d/b.json" --gasto 5 2>&1) && _fail "segundo registro aceito"
  assert_contains "$out" "--force" "pede --force para a saída existente"
  rm -rf "$d"
}

test_register_overrun_keeps_the_file_and_exits_with_an_error() {
  local d; d="$(mktemp -d)"; _plan "$d"; _vertical "$d/ok.mp4"; _b init "$d/b.json" 10 >/dev/null
  bash "$ROOT/scripts/katana_register.sh" "$d/v.json" 1 "$d/ok.mp4" "$d/out" --budget "$d/b.json" --gasto 25 >/dev/null 2>&1 && _fail "estouro deveria sair com erro"
  assert_file_exists "$d/out/final-1.mp4"
  assert_contains "$(_b status "$d/b.json")" "gasto: 25" "gasto efetivo registrado"
  rm -rf "$d"
}

test_run_variants_katana_points_to_the_agent_skill() {
  local d out; d="$(mktemp -d)"; _plan "$d"; _b init "$d/b.json" sem-teto >/dev/null
  out=$(bash "$ROOT/scripts/run-variants.sh" "$d/bruto.mp4" "$d/w" --variants "$d/v.json" --stage run --budget "$d/b.json" 2>&1) && _fail "katana real não deveria rodar por script"
  assert_contains "$out" "edit-katana" "indica a skill"
}

test_katana_skill_has_the_gates() {
  local f="$ROOT/skills/edit-katana/SKILL.md" s
  assert_file_exists "$f"; s=$(cat "$f")
  assert_contains "$s" "name: edit-katana" "frontmatter"
  assert_contains "$s" "gasta sozinho" "avisa que o Katana gasta por conta própria"
  assert_contains "$s" "aceito" "exige a aceitação explícita do usuário"
  assert_contains "$s" "limite" "passa o teto como limite ao Katana"
  assert_contains "$s" "sem limite" "explica o caso sem teto"
  assert_contains "$s" "katana_register.sh" "registra o resultado"
  assert_contains "$s" "katana_brief.py" "monta o briefing"
  assert_contains "$s" "get_katana_config" "cita a ferramenta que cria sessão"
  assert_contains "$s" "não verificada" "download ainda não verificado com a conta real"
  assert_contains "$s" "CLAUDE_PLUGIN_ROOT" "caminhos via raiz do plugin"
}
