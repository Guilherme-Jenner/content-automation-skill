# Guia de instalação e atualização (Mac)

## 1. Dependências (uma vez)
1. Instale o Homebrew (https://brew.sh) se ainda não tiver.
2. Ferramentas:
   ```bash
   brew install ffmpeg whisper-cpp
   ```
   Para o acabamento com Remotion (opcional): `brew install node` e, uma vez, `bash scripts/setup-remotion.sh` (baixa pacotes e um Chrome headless para `~/.cache/clo/remotion`; sobrevive às atualizações do plugin).
3. Modelo do Whisper (uma vez):
   ```bash
   mkdir -p ~/.cache/clo
   curl -L -o ~/.cache/clo/ggml-small.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
   ```
4. Depois de instalar o plugin, peça ao Claude para rodar a checagem (`check-deps.sh`) e confirmar que está tudo certo.

## 2. Instalar o plugin
Dentro do Claude Code:
```
/plugin marketplace add OWNER/REPO
/plugin install clo-content-pipeline@clo-tools
```
(`OWNER/REPO` é o endereço do repositório no GitHub. Se o repositório for privado, entre antes no GitHub pelo terminal com `gh auth login` e depois `gh auth setup-git`, para o Claude Code conseguir baixar e atualizar.)

Para conferir, no terminal: `claude plugin list`.

## 3. Receber atualizações sem reinstalar
A atualização automática de marketplaces de terceiros vem **desligada**. Ligue uma vez:
1. No Claude Code, abra `/plugin`, vá na aba **Marketplaces**, escolha `clo-tools` e selecione **Enable auto-update**.
2. A partir daí o Claude Code procura versões novas ao abrir uma sessão. A versão nova vale na **próxima sessão** (ou com `/reload-plugins`).

Atualizar na hora, sem esperar:
```
/plugin marketplace update clo-tools
```
Só chega atualização quando o `version` do plugin muda (veja `docs/publicacao.md`).

## 4. Primeiro uso
Abra uma pasta de trabalho e peça: "quero criar um vídeo para o Clo App". A skill `content-pipeline` conduz o resto e pergunta, no início, se você quer definir um teto de créditos (é opcional).
