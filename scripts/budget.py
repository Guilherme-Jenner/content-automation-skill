#!/usr/bin/env python3
"""Teto de gastos: registro de tudo que consome crédito (Katana, geração de clipes etc.).

Fluxo obrigatório: init (teto) -> quote (uma cotação por item) -> confirm (o usuário aprova o TOTAL)
-> spend (por item, até a cotação). Nada é gasto sem cotação confirmada, e o total comprometido
(gasto + confirmado ainda não gasto) nunca passa do teto.

Uso:
  budget.py init   <arquivo> <teto>
  budget.py quote  <arquivo> <item> <custo>
  budget.py status <arquivo>
  budget.py confirm <arquivo>          confirma todas as cotações pendentes de uma vez
  budget.py spend  <arquivo> <item> <custo>

Este módulo só controla o orçamento; quem chama é responsável por pedir a confirmação do usuário
antes de rodar `confirm` e por só gerar/gastar depois dele.
"""
import json
import os
import re
import sys
from decimal import Decimal, InvalidOperation

LIMITE_MAXIMO = Decimal("1000000")
ITEM_VALIDO = re.compile(r"^[A-Za-z0-9_-]{1,32}$")


class Recusa(Exception):
    pass


def numero(texto, nome, minimo_exclusivo=False):
    try:
        v = Decimal(texto)
    except (InvalidOperation, ValueError, TypeError):
        raise Recusa(f"{nome} inválido: '{texto}' não é um número")
    if v.is_nan() or v.is_infinite():
        raise Recusa(f"{nome} inválido: '{texto}' não é um número finito")
    if v < 0 or (minimo_exclusivo and v == 0):
        raise Recusa(f"{nome} inválido: deve ser {'maior que' if minimo_exclusivo else 'pelo menos'} zero")
    if v > LIMITE_MAXIMO:
        raise Recusa(f"{nome} inválido: máximo aceito é {LIMITE_MAXIMO}")
    return v


def fmt(d):
    return format(d.normalize(), "f") if d != 0 else "0"


def carregar(caminho):
    if not os.path.exists(caminho):
        raise Recusa(f"orçamento não encontrado: {caminho} (rode init antes)")
    with open(caminho, encoding="utf-8") as f:
        dados = json.load(f)
    dados["teto"] = Decimal(dados["teto"])
    for item in dados["itens"].values():
        item["cotado"] = Decimal(item["cotado"])
        item["gasto"] = None if item["gasto"] is None else Decimal(item["gasto"])
    return dados


def salvar(caminho, dados):
    saida = {
        "teto": fmt(dados["teto"]),
        "itens": {
            k: {"cotado": fmt(v["cotado"]), "confirmado": v["confirmado"], "gasto": None if v["gasto"] is None else fmt(v["gasto"])}
            for k, v in dados["itens"].items()
        },
    }
    tmp = caminho + ".tmp"
    with open(tmp, "wb") as f:
        f.write((json.dumps(saida, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    os.replace(tmp, caminho)


def gasto_total(dados):
    return sum((v["gasto"] for v in dados["itens"].values() if v["gasto"] is not None), Decimal(0))


def comprometido(dados):
    """Gasto + o que já foi confirmado e ainda não foi gasto."""
    total = Decimal(0)
    for v in dados["itens"].values():
        if v["gasto"] is not None:
            total += v["gasto"]
        elif v["confirmado"]:
            total += v["cotado"]
    return total


def pendente(dados):
    return sum((v["cotado"] for v in dados["itens"].values() if not v["confirmado"]), Decimal(0))


def item_valido(nome):
    if not ITEM_VALIDO.match(nome):
        raise Recusa(f"item inválido: '{nome}' (use letras, números, _ e -, até 32 caracteres)")


def cmd_init(a):
    caminho, teto_txt = a
    if os.path.exists(caminho):
        raise Recusa(f"o orçamento já existe: {caminho} (não é sobrescrito)")
    teto = numero(teto_txt, "teto", minimo_exclusivo=True)
    salvar(caminho, {"teto": teto, "itens": {}})
    print(f"orçamento criado: teto {fmt(teto)}")


def cmd_quote(a):
    caminho, item, custo_txt = a
    item_valido(item)
    custo = numero(custo_txt, "custo")
    d = carregar(caminho)
    if item in d["itens"] and (d["itens"][item]["confirmado"] or d["itens"][item]["gasto"] is not None):
        raise Recusa(f"o item '{item}' já tem cotação confirmada; não pode ser recotado")
    d["itens"][item] = {"cotado": custo, "confirmado": False, "gasto": None}
    salvar(caminho, d)
    print(f"cotação registrada: {item} = {fmt(custo)}")


def cmd_status(a):
    d = carregar(a[0])
    comp = comprometido(d)
    print(f"teto: {fmt(d['teto'])}")
    print(f"gasto: {fmt(gasto_total(d))}")
    print(f"comprometido: {fmt(comp)}")
    print(f"restante: {fmt(d['teto'] - comp)}")
    print(f"total cotado: {fmt(pendente(d))}")
    for nome, v in d["itens"].items():
        estado = "gasto" if v["gasto"] is not None else ("confirmado" if v["confirmado"] else "pendente")
        print(f"  {nome}: cotado {fmt(v['cotado'])} ({estado})")


def cmd_confirm(a):
    caminho = a[0]
    d = carregar(caminho)
    novos = pendente(d)
    if not any(not v["confirmado"] for v in d["itens"].values()):
        raise Recusa("não há cotações pendentes para confirmar")
    restante = d["teto"] - comprometido(d)
    if novos > restante:
        raise Recusa(f"o custo total cotado ({fmt(novos)}) excede o restante do teto ({fmt(restante)})")
    for v in d["itens"].values():
        v["confirmado"] = True
    salvar(caminho, d)
    print(f"confirmado: {fmt(novos)} (restante após reservar: {fmt(restante - novos)})")


def cmd_spend(a):
    caminho, item, custo_txt = a
    item_valido(item)
    custo = numero(custo_txt, "custo")
    d = carregar(caminho)
    if item not in d["itens"]:
        raise Recusa(f"o item '{item}' não tem cotação; cote antes de gastar")
    v = d["itens"][item]
    if v["gasto"] is not None:
        raise Recusa(f"o gasto do item '{item}' já foi registrado")
    if not v["confirmado"]:
        raise Recusa(f"a cotação do item '{item}' ainda não foi confirmada (rode confirm)")
    if custo > v["cotado"]:
        raise Recusa(f"o custo ({fmt(custo)}) é maior que a cotação ({fmt(v['cotado'])}) do item '{item}'")
    v["gasto"] = custo
    salvar(caminho, d)
    print(f"gasto registrado: {item} = {fmt(custo)}")


COMANDOS = {"init": (cmd_init, 2), "quote": (cmd_quote, 3), "status": (cmd_status, 1), "confirm": (cmd_confirm, 1), "spend": (cmd_spend, 3)}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMANDOS:
        print(__doc__, file=sys.stderr)
        return 2
    fn, n = COMANDOS[argv[1]]
    if len(argv) - 2 != n:
        print(f"uso incorreto de '{argv[1]}'; veja budget.py sem argumentos", file=sys.stderr)
        return 2
    try:
        fn(argv[2:])
    except Recusa as e:
        print(f"recusado: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
