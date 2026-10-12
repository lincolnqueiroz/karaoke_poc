# Plano de validação da referência vocal

Pesquisa e revisão em 2026-10-11. Nenhum estimador foi substituído, nenhuma
dependência foi instalada e nenhum build foi gerado nesta etapa.

## Objetivo e limite

Separar sucesso técnico da importação, qualidade musical e custo de processamento.
Um MP3 válido pode ser importado corretamente e ainda produzir uma referência
ruim. Não prometer uma melodia única correta para qualquer áudio: coros,
harmonias, duetos simultâneos e fala podem não possuir um alvo monofônico inequívoco.
Definir o alvo como voz principal cantada; anotar trechos ambíguos separadamente.

## Situação atual

Comando executado: `analyzer/.venv/Scripts/python.exe -m pytest analyzer/tests -q`.
Resultado: **82 testes passaram**. Os testes de pipeline simulam os estimadores
e a separação: não demonstram precisão de transcrição em gravações reais.

O pipeline usa pYIN a 22050 Hz, hop 256, faixa C2–C7, duas janelas (2048/4096),
energia, recuperação conservadora e consenso. A segmentação suaviza o pitch,
confirma mudanças e une pequenas lacunas; notas normalmente precisam de 120 ms,
com exceções sustentadas pelo consenso. A confiança exportada continua sendo
o placeholder 1.0. CUDA na separação não torna automaticamente o pYIN acelerado
por GPU. Cada passagem de pitch carrega e reamostra o áudio independentemente.

Os testes já cobrem vibrato, transições reais, erros curtos de oitava, lacunas,
energia e probabilidades inválidas, limites da recuperação, consenso, preservação
do MP3, publicação após conclusão, falhas simuladas e limites de caminhos.
Faltam avaliações de qualidade com referência humana, testes diretos de extração
de F0 e medições de tempo/memória em músicas reais.

## Matriz proposta

| Grupo | Casos prioritários | O que verificar |
| --- | --- | --- |
| Registro e timbre | Grave, agudo, falsete, voz suave e rouca; dentro e fora da faixa de busca | Omissões, fundamental/harmônico e erros de oitava |
| Segmentação | Vibrato, slides, saltos, melismas, notas rápidas, notas repetidas na mesma altura | Não fragmentar sustentação; não fundir ataques legítimos |
| Ausência de alvo | Introdução, solo instrumental, pausas, respiração, fala/rap sem altura estável | Ausência de notas falsas; separar fala de canto afinado |
| Mistura | Voz baixa, instrumentos fortes, reverberação, distorção, gravação ao vivo | Qualidade com e sem separação; efeito de vazamento e artefatos |
| Várias vozes | Backing vocals, dueto alternado/simultâneo, coro em uníssono/harmonia | Seleção da voz principal ou marcação de ambiguidade |
| Formato | MP3 CBR/VBR, mono/estéreo, 44,1/48 kHz, baixa qualidade, canais em oposição de fase | Decode real, duração e alinhamento, sobrevivência da voz na conversão mono |
| Arquivo e execução | MP3 truncado/inválido, caminhos Unicode/espaços, disco cheio, permissões, importação interrompida | Erro claro; original intacto; biblioteca sem publicação parcial |
| Hardware/distribuição | CPU, CUDA, VRAM insuficiente, pesos disponíveis/ausentes, execução offline e empacotada | Resultado válido ou falha explícita, sem download não autorizado |
| Escala | Trechos curtos, músicas de 3–5 min e arquivos longos, execuções sucessivas | Tempo, RAM/VRAM, limpeza e responsividade da interface |

Na arquitetura atual, duas notas consecutivas na mesma altura podem ser unidas
porque não há detector independente de ataques. Esse é um teste prioritário,
junto com graves, falsos positivos instrumentais e seleção da voz principal.
O teste existente de oposição de fase verifica energia; não garante que a
conversão mono da extração de pitch preserve a voz.

## Conjunto de regressão e anotação

Começar com 20–30 músicas legalmente utilizáveis, distribuídas pelas categorias,
com 3–5 trechos de 10–20 segundos anotados por música. É um conjunto inicial
de engenharia, não evidência suficiente para afirmar cobertura de todo repertório.
Separar desenvolvimento e avaliação por música/artista; não ajustar parâmetros
no conjunto reservado. Além dos trechos, executar algumas músicas completas para
detectar deriva, cortes e problemas de memória.

