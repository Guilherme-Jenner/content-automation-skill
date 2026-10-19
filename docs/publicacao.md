# Publicar e atualizar o plugin

O repositório é, ao mesmo tempo, o **plugin** e o **marketplace** `clo-tools` (`.claude-plugin/marketplace.json`, com o plugin na raiz: `"source": "."`).

## Publicar pela primeira vez
1. `claude plugin validate .` na raiz do repositório (o validador não pega tudo: teste a instalação de verdade).
2. Faça o push para o GitHub.
3. Numa máquina limpa (ou outra conta): `claude plugin marketplace add Guilherme-Jenner/content-automation-skill`, depois `claude plugin install clo-content-pipeline@clo-tools` e `claude plugin list`.
4. Se o repositório for privado (**repositório privado**), cada pessoa precisa de credenciais do GitHub na máquina (`gh auth login` e `gh auth setup-git`); sem elas a atualização falha em silêncio e a cópia antiga continua funcionando.

## Lançar uma atualização (por exemplo, quando o agendamento ficar pronto)
1. Termine a mudança e rode `bash tests/run.sh` (tem de ficar verde).
2. Suba o `version` em `.claude-plugin/plugin.json` (semântico: `0.2.0` → `0.3.0` para recurso novo, `0.2.1` para correção). Escreva o que mudou em `CHANGELOG.md`, numa seção `## <versão>`. Um teste confere que as duas coisas batem.
3. Faça o commit e o push.
4. Quem ligou a atualização automática recebe a versão na **próxima sessão** (ou com `/reload-plugins`). Quem não ligou roda `/plugin marketplace update clo-tools`.

Sem mudar o `version`, **ninguém** recebe nada, mesmo com commits novos. Não coloque `version` também na entrada do `marketplace.json`: se estiver nos dois lugares, vale o do `plugin.json` sem aviso.

## Uma pessoa já em uma sessão
A sessão em andamento mantém a versão que carregou. Para pegar a nova sem fechar: `/plugin marketplace update clo-tools` e depois `/reload-plugins`.

## Avisos
- Não grave dados dentro da pasta do plugin: o caminho (`${CLAUDE_PLUGIN_ROOT}`) muda a cada versão.
- O Remotion tem licença própria; veja `remotion/README.md`.
