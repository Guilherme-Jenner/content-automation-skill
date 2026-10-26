#!/usr/bin/env bash
# Testes do carrossel no plano de agendamento e do adaptador do Metricool (payload preparado para o agente; nada é enviado)

NOW="2026-10-20T10:00:00-03:00"

# _mq <dir> [expressão python que altera p] → plan.json com p1 (vídeo) e p2 (carrossel de 3 imagens), media-urls
_mq() {
  mkdir -p "$1"; printf 'video' > "$1/v.mp4"; printf 'a' > "$1/s1.png"; printf 'b' > "$1/s2.png"; printf 'c' > "$1/s3.png"
  python3 - "$1" "${2:-pass}" <<'PY'
import json, os, sys
d = sys.argv[1]
perfis = [{"rede": "instagram", "conta": "clo.app"}, {"rede": "tiktok", "conta": "clo.app"}]
p = {"posts": [
    {"id": "p1", "video": "v.mp4", "legenda": "Rotina organizada", "hashtags": ["#clo"], "perfis": perfis, "data_hora": "2026-10-21T12:00:00-03:00"},
    {"id": "p2", "imagens": ["s1.png", "s2.png", "s3.png"], "legenda": "Sua rotina vive bagunçada?", "hashtags": ["#clo", "#rotina"], "perfis": perfis,
     "data_hora": "2026-10-22T19:00:00-03:00", "conteudo_ia": False}]}
exec(sys.argv[2])
json.dump(p, open(os.path.join(d, "plan.json"), "w", encoding="utf-8"), ensure_ascii=False)
json.dump({"v.mp4": "https://exemplo.com/v.mp4", "s1.png": "https://exemplo.com/1.png", "s2.png": "https://exemplo.com/2.png", "s3.png": "https://exemplo.com/3.png"},
          open(os.path.join(d, "urls.json"), "w"))
# media-urls por post (o payload recusa entradas de outro post)
json.dump({"v.mp4": "https://exemplo.com/v.mp4"}, open(os.path.join(d, "urls-p1.json"), "w"))
json.dump({k: v for k, v in {"s1.png": "https://exemplo.com/1.png", "s2.png": "https://exemplo.com/2.png", "s3.png": "https://exemplo.com/3.png"}.items()},
          open(os.path.join(d, "urls-p2.json"), "w"))
PY
}
_ap() { python3 "$ROOT/scripts/approval.py" approve "$1/plan.json" "$2" "$1/ap" --now "$NOW" >/dev/null 2>&1 || _fail "approve $2 falhou"; }
_mp() { python3 "$ROOT/scripts/metricool_payload.py" "$@"; }

test_carousel_plan_validates_and_rejects_bad_media() {
  local d out; d="$(mktemp -d)"; _mq "$d"
  python3 "$ROOT/scripts/validate_schedule.py" "$d/plan.json" --now "$NOW" || _fail "plano com carrossel recusado"
  _mq "$d" "p['posts'][1]['video']='v.mp4'"
  out=$(python3 "$ROOT/scripts/validate_schedule.py" "$d/plan.json" --now "$NOW" 2>&1) && _fail "vídeo e imagens juntos aceitos"; assert_contains "$out" "OU" "um dos dois"
  _mq "$d" "p['posts'][1]['imagens']=['s1.png']"
  assert_fails python3 "$ROOT/scripts/validate_schedule.py" "$d/plan.json" --now "$NOW"
  _mq "$d" "p['posts'][1]['imagens']=['s1.png','nao.png']"
  out=$(python3 "$ROOT/scripts/validate_schedule.py" "$d/plan.json" --now "$NOW" 2>&1) && _fail "imagem ausente aceita"; assert_contains "$out" "não encontrado" "imagem ausente"
  _mq "$d" "del p['posts'][1]['imagens']"
  assert_fails python3 "$ROOT/scripts/validate_schedule.py" "$d/plan.json" --now "$NOW"
  rm -rf "$d"
}

