#!/usr/bin/env python3
"""Sobe para o Google Drive as mídias dos posts APROVADOS e gera os `urls-<post>.json` do Metricool (só biblioteca padrão).

  drive_upload.py auth    --client-secret <client_secret.json>
      Uma vez, no terminal do usuário (abre o navegador): autoriza o escopo `drive.file` (só enxerga o que esta
      ferramenta cria, nunca o resto do Drive) e guarda o token em ~/.config/clo-content-pipeline/drive-token.json (0600).
  drive_upload.py enviar  <plano> --approvals <dir> [--pasta "Nome"] [--posts p1,p2] [--compartilhar-link] [--link view|download]
      Cria a pasta (<pasta>/<post-id>/) e envia a mídia (vídeo, ou cada imagem do carrossel) dos posts com aprovação válida.
      Escreve <pasta do plano>/urls-<post-id>.json ({caminho da mídia: link}) e .drive-upload.json (ids; reenvio não duplica).
      Por padrão os arquivos ficam PRIVADOS. --compartilhar-link os torna acessíveis a quem tiver o link (isso é publicar:
      só com o "pode" explícito do usuário); sem ele, o Drive precisa estar vinculado na conta do Metricool.
  drive_upload.py revogar <plano>
      Remove o acesso por link dos arquivos que `enviar --compartilhar-link` compartilhou (os arquivos continuam no Drive).

Token alternativo: variável GOOGLE_DRIVE_ACCESS_TOKEN (token de acesso já pronto). O formato dos links aceitos pelo
Metricool não foi verificado em execução: `view` (padrão) é o link de visualização; `download` é o de download direto.
"""
import base64
import hashlib
import http.server
import json
import mimetypes
import os
import secrets
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from approval import Recusa as RecusaAprovacao  # noqa: E402
from approval import achar_post, sha256_arquivo, verificar  # noqa: E402
from validate_schedule import midias_do_post  # noqa: E402

ESCOPO = "https://www.googleapis.com/auth/drive.file"
API = "https://www.googleapis.com"
OAUTH_AUTH = "https://accounts.google.com/o/oauth2/v2/auth"
OAUTH_TOKEN = "https://oauth2.googleapis.com/token"
MANIFESTO = ".drive-upload.json"


class Recusa(Exception):
    pass


def teste(nome, padrao):
    """URLs de teste (servidor falso): só com CLO_ALLOW_TEST_NOW=1, como --now; em produção valem as do Google."""
    return os.environ.get(nome, padrao) if os.environ.get("CLO_ALLOW_TEST_NOW") == "1" else padrao


def arquivo_token():
    return teste("CLO_DRIVE_TOKEN_FILE", os.path.join(os.path.expanduser("~"), ".config", "clo-content-pipeline", "drive-token.json"))


def chamar(metodo, url, cabecalhos=None, corpo=None):
    req = urllib.request.Request(url, data=corpo, method=metodo, headers=cabecalhos or {})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            bruto = r.read()
    except urllib.error.HTTPError as e:
        detalhe = e.read().decode("utf-8", "replace")[:300]
        raise Recusa(f"o Google respondeu {e.code} em {metodo} {urllib.parse.urlsplit(url).path}: {detalhe}")
    except (urllib.error.URLError, OSError) as e:
        raise Recusa(f"sem conexão com o Google ({e})")
    return json.loads(bruto) if bruto else {}


def token_de_acesso():
    if os.environ.get("GOOGLE_DRIVE_ACCESS_TOKEN"):
        return os.environ["GOOGLE_DRIVE_ACCESS_TOKEN"]
    try:
        with open(arquivo_token(), encoding="utf-8") as f:
            t = json.load(f)
        corpo = urllib.parse.urlencode({
            "client_id": t["client_id"], "client_secret": t["client_secret"],
            "refresh_token": t["refresh_token"], "grant_type": "refresh_token"}).encode()
    except (OSError, ValueError, KeyError):
        raise Recusa("Drive não autorizado: rode uma vez `drive_upload.py auth --client-secret <client_secret.json>` no seu terminal")
    r = chamar("POST", teste("CLO_DRIVE_OAUTH_TOKEN_URL", OAUTH_TOKEN), {"Content-Type": "application/x-www-form-urlencoded"}, corpo)
    if "access_token" not in r:
        raise Recusa("não foi possível renovar o acesso ao Drive; rode `auth` de novo")
    return r["access_token"]


