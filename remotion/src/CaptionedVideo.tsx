import React from 'react';
import {agruparPalavras, grupoAtual, Palavra} from './grupos';
import {AbsoluteFill, OffthreadVideo, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';


// Contrato de scripts/to_remotion_input.py (schemas/remotion-input.schema.json) mais a duração em segundos,
// que scripts/render-remotion.sh mede no vídeo e acrescenta.
export type CaptionedVideoProps = {
  video: string;
  largura: number;
  altura: number;
  fps: number;
  duracao_s: number;
  estilo: string;
  palavras: Palavra[];
};

type Estilo = {fonte: number; palavrasPorGrupo: number; cor: string; destaque: string; fundo: string; contorno: number; baixo: number};

// Os três estilos espelham os do subtitles.sh (padrao, destaque, discreto).
const ESTILOS: Record<string, Estilo> = {
  padrao: {fonte: 64, palavrasPorGrupo: 3, cor: '#FFFFFF', destaque: '#FFE14D', fundo: 'transparent', contorno: 8, baixo: 380},
  destaque: {fonte: 88, palavrasPorGrupo: 2, cor: '#FFFFFF', destaque: '#FFD400', fundo: 'transparent', contorno: 10, baixo: 420},
  discreto: {fonte: 48, palavrasPorGrupo: 4, cor: '#FFFFFF', destaque: '#FFFFFF', fundo: 'rgba(0,0,0,0.45)', contorno: 0, baixo: 300},
};

const FOLGA_S = 0.15; // o grupo continua na tela um instante depois da última palavra

export const CaptionedVideo: React.FC<CaptionedVideoProps> = ({video, palavras, estilo}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const agora = frame / fps;
  const e = ESTILOS[estilo] ?? ESTILOS.padrao;

  const grupo = grupoAtual(agruparPalavras(palavras, e.palavrasPorGrupo), agora, FOLGA_S);

  return (
    <AbsoluteFill style={{backgroundColor: 'black'}}>
      <OffthreadVideo src={staticFile(video)} style={{width: '100%', height: '100%', objectFit: 'cover'}} />
      {grupo ? (
        <AbsoluteFill style={{justifyContent: 'flex-end', alignItems: 'center', paddingBottom: e.baixo}}>
          <div
            style={{
              display: 'flex',
              flexWrap: 'wrap',
              justifyContent: 'center',
              gap: '0 30px',
              maxWidth: 940,
              padding: e.fundo === 'transparent' ? 0 : '14px 28px',
              borderRadius: 18,
              backgroundColor: e.fundo,
              fontFamily: 'Arial Black, Arial, Helvetica, sans-serif',
              fontWeight: 900,
              fontSize: e.fonte,
              lineHeight: 1.15,
              textAlign: 'center',
              textTransform: 'uppercase',
            }}
          >
            {grupo.map((p, i) => {
              const ativa = agora >= p.inicio_s && agora <= p.fim_s;
              const entrada = spring({frame: frame - Math.round(p.inicio_s * fps), fps, config: {damping: 14, stiffness: 180}});
              const escala = ativa ? interpolate(entrada, [0, 1], [0.9, 1.04]) : 1;
              return (
                <span
                  key={`${p.inicio_s}-${i}`}
                  style={{
                    color: ativa ? e.destaque : e.cor,
                    transform: `scale(${escala})`,
                    WebkitTextStroke: e.contorno ? `${e.contorno}px black` : undefined,
                    paintOrder: 'stroke fill',
                    display: 'inline-block',
                  }}
                >
                  {p.texto}
                </span>
              );
            })}
          </div>
        </AbsoluteFill>
      ) : null}
    </AbsoluteFill>
  );
};
