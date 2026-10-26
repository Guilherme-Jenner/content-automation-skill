#!/usr/bin/env python3
"""Log de agendamentos: impede agendar o mesmo post duas vezes e entrega ao agendador um snapshot APROVADO.

  schedule_log.py status    <plano> <post-id> <log>   -> livre | em_andamento | agendado | conflito
  schedule_log.py reserve   <plano> <post-id> <log> <agendador> <dir-aprovacoes>
                            verifica a aprovação SOB A TRAVA, reserva e imprime (última linha) a pasta do snapshot
  schedule_log.py commit    <plano> <post-id> <log> <id_externo>
  schedule_log.py release   <plano> <post-id> <log> [--conferido]
                            libera uma reserva em_andamento; reserva recente exige --conferido
  schedule_log.py supersede <log> <post-id>           marca o agendamento anterior do post como substituído
  schedule_log.py describe  <plano> <post-id>         resumo do post para mostrar ao usuário

Chave = sha256(conteúdo) + sha256(vídeo). Além disso, um post_id com agendamento ativo e conteúdo DIFERENTE só
pode ser reagendado depois de `supersede` (o usuário cancela o anterior no agendador e confirma).
O snapshot (pasta .snapshots/<post-id>-<chave>/) tem o vídeo e o conteúdo exatamente como aprovados; o
agendador deve usar só ele. Todos os comandos que escrevem usam trava de arquivo (<log>.lock) e escrita atômica.
"""
import hashlib
import json
import os
import shutil
import sys
import tempfile
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from approval import Recusa as RecusaAprovacao  # noqa: E402
from approval import achar_post, sha256_arquivo, sha256_conteudo, sha256_midia, verificar  # noqa: E402
from budget import travar  # noqa: E402
from validate_schedule import midias_do_post  # noqa: E402

JA_AGENDADO = 4
ATIVOS = ("agendado", "em_andamento")
IDADE_MINIMA_PARA_LIBERAR = timedelta(minutes=10)


class Recusa(Exception):
    codigo = 1


def chave_atual(plano, post_id):
    post = achar_post(plano, post_id)
    return post, f"{sha256_conteudo(post)}:{sha256_midia(plano, post)}"


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
    return datetime.now(timezone.utc)


def pasta_snapshot(log, post_id, chave):
    return os.path.join(os.path.dirname(os.path.abspath(log)), ".snapshots", f"{post_id}-{chave.split(':')[0][:12]}")


def limpar_snapshot(log, post_id, chave):
    shutil.rmtree(pasta_snapshot(log, post_id, chave), ignore_errors=True)


def ativo_do_post(dados, post_id, exceto_chave=None):
    for k, e in dados["agendamentos"].items():
        if e["post_id"].lower() == post_id.lower() and e["estado"] in ATIVOS and k != exceto_chave:
            return k, e
    return None, None


def cmd_status(plano, post_id, log):
    _, chave = chave_atual(plano, post_id)
    with travar(log):
        dados = carregar(log)
    entrada = dados["agendamentos"].get(chave)
    if entrada and entrada["estado"] in ATIVOS:
        print(entrada["estado"])
    elif ativo_do_post(dados, post_id, chave)[0]:
        print("conflito")
    else:
        print("livre")


