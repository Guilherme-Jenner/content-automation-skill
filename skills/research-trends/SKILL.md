---
name: research-trends
description: Pesquisa na web, com fontes, o que atrai e retém quem assiste a vídeos curtos para a proposta do vídeo. Use antes de propor roteiro, hook ou edição criativa.
---

# Pesquisa embasada para roteiro e edição

Objetivo: o roteiro e a edição precisam **atrair e prender a atenção**, e isso deve se apoiar em dados reais, não em palpite. Converse em português do Brasil.

## 1. Entenda a proposta
Se ainda não estiver claro, pergunte (uma pergunta por vez): qual é a ideia do vídeo, para quem, em qual plataforma (Instagram Reels, TikTok) e qual ação esperamos de quem assiste.

## 2. Pesquise
Use a busca na web (WebSearch/WebFetch) para levantar, para **essa proposta e plataforma**:
- o que decide se a pessoa continua assistindo (hook, primeiros segundos);
- ritmo de cortes, duração ideal, uso de legenda, texto na tela e trilha;
- tendências e formatos atuais do nicho;
- se houver acesso a métricas do perfil da CLO (ex.: Metricool), use-as: são a fonte mais forte.
Prefira fontes recentes e primárias (documentação das plataformas, estudos, relatórios). Anote a data de acesso.

## 3. Registre em `research.json`
Formato em `schemas/research.schema.json`: cada achado tem `afirmacao`, `tipo` (`fato` ou `hipotese`), `fonte_url`, `fonte_titulo`, `data_acesso` e `aplicacao` (o que isso muda no vídeo).
- Só marque `fato` quando houver fonte. O que não tiver fonte é `hipotese`, dita como tal.
- **Nunca invente** fonte, número ou estudo. Se a busca falhar ou não achar nada confiável, diga isso ao usuário e proponha só hipóteses.

## 4. Valide e apresente
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/check_research.py" research.json
```
Corrija até passar. Depois mostre um resumo curto: os achados mais úteis, a fonte de cada um e o que mudam no roteiro/edição. As propostas seguintes devem citar o achado que as justifica.
