#!/usr/bin/env python3
"""Valida um gen-variants-plan.json (1 a 5 vídeos finais a partir dos MESMOS clipes já gerados).

Erros (exit 1): schema; quantidade fora de 1..5 ou diferente do número de variantes; ids inseguros ou repetidos
(caixa ignorada); cena que não existe no gen-plan ou repetida na mesma variante; legendas de cena que não está na
variante ou fora do schema de captions-plan; volume fora de -40..0; variantes idênticas; ganchos repetidos sem
justificativa; achados vazios. O gancho é a PRIMEIRA legenda da primeira cena que tem legenda, na ordem da variante.
A validação fina das legendas (tamanho, tempo) é feita na conversão (captions_to_transcript.py).

Uso: validate_gen_variants.py <gen-variants-plan.json> <gen-plan.json>
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_json import validar  # noqa: E402

AQUI = os.path.dirname(os.path.abspath(__file__))
SCHEMA = os.path.join(AQUI, "..", "schemas", "gen-variants-plan.schema.json")
SCHEMA_LEGENDAS = os.path.join(AQUI, "..", "schemas", "captions-plan.schema.json")
MAX_VARIANTES = 5
ID_VALIDO = re.compile(r"^[A-Za-z0-9_-]{1,32}$")


def gancho(variante):
    """Primeira legenda da primeira cena (na ordem da variante) que tem legenda, normalizada."""
    por_cena = {c["cena"]: c["legendas"] for c in variante["legendas"]["cenas"]}
    for cid in variante["cenas"]:
        if por_cena.get(cid):
            return " ".join(por_cena[cid][0]["texto"].lower().split())
    return None


def erros_das_variantes(plano, genplan):
    with open(SCHEMA, encoding="utf-8") as f:
        schema = json.load(f)
    with open(SCHEMA_LEGENDAS, encoding="utf-8") as f:
        schema_leg = json.load(f)
    erros = []
    validar(plano, schema, "", erros)
    if erros:
        return erros
    variantes = plano["variantes"]
    cenas_do_plano = {c["id"] for c in genplan["cenas"]}
    if not 1 <= plano["quantidade"] <= MAX_VARIANTES:
        erros.append(f"quantidade deve estar entre 1 e {MAX_VARIANTES} (recebido {plano['quantidade']})")
    if plano["quantidade"] != len(variantes):
        erros.append(f"quantidade ({plano['quantidade']}) não bate com o número de variantes ({len(variantes)})")
    vistos = set()
    for i, v in enumerate(variantes):
        nome = f"variantes[{i}]"
        if not ID_VALIDO.fullmatch(v["id"]):   # fullmatch: com match, "B\n" passaria ($ casa antes da quebra final)
            erros.append(f"{nome}.id inválido: use só letras, números, _ e - (até 32 caracteres)")
        if v["id"].lower() in vistos:
            erros.append("ids de variantes repetidos (maiúsculas e minúsculas contam como iguais)")
        vistos.add(v["id"].lower())
        if len(set(v["cenas"])) != len(v["cenas"]):
            erros.append(f"{nome}: cena repetida na mesma variante")
        for cid in v["cenas"]:
            if cid not in cenas_do_plano:
                erros.append(f"{nome}: a cena '{cid}' não existe no gen-plan")
        sub = []
        validar(v["legendas"], schema_leg, "", sub)
        erros.extend(f"{nome}.legendas: {e}" for e in sub)
        if not sub:
            for c in v["legendas"]["cenas"]:
                if c["cena"] not in v["cenas"]:
                    erros.append(f"{nome}: legendas para a cena '{c['cena']}', que não está nesta variante")
        if "volume_db" in v and not -40 <= v["volume_db"] <= 0:
            erros.append(f"{nome}: volume_db deve estar entre -40 e 0 (recebido {v['volume_db']})")
        if not v["achados"]:
            erros.append(f"{nome}: achados vazio (ligue a variante à pesquisa)")
    if not erros:
        assinaturas = {}
        for i, v in enumerate(variantes):
            ass = json.dumps([v["cenas"], v["legendas"], v.get("musica"), v.get("volume_db")], sort_keys=True, ensure_ascii=False)
            if ass in assinaturas:
                erros.append(f"variantes[{i}] é idêntica a variantes[{assinaturas[ass]}] (mesmas cenas, legendas e música)")
            assinaturas.setdefault(ass, i)
        ganchos = {}
        for i, v in enumerate(variantes):
            g = gancho(v)
            if g is None:
                continue
            if g in ganchos and not (v.get("gancho_repetido") and v.get("justificativa_gancho", "").strip()):
                erros.append(
                    f"variantes[{i}]: gancho repetido de variantes[{ganchos[g]}] sem gancho_repetido e justificativa_gancho"
                )
            ganchos.setdefault(g, i)
    return erros


def main(argv):
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        plano = json.load(f)
    with open(argv[2], encoding="utf-8") as f:
        genplan = json.load(f)
    erros = erros_das_variantes(plano, genplan)
    for e in erros:
        print(e, file=sys.stderr)
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
