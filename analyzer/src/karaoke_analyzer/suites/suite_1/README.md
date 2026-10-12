# Suíte 1 — pYIN conservador

Referência inicial preservada em 12/10/2026. Identificador: `suite_1`, versão 1.
Este diretório contém a implementação do algoritmo atual, incluindo sua
orquestração. Novas estratégias devem ocupar outro diretório, preservando esta
base para comparação. Os módulos antigos apenas reexportam suas funções.

## Pipeline

1. Preserva o MP3 e decodifica com FFmpeg. Opcionalmente separa o vocal com
   Demucs; CPU ou CUDA afetam a separação, não o pYIN.
2. Executa pYIN monofônico em 22.050 Hz, hop de 256 amostras, faixa C2–C7,
   com janelas de 2.048 e 4.096 amostras e parâmetros padrão do librosa.
3. Mede energia RMS em janelas de 90 ms. Com separação, compara vocal e mix,
   usando piso adaptativo de energia e rejeição conservadora de candidatos
   fracos fora do registro observado.
4. Usa consenso entre janelas e recuperação conservadora de baixa confiança.
   A referência primária forte tem prioridade; a secundária pode recuperar
   lacunas quando há estabilidade ou concordância dos candidatos brutos.
   Interpola somente lacunas ativas de até 60 ms entre alturas próximas.
5. Converte para MIDI com mediana de 70 ms, histerese de 0,75 semitom e mudança
   sustentada por 80 ms. Corrige pequenos saltos de oitava de até 150 ms.
   Une notas iguais com lacunas de até 60 ms, respeitando atividade vocal.
   Duração mínima: 120 ms, ou 80 ms com suporte suficiente entre janelas.
6. Exporta `song.json` no contrato v1 e os CSVs brutos de pitch, candidatos,
   consenso, atividade, recuperação e referência. O despachante registra
   `analysis-suite.json` ao lado do manifesto, sem alterar seu contrato.

## Uso e comparação

No Godot em depuração, abra **Importar música → Suíte de análise**.
O padrão é esta suíte. A seleção vale para a nova importação: não recalcula
músicas existentes. Importe o mesmo MP3 novamente para comparar resultados;
o importador reserva outro diretório e preserva a versão anterior.

```powershell
.\analyzer\.venv\Scripts\python.exe -m karaoke_analyzer analyze workspace\downloads\we_are.mp3 --output workspace\suite-tests\suite_1\we_are --separate --device cuda --suite suite_1
.\analyzer\.venv\Scripts\python.exe -m pytest analyzer/tests -q
```

## Limitações conhecidas

- Instrumentos presentes no stem podem gerar notas falsas; refrões cantados
  ainda podem ficar sem referência, como `we_are` em 01:41–01:48.
- Coros, harmonias, backing vocals e mudanças de cantor dificultam a estimação
  monofônica. Pitch não equivale a uma classificação confiável de voz.
- Cancelamento entre canais, ataques repetidos e erros de oitava continuam
  sujeitos às limitações registradas nos testes e diagnósticos existentes.
- A confiança exportada por nota ainda é um valor fixo; os CSVs preservam a
  probabilidade por frame para avaliação.
- Preservar o código não congela dependências, pesos ou dispositivo. Para uma
  comparação válida, use os mesmos stems, versões de bibliotecas e trechos.

Esta suíte não incorpora SwiftF0, CREPE nem os parâmetros experimentais do
benchmark. Consulte `docs/note-segmentation-strategy.md` e
`docs/pyin-parameter-investigation.md` na raiz do projeto para os resultados.

## Próximas suítes

Crie `suites/suite_2/` com implementação independente e documentação. Registre
seu identificador em `suites/__init__.py` e adicione a opção correspondente ao
seletor de depuração em `game/scripts/import_page.gd`. Preserve a assinatura
de `analyze`, o contrato v1 e os diagnósticos necessários à comparação. Faça
os testes de regressão e compare os mesmos intervalos revisados pelo usuário.
