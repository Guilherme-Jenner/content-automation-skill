#!/usr/bin/env python3
"""Converte um transcript no JSON de entrada do Remotion (legenda palavra por palavra).

Uso: to_remotion_input.py <transcript.json> <video> [--fps 30]   (imprime o JSON em stdout)
O tempo de cada segmento é dividido entre as palavras proporcionalmente ao tamanho delas.
O visual (template) é a fase 5 do projeto; aqui só existe o contrato.
"""
import json
import sys


def main(argv):
    fps = 30.0
    args = argv[1:]
    if "--fps" in args:
        i = args.index("--fps")
        fps = float(args[i + 1])
        del args[i : i + 2]
    transcript_path, video = args[0], args[1]
    with open(transcript_path, encoding="utf-8") as f:
        transcript = json.load(f)

    palavras = []
    for seg in transcript["segmentos"]:
        textos = seg["texto"].split()
        if not textos:
            continue
        total = sum(len(t) for t in textos)
        duracao = seg["fim_s"] - seg["inicio_s"]
        pos = seg["inicio_s"]
        for n, t in enumerate(textos):
            fim = seg["fim_s"] if n == len(textos) - 1 else pos + duracao * len(t) / total
            palavras.append({"texto": t, "inicio_s": round(pos, 3), "fim_s": round(fim, 3)})
            pos = fim

    saida = {"video": video, "largura": 1080, "altura": 1920, "fps": fps, "palavras": palavras, "estilo": "padrao"}
    # Bytes UTF-8 + LF, igual nos outros scripts: o console do Windows usa outra codificação e quebraria os acentos.
    sys.stdout.buffer.write((json.dumps(saida, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
