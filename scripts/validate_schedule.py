#!/usr/bin/env python3
"""Valida um schedule-plan.json (posts a agendar em Instagram/TikTok).

Erros (exit 1): schema; ids inseguros ou repetidos (maiúsculas contam como iguais); vídeo inexistente;
data_hora fora do formato AAAA-MM-DDTHH:MM:SS-03:00, a menos de 15 minutos de agora ou a mais de 30 dias;
perfis vazios ou duplicados; hashtags inválidas; legenda acima do limite.

Uso: validate_schedule.py <schedule-plan.json> [--now <ISO com fuso>]
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
    if "--now" in argv:
        return datetime.fromisoformat(argv[argv.index("--now") + 1])
    return datetime.now(timezone.utc)


def main(argv):
    with open(SCHEMA, encoding="utf-8") as f:
        schema = json.load(f)
    caminho = argv[1]
    with open(caminho, encoding="utf-8") as f:
        plano = json.load(f)
    base = os.path.dirname(os.path.abspath(caminho))
    now = agora(argv)
    erros = []
    validar(plano, schema, "", erros)
    if not erros:
        vistos = set()
        for i, p in enumerate(plano["posts"]):
            nome = f"posts[{i}]"
            if not ID_VALIDO.match(p["id"]):
                erros.append(f"{nome}.id inválido: use só letras, números, _ e - (até 32 caracteres)")
            if p["id"].lower() in vistos:
                erros.append("ids de posts repetidos (maiúsculas e minúsculas contam como iguais)")
            vistos.add(p["id"].lower())
            video = p["video"] if os.path.isabs(p["video"]) else os.path.join(base, p["video"])
            if not os.path.isfile(video):
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
    for e in erros:
        print(e, file=sys.stderr)
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
