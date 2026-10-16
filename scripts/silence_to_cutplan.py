#!/usr/bin/env python3
"""Converte a saída do filtro silencedetect do ffmpeg (stdin) em um plano de cortes.

Uso: ffmpeg ... -af silencedetect ... 2>&1 | silence_to_cutplan.py <video> <duracao_s> <pad_s>
Cada silêncio vira um corte encolhido por pad_s em cada borda (preserva respiro).
O plano sai com approved=false. Se o vídeo inteiro for silêncio, sai com código 3.
"""
import json
import re
import sys


def main(argv):
    video, duracao, pad = argv[1], float(argv[2]), float(argv[3])
    inicio = None
    silencios = []
    for linha in sys.stdin:
        m = re.search(r"silence_start: (-?[\d.]+)", linha)
        if m:
            inicio = max(0.0, float(m.group(1)))
            continue
        m = re.search(r"silence_end: ([\d.]+)", linha)
        if m and inicio is not None:
            silencios.append((inicio, min(float(m.group(1)), duracao)))
            inicio = None
    if inicio is not None:  # silêncio até o fim do arquivo
        silencios.append((inicio, duracao))

    if silencios and sum(f - i for i, f in silencios) >= duracao - 0.05:
        print("o vídeo inteiro é silêncio; nada para cortar", file=sys.stderr)
        return 3

    cortes = []
    for i, f in silencios:
        ini = i + pad if i > 0 else i
        fim = f - pad if f < duracao else f
        if fim - ini > 0.05:
            cortes.append({"inicio_s": round(ini, 3), "fim_s": round(fim, 3), "motivo": "silêncio"})

    plano = {"video": video, "duracao_s": round(duracao, 3), "approved": False, "cortes": cortes}
    json.dump(plano, sys.stdout, ensure_ascii=False, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
