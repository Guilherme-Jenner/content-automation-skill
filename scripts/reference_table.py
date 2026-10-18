#!/usr/bin/env python3
"""Tabela de referência de custos de geração (qualidade x duração -> créditos e valor aproximado).

Mostrada ao usuário ao perguntar o teto de gastos, porque quase ninguém sabe quanto custa um clipe.

Uso: reference_table.py [--duracoes 5,10,15,30] [--cotacao-dolar 5,50]
- Os dados vêm de data/precos-higgsfield.json (cotados com get_cost, com a data da consulta); preço muda: confira com
  get_cost antes de gerar, que é o valor que vale.
- O valor em dólar usa o preço de referência do crédito; reais só aparecem se o usuário informar a cotação do dólar.
"""
import json
import os
import sys
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation

DADOS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "precos-higgsfield.json")
DURACAO_MIN, DURACAO_MAX = 4, 30
PADRAO = [5, 10, 15, 30]


def dinheiro(valor):
    q = valor.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return f"{q:.2f}".replace(".", ",")


def numero_br(texto):
    try:
        v = Decimal(texto.strip().replace(",", "."))
    except InvalidOperation:
        raise ValueError(f"valor inválido: '{texto}'")
    if not v.is_finite() or v <= 0:
        raise ValueError(f"o valor deve ser maior que zero (recebido '{texto}')")
    return v


def main(argv):
    args = argv[1:]
    duracoes, cotacao = PADRAO, None
    try:
        while args:
            a = args.pop(0)
            if a == "--duracoes" and args:
                duracoes = [int(x) for x in args.pop(0).split(",")]
                if not duracoes or any(not DURACAO_MIN <= d <= DURACAO_MAX for d in duracoes):
                    raise ValueError(f"as durações devem estar entre {DURACAO_MIN} e {DURACAO_MAX} segundos")
            elif a == "--cotacao-dolar" and args:
                cotacao = numero_br(args.pop(0))
            else:
                print(__doc__, file=sys.stderr)
                return 2
    except ValueError as e:
        print(f"erro: {e}", file=sys.stderr)
        return 1
    with open(DADOS, encoding="utf-8") as f:
        d = json.load(f)
    ref = Decimal(str(d["preco_credito_usd"]["referencia"]))
    cabecalho = "| Qualidade | Duração | Créditos | ≈ US$ |" + (" ≈ R$ |" if cotacao else "")
    separador = "|---|---|---|---|" + ("---|" if cotacao else "")
    linhas = [cabecalho, separador]
    for res, por_s in d["creditos_por_segundo"].items():
        for dur in duracoes:
            creditos = por_s * dur
            usd = Decimal(creditos) * ref
            linha = f"| {res} | {dur} s | {creditos} | US$ {dinheiro(usd)} |"
            if cotacao:
                linha += f" R$ {dinheiro(usd * cotacao)} |"
            linhas.append(linha)
    usd_min, usd_max = d["preco_credito_usd"]["minimo"], d["preco_credito_usd"]["maximo"]
    saida = [
        f"Referência de custo por clipe ({d['modelo']}, {d['modo']}), consultada em {d['consultado_em']}:",
        "",
        *linhas,
        "",
        f"Valores em dinheiro são aproximados: usam US$ {str(ref).replace('.', ',')} por crédito (varia de US$ {str(usd_min).replace('.', ',')} no plano anual a US$ {str(usd_max).replace('.', ',')} no menor pacote avulso)"
        + (f" e dólar a R$ {dinheiro(cotacao)}." if cotacao else "; informe a cotação do dólar para ver em reais."),
        "O preço exato é cotado com get_cost (sem cobrar) antes de gerar, e é ele que vale.",
    ]
    sys.stdout.buffer.write(("\n".join(saida) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
