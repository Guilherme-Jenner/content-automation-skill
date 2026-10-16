#!/usr/bin/env python3
"""Valida um plano de cortes: schema, limites da duração e ausência de sobreposição.

Uso: validate_cutplan.py <cut-plan.json>
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_json import validar  # noqa: E402

SCHEMA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "schemas", "cut-plan.schema.json")


def main(argv):
    with open(SCHEMA, encoding="utf-8") as f:
        schema = json.load(f)
    with open(argv[1], encoding="utf-8") as f:
        plano = json.load(f)
    erros = []
    validar(plano, schema, "", erros)
    if not erros:
        dur = plano["duracao_s"]
        cortes = sorted(plano["cortes"], key=lambda c: c["inicio_s"])
        anterior_fim = 0.0
        for i, c in enumerate(cortes):
            if c["fim_s"] <= c["inicio_s"]:
                erros.append(f"cortes[{i}]: intervalo invertido ({c['inicio_s']}s a {c['fim_s']}s)")
            if c["fim_s"] > dur + 0.01:
                erros.append(f"cortes[{i}]: fora da duração do vídeo ({dur}s)")
            if c["inicio_s"] < anterior_fim - 1e-9:
                erros.append(f"cortes[{i}]: sobrepõe o corte anterior")
            anterior_fim = max(anterior_fim, c["fim_s"])
    for e in erros:
        print(e, file=sys.stderr)
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
