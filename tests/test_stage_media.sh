#!/usr/bin/env bash
# Testes de stage_media.py e drive_links.py (preparar a pasta para o Drive e montar os links a partir da busca do MCP do Drive)

NOW="2026-10-20T10:00:00-03:00"

# _sg <dir> → plano com p1 (vídeo), p2 (carrossel de 3 imagens) e p3 (vídeo, sem aprovação); aprova p1 e p2
_sg() {
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
}
# _found <dir> → found.json como o do search_files, com os nomes do manifesto
_found() {
  python3 - "$1" <<'PY'
import json, os, sys
d = sys.argv[1]
m = json.load(open(os.path.join(d, ".drive-staging.json")))
files = []
for i, (pid, p) in enumerate(m["posts"].items()):
    for j, (rel, x) in enumerate(p["midias"].items()):
        files.append({"id": f"1AbCdEfGhIjKlMnOp{i}{j}", "name": x["nome"], "mimeType": "image/png"})
json.dump({"files": files}, open(os.path.join(d, "found.json"), "w"))
PY
}

test_stage_media_prepares_only_approved_with_searchable_names() {
  local d out; d="$(mktemp -d)"; _sg "$d"
  out=$(python3 "$ROOT/scripts/stage_media.py" "$d/plan.json" --approvals "$d/ap" 2>&1) || _fail "stage falhou: $out"
  assert_contains "$out" "pulado (sem aprovação válida): p3" "p3 pulado"
  assert_eq "4" "$(ls "$d/para-drive" | wc -l | tr -d ' ')" "1 vídeo + 3 imagens"
  assert_contains "$(ls "$d/para-drive" | tr '\n' ' ')" "clo__p2__02__" "nome com post e ordem"
  assert_contains "$(ls "$d/para-drive" | tr '\n' ' ')" "clo__p1__01__" "nome do vídeo"
  python3 "$ROOT/scripts/stage_media.py" "$d/plan.json" --approvals "$d/ap" >/dev/null 2>&1 || _fail "reexecução"
  assert_eq "4" "$(ls "$d/para-drive" | wc -l | tr -d ' ')" "reexecutar não duplica"
  out=$(python3 "$ROOT/scripts/stage_media.py" "$d/plan.json" --approvals "$d/ap" --posts p3 2>&1) && _fail "post sem aprovação aceito"
  assert_contains "$out" "aprovação" "mensagem"
  assert_fails python3 "$ROOT/scripts/stage_media.py" "$d/plan.json" --approvals "$d/ap" --prefixo "a_b"
  mkdir "$d/sync"; python3 "$ROOT/scripts/stage_media.py" "$d/plan.json" --approvals "$d/ap" --destino "$d/sync" >/dev/null 2>&1 || _fail "destino próprio"
  assert_eq "4" "$(ls "$d/sync" | wc -l | tr -d ' ')" "copiou para a pasta sincronizada"
  rm -rf "$d"
}

test_stage_media_changed_image_gets_a_new_name() {
  local d a b; d="$(mktemp -d)"; _sg "$d"
  python3 "$ROOT/scripts/stage_media.py" "$d/plan.json" --approvals "$d/ap" >/dev/null 2>&1
  a=$(ls "$d/para-drive" | grep p2__02)
  printf 'bb' > "$d/s2.jpg"; python3 "$ROOT/scripts/approval.py" approve "$d/plan.json" p2 "$d/ap" --force --now "$NOW" >/dev/null 2>&1
  python3 "$ROOT/scripts/stage_media.py" "$d/plan.json" --approvals "$d/ap" --posts p2 >/dev/null 2>&1
  b=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['posts']['p2']['midias']['s2.jpg']['nome'])" "$d/.drive-staging.json")
  [ "$a" != "$b" ] || _fail "imagem alterada manteve o mesmo nome"
  rm -rf "$d"
}

test_drive_links_builds_urls_from_mcp_search_results() {
  local d out; d="$(mktemp -d)"; _sg "$d"
  python3 "$ROOT/scripts/stage_media.py" "$d/plan.json" --approvals "$d/ap" >/dev/null 2>&1; _found "$d"
  out=$(python3 "$ROOT/scripts/drive_links.py" "$d/plan.json" --found "$d/found.json" 2>&1) || _fail "links falhou: $out"
  assert_file_exists "$d/urls-p1.json"; assert_file_exists "$d/urls-p2.json"
  assert_contains "$(cat "$d/urls-p2.json")" "https://drive.google.com/uc?export=download&id=" "link direto por padrão"
  assert_eq "3" "$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))))" "$d/urls-p2.json")" "3 links no carrossel"
  python3 "$ROOT/scripts/drive_links.py" "$d/plan.json" --found "$d/found.json" --link view >/dev/null 2>&1
  assert_contains "$(cat "$d/urls-p1.json")" "/view" "link de visualização"
  # os links alimentam o payload do Metricool
  python3 "$ROOT/scripts/metricool_payload.py" plano "$d/plan.json" p2 --urls "$d/urls-p2.json" --blog-id 7 >/dev/null || _fail "payload com os links do Drive"
  rm -rf "$d"
}

test_drive_links_refuses_missing_duplicate_and_bad_input() {
  local d out; d="$(mktemp -d)"; _sg "$d"
  python3 "$ROOT/scripts/stage_media.py" "$d/plan.json" --approvals "$d/ap" >/dev/null 2>&1; _found "$d"
  python3 - "$d" <<'PY'
import json, os, sys
d = sys.argv[1]; f = json.load(open(os.path.join(d, "found.json")))["files"]
f = [x for x in f if "p2__03" not in x["name"]]                     # falta uma imagem do p2 (sincronização incompleta)
f.append(dict(f[0], id="OutroIdDuplicado123"))                       # o vídeo do p1 aparece duas vezes
json.dump(f, open(os.path.join(d, "found.json"), "w"))
PY
  out=$(python3 "$ROOT/scripts/drive_links.py" "$d/plan.json" --found "$d/found.json" 2>&1) && _fail "faltando/duplicado aceito"
  assert_contains "$out" "não apareceu" "arquivo faltando"
  assert_contains "$out" "aparece 2 vezes" "duplicado"
  [ ! -e "$d/urls-p2.json" ] && [ ! -e "$d/urls-p1.json" ] || _fail "gerou links de post com problema"
  printf 'nao e json' > "$d/found.json"
  assert_fails python3 "$ROOT/scripts/drive_links.py" "$d/plan.json" --found "$d/found.json"
  rm "$d/.drive-staging.json"
  assert_fails python3 "$ROOT/scripts/drive_links.py" "$d/plan.json" --found "$d/found.json"
  rm -rf "$d"
}
