#!/usr/bin/env python3
"""Teto de gastos: registro de tudo que consome crédito (Katana, geração de clipes etc.).

Fluxo obrigatório: init (teto) -> quote (uma cotação por item) -> confirm <total> (o usuário aprova o
TOTAL que viu) -> spend (por item). Nada é gasto sem cotação confirmada, e o total comprometido
(gasto + confirmado ainda não gasto) nunca passa do teto.

Uso:
  budget.py init    <arquivo> <teto>
  budget.py quote   <arquivo> <item> <custo>
  budget.py status  <arquivo>
  budget.py confirm <arquivo> <total>   confirma as cotações pendentes; <total> deve ser o total mostrado ao usuário
  budget.py spend   <arquivo> <item> <custo>   custo acima da cotação é REGISTRADO e sai com código 3 (estouro)
  budget.py check   <arquivo> <item> [custo_atual]   sai 0 só se o item está confirmado e não gasto (e custo_atual <= cotado)
  budget.py state   <arquivo> <item>    imprime: nenhum | pendente | confirmado | gasto

Todos os comandos usam uma trava de arquivo (<arquivo>.lock), então processos paralelos não perdem gastos.
Este módulo só controla o orçamento; quem chama pede a confirmação do usuário antes do confirm
e só gera/gasta depois dele.
"""
import contextlib
import json
import os
import re
import sys
import tempfile
import time
from decimal import Decimal, InvalidOperation

LIMITE_MAXIMO = Decimal("1000000")
MENOR_FRACAO = Decimal("0.0001")
ITEM_VALIDO = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
SAIDA_ESTOURO = 3


class Recusa(Exception):
    codigo = 1


class Estouro(Recusa):
    codigo = SAIDA_ESTOURO


def numero(texto, nome, minimo_exclusivo=False):
    try:
        v = Decimal(str(texto))
    except (InvalidOperation, ValueError, TypeError):
        raise Recusa(f"{nome} inválido: '{texto}' não é um número")
    if v.is_nan() or v.is_infinite():
        raise Recusa(f"{nome} inválido: '{texto}' não é um número finito")
    if v < 0 or (minimo_exclusivo and v == 0):
        raise Recusa(f"{nome} inválido: deve ser {'maior que' if minimo_exclusivo else 'pelo menos'} zero")
    if v > LIMITE_MAXIMO:
        raise Recusa(f"{nome} inválido: máximo aceito é {LIMITE_MAXIMO}")
    if v != 0 and v.adjusted() < -4:
        raise Recusa(f"{nome} inválido: precisão menor que {MENOR_FRACAO} não é aceita")
    return v


def fmt(d):
    return format(d.normalize(), "f") if d != 0 else "0"


@contextlib.contextmanager
def travar(caminho):
    """Trava exclusiva por todo o ciclo carregar -> salvar (flock no POSIX, msvcrt no Windows)."""
    fd = os.open(caminho + ".lock", os.O_CREAT | os.O_RDWR)
    try:
        if os.name == "nt":
            import msvcrt

            inicio = time.time()
            while True:
                try:
                    msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)
                    break
                except OSError:
                    if time.time() - inicio > 60:
                        raise Recusa("não foi possível obter a trava do orçamento (outro processo está usando)")
                    time.sleep(0.02)
        else:
            import fcntl

            fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            if os.name == "nt":
                import msvcrt

                os.lseek(fd, 0, 0)
                msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)
        except OSError:
            pass
        os.close(fd)


def corrompido(motivo):
    return Recusa(f"orçamento corrompido ({motivo}); não edite o arquivo à mão")


def carregar(caminho):
    if not os.path.exists(caminho):
        raise Recusa(f"orçamento não encontrado: {caminho} (rode init antes)")
    try:
        with open(caminho, encoding="utf-8") as f:
            dados = json.load(f)
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        raise corrompido(str(e))
    if not isinstance(dados, dict) or not isinstance(dados.get("itens"), dict) or "teto" not in dados:
        raise corrompido("estrutura inesperada")
    try:
        dados["teto"] = numero(dados["teto"], "teto", minimo_exclusivo=True)
        for nome, item in dados["itens"].items():
            if not isinstance(item, dict) or not isinstance(item.get("confirmado"), bool):
                raise corrompido(f"item '{nome}'")
            item["cotado"] = numero(item["cotado"], "cotado")
            item["gasto"] = None if item.get("gasto") is None else numero(item["gasto"], "gasto")
            item["estourou"] = bool(item.get("estourou", False))
    except Recusa as e:
        if str(e).startswith("orçamento corrompido"):
            raise
        raise corrompido(str(e))
    return dados


