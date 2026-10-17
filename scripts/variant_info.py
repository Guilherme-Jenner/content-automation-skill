#!/usr/bin/env python3
"""Consulta campos de um variants-plan.json para os scripts bash (saída com LF, mesmo no Windows).

Uso:
  variant_info.py <plano> editor              -> local|katana
  variant_info.py <plano> list                -> uma linha por variante: "<id> sim|nao" (aprovada)
  variant_info.py <plano> get <id>            -> "<min_silencio_s> <margem_s> <legenda_estilo>"
"""
import json
import sys


def main(argv):
    with open(argv[1], encoding="utf-8") as f:
        plano = json.load(f)
    modo = argv[2]
    if modo == "editor":
        linhas = [plano["editor"]]
    elif modo == "list":
        linhas = [f"{v['id']} {'sim' if v['aprovada'] else 'nao'}" for v in plano["variantes"]]
    elif modo == "get":
        v = next(v for v in plano["variantes"] if v["id"] == argv[3])
        linhas = [f"{v['ritmo']['min_silencio_s']} {v['ritmo']['margem_s']} {v['legenda_estilo']}"]
    else:
        print(f"modo desconhecido: {modo}", file=sys.stderr)
        return 2
    sys.stdout.buffer.write(("\n".join(linhas) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