def cmd_auth(client_secret):
    try:
        with open(client_secret, encoding="utf-8") as f:
            c = json.load(f)
        c = c.get("installed") or c.get("web") or c
        cid, csec = c["client_id"], c["client_secret"]
    except (OSError, ValueError, KeyError):
        raise Recusa("client_secret.json inválido (crie um ID de cliente OAuth do tipo 'App para computador' no Google Cloud)")
    verificador = secrets.token_urlsafe(64)
    desafio = base64.urlsafe_b64encode(hashlib.sha256(verificador.encode()).digest()).rstrip(b"=").decode()
    estado, achado = secrets.token_urlsafe(16), {}

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
            if q.get("state", [""])[0] == estado and "code" in q:
                achado["code"] = q["code"][0]
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write("Pode fechar esta aba e voltar ao terminal.".encode("utf-8"))

        def log_message(self, *a):
            pass

    srv = http.server.HTTPServer(("127.0.0.1", 0), H)
    redirect = f"http://127.0.0.1:{srv.server_address[1]}"
    url = OAUTH_AUTH + "?" + urllib.parse.urlencode({
        "client_id": cid, "redirect_uri": redirect, "response_type": "code", "scope": ESCOPO, "state": estado,
        "code_challenge": desafio, "code_challenge_method": "S256", "access_type": "offline", "prompt": "consent"})
    print("Abra este link no navegador (tentando abrir automaticamente) e autorize:\n" + url)
    webbrowser.open(url)
    threading.Thread(target=srv.handle_request, daemon=True).start()
    for _ in range(600):
        if "code" in achado:
            break
        threading.Event().wait(0.5)
    srv.server_close()
    if "code" not in achado:
        raise Recusa("autorização não concluída (tempo esgotado)")
    r = chamar("POST", OAUTH_TOKEN, {"Content-Type": "application/x-www-form-urlencoded"}, urllib.parse.urlencode({
        "client_id": cid, "client_secret": csec, "code": achado["code"], "code_verifier": verificador,
        "grant_type": "authorization_code", "redirect_uri": redirect}).encode())
    if "refresh_token" not in r:
        raise Recusa("o Google não devolveu o token de renovação; remova o acesso do app em myaccount.google.com/permissions e rode de novo")
    destino = arquivo_token()
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    fd = os.open(destino, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump({"client_id": cid, "client_secret": csec, "refresh_token": r["refresh_token"]}, f)
    print(f"Drive autorizado (escopo drive.file). Token guardado em {destino}")


def api(token, metodo, caminho, corpo=None, upload=False):
    base = teste("CLO_DRIVE_API_BASE", API)
    url = base + ("/upload" if upload else "") + caminho
    cab = {"Authorization": f"Bearer {token}"}
    dados = None
    if isinstance(corpo, dict):
        cab["Content-Type"] = "application/json"
        dados = json.dumps(corpo).encode("utf-8")
    elif corpo is not None:
        dados = corpo[1]
        cab["Content-Type"] = corpo[0]
    return chamar(metodo, url, cab, dados)


def criar_pasta(token, nome, pai=None):
    meta = {"name": nome, "mimeType": "application/vnd.google-apps.folder"}
    if pai:
        meta["parents"] = [pai]
    return api(token, "POST", "/drive/v3/files?fields=id", meta)["id"]


def enviar_arquivo(token, caminho, pasta_id, nome):
    limite = secrets.token_hex(16)
    tipo = mimetypes.guess_type(nome)[0] or "application/octet-stream"
    meta = json.dumps({"name": nome, "parents": [pasta_id]})
    with open(caminho, "rb") as f:
        conteudo = f.read()
    corpo = (f"--{limite}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n{meta}\r\n--{limite}\r\nContent-Type: {tipo}\r\n\r\n").encode() \
        + conteudo + f"\r\n--{limite}--".encode()
    return api(token, "POST", "/drive/v3/files?uploadType=multipart&fields=id", (f"multipart/related; boundary={limite}", corpo), upload=True)["id"]


def link(id_, formato):
    if formato == "download":
        return f"https://drive.google.com/uc?export=download&id={id_}"
    return f"https://drive.google.com/file/d/{id_}/view"


def carregar(caminho):
    if not os.path.exists(caminho):
        return {"posts": {}}
    try:
        with open(caminho, encoding="utf-8") as f:
            d = json.load(f)
        d.setdefault("posts", {})
        return d
    except ValueError:
        raise Recusa(f"{caminho} está corrompido")


def salvar(caminho, dados):
    tmp = caminho + ".tmp"
    with open(tmp, "wb") as f:
        f.write((json.dumps(dados, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    os.replace(tmp, caminho)


def cmd_enviar(plano, aprovacoes, pasta, posts, compartilhar, formato):
    base = os.path.dirname(os.path.abspath(plano))
    with open(plano, encoding="utf-8") as f:
        ids = [p["id"] for p in json.load(f)["posts"]]
    explicitos = posts is not None
    alvo = posts if explicitos else ids
    validos = []
    for pid in alvo:
        try:
            achar_post(plano, pid)
            verificar(plano, pid, aprovacoes)
            validos.append(pid)
        except RecusaAprovacao as e:
            if explicitos:
                raise Recusa(f"o post '{pid}' não tem aprovação válida ({e}); nada foi enviado")
            print(f"pulado (sem aprovação válida): {pid}")
    if not validos:
        raise Recusa("nenhum post com aprovação válida para enviar")
    token = token_de_acesso()
    caminho_m = os.path.join(base, MANIFESTO)
    m = carregar(caminho_m)
    if m.get("pasta", {}).get("nome") != pasta:
        m["pasta"] = {"nome": pasta, "id": criar_pasta(token, pasta)}
        m["posts"] = {}
        salvar(caminho_m, m)
    for pid in validos:
        post = achar_post(plano, pid)
        reg = m["posts"].setdefault(pid, {"pasta_id": None, "arquivos": {}})
        if not reg["pasta_id"]:
            reg["pasta_id"] = criar_pasta(token, pid, m["pasta"]["id"])
            salvar(caminho_m, m)
        urls = {}
        nomes = ([os.path.basename(post["video"])] if "video" in post else
                 [f"{i:02d}-{os.path.basename(x)}" for i, x in enumerate(post["imagens"], 1)])
        originais = [post["video"]] if "video" in post else post["imagens"]
        for rel, abs_, nome in zip(originais, midias_do_post(plano, post), nomes):
            h = sha256_arquivo(abs_)
            a = reg["arquivos"].get(rel)
            if not a or a["sha256"] != h:
                a = {"id": enviar_arquivo(token, abs_, reg["pasta_id"], nome), "sha256": h, "compartilhado": False}
                reg["arquivos"][rel] = a
                salvar(caminho_m, m)
                print(f"enviado: {pid}/{nome}")
            if compartilhar and not a["compartilhado"]:
                api(token, "POST", f"/drive/v3/files/{a['id']}/permissions", {"role": "reader", "type": "anyone"})
                a["compartilhado"] = True
                salvar(caminho_m, m)
            urls[rel] = link(a["id"], formato)
        saida = os.path.join(base, f"urls-{pid}.json")
        salvar(saida, urls)
        print(f"links: {saida}" + ("" if compartilhar else " (arquivos PRIVADOS: o Drive precisa estar vinculado ao Metricool)"))


def cmd_revogar(plano):
    caminho_m = os.path.join(os.path.dirname(os.path.abspath(plano)), MANIFESTO)
    m = carregar(caminho_m)
    token = token_de_acesso()
    n = 0
    for reg in m["posts"].values():
        for a in reg["arquivos"].values():
            if a.get("compartilhado"):
                try:
                    api(token, "DELETE", f"/drive/v3/files/{a['id']}/permissions/anyoneWithLink")
                except Recusa as e:
                    if " 404 " not in str(e):
                        raise
                a["compartilhado"] = False
                n += 1
    salvar(caminho_m, m)
    print(f"acesso por link removido de {n} arquivo(s)")


def main(argv):
    if len(argv) < 2 or argv[1] not in ("auth", "enviar", "revogar"):
        print(__doc__, file=sys.stderr)
        return 2
    cmd, args, op, pos, i = argv[1], argv[2:], {}, [], 0
    while i < len(args):
        a = args[i]
        if a in ("--client-secret", "--approvals", "--pasta", "--posts", "--link"):
            if i + 1 >= len(args):
                print(f"{a} exige um valor", file=sys.stderr)
                return 2
            op[a] = args[i + 1]
            i += 2
        elif a == "--compartilhar-link":
            op[a] = True
            i += 1
        else:
            pos.append(a)
            i += 1
    try:
        if cmd == "auth":
            if "--client-secret" not in op or pos:
                print(__doc__, file=sys.stderr)
                return 2
            cmd_auth(op["--client-secret"])
        elif cmd == "enviar":
            if len(pos) != 1 or "--approvals" not in op:
                print(__doc__, file=sys.stderr)
                return 2
            formato = op.get("--link", "view")
            if formato not in ("view", "download"):
                raise Recusa("--link deve ser view ou download")
            posts = [p for p in op["--posts"].split(",") if p] if "--posts" in op else None
            cmd_enviar(pos[0], op["--approvals"], op.get("--pasta", "Clo Content"), posts, bool(op.get("--compartilhar-link")), formato)
        else:
            if len(pos) != 1:
                print(__doc__, file=sys.stderr)
                return 2
            cmd_revogar(pos[0])
    except (Recusa, RecusaAprovacao) as e:
        print(f"recusado: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
