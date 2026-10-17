#!/usr/bin/env bash
# Testes de scripts/export_package.sh (pacote para agendar manualmente no Instagram/TikTok)

NOW="2026-10-20T10:00:00-03:00"

_pk() { bash "$ROOT/scripts/export_package.sh" "$@"; }

# _setup <dir> → plan.json com o post p1 e vídeo v.mp4 (legenda com acentos, emoji, aspas e quebra de linha)
_setup() {
  mkdir -p "$1"; head -c 3000 /dev/urandom > "$1/v.mp4"
  python3 - "$1/plan.json" <<'PY'
import json, sys
json.dump({"posts": [{"id": "p1", "video": "v.mp4", "legenda": "Ação \"rápida\" d'água 🚀\nsegunda linha #tag",
                      "hashtags": ["#clo", "#produtividade"],
                      "perfis": [{"rede": "instagram", "conta": "clo.app"}, {"rede": "tiktok", "conta": "clo.app"}],
                      "data_hora": "2026-10-21T12:00:00-03:00"}]}, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}

test_package_has_all_files() {
  local d; d="$(mktemp -d)"; _setup "$d"
  _pk "$d/plan.json" p1 "$d/out" --now "$NOW" >/dev/null 2>&1 || _fail "export falhou"
  assert_file_exists "$d/out/p1/video.mp4"
  assert_file_exists "$d/out/p1/legenda.txt"
  assert_file_exists "$d/out/p1/horario.txt"
  assert_file_exists "$d/out/p1/COMO-AGENDAR.md"
  rm -rf "$d"
}

test_caption_preserved_byte_for_byte() {
  local d; d="$(mktemp -d)"; _setup "$d"
  _pk "$d/plan.json" p1 "$d/out" --now "$NOW" >/dev/null 2>&1 || _fail "export falhou"
  python3 - "$d/plan.json" "$d/esperado.txt" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))["posts"][0]
open(sys.argv[2], "wb").write((p["legenda"] + "\n\n" + " ".join(p["hashtags"]) + "\n").encode("utf-8"))
PY
  cmp -s "$d/esperado.txt" "$d/out/p1/legenda.txt" || _fail "legenda.txt difere do plano (byte a byte)"
  rm -rf "$d"
}

test_video_copied_identically() {
  local d; d="$(mktemp -d)"; _setup "$d"
  _pk "$d/plan.json" p1 "$d/out" --now "$NOW" >/dev/null 2>&1 || _fail "export falhou"
  cmp -s "$d/v.mp4" "$d/out/p1/video.mp4" || _fail "o vídeo copiado difere do original"
  rm -rf "$d"
}

test_schedule_and_instructions_are_readable() {
  local d h m; d="$(mktemp -d)"; _setup "$d"
  _pk "$d/plan.json" p1 "$d/out" --now "$NOW" >/dev/null 2>&1 || _fail "export falhou"
  h=$(cat "$d/out/p1/horario.txt"); m=$(cat "$d/out/p1/COMO-AGENDAR.md")
  assert_contains "$h" "quarta-feira" "dia da semana"
  assert_contains "$h" "21/10/2026" "data"
  assert_contains "$h" "12:00" "hora"
  assert_contains "$m" "Instagram" "passo a passo do Instagram"
  assert_contains "$m" "TikTok" "passo a passo do TikTok"
  assert_contains "$m" "conferir" "avisa que as telas mudam"
  rm -rf "$d"
}

test_refuses_overwrite_without_force() {
  local d msg; d="$(mktemp -d)"; _setup "$d"
  _pk "$d/plan.json" p1 "$d/out" --now "$NOW" >/dev/null 2>&1
  echo editado > "$d/out/p1/legenda.txt"
  msg=$(_pk "$d/plan.json" p1 "$d/out" --now "$NOW" 2>&1) && _fail "sobrescreveu sem --force"
  assert_contains "$msg" "--force" "mensagem"
  assert_eq editado "$(cat "$d/out/p1/legenda.txt")" "arquivo intacto"
  _pk "$d/plan.json" p1 "$d/out" --now "$NOW" --force >/dev/null 2>&1 || _fail "--force deveria permitir"
  rm -rf "$d"
}

test_works_with_spaces_and_relative_paths() {
  local d; d="$(mktemp -d)/pasta com espaço é"; _setup "$d"
  (cd "$d" && bash "$ROOT/scripts/export_package.sh" plan.json p1 "saída pacote" --now "$NOW" >/dev/null 2>&1) || _fail "caminhos relativos/espaços falharam"
  assert_file_exists "$d/saída pacote/p1/video.mp4"
  rm -rf "$d"
}

test_invalid_plan_or_post_is_refused() {
  local d msg; d="$(mktemp -d)"; _setup "$d"
  msg=$(_pk "$d/plan.json" p1 "$d/out" --now "2026-10-22T10:00:00-03:00" 2>&1) && _fail "horário passado aceito"
  assert_contains "$msg" "data_hora" "mensagem"
  msg=$(_pk "$d/plan.json" naoexiste "$d/out" --now "$NOW" 2>&1) && _fail "post inexistente aceito"
  assert_contains "$msg" "naoexiste" "mensagem"
  [ ! -e "$d/out" ] || _fail "não deveria criar nada"
  rm -rf "$d"
}
