#!/usr/bin/env python3
"""Monta o payload da ferramenta `createScheduledPost` do MCP do Metricool a partir de um post APROVADO.

O MCP é ferramenta do agente (um script não consegue chamá-lo): este script só prepara os argumentos, e o agente
faz a chamada com eles e mais nada. O contrato abaixo vem das definições das ferramentas lidas em 2026-10-17
(docs/agendadores.md) e NÃO foi verificado em execução: o agente deve conferir cada campo contra o esquema da
ferramenta carregada na sessão e parar se algo divergir.

Uso: metricool_payload.py snapshot <pasta-do-snapshot> --urls <media-urls.json> --blog-id <id> [--modo teste|real]
     metricool_payload.py plano <plano> <post-id> --urls <media-urls.json> --blog-id <id> [--modo teste|real]
     (`plano` só confere e mostra; o envio sempre parte do `snapshot` aprovado)

media-urls.json: {"<caminho da mídia como está no plano>": "https://link-publico-do-arquivo", ...}
  Uma entrada por arquivo do post (vídeo, ou cada imagem do carrossel). O Metricool só aceita URL pública
  (ou link do Google Drive/Dropbox vinculado à conta dele): subir o arquivo é uma ação do USUÁRIO.
--modo teste (padrão): autoPublish=false (o Metricool NÃO publica sozinho; avisa o celular) e TikTok SELF_ONLY.
--modo real: autoPublish=true e TikTok público. Só use depois de validar em modo teste e do "confirmo" do usuário.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

FUSO = "America/Sao_Paulo"
REDES = {"instagram", "tiktok"}


class Recusa(Exception):
    pass


def midias_do_post(post):
    return [post["video"]] if "video" in post else list(post["imagens"])


def urls_das_midias(post, urls):
    esperado = midias_do_post(post)
    faltam = [m for m in esperado if m not in urls]
    if faltam:
        raise Recusa("faltam URLs públicas em media-urls.json para: " + ", ".join(faltam))
    extras = [k for k in urls if k not in esperado]
    if extras:
        raise Recusa("media-urls.json tem entradas que não são deste post: " + ", ".join(extras))
    saida = []
    for m in esperado:
        u = urls[m]
        if not isinstance(u, str) or not re.fullmatch(r"https://[^\s]+", u):
            raise Recusa(f"a URL de '{m}' precisa ser um link https sem espaços (recebido: {u!r})")
        saida.append(u)
    if len(set(saida)) != len(saida):
        raise Recusa("duas mídias do post apontam para a mesma URL")
    return saida


def montar(post, urls, blog_id, modo):
    if modo not in ("teste", "real"):
        raise Recusa("modo deve ser teste ou real")
    if not re.fullmatch(r"[0-9]{1,18}", str(blog_id)):
        raise Recusa("blog-id (id da marca no Metricool) deve ser numérico")
    redes = sorted({p["rede"] for p in post["perfis"]})
    if not set(redes) <= REDES:
        raise Recusa("rede não suportada: " + ", ".join(sorted(set(redes) - REDES)))
    midia = urls_das_midias(post, urls)
    carrossel = "imagens" in post
    ia = bool(post.get("conteudo_ia", False))
    texto = post["legenda"] + ("\n\n" + " ".join(post["hashtags"]) if post["hashtags"] else "")
    data = post["data_hora"]
    info = {
        "providers": [{"network": r} for r in redes],
        "publicationDate": {"dateTime": data[:19], "timezone": FUSO},
        "text": texto,
        "media": midia,
    }
    avisos = ["Contrato não verificado em execução: conferir cada campo contra o esquema vivo da ferramenta antes de chamar."]
    if "instagram" in redes:
        info["instagramData"] = {"type": "POST" if carrossel else "REEL", "isAiGenerated": ia}
    if "tiktok" in redes:
        info["tiktokData"] = {"privacyOption": "SELF_ONLY" if modo == "teste" else "PUBLIC_TO_EVERYONE", "isAigc": ia}
        if carrossel:
            avisos.append("TikTok em Modo Foto (carrossel de imagens) via Metricool NÃO foi verificado: validar com a conta de teste (SELF_ONLY) antes de contar com isso.")
    if modo == "teste":
        avisos.append("MODO TESTE: autoPublish=false (o Metricool não publica sozinho) e TikTok SELF_ONLY.")
    return {
        "ferramenta": "createScheduledPost",
        "argumentos": {
            "blogId": int(blog_id),
            "date": data,
            "autoPublish": modo == "real",
            "info": json.dumps(info, ensure_ascii=False),
        },
        "resumo": {"post": post["id"], "redes": redes, "data_hora": data, "midia": midia, "conteudo_ia": ia,
                   "modo": modo, "contas_no_plano": post["perfis"]},
        "avisos": avisos + ["A conta publicada é a que a MARCA (blogId) tem conectada em cada rede; 'conta' do plano é só conferência."],
    }


def ler_urls(caminho):
    try:
        with open(caminho, encoding="utf-8") as f:
            urls = json.load(f)
    except (OSError, ValueError):
        raise Recusa(f"não foi possível ler {caminho} (esperado: JSON {{caminho da mídia: URL pública}})")
    if not isinstance(urls, dict):
        raise Recusa("media-urls.json deve ser um objeto {caminho: URL}")
    return urls


def main(argv):
    args = argv[1:]
    opcoes = {"--urls": None, "--blog-id": None, "--modo": "teste"}
    pos, i = [], 0
    while i < len(args):
        if args[i] in opcoes:
            if i + 1 >= len(args):
                print(f"{args[i]} exige um valor", file=sys.stderr)
                return 2
            opcoes[args[i]] = args[i + 1]
            i += 2
        else:
            pos.append(args[i])
            i += 1
    if not pos or pos[0] not in ("snapshot", "plano") or opcoes["--urls"] is None or opcoes["--blog-id"] is None \
            or len(pos) != (2 if pos[0] == "snapshot" else 3):
        print(__doc__, file=sys.stderr)
        return 2
    try:
        if pos[0] == "snapshot":
            with open(os.path.join(pos[1], "post.json"), encoding="utf-8") as f:
                post = json.load(f)
        else:
            from approval import achar_post
            post = achar_post(pos[1], pos[2])
        saida = montar(post, ler_urls(opcoes["--urls"]), opcoes["--blog-id"], opcoes["--modo"])
    except (Recusa, OSError, KeyError, ValueError) as e:
        print(f"recusado: {e}", file=sys.stderr)
        return 1
    except Exception as e:   # approval.Recusa
        print(f"recusado: {e}", file=sys.stderr)
        return 1
    sys.stdout.buffer.write((json.dumps(saida, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
