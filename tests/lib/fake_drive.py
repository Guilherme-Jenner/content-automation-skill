#!/usr/bin/env python3
"""Servidor FALSO da API do Google Drive para os testes (nunca usa rede real).
Uso: fake_drive.py <arquivo-de-log> <arquivo-da-porta>. Registra uma linha JSON por requisição."""
import http.server
import json
import re
import sys

LOG, PORTA = sys.argv[1], sys.argv[2]
contador = {"n": 0}


class H(http.server.BaseHTTPRequestHandler):
    def _responde(self, obj, codigo=200):
        corpo = json.dumps(obj).encode()
        self.send_response(codigo)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(corpo)))
        self.end_headers()
        self.wfile.write(corpo)

    def _lê(self):
        n = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(n)

    def _registra(self, extra=None):
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps({"m": self.command, "p": self.path, "auth": self.headers.get("Authorization"), **(extra or {})}) + "\n")

    def do_POST(self):
        corpo = self._lê()
        if self.path.startswith("/token"):
            self._registra()
            return self._responde({"access_token": "tok-renovado"})
        contador["n"] += 1
        novo = f"id{contador['n']}"
        if self.path.startswith("/upload/drive/v3/files"):
            m = re.search(rb'\{"name": "([^"]*)", "parents": \["([^"]*)"\]\}', corpo)
            self._registra({"nome": m.group(1).decode() if m else None, "pai": m.group(2).decode() if m else None, "bytes": len(corpo)})
        elif re.match(r"/drive/v3/files/[^/]+/permissions", self.path):
            self._registra({"perm": json.loads(corpo)})
        else:
            meta = json.loads(corpo or b"{}")
            self._registra({"pasta": meta.get("name"), "pai": (meta.get("parents") or [None])[0]})
        self._responde({"id": novo})

    def do_DELETE(self):
        self._registra()
        self._responde({})

    def log_message(self, *a):
        pass


srv = http.server.HTTPServer(("127.0.0.1", 0), H)
open(PORTA, "w").write(str(srv.server_address[1]))
srv.serve_forever()