test_carousel_approval_is_bound_to_images_and_order() {
  local d; d="$(mktemp -d)"; _mq "$d"; _ap "$d" p2
  python3 "$ROOT/scripts/approval.py" verify "$d/plan.json" p2 "$d/ap" >/dev/null 2>&1 || _fail "verify deveria passar"
  python3 - "$d/plan.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1])); p["posts"][1]["imagens"] = ["s2.png", "s1.png", "s3.png"]; json.dump(p, open(sys.argv[1], "w"))
PY
  assert_fails python3 "$ROOT/scripts/approval.py" verify "$d/plan.json" p2 "$d/ap"   # outra ordem = outra aprovação
  _mq "$d"; printf 'trocada' > "$d/s3.png"
  assert_fails python3 "$ROOT/scripts/approval.py" verify "$d/plan.json" p2 "$d/ap"   # imagem mudou
  rm -rf "$d"
}

test_payload_for_video_and_carousel() {
  local d out; d="$(mktemp -d)"; _mq "$d"
  out=$(_mp plano "$d/plan.json" p1 --urls "$d/urls-p1.json" --blog-id 123) || _fail "payload do vídeo falhou: $out"
  assert_eq "REEL" "$(printf '%s' "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.loads(d['argumentos']['info'])['instagramData']['type'])")" "vídeo = REEL"
  assert_eq "False" "$(printf '%s' "$out" | python3 -c "import json,sys; print(json.load(sys.stdin)['argumentos']['autoPublish'])")" "modo teste não publica sozinho"
  assert_contains "$out" "SELF_ONLY" "TikTok privado no teste"
  out=$(_mp plano "$d/plan.json" p2 --urls "$d/urls-p2.json" --blog-id 123 --modo real) || _fail "payload do carrossel falhou: $out"
  assert_eq "POST" "$(printf '%s' "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.loads(d['argumentos']['info'])['instagramData']['type'])")" "imagens = POST"
  assert_eq "3" "$(printf '%s' "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(json.loads(d['argumentos']['info'])['media']))")" "3 mídias"
  assert_eq "True" "$(printf '%s' "$out" | python3 -c "import json,sys; print(json.load(sys.stdin)['argumentos']['autoPublish'])")" "modo real publica"
  assert_contains "$out" "valide em modo teste" "avisa que o Modo Foto não foi executado"
  assert_contains "$out" "photoCoverIndex" "capa do Modo Foto"
  assert_contains "$out" "#clo #rotina" "hashtags no texto"
  assert_contains "$out" "2026-10-22T19:00:00" "data e hora"
  rm -rf "$d"
}

test_payload_refuses_bad_urls_and_ids() {
  local d out; d="$(mktemp -d)"; _mq "$d"
  out=$(_mp plano "$d/plan.json" p2 --urls "$d/urls-p1.json" --blog-id 123 2>&1) && _fail "URLs faltando aceitas"; assert_contains "$out" "faltam" "faltam URLs"
  out=$(_mp plano "$d/plan.json" p2 --urls "$d/urls.json" --blog-id 123 2>&1) && _fail "entrada de outro post aceita"; assert_contains "$out" "não são deste post" "extras"
  printf '{"s1.png":"http://x/1.png","s2.png":"https://x/2.png","s3.png":"https://x/3.png"}' > "$d/u.json"
  out=$(_mp plano "$d/plan.json" p2 --urls "$d/u.json" --blog-id 123 2>&1) && _fail "http aceito"; assert_contains "$out" "https" "só https"
  assert_fails _mp plano "$d/plan.json" p1 --urls "$d/urls-p1.json" --blog-id abc
  assert_fails _mp plano "$d/plan.json" p1 --urls "$d/urls-p1.json" --blog-id 123 --modo qualquer
  assert_fails _mp plano "$d/plan.json" p1 --urls "$d/urls-p1.json" --blog-id 123 --timezone "Sao Paulo"
  out=$(_mp plano "$d/plan.json" p1 --urls "$d/urls-p1.json" --blog-id 123 --timezone America/Recife)
  assert_contains "$out" "America/Recife" "fuso da marca"
  assert_contains "$out" '"blogId": "123"' "blogId é texto"
  rm -rf "$d"
}

