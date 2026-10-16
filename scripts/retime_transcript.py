#!/usr/bin/env python3
"""Reajusta um transcript para a linha do tempo do vídeo DEPOIS dos cortes.

Uso: retime_transcript.py <transcript.json> <cut-plan.json>   (imprime o novo transcript)
Segmentos totalmente dentro de um corte somem; os parcialmente cortados ficam só com a parte mantida.
"""
import json
import sys


def mapear(t, cortes):
    """Tempo original -> tempo no vídeo cortado."""
    return t - sum(min(c["fim_s"], t) - c["inicio_s"] for c in cortes if c["inicio_s"] < t)


def parte_mantida(ini, fim, cortes):
    """Subintervalos de [ini, fim] que sobram depois de remover os cortes."""
    restos = [(ini, fim)]
    for c in cortes:
        novos = []
        for a, b in restos:
            if c["fim_s"] <= a or c["inicio_s"] >= b:
                novos.append((a, b))
                continue
            if c["inicio_s"] > a:
                novos.append((a, c["inicio_s"]))
            if c["fim_s"] < b:
                novos.append((c["fim_s"], b))
        restos = novos
    return restos


def main(argv):
    with open(argv[1], encoding="utf-8") as f:
        transcript = json.load(f)
    with open(argv[2], encoding="utf-8") as f:
        cortes = sorted(json.load(f)["cortes"], key=lambda c: c["inicio_s"])
    segmentos = []
    for s in transcript["segmentos"]:
        restos = [(a, b) for a, b in parte_mantida(s["inicio_s"], s["fim_s"], cortes) if b - a > 0.01]
        if not restos:
            continue
        segmentos.append(
            {
                "inicio_s": round(mapear(restos[0][0], cortes), 3),
                "fim_s": round(mapear(restos[-1][1], cortes), 3),
                "texto": s["texto"],
            }
        )
    json.dump({"idioma": transcript["idioma"], "segmentos": segmentos}, sys.stdout, ensure_ascii=False, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
