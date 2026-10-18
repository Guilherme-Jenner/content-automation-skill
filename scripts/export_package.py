#!/usr/bin/env python3
"""Monta o pacote para agendar um post manualmente no Instagram/TikTok (plano B, sem MCP).

Uso: export_package.py <plano> <post-id> <saida-dir> [--force] [--now <ISO>]
Cria <saida-dir>/<post-id>/ com video.<ext>, legenda.txt, horario.txt e COMO-AGENDAR.md.
Não publica nem agenda nada; só exige que o plano esteja válido.
"""
import os
import shutil
import sys
import tempfile
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from approval import Recusa, achar_post  # noqa: E402
from validate_schedule import agora, caminho_do_video, erros_do_plano  # noqa: E402

DIAS = ["segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado", "domingo"]

COMO_AGENDAR = """# Como agendar este post manualmente

Arquivos desta pasta: `video`, `legenda.txt` (cole como está) e `horario.txt` (dia, hora e perfis).

> Os nomes de botões, os limites e as regras das redes mudam com frequência: **conferir no app** antes de contar
> com qualquer passo abaixo. Se algo estiver diferente, vale o que o app mostrar.

## Instagram
1. No celular ou no Meta Business Suite (computador), crie um novo Reel/post e escolha o vídeo desta pasta.
2. Cole o conteúdo de `legenda.txt` na legenda.
3. Procure a opção de **agendar** (nas configurações avançadas ou ao lado de "Compartilhar") e informe o dia e a hora de `horario.txt`.
4. Em geral o agendamento exige conta profissional (comercial ou criador): conferir no app.

## TikTok
1. No computador (TikTok Studio / upload pela web), envie o vídeo desta pasta.
2. Cole o conteúdo de `legenda.txt`.
3. Ative **agendar** e informe o dia e a hora de `horario.txt`. A antecedência máxima permitida varia: conferir no app.

## Depois
Confirme no app que o post aparece como agendado, com o dia, a hora e o perfil corretos.
"""


def main(argv):
    force = "--force" in argv
    now = agora(argv)
    args, i = [], 1
    while i < len(argv):
        if argv[i] == "--force":
            i += 1
        elif argv[i] == "--now":
            i += 2
        else:
            args.append(argv[i])
            i += 1
    if len(args) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    plano, post_id, saida = args
    try:
        post = achar_post(plano, post_id)
        erros = erros_do_plano(plano, now, post_id)
        if erros:
            raise Recusa("o plano não está válido:\n  " + "\n  ".join(erros))
        destino = os.path.join(saida, post_id)
        if os.path.exists(destino) and not force:
            raise Recusa(f"o pacote já existe: {destino} (use --force para refazer)")
        os.makedirs(saida, exist_ok=True)
        tmp = tempfile.mkdtemp(dir=saida, prefix=f".{post_id}.")   # nome único: duas execuções não se pisam
        video = caminho_do_video(plano, post["video"])
        shutil.copyfile(video, os.path.join(tmp, "video" + os.path.splitext(video)[1]))
        legenda = post["legenda"] + "\n"
        if post["hashtags"]:
            legenda = post["legenda"] + "\n\n" + " ".join(post["hashtags"]) + "\n"
        dt = datetime.fromisoformat(post["data_hora"])
        perfis = "\n".join(f"- {p['rede']}: {p['conta']}" for p in post["perfis"])
        horario = (
            f"{DIAS[dt.weekday()]}, {dt:%d/%m/%Y} às {dt:%H:%M} (horário de Brasília, -03:00)\n\n"
            f"Perfis:\n{perfis}\n"
        )
        for nome, conteudo in (("legenda.txt", legenda), ("horario.txt", horario), ("COMO-AGENDAR.md", COMO_AGENDAR)):
            with open(os.path.join(tmp, nome), "wb") as f:  # bytes + LF: idêntico no Windows e no Mac
                f.write(conteudo.encode("utf-8"))
        antigo = destino + ".old"
        if os.path.exists(destino):
            shutil.rmtree(antigo, ignore_errors=True)
            os.rename(destino, antigo)
        os.rename(tmp, destino)
        shutil.rmtree(antigo, ignore_errors=True)
    except Recusa as e:
        print(f"recusado: {e}", file=sys.stderr)
        return 1
    print(f"pacote criado: {destino}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
