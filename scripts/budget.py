#!/usr/bin/env python3
"""Teto de gastos: registro de tudo que consome crédito (Katana, geração de clipes etc.).

Fluxo obrigatório: init (teto) -> quote (uma cotação por item) -> confirm <total> (o usuário aprova o
TOTAL que viu) -> spend (por item). Nada é gasto sem cotação confirmada, e o total comprometido
(gasto + confirmado ainda não gasto) nunca passa do teto.

Uso:
  budget.py init    <arquivo> <teto|sem-teto>   (o teto é opcional: o usuário escolhe ao iniciar o fluxo)
  budget.py quote   <arquivo> <item> <custo>
  budget.py status  <arquivo>
  budget.py confirm <arquivo> <total>   confirma as cotações pendentes; <total> deve ser o total mostrado ao usuário
  budget.py spend   <arquivo> <item> <custo>   custo acima da cotação é REGISTRADO e sai com código 3 (estouro)
  budget.py check   <arquivo> <item> [custo_atual] [--ignorar-teto] [--exigir-emitido]
                    sai 0 só se o item está confirmado e não gasto, o preço atual não subiu e os compromissos
                    (gasto + confirmado não gasto) cabem no teto; --ignorar-teto é só para REGISTRAR um clipe já pago
  budget.py emit    <arquivo> <item> [--reemitir]   marca que o payload de geração foi emitido (uma vez); reemitir só
                    depois de conferir no Higgsfield que nenhum job foi criado
  budget.py externo <arquivo> <item> <gasto>  registra o gasto de um serviço AUTÔNOMO que cobra por conta própria (Katana):
                    não há cotação prévia a confirmar; o gasto efetivo é registrado e, se passar do teto, sai com código 3
  budget.py raise   <arquivo> <novo_teto>  aumenta o teto (decisão explícita do usuário; nunca reduz)
  budget.py drop    <arquivo> <item>       descarta um item que ainda não foi gasto (libera a reserva)
  budget.py state   <arquivo> <item>    imprime: nenhum | pendente | confirmado | emitido | gasto

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


SEM_TETO = "sem-teto"


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
        if dados["teto"] is not None:
            dados["teto"] = numero(dados["teto"], "teto", minimo_exclusivo=True)
        for nome, item in dados["itens"].items():
            if not isinstance(item, dict) or not isinstance(item.get("confirmado"), bool):
                raise corrompido(f"item '{nome}'")
            item["cotado"] = numero(item["cotado"], "cotado")
            item["gasto"] = None if item.get("gasto") is None else numero(item["gasto"], "gasto")
            item["estourou"] = bool(item.get("estourou", False))
            item["emitido"] = bool(item.get("emitido", False))
    except Recusa as e:
        if str(e).startswith("orçamento corrompido"):
            raise
        raise corrompido(str(e))
    return dados


def salvar(caminho, dados):
    saida = {
        "teto": None if dados["teto"] is None else fmt(dados["teto"]),
        "itens": {
            k: {
                "cotado": fmt(v["cotado"]),
                "confirmado": v["confirmado"],
                "gasto": None if v["gasto"] is None else fmt(v["gasto"]),
                "estourou": v["estourou"],
                "emitido": v["emitido"],
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
    if v["confirmado"]:
        return "emitido" if v["emitido"] else "confirmado"
    return "pendente"


def cmd_init(a):
    caminho, teto_txt = a
    teto = None if teto_txt.strip().lower() == SEM_TETO else numero(teto_txt, "teto", minimo_exclusivo=True)
    with travar(caminho):
        if os.path.exists(caminho):
            raise Recusa(f"o orçamento já existe: {caminho} (não é sobrescrito)")
        salvar(caminho, {"teto": teto, "itens": {}})
    print("orçamento criado: sem teto (cotação e confirmação do total continuam valendo)" if teto is None else f"orçamento criado: teto {fmt(teto)}")


def cmd_quote(a):
    caminho, item, custo_txt = a
    item_valido(item)
    custo = numero(custo_txt, "custo", minimo_exclusivo=True)   # cotação 0 quase sempre é leitura errada do preço
    with travar(caminho):
        d = carregar(caminho)
        if item in d["itens"] and estado(d["itens"][item]) != "pendente":
            raise Recusa(f"o item '{item}' já tem cotação confirmada; não pode ser recotado")
        d["itens"][item] = {"cotado": custo, "confirmado": False, "gasto": None, "estourou": False, "emitido": False}
        salvar(caminho, d)
    print(f"cotação registrada: {item} = {fmt(custo)}")


def cmd_status(a):
    with travar(a[0]):
        d = carregar(a[0])
    comp = comprometido(d)
    print("teto: sem teto" if d["teto"] is None else f"teto: {fmt(d['teto'])}")
    print(f"gasto: {fmt(gasto_total(d))}")
    print(f"comprometido: {fmt(comp)}")
    if d["teto"] is not None:
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
        restante = None if d["teto"] is None else d["teto"] - comprometido(d)
        if restante is not None and novos > restante:
            raise Recusa(f"o custo total cotado ({fmt(novos)}) excede o restante do teto ({fmt(restante)})")
        for v in d["itens"].values():
            v["confirmado"] = True
        salvar(caminho, d)
    if restante is None:
        print(f"confirmado: {fmt(novos)} (sem teto definido)")
    else:
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


def validar_item_para_gerar(d, item, atual=None, ignorar_teto=False, exigir_emitido=False):
    if item not in d["itens"]:
        raise Recusa(f"o item '{item}' não tem cotação")
    v = d["itens"][item]
    if v["gasto"] is not None:
        raise Recusa(f"o gasto do item '{item}' já foi registrado")
    if not v["confirmado"]:
        raise Recusa(
            f"a cotação do item '{item}' ainda não foi confirmada (rode confirm depois que o usuário aprovar o total)"
        )
    comp = comprometido(d)
    if not ignorar_teto and d["teto"] is not None and comp > d["teto"]:
        raise Recusa(
            f"os compromissos ({fmt(comp)}) ultrapassam o teto ({fmt(d['teto'])}), em geral depois de um estouro: nada novo é gerado "
            "sem uma decisão do usuário (aumentar o teto com raise, ou descartar itens com drop e cotar de novo)"
        )
    if atual is not None and atual > v["cotado"]:
        raise Recusa(
            f"o custo atual ({fmt(atual)}) é maior que o cotado ({fmt(v['cotado'])}); recote e peça nova confirmação"
        )
    if exigir_emitido and not v["emitido"]:
        raise Recusa(f"o payload de geração da cena ainda não foi emitido (item '{item}'); emita antes de registrar")
    return v


def cmd_check(a):
    flags = [x for x in a if x.startswith("--")]
    pos = [x for x in a if not x.startswith("--")]
    caminho, item = pos[0], pos[1]
    item_valido(item)
    atual = numero(pos[2], "custo atual") if len(pos) > 2 else None
    with travar(caminho):
        d = carregar(caminho)
        v = validar_item_para_gerar(d, item, atual, "--ignorar-teto" in flags, "--exigir-emitido" in flags)
    print(f"ok: {item} confirmado ({fmt(v['cotado'])})")


def cmd_emit(a):
    flags = [x for x in a if x.startswith("--")]
    caminho, item = [x for x in a if not x.startswith("--")][:2]
    item_valido(item)
    with travar(caminho):
        d = carregar(caminho)
        v = validar_item_para_gerar(d, item)
        if v["emitido"] and "--reemitir" not in flags:
            raise Recusa(
                f"o payload de geração do item '{item}' já foi emitido: um job pode ter sido criado e cobrado. "
                "Confira o job no Higgsfield (job_id, show_generations) em vez de reenviar; só se tiver certeza de que "
                "nenhum job foi criado, emita de novo com --reemitir"
            )
        v["emitido"] = True
        salvar(caminho, d)
    print(f"payload emitido: {item}")


def cmd_externo(a):
    caminho, item, gasto_txt = a
    item_valido(item)
    gasto = numero(gasto_txt, "gasto")
    with travar(caminho):
        d = carregar(caminho)
        if item in d["itens"]:
            raise Recusa(f"o item '{item}' já está registrado")
        d["itens"][item] = {"cotado": gasto, "confirmado": True, "gasto": gasto, "estourou": False, "emitido": True}
        passou = d["teto"] is not None and comprometido(d) > d["teto"]
        if passou:
            d["itens"][item]["estourou"] = True
        salvar(caminho, d)  # o crédito já foi consumido: registra sempre o valor efetivo
    if passou:
        raise Estouro(f"o gasto registrado ({fmt(gasto)}) levou o total acima do teto ({fmt(d['teto'])}); nada novo deve ser gerado sem uma decisão do usuário")
    print(f"gasto externo registrado: {item} = {fmt(gasto)}")


def cmd_raise(a):
    caminho, novo_txt = a
    novo = numero(novo_txt, "teto", minimo_exclusivo=True)
    with travar(caminho):
        d = carregar(caminho)
        era_sem_teto = d["teto"] is None
        if era_sem_teto:
            if novo < comprometido(d):
                raise Recusa(f"o teto ({fmt(novo)}) não pode ficar abaixo do que já está gasto ou confirmado ({fmt(comprometido(d))})")
        elif novo <= d["teto"]:
            raise Recusa(f"o novo teto ({fmt(novo)}) deve ser maior que o atual ({fmt(d['teto'])}); este comando nunca reduz o teto")
        d["teto"] = novo
        salvar(caminho, d)
    print(f"teto definido em {fmt(novo)}" if era_sem_teto else f"teto aumentado para {fmt(novo)}")


def cmd_drop(a):
    caminho, item = a
    item_valido(item)
    with travar(caminho):
        d = carregar(caminho)
        if item not in d["itens"]:
            raise Recusa(f"o item '{item}' não existe no orçamento")
        if d["itens"][item]["gasto"] is not None:
            raise Recusa(f"o item '{item}' já foi gasto e não pode ser descartado")
        del d["itens"][item]
        salvar(caminho, d)
    print(f"item descartado: {item}")


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
    "check": (cmd_check, 2, 5),
    "emit": (cmd_emit, 2, 3),
    "externo": (cmd_externo, 3, 3),
    "raise": (cmd_raise, 2, 2),
    "drop": (cmd_drop, 2, 2),
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
