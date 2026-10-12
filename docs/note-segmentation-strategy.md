# Segmentação e seleção da referência — 12/10/2026

## Estratégia implementada

Manter pYIN e separar três decisões: existe áudio vocal plausível, qual
estimativa de frequência tem suporte e onde começa/termina uma nota estável.
Não diminuir globalmente a confiança mínima nem preencher refrões inteiros
sem evidência de pitch. Não mudar o contrato JSON v1 ou adicionar dependências.

1. **Atividade do stem separado.** Além de -50 dBFS, comparar a energia do
   stem com a mistura: rejeitar diferenças inferiores a -25 dB e energia
   inferior ao maior entre -50 dBFS e o percentil 90 menos 30 dB. Essa regra
   adicional só se aplica quando há separação. É uma heurística de vazamento,
   não um classificador de voz: instrumentos audíveis no stem podem passar.
2. **Registro sem dobrar oitavas.** Quando há pelo menos 40 frames de pitch
   confiável em áudio forte, estimar os percentis 5/95 de MIDI e ampliar em uma
   oitava. Rejeitar apenas candidatos fora desse registro em áudio pelo menos
   12 dB abaixo do nível de referência. Mudanças agudas/graves em áudio forte
   permanecem possíveis. Voz suave em registro extremo pode ser prejudicada.
3. **Seleção entre janelas.** Manter a primeira estimativa com probabilidade
   >=0,1. Usar a segunda se a primeira falhar e houver probabilidade forte ou
   um trecho estável de pelo menos 120 ms. Estimativas fracas sem confirmação
   independente precisam de probabilidade >=0,03; não usar qualquer candidato
   de 0,01 apenas porque permanece estável.
4. **Candidatos não vocalizados.** Executar a mesma inferência pYIN com
   `fill_na=None`, guardando separadamente o melhor candidato quando Viterbi
   marca o frame como não vocalizado. O resultado público/raw continua com
   NaN nesses frames. Aceitar recuperação fraca somente quando as duas janelas
   concordam em até 0,5 semitom, com probabilidade >=0,01, estabilidade de
   120 ms e atividade. Descartar candidatos junto aos limites C2/C7 (margem
   interna de meio semitom): concordar no limite da busca não confirma voz.
5. **Lacunas e limites.** Interpolar somente lacunas de até 60 ms entre pitches
   compatíveis, sem atravessar inatividade ou buracos nos timestamps. A
   segmentação não une duas notas através de um frame explicitamente inativo.
   A estabilização por mediana/histerese e a correção de erros breves de oitava
   permanecem. Isso não acrescenta um detector completo de ataques.

`pitch-debug.csv` e `pitch-secondary-debug.csv` continuam preservando as curvas
brutas e flags. `pitch-candidates-debug.csv` guarda os candidatos descartados
pelo voicing. `reference-debug.csv` mostra atividade, suporte, frequência e
probabilidade escolhidas: source 0=rejeitado, 1=primário, 2=secundário,
3=interpolação curta. Seleção de frame não garante que ele sobreviva à duração
mínima de uma nota. A confiança JSON 1.0 continua sendo um placeholder.

## Validação executada

`python -m pytest analyzer/tests -q`: **112 passed, 2 xfailed**, em 7,91 s.
`ruff check .` no analyzer: aprovado; foram corrigidas duas separações de
imports preexistentes em `cli.py` e `test_exporter.py`. `git diff --check`:
aprovado. Os dois `xfail` continuam
registrando cancelamento estéreo e fusão de ataques sem evidência independente
de silêncio. Há três avisos de depreciação do audioread no Python 3.11.

O pipeline completo também foi executado para `we_are`, reutilizando o stem
Demucs existente e executando novamente ambos os passes de pYIN. As 156 notas
exportadas coincidiram com a comparação em cache. A saída isolada é
`workspace/pitch-validation/20261012-we_are-production/song.json`.

Artefatos em `workspace/pitch-validation/20261012-segmentation-final`.
Comparação antes/depois nos mesmos dados, sem SwiftF0. Cinco músicas anteriores
foram avaliadas completas com os diagnósticos em cache. As sete músicas novas
foram separadas em CUDA, offline com os pesos existentes, e analisadas nas duas
janelas num trecho fixo de 30 s ao redor do meio de cada música. Os hashes dos
MP3s novos confirmaram preservação.

As quatro músicas de vocalista único são `acid_rain`, `heroes_of_sand`,
`nova_era` e `rebirth`. O grupo com vários vocalistas inclui
`as_long_as_you_love_me`, `i_want_it_that_way`, `quit_playing_games` e
`shape_of_my_heart`. A classificação vem do usuário: ela não significa que
todo frame desses arquivos contenha voz solo ou simultânea.

