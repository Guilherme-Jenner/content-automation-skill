#!/usr/bin/env bash
# Testes de scripts/drive_upload.py contra um servidor FALSO do Drive (nenhum teste usa o Google de verdade)

NOW="2026-10-20T10:00:00-03:00"

# _dv <dir> → sobe o servidor falso, cria plano (p1 vídeo, p2 carrossel de 3 imagens) e aprova p1 e p2; exporta variáveis do teste
_dv() {
  local d="$1"; mkdir -p "$d"
  printf 'video' > "$d/v.mp4"; printf 'a' > "$d/s1.jpg"; printf 'b' > "$d/s2.jpg"; printf 'c' > "$d/s3.jpg"
  python3 - "$d/plan.json" <<'PY'
import json, sys
perfis = [{"rede": "instagram", "conta": "clo.app"}]
json.dump({"posts": [
  {"id": "p1", "video": "v.mp4", "legenda": "a", "hashtags": [], "perfis": perfis, "data_hora": "2026-10-21T12:00:00-03:00"},
  {"id": "p2", "imagens": ["s1.jpg", "s2.jpg", "s3.jpg"], "legenda": "b", "hashtags": [], "perfis": perfis, "data_hora": "2026-10-22T12:00:00-03:00"},
  {"id": "p3", "video": "v.mp4", "legenda": "c", "hashtags": [], "perfis": perfis, "data_hora": "2026-10-23T12:00:00-03:00"}]}, open(sys.argv[1], "w"))
PY
  for p in p1 p2; do python3 "$ROOT/scripts/approval.py" approve "$d/plan.json" $p "$d/ap" --now "$NOW" >/dev/null 2>&1 || _fail "approve $p"; done
  python3 "$ROOT/tests/lib/fake_drive.py" "$d/req.log" "$d/porta" &
  echo $! > "$d/pid"
  local i; for i in 1 2 3 4 5 6 7 8 9 10; do [ -s "$d/porta" ] && break; sleep 0.3; done
}
_dstop() { kill "$(cat "$1/pid")" 2>/dev/null; rm -rf "$1"; }
_dd() { # <dir> args... → drive_upload.py contra o servidor falso
  local d="$1"; shift
  CLO_ALLOW_TEST_NOW=1 CLO_DRIVE_API_BASE="http://127.0.0.1:$(cat "$d/porta")" GOOGLE_DRIVE_ACCESS_TOKEN=tok-teste \
    python3 "$ROOT/scripts/drive_upload.py" "$@"
}

test_drive_uploads_only_approved_media_private_by_default() {
  local d out; d="$(mktemp -d)"; _dv "$d"
  out=$(_dd "$d" enviar "$d/plan.json" --approvals "$d/ap" --pasta "Campanha" 2>&1) || _fail "enviar falhou: $out"
  assert_contains "$out" "pulado (sem aprovação válida): p3" "p3 não aprovado é pulado"
  assert_file_exists "$d/urls-p1.json"; assert_file_exists "$d/urls-p2.json"
  [ ! -e "$d/urls-p3.json" ] || _fail "post não aprovado recebeu links"
  assert_eq "4" "$(grep -c '"nome"' "$d/req.log")" "4 arquivos enviados (1 vídeo + 3 imagens)"
  assert_eq "3" "$(grep -c '"pasta"' "$d/req.log")" "pasta raiz + 1 pasta por post aprovado"
  ! grep -q '"perm"' "$d/req.log" || _fail "nada deveria ser compartilhado sem --compartilhar-link"
  assert_contains "$(cat "$d/urls-p2.json")" "drive.google.com/file/d/" "link de visualização"
  assert_contains "$(grep '"nome"' "$d/req.log" | head -4 | tr '\n' ' ')" "01-s1.jpg" "imagens numeradas na ordem"
  assert_contains "$(head -1 "$d/req.log")" "Bearer tok-teste" "usa o token"
  _dstop "$d"
}

test_drive_reupload_does_not_duplicate_and_detects_changes() {
  local d; d="$(mktemp -d)"; _dv "$d"
  _dd "$d" enviar "$d/plan.json" --approvals "$d/ap" --posts p1,p2 >/dev/null 2>&1 || _fail "1º envio"
  local antes; antes=$(grep -c '"nome"' "$d/req.log")
  _dd "$d" enviar "$d/plan.json" --approvals "$d/ap" --posts p1,p2 >/dev/null 2>&1 || _fail "2º envio"
  assert_eq "$antes" "$(grep -c '"nome"' "$d/req.log")" "reenvio não duplica"
  printf 'trocada' > "$d/s2.jpg"   # muda depois da aprovação: aprovação deixa de valer e nada é enviado
  assert_fails _dd "$d" enviar "$d/plan.json" --approvals "$d/ap" --posts p2
  assert_eq "$antes" "$(grep -c '"nome"' "$d/req.log")" "mídia alterada não é enviada"
  _dstop "$d"
}

test_drive_explicit_post_needs_approval() {
  local d out; d="$(mktemp -d)"; _dv "$d"
  out=$(_dd "$d" enviar "$d/plan.json" --approvals "$d/ap" --posts p3 2>&1) && _fail "post sem aprovação aceito"
  assert_contains "$out" "aprovação" "mensagem"
  [ ! -s "$d/req.log" ] || _fail "não deveria ter chamado o Drive"
  _dstop "$d"
}

test_drive_share_link_and_revoke() {
  local d out; d="$(mktemp -d)"; _dv "$d"
  _dd "$d" enviar "$d/plan.json" --approvals "$d/ap" --posts p1 --compartilhar-link --link download >/dev/null 2>&1 || _fail "enviar com link"
  assert_contains "$(grep '"perm"' "$d/req.log")" '"type": "anyone"' "permissão por link"
  assert_contains "$(cat "$d/urls-p1.json")" "export=download" "link de download"
  out=$(_dd "$d" revogar "$d/plan.json" 2>&1) || _fail "revogar falhou: $out"
  assert_contains "$out" "1 arquivo" "revogou 1"
  assert_contains "$(grep DELETE "$d/req.log")" "anyoneWithLink" "remove a permissão"
  _dstop "$d"
}

test_drive_refreshes_token_and_needs_auth() {
  local d out; d="$(mktemp -d)"; _dv "$d"
  printf '{"client_id":"c","client_secret":"s","refresh_token":"r"}' > "$d/tok.json"
  CLO_ALLOW_TEST_NOW=1 CLO_DRIVE_API_BASE="http://127.0.0.1:$(cat "$d/porta")" CLO_DRIVE_OAUTH_TOKEN_URL="http://127.0.0.1:$(cat "$d/porta")/token" CLO_DRIVE_TOKEN_FILE="$d/tok.json" \
    python3 "$ROOT/scripts/drive_upload.py" enviar "$d/plan.json" --approvals "$d/ap" --posts p1 >/dev/null 2>&1 || _fail "enviar com refresh falhou"
  assert_contains "$(grep -v token "$d/req.log" | head -1)" "Bearer tok-renovado" "usa o token renovado"
  out=$(CLO_ALLOW_TEST_NOW=1 CLO_DRIVE_TOKEN_FILE="$d/nao-existe.json" python3 "$ROOT/scripts/drive_upload.py" enviar "$d/plan.json" --approvals "$d/ap" --posts p1 2>&1) && _fail "sem token aceito"
  assert_contains "$out" "auth" "orienta a autorizar"
  _dstop "$d"
}