def cmd_reserve(plano, post_id, log, agendador, aprovacoes):
    with travar(log):
        # A verificação acontece aqui, sob a trava, e a chave vem do registro aprovado: não há janela entre
        # "verificar" e "usar". O agendador recebe um snapshot copiado e conferido, não o plano vivo.
        post, reg = verificar(plano, post_id, aprovacoes)
        chave = f"{reg['sha256_conteudo']}:{reg['sha256_video']}"
        dados = carregar(log)
        existente = dados["agendamentos"].get(chave)
        if existente and existente["estado"] in ATIVOS:
            e = Recusa(
                f"o post '{post_id}' já agendado" + (f" em {existente['atualizado_em']} ({existente.get('id_externo')})" if existente["estado"] == "agendado"
                else " ou em andamento por outro processo; conferir no agendador antes de liberar (release)")
            )
            e.codigo = JA_AGENDADO
            raise e
        k, outro = ativo_do_post(dados, post_id, chave)
        if k:
            e = Recusa(
                f"o post '{post_id}' já tem um agendamento com conteúdo diferente (id externo: {outro.get('id_externo')}). "
                "Cancele o anterior no agendador e registre a substituição com: schedule_log.py supersede <log> " + post_id
            )
            e.codigo = JA_AGENDADO
            raise e
        snap = pasta_snapshot(log, post_id, chave)
        shutil.rmtree(snap, ignore_errors=True)
        os.makedirs(snap)
        origens = midias_do_post(plano, post)
        if "video" in post:
            nomes = ["video" + os.path.splitext(origens[0])[1]]
        else:   # carrossel: imagem-01.png, imagem-02.png... na ordem aprovada
            nomes = [f"imagem-{i:02d}" + os.path.splitext(o)[1].lower() for i, o in enumerate(origens, 1)]
        for origem, nome in zip(origens, nomes):
            shutil.copyfile(origem, os.path.join(snap, nome))
        hashes = [sha256_arquivo(os.path.join(snap, n)) for n in nomes]
        copiado = hashes[0] if "video" in post else hashlib.sha256("\n".join(hashes).encode("utf-8")).hexdigest()
        if copiado != reg["sha256_video"]:
            shutil.rmtree(snap, ignore_errors=True)
            raise Recusa("a mídia mudou durante a cópia; peça uma nova aprovação")
        with open(os.path.join(snap, "post.json"), "wb") as f:
            f.write((json.dumps(post, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
        with open(os.path.join(snap, "aprovado.json"), "wb") as f:
            f.write((json.dumps({"post_id": post_id, "sha256_video": reg["sha256_video"], "sha256_conteudo": reg["sha256_conteudo"]}) + "\n").encode("utf-8"))
        dados["agendamentos"][chave] = {
            "post_id": post_id,
            "estado": "em_andamento",
            "agendador": agendador,
            "data_hora": post["data_hora"],
            "perfis": post["perfis"],
            "id_externo": None,
            "atualizado_em": agora().isoformat(),
        }
        salvar(log, dados)
    print(snap)


def cmd_commit(plano, post_id, log, id_externo):
    _, chave = chave_atual(plano, post_id)
    with travar(log):
        dados = carregar(log)
        entrada = dados["agendamentos"].get(chave)
        if not entrada or entrada["estado"] != "em_andamento":
            raise Recusa(f"não há reserva em andamento para o post '{post_id}'")
        entrada.update({"estado": "agendado", "id_externo": id_externo, "atualizado_em": agora().isoformat()})
        salvar(log, dados)
    limpar_snapshot(log, post_id, chave)
    print(f"agendado: {post_id} ({id_externo})")


def cmd_release(plano, post_id, log, *flags):
    conferido = "--conferido" in flags
    _, chave = chave_atual(plano, post_id)
    with travar(log):
        dados = carregar(log)
        entrada = dados["agendamentos"].get(chave)
        if not entrada or entrada["estado"] != "em_andamento":
            raise Recusa(f"não há reserva em andamento para o post '{post_id}'; nada foi liberado")
        idade = agora() - datetime.fromisoformat(entrada["atualizado_em"])
        if idade < IDADE_MINIMA_PARA_LIBERAR and not conferido:
            raise Recusa(
                f"a reserva é recente ({int(idade.total_seconds() // 60)} min): o processo pode ainda estar em andamento. "
                "Antes de liberar, conferir no agendador (app) se o post foi criado; "
                "se tiver certeza de que nada foi agendado, rode de novo com --conferido"
            )
        del dados["agendamentos"][chave]
        salvar(log, dados)
    limpar_snapshot(log, post_id, chave)
    print(f"reserva liberada: {post_id}")


def cmd_supersede(log, post_id):
    with travar(log):
        dados = carregar(log)
        n = 0
        for e in dados["agendamentos"].values():
            if e["post_id"].lower() == post_id.lower() and e["estado"] in ATIVOS:
                e["estado"] = "substituido"
                e["atualizado_em"] = agora().isoformat()
                n += 1
        if not n:
            raise Recusa(f"não há agendamento ativo do post '{post_id}' para substituir")
        salvar(log, dados)
    print(f"substituído: {n} agendamento(s) do post {post_id} (confirme que foram cancelados no agendador)")


def cmd_describe(plano, post_id):
    post = achar_post(plano, post_id)
    perfis = ", ".join(f"{p['rede']}:{p['conta']}" for p in post["perfis"])
    linhas = [
        f"Post {post['id']}",
        f"Vídeo: {post['video']}" if "video" in post else f"Carrossel ({len(post['imagens'])} imagens, nesta ordem): " + ", ".join(post["imagens"]),
        f"Data/hora: {post['data_hora']} (America/Sao_Paulo)",
        f"Perfis: {perfis}",
        f"Hashtags: {' '.join(post['hashtags']) or '(nenhuma)'}",
        "Conteúdo gerado/alterado por IA: " + ("sim (será declarado)" if post.get("conteudo_ia") else "não"),
        "Legenda:",
        post["legenda"],
    ]
    if post.get("titulo_tiktok"):
        linhas.insert(-2, "Título do TikTok: " + post["titulo_tiktok"])
    sys.stdout.buffer.write(("\n".join(linhas) + "\n").encode("utf-8"))


COMANDOS = {
    "status": (cmd_status, 3, 3),
    "reserve": (cmd_reserve, 5, 5),
    "commit": (cmd_commit, 4, 4),
    "release": (cmd_release, 3, 4),
    "supersede": (cmd_supersede, 2, 2),
    "describe": (cmd_describe, 2, 2),
}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMANDOS:
        print(__doc__, file=sys.stderr)
        return 2
    fn, minimo, maximo = COMANDOS[argv[1]]
    if not minimo <= len(argv) - 2 <= maximo:
        print(f"uso incorreto de '{argv[1]}'", file=sys.stderr)
        return 2
    try:
        fn(*argv[2:])
    except Recusa as e:
        print(f"recusado: {e}", file=sys.stderr)
        return e.codigo
    except RecusaAprovacao as e:
        print(f"recusado: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
