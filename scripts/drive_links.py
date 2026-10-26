#!/usr/bin/env python3
"""Gera os `urls-<post>.json` (links do Google Drive) a partir do resultado da busca do MCP do Drive.

Uso: drive_links.py <plano> --found <found.json> [--posts p1,p2] [--link view|download]
  found.json: a lista de arquivos achados com `search_files` do MCP do Drive, copiada como veio:
              [{"id": "...", "name": "clo__p2__01__ab12cd34.png"}, ...]  (aceita também {"files": [...]})
  Confere, para cada mídia preparada por `stage_media.py`, que existe EXATAMENTE um arquivo com o nome esperado (o nome leva o
  início do hash do conteúdo: arquivo trocado = nome diferente). Faltando (ainda sincronizando?) ou duplicado: recusa, sem
  gerar nada para aquele post. Escreve <pasta do plano>/urls-<post-id>.json ({caminho da mídia no plano: link}).
  Os links não são públicos: o Metricool só os lê se o Google Drive estiver vinculado na conta dele.
"""
import json
import os
import re
import sys

MANIFESTO = ".drive-staging.json"
ID_DRIVE = re.compile(r"^[A-Za-z0-9_-]{10,}$")


class Recusa(Exception):
    pass


def link(id_, formato):
    if formato == "download":
        return f"https://drive.google.com/uc?export=download&id={id_}"
    return f"https://drive.google.com/file/d/{id_}/view"


def ler_achados(caminho):
    try:
        with open(caminho, encoding="utf-8") as f:
            dados = json.load(f)
    except (OSError, ValueError):
        raise Recusa(f"não foi possível ler {caminho} (esperado: lista de {{id, name}} da busca do Drive)")
    lista = dados.get("files", dados.get("arquivos")) if isinstance(dados, dict) else dados
    if not isinstance(lista, list):
        raise Recusa("found.json deve ser uma lista de arquivos (ou {\"files\": [...]})")
    achados = {}
    for item in lista:
        if not isinstance(item, dict):
            continue
        nome = item.get("name") or item.get("title")
        id_ = item.get("id")
        if isinstance(nome, str) and isinstance(id_, str):
            achados.setdefault(nome, []).append(id_)
    return achados


def gerar(plano, found, posts, formato):
    base = os.path.dirname(os.path.abspath(plano))
    try:
        with open(os.path.join(base, MANIFESTO), encoding="utf-8") as f:
            manifesto = json.load(f)
    except (OSError, ValueError):
        raise Recusa("não há .drive-staging.json ao lado do plano: rode stage_media.py primeiro")
    achados = ler_achados(found)
    alvo = posts if posts is not None else list(manifesto["posts"])
    saidas, problemas = {}, []
    for pid in alvo:
        if pid not in manifesto["posts"]:
            problemas.append(f"{pid}: não foi preparado por stage_media.py")
            continue
        urls, erros = {}, []
        for rel, m in manifesto["posts"][pid]["midias"].items():
            ids = achados.get(m["nome"], [])
            if len(ids) == 0:
                erros.append(f"{pid}: '{m['nome']}' não apareceu na busca (o arquivo já chegou ao Drive? a sincronização terminou?)")
            elif len(set(ids)) > 1:
                erros.append(f"{pid}: '{m['nome']}' aparece {len(set(ids))} vezes no Drive; apague as cópias extras e busque de novo")
            elif not ID_DRIVE.fullmatch(ids[0]):
                erros.append(f"{pid}: id de arquivo inválido para '{m['nome']}'")
            else:
                urls[rel] = link(ids[0], formato)
        if erros:
            problemas.extend(erros)
        else:
            saidas[pid] = urls
    for pid, urls in saidas.items():
        caminho = os.path.join(base, f"urls-{pid}.json")
        tmp = caminho + ".tmp"
        with open(tmp, "wb") as f:
            f.write((json.dumps(urls, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
        os.replace(tmp, caminho)
        print(f"links: {caminho}")
    return saidas, problemas


def main(argv):
    args, op, pos, i = argv[1:], {}, [], 0
    while i < len(args):
        if args[i] in ("--found", "--posts", "--link"):
            if i + 1 >= len(args):
                print(f"{args[i]} exige um valor", file=sys.stderr)
                return 2
            op[args[i]] = args[i + 1]
            i += 2
        else:
            pos.append(args[i])
            i += 1
    if len(pos) != 1 or "--found" not in op:
        print(__doc__, file=sys.stderr)
        return 2
    formato = op.get("--link", "view")
    try:
        if formato not in ("view", "download"):
            raise Recusa("--link deve ser view ou download")
        posts = [p for p in op["--posts"].split(",") if p] if "--posts" in op else None
        saidas, problemas = gerar(pos[0], op["--found"], posts, formato)
    except Recusa as e:
        print(f"recusado: {e}", file=sys.stderr)
        return 1
    for p in problemas:
        print(f"pendente: {p}", file=sys.stderr)
    return 1 if problemas else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
