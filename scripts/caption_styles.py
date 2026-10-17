#!/usr/bin/env python3
"""Estilos de legenda: largura de quebra (caracteres por linha na tela) e limite de texto por legenda.

Os valores foram calibrados para vídeo 1080x1920 com os estilos do subtitles.sh (padrao, destaque, discreto):
o libass quebra de novo qualquer linha que não caiba na largura, então a quebra do SRT precisa ser a da tela,
senão uma legenda "de 3 linhas" ocupa 5 a 10 linhas e cobre o quadro. Máximo de 3 linhas por legenda.

As larguras têm folga de segurança sobre o que foi medido no vídeo (texto em maiúsculas ou com letras largas
ocupa mais e pode ainda ser quebrado de novo pelo renderizador). O que vale para validar é CABER EM 3 LINHAS
depois da quebra por palavras: o limite em caracteres é só uma referência (palavras não se partem).

Uso: caption_styles.py largura <estilo>        -> caracteres por linha
     caption_styles.py max <estilo>            -> referência de caracteres por legenda (3 linhas)
     caption_styles.py cabe <estilo> <texto>   -> código 0 se o texto cabe em 3 linhas
     caption_styles.py prefixo <estilo> <texto> -> o maior começo do texto (por palavras) que cabe em 3 linhas
"""
import sys
import textwrap

MAX_LINHAS = 3
LARGURAS = {"padrao": 17, "destaque": 13, "discreto": 21}


def largura(estilo):
    return LARGURAS[estilo]


def maximo(estilo):
    return LARGURAS[estilo] * MAX_LINHAS


def linhas(texto, estilo):
    return textwrap.wrap(" ".join(texto.split()), LARGURAS[estilo])


def cabe(texto, estilo):
    return len(linhas(texto, estilo)) <= MAX_LINHAS


def prefixo(texto, estilo):
    saida = ""
    for palavra in texto.split():
        candidato = (saida + " " + palavra).strip()
        if not cabe(candidato, estilo):
            break
        saida = candidato
    return saida


def main(argv):
    if len(argv) < 3 or argv[1] not in ("largura", "max", "cabe", "prefixo") or argv[2] not in LARGURAS:
        print(__doc__, file=sys.stderr)
        return 2
    if argv[1] == "largura":
        print(largura(argv[2]))
    elif argv[1] == "max":
        print(maximo(argv[2]))
    elif len(argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    elif argv[1] == "cabe":
        return 0 if cabe(argv[3], argv[2]) else 1
    else:
        sys.stdout.buffer.write((prefixo(argv[3], argv[2]) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
