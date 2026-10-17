#!/usr/bin/env python3
"""Monta o payload EXATO de `generate_video` (Higgsfield) para uma cena de um gen-plan.json.

Uso: genpayload.py <gen-plan.json> <id> [--cost-only]
- `--cost-only` → `get_cost: true` (cota sem criar job e sem cobrar).
- Sem `--cost-only` → `get_cost: false` (gera de verdade; só depois da confirmação do total, ver generate-clips.sh).
Nunca inclui use_unlim, use_free_gens, preset_session_id, medias nem folder_id. count é sempre 1.
O agente (skill) envia este JSON à ferramenta `generate_video`, sem alterar nada.
"""
import json
import sys


def main(argv):
    args = argv[1:]
    cost_only = "--cost-only" in args
    if cost_only:
        args.remove("--cost-only")
    if len(args) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    with open(args[0], encoding="utf-8") as f:
        plano = json.load(f)
    cena = next((c for c in plano["cenas"] if c["id"] == args[1]), None)
    if cena is None:
        print(f"a cena '{args[1]}' não existe no plano", file=sys.stderr)
        return 1
    payload = {
        "context": "Gerar uma cena de vídeo vertical para um vídeo curto de marketing",
        "params": {
            "model": plano["modelo"],
            "prompt": cena["prompt"],
            "aspect_ratio": plano["aspecto"],
            "duration": cena["duracao_s"],
            "resolution": plano["resolucao"],
            "generate_audio": plano["audio"],
            "count": 1,
            "get_cost": cost_only,
        },
    }
    sys.stdout.buffer.write((json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
