# Generalizar a referência entre músicas

## Limitação observada: vários cantores simultâneos

Em teste manual com um grupo musical, o usuário observou reconhecimento
incorreto das notas nos trechos em que todos cantam juntos. A limitação fica
registrada junto às dificuldades com backing vocals e harmonias; não houve
medição quantitativa nem diagnóstico desses trechos.

O analisador estima uma única altura por frame. A separação de vocals não
garante isolamento de um cantor principal, e vozes sobrepostas podem tornar
a referência ambígua, com notas ausentes ou alturas incorretas. A concordância
entre duas janelas não garante a seleção da melodia principal nesses casos.
Revisar esses trechos antes de usar a referência para pontuação e incluir
canto em grupo no conjunto de regressão de futuros ajustes.

## Diagnóstico com os arquivos existentes

Comparação de `pitch-debug.csv`, `activity-debug.csv` e `song.json`, sem executar
Demucs novamente ou modificar as referências. Tempos abaixo representam a soma
dos frames classificados pelo estimador, não uma anotação humana de voz principal.

| Medida | como_eu_quero | amiga_da_minha_mulher |
| --- | ---: | ---: |
| Duração da música | 273,43 s | 248,08 s |
| Duração das notas exportadas | 152,73 s | 42,27 s |
| Frames com pitch/voicing aceitos pelos filtros | 160,39 s | 65,39 s |
| Pitch marcado como voiced, audível, mas probabilidade abaixo de 0,1 | 28,91 s | 106,95 s |
| Voiced com probabilidade suficiente, descartado pelo limiar de energia | 7,99 s | 2,74 s |

Na segunda música, a perda principal está no limiar adicional de probabilidade
e na fragmentação/remoção de segmentos curtos. Repetir a segmentação com os mesmos
dados, apenas retirando o limiar adicional de probabilidade, produz 148,61 s de
notas; reduzir somente a duração mínima de 120 para 60 ms produz 57,44 s. Diminuir
o limiar de energia de -50 para -60 dBFS mantém os mesmos 42,27 s.

Essas alternativas são experimentos diagnósticos, não referências validadas.
Cobertura maior pode incluir instrumentos, backing vocals e alturas incorretas.
O pYIN já admite aproximadamente 65–2093 Hz (C2–C7). Os pitches válidos da segunda
música têm percentis 5/50/95 de 113/263/415 Hz; isso não confirma a frequência real
do cantor nem descarta erros de oitava. Frames sem F0 não revelam se o sinal
verdadeiro estava abaixo da faixa de busca.

## Estratégia recomendada

1. Formar um conjunto de regressão com ambas as músicas e trechos anotados:
   vocal sustentado, frase rápida, voz grave, silêncio/instrumental e backing
   vocals. Avaliar omissões e falsos positivos separadamente; não otimizar
   apenas quantidade ou duração de notas.
2. Separar atividade vocal de qualidade do pitch. Energia pode rejeitar quase
   silêncio, mas não identifica voz humana. Preferir limiar de energia relativo
   ao piso de ruído e à dinâmica do stem, com limites conservadores.
3. Aceitar primeiro regiões confiáveis. Recuperar estimativas de probabilidade
   menor somente quando forem audíveis e tiverem continuidade temporal de pitch
   com regiões confiáveis. Limitar a recuperação e registrar sua origem. Não
   preencher lacunas longas nem converter automaticamente frames sem F0 em notas.
4. Distinguir notas curtas legítimas de fragmentos espúrios. Unir pequenas
   interrupções compatíveis antes de aplicar duração mínima e usar a coerência
   local da frase. Não reduzir globalmente o mínimo como única correção.
5. Nos trechos ainda ambíguos, comparar janelas de análise e faixas de busca
   alternativas, mantendo o hop/tempo alinhado. Conferir fundamental versus
   harmônicos e erros de oitava com o stem. Um segundo estimador pode ajudar
   depois; dependências/modelos adicionais exigem discussão prévia.
6. Medir o ganho nos trechos ausentes da nova música e confirmar que o trecho
   instrumental 109–115 s da primeira continua sem falsos positivos.

Manter diagnósticos brutos e o manifesto anterior durante os experimentos.
O diagnóstico inicial não alterou a produção. Posteriormente, a recuperação
conservadora foi implementada; veja [regras e comparação](segmentation.md#conservative-recovery).
A confiança v1 continua sendo o placeholder documentado, não uma probabilidade calibrada.

A etapa seguinte compara janelas de 2048 e 4096 amostras para sustentar regiões
fracas e notas curtas com concordância de pitch. As regras e os resultados nos
trechos 26–28 s e 68–70 s estão em [segmentation.md](segmentation.md#support-from-two-analysis-windows).

O relatório detalhado e o script de reprodução estão em
`workspace/environment-check/song-coverage-comparison.json` e
`workspace/environment-check/compare_song_coverage.py`.
