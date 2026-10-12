# Investigação dos parâmetros pYIN — 12/10/2026

## Resultado

Foram executadas **83 variações de extração**, usando o stem que está na
biblioteca `workspace/songs/we_are/stems/htdemucs/we_are/vocals.wav`.
Nenhuma configuração testada demonstrou recuperação suficiente do refrão sem
também aceitar mais notas no trecho instrumental. **Os parâmetros de produção
permanecem iguais aos da etapa anterior.**

Os MP3s, stems e referências importadas não foram sobrescritos. Nenhuma nova
dependência foi instalada, nenhum modelo foi baixado e nenhum build foi feito.

## Procedimento e evidências

Trechos relatados: 17–19 s e 36–38 s sem vocal, 101–108 s com vocal.
Cada trecho foi extraído com 3 s de contexto de cada lado. Os horários nos
diagnósticos são absolutos, preservando o alinhamento com o original.

- 42 execuções: sete configurações, janelas 2048/4096 e os três trechos.
  Incluem priors beta (2,18), (2,12), (2,8), (2,6), (2,4), redução de
  `no_trough_prob` para 0,001 e `max_transition_rate` para 12.
- Nove execuções: janelas 768/1024/1536 nos três trechos.
- 16 execuções: passa-altas 50/150/300 Hz e pré-ênfase (1 - 0,97 z⁻¹),
  nas duas janelas, para o instrumental de 36 s e o refrão.
- 16 execuções: combinações de passa-altas 300 Hz/pré-ênfase com beta (2,8)
  ou (2,4) e `no_trough_prob=0,001`, nas mesmas janelas e dois trechos.

O [pYIN do librosa 0.11](https://librosa.org/doc/0.11.0/generated/librosa.pyin.html)
usa candidatos YIN e decodificação Viterbi. `beta_parameters` altera a
distribuição dos limiares de periodicidade; portanto, aumentar sua probabilidade
de voicing não constitui uma melhora de precisão medida.

Na comparação abaixo, as notas são montadas por **uma única passagem**, com
probabilidade mínima 0,1 e as mesmas regras de estabilização/duração. Não são
as coberturas do pipeline completo com recuperação e seleção entre janelas.

| Configuração | Janela | Cobertura 36–38 s, sem vocal | Cobertura 101–108 s, vocal |
| --- | ---: | ---: | ---: |
| Padrão, beta (2,18) | 2048 | 0,0% | 0,0% |
| Beta (2,8) | 2048 | 16,3% | 9,2% |
| Beta (2,6) | 2048 | 22,1% | 31,6% |
| Beta (2,4) | 2048 | 32,5% | 59,0% |
| Beta (2,4) | 4096 | 31,3% | 56,4% |

As janelas curtas não produziram notas no refrão com essa montagem. A
filtragem simples também não produziu recuperação suficiente. As combinações
mais permissivas continuaram aceitando eventos instrumentais.

Os resultados de energia harmônica no stem vocal e em `no_vocals.wav`
também foram inspecionados. As distribuições se sobrepuseram entre o trecho
instrumental e o refrão; isso não forneceu um filtro seguro de voz.
SwiftF0, já autorizado e instalado, foi usado apenas como diagnóstico adicional;
sua confiança também não ofereceu um corte simples que separasse esses trechos.
Ele não foi integrado à produção.

Artefatos locais:

- `workspace/pitch-validation/20261012-pyin-parameters/all-results.json`:
  agregado das 83 execuções, com precisão real ainda nula.
- `workspace/pitch-validation/20261012-pyin-parameters/parameter-comparison.png`:
  comparação visual de F0 padrão e beta (2,4).
- CSVs individuais em `20261012-pyin-parameters`, `20261012-pyin-short-windows`,
  `20261012-pyin-filtering` e `20261012-pyin-combined`.

Esses números indicam cobertura e falsos positivos nos relatos de presença de
voz. Não comprovam afinação: ainda faltam notas revisadas. As inferências locais
com contexto podem diferir de Viterbi executado na música inteira. Os resultados
não demonstram generalização para as outras músicas; nenhuma dessas variantes
passou pelo critério local para avançar à regressão do corpus em produção.

## Reprodução e proposta seguinte

```powershell
.\analyzer\.venv\Scripts\python.exe analyzer/scripts/experiment_pyin.py `
  workspace/songs/we_are/stems/htdemucs/we_are/vocals.wav `
  workspace/pitch-validation/new-pyin-parameters
# Repetir com saídas novas e --experiment short-windows, filtering ou combined.
```

O próximo experimento proposto é comparar [CREPE/torchcrepe](https://github.com/maxrmorrison/torchcrepe)
nos mesmos três trechos antes de escolher qualquer backend ou fallback.
`analyzer/scripts/experiment_crepe.py` está preparado e sua CLI foi verificada;
a inferência **não foi executada**, pois torchcrepe ainda não está instalado.

O teste usa o modelo oficial incluído no pacote, registra periodicidade e
cobertura com três limiares e permite CUDA ou CPU explícito. Isso não é um
detector de identidade vocal, e não há garantia de que resolverá a música.
A instalação de `torchcrepe==0.0.24` e seus pesos requer autorização pelo
AGENTS.md. Preservar o PyTorch CUDA existente e manter pYIN em produção durante
o benchmark. Nenhuma alteração do contrato JSON é proposta.
