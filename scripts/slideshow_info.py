#!/usr/bin/env python3
"""Informações de um slideshow-plan.json já validado, para o make-slideshow.sh.

Uso: slideshow_info.py aprovadas <plano>                 -> um id de variante aprovada por linha
     slideshow_info.py estilo <plano>                    -> estilo do plano (padrao por omissão)
     slideshow_info.py slides <plano> <id>               -> TSV: caminho absoluto da foto, duração, papel
     slideshow_info.py transcript <plano> <id>           -> transcript.json (tempos absolutos, um segmento por slide)
     slideshow_info.py musica <plano> <id>               -> "<caminho absoluto>\t<volume_db ou vazio>" (vazio sem música)
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_slideshow import duracao_do_slide  # noqa: E402


def abs_do_plano(base, caminho):
    return caminho if os.path.isabs(caminho) or (len(caminho) > 2 and caminho[1] == ":") else os.path.join(base, caminho)


def main(argv):
    if len(argv) < 3 or argv[1] not in ("aprovadas", "estilo", "slides", "transcript", "musica"):
        print(__doc__, file=sys.stderr)
        return 2
    with open(argv[2], encoding="utf-8") as f:
        plano = json.load(f)
    base = os.path.dirname(os.path.abspath(argv[2]))
    cmd = argv[1]
    if cmd == "aprovadas":
        for v in plano["variantes"]:
            if v["aprovada"] is True:
                print(v["id"])
        return 0
    if cmd == "estilo":
        print(plano.get("estilo", "padrao"))
        return 0
    if len(argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    v = next((x for x in plano["variantes"] if x["id"] == argv[3]), None)
    if v is None:
        print(f"variante '{argv[3]}' não existe no plano", file=sys.stderr)
        return 1
    fotos = {f["id"]: f for f in plano["fotos"]}
    if cmd == "slides":
        for s in v["slides"]:
            print(f"{abs_do_plano(base, fotos[s['foto']]['arquivo'])}\t{duracao_do_slide(s):g}\t{s['papel']}")
    elif cmd == "transcript":
        t, segmentos = 0.0, []
        for s in v["slides"]:
            d = duracao_do_slide(s)
            segmentos.append({"inicio_s": round(t, 3), "fim_s": round(t + d, 3), "texto": " ".join(s["texto"].split())})
            t += d
        sys.stdout.buffer.write((json.dumps({"idioma": "pt", "segmentos": segmentos}, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    else:
        if "musica" in v:
            vol = f"{v['volume_db']:g}" if "volume_db" in v else ""
            print(f"{abs_do_plano(base, v['musica'])}\t{vol}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
