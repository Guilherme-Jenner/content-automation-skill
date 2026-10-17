#!/usr/bin/env python3
"""Valida um variants-plan.json (de 1 a 5 variantes de um mesmo vídeo bruto).

Erros (exit 1): schema; quantidade fora de 1..5 ou diferente do número de variantes; ids repetidos;
trechos sobrepostos, fora da duração ou somando menos de 1 s; gancho repetido sem justificativa;
variante sem achados da pesquisa.
Avisos (stderr, exit 0): variantes trecho_diferente com trechos quase idênticos.

Uso: validate_variants.py <variants-plan.json>
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_json import validar  # noqa: E402

SCHEMA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "schemas", "variants-plan.schema.json")
MAX_VARIANTES = 5


def soma(trechos):
    return sum(t["fim_s"] - t["inicio_s"] for t in trechos)


def intersecao(a, b):
    total = 0.0
    for x in a:
        for y in b:
            total += max(0.0, min(x["fim_s"], y["fim_s"]) - max(x["inicio_s"], y["inicio_s"]))
    return total


def main(argv):
    with open(SCHEMA, encoding="utf-8") as f:
        schema = json.load(f)
    with open(argv[1], encoding="utf-8") as f:
        plano = json.load(f)
    erros, avisos = [], []
    validar(plano, schema, "", erros)
    if not erros:
        variantes = plano["variantes"]
        dur = plano["duracao_s"]
        if not 1 <= plano["quantidade"] <= MAX_VARIANTES:
            erros.append(f"quantidade deve estar entre 1 e {MAX_VARIANTES} (recebido {plano['quantidade']})")
        if plano["quantidade"] != len(variantes):
            erros.append(f"quantidade ({plano['quantidade']}) não bate com o número de variantes ({len(variantes)})")
        ids = [v["id"] for v in variantes]
        if len(set(ids)) != len(ids):
            erros.append("ids de variantes repetidos")
        for i, v in enumerate(variantes):
            nome = f"variantes[{i}]"
            trechos = sorted(v["trechos"], key=lambda t: t["inicio_s"])
            anterior = 0.0
            for j, t in enumerate(trechos):
                if t["fim_s"] <= t["inicio_s"]:
                    erros.append(f"{nome}.trechos[{j}]: intervalo invertido")
                if t["fim_s"] > dur + 0.01:
                    erros.append(f"{nome}.trechos[{j}]: fora da duração do bruto ({dur}s)")
                if t["inicio_s"] < anterior - 1e-9:
                    erros.append(f"{nome}.trechos[{j}]: sobrepõe o trecho anterior")
                anterior = max(anterior, t["fim_s"])
            if not erros and soma(trechos) < 1.0:
                erros.append(f"{nome}: os trechos somam menos de 1 s")
            if not v["achados"]:
                erros.append(f"{nome}: achados vazio (ligue a variante à pesquisa)")
        # ganchos
        vistos = {}
        for i, v in enumerate(variantes):
            g = v["gancho"].strip().lower()
            if g in vistos:
                if not (v.get("gancho_repetido") and v.get("justificativa_gancho", "").strip()):
                    erros.append(
                        f"variantes[{i}]: gancho repetido de variantes[{vistos[g]}] sem gancho_repetido e justificativa_gancho"
                    )
            else:
                vistos[g] = i
        # redundância
        if not erros:
            for i in range(len(variantes)):
                for j in range(i + 1, len(variantes)):
                    a, b = variantes[i], variantes[j]
                    if a["tipo"] == b["tipo"] == "trecho_diferente":
                        menor = min(soma(a["trechos"]), soma(b["trechos"]))
                        if menor > 0 and intersecao(a["trechos"], b["trechos"]) / menor > 0.8:
                            avisos.append(
                                f"aviso: variantes {a['id']} e {b['id']} (trecho_diferente) têm trechos quase idênticos"
                            )
    for e in erros:
        print(e, file=sys.stderr)
    for a in avisos:
        print(a, file=sys.stderr)
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