Anotar presença de voz principal afinada, notas (início/fim/MIDI), ataques repetidos
e regiões ambíguas. Revisar manualmente ouvindo original e stem. Manter as músicas
e anotações locais em `workspace/`; usar sinais sintéticos próprios nos testes
versionados. LRC por verso não oferece precisão de início/fim de cada nota.

Preservar como regressão os trechos relatados anteriormente: 52–57 s e
109–115 s da primeira música; 26–28 s e 68–70 s da segunda. Os arquivos atuais
podem ter sido removidos pelo usuário; sua disponibilidade deve ser conferida
antes da execução. Não usar as estimativas atuais como verdade de referência.

## Medidas e critérios

- Cobertura correta: fração do tempo vocal anotado coberto por notas de pitch
  correto; reportar também cobertura simples, sem confundi-la com acerto.
- Falsos positivos: tempo de referência indevida em trechos anotados sem alvo.
- Pitch: erro em cents, taxa de acerto absoluto e taxa de erros de oitava;
  comparar pitch absoluto e classe de pitch separadamente.
- Notas: precisão/recall/F1 com correspondência um a um; medir início, fim,
  fragmentação e fusão de notas. Adotar inicialmente ±50 cents e ±50 ms para
  início como tolerâncias do benchmark. Para o fim, começar com o maior entre
  50 ms e 20% da duração da nota anotada, reportando também erros em ms.
- Sincronização: atraso sistemático e deriva ao longo da música, incluindo
  delay/padding do MP3, janelas centradas e bordas dos futuros chunks.
- Desempenho: segundos por etapa, tempo total/duração do áudio (RTF), RAM/VRAM,
  cache frio/quente e primeira execução. Registrar hardware, versões e parâmetros.
- Produto: proporção de músicas consideradas jogáveis por revisão humana;
  reportar por categoria e os piores casos, não somente a média.

Metas iniciais propostas para canto solo claro: pelo menos 90% de acerto de pitch
nos frames vocais anotados, F1 de notas de pelo menos 0,85 e no máximo 2% de
cobertura falsa em trechos instrumentais. São critérios a negociar e medir,
não resultados atuais. Coros e fala precisam de critérios próprios. Uma versão
mais rápida só deve ser aceita após comparar sua qualidade com a versão atual.

## Referências externas examinadas