Os candidatos adicionais foram inferidos e verificados nos sete trechos novos
e na música `we_are` completa. A inferência retornou as mesmas curvas brutas
nos trechos novos. Os outros quatro caches antigos não têm candidatos
não vocalizados; a comparação deles usa a seleção conservadora disponível.
É preciso reanalisar para verificar integralmente esse caminho nessas músicas.

| Música / trecho relatado | Cobertura anterior | Cobertura nova |
| --- | ---: | ---: |
| we_are 00:17–00:19, sem vocal | 70,8% | 0,0% |
| we_are 00:36–00:38, sem vocal | 0,0% | 0,0% |
| we_are 01:41–01:48, com vocal | 6,9% | 10,4% |
| como_eu_quero 00:52–00:57, com vocal | 93,3% | 93,3% |
| como_eu_quero 01:49–01:55, sem vocal | 56,1% | 52,1% |
| amiga_da_minha_mulher 00:26–00:28, com vocal | 58,0% | 58,0% |
| amiga_da_minha_mulher 01:08–01:10, com vocal | 47,6% | 55,1% |

Relatos do usuário são rótulos aproximados de presença de voz, não notas
revisadas. Cobertura não prova afinação. A primeira tentativa de usar qualquer
secundário estável de probabilidade 0,01 produziu 48,8% de notas falsas em
00:36–00:38; foi restringida. Filtros passa-faixa e isolamento harmônico foram
testados em 00:36–00:38 e 01:41–01:48: aumentaram detecções no instrumental e
não foram integrados.

O refrão de `we_are` **continua insuficiente**. A ausência de fundamentais
confiáveis precede a segmentação; preencher artificialmente esse intervalo
aumentaria cobertura sem demonstrar notas corretas. Backing vocals, coros,
harmonias e vazamento instrumental continuam limitações. Alguns trechos novos
perderam cobertura; sem escuta/referências não afirmar que a redução é correta.

### Escuta do stem pelo usuário

O usuário ouviu o vocal separado e relatou um pico instrumental no início,
enquanto o refrão foi separado normalmente, sem excesso perceptível de ruído.
Isso orienta a investigação do refrão para extração/voicing do pYIN; não é
evidência suficiente para identificar a causa exata ou uma fundamental única.
Em 101–108 s, a execução completa marcou 12,9% dos frames como vocalizados na
janela 2048 e 56,7% na janela 4096. A mediana de probabilidade foi aproximadamente
0,01 nas duas; apenas 0,17% dos frames primários atingiram 0,1 e nenhum dos
secundários atingiu esse valor. Os números são diagnósticos do estimador,
não uma medição da presença real de voz ou da qualidade do stem.

Prioridade: avaliar periodicidade, candidatos e parâmetros de extração no
vocal audível do refrão, preservando o instrumental inicial como regressão de
falsos positivos. Não atribuir automaticamente a lacuna à separação ou ao ruído.

Investigação posterior executada: [83 variações de pYIN e conclusão](pyin-parameter-investigation.md).
As variantes mais permissivas também aumentaram falsos positivos; não foram
adotadas em produção.

## Reprodução e próximo passo

```powershell
.\analyzer\.venv\Scripts\python.exe -m pytest analyzer/tests -q
.\analyzer\.venv\Scripts\python.exe analyzer/scripts/validate_segmentation.py `
  workspace/pitch-validation/new-segmentation-run `
  --cache-root workspace/pitch-validation/20261011-183539 `
  --downloads workspace/downloads
.\analyzer\.venv\Scripts\python.exe analyzer/scripts/validate_segmentation.py `
  workspace/pitch-validation/new-segmentation-replay `
  --replay workspace/pitch-validation/20261012-segmentation/inputs `
  --refresh-candidates
```

Os scripts exigem uma pasta de saída nova. Resultados individuais ficam em
`before-notes.json`/`after-notes.json`, e o agregado em `results.json`. Não foi
feito build. A mudança vale para novas importações; músicas já importadas
guardam as notas anteriores até serem reanalisadas.

Próximo passo: ouvir/revisar os trechos de 30 s, marcar voz principal e regiões
ambíguas e reservar músicas/artistas para avaliação independente. Priorizar
extração/voicing do refrão de `we_are`, em vez de continuar relaxando a
segmentação. Qualquer detector/modelo adicional requer consulta antes da
instalação; não há novo modelo nesta implementação.
