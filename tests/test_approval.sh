#!/usr/bin/env bash
# Testes de scripts/approval.py (aprovação amarrada ao conteúdo exato)

NOW="2026-10-20T10:00:00-03:00"

_ap() { python3 "$ROOT/scripts/approval.py" "$@"; }

# _mk <dir> <instruções python que alteram p>  → <dir>/plan.json com os posts p1 e p2 (vídeos v1.mp4 e v2.mp4)
_mk() {
  mkdir -p "$1"; printf 'video 1' > "$1/v1.mp4"; printf 'video 2' > "$1/v2.mp4"
  python3 - "$1/plan.json" "$2" <<'PY'
import json, sys
def post(i, v):
    return {"id": i, "video": v, "legenda": "Rotina organizada ✨", "hashtags": ["#clo"],
            "perfis": [{"rede": "instagram", "conta": "clo.app"}], "data_hora": "2026-10-21T12:00:00-03:00"}
p = {"posts": [post("p1", "v1.mp4"), post("p2", "v2.mp4")]}
exec(sys.argv[2])
json.dump(p, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
}

_approve() { _ap approve "$1/plan.json" "$2" "$1/ap" --now "$NOW"; }

test_verify_passes_right_after_approve() {
  local d; d="$(mktemp -d)"; _mk "$d" "pass"
  _approve "$d" p1 >/dev/null 2>&1 || _fail "approve falhou"
  assert_file_exists "$d/ap/p1.approval.json"
  _ap verify "$d/plan.json" p1 "$d/ap" >/dev/null 2>&1 || _fail "verify deveria passar logo após aprovar"
  rm -rf "$d"
}

test_changed_video_bytes_rejected() {
  local d out; d="$(mktemp -d)"; _mk "$d" "pass"; _approve "$d" p1 >/dev/null 2>&1
  printf 'outro conteudo, mesmo nome' > "$d/v1.mp4"
  out=$(_ap verify "$d/plan.json" p1 "$d/ap" 2>&1) && _fail "vídeo trocado aceito"
  assert_contains "$out" "vídeo" "mensagem"
  rm -rf "$d"
}

test_changed_caption_time_or_profiles_rejected() {
  local d out expr
  for expr in "p['posts'][0]['legenda']='outra legenda'" \
              "p['posts'][0]['data_hora']='2026-10-22T12:00:00-03:00'" \
              "p['posts'][0]['perfis']=[{'rede':'tiktok','conta':'clo.app'}]" \
              "p['posts'][0]['hashtags']=['#outra']"; do
    d="$(mktemp -d)"; _mk "$d" "pass"; _approve "$d" p1 >/dev/null 2>&1
    _mk "$d" "$expr"
    out=$(_ap verify "$d/plan.json" p1 "$d/ap" 2>&1) && _fail "alteração aceita: $expr"
    assert_contains "$out" "conteúdo" "mensagem ($expr)"
    rm -rf "$d"
  done
}

test_approval_of_one_post_does_not_cover_another() {
  local d out; d="$(mktemp -d)"; _mk "$d" "pass"; _approve "$d" p1 >/dev/null 2>&1
  out=$(_ap verify "$d/plan.json" p2 "$d/ap" 2>&1) && _fail "p2 não foi aprovado"
  assert_contains "$out" "aprovação" "mensagem"
  cp "$d/ap/p1.approval.json" "$d/ap/p2.approval.json"
  _ap verify "$d/plan.json" p2 "$d/ap" >/dev/null 2>&1 && _fail "aprovação copiada de outro post foi aceita"
  rm -rf "$d"
}

test_verify_without_approval_rejected() {
  local d out; d="$(mktemp -d)"; _mk "$d" "pass"
  out=$(_ap verify "$d/plan.json" p1 "$d/ap" 2>&1) && _fail "sem aprovação aceito"
  assert_contains "$out" "aprovação" "mensagem"
  rm -rf "$d"
}

test_approve_refuses_overwrite_without_force() {
  local d out; d="$(mktemp -d)"; _mk "$d" "pass"; _approve "$d" p1 >/dev/null 2>&1
  out=$(_approve "$d" p1 2>&1) && _fail "sobrescreveu sem --force"
  assert_contains "$out" "--force" "mensagem"
  _ap approve "$d/plan.json" p1 "$d/ap" --now "$NOW" --force >/dev/null 2>&1 || _fail "--force deveria permitir"
  rm -rf "$d"
}

test_unicode_caption_roundtrip() {
  local d; d="$(mktemp -d)"
  _mk "$d" "p['posts'][0]['legenda']='Ação \"rápida\" d\\'água 🚀\\nsegunda linha #tag'"
  _approve "$d" p1 >/dev/null 2>&1 || _fail "approve com unicode falhou"
  _ap verify "$d/plan.json" p1 "$d/ap" >/dev/null 2>&1 || _fail "verify com unicode falhou"
  rm -rf "$d"
}

test_cannot_approve_an_invalid_post() {
  local d out; d="$(mktemp -d)"; _mk "$d" "p['posts'][0]['data_hora']='2026-10-19T12:00:00-03:00'"
  out=$(_approve "$d" p1 2>&1) && _fail "post inválido aprovado"
  assert_contains "$out" "data_hora" "mensagem"
  [ ! -e "$d/ap/p1.approval.json" ] || _fail "não deveria gravar aprovação"
  out=$(_approve "$d" nao-existe 2>&1) && _fail "post inexistente aprovado"
  assert_contains "$out" "nao-existe" "mensagem"
  rm -rf "$d"
}

test_unsafe_post_id_cannot_escape_the_approvals_dir() {
  local d; d="$(mktemp -d)"; _mk "$d" "pass"
  _ap approve "$d/plan.json" "../fora" "$d/ap" --now "$NOW" >/dev/null 2>&1 && _fail "id com .. aceito"
  [ ! -e "$d/fora.approval.json" ] || _fail "escreveu fora do diretório"
  rm -rf "$d"
}
