#!/usr/bin/env python3
"""Consulta um gen-plan.json para os scripts bash (saída sempre com LF, também no Windows).

Uso:
  genplan_info.py <plano> list                 -> ids das cenas, uma por linha, na ordem do plano
  genplan_info.py <plano> get <id>             -> "<duracao_s> <resolucao> <sim|nao audio> <aspecto>"
  genplan_info.py <plano> key <id>             -> item de orçamento: clip-<id>-<hash8 de tudo que muda o custo/resultado>
"""
import hashlib
import json
import sys


def main(argv):
    with open(argv[1], encoding="utf-8") as f:
        plano = json.load(f)
    modo = argv[2]
    if modo == "list":
        linhas = [c["id"] for c in plano["cenas"]]
    elif modo in ("get", "key"):
        cena = next((c for c in plano["cenas"] if c["id"] == argv[3]), None)
        if cena is None:
            print(f"a cena '{argv[3]}' não existe no plano", file=sys.stderr)
            return 1
        if modo == "get":
            linhas = [f"{cena['duracao_s']} {plano['resolucao']} {'sim' if plano['audio'] else 'nao'} {plano['aspecto']}"]
        else:
            carga = json.dumps(
                {
                    "prompt": cena["prompt"],
                    "modelo": plano["modelo"],
                    "duracao_s": cena["duracao_s"],
                    "resolucao": plano["resolucao"],
                    "audio": plano["audio"],
                    "aspecto": plano["aspecto"],
                },
                sort_keys=True,
                ensure_ascii=False,
            )
            linhas = [f"clip-{cena['id']}-{hashlib.sha1(carga.encode('utf-8')).hexdigest()[:8]}"]
    else:
        print(f"modo desconhecido: {modo}", file=sys.stderr)
        return 2
    sys.stdout.buffer.write(("\n".join(linhas) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
