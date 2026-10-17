#!/usr/bin/env python3
"""Propõe datas/horários de postagem a partir de uma cadência.

Uso: propose_slots.py <cadencia.json> <n> [--now <ISO com fuso>]
Cadência: {"dias": ["seg","qua","sex"], "horarios": ["12:00","19:00"], "minimo_entre_posts_h": 6}
Imprime n datas AAAA-MM-DDTHH:MM:SS-03:00, crescentes, dentro da janela aceita por validate_schedule.py
(de 15 minutos a 30 dias à frente) e respeitando o espaçamento mínimo.
"""
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_schedule import ANTECEDENCIA_MAXIMA, MARGEM_MINIMA, agora  # noqa: E402

FUSO = timezone(timedelta(hours=-3))  # America/Sao_Paulo (sem horário de verão desde 2019)
DIAS = {"seg": 0, "ter": 1, "qua": 2, "qui": 3, "sex": 4, "sab": 5, "dom": 6}
MAXIMO_POSTS = 100


class Recusa(Exception):
    pass


def ler_cadencia(caminho):
    try:
        with open(caminho, encoding="utf-8") as f:
            c = json.load(f)
    except (OSError, json.JSONDecodeError):
        raise Recusa(f"cadência ilegível ou não é JSON: {caminho}")
    if not isinstance(c, dict):
        raise Recusa("a cadência deve ser um objeto JSON")
    dias, horarios, minimo = c.get("dias"), c.get("horarios"), c.get("minimo_entre_posts_h")
    if not isinstance(dias, list) or not dias or any(d not in DIAS for d in dias):
        raise Recusa("dias deve ser uma lista não vazia com: " + ", ".join(DIAS))
    if not isinstance(horarios, list) or not horarios or any(
        not isinstance(h, str) or not re.fullmatch(r"([01]\d|2[0-3]):[0-5]\d", h) for h in horarios
    ):
        raise Recusa("horarios deve ser uma lista não vazia de HH:MM (00:00 a 23:59)")
    if isinstance(minimo, bool) or not isinstance(minimo, (int, float)) or minimo < 0:
        raise Recusa("minimo_entre_posts_h deve ser um número maior ou igual a zero")
    return {DIAS[d] for d in dias}, sorted(horarios), timedelta(hours=minimo)


def propor(dias, horarios, espacamento, quantidade, now):
    now = now.astimezone(FUSO)
    inicio, fim = now + MARGEM_MINIMA, now + ANTECEDENCIA_MAXIMA
    escolhidos = []
    for delta in range(0, 32):
        dia = (now + timedelta(days=delta)).date()
        if dia.weekday() not in dias:
            continue
        for h in horarios:
            hh, mm = map(int, h.split(":"))
            dt = datetime(dia.year, dia.month, dia.day, hh, mm, tzinfo=FUSO)
            if dt < inicio or dt > fim:
                continue
            if escolhidos and dt - escolhidos[-1] < espacamento:
                continue
            escolhidos.append(dt)
            if len(escolhidos) == quantidade:
                return escolhidos
    raise Recusa(f"só há {len(escolhidos)} horário(s) dentro de 30 dias com essa cadência; pediram {quantidade}")


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        if not re.fullmatch(r"[0-9]+", argv[2]) or not 1 <= int(argv[2]) <= MAXIMO_POSTS:
            raise Recusa(f"a quantidade deve ser um inteiro de 1 a {MAXIMO_POSTS}")
        dias, horarios, espacamento = ler_cadencia(argv[1])
        slots = propor(dias, horarios, espacamento, int(argv[2]), agora(argv))
    except Recusa as e:
        print(f"recusado: {e}", file=sys.stderr)
        return 1
    sys.stdout.buffer.write(("\n".join(s.isoformat() for s in slots) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