test_ai_flag_goes_into_payload_and_approval_hash() {
  local d out; d="$(mktemp -d)"; _mq "$d" "p['posts'][0]['conteudo_ia']=True"; _ap "$d" p1
  out=$(_mp plano "$d/plan.json" p1 --urls "$d/urls-p1.json" --blog-id 1)
  assert_contains "$out" 'isAiGenerated\": true' "declara IA no Instagram"
  assert_contains "$out" 'isAigc\": true' "declara IA no TikTok"
  _mq "$d" "p['posts'][0]['conteudo_ia']=False"
  assert_fails python3 "$ROOT/scripts/approval.py" verify "$d/plan.json" p1 "$d/ap"   # trocar a declaração invalida a aprovação
  rm -rf "$d"
}

_sm() { bash "$ROOT/scripts/schedule.sh" "$1/plan.json" "$2" --approvals "$1/ap" --scheduler metricool --urls "$1/urls-$2.json" --blog-id 123 --now "$NOW" "${@:3}"; }

test_schedule_metricool_dry_run_confirm_commit_and_release() {
  local d out; d="$(mktemp -d)"; _mq "$d"; _ap "$d" p2
  out=$(_sm "$d" p2 2>&1) || _fail "simulação falhou: $out"
  assert_contains "$out" "SIMULAÇÃO" "simulação"; assert_contains "$out" "createScheduledPost" "mostra o payload"
  [ ! -e "$d/.schedule-log.json" ] || _fail "simulação não grava log"
  out=$(_sm "$d" p2 --confirm 2>&1) || _fail "confirm falhou: $out"
  assert_contains "$out" "PAYLOAD PRONTO" "payload gerado"
  assert_eq "em_andamento" "$(python3 "$ROOT/scripts/schedule_log.py" status "$d/plan.json" p2 "$d/.schedule-log.json")" "reserva aberta, nada marcado como agendado"
  assert_file_exists "$(ls -d "$d"/.snapshots/p2-*)/metricool-payload.json"
  assert_file_exists "$(ls -d "$d"/.snapshots/p2-*)/imagem-03.png"
  out=$(_sm "$d" p2 --confirm 2>&1) && _fail "segunda reserva aceita"
  python3 "$ROOT/scripts/schedule_log.py" commit "$d/plan.json" p2 "$d/.schedule-log.json" "https://planner.metricool.com/x" >/dev/null || _fail "commit falhou"
  assert_eq "agendado" "$(python3 "$ROOT/scripts/schedule_log.py" status "$d/plan.json" p2 "$d/.schedule-log.json")" "agendado após commit"
  out=$(_sm "$d" p2 --confirm 2>&1) && _fail "reagendou o mesmo post"
  rm -rf "$d"
}

test_schedule_metricool_needs_approval_urls_and_releases_on_bad_payload() {
  local d out; d="$(mktemp -d)"; _mq "$d"
  assert_fails _sm "$d" p2 --confirm                                  # sem aprovação
  _ap "$d" p2
  assert_fails bash "$ROOT/scripts/schedule.sh" "$d/plan.json" p2 --approvals "$d/ap" --scheduler metricool --now "$NOW"   # sem --urls/--blog-id
  printf '{"s1.png":"https://x/1.png"}' > "$d/urls-p2.json"
  out=$(_sm "$d" p2 --confirm 2>&1) && _fail "payload incompleto aceito"; assert_contains "$out" "liberada" "reserva liberada"
  assert_eq "livre" "$(python3 "$ROOT/scripts/schedule_log.py" status "$d/plan.json" p2 "$d/.schedule-log.json")" "livre após falha do payload"
  rm -rf "$d"
}
