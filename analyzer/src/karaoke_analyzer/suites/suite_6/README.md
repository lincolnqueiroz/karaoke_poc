# Suíte 6 — Demucs ajustado + HPSS

Identificador `suite_6`, versão 1. Baseada na suíte 4: HPSS antes das duas
janelas pYIN e atividade, recuperação e segmentação da suíte 1. Não usa o veto
harmônico da suíte 5 nem o piso relativo da suíte 3.

## Separação

Aplica Demucs uma única vez ao MP3 estéreo original, com:

| Parâmetro | Suíte 4 | Suíte 6 |
|---|---|---|
| Modelo | htdemucs | htdemucs |
| Shifts | 1 | 4 |
| Overlap | 25% | 50% |
| WAV | int16 | float32 |
| Clip mode | rescale | none |
| Acompanhamento | soma dos outros stems | soma dos outros stems |

Shifts faz a média de predições com deslocamentos temporais aleatórios,
desfazendo os deslocamentos na saída. Overlap aumenta a sobreposição dos blocos.
São hipóteses de melhora da separação, não garantia de remover instrumentos.
Float32 sem reescala preserva amplitudes relativas mesmo quando excedem ±1;
não melhora a inferência por si só. Os stems são diagnósticos; o playback usa
o MP3 original. O tamanho dos segmentos permanece o padrão do modelo.

## Uso e artefatos

No Godot em depuração, selecione **Suíte 6 — Demucs ajustado + HPSS**.
A separação fica obrigatória. No CLI:

```powershell
.\analyzer\.venv\Scripts\python.exe -m karaoke_analyzer analyze workspace\downloads\nova_era.mp3 --output workspace\suite-tests\suite_6\nova_era --separate --device cuda --suite suite_6
```

Não adiciona dependência nem modelo. Reutiliza os pesos `htdemucs` existentes;
download continua sujeito ao controle já usado pelo importador.

Preserva `stems/htdemucs/<nome>/vocals.wav`, `no_vocals.wav`, HPSS, CSVs e
`analysis-suite.json`. `demucs-config-debug.json` registra os parâmetros efetivos
escolhidos. A configuração de separação está isolada nesta suíte: as anteriores
mantêm seus comandos originais.

## Avaliação e limites

O processamento será mais lento: quatro shifts multiplicam as predições e o
overlap maior acrescenta trabalho. Float32 aumenta o tamanho dos stems.
A aleatoriedade dos shifts pode produzir pequenas diferenças entre execuções;
os tempos e a qualidade em GPU ainda precisam ser medidos em músicas reais.

Testes sem GPU verificam comando, falhas, saída, configuração e roteamento ao
HPSS/pYIN. Não baixam pesos nem executam inferência Demucs.

Compare suítes 4 e 6 na introdução `nova_era` 00:00–00:39 e nos dois trechos
vocais que melhoraram com HPSS. Ouça o novo stem e avalie redução de vazamento
sem perda de voz. Alteramos um conjunto de parâmetros; se houver melhora,
experimentos separados serão necessários para identificar qual ajuste ajudou.
