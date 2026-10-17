#!/usr/bin/env python3
"""Log de agendamentos: impede agendar o mesmo post (mesmo vídeo + mesmo conteúdo) duas vezes.

  schedule_log.py status   <plano> <post-id> <log>              -> livre | em_andamento | agendado
  schedule_log.py reserve  <plano> <post-id> <log> <agendador>   -> reserva; código 4 se já agendado/em andamento
  schedule_log.py commit   <plano> <post-id> <log> <id_externo>  -> marca como agendado
  schedule_log.py release  <plano> <post-id> <log>               -> libera a reserva (falha do agendador, ou processo que caiu)
  schedule_log.py describe <plano> <post-id>                     -> resumo do post para mostrar ao usuário

A chave é sha256(conteúdo) + sha256(vídeo): mudar a legenda, o horário, os perfis ou o vídeo gera outra chave.
Todos os comandos que escrevem usam trava de arquivo (<log>.lock); o log é gravado de forma atômica.
"""
import json
import os
import sys
import tempfile
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from approval import achar_post, sha256_arquivo, sha256_conteudo  # noqa: E402
from budget import travar  # noqa: E402
from validate_schedule import caminho_do_video  # noqa: E402

JA_AGENDADO = 4


class Recusa(Exception):
    codigo = 1


def chave_do_post(plano, post_id):
    post = achar_post(plano, post_id)
    return post, f"{sha256_conteudo(post)}:{sha256_arquivo(caminho_do_video(plano, post['video']))}"


def carregar(log):
    if not os.path.exists(log):
        return {"agendamentos": {}}
    try:
        with open(log, encoding="utf-8") as f:
            dados = json.load(f)
        if not isinstance(dados.get("agendamentos"), dict):
            raise ValueError
        return dados
    except (ValueError, UnicodeDecodeError):
        raise Recusa(f"o log de agendamentos está corrompido: {log}")


def salvar(log, dados):
    pasta = os.path.dirname(os.path.abspath(log))
    os.makedirs(pasta, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=pasta, prefix=".schedule-log-", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write((json.dumps(dados, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, log)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def agora():
    return datetime.now(timezone.utc).isoformat()


def cmd_status(plano, post_id, log):
    _, chave = chave_do_post(plano, post_id)
    with travar(log):
        entrada = carregar(log)["agendamentos"].get(chave)
    print(entrada["estado"] if entrada else "livre")


def cmd_reserve(plano, post_id, log, agendador):
    post, chave = chave_do_post(plano, post_id)
    with travar(log):
        dados = carregar(log)
        existente = dados["agendamentos"].get(chave)
        if existente:
            if existente["estado"] == "agendado":
                e = Recusa(f"o post '{post_id}' já agendado em {existente['atualizado_em']} ({existente.get('agendador')}, {existente.get('id_externo')})")
            else:
                e = Recusa(
                    f"o post '{post_id}' já agendado ou em andamento por outro processo; se esse processo caiu, "
                    "libere com: schedule_log.py release"
                )
            e.codigo = JA_AGENDADO
            raise e
        dados["agendamentos"][chave] = {
            "post_id": post_id,
            "estado": "em_andamento",
            "agendador": agendador,
            "data_hora": post["data_hora"],
            "perfis": post["perfis"],
            "id_externo": None,
            "atualizado_em": agora(),
        }
        salvar(log, dados)
    print(f"reservado: {post_id}")


def cmd_commit(plano, post_id, log, id_externo):
    _, chave = chave_do_post(plano, post_id)
    with travar(log):
        dados = carregar(log)
        entrada = dados["agendamentos"].get(chave)
        if not entrada or entrada["estado"] != "em_andamento":
            raise Recusa(f"não há reserva em andamento para o post '{post_id}'")
        entrada.update({"estado": "agendado", "id_externo": id_externo, "atualizado_em": agora()})
        salvar(log, dados)
    print(f"agendado: {post_id} ({id_externo})")


def cmd_release(plano, post_id, log):
    _, chave = chave_do_post(plano, post_id)
    with travar(log):
        dados = carregar(log)
        entrada = dados["agendamentos"].get(chave)
        if entrada and entrada["estado"] == "em_andamento":
            del dados["agendamentos"][chave]
            salvar(log, dados)
    print(f"reserva liberada: {post_id}")


def cmd_describe(plano, post_id):
    post = achar_post(plano, post_id)
    perfis = ", ".join(f"{p['rede']}:{p['conta']}" for p in post["perfis"])
    linhas = [
        f"Post {post['id']}",
        f"Vídeo: {post['video']}",
        f"Data/hora: {post['data_hora']} (America/Sao_Paulo)",
        f"Perfis: {perfis}",
        f"Hashtags: {' '.join(post['hashtags']) or '(nenhuma)'}",
        "Legenda:",
        post["legenda"],
    ]
    sys.stdout.buffer.write(("\n".join(linhas) + "\n").encode("utf-8"))


COMANDOS = {
    "status": (cmd_status, 3),
    "reserve": (cmd_reserve, 4),
    "commit": (cmd_commit, 4),
    "release": (cmd_release, 3),
    "describe": (cmd_describe, 2),
}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMANDOS:
        print(__doc__, file=sys.stderr)
        return 2
    fn, n = COMANDOS[argv[1]]
    if len(argv) - 2 != n:
        print(f"uso incorreto de '{argv[1]}'", file=sys.stderr)
        return 2
    try:
        fn(*argv[2:])
    except Recusa as e:
        print(f"recusado: {e}", file=sys.stderr)
        return e.codigo
    except Exception as e:  # post inexistente, id inválido etc. vêm de approval.Recusa
        if e.__class__.__name__ == "Recusa":
            print(f"recusado: {e}", file=sys.stderr)
            return 1
        raise
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
