#!/usr/bin/env bash
# Testes de validate_slideshow.py, slideshow_info.py e make-slideshow.sh (slideshow/carrossel a partir de fotos)

_sv() { python3 "$ROOT/scripts/validate_slideshow.py" "$@"; }

# _sp <dir> [expressão python que altera p] → cria 5 fotos em $d/fotos e grava $d/p.json (2 variantes)
_sp() {
  local d="$1" i
  mkdir -p "$d/fotos"
  for i in 1 2 3 4 5; do
    ffmpeg -v error -y -f lavfi -i "testsrc=size=1080x1350:rate=1:duration=1" -frames:v 1 "$d/fotos/f$i.jpg" </dev/null
  done
  python3 - "$d" "${2:-pass}" <<'PY'
import json, os, sys
d = sys.argv[1]
def sl(f, papel, texto): return {"foto": f, "papel": papel, "texto": texto}
p = {"quantidade": 2, "estilo": "padrao",
     "fotos": [{"id": f"f{i}", "arquivo": f"fotos/f{i}.jpg", "descricao": f"tela {i} do app"} for i in range(1, 6)],
     "variantes": [
        {"id": "A", "formato_hook": "pergunta", "formato_anuncio": "demo", "aprovada": True, "achados": ["pergunta retém mais"],
         "slides": [sl("f1", "hook", "Sua rotina vive bagunçada?"), sl("f2", "app", "O Clo App organiza tudo"), sl("f3", "prova", "Tudo em um lugar só"), sl("f4", "cta", "Baixe o Clo App")]},
        {"id": "B", "formato_hook": "resultado", "formato_anuncio": "antes_depois", "aprovada": True, "achados": ["resultado primeiro"],
         "slides": [sl("f4", "hook", "Organizei minha semana em 5 min"), sl("f3", "problema", "Antes: caos"), sl("f2", "app", "Agora: Clo App"), sl("f5", "cta", "Teste grátis")]}]}
exec(sys.argv[2])
json.dump(p, open(os.path.join(d, "p.json"), "w", encoding="utf-8"), ensure_ascii=False)
PY
}
# _sbad <expressão> → saída do validador; retorna o status dele
_sbad() { local d out rc; d="$(mktemp -d)"; _sp "$d" "$1"; out=$(_sv "$d/p.json" 2>&1); rc=$?; rm -rf "$d"; printf '%s' "$out"; return "$rc"; }

test_slideshow_valid_plan_passes() {
  local d; d="$(mktemp -d)"; _sp "$d"
  _sv "$d/p.json" >/dev/null 2>&1 || _fail "plano válido recusado"
  rm -rf "$d"
}

test_slideshow_structure_rules() {
  local out
  out=$(_sbad "p['variantes'][0]['slides'][0]['papel']='app'") && _fail "primeiro slide sem hook aceito"; assert_contains "$out" "hook" "hook"
  out=$(_sbad "p['variantes'][0]['slides'][-1]['papel']='prova'") && _fail "último slide sem cta aceito"; assert_contains "$out" "cta" "cta"
  out=$(_sbad "p['variantes'][0]['slides'][1]['papel']='prova'") && _fail "sem slide de app aceito"; assert_contains "$out" "app" "app"
  out=$(_sbad "p['variantes'][0]['slides'][2]['foto']='f1'") && _fail "foto repetida aceita"; assert_contains "$out" "repetida" "foto repetida"
  out=$(_sbad "p['variantes'][0]['slides'][2]['foto']='f9'") && _fail "foto inexistente aceita"; assert_contains "$out" "f9" "foto inexistente"
  out=$(_sbad "p['variantes'][0]['slides']=p['variantes'][0]['slides'][:2]") && _fail "2 slides aceitos"
}

test_slideshow_text_duration_and_files() {
  local out
  out=$(_sbad "p['variantes'][0]['slides'][1]['texto']='x '*80") && _fail "texto longo aceito"; assert_contains "$out" "3 linhas" "texto longo"
  out=$(_sbad "p['variantes'][0]['slides'][1]['duracao_s']=0.5") && _fail "duração curta aceita"; assert_contains "$out" "duracao_s" "duração"
  out=$(_sbad "p['fotos'][0]['arquivo']='fotos/nao.jpg'") && _fail "arquivo ausente aceito"; assert_contains "$out" "não encontrado" "arquivo ausente"
  out=$(_sbad "p['fotos'][0]['arquivo']='/etc/passwd'") && _fail "caminho absoluto aceito"; assert_contains "$out" "dentro da pasta" "caminho absoluto"
  out=$(_sbad "p['fotos'][0]['arquivo']='fotos/f1.gif'") && _fail "formato gif aceito"; assert_contains "$out" "formato" "formato"
}

test_slideshow_variants_must_differ() {
  local out
  out=$(_sbad "p['variantes'][1]=json.loads(json.dumps(p['variantes'][0])); p['variantes'][1]['id']='B'; p['variantes'][1]['formato_hook']='numero'") \
    && _fail "variante idêntica aceita"; assert_contains "$out" "idêntica" "variante idêntica"
  out=$(_sbad "p['variantes'][1]['formato_hook']='pergunta'") && _fail "formato_hook repetido sem justificativa aceito"; assert_contains "$out" "justificativa" "hook repetido"
  _sbad "p['variantes'][1]['formato_hook']='pergunta'; p['variantes'][1]['gancho_repetido']=True; p['variantes'][1]['justificativa_gancho']='só 2 ganchos bons'" >/dev/null \
    || _fail "hook repetido justificado recusado"
  out=$(_sbad "p['quantidade']=3") && _fail "quantidade errada aceita"
}

test_make_slideshow_renders_video_and_carousel() {
  local d out; d="$(mktemp -d)"; _sp "$d" "p['variantes'][1]['aprovada']=False"
  out=$(bash "$ROOT/scripts/make-slideshow.sh" "$d/p.json" "$d/out" 2>&1) || _fail "make-slideshow falhou: $out"
  assert_file_exists "$d/out/slideshow-A.mp4"
  assert_file_exists "$d/out/slideshow-A.srt"
  assert_file_exists "$d/out/carrossel-A/slide-04.png"
  [ ! -e "$d/out/slideshow-B.mp4" ] || _fail "variante não aprovada foi montada"
  assert_near 10 "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$d/out/slideshow-A.mp4")" 0.3 "4 slides de 2,5 s"
  assert_eq "1080x1920" "$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=s=x:p=0 "$d/out/slideshow-A.mp4")" "9:16"
  assert_contains "$(cat "$d/out/slideshow-A.srt")" "Sua rotina vive bagunçada?" "legenda do hook"
  out=$(bash "$ROOT/scripts/make-slideshow.sh" "$d/p.json" "$d/out" 2>&1) && _fail "sobrescreveu sem --force"
  rm -rf "$d"
}

test_make_slideshow_refuses_without_approval_and_invalid_plan() {
  local d; d="$(mktemp -d)"; _sp "$d" "p['variantes'][0]['aprovada']=False; p['variantes'][1]['aprovada']=False"
  assert_fails bash "$ROOT/scripts/make-slideshow.sh" "$d/p.json" "$d/out"
  _sp "$d" "p['quantidade']=9"
  assert_fails bash "$ROOT/scripts/make-slideshow.sh" "$d/p.json" "$d/out"
  rm -rf "$d"
}
