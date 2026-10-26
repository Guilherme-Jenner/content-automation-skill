#!/usr/bin/env python3
"""Valida um slideshow-plan.json (1 a 5 slideshows/carrosséis a partir das MESMAS fotos do usuário).

Erros (exit 1): schema; quantidade fora de 1..5 ou diferente do número de variantes; ids inseguros ou repetidos
(caixa ignorada); foto sem arquivo, com extensão não suportada ou fora da pasta do plano; slide com foto que não
existe no plano ou foto repetida na mesma variante; 3 a 10 slides por variante; primeiro slide deve ser o único
`hook`, o último o único `cta`, e ao menos um `app` (ou o `cta` marcado `mostra_app: true`, quando a foto do CTA é o print do app); texto vazio ou que não cabe em 3 linhas no estilo;
duracao_s fora de 1,5..6 s ou vídeo acima de 60 s; volume fora de -40..0; variantes idênticas (mesma ordem de fotos
e mesmos textos); formato_hook repetido sem justificativa (exceto com `hook_fixo: true`, que exige o mesmo formato e texto de hook em todas as variantes); achados vazios.
Os arquivos de foto são resolvidos a partir da pasta do plano.

Uso: validate_slideshow.py <slideshow-plan.json>
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from caption_styles import cabe, maximo  # noqa: E402
from validate_json import validar  # noqa: E402

AQUI = os.path.dirname(os.path.abspath(__file__))
SCHEMA = os.path.join(AQUI, "..", "schemas", "slideshow-plan.schema.json")
MAX_VARIANTES = 5
MIN_SLIDES, MAX_SLIDES = 3, 10
DURACAO_PADRAO, DURACAO_MIN, DURACAO_MAX, DURACAO_TOTAL_MAX = 2.5, 1.5, 6.0, 60.0
EXTENSOES = {".jpg", ".jpeg", ".png", ".webp"}
CAMPOS_TOPO = {"quantidade", "estilo", "fotos", "variantes", "hook_fixo"}
CAMPOS_FOTO = {"id", "arquivo", "descricao"}
CAMPOS_VARIANTE = {"id", "formato_hook", "formato_anuncio", "slides", "musica", "volume_db",
                   "gancho_repetido", "justificativa_gancho", "aprovada", "achados"}
CAMPOS_SLIDE = {"foto", "papel", "texto", "duracao_s", "mostra_app"}
ID_VALIDO = re.compile(r"^[A-Za-z0-9_-]{1,32}$")


def _norm(texto):
    return " ".join(texto.lower().split())


def duracao_do_slide(slide):
    return slide.get("duracao_s", DURACAO_PADRAO)


def erros_do_plano(plano, base):
    with open(SCHEMA, encoding="utf-8") as f:
        schema = json.load(f)
    erros = []
    validar(plano, schema, "", erros)
    if erros:
        return erros
    for chave in plano:
        if chave not in CAMPOS_TOPO:
            erros.append(f"campo desconhecido no plano: '{chave}' (confira a grafia)")
    estilo = plano.get("estilo", "padrao")
    variantes = plano["variantes"]
    if not 1 <= plano["quantidade"] <= MAX_VARIANTES:
        erros.append(f"quantidade deve estar entre 1 e {MAX_VARIANTES} (recebido {plano['quantidade']})")
    if plano["quantidade"] != len(variantes):
        erros.append(f"quantidade ({plano['quantidade']}) não bate com o número de variantes ({len(variantes)})")

    fotos = {}
    for i, f in enumerate(plano["fotos"]):
        nome = f"fotos[{i}]"
        for chave in f:
            if chave not in CAMPOS_FOTO:
                erros.append(f"{nome}: campo desconhecido '{chave}' (confira a grafia)")
        if not ID_VALIDO.fullmatch(f["id"]):
            erros.append(f"{nome}.id inválido: use só letras, números, _ e - (até 32 caracteres)")
        if f["id"] in fotos:
            erros.append(f"{nome}: id de foto repetido '{f['id']}'")
        fotos[f["id"]] = f
        if not f["descricao"].strip():
            erros.append(f"{nome}: descricao vazia (descreva o que a foto mostra)")
        caminho = f["arquivo"]
        if os.path.isabs(caminho) or caminho.startswith(("/", "\\")) or re.match(r"^[A-Za-z]:[\\/]", caminho) or os.path.normpath(caminho).split(os.sep)[0] == "..":
            erros.append(f"{nome}: '{caminho}' precisa ficar dentro da pasta do plano (caminho relativo, sem '..')")
        elif os.path.splitext(caminho)[1].lower() not in EXTENSOES:
            erros.append(f"{nome}: formato não suportado '{caminho}' (use .jpg, .jpeg, .png ou .webp)")
        elif not os.path.isfile(os.path.join(base, caminho)):
            erros.append(f"{nome}: arquivo não encontrado: {caminho}")

    vistos = set()
    for i, v in enumerate(variantes):
        nome = f"variantes[{i}]"
        if not ID_VALIDO.fullmatch(v["id"]):
            erros.append(f"{nome}.id inválido: use só letras, números, _ e - (até 32 caracteres)")
        if v["id"].lower() in vistos:
            erros.append("ids de variantes repetidos (maiúsculas e minúsculas contam como iguais)")
        vistos.add(v["id"].lower())
        for chave in v:
            if chave not in CAMPOS_VARIANTE:
                erros.append(f"{nome}: campo desconhecido '{chave}' (confira a grafia)")
        if "volume_db" in v and "musica" not in v:
            erros.append(f"{nome}: volume_db sem musica (o volume só vale para a trilha)")
        if "volume_db" in v and not -40 <= v["volume_db"] <= 0:
            erros.append(f"{nome}: volume_db deve estar entre -40 e 0 (recebido {v['volume_db']})")
        if "musica" in v:
            m = v["musica"]
            if not os.path.isabs(m) and not re.match(r"^[A-Za-z]:[\\/]", m) and os.path.normpath(m).split(os.sep)[0] == "..":
                erros.append(f"{nome}: a música relativa sai da pasta do plano ('{m}'); coloque o arquivo ao lado do plano ou use caminho absoluto")
        if not v["achados"]:
            erros.append(f"{nome}: achados vazio (ligue a variante à pesquisa)")

        slides = v["slides"]
        if not MIN_SLIDES <= len(slides) <= MAX_SLIDES:
            erros.append(f"{nome}: de {MIN_SLIDES} a {MAX_SLIDES} slides (tem {len(slides)})")
        papeis = [s["papel"] for s in slides]
        if papeis[0] != "hook" or papeis.count("hook") != 1:
            erros.append(f"{nome}: o primeiro slide (e só ele) deve ter papel 'hook'")
        if papeis[-1] != "cta" or papeis.count("cta") != 1:
            erros.append(f"{nome}: o último slide (e só ele) deve ter papel 'cta'")
        if "app" not in papeis and not any(s["papel"] == "cta" and s.get("mostra_app") is True for s in slides):
            erros.append(f"{nome}: falta ao menos um slide com papel 'app' (o anúncio do app), ou o cta com mostra_app: true")
        usadas = [s["foto"] for s in slides]
        if len(set(usadas)) != len(usadas):
            erros.append(f"{nome}: foto repetida na mesma variante")
        total = 0.0
        for k, s in enumerate(slides):
            ns = f"{nome}.slides[{k}]"
            for chave in s:
                if chave not in CAMPOS_SLIDE:
                    erros.append(f"{ns}: campo desconhecido '{chave}' (confira a grafia)")
            if s["foto"] not in fotos:
                erros.append(f"{ns}: a foto '{s['foto']}' não existe em fotos")
            texto = s["texto"].strip()
            if not texto:
                erros.append(f"{ns}: texto vazio")
            elif not cabe(texto, estilo):
                erros.append(f"{ns}: o texto ({len(texto)} caracteres) não cabe em 3 linhas no estilo '{estilo}' "
                             f"(cerca de {maximo(estilo)} caracteres); encurte")
            d = duracao_do_slide(s)
            if not DURACAO_MIN <= d <= DURACAO_MAX:
                erros.append(f"{ns}: duracao_s deve estar entre {DURACAO_MIN:g} e {DURACAO_MAX:g} s (recebido {d:g})")
            total += d
        if total > DURACAO_TOTAL_MAX:
            erros.append(f"{nome}: duração total {total:g} s passa de {DURACAO_TOTAL_MAX:g} s")

    if not erros:
        assinaturas = {}
        for i, v in enumerate(variantes):
            ass = json.dumps([[(s["foto"], " ".join(s["texto"].lower().split())) for s in v["slides"]],
                              v.get("musica"), v.get("volume_db")], ensure_ascii=False)
            if ass in assinaturas:
                erros.append(f"variantes[{i}] é idêntica a variantes[{assinaturas[ass]}] (mesma ordem de fotos e mesmos textos)")
            assinaturas.setdefault(ass, i)
        ganchos = {}
        hook_fixo = plano.get("hook_fixo", False)
        if hook_fixo:
            # hook fixo (opcional): o mesmo hook (formato e texto) em todas as variantes; só o resto varia
            for i, v in enumerate(variantes[1:], 1):
                if v["formato_hook"] != variantes[0]["formato_hook"]:
                    erros.append(f"variantes[{i}]: com hook_fixo, o formato_hook deve ser o mesmo de variantes[0] ('{variantes[0]['formato_hook']}')")
                if _norm(v["slides"][0]["texto"]) != _norm(variantes[0]["slides"][0]["texto"]):
                    erros.append(f"variantes[{i}]: com hook_fixo, o texto do hook deve ser o mesmo de variantes[0]")
        for i, v in enumerate(variantes):
            g = v["formato_hook"]
            if hook_fixo:
                break
            if g in ganchos and not (v.get("gancho_repetido") and v.get("justificativa_gancho", "").strip()):
                erros.append(f"variantes[{i}]: formato_hook '{g}' repetido de variantes[{ganchos[g]}] "
                             "sem gancho_repetido e justificativa_gancho")
            ganchos.setdefault(g, i)
    return erros


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        plano = json.load(f)
    erros = erros_do_plano(plano, os.path.dirname(os.path.abspath(argv[1])))
    for e in erros:
        print(e, file=sys.stderr)
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