def salvar(caminho, dados):
    saida = {
        "teto": fmt(dados["teto"]),
        "itens": {
            k: {
                "cotado": fmt(v["cotado"]),
                "confirmado": v["confirmado"],
                "gasto": None if v["gasto"] is None else fmt(v["gasto"]),
                "estourou": v["estourou"],
            }
            for k, v in dados["itens"].items()
        },
    }
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(caminho)), prefix=".budget-", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write((json.dumps(saida, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, caminho)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


def gasto_total(dados):
    return sum((v["gasto"] for v in dados["itens"].values() if v["gasto"] is not None), Decimal(0))


def comprometido(dados):
    """Gasto efetivo + o que já foi confirmado e ainda não foi gasto."""
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
        raise Recusa(f"item inválido: '{nome}' (use letras, números, _ e -, até 64 caracteres)")


def estado(v):
    if v["gasto"] is not None:
        return "gasto"
    return "confirmado" if v["confirmado"] else "pendente"


def cmd_init(a):
    caminho, teto_txt = a
    teto = numero(teto_txt, "teto", minimo_exclusivo=True)
    with travar(caminho):
        if os.path.exists(caminho):
            raise Recusa(f"o orçamento já existe: {caminho} (não é sobrescrito)")
        salvar(caminho, {"teto": teto, "itens": {}})
    print(f"orçamento criado: teto {fmt(teto)}")


def cmd_quote(a):
    caminho, item, custo_txt = a
    item_valido(item)
    custo = numero(custo_txt, "custo")
    with travar(caminho):
        d = carregar(caminho)
        if item in d["itens"] and estado(d["itens"][item]) != "pendente":
            raise Recusa(f"o item '{item}' já tem cotação confirmada; não pode ser recotado")
        d["itens"][item] = {"cotado": custo, "confirmado": False, "gasto": None, "estourou": False}
        salvar(caminho, d)
    print(f"cotação registrada: {item} = {fmt(custo)}")


def cmd_status(a):
    with travar(a[0]):
        d = carregar(a[0])
    comp = comprometido(d)
    print(f"teto: {fmt(d['teto'])}")
    print(f"gasto: {fmt(gasto_total(d))}")
    print(f"comprometido: {fmt(comp)}")
    print(f"restante: {fmt(d['teto'] - comp)}")
    print(f"total cotado: {fmt(pendente(d))}")
    for nome, v in d["itens"].items():
        extra = ", estourou" if v["estourou"] else ""
        print(f"  {nome}: cotado {fmt(v['cotado'])} ({estado(v)}{extra})")


def cmd_confirm(a):
    caminho, total_txt = a
    total = numero(total_txt, "total")
    with travar(caminho):
        d = carregar(caminho)
        novos = pendente(d)
        if not any(not v["confirmado"] for v in d["itens"].values()):
            raise Recusa("não há cotações pendentes para confirmar")
        if total != novos:
            raise Recusa(
                f"o total informado ({fmt(total)}) não bate com o total pendente ({fmt(novos)}); mostre o total atual ao usuário"
            )
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
    with travar(caminho):
        d = carregar(caminho)
        if item not in d["itens"]:
            raise Recusa(f"o item '{item}' não tem cotação; cote antes de gastar")
        v = d["itens"][item]
        if v["gasto"] is not None:
            raise Recusa(f"o gasto do item '{item}' já foi registrado")
        if not v["confirmado"]:
            raise Recusa(f"a cotação do item '{item}' ainda não foi confirmada (rode confirm)")
        v["gasto"] = custo
        if custo > v["cotado"]:
            v["estourou"] = True
            salvar(caminho, d)  # o crédito foi consumido: registra o valor efetivo
            raise Estouro(
                f"estouro da cotação no item '{item}': custo {fmt(custo)} > cotação {fmt(v['cotado'])} "
                "(registrado; interrompa o lote)"
            )
        salvar(caminho, d)
    print(f"gasto registrado: {item} = {fmt(custo)}")


def cmd_check(a):
    caminho, item = a[0], a[1]
    item_valido(item)
    atual = numero(a[2], "custo atual") if len(a) > 2 else None
    with travar(caminho):
        d = carregar(caminho)
    if item not in d["itens"]:
        raise Recusa(f"o item '{item}' não tem cotação")
    v = d["itens"][item]
    if v["gasto"] is not None:
        raise Recusa(f"o gasto do item '{item}' já foi registrado")
    if not v["confirmado"]:
        raise Recusa(
            f"a cotação do item '{item}' ainda não foi confirmada (rode confirm depois que o usuário aprovar o total)"
        )
    if atual is not None and atual > v["cotado"]:
        raise Recusa(
            f"o custo atual ({fmt(atual)}) é maior que o cotado ({fmt(v['cotado'])}); recote e peça nova confirmação"
        )
    print(f"ok: {item} confirmado ({fmt(v['cotado'])})")


def cmd_state(a):
    caminho, item = a
    item_valido(item)
    with travar(caminho):
        d = carregar(caminho)
    print(estado(d["itens"][item]) if item in d["itens"] else "nenhum")


COMANDOS = {
    "init": (cmd_init, 2, 2),
    "quote": (cmd_quote, 3, 3),
    "status": (cmd_status, 1, 1),
    "confirm": (cmd_confirm, 2, 2),
    "spend": (cmd_spend, 3, 3),
    "check": (cmd_check, 2, 3),
    "state": (cmd_state, 2, 2),
}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMANDOS:
        print(__doc__, file=sys.stderr)
        return 2
    fn, minimo, maximo = COMANDOS[argv[1]]
    n = len(argv) - 2
    if not minimo <= n <= maximo:
        print(f"uso incorreto de '{argv[1]}'; veja budget.py sem argumentos", file=sys.stderr)
        return 2
    try:
        fn(argv[2:])
    except Recusa as e:
        print(f"recusado: {e}", file=sys.stderr)
        return e.codigo
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
