#!/usr/bin/env python3
"""Organiza as mídias dos posts APROVADOS numa pasta pronta para o Google Drive (sem API, sem credenciais).

Uso: stage_media.py <plano> --approvals <dir> [--destino <pasta>] [--prefixo clo] [--posts p1,p2]
  Copia o vídeo (ou cada imagem do carrossel) de cada post com aprovação válida para <destino> (padrão: <pasta do plano>/para-drive)
  com nome único e fácil de buscar: <prefixo>__<post>__<NN>__<hash8>.<ext>  (NN = ordem no carrossel; hash8 = início do sha256).
  Escreve <pasta do plano>/.drive-staging.json (o que foi preparado). Reexecutar não duplica; mídia alterada vira outro nome.
  Depois: leve o conteúdo de <destino> para o Drive (arraste no navegador, ou use como <destino> uma pasta do Google Drive para
  computador, que sincroniza sozinha) e rode `drive_links.py` com o resultado da busca do MCP do Drive.
"""
import json
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from approval import Recusa, achar_post, sha256_arquivo, verificar  # noqa: E402
from validate_schedule import midias_do_post  # noqa: E402

PREFIXO_VALIDO = re.compile(r"^[A-Za-z0-9-]{1,16}$")   # sem "_": o separador do nome é "__"
MANIFESTO = ".drive-staging.json"


def nome_staged(prefixo, post_id, indice, hash_, ext):
    return f"{prefixo}__{post_id}__{indice:02d}__{hash_[:8]}{ext.lower()}"


def salvar(caminho, dados):
    tmp = caminho + ".tmp"
    with open(tmp, "wb") as f:
        f.write((json.dumps(dados, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    os.replace(tmp, caminho)


def preparar(plano, aprovacoes, destino, prefixo, posts):
    base = os.path.dirname(os.path.abspath(plano))
    with open(plano, encoding="utf-8") as f:
        ids = [p["id"] for p in json.load(f)["posts"]]
    explicitos = posts is not None
    validos, pulados = [], []
    for pid in (posts if explicitos else ids):
        try:
            achar_post(plano, pid)
            verificar(plano, pid, aprovacoes)
            validos.append(pid)
        except Recusa as e:
            if explicitos:
                raise Recusa(f"o post '{pid}' não tem aprovação válida ({e}); nada foi preparado")
            pulados.append(pid)
    if not validos:
        raise Recusa("nenhum post com aprovação válida para preparar")
    os.makedirs(destino, exist_ok=True)
    manifesto = {"prefixo": prefixo, "destino": os.path.abspath(destino), "posts": {}}
    for pid in validos:
        post = achar_post(plano, pid)
        originais = [post["video"]] if "video" in post else post["imagens"]
        midias = {}
        for i, (rel, abs_) in enumerate(zip(originais, midias_do_post(plano, post)), 1):
            h = sha256_arquivo(abs_)
            nome = nome_staged(prefixo, pid, i, h, os.path.splitext(abs_)[1])
            alvo = os.path.join(destino, nome)
            if not (os.path.isfile(alvo) and sha256_arquivo(alvo) == h):
                shutil.copyfile(abs_, alvo)
            midias[rel] = {"nome": nome, "sha256": h}
        manifesto["posts"][pid] = {"midias": midias}
    salvar(os.path.join(base, MANIFESTO), manifesto)
    return validos, pulados, manifesto


def main(argv):
    args, op, pos, i = argv[1:], {}, [], 0
    while i < len(args):
        if args[i] in ("--approvals", "--destino", "--prefixo", "--posts"):
            if i + 1 >= len(args):
                print(f"{args[i]} exige um valor", file=sys.stderr)
                return 2
            op[args[i]] = args[i + 1]
            i += 2
        else:
            pos.append(args[i])
            i += 1
    if len(pos) != 1 or "--approvals" not in op:
        print(__doc__, file=sys.stderr)
        return 2
    prefixo = op.get("--prefixo", "clo")
    try:
        if not PREFIXO_VALIDO.fullmatch(prefixo):
            raise Recusa("prefixo inválido: use letras, números e - (até 16 caracteres; sem _)")
        destino = op.get("--destino") or os.path.join(os.path.dirname(os.path.abspath(pos[0])), "para-drive")
        posts = [p for p in op["--posts"].split(",") if p] if "--posts" in op else None
        validos, pulados, m = preparar(pos[0], op["--approvals"], destino, prefixo, posts)
    except Recusa as e:
        print(f"recusado: {e}", file=sys.stderr)
        return 1
    for p in pulados:
        print(f"pulado (sem aprovação válida): {p}")
    n = sum(len(v["midias"]) for v in m["posts"].values())
    print(f"preparados {n} arquivo(s) de {len(validos)} post(s) em: {m['destino']}")
    print(f"Próximo passo: leve o conteúdo dessa pasta para o Google Drive e busque por: title contains '{prefixo}__<post-id>__'")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
