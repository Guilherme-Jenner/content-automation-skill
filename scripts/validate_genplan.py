#!/usr/bin/env python3
"""Valida um gen-plan.json (cenas a gerar no Higgsfield).

Erros (exit 1): schema; 1 a 12 cenas; ids seguros e únicos (caixa ignorada); prompt não vazio (até 4000
caracteres); duração inteira de 4 a 30 s; modelo/resolução/aspecto conhecidos.
Limites de duração e de cenas: CONFERIR com `models_explore` (seedance_2_5: 4–30 s) e com o lote do Higgsfield (12).

Uso: validate_genplan.py <gen-plan.json>
Importável: erros_do_genplan(plano_dict) -> lista de mensagens.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_json import validar  # noqa: E402

SCHEMA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "schemas", "gen-plan.schema.json")
ID_VALIDO = re.compile(r"^[A-Za-z0-9_-]{1,32}$")
DURACAO_MIN, DURACAO_MAX = 4, 30
MAX_CENAS = 12
MAX_PROMPT = 4000


def erros_do_genplan(plano):
    with open(SCHEMA, encoding="utf-8") as f:
        schema = json.load(f)
    erros = []
    validar(plano, schema, "", erros)
    if erros:
        return erros
    cenas = plano["cenas"]
    if len(cenas) > MAX_CENAS:
        erros.append(f"o plano tem {len(cenas)} cenas; o máximo é {MAX_CENAS}")
    vistos = set()
    for i, c in enumerate(cenas):
        nome = f"cenas[{i}]"
        if not ID_VALIDO.match(c["id"]):
            erros.append(f"{nome}.id inválido: use só letras, números, _ e - (até 32 caracteres)")
        if c["id"].lower() in vistos:
            erros.append("ids de cenas repetidos (maiúsculas e minúsculas contam como iguais)")
        vistos.add(c["id"].lower())
        if not c["prompt"].strip():
            erros.append(f"{nome}.prompt vazio")
        elif len(c["prompt"]) > MAX_PROMPT:
            erros.append(f"{nome}.prompt tem {len(c['prompt'])} caracteres; o máximo é {MAX_PROMPT}")
        if not DURACAO_MIN <= c["duracao_s"] <= DURACAO_MAX:
            erros.append(f"{nome}.duracao_s deve estar entre {DURACAO_MIN} e {DURACAO_MAX} segundos (recebido {c['duracao_s']})")
    return erros


def main(argv):
    with open(argv[1], encoding="utf-8") as f:
        plano = json.load(f)
    erros = erros_do_genplan(plano)
    for e in erros:
        print(e, file=sys.stderr)
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
