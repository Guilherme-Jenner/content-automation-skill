#!/usr/bin/env python3
"""Converte o JSON do whisper.cpp (-oj) para o formato transcript do pipeline.

Uso: whisper_to_transcript.py <whisper.json>   (imprime o transcript em stdout)
"""
import json
import sys


def main(argv):
    with open(argv[1], encoding="utf-8") as f:
        dados = json.load(f)
    segmentos = []
    for s in dados.get("transcription", []):
        texto = s.get("text", "").strip()
        if not texto:
            continue
        segmentos.append(
            {
                "inicio_s": round(s["offsets"]["from"] / 1000, 3),
                "fim_s": round(s["offsets"]["to"] / 1000, 3),
                "texto": texto,
            }
        )
    saida = {"idioma": dados.get("result", {}).get("language", "pt"), "segmentos": segmentos}
    json.dump(saida, sys.stdout, ensure_ascii=False, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
