#!/usr/bin/env python3
"""Consulta um gen-variants-plan.json para os scripts bash (saída com LF, também no Windows).

Uso:
  gen_variant_info.py <plano> list                       -> "<id> sim|nao" (aprovada), uma linha por variante
  gen_variant_info.py <plano> genplan <gen-plan> <id>    -> gen-plan derivado (só as cenas da variante, na ordem dela)
  gen_variant_info.py <plano> captions <id>              -> captions-plan da variante
  gen_variant_info.py <plano> music <id>                 -> caminho absoluto da música ou "-" (sem música);
                                                            caminho relativo é relativo à pasta do plano
  gen_variant_info.py <plano> volume <id>                -> volume_db declarado ou "-" (vale o padrão do add-soundtrack.sh)
"""
import json
import os
import sys


def saida(texto):
    sys.stdout.buffer.write((texto + "\n").encode("utf-8"))


def main(argv):
    with open(argv[1], encoding="utf-8") as f:
        plano = json.load(f)
    modo = argv[2]
    if modo == "list":
        saida("\n".join(f"{v['id']} {'sim' if v['aprovada'] else 'nao'}" for v in plano["variantes"]))
        return 0
    if modo == "genplan":
        with open(argv[3], encoding="utf-8") as f:
            genplan = json.load(f)
        v = next(v for v in plano["variantes"] if v["id"] == argv[4])
        por_id = {c["id"]: c for c in genplan["cenas"]}
        derivado = dict(genplan, cenas=[por_id[c] for c in v["cenas"]])
        saida(json.dumps(derivado, ensure_ascii=False, indent=2))
        return 0
    v = next(v for v in plano["variantes"] if v["id"] == argv[3])
    if modo == "captions":
        saida(json.dumps(v["legendas"], ensure_ascii=False, indent=2))
    elif modo == "music":
        if "musica" not in v:
            saida("-")
        else:
            caminho = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(argv[1])), v["musica"]))
            saida(caminho)
    elif modo == "volume":
        saida(f"{v['volume_db']:g}" if "volume_db" in v else "-")
    else:
        print(f"modo desconhecido: {modo}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
