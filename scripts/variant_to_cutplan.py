#!/usr/bin/env python3
"""Converte uma variante do variants-plan.json em um cut-plan (cortes = complemento dos trechos mantidos).

Uso: variant_to_cutplan.py <variants-plan.json> <id> <video> [--merge <cut-plan.json>]   (imprime o cut-plan em stdout)
--merge une os cortes de outro plano (ex.: silêncios detectados com o ritmo da variante).
approved vem da aprovação DA variante; aprovar uma não aprova as outras.
"""
import json
import sys


def unir(cortes):
    """Ordena e funde cortes que se tocam ou se sobrepõem."""
    unidos = []
    for c in sorted(cortes, key=lambda c: c["inicio_s"]):
        if unidos and c["inicio_s"] <= unidos[-1]["fim_s"] + 1e-9:
            unidos[-1]["fim_s"] = max(unidos[-1]["fim_s"], c["fim_s"])
        else:
            unidos.append(dict(c))
    return unidos


def main(argv):
    with open(argv[1], encoding="utf-8") as f:
        plano = json.load(f)
    alvo = next((v for v in plano["variantes"] if v["id"] == argv[2]), None)
    if alvo is None:
        print(f"variante '{argv[2]}' não existe no plano", file=sys.stderr)
        return 1
    dur = plano["duracao_s"]
    cortes, pos = [], 0.0
    for t in sorted(alvo["trechos"], key=lambda t: t["inicio_s"]):
        if t["inicio_s"] - pos > 1e-9:
            cortes.append({"inicio_s": round(pos, 3), "fim_s": round(t["inicio_s"], 3), "motivo": f"fora dos trechos da variante {alvo['id']}"})
        pos = max(pos, t["fim_s"])
    if dur - pos > 1e-9:
        cortes.append({"inicio_s": round(pos, 3), "fim_s": round(dur, 3), "motivo": f"fora dos trechos da variante {alvo['id']}"})
    if "--merge" in argv:
        with open(argv[argv.index("--merge") + 1], encoding="utf-8") as f:
            cortes += json.load(f)["cortes"]
        cortes = unir(cortes)
    saida = {"video": argv[3], "duracao_s": dur, "approved": bool(alvo["aprovada"]), "cortes": cortes}
    sys.stdout.buffer.write((json.dumps(saida, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