- [UltraSinger](https://github.com/rakuri255/UltraSinger): ferramenta de geração
  de arquivos de karaokê. O [pitcher atual](https://github.com/rakuri255/UltraSinger/blob/main/src/modules/Pitcher/pitcher.py)
  usa SwiftF0 e preserva timestamps/confiança. O README descreve separação,
  transcrição/alinhamento e quantização à tonalidade. Há diferença entre a faixa
  mencionada no README e a configurada no código; preferir verificar a revisão
  efetivamente testada. Avaliar um estimador alternativo sem copiar quantização
  à tonalidade indiscriminadamente.
- [Ultrasongs](https://github.com/pablopramparo/ultrasongs): o README descreve
  Demucs, torchcrepe, pitch por palavra, alinhamento de letra e conversão para
  beats, além de editor de notas. Nesta pesquisa, a implementação interna de
  montagem não pôde ser consultada; não atribuir detalhes além da documentação.
  Uma altura por palavra pode simplificar o jogo, mas requer testes de melismas.
- [VOCANO](https://github.com/B05901022/VOCANO): separa extração de pitch
  (Patch-CNN) de segmentação neural (PyramidNet). O [core](https://github.com/B05901022/VOCANO/blob/main/vocano/core.py)
  pós-processa previsões de limites, estima pitch nos intervalos e gera MIDI.
  O projeto recomenda separação para misturas. Inspiração: limites de notas
  precisam de evidência própria. A instalação antiga com Apex/CUDA merece
  avaliação de compatibilidade antes de qualquer integração.
- [Basic Pitch](https://github.com/spotify/basic-pitch/blob/main/basic_pitch/note_creation.py):
  o código combina ativações de início e sustentação, tolera breves quedas,
  elimina notas curtas e recupera eventos a partir de ativações restantes.
  É transcrição polifônica: não resolve sozinho a escolha da voz principal.
  Inspiração: avaliar limites das notas independentemente da curva de frequência.
- [ultrastar_pitch](https://github.com/paradigmn/ultrastar_pitch): parte de um
  arquivo de notas existente e estima/corrige suas alturas. Não equivale a criar
  todos os limites do zero; separar esses dois problemas ao comparar resultados.

Inspeção estática de código/documentação; nenhum desses projetos foi instalado,
nenhum modelo externo foi executado e suas alegações de velocidade/precisão não
foram reproduzidas nesta máquina.

## Ordem recomendada

1. Montar o conjunto anotado e registrar resultados atuais, incluindo tempos por etapa.
2. Acrescentar extração sintética direta e casos de ataques repetidos/canais.
3. Comparar separação e pitch nos mesmos trechos; mudar uma etapa por vez.
4. Comparar um estimador alternativo, após aprovação das dependências/pesos,
   mantendo inicialmente a segmentação atual para isolar o efeito.
5. Investigar ataques, atividade vocal e escolha de voz principal conforme os
   erros medidos; manter alternativas de revisão para trechos ambíguos.
6. Otimizar o custo medido: reutilização de áudio, cache versionado, segunda
   passagem seletiva ou processamento em chunks com sobreposição. Validar
   fronteiras e equivalência antes de substituir as duas passagens completas.

## Execução inicial e reprodução

Resultados e limitações medidos: [relatório da execução inicial](pitch-validation-results.md).

Evolução posterior: [estratégia de seleção e segmentação implementada em 12/10](note-segmentation-strategy.md).

A execução inicial usa os cinco MP3s disponíveis em `workspace/downloads`, com
passagens completas na mistura e no stem gerado pelo Demucs em CUDA. Um trecho
derivado de 20 segundos também é processado em CPU e CUDA. As referências antigas
da biblioteca não são sobrescritas. O usuário confirmou que não possui notas
revisadas; precisão real e metas de F1 permanecem pendentes.

Os novos testes usam pYIN real e áudio sintético, sem pesos ou GPU. Os testes de
FFmpeg são opcionais e pulados se o executável não estiver disponível. Duas falhas
conhecidas são registradas com `xfail(strict=True)`: cancelamento de canais em
oposição de fase na extração e fusão de ataques repetidos na mesma altura.

```powershell
.\analyzer\.venv\Scripts\python.exe -m pytest analyzer/tests -q
.\analyzer\.venv\Scripts\python.exe analyzer/scripts/benchmark_pitch.py `
  workspace/downloads/como_eu_quero.mp3 workspace/pitch-validation/new-run `
  --separate --device cuda
.\analyzer\.venv\Scripts\python.exe analyzer/scripts/summarize_pitch_validation.py `
  workspace/pitch-validation/20261011-183539
```

O benchmark exige uma pasta de saída nova. Gera `benchmark.json` com tempos,
preservação SHA-256, versões e memória, além das saídas normais da análise. O
processo Demucs é executado offline, usando pesos já disponíveis. RAM refere-se
ao processo pai, sem os subprocessos. Quando disponível, a VRAM é amostrada via
`nvidia-smi` para o dispositivo inteiro, incluindo outros aplicativos; não é
medição exclusiva do modelo. As primeiras execuções não tiveram essa amostragem.
Os tempos são observacionais; a execução teve testes simultâneos e não fornece
controle completo de cache/carga.

Após aprovação explícita, o usuário instalou SwiftF0 0.3.0 com ONNX Runtime
1.31.0 no venv. Torch permaneceu 2.14.1+cu126 e CUDA continuou disponível.
A dependência é opcional (`.[benchmark]`); nenhum backend de produção foi trocado.

```powershell
.\analyzer\.venv\Scripts\python.exe analyzer/scripts/compare_pitch_estimators.py `
  workspace/pitch-validation/new-comparison --swift --harmonics
```

Para música real, acrescente `--wav <stem.wav>`; `--pyin-cache <pitch-debug.csv>`
reutiliza o diagnóstico da mesma entrada para não executar pYIN novamente.
`--no-synthetic` evita repetir os casos sintéticos já executados. A comparação
usa a mesma segmentação de passagem única, sem consenso nem recuperação. Não
equivale à análise de produção completa e não transforma confiança em precisão.
O relatório agregado fica em `workspace/pitch-validation/20261011-183539/REPORT.md`.

Manter o contrato JSON v1; um benchmark pode ter anotações próprias sem alterar
o contrato consumido pelo jogo. Não usar `confidence=1.0` para atestar qualidade.
