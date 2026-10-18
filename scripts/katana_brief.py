#!/usr/bin/env python3
"""Briefing para o AGENTE rodar o Katana (Higgsfield) em uma variante aprovada. Imprime JSON; não chama serviço nenhum.

Uso: katana_brief.py <variants-plan.json> <id-da-variante> --budget <orcamento.json>

O Katana é um fluxo autônomo: ele analisa o material, cota e gasta créditos por conta própria, sem pedir confirmação.
Por isso o briefing leva o LIMITE de créditos (`limite_creditos`): o que resta do teto escolhido pelo usuário
(teto - gasto - confirmado), ou null quando o usuário não definiu teto (então o Katana define o próprio limite).
Recusa: variante inexistente ou não aprovada; plano com editor diferente de katana.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from budget import Recusa, carregar, comprometido, fmt  # noqa: E402


def limite_restante(caminho_orcamento):
    dados = carregar(caminho_orcamento)
    if dados["teto"] is None:
        return None
    restante = dados["teto"] - comprometido(dados)
    return max(restante, 0)


def main(argv):
    args = argv[1:]
    if "--budget" not in args or args.index("--budget") + 1 >= len(args):
        print("erro: informe --budget <orcamento.json> (crie com budget.py init <arquivo> <teto|sem-teto>)", file=sys.stderr)
        return 2
    i = args.index("--budget")
    orcamento = args[i + 1]
    del args[i : i + 2]
    if len(args) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    plano_caminho, vid = args
    with open(plano_caminho, encoding="utf-8") as f:
        plano = json.load(f)
    if plano.get("editor") != "katana":
        print("erro: o plano não usa o editor katana (editor: local roda com ffmpeg, sem custo)", file=sys.stderr)
        return 1
    v = next((x for x in plano["variantes"] if x["id"] == vid), None)
    if v is None:
        print(f"erro: a variante '{vid}' não existe no plano", file=sys.stderr)
        return 1
    if not v["aprovada"]:
        print(f"erro: a variante '{vid}' não foi aprovada pelo usuário (aprovada: true)", file=sys.stderr)
        return 1
    try:
        limite = limite_restante(orcamento)
    except Recusa as e:
        print(f"erro: {e}", file=sys.stderr)
        return 1
    trechos = [{"inicio_s": t["inicio_s"], "fim_s": t["fim_s"]} for t in v["trechos"]]
    texto = (
        "Edite o vídeo-fonte anexado em um vídeo curto vertical 9:16 (1080x1920) para o Clo App. "
        f"Use somente estes trechos do vídeo-fonte, nesta ordem: {json.dumps(trechos)}. "
        f"Abra com este gancho: \"{v['gancho']}\". "
        f"Estilo de legenda: {v['legenda_estilo']}; cortes com pausas a partir de {v['ritmo']['min_silencio_s']} s removidas e margem de {v['ritmo']['margem_s']} s. "
        "Mantenha a fala original e o rosto da pessoa como estão (não gere nem altere rostos). Legendas em português do Brasil. "
        "Entregue um único arquivo de vídeo final."
    )
    aviso = (
        "O Katana gasta sozinho, sem pedir confirmação. "
        + (
            f"Limite de créditos para este trabalho: {fmt(limite)} (o que resta do teto escolhido pelo usuário)."
            if limite is not None
            else "O usuário não definiu teto: o Katana define o próprio limite (sem limite fixo do usuário)."
        )
    )
    saida = {
        "id": vid,
        "fonte": os.path.abspath(plano["bruto"]),
        "trechos": trechos,
        "brief": texto,
        "limite_creditos": None if limite is None else (int(limite) if limite == int(limite) else float(limite)),
        "aviso": aviso,
        "formato": "9:16",
        "achados": v["achados"],
    }
    sys.stdout.buffer.write((json.dumps(saida, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
