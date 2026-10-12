# Suíte 5 — HPSS + Harmônicos

Identificador `suite_5`, versão 1. Mantém o HPSS da suíte 4 e a estimação,
atividade e segmentação da suíte 1. Acrescenta um veto experimental de vazamento
instrumental comparando harmônicos do pitch candidato nos dois stems do Demucs.
A separação é obrigatória; não usa segunda passagem nem energia da suíte 3.

## Evidência e decisão

Após selecionar a referência entre as duas janelas pYIN, compara o vocal
**antes do HPSS** com `no_vocals.wav`. Isso evita comparar um vocal atenuado pelo
HPSS com acompanhamento não filtrado. Ambos são reamostrados a 22.050 Hz;
potências espectrais dos canais são calculadas separadamente e depois médias,
evitando cancelamento entre canais. Usa FFT 4096 centrada no timestamp do pitch.

Para cada fundamental candidata, examina até cinco harmônicos, em bandas de
meio semitom (no mínimo um bin). Só conta harmônicos do acompanhamento com pico
de potência pelo menos quatro vezes a mediana espectral de sua vizinhança,
excluindo a banda do alvo. Ruído amplo sozinho não basta.

O veto exige simultaneamente:

- Acompanhamento dominando em **pelo menos três harmônicos**, cada um com potência
  vocal/acompanhamento ≤ −12 dB.
- Razão agregada ≤ −12 dB, ponderando cada harmônico por `1/h`.
- Evidência contínua por pelo menos **120 ms**, sem atravessar lacunas de tempo.

Não veta automaticamente só porque a mesma altura aparece nos dois stems.
Uma voz com presença comparável ao acompanhamento fica preservada. Nenhum veto
preenche lacunas ou altera o pitch. Frames vetados são removidos da atividade,
referência e suporte, impedindo que recuperação e junção os reintroduzam.

## Uso e diagnósticos

Selecione **Suíte 5 — HPSS + Harmônicos** na importação do Godot em depuração.
Ou use `--suite suite_5 --separate` no CLI. CPU/CUDA seguem as opções do Demucs;
a comparação harmônica é CPU. Nenhuma nova dependência ou peso é necessário.
Os stems, HPSS, original e CSVs brutos continuam preservados.

`harmonic-leakage-debug.csv` registra timestamp, F0, razão em dB, quantidade de
harmônicos dominados e veto. `NaN` na razão significa ausência de evidência
comparável, não razão zero. `reference-debug.csv` mostra a referência após o veto;
os CSVs pYIN permanecem brutos. Os parâmetros estão neste documento e em `leakage.py`.

## Limites e avaliação

Os limiares são hipóteses iniciais, não valores calibrados no corpus. Voz fraca
duplicada no acompanhamento pode ser descartada; vazamentos fortes no vocal,
sons com poucos harmônicos ou instrumentos em outra oitava podem permanecer.
É uma evidência de separação, não uma classificação confiável de voz.

Os testes executam comparação espectral real em sinais sintéticos: vazamento
harmônico, voz em uníssono preservada, acompanhamento em outra altura e invariância
ao ganho. Também verificam continuidade temporal e bloqueio de recuperação.
A qualidade em músicas reais precisa de audição e comparação.

Compare suítes 4 e 5 em `nova_era` 00:00–00:39 e nos dois trechos cantados que
melhoraram com HPSS. Observe perdas de voz antes de tornar o veto mais agressivo.
