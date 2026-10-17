#!/usr/bin/env python3
"""Converte um storyboard do modo gerado em gen-plan.json (imprime em stdout).

Uso: storyboard_to_genplan.py <storyboard.json> [--resolucao 480p|720p|1080p] [--audio]
- Só aceita storyboard com "modo": "gerado" e prompt em todas as cenas.
- Duração: arredondada PARA CIMA a inteiro e elevada a 4 s se menor; acima de 30 s é erro (divida a cena).
  Todo ajuste é avisado em stderr ("aviso: cena X ajustada de A para B s"): nunca silencioso.
- Resolução padrão 720p; áudio desligado por padrão (conferir o custo com get_cost antes de ligar).
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_genplan import DURACAO_MAX, DURACAO_MIN, ID_VALIDO  # noqa: E402


def g(v):
    return f"{v:g}"


def main(argv):
    args = argv[1:]
    resolucao, audio = "720p", False
    if "--audio" in args:
        audio = True
        args.remove("--audio")
    if "--resolucao" in args:
        i = args.index("--resolucao")
        if i + 1 >= len(args):
            print("erro: --resolucao exige um valor (480p, 720p ou 1080p)", file=sys.stderr)
            return 1
        resolucao = args[i + 1]
        del args[i : i + 2]
    if len(args) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    with open(args[0], encoding="utf-8") as f:
        sb = json.load(f)
    if sb.get("modo") != "gerado" or "cenas" not in sb:
        print("erro: o storyboard precisa ser do modo gerado (\"modo\": \"gerado\") e ter cenas", file=sys.stderr)
        return 1
    cenas, erros = [], []
    for c in sb["cenas"]:
        cid = c.get("id", "")
        if not ID_VALIDO.match(str(cid)):
            erros.append(f"cena com id inválido: '{cid}' (use só letras, números, _ e -)")
            continue
        prompt = (c.get("prompt") or "").strip()
        if not prompt:
            erros.append(f"cena {cid} sem prompt: peça o prompt visual dessa cena")
            continue
        original = c["duracao_s"]
        dur = max(DURACAO_MIN, math.ceil(original))
        if dur > DURACAO_MAX:
            erros.append(f"cena {cid} dura {g(original)} s; o máximo é {DURACAO_MAX} s: divida a cena")
            continue
        if dur != original:
            print(f"aviso: cena {cid} ajustada de {g(original)} para {dur} s (o modelo aceita {DURACAO_MIN} a {DURACAO_MAX} s inteiros)", file=sys.stderr)
        cenas.append({"id": cid, "prompt": prompt, "duracao_s": dur})
    if erros:
        for e in erros:
            print(f"erro: {e}", file=sys.stderr)
        return 1
    plano = {"modelo": "seedance_2_5", "aspecto": "9:16", "resolucao": resolucao, "audio": audio, "cenas": cenas}
    sys.stdout.buffer.write((json.dumps(plano, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
