# Suíte 4 — HPSS

Identificador `suite_4`, versão 1. Baseada na suíte 1, com pré-processamento
harmônico/percussivo antes das duas estimativas pYIN. Não usa os limiares
relativos da suíte 3 nem a segunda passagem do Demucs da suíte 2.

## Pipeline

1. Preserva e decodifica o MP3 original.
2. Opcionalmente aplica Demucs uma vez, como na suíte 1.
3. Aplica `librosa.effects.hpss` ao stem vocal (ou ao WAV decodificado quando
   não há separação), conservando apenas o componente harmônico.
4. Executa as duas janelas pYIN sobre `hpss-harmonic.wav`.
5. Usa os critérios de energia, consenso, recuperação e segmentação da suíte 1.

A energia é medida no áudio de referência **antes do HPSS**, e comparada com o
mix original quando há Demucs. Isso mantém os filtros da suíte 1 e evita que
a atenuação introduzida pelo HPSS seja uma segunda mudança no experimento.
Os CSVs de pitch descrevem o componente harmônico; o CSV de atividade descreve
a referência anterior ao filtro. O áudio reproduzido continua sendo o MP3 original.

## Parâmetros e artefatos

- HPSS: kernel 31, potência 2, margem 1, FFT 2048, hop 512, janelas centradas.
- Conserva a taxa de amostragem, os canais e o número de amostras da referência.
- `hpss-harmonic.wav`: componente usado pelo pYIN, WAV float para evitar clipping.
- `hpss-harmonic.json`: parâmetros, tamanho e indicação da referência de energia.
- Mantém os diagnósticos da suíte 1 e `analysis-suite.json` do despachante.

No Godot em depuração, escolha **Suíte 4 — HPSS**. O CLI aceita `--suite suite_4`;
`--separate` habilita Demucs antes do HPSS. Não há nova dependência ou modelo:
o HPSS usa librosa, já instalado. O processamento HPSS é em CPU e aumenta o
tempo e uso de memória, especialmente em músicas longas.

## Hipótese, testes e limites

O HPSS pode reduzir ataques percussivos que atrapalham a estimação de pitch.
Instrumentos harmônicos sustentados podem permanecer; não é um detector de voz.
Também pode atenuar ataques vocais ou alterar os candidatos estimados pelo pYIN.

O teste de sinal sintético executa HPSS real, verifica redução de impulsos,
preservação de frequência, canais e duração. Testes de integração com mocks
verificam roteamento e diagnósticos sem GPU ou pesos.

Para avaliar qualidade, compare as suítes 1 e 4 em `nova_era` 00:00–00:39,
nos trechos cantados descobertos e em `we_are` 01:41–01:48. Ouça também o WAV
harmônico. A melhora em músicas reais ainda depende dessa comparação.
