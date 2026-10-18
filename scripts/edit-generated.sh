#!/usr/bin/env bash
# Edição do modo gerado: legendas por cena e/ou trilha sonora sobre o vídeo montado. Não gasta crédito.
# Uso: edit-generated.sh <video-montado> <gen-plan> <clips-manifest.json> <saida.mp4>
#                        [--captions <captions-plan.json>] [--music <arquivo de áudio>] [--volume-db -18] [--force]
#   - exige --captions e/ou --music;
#   - valida TUDO antes de processar (legendas contra o manifesto e a duração real dos clipes; música);
#   - vídeo que não for 1080x1920 é reenquadrado (reframe-9x16.sh);
#   - ordem: reenquadrar (se preciso) → trilha → legendas (estilo do plano); gera <saida>.srt quando há legendas;
#   - gravação atômica; nada fica para trás se algo falhar.
# A música é fornecida pelo usuário (a licença é responsabilidade dele); nada é baixado nem gerado aqui.
set -eu
_src="${BASH_SOURCE[0]}"; case "$_src" in */*) _dir="${_src%/*}" ;; *) _dir=. ;; esac; here="$(cd "$_dir" && pwd)"   # bash puro: sem dirname externo
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

force=0; captions=""; music=""; vol_args=(); args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    --captions) [ $# -ge 2 ] || die "--captions exige o captions-plan.json"; captions="$(abspath "$2")"; shift 2 ;;
    --music) [ $# -ge 2 ] || die "--music exige o arquivo de áudio"; music="$(abspath "$2")"; shift 2 ;;
    --volume-db) [ $# -ge 2 ] || die "--volume-db exige um valor"; vol_args=(--volume-db "$2"); shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
set -- ${args[@]+"${args[@]}"}
[ $# -ge 4 ] || die "uso: edit-generated.sh <video-montado> <gen-plan> <clips-manifest.json> <saida.mp4> [--captions <plano>] [--music <arquivo>] [--volume-db -18] [--force]"
video="$(abspath "$1")"; plan="$(abspath "$2")"; manifest="$(abspath "$3")"; out="$(abspath "$4")"
[ -n "$captions" ] || [ -n "$music" ] || die "informe --captions <plano de legendas> e/ou --music <arquivo de música>: sem nenhuma das duas não há o que editar"

need_cmd ffmpeg "brew install ffmpeg"
need_cmd ffprobe "brew install ffmpeg"
need_cmd python3 "brew install python"
[ -f "$video" ] || die "vídeo não encontrado: $video"
[ -f "$plan" ] || die "gen-plan não encontrado: $plan"
[ -f "$manifest" ] || die "manifesto não encontrado: $manifest"
srt_out="$(srt_path "$out")"
[ -d "$(dirname "$out")" ] || die "a pasta de saída não existe: $(dirname "$out")"
python3 "$here/validate_genplan.py" "$plan" || die "plano de geração inválido: $plan"
refuse_existing "$out" "$force"
if [ -n "$captions" ]; then
  [ -f "$captions" ] || die "plano de legendas não encontrado: $captions"
  refuse_existing "$srt_out" "$force"
fi
dur_video="$(probe_duration "$video")"

# O vídeo montado precisa corresponder AOS CLIPES E AO PLANO atuais: o manifesto confere hash e versão do plano
# (um clipe regerado depois da montagem, ou um plano alterado, desloca ou apaga legendas sem nenhum erro).
lista="$(python3 "$here/clips_manifest.py" verify "$manifest" "$plan")" || die "os clipes não conferem com o manifesto e o plano; gere/registre de novo e monte outra vez com assemble-clips.sh"
total_real="$(printf '%s\n' "$lista" | python3 -c "
import subprocess, sys
total, n = 0.0, 0
for linha in sys.stdin.read().split('\n'):
    if not linha.strip():
        continue
    r = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', linha.strip()],
                       capture_output=True, text=True, stdin=subprocess.DEVNULL)
    total += float(r.stdout.strip())
    n += 1
print(f'{total:.3f} {n}')")"
read -r soma_clipes n_clipes <<EOT
$total_real
EOT
python3 -c "import sys; soma, dur, n = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3]); sys.exit(0 if abs(soma - dur) <= 0.1 + 0.05 * n else 1)" "$soma_clipes" "$dur_video" "$n_clipes" \
  || die "o vídeo montado (${dur_video} s) não corresponde aos clipes atuais (${soma_clipes} s no total): monte de novo com assemble-clips.sh antes de editar"

work="$(tmpdir)"
CURRENT_WORK="$work"
CURRENT_TMP="$(dirname "$out")/.$(basename "$out").partial.mp4"
CURRENT_SRT_TMP="$(dirname "$out")/.$(basename "$srt_out").partial"
trap 'rm -rf "$CURRENT_WORK" "$CURRENT_TMP" "$CURRENT_SRT_TMP"' EXIT

# 1) valida e converte as legendas (barato) antes de qualquer processamento pesado
estilo=padrao
if [ -n "$captions" ]; then
  python3 "$here/captions_to_transcript.py" "$captions" "$plan" "$manifest" > "$work/transcript.json" \
    || die "as legendas não conferem com o plano e os clipes; nada foi gerado"
  estilo="$(python3 "$here/captions_to_transcript.py" "$captions" "$plan" "$manifest" --estilo)"
fi

# 1b) valida a música (e o volume) ANTES de qualquer etapa pesada
if [ -n "$music" ]; then
  "$here/add-soundtrack.sh" "$video" "$music" "$work/validacao.mp4" ${vol_args[@]+"${vol_args[@]}"} --check-only || die "a música não pode ser usada; nada foi gerado"
fi

# 2) etapas (cada uma só começa depois da anterior ter dado certo)
cur="$video"
dims="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$cur" </dev/null)"
if [ "$dims" != "1080,1920" ]; then
  "$here/reframe-9x16.sh" "$cur" "$work/0-vertical.mp4" --force || die "falha ao reenquadrar o vídeo para 9:16"
  cur="$work/0-vertical.mp4"
fi
if [ -n "$music" ]; then
  "$here/add-soundtrack.sh" "$cur" "$music" "$work/1-trilha.mp4" ${vol_args[@]+"${vol_args[@]}"} --force || die "falha ao adicionar a trilha"
  cur="$work/1-trilha.mp4"
fi
if [ -n "$captions" ]; then
  "$here/subtitles.sh" "$cur" "$work/transcript.json" "$work/2-legendado.mp4" --style "$estilo" --force || die "falha ao queimar as legendas"
  cur="$work/2-legendado.mp4"
fi

# 3) entrega atômica
cp "$cur" "$CURRENT_TMP"
if [ -n "$captions" ]; then
  cp "$work/2-legendado.srt" "$CURRENT_SRT_TMP"
  mv -f "$CURRENT_SRT_TMP" "$srt_out"
elif [ "$force" -eq 1 ]; then
  rm -f "$srt_out"   # a saída antiga tinha legendas e a nova não tem: o .srt velho não pode ficar ao lado
fi
mv -f "$CURRENT_TMP" "$out"
echo "pronto: $out"
