# Suíte 8 — HPSS + Pós-processamento

Identificador `suite_8`, versão 2. Preserva a suíte 7 revisão 2, com HPSS,
Demucs padrão opcional, duas janelas pYIN e piso inicial de −25 dBFS.
Acrescenta uma etapa de revisão das notas após segmentação e recorte à duração
original. As implementações anteriores permanecem preservadas.

## Limpeza

Primeiro absorve uma nota de até **180 ms** imediatamente após uma nota forte
de pelo menos **400 ms**, estendendo a nota longa e mantendo sua altura, mesmo
se a nota curta tem outra altura ou confiança alta. Aceita lacunas de até 60 ms
apenas com energia ≥ −25 dBFS, timestamps contínuos e a comparação vocal/mix
aprovada. Não atravessa silêncio. A âncora deve ser uma nota longa original:
notas curtas absorvidas não permitem absorver uma sequência inteira.
Registra cada operação como `absorb_short`. Essa simplificação deliberada pode
eliminar notas curtas legítimas ou prolongar uma nota instrumental forte.

Remove notas de até 180 ms somente quando têm pouca evidência e estão isoladas
(nenhuma vizinha a até 350 ms) ou são um salto de pelo menos sete semitons
entre duas notas próximas de mesma altura. Considera evidência forte quando
pelo menos metade dos frames tem probabilidade selecionada ≥ 0,1 ou suporte.
Fora da regra de absorção, notas curtas fortes e mudanças de altura sem esse
contexto são preservadas.
A confiança fixa exportada por nota não é usada como evidência.

## Recuperação de continuidade

Une notas da mesma altura separadas por uma lacuna de até 250 ms, somente se
ambas as notas originais têm evidência forte. Reavalia os candidatos brutos das
duas janelas nessa lacuna, incluindo candidatos originalmente não voiced:

- Probabilidade ≥ 0,01 nas duas janelas, candidatos dentro da faixa útil C2–C7.
- Concordância entre janelas e com a nota de até meio semitom.
- Pelo menos 90% dos frames com evidência; falta contínua de até 30 ms.
- Energia ≥ −35 dBFS em toda a lacuna, nunca silêncio. Com Demucs, mantém
  a diferença vocal/mix ≥ −25 dB durante toda a lacuna.
- Nenhuma lacuna de timestamps; não extrapola antes/depois da frase.

O piso local de −35 dBFS é uma exceção limitada às lacunas ancoradas: permite
recuperar frames rejeitados pelo piso inicial de −25, sem abaixar o corte global.
Não preenche frases inteiras, não inventa alturas e não dobra oitavas.
Notas recém-estendidas não criam novas âncoras. Notas removidas são registradas
antes de qualquer eventual união; os candidatos brutos devem apoiar a altura.

## Uso e diagnósticos

Selecione **Suíte 8 — HPSS + Pós-processamento** na importação em depuração,
ou use `--suite suite_8` no CLI. Separação Demucs continua opcional.

- `notes-before-postprocess.json`: notas originais da segmentação.
- `postprocess-debug.json`: parâmetros, notas removidas e intervalos unidos.
- `song.json`: notas finais no contrato v1.
- CSVs de referência/pitch: evidências anteriores ao pós-processamento,
  preservadas para investigar cada alteração.
- `analysis-suite.json`: identificação desta suíte.

Nenhuma nova dependência ou modelo. O original e os stems não são alterados.

## Limites e avaliação

Instrumentos longos, estáveis ou fortes podem permanecer. Backing vocals podem
apoiar uma recuperação indevida, e frases cantadas longas sem candidatos brutos
continuam descobertas. Os limiares são experimentais e ainda requerem comparação
nos trechos específicos de `nova_era`, mantendo `we_are` como regressão.
Testes controlados cobrem limpeza, preservação de saltos legítimos, recuperação
local, silêncio, pitch conflitante, lacunas temporais e exportação antes/depois.
