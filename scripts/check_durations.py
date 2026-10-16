#!/usr/bin/env python3
"""Confere se a soma das durações de cenas/takes bate com duracao_alvo_s (tolerância de 10%).

Uso: check_durations.py <storyboard.json|shot-list.json>
"""
import json
import sys

TOLERANCIA = 0.10


def main(argv):
    if len(argv) != 2:
        print("uso: check_durations.py <arquivo.json>", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        dados = json.load(f)
    itens = dados.get("cenas") or dados.get("takes") or []
    soma = sum(i["duracao_s"] for i in itens)
    alvo = dados["duracao_alvo_s"]
    if abs(soma - alvo) > alvo * TOLERANCIA:
        print(
            f"a soma das durações ({soma:g}s) difere do alvo ({alvo:g}s) em mais de {TOLERANCIA:.0%}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
