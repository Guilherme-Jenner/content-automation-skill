#!/usr/bin/env python3
"""Confere um snapshot de agendamento: post.json, aprovado.json e o vídeo com o hash aprovado.

Uso: verify_snapshot.py <snapshot-dir>   (código 0 só se tudo bate)
"""
import glob
import hashlib
import json
import os
import sys


def sha256(caminho):
    h = hashlib.sha256()
    with open(caminho, "rb") as f:
        for bloco in iter(lambda: f.read(1024 * 1024), b""):
            h.update(bloco)
    return h.hexdigest()


def main(argv):
    pasta = argv[1]
    try:
        with open(os.path.join(pasta, "aprovado.json"), encoding="utf-8") as f:
            aprovado = json.load(f)
        with open(os.path.join(pasta, "post.json"), encoding="utf-8") as f:
            json.load(f)
        videos = glob.glob(os.path.join(glob.escape(pasta), "video.*"))
        imagens = sorted(glob.glob(os.path.join(glob.escape(pasta), "imagem-*")))
        if len(videos) == 1 and not imagens:
            return 0 if sha256(videos[0]) == aprovado["sha256_video"] else 1
        if videos or len(imagens) < 2:
            return 1
        hashes = [sha256(i) for i in imagens]   # imagem-01, imagem-02...: a ordem do nome é a ordem aprovada
        return 0 if hashlib.sha256("\n".join(hashes).encode("utf-8")).hexdigest() == aprovado["sha256_video"] else 1
    except (OSError, ValueError, KeyError):
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
