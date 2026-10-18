#!/usr/bin/env python3
"""Converte um captions-plan.json (legendas por cena) em transcript.json com tempos ABSOLUTOS.

Uso: captions_to_transcript.py <captions-plan.json> <gen-plan.json> <clips-manifest.json> [--estilo]
- Os tempos de cada legenda são relativos ao início da cena (padrão: início 0,2 s, fim = duração − 0,2 s).
- O início de cada cena é a soma das durações REAIS (ffprobe) dos clipes anteriores, na ordem do plano.
- `--estilo` imprime só o estilo do plano (padrao, destaque ou discreto).
Recusa: cena que não existe no gen-plan ou no manifesto; texto vazio ou acima do limite do estilo (3 linhas na tela: ver caption_styles.py); fim <= início;
duração < 0,8 s; tempos fora da cena; legendas sobrepostas na mesma cena; mais de 40 legendas.
"""
import json
import math
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from caption_styles import cabe, maximo  # noqa: E402
from validate_json import validar  # noqa: E402

SCHEMA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "schemas", "captions-plan.schema.json")
MAX_LEGENDAS = 40
DURACAO_MINIMA = 0.8
MARGEM_PADRAO = 0.2


def duracao_real(caminho):
    try:
        r = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", caminho],
            capture_output=True, text=True, check=True, stdin=subprocess.DEVNULL,
        )
        return float(r.stdout.strip())
    except (OSError, subprocess.CalledProcessError, ValueError):
        return None


def main(argv):
    args = argv[1:]
    so_estilo = "--estilo" in args
    if so_estilo:
        args.remove("--estilo")
    if len(args) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    with open(SCHEMA, encoding="utf-8") as f:
        schema = json.load(f)
    with open(args[0], encoding="utf-8") as f:
        caps = json.load(f)
    erros = []
    validar(caps, schema, "", erros)
    if erros:
        for e in erros:
            print(e, file=sys.stderr)
        return 1
    for item in caps["cenas"]:
        for k, leg in enumerate(item["legendas"]):
            for campo in ("inicio_s", "fim_s"):
                if campo in leg and not math.isfinite(leg[campo]):
                    erros.append(f"cena {item['cena']}, legenda {k + 1}: {campo} precisa ser um número finito")
    if erros:
        for e in erros:
            print(e, file=sys.stderr)
        return 1
    if so_estilo:
        print(caps["estilo"])
        return 0
    with open(args[1], encoding="utf-8") as f:
        plano = json.load(f)
    with open(args[2], encoding="utf-8") as f:
        manifesto = json.load(f)
    base = os.path.dirname(os.path.abspath(args[2]))

    # início e duração reais de cada cena, na ordem do plano
    inicio, duracao, t = {}, {}, 0.0
    for cena in plano["cenas"]:
        c = manifesto.get("clips", {}).get(cena["id"])
        if c is None:
            erros.append(f"a cena '{cena['id']}' não está no manifesto: gere ou registre o clipe antes de legendar")
            continue
        d = duracao_real(os.path.join(base, c["arquivo"]))
        if d is None:
            erros.append(f"não foi possível ler a duração do clipe da cena '{cena['id']}'")
            continue
        inicio[cena["id"]], duracao[cena["id"]] = t, d
        t += d
    if erros:
        for e in erros:
            print(e, file=sys.stderr)
        return 1

    total = sum(len(c["legendas"]) for c in caps["cenas"])
    if total > MAX_LEGENDAS:
        print(f"o plano tem {total} legendas; o máximo é {MAX_LEGENDAS}", file=sys.stderr)
        return 1

    segmentos, por_cena = [], {}
    for item in caps["cenas"]:
        cid = item["cena"]
        if cid not in duracao:
            erros.append(f"a cena '{cid}' não existe no gen-plan")
            continue
        for k, leg in enumerate(item["legendas"]):
            nome = f"cena {cid}, legenda {k + 1}"
            texto = leg["texto"].strip()
            ini = leg.get("inicio_s", MARGEM_PADRAO)
            fim = leg.get("fim_s", duracao[cid] - MARGEM_PADRAO)
            if not texto:
                erros.append(f"{nome}: texto vazio")
            elif not cabe(texto, caps["estilo"]):
                erros.append(
                    f"{nome}: o texto ({len(texto)} caracteres) não cabe em 3 linhas no estilo '{caps['estilo']}' "
                    f"(cerca de {maximo(caps['estilo'])} caracteres, conforme o tamanho das palavras); encurte a legenda"
                )
            if fim <= ini:
                erros.append(f"{nome}: fim_s ({fim:g}) deve ser maior que inicio_s ({ini:g})")
                continue
            if fim - ini < DURACAO_MINIMA:
                erros.append(f"{nome}: duração mínima de 0,8 s (tem {fim - ini:.2f} s)")
            if ini < 0 or fim > duracao[cid] + 0.01:
                erros.append(f"{nome}: fora da cena (a cena dura {duracao[cid]:.2f} s)")
            por_cena.setdefault(cid, []).append((ini, fim, nome))
            segmentos.append({"inicio_s": round(inicio[cid] + ini, 3), "fim_s": round(inicio[cid] + fim, 3), "texto": texto})
    for cid, itens in por_cena.items():
        itens.sort()
        for (_, f1, n1), (i2, _, n2) in zip(itens, itens[1:]):
            if i2 < f1 - 1e-9:
                erros.append(f"{n2} sobrepõe {n1}")
    if erros:
        for e in erros:
            print(e, file=sys.stderr)
        return 1
    segmentos.sort(key=lambda s: s["inicio_s"])
    saida = {"idioma": "pt", "segmentos": segmentos}
    sys.stdout.buffer.write((json.dumps(saida, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
