export type Palavra = {texto: string; inicio_s: number; fim_s: number};

// Pausa (segundos) entre duas palavras a partir da qual começa um grupo novo: não juntar o fim de uma frase com o início da outra.
export const PAUSA_QUEBRA_S = 0.3;

// Agrupa as palavras em blocos de até `porGrupo` (o que aparece junto na tela), sem atravessar uma pausa de frase.
export function agruparPalavras(palavras: Palavra[], porGrupo: number): Palavra[][] {
  const grupos: Palavra[][] = [];
  for (const p of palavras) {
    const atual = grupos[grupos.length - 1];
    const anterior = atual ? atual[atual.length - 1] : null;
    if (atual && atual.length < porGrupo && anterior && p.inicio_s - anterior.fim_s <= PAUSA_QUEBRA_S) {
      atual.push(p);
    } else {
      grupos.push([p]);
    }
  }
  return grupos;
}

// Grupo que deve estar na tela em `agora` (segundos): o ÚLTIMO que já começou, e só enquanto não passou
// do fim da sua última palavra mais a folga. Assim, na troca de grupos, o novo grupo vence o anterior.
export function grupoAtual(grupos: Palavra[][], agora: number, folga: number): Palavra[] | null {
  let escolhido: Palavra[] | null = null;
  for (const g of grupos) {
    if (agora >= g[0].inicio_s) {
      escolhido = g;
    }
  }
  if (escolhido === null) {
    return null;
  }
  return agora <= escolhido[escolhido.length - 1].fim_s + folga ? escolhido : null;
}
