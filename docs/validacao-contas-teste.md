# Roteiro de validação com contas de teste (agendador e Katana)

Objetivo: descobrir, com **contas de teste**, o que ainda não sabemos antes de escrever os adaptadores reais. Cada passo diz se ele **gasta crédito ou publica** e se **precisa da sua autorização**. Nada deste roteiro foi executado: ele foi escrito a partir de leitura (instruções do Higgsfield e páginas de fornecedores, tudo **não verificado** até o teste).

Legenda: **Não gasta crédito e não publica** = só leitura ou local. **Exige a sua autorização** = mexe numa conta, envia arquivo ou pode consumir crédito.

---

## Parte A. Escolha do agendador (Metricool como primeira tentativa)

### Por que o Metricool primeiro
- É o MCP **oficial** do fornecedor, lista agendamento para Instagram (Reels) e TikTok, e a documentação diz que funciona em qualquer plano, inclusive o grátis (não verificado). Fontes e ressalvas em `docs/agendadores.md`.
- **Limitação que muda o desenho:** o Metricool pede o vídeo por **URL pública** (link direto). Não aceita arquivo local nem anexo no chat. Então o fluxo precisa de um passo de hospedagem do vídeo, e isso é publicar o arquivo em algum lugar.
- Critério de decisão que vale mais que qualquer comparação: **usar a ferramenta que o seu sócio já paga**. Se ele já usa outra (Planoly, por exemplo), valide essa em vez do Metricool.

### Passos
1. **Decidir o candidato.** Não gasta crédito e não publica. Você me diz o que o sócio já usa e paga hoje (ver "Perguntas para você").
2. **Criar a conta de teste do agendador** (plano grátis, se existir). Exige a sua autorização, porque é criar conta e aceitar termos; eu não crio contas nem aceito termos por você.
3. **Conectar uma conta de teste de Instagram e uma de TikTok** (perfis descartáveis, nunca os reais do sócio). Exige a sua autorização: o login é seu.
4. **Instalar o MCP do agendador no Claude Code** seguindo a página oficial. Exige a sua autorização, porque dá a uma ferramenta acesso à conta.
5. **Ler a descrição das ferramentas expostas** (nomes, parâmetros, o que cada uma diz fazer) sem chamar nenhuma. Não gasta crédito e não publica. Conferir: aceita data/hora com fuso? devolve um ID? permite listar, alterar e cancelar?
6. **Preparar um vídeo de teste inofensivo** (5 a 10 s, sem rosto, sem música com direitos, sem dado do app) e decidir onde hospedá-lo como link público temporário. Exige a sua autorização por vídeo (hospedar é publicar). Apague o link depois.
7. **Agendar para longe no futuro**, por exemplo daqui a 25 dias, na conta de teste, só para ver a ferramenta aceitar. Exige a sua autorização. Como é conta de teste e a data é distante, nada vai ao ar; **cancele o agendamento no fim**.
8. **Consultar o post agendado** pela própria ferramenta: horário gravado no fuso certo (`-03:00`), legenda idêntica byte a byte, perfis corretos. Não gasta crédito e não publica (leitura).
9. **Alterar e cancelar** o post pela ferramenta e confirmar no app. Exige a sua autorização (mexe no agendamento de teste).
10. **Registrar as respostas** do checklist de `docs/agendadores.md` e só então escrever o adaptador atrás de `schedule.sh --scheduler <nome>` (a porta já existe, com o agendador falso nos testes).

### O que o sistema já garante, sem depender do agendador
Aprovação amarrada ao conteúdo (hash), simulação por padrão, idempotência, snapshot aprovado, recuperação de reserva órfã. O adaptador real precisa devolver **um único ID de agendamento** e, quando falhar, **não ter criado nada** (senão a reserva fica `em_andamento` e o usuário confere no app).

---

## Parte B. Validação do Katana (sem gastar crédito)

