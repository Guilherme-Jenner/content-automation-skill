#!/usr/bin/env python3
"""Valida um schedule-plan.json (posts a agendar em Instagram/TikTok).

Erros (exit 1): schema; ids inseguros ou repetidos (maiúsculas contam como iguais); vídeo inexistente;
data_hora fora do formato AAAA-MM-DDTHH:MM:SS-03:00, a menos de 15 minutos de agora ou a mais de 30 dias;
perfis vazios ou duplicados; hashtags inválidas; legenda acima do limite.

Uso: validate_schedule.py <schedule-plan.json> [--post <id>] [--now <ISO com fuso>]   (--now: só em testes)
Também importável: erros_do_plano(caminho, now) -> lista de mensagens.
"""
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_json import validar  # noqa: E402

SCHEMA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "schemas", "schedule-plan.schema.json")
ID_VALIDO = re.compile(r"^[A-Za-z0-9_-]{1,32}$")
DATA_HORA = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}-03:00$")
# America/Sao_Paulo sem horário de verão desde 2019 = offset fixo -03:00 (revisar se o horário de verão voltar).
MARGEM_MINIMA = timedelta(minutes=15)
ANTECEDENCIA_MAXIMA = timedelta(days=30)
# Limite de legenda: CONFERIR na documentação de cada rede antes de confiar (valor conservador).
LIMITE_LEGENDA = 2200


def agora(argv):
    """Relógio. `--now` só existe para testes: em produção o prazo é sempre contra a hora real."""
    if "--now" in argv:
        if os.environ.get("CLO_ALLOW_TEST_NOW") != "1":
            sys.exit("recusado: --now só para testes (o prazo é sempre conferido contra a hora real)")
        i = argv.index("--now")
        if i + 1 >= len(argv):
            sys.exit("recusado: --now exige uma data ISO com fuso")
        try:
            dt = datetime.fromisoformat(argv[i + 1])
        except ValueError:
            sys.exit(f"recusado: --now inválido: {argv[i + 1]}")
        if dt.tzinfo is None:
            sys.exit("recusado: --now precisa de fuso (ex.: 2026-10-20T10:00:00-03:00)")
        return dt
    return datetime.now(timezone.utc)


def caminho_do_video(caminho_plano, video):
    base = os.path.dirname(os.path.abspath(caminho_plano))
    return video if os.path.isabs(video) else os.path.join(base, video)


def erros_do_plano(caminho, now, post_id=None):
    with open(SCHEMA, encoding="utf-8") as f:
        schema = json.load(f)
    with open(caminho, encoding="utf-8") as f:
        plano = json.load(f)
    erros = []
    validar(plano, schema, "", erros)
    if erros:
        return erros
    vistos = set()
    for i, p in enumerate(plano["posts"]):
        nome = f"posts[{i}]"
        if not ID_VALIDO.match(p["id"]):
            erros.append(f"{nome}.id inválido: use só letras, números, _ e - (até 32 caracteres)")
        if p["id"].lower() in vistos:
            erros.append("ids de posts repetidos (maiúsculas e minúsculas contam como iguais)")
        vistos.add(p["id"].lower())
        # A estrutura (ids, schema) vale para o plano inteiro; as regras de conteúdo e de prazo,
        # só para o post-alvo: um post vencido não pode bloquear os demais.
        if post_id is not None and p["id"] != post_id:
            continue
        if not os.path.isfile(caminho_do_video(caminho, p["video"])):
            erros.append(f"{nome}.video não encontrado: {p['video']}")
        if not DATA_HORA.match(p["data_hora"]):
            erros.append(f"{nome}.data_hora deve estar no formato AAAA-MM-DDTHH:MM:SS-03:00 (fuso America/Sao_Paulo)")
        else:
            try:
                dt = datetime.fromisoformat(p["data_hora"])
            except ValueError:
                erros.append(f"{nome}.data_hora não é uma data válida: {p['data_hora']}")
            else:
                if dt < now + MARGEM_MINIMA:
                    erros.append(f"{nome}.data_hora deve estar a pelo menos 15 minutos do momento atual")
                elif dt > now + ANTECEDENCIA_MAXIMA:
                    erros.append(f"{nome}.data_hora deve estar a no máximo 30 dias à frente")
        perfis = [(x["rede"], x["conta"].strip().lower()) for x in p["perfis"]]
        if len(set(perfis)) != len(perfis):
            erros.append(f"{nome}.perfis tem perfil duplicado")
        if any(not conta for _, conta in perfis):
            erros.append(f"{nome}.perfis tem conta vazia")
        for h in p["hashtags"]:
            if not re.match(r"^#\S+$", h):
                erros.append(f"{nome}.hashtag inválida: '{h}' (comece com # e não use espaços)")
        if len(p["legenda"]) > LIMITE_LEGENDA:
            erros.append(f"{nome}.legenda tem {len(p['legenda'])} caracteres (limite configurado: {LIMITE_LEGENDA}; conferir na rede)")
    return erros


def main(argv):
    post_id = argv[argv.index("--post") + 1] if "--post" in argv else None
    erros = erros_do_plano(argv[1], agora(argv), post_id)
    for e in erros:
        print(e, file=sys.stderr)
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
