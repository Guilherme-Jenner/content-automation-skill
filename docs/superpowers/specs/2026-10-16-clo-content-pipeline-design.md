# Clo Content Pipeline — Design

Data: 2026-10-16 · Status: **rascunho para aprovação**

## Intenção
A CLO (2 pessoas) precisa produzir vídeos curtos para o Clo App sem custo duplo de API. A solução é um **plugin do Claude Code** com skills, rodando no plano do Claude já contratado. O repositório também é projeto de portfólio: engenharia, documentação e testes importam. O sócio de marketing usa **Mac**; o desenvolvimento acontece em **Windows** (Git Bash/PowerShell).

## Objetivos
- Uma skill orquestradora (a única usada pelo sócio) conduz: roteiro → [modo] → edição → agendamento → aprovação humana.
- Modo **gerado** (Higgsfield via MCP, com teto de créditos) e modo **gravado** (shot list; o usuário informa o caminho do arquivo).
- Cada etapa é uma skill testável isoladamente.
- Instalável no Mac via marketplace do Claude Code a partir de repo privado.

## Não-objetivos
- Sem chaves de API próprias nem serviços pagos nos testes.
- Sem publicação automática: **nunca** agenda/publica sem aprovação humana explícita.
- Sem edição manual tipo editor de vídeo; cortes criativos são propostos e aprovados.

## Anti-objetivos (falha mesmo que "funcione")
- Agendar algo diferente do que foi aprovado.
- Gastar créditos acima do teto.
- Scripts que só rodam no Windows.

## Decisões tomadas (pelo usuário)
- Plugin + skills; repositório novo, separado do Clo-Ops.
- Ordem: (1) roteiro e edição do gravado, (2) agendamento, (3) geração Higgsfield, (4) empacotamento.
- Remotion existe na estrutura desde o início; **qualidade visual é o último passo**, após todo o resto validado.
- Entrada de vídeo gravado por caminho de arquivo local.

## Decisões do builder (a confirmar)
- Lógica em **bash/POSIX + ffmpeg**; parsing (silêncio, SRT, JSON) em **python3 stdlib** (já presente no Mac com Xcode CLT).
- Transcrição local com **whisper.cpp** (`brew install whisper-cpp` no Mac).
- Testes com fixtures geradas pelo `ffmpeg` (`lavfi`), **transcritor falso**, **gerador falso** e **agendador falso**.

## Estrutura
```
.claude-plugin/{plugin.json,marketplace.json}
skills/{content-pipeline,script-storyboard,edit-recorded,edit-generated,generate-clips,schedule-post}/SKILL.md
scripts/lib/  scripts/{silence-cut,subtitles,normalize-audio,reframe-9x16}.sh
remotion/     (template mínimo de legenda; polimento por último)
schemas/      (storyboard, shot list, plano de cortes, aprovação)
tests/{fixtures,fakes,run.sh}
docs/         README.md
```

## Interfaces (portas e fakes)
- **Transcritor**: real (whisper.cpp) / falso (JSON fixo).
- **Gerador**: real (Higgsfield) / falso (vídeo de exemplo + custo fictício).
- **Agendador**: real (adaptador por MCP) / falso (registra o que seria publicado).
- **Edição → Remotion**: JSON com transcrição, tempos e estilo.

## Atratividade embasada em pesquisa (adendo de 2026-10-16)
Roteiro **e** edição criativa devem buscar prender a atenção de quem assiste, e isso deve ser **embasado em dados reais**, não em palpite.
- Nova skill `research-trends`, usada pelo roteiro e pela edição **antes** de propor qualquer coisa: entende a ideia/proposta do vídeo, pesquisa na web (práticas de retenção, hooks, ritmo, legendas, duração, tendências do nicho e da plataforma) e grava `research.json`.
- Regra: **nenhuma afirmação sem fonte** (URL + data de acesso). O que não tiver fonte vira "hipótese", marcado como tal. Cada achado traz a *aplicação* no vídeo (ex.: "hook em ≤3 s", "corte a cada ~2 s").
- Roteiro: o hook e a estrutura propostos citam os achados que os justificam.
- Edição: a skill monta um **brief de edição** (ideia e proposta do vídeo → ritmo, cortes, legendas, zoom, trilha) amarrado à pesquisa; as propostas criativas continuam passando por aprovação humana.
- Limite assumido: pesquisa web traz guias, estudos e artigos, não métricas privadas. Quando houver acesso (ex.: Metricool), os dados do **próprio perfil** da CLO entram como fonte mais forte.

## Edição do gravado (etapa de maior risco)
1. Validar entrada (`ffprobe`). 2. Transcrever. 3. Detectar silêncios. 4. Skill propõe **plano de cortes** (arquivo JSON); humano aprova. 5. Aplicar cortes (recusa sem plano aprovado). 6. Legenda SRT. 7. Normalizar áudio (~-14 LUFS). 8. 9:16 (1080×1920, sem esticar).

## Agendamento e aprovação
- Skill propõe dias/horários (fuso `America/Sao_Paulo`) a partir de config de cadência.
- Aprovação grava arquivo com **hash** de vídeo + legenda + horário + perfis. O script recusa se faltar ou se algo mudou. Padrão é *dry-run*; sem duplicidade.
- A validar com conta de teste: qual MCP aceita vídeo + data/hora + perfis; arquivo local ou só URL pública (hospedagem temporária só com permissão explícita).
- **Plano B**: pacote pronto (vídeo, legenda, horário) para agendar manualmente no Instagram/TikTok.

## Critérios de teste (resumo)
Silêncio: intervalos corretos, duração ±0,1 s, entrada sem silêncio intacta, arquivo ruim → erro claro. Legenda: SRT ordenado, tempos dentro da duração. 9:16: `ffprobe` confere. Áudio: LUFS-alvo. Aprovação: sem arquivo/hash divergente → recusa. Roteiro: schemas válidos, soma das durações = alvo. Portabilidade: `shellcheck` limpo; rodar no Git Bash e, para integração, no Mac.

## Em aberto
- Instalar `ffmpeg`, `shellcheck` e `whisper.cpp` no Windows para testes reais.
- Testes com `ffmpeg` real no Mac do sócio.
- Escolha do MCP de agendamento e validações do Higgsfield (saldo, custo prévio, download).
