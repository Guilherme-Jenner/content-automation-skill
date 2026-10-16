#!/usr/bin/env python3
"""Confere se uma pesquisa (research.json) está embasada em fontes.

Regras: valida no schema; ao menos 3 achados e ao menos 1 fato; todo fato tem fonte_url
http(s), fonte_titulo e data_acesso; todo achado tem aplicacao. Hipóteses podem não ter fonte.

Uso: check_research.py <research.json>
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_json import validar  # noqa: E402

SCHEMA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "schemas", "research.schema.json")


def main(argv):
    with open(SCHEMA, encoding="utf-8") as f:
        schema = json.load(f)
    with open(argv[1], encoding="utf-8") as f:
        dados = json.load(f)
    erros = []
    validar(dados, schema, "", erros)
    if not erros:
        achados = dados["achados"]
        if len(achados) < 3:
            erros.append("a pesquisa precisa ter ao menos 3 achados")
        if not any(a["tipo"] == "fato" for a in achados):
            erros.append("a pesquisa precisa ter ao menos 1 fato com fonte")
        for i, a in enumerate(achados):
            if not a["aplicacao"].strip():
                erros.append(f"achados[{i}]: aplicacao vazia")
            if a["tipo"] == "fato":
                url = a.get("fonte_url", "")
                if not url.startswith(("http://", "https://")):
                    erros.append(f"achados[{i}]: fato sem fonte_url http(s) válida")
                if not a.get("fonte_titulo", "").strip():
                    erros.append(f"achados[{i}]: fato sem fonte_titulo")
                if not a.get("data_acesso", "").strip():
                    erros.append(f"achados[{i}]: fato sem data_acesso")
    for e in erros:
        print(e, file=sys.stderr)
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
