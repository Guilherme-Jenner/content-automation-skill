#!/usr/bin/env python3
"""Consulta campos de um variants-plan.json para os scripts bash (saída com LF, mesmo no Windows).

Uso:
  variant_info.py <plano> editor              -> local|katana
  variant_info.py <plano> list                -> uma linha por variante: "<id> sim|nao" (aprovada)
  variant_info.py <plano> get <id>            -> "<min_silencio_s> <margem_s> <legenda_estilo>"
"""
import hashlib
import json
import os
import sys


def achar(plano, vid):
    for v in plano["variantes"]:
        if v["id"] == vid:
            return v
    print(f"a variante '{vid}' não existe no plano", file=sys.stderr)
    sys.exit(1)


def main(argv):
    with open(argv[1], encoding="utf-8") as f:
        plano = json.load(f)
    modo = argv[2]
    if modo == "editor":
        linhas = [plano["editor"]]
    elif modo == "list":
        linhas = [f"{v['id']} {'sim' if v['aprovada'] else 'nao'}" for v in plano["variantes"]]
    elif modo == "get":
        v = achar(plano, argv[3])
        linhas = [f"{v['ritmo']['min_silencio_s']} {v['ritmo']['margem_s']} {v['legenda_estilo']}"]
    elif modo == "key":
        # Identidade do item de orçamento: muda se o bruto, os trechos, o ritmo ou o estilo mudarem.
        v = achar(plano, argv[3])
        carga = json.dumps(
            {
                "bruto": os.path.normcase(os.path.normpath(os.path.abspath(plano["bruto"]))),
                "trechos": sorted([t["inicio_s"], t["fim_s"]] for t in v["trechos"]),
                "ritmo": v["ritmo"],
                "estilo": v["legenda_estilo"],
            },
            sort_keys=True,
        )
        linhas = [f"var-{v['id']}-{hashlib.sha1(carga.encode('utf-8')).hexdigest()[:8]}"]
    elif modo == "seconds":
        v = achar(plano, argv[3])
        linhas = [f"{sum(t['fim_s'] - t['inicio_s'] for t in v['trechos']):g}"]
    else:
        print(f"modo desconhecido: {modo}", file=sys.stderr)
        return 2
    sys.stdout.buffer.write(("\n".join(linhas) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
