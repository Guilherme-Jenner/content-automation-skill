#!/usr/bin/env bash
# Adiciona uma trilha sonora (arquivo FORNECIDO pelo usuário) a um vídeo, sem re-encode do vídeo.
# Uso: add-soundtrack.sh <video> <musica> <saida.mp4> [--volume-db -18] [--force]
#   - música mais longa que o vídeo: cortada, com fade-out de até 1,5 s terminando no fim do vídeo;
#     mais curta: repetida em laço; fade-in de até 0,5 s;
#   - --volume-db: volume da trilha em relação ao original, de -40 a 0 (padrão -18). Só tem efeito quando o vídeo
#     já tem áudio: em vídeo mudo a trilha sai normalizada (~-14 LUFS) e o script avisa;
#   - --check-only: só valida (volume, vídeo, música) e sai, sem produzir nada;
#   - se o vídeo já tem áudio, a trilha entra por baixo (mistura simples, sem ducking);
#   - a saída é normalizada para ~-14 LUFS (normalize-audio.sh).
# Licença da música: responsabilidade do usuário. Este script não baixa nem gera música.
set -eu
here="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=lib/common.sh
. "$here/lib/common.sh"

force=0; volume="-18"; volume_set=0; check_only=0; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    --check-only) check_only=1; shift ;;
    --volume-db) [ $# -ge 2 ] || die "--volume-db exige um valor (volume da trilha de -40 a 0 dB)"; volume="$2"; volume_set=1; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
set -- ${args[@]+"${args[@]}"}
[ $# -ge 3 ] || die "uso: add-soundtrack.sh <video> <musica> <saida.mp4> [--volume-db -18] [--force]"
video="$(abspath "$1")"; music="$(abspath "$2")"; out="$(abspath "$3")"

python3 -c "import sys; v = float(sys.argv[1]); sys.exit(0 if -40 <= v <= 0 else 1)" "$volume" 2>/dev/null \
  || die "volume inválido: '$volume' (use um número de -40 a 0 dB)"
need_cmd ffmpeg "brew install ffmpeg"
need_cmd ffprobe "brew install ffmpeg"
[ "$check_only" -eq 1 ] || refuse_existing "$out" "$force"

[ -f "$video" ] || die "vídeo não encontrado: $video"
dur="$(probe_duration "$video")"
[ -f "$music" ] || die "arquivo de música não encontrado: $music"
ffprobe -v error -show_entries format=duration -of csv=p=0 "$music" >/dev/null 2>&1 </dev/null || die "não foi possível ler a música: $music"
[ -n "$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$music" </dev/null 2>/dev/null)" ] \
  || die "o arquivo de música não tem faixa de áudio: $music"
maxvol="$(ffmpeg -hide_banner -nostats -i "$music" -af volumedetect -f null - </dev/null 2>&1 | sed -n 's/.*max_volume: \(-\{0,1\}[0-9.]*\) dB.*/\1/p' | head -1)"
[ -n "$maxvol" ] || die "não foi possível medir o volume da música: $music"
python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) > -60 else 1)" "$maxvol" || die "a música está silenciosa (nada para misturar): $music"

tem_audio=0
[ -z "$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$video" </dev/null 2>/dev/null)" ] || tem_audio=1

# --check-only: só as validações (volume, vídeo e música); não produz nada. Usado por edit-generated.sh para
# recusar uma música ruim ANTES de reenquadrar ou queimar legendas.
[ "$check_only" -eq 0 ] || exit 0

if [ "$tem_audio" -eq 0 ] && [ "$volume_set" -eq 1 ]; then
  echo "aviso: este vídeo não tem áudio original; --volume-db só tem efeito quando há áudio para misturar. Aqui a trilha sai normalizada para ~-14 LUFS, qualquer que seja o volume pedido." >&2
fi

read -r fade_in fade_out fade_out_inicio <<EOF
$(python3 -c "import sys; d = float(sys.argv[1]); fi = min(0.5, d / 4); fo = min(1.5, d / 2); print(f'{fi:g} {fo:g} {d - fo:g}')" "$dur")
EOF
cadeia_musica="[1:a]atrim=0:${dur},asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo,afade=t=in:st=0:d=${fade_in},afade=t=out:st=${fade_out_inicio}:d=${fade_out},volume=${volume}dB"
if [ "$tem_audio" -eq 1 ]; then
  filtro="[0:a]aresample=48000,aformat=channel_layouts=stereo[orig];${cadeia_musica}[mus];[orig][mus]amix=inputs=2:duration=first:normalize=0[a]"
else
  filtro="${cadeia_musica}[a]"
fi

work="$(tmpdir)"
CURRENT_WORK="$work"
CURRENT_TMP="$(dirname "$out")/.$(basename "$out").partial.mp4"
trap 'rm -rf "$CURRENT_WORK" "$CURRENT_TMP"' EXIT
ffmpeg -v error -y -i "$video" -stream_loop -1 -i "$music" -filter_complex "$filtro" \
  -map 0:v:0 -map "[a]" -c:v copy -c:a aac -t "$dur" "$work/mixado.mp4" </dev/null || die "falha ao misturar a trilha"
"$here/normalize-audio.sh" "$work/mixado.mp4" "$CURRENT_TMP" --force || die "falha ao normalizar o áudio"
mv -f "$CURRENT_TMP" "$out"
echo "trilha adicionada: $out"
