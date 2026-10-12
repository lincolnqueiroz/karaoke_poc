# Suíte 7 — HPSS + Corte absoluto

Identificador `suite_7`, versão 2. Baseada na suíte 4, com um corte mínimo
absoluto de **−25 dBFS**, contra −50 dBFS na suíte 4. Isso aumenta o piso em
25 dB (aproximadamente 17,8 vezes a amplitude RMS mínima). A versão 1 usava
−30 dBFS e melhorou o resultado segundo o teste do usuário; esta revisão aumenta
o piso mais 5 dB. Não usa os ajustes Demucs da suíte 6,
o veto da suíte 5 ou o limiar proporcional da suíte 3.

## Pipeline e parâmetros

Demucs opcional com os padrões da suíte 4 (`htdemucs`, um shift, overlap 25%),
HPSS harmônico e duas janelas pYIN. Todas as etapas de atividade, consenso,
recuperação e segmentação compartilham `MIN_RMS_DB = -25.0` em `settings.py`.
O código de seleção/segmentação foi preservado neste diretório a partir da
suíte 1, com apenas a alteração dos cortes absolutos. HPSS reutiliza a suíte 4.

A energia continua sendo RMS em janelas de 90 ms sobre a referência **antes do
HPSS**. Com Demucs, o piso adaptativo continua `máximo(−25, P90 − 30 dB)`;
a diferença vocal/mix de −25 dB e os filtros de registro ficam preservados.
Nenhum frame abaixo do piso pode ser reintroduzido por consenso ou recuperação.
Os demais parâmetros de pitch, probabilidade, duração e junção seguem a suíte 4.

## Uso e diagnósticos

Selecione **Suíte 7 — HPSS + Corte absoluto** na importação em depuração do
Godot. O CLI aceita `--suite suite_7`, com `--separate` para habilitar Demucs.
O MP3 original e os stems são preservados; a música já importada não é atualizada.
Para comparar, importe novamente e mantenha a versão anterior.

`energy-threshold-debug.json` registra o piso absoluto e os critérios adicionais.
Mantém `analysis-suite.json`, `hpss-harmonic.wav`, configuração HPSS e os CSVs
brutos de pitch, atividade, consenso, referência e recuperação.

## Riscos e comparação

Um instrumento forte pode continuar passando. Voz suave e gravações baixas
podem ficar sem notas: o corte não identifica voz nem se adapta ao ganho.
Avalie a introdução de `nova_era` 00:00–00:39 e os dois trechos cantados que
melhoraram na suíte 4. Os testes verificam rejeição de frames fracos mesmo com
pitch/confiança fortes, preservação de frames fortes, recuperação e ausência de
alteração da suíte 4. A qualidade musical ainda requer essa comparação.
