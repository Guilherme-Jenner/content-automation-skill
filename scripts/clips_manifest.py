#!/usr/bin/env python3
"""Manifesto dos clipes gerados: liga cada cena ao arquivo, hash, custo, item de orçamento e origem.

  clips_manifest.py add  <manifesto> <id> <arquivo-relativo> <custo> <item> <origem> [job_id]
  clips_manifest.py show <manifesto>      -> ids dos clipes, um por linha, em ordem alfabética
  clips_manifest.py verify <manifesto> <gen-plan>   -> caminhos dos clipes NA ORDEM DO PLANO, um por linha;
                                          falha se faltar cena no manifesto, arquivo ou se o hash não bater

O arquivo é relativo à pasta do manifesto. O sha256 é calculado na hora do registro. Escrita atômica, com trava.
"""
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from budget import travar  # noqa: E402

ID_VALIDO = re.compile(r"^[A-Za-z0-9_-]{1,32}$")


def sha256(caminho):
    h = hashlib.sha256()
    with open(caminho, "rb") as f:
        for bloco in iter(lambda: f.read(1024 * 1024), b""):
            h.update(bloco)
    return h.hexdigest()


def carregar(manifesto):
    if not os.path.exists(manifesto):
        return {"clips": {}}
    with open(manifesto, encoding="utf-8") as f:
        dados = json.load(f)
    if not isinstance(dados.get("clips"), dict):
        raise ValueError("manifesto corrompido")
    return dados


def cmd_add(manifesto, cid, arquivo, custo, item, origem, job_id=None):
    if not ID_VALIDO.match(cid):
        print(f"id de cena inválido: '{cid}'", file=sys.stderr)
        return 1
    base = os.path.dirname(os.path.abspath(manifesto))
    caminho = os.path.normpath(os.path.join(base, arquivo))
    if not caminho.startswith(base + os.sep) or not os.path.isfile(caminho):
        print(f"arquivo não encontrado dentro da pasta do manifesto: {arquivo}", file=sys.stderr)
        return 1
    with travar(manifesto):
        dados = carregar(manifesto)
        dados["clips"][cid] = {
            "arquivo": arquivo.replace("\\", "/"),
            "sha256": sha256(caminho),
            "custo": custo,
            "item": item,
            "origem": origem,
            "job_id": job_id,
            "conteudo_ia": True,
            "registrado_em": datetime.now(timezone.utc).isoformat(),
        }
        fd, tmp = tempfile.mkstemp(dir=base, prefix=".clips-manifest-", suffix=".tmp")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write((json.dumps(dados, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, manifesto)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
    return 0


def cmd_show(manifesto):
    with travar(manifesto):
        dados = carregar(manifesto)
    sys.stdout.buffer.write(("\n".join(sorted(dados["clips"])) + "\n").encode("utf-8"))
    return 0


def cmd_verify(manifesto, plano_caminho):
    with open(plano_caminho, encoding="utf-8") as f:
        plano = json.load(f)
    base = os.path.dirname(os.path.abspath(manifesto))
    with travar(manifesto):
        dados = carregar(manifesto)
    caminhos = []
    for cena in plano["cenas"]:
        c = dados["clips"].get(cena["id"])
        if c is None:
            print(f"a cena '{cena['id']}' não está no manifesto: gere ou registre o clipe antes de montar", file=sys.stderr)
            return 1
        caminho = os.path.normpath(os.path.join(base, c["arquivo"]))
        if not os.path.isfile(caminho):
            print(f"o clipe da cena '{cena['id']}' não foi encontrado: {c['arquivo']}", file=sys.stderr)
            return 1
        if sha256(caminho) != c["sha256"]:
            print(f"o clipe da cena '{cena['id']}' mudou depois do registro (hash diferente do manifesto)", file=sys.stderr)
            return 1
        caminhos.append(caminho)
    sys.stdout.buffer.write(("\n".join(caminhos) + "\n").encode("utf-8"))
    return 0


def main(argv):
    if len(argv) < 3 or argv[1] not in ("add", "show", "verify"):
        print(__doc__, file=sys.stderr)
        return 2
    if argv[1] == "add" and 7 <= len(argv) - 0 <= 9:
        return cmd_add(*argv[2:])
    if argv[1] == "show" and len(argv) == 3:
        return cmd_show(argv[2])
    if argv[1] == "verify" and len(argv) == 4:
        return cmd_verify(argv[2], argv[3])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(argv=sys.argv))
