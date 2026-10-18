import React from 'react';
import {Composition} from 'remotion';
import {CaptionedVideo, CaptionedVideoProps} from './CaptionedVideo';

// Propriedades padrão só para o Remotion Studio; o render real recebe o remotion-input.json por --props.
const exemplo: CaptionedVideoProps = {
  video: 'entrada.mp4',
  largura: 1080,
  altura: 1920,
  fps: 30,
  duracao_s: 5,
  estilo: 'padrao',
  palavras: [
    {texto: 'Sua', inicio_s: 0.2, fim_s: 0.6},
    {texto: 'rotina', inicio_s: 0.6, fim_s: 1.1},
    {texto: 'organizada', inicio_s: 1.1, fim_s: 1.9},
  ],
};

export const RemotionRoot: React.FC = () => (
  <Composition
    id="CaptionedVideo"
    component={CaptionedVideo}
    width={1080}
    height={1920}
    fps={30}
    durationInFrames={150}
    defaultProps={exemplo}
    calculateMetadata={({props}) => ({
      width: props.largura,
      height: props.altura,
      fps: props.fps,
      durationInFrames: Math.max(1, Math.round(props.duracao_s * props.fps)),
    })}
  />
);
