#!/usr/bin/env python3
"""Aprovação humana amarrada ao conteúdo exato de um post.

  approval.py approve <plano> <post-id> <dir-aprovacoes> [--force] [--now <ISO>]
  approval.py verify  <plano> <post-id> <dir-aprovacoes>

`approve` só deve ser rodado depois de o usuário dizer "aprovo" ao resumo do post. Grava
<dir>/<post-id>.approval.json com o sha256 do vídeo (ou das imagens do carrossel, na ordem) e do conteúdo (legenda, hashtags, perfis, data/hora).
`verify` NUNCA aprova nada: só confere se o arquivo existe e se tudo ainda bate (código 0).
"""
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_schedule import ID_VALIDO, agora, erros_do_plano, midias_do_post  # noqa: E402


class Recusa(Exception):
    pass


def sha256_arquivo(caminho):
    h = hashlib.sha256()
    with open(caminho, "rb") as f:
        for bloco in iter(lambda: f.read(1024 * 1024), b""):
            h.update(bloco)
    return h.hexdigest()


def sha256_midia(plano_caminho, post):
    """Hash da mídia aprovada: o do arquivo (vídeo) ou, no carrossel, o das imagens NA ORDEM (ordem importa)."""
    hashes = [sha256_arquivo(m) for m in midias_do_post(plano_caminho, post)]
    if "video" in post:
        return hashes[0]
    return hashlib.sha256("\n".join(hashes).encode("utf-8")).hexdigest()


def sha256_conteudo(post):
    campos = {
        "id": post["id"],
        "legenda": post["legenda"],
        "hashtags": post["hashtags"],
        "perfis": sorted([x["rede"], x["conta"]] for x in post["perfis"]),
        "data_hora": post["data_hora"],
    }
    if "conteudo_ia" in post:   # só entra no hash quando declarado: aprovações antigas continuam valendo
        campos["conteudo_ia"] = post["conteudo_ia"]
    canon = json.dumps(campos, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(canon.encode("utf-8")).hexdigest()


def achar_post(plano_caminho, post_id):
    if not ID_VALIDO.match(post_id):
        raise Recusa(f"id de post inválido: '{post_id}'")
    with open(plano_caminho, encoding="utf-8") as f:
        plano = json.load(f)
    for p in plano["posts"]:
        if p["id"] == post_id:
            return p
    raise Recusa(f"o post '{post_id}' não existe no plano")


def caminho_aprovacao(diretorio, post_id):
    return os.path.join(diretorio, f"{post_id}.approval.json")


def cmd_approve(args, now, force):
    plano_caminho, post_id, diretorio = args
    post = achar_post(plano_caminho, post_id)
    erros = erros_do_plano(plano_caminho, now, post_id)
    if erros:
        raise Recusa("o plano não está válido, nada foi aprovado:\n  " + "\n  ".join(erros))
    destino = caminho_aprovacao(diretorio, post_id)
    if os.path.exists(destino) and not force:
        raise Recusa(f"o post '{post_id}' já tem aprovação: {destino} (use --force para refazer)")
    os.makedirs(diretorio, exist_ok=True)
    registro = {
        "post_id": post_id,
        "sha256_video": sha256_midia(plano_caminho, post),   # nome mantido por compatibilidade: vale também para o carrossel
        "sha256_conteudo": sha256_conteudo(post),
        "data_hora": post["data_hora"],
        "perfis": post["perfis"],
        "aprovado_em": datetime.now(timezone.utc).isoformat(),
    }
    fd, tmp = tempfile.mkstemp(dir=diretorio, prefix=".approval-", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write((json.dumps(registro, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, destino)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    print(f"aprovado: {post_id} ({post['data_hora']})")


def verificar(plano_caminho, post_id, diretorio):
    """Confere a aprovação; devolve (post, registro) ou levanta Recusa. Nunca aprova nada."""
    post = achar_post(plano_caminho, post_id)
    arq = caminho_aprovacao(diretorio, post_id)
    if not os.path.isfile(arq):
        raise Recusa(f"o post '{post_id}' não tem aprovação em {arq}")
    try:
        with open(arq, encoding="utf-8") as f:
            reg = json.load(f)
    except (json.JSONDecodeError, UnicodeDecodeError):
        raise Recusa(f"o arquivo de aprovação está corrompido: {arq}")
    if reg.get("post_id") != post_id:
        raise Recusa(f"a aprovação em {arq} é de outro post ({reg.get('post_id')})")
    for m in midias_do_post(plano_caminho, post):
        if not os.path.isfile(m):
            raise Recusa(f"arquivo de mídia não encontrado: {m}")
    if sha256_midia(plano_caminho, post) != reg.get("sha256_video"):
        raise Recusa("o vídeo (ou as imagens, ou a ordem delas) mudou depois da aprovação; peça uma nova aprovação")
    if sha256_conteudo(post) != reg.get("sha256_conteudo"):
        raise Recusa("o conteúdo (legenda, hashtags, perfis ou data/hora) mudou depois da aprovação; peça uma nova aprovação")
    return post, reg


def cmd_verify(args):
    verificar(*args)
    print(f"aprovação válida: {args[1]}")


def main(argv):
    if len(argv) < 5 or argv[1] not in ("approve", "verify"):
        print(__doc__, file=sys.stderr)
        return 2
    comando, resto = argv[1], argv[2:]
    force = "--force" in resto
    now = agora(argv)
    limpo, i = [], 0
    while i < len(resto):
        if resto[i] == "--force":
            i += 1
        elif resto[i] == "--now":
            i += 2
        else:
            limpo.append(resto[i])
            i += 1
    if len(limpo) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        if comando == "approve":
            cmd_approve(limpo, now, force)
        else:
            cmd_verify(limpo)
    except Recusa as e:
        print(f"recusado: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