### O que as instruções do Higgsfield dizem (lidas em modo leitura)
- **Katana** edita o material que você envia, seguindo um briefing, ou refaz (remix) um vídeo de referência. O processamento roda no **sandbox do Higgsfield**, com ffmpeg, não no seu computador. Ele só **gera vídeo novo** (Seedance) quando o briefing exige; edição de material enviado "não precisa de geração".
- O workflow do Katana é **autônomo**: não pede confirmação de crédito e define o próprio teto interno. Por isso o nosso teto precisa ser aplicado **antes** (no briefing e na conferência do saldo), como o `budget.py` já faz com o Katana falso.
- **`ad-multiplier`** (4 a 30 s) é para **trocar pessoas, produtos, objetos, fundos ou textos** de um anúncio, mantendo movimento e cortes; também refaz o anúncio para outro mercado. **Não** serve para "cortar trechos diferentes do mesmo bruto". Consome crédito por vídeo gerado.
- **`video-montage`** monta clipes que já existem, troca a trilha e queima legendas, no sandbox, com ffmpeg. O custo desse tipo de etapa **não ficou claro** (não verificado).
- **Conclusão honesta:** para variantes por **cortes e ritmo**, o editor `local` já faz o trabalho a custo zero. O Katana tende a valer para **efeitos, tipografia e movimento** que o ffmpeg local não faz bem. Vale validar isso antes de investir no adaptador.
- **Aviso:** `get_katana_config` **não é consulta**: ela cria uma sessão e pode gastar a geração grátis. Nunca use para "ver a configuração".

### Passos
1. **Ver o saldo** com `balance`. Não gasta crédito e não publica. (Já testado: devolve créditos e plano.)
2. **Ler as instruções** do `/katana`, `ad-multiplier` e `video-montage`. Não gasta crédito e não publica. (Feito; resumo acima.)
3. **Cotar sem cobrar:** gerações aceitam `get_cost: true`, que devolve o custo sem criar job nem cobrar. Não gasta crédito e não publica. Serve para estimar o custo de qualquer geração antes de pedir. Para edição pura (sem geração) não há cotação conhecida: **não verificado**.
4. **Definir o teto do teste** (por exemplo, 0 crédito para a edição pura) e anotar saldo e `transactions` antes. Não gasta crédito e não publica.
5. **Enviar um clipe de teste** (5 a 10 s, sem dado sensível) por upload. Exige a sua autorização, porque envia um arquivo à sua conta. Conferir: o upload de arquivo local funciona de forma automatizada? o upload tem custo? (não verificado).
6. **Pedir uma edição pura do clipe** ("edite o material enviado: cortes e legenda; **não gere vídeo novo**; teto de 0 crédito"). Exige a sua autorização, porque o Katana é autônomo e não pede confirmação; a única proteção é o teto no briefing e a conferência depois.
7. **Conferir o depois:** `balance` e `transactions` de novo. Pass se o saldo não mudou (ou mudou só no que você aceitou). Se mudou, parar e registrar quanto e por quê.
8. **Baixar o resultado de forma automatizada:** confirmar se a saída vem como URL baixável. Esta é a terceira pergunta aberta do projeto (não verificado). Exige a sua autorização se envolver nova execução.
9. **Só depois, e só se o passo 7 passou**, decidir se vale testar uma geração real pequena, sempre com `get_cost` antes e confirmação do total.

### O que registrar
Saldo antes/depois, o que o Katana fez de fato (cortes? geração?), tempo, se o resultado foi baixável, e a qualidade comparada ao `edit-recorded` local. Com isso decidimos se o adaptador real compensa.

---

## Perguntas para você
1. **Qual ferramenta de agendamento o seu sócio já paga ou usa?** (Metricool, Planoly, outra, nenhuma). Isso decide o candidato.
2. **Vocês têm perfis de teste** de Instagram e de TikTok, ou preferem que eu monte o roteiro de criação deles?
3. **Onde hospedar o vídeo de teste** como link público temporário? (Drive com "qualquer pessoa com o link", outro serviço, ou prefere pular a hospedagem e testar só a leitura das ferramentas.)
4. **Quer incluir o Katana no teste agora** (passos 5 a 8, com teto de 0 crédito) ou só depois do agendador?
5. **Qual clipe de teste** posso usar (sem rosto e sem dado do app)?
