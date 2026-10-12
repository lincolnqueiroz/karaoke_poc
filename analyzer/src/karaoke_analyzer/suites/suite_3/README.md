# Suíte 3 — Energia relativa

Identificador `suite_3`, versão 3. Experimento de substituição dos cortes
absolutos de energia da suíte 1. A suíte 1 permanece preservada e como padrão.

## Regra

Após estimar pitch e energia RMS do áudio de referência, calcula:

`R = percentil 90 dos frames com energia finita`

`piso_RMS = 0,40 × RMS correspondente a R`

Em dB: `piso = R + 20 × log10(0,40) ≈ R − 7,96 dB`.
A proporção é aplicada à amplitude RMS linear, não ao número em dBFS.
O corte anterior (versão 1) correspondia a aproximadamente 3,16% do RMS do P90;
Na versão 2, a fração era 10%; agora o piso é mais alto e rejeita mais frames fracos.

Nenhum frame é previamente excluído pelo antigo corte de −50 dBFS.
O mesmo piso substitui −50 dBFS em atividade vocal, consenso entre janelas,
recuperação de baixa probabilidade e segmentação. Ele também substitui o antigo
`máximo(−50, P90 − 30)` da atividade vocal com Demucs.

São mantidos os critérios que já eram relativos: diferença vocal/mix de
−25 dB e seleção de registro baseada em P70 − 12 dB. P70 agora é calculado
sobre os frames aprovados pelo novo piso e pela comparação com o mix.
Todos os outros parâmetros de pitch, duração, recuperação e registro seguem
a suíte 1. Demucs é aplicado uma única vez quando a separação está habilitada.

## Uso e diagnósticos

Na importação do Godot em depuração, escolha **Suíte 3 — Energia relativa**.
Ou use `--suite suite_3` no CLI, com `--separate` se desejar Demucs.
Os módulos desta suíte foram copiados da suíte 1, preservando a independência
das implementações para experiências futuras.

Além dos arquivos habituais e de `analysis-suite.json`, a análise grava
`energy-threshold-debug.json` com percentil, fração RMS, margem, referência e piso em dBFS.
O CSV de atividade mantém a energia bruta, sem normalização do áudio.
Quando não há energia finita, referência e piso são registrados como `null`
e nenhum frame é aceito. O original não é alterado.

## Validação e limites

Testes com pitch controlado verificam que reduzir ou aumentar igualmente as
energias de vocal e mix preserva atividade, consenso e notas; incluem recuperação
de frames fracos, rejeição de resíduos e silêncio. Isso verifica os filtros,
não garante invariância do Demucs ou do pYIN ao ganho do áudio real.

O percentil global pode ser dominado por ruído ou instrumentos. A suíte não
identifica voz e pode aumentar falsos positivos em stems contaminados.
A fração de 40% é experimental e pode descartar voz suave. Compare `we_are` em 00:17–00:19,
00:36–00:38 e 01:41–01:48 com a suíte 1, além de músicas já satisfatórias.

## Investigação de nova_era

O usuário confirmou ausência de vocal em 00:00–00:39 e instrumentos vazando
no stem. Reexecutamos seleção e segmentação usando o pitch existente e o mesmo
stem, sem nova inferência de Demucs/pYIN. Resultados locais em
`workspace/pitch-validation/nova-era-relative-sweep/`:

| Fração RMS | Notas na introdução (s) | Notas no restante (s) |
|---|---:|---:|
| 10% | 10,51 | 96,98 |
| 20% | 8,16 | 89,77 |
| 25% | 7,21 | 88,51 |
| 31,62% | 6,14 | 86,49 |
| 40% | 4,56 | 82,27 |
| 50% | 2,57 | 74,88 |

Escolhemos 40% como próximo experimento. A queda na introdução representa redução
de falsos positivos confirmados; a queda no restante pode incluir perdas de voz
e exige audição. Não há referência manual para medir precisão nesse restante.
A biblioteca existente não foi regravada; é necessário reimportar para testar.
