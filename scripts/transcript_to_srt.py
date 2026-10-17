#!/usr/bin/env python3
"""Converte um transcript em SRT (stdout).

Uso: transcript_to_srt.py <transcript.json> [duracao_s]
Ordena por início, descarta segmentos vazios ou fora da duração, limita o fim à duração
e quebra o texto em linhas de até 42 caracteres.
"""
import json
import sys
import textwrap

LARGURA = 42


def tempo(s):
    ms = round(s * 1000)
    h, ms = divmod(ms, 3600000)
    m, ms = divmod(ms, 60000)
    seg, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{seg:02d},{ms:03d}"


def main(argv):
    # --escapar-ass: só para a cópia usada na QUEIMA. O libass trata {...} como código de estilo e o texto
    # entre chaves sumiria do vídeo; escapando as chaves ele aparece. O .srt entregue ao usuário não usa isto.
    escapar = "--escapar-ass" in argv
    argv = [a for a in argv if a != "--escapar-ass"]
    # --largura N: caracteres por linha na quebra (padrão 42, para o .srt entregue; a cópia de queima usa a
    # largura do estilo, porque o libass quebra de novo o que não cabe na tela).
    largura = LARGURA
    if "--largura" in argv:
        i = argv.index("--largura")
        largura = int(argv[i + 1])
        del argv[i : i + 2]
    with open(argv[1], encoding="utf-8") as f:
        dados = json.load(f)
    duracao = float(argv[2]) if len(argv) > 2 else None
    blocos = []
    for s in sorted(dados["segmentos"], key=lambda s: s["inicio_s"]):
        texto = " ".join(s["texto"].split())
        ini, fim = s["inicio_s"], s["fim_s"]
        if not texto:
            continue
        if duracao is not None:
            if ini >= duracao:
                continue
            fim = min(fim, duracao)
        if fim <= ini:
            continue
        linhas = textwrap.wrap(texto, largura)
        if escapar:  # depois de quebrar, para o escape nunca ser separado do caractere que protege
            linhas = [l.replace("{", "\\{").replace("}", "\\}") for l in linhas]
        blocos.append((ini, fim, "\n".join(linhas)))
    saida = []
    for n, (ini, fim, texto) in enumerate(blocos, 1):
        saida.append(f"{n}\n{tempo(ini)} --> {tempo(fim)}\n{texto}\n")
    # LF explícito: no Windows o stdout em modo texto converteria para CRLF.
    sys.stdout.buffer.write("\n".join(saida).encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
