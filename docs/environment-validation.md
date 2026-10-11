# Validação local do ambiente — 2026-10-10

Nenhuma funcionalidade ou contrato de dados foi alterado. Por solicitação do
usuário, o requisito de Python foi ampliado para aceitar 3.15 além de 3.11;
as versões intermediárias continuam excluídas. O ambiente ainda não está pronto
para executar o analisador.

## Estado atual: Python 3.11 após instalação pelo usuário

### Letra LRC integrada

Após o usuário salvar o arquivo UTF-8, `como_eu_quero.lrc` foi copiado para a
pasta local ignorada da demo. A cena aponta ao LRC por uma propriedade exportada
separada; o contrato `song.json` permanece inalterado.

- Parser e seleção de versos em `lrc_lyrics.gd`: tempos por verso, metadados,
  tags de tempo repetidas, offset em ms e cues vazios para pausas.
- Label com quebra de linha exibe o verso corrente usando `elapsed` do áudio.
  O offset de notas **0.1 s** foi preservado e não afeta a seleção da letra.
- Godot headless `test_lyrics.gd`: **PASS**.
- Validação local: **54 cues**, seleção de cada verso no tempo correspondente
  e limpeza ao final da música: **PASS**.
- `test_timeline.gd`: **PASS**; teste de reprodução real com 388 notas: **PASS**.
- Permanecem os avisos de certificados/objetos no encerramento desta sessão.

Sem timestamps de fim, o verso permanece até o seguinte; pausas exigem cues
vazios no LRC. Próximo passo: conferir legibilidade e alinhamento dos versos
ao executar F5 no editor. O texto da letra continua fora do Git.

### Revisão dos trechos indicados pelo usuário

Implementado RMS centrado de 90 ms em `activity.py`, com gate padrão de -50 dBFS;
pipeline escreve `activity-debug.csv` e usa a energia na segmentação.
O limiar de probabilidade padrão passou de 0.5 para 0.1, combinado com esse gate.
Não foram adicionadas dependências ou alterado o schema do manifesto.

Reprocessados os frames existentes, preservando o CSV bruto por SHA-256 e
retendo o manifesto anterior em `song-before-energy-gate.json`:

- 52–57 s: cobertura **1.343 → 3.154 s**, recuperando voz filtrada.
- 109–115 s: cobertura **1.368 → 0 s**, removendo pitch do silêncio residual.
- Referência completa: **388 notas**; manifesto da demo Godot atualizado.
- `python -m pytest`: **39 passed**.
- Ruff dos seis arquivos alterados/novos: **passou**.
- Godot headless: carregou **388 notas** e iniciou reprodução, exit code 0.
  Avisos de certificados/objetos na saída continuam conhecidos.
- Gráfico e métricas salvos na pasta local da música como
  `reported-ranges.png` e `reported-ranges.json`.

Restam lacunas por frames incertos/transições curtas no trecho cantado.
Energia não é um classificador de voz; instrumentos audíveis ainda podem gerar
falsas notas. Próximo passo: revisar os dois trechos atualizados no Godot.

### Segmentação estabilizada

Implementados filtro por probabilidade, mediana temporal, histerese, confirmação
de mudanças sustentadas, reparo de excursões breves de oitava e união de notas
iguais através de gaps curtos. Sem novas dependências ou alteração do schema v1.
A pipeline agora passa a probabilidade à segmentação e mantém o CSV bruto.

- `python -m pytest`: **31 passed**, incluindo casos de vibrato, pausas,
  oitavas, transições reais e integração da probabilidade na pipeline.
- Ruff dos quatro arquivos Python alterados/novos: **passou**.
- Ruff completo: **5 erros I001 preexistentes** em arquivos não alterados.
- Reprocessamento do CSV existente: **541 → 295 notas**, faixa MIDI
  **36–93 → 55–74**, cobertura **175.284 → 99.345 segundos**.
- Manifesto anterior preservado em `song-before-stabilization.json`.
  CSV bruto preservado e verificado por SHA-256.
- Demo Godot atualizada; teste headless carregou **295 notas**, iniciou áudio
  e confirmou timeline e playback em aproximadamente **1.024 s**, exit code 0.
  Permanecem os avisos de certificados/objetos na saída já observados.

Detalhes e riscos de perda de cobertura em [segmentation.md](segmentation.md).
Próximo passo: revisar visualmente/por audição as frases removidas antes de
ajustar o limiar de probabilidade ou usar essa referência para scoring.

### Godot 4.7.2 validado em modo headless

Executável encontrado em
`D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`.
`--version` confirmou `4.7.2.stable.official.ed1daf0bf`.
`--headless --path game --editor --import --quit` importou o MP3 e não
reportou erros de GDScript. O editor reportou erros de gravação dos caches
fora do workspace e leitura do armazenamento de certificados nesta sessão.

Um script temporário em `workspace/environment-check/godot_smoke.gd`
instanciou a cena real e confirmou: **541 notas**, áudio carregado,
reprodução ativa e avanço de posição (aproximadamente 1.024 s), igual ao
tempo usado pela timeline. APPDATA/LOCALAPPDATA foram redirecionados somente
nesse processo para pastas sob workspace. A leitura de certificados continua
reportando erro, sem impedir a reprodução local headless.
Essa verificação não comprova som audível ou aparência da janela; esses pontos
precisam ser avaliados pelo usuário ao executar F5 no editor.

### GPU validada após instalação de PyTorch pelo usuário

### Tentativa de análise com Demucs

### Exportação concluída usando stems existentes

Na retomada, o cache `workspace/cache/torch/hub/checkpoints` estava vazio,
mas `stems/htdemucs/como_eu_quero/vocals.wav` e `no_vocals.wav` já existiam.
Ambos foram inspecionados com SoundFile: WAV PCM16, estéreo, 44100 Hz,
273.456 segundos. A tentativa de repetir Demucs foi interrompida;
não se atribui a esta sessão a execução que produziu esses stems.

As funções existentes `decode_to_wav`, `estimate_pitch`, `segment_notes`
e `export_song` foram executadas diretamente para aproveitar `vocals.wav`.
Gerados em `workspace/songs/como_eu_quero`: `analysis.wav`, `pitch-debug.csv`
e `song.json`, com **541 notas** e duração decodificada **273.4267 s**.
A diferença de aproximadamente 29 ms em relação ao FFprobe está registrada;
o manifesto usa a duração do WAV decodificado do MP3 original.
SHA-256 da entrada e da cópia `original.mp3` são iguais.
Os **13 testes passaram**. Nenhuma funcionalidade ou contrato foi alterado.

Pitch e segmentação continuam estimativas: confiança das notas é o placeholder
1.0. Próximo passo: ouvir os stems e comparar a visualização com o áudio antes
de considerar a referência confiável. A execução completa do CLI com Demucs
na GPU ainda precisa de uma reprodução com pesos acessíveis à sessão.

Após autorização explícita para baixar pesos oficiais, foi executado:
`python -m karaoke_analyzer analyze workspace/downloads/como_eu_quero.mp3
--output workspace/songs/como_eu_quero --separate --device cuda`.
O PATH do processo incluiu o FFmpeg fornecido pelo usuário e `TORCH_HOME`
foi configurado para `workspace/cache/torch`.

- MP3 confirmado pelo FFprobe: estéreo, 48000 Hz, 273.456 segundos.
- Demucs 4.1.0 instalado; seu `--help` funciona; `pip check` sem conflitos.
- A execução falhou no download dos pesos via `torch.hub`, com
  `URLError`/`WinError 10013` (rede bloqueada nesta sessão).
- Apenas `original.mp3` foi copiado para a saída; separação, extração de pitch
  e exportação do manifesto não foram concluídas. O MP3 de entrada foi preservado.
- Retomada: baixar o modelo `htdemucs` através da própria biblioteca em um
  terminal com rede, usando o mesmo `TORCH_HOME`, e repetir a análise.

- `torch`: **2.14.1+cu126**; runtime CUDA **12.6**.
- `torchaudio`: **2.11.0+cu126**, importado com sucesso.
- `torch.cuda.is_available()`: **True**; uma GPU, RTX 3070,
  compute capability **8.6**.
- Multiplicação de matrizes 32x32 na GPU executada, sincronizada com
  `torch.cuda.synchronize()` e comparada ao resultado CPU por
  `torch.testing.assert_close`: **PASS**.
- `python -m pip check`: nenhum conflito declarado.
- `python -m pytest`: **5 passed**, após a instalação de PyTorch.
- A [documentação oficial de torchaudio](https://docs.pytorch.org/audio/master/installation.html)
  informa que torchaudio 2.11 é compatível com PyTorch 2.11 e posteriores;
  a diferença de versões acima não implica conflito.

Python, decoding sintético via FFmpeg e cálculo CUDA básico foram validados.
Demucs, pesos de modelos e análise de uma música real continuam sem validação.
Os oito problemas I001 previamente encontrados no Ruff continuam pendentes.
Os parágrafos seguintes registram verificações anteriores à instalação de torch.

FFmpeg e FFprobe posteriormente localizados e executados pelo caminho informado
pelo usuário: `D:\Downloads\ffmpeg-master-latest-win64-gpl-shared\ffmpeg-master-latest-win64-gpl-shared\bin`.
Ambos informam build `N-110057-g1e406692e5-20230321` (2023-03-21).
Ao acrescentar esse diretório ao PATH do processo, o Python do venv encontra
ambos via `shutil.which`. Nenhuma variável persistente do Windows foi modificada.
Foi gerado um MP3 sintético de 1 segundo/440 Hz em `workspace/environment-check`
e convertido pela função existente `decode_to_wav`. SoundFile e FFprobe
confirmaram WAV PCM de 16 bits, mono, 22050 Hz e duração de 1 segundo.
Essa validação não utilizou músicas do usuário nem modelos.

Tentativa posterior de instalação CUDA no venv:
`python -m pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu126`.
Falhou por bloqueio de conexão (`WinError 10013`) ao índice oficial. A mensagem
subsequente de ausência de distribuição não comprova incompatibilidade: o índice
não pôde ser consultado. Nenhum pacote torch/torchaudio foi instalado e nenhuma
operação CUDA pôde ser executada. O usuário informou FFmpeg no PATH, mas os
comandos ffmpeg/ffprobe continuam não resolvidos nesta sessão mesmo após atualizar
o PATH a partir das variáveis persistidas.

`analyzer/.venv` foi recriado com o Python 3.11.9 instalado fora da Microsoft
Store. O usuário executou a instalação de dependências no seu terminal.
As verificações posteriores realizadas nesta sessão foram:

- `python -m pip list`: analisador 0.1.0 instalado em modo editável;
  NumPy 2.4.6, SciPy 1.17.1, Librosa 0.11.0, SoundFile 0.14.0,
  Matplotlib 3.11.2, pytest 9.1.1 e Ruff 0.17.0 disponíveis.
- `python -m pip check`: nenhum conflito declarado encontrado.
- `python -m pytest`: **5 testes passaram**.
- `python -m ruff check .`: **8 erros I001**, de organização de imports,
  no código e nos testes. Não foram corrigidos nesta validação.
- `python -m karaoke_analyzer --help`: executou corretamente.
- Importações de Librosa, SciPy, SoundFile e Matplotlib executaram corretamente.
  `librosa.pyin` em um seno sintético de 440 Hz (4096 amostras a 22050 Hz)
  produziu 17 frames voiced e mediana de F0 aproximadamente 440 Hz.
  Essa verificação não substitui uma análise de MP3 ou validação de separação.
- PyTorch, torchaudio e Demucs ausentes do venv.
- FFmpeg e FFprobe ausentes do PATH, mesmo após incorporar o PATH persistido
  do usuário e da máquina.
- `nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader`:
  RTX 3070, driver 581.80, 8192 MiB.

A base Python está preparada para os testes unitários; GPU, decoding MP3 e
separação ainda não foram validados. Próximo passo: disponibilizar FFmpeg e
FFprobe e instalar torch/torchaudio CUDA no mesmo venv, a partir do índice
oficial selecionado para a máquina. Os registros abaixo são históricos.

## Histórico: tentativa com Python 3.15

- Recriado `analyzer/.venv` pelo executável instalado em
  `%LOCALAPPDATA%\Programs\Python\Python315\python.exe`, com `-m venv`.
- Verificados `python --version` (3.15.0) e `python -m pip --version`
  (pip 26.2.1 dentro do venv).
- `python -m pip install -e '.[dev]'`: falhou ao obter setuptools do PyPI
  por bloqueio de conexão (`WinError 10013`). Nenhuma dependência instalada.
- Tentativa explícita de wheels CUDA: `python -m pip install --only-binary=:all:
  torch torchaudio --index-url https://download.pytorch.org/whl/cu126`:
  nenhum wheel torch correspondente encontrado. Isso não constitui validação
  completa de todos os índices ou versões possíveis.
- `python -m pytest`, `python -m ruff check .` e
  `python -m karaoke_analyzer --help`: módulos ausentes.
- `python -m pip check`: não encontrou requisitos quebrados, mas o ambiente
  ainda não contém as dependências do analisador.
- Validação do TOML e do especificador via packaging incluído no pip:
  aceita 3.11 e 3.15, rejeita 3.12/3.13/3.14/3.16.
- README atualizado para descrever o caráter experimental do 3.15.

O [anúncio oficial do PyTorch 2.13](https://pytorch.org/blog/pytorch-2-13-release-blog/)
declara wheels Python 3.15 somente para Linux nessa versão, sem Windows/macOS.
A afirmação anterior de suporte genérico ao 3.15 precisava dessa ressalva.
CUDA e Demucs continuam sem validação. Nenhum peso de modelo foi baixado.

Próximo passo: executar a instalação de `.[dev]` em uma sessão com acesso ao
PyPI e repetir testes/Ruff/CLI. Para GPU no Windows, confirmar primeiro um par
torch/torchaudio com wheels CUDA para CPython 3.15; se indisponível, manter um
venv Python 3.11 separado para essa etapa.

As evidências abaixo registram a inspeção inicial, anterior à criação do venv 3.15.

## Evidências

- `AGENTS.md`, `README.md`, `analyzer/pyproject.toml`, código Python, testes,
  contrato v1 e projeto/scripts Godot foram inspecionados.
- `python --version` e `py -0p`: comandos ausentes no PATH da sessão.
- `D:\Anaconda\python.exe --version`: Python 3.8.8.
- `D:\Anaconda\envs\ifood\python.exe --version`: Python 3.9.12.
- `D:\Anaconda\envs\keras\python.exe --version`: Python 3.10.8.
- O projeto exige `>=3.11,<3.12`; esses interpretadores são incompatíveis.
- O alias Python 3.11 da Microsoft Store existe, mas sua execução falhou
  por impossibilidade de acesso ao arquivo. O Python de `C:\env` também
  falhou ao tentar usar esse alias como interpretador base.
- `ffmpeg -version` e `ffprobe -version`: comandos ausentes no PATH.
  A entrada antiga `D:\AI Voice\ffmpeg-n6.0-latest-win64-gpl-6.0\bin`
  no PATH aponta para um diretório inexistente.
- `nvidia-smi`: GeForce RTX 3070, 8192 MiB, driver 581.80,
  indicador CUDA 13.0. Isso não demonstra execução CUDA via PyTorch.
- `nvcc --version`: CUDA Toolkit 12.4.99. Os diretórios de toolkit 12.4
  e 12.6 existem; o PATH seleciona primeiro o 12.4.
- No ambiente Anaconda Python 3.10, `torch`, `torchaudio`, `pytest`, `ruff`,
  `librosa` e `soundfile` não foram encontrados. `numpy` e `pip` existem.
- `python -m pytest analyzer/tests` e `python -m ruff check analyzer`,
  usando esse Python 3.10: falharam por ausência dos respectivos módulos.
  A importação de `torch` falhou com `ModuleNotFoundError`.
- Consulta HTTP HEAD ao instalador oficial Python 3.11.9 em python.org:
  falhou com “Impossível conectar-se ao servidor remoto”.
- Uma simulação de criação Conda de Python 3.11, com prefixo e caches
  dentro de `workspace/setup`, não produziu resultado e foi interrompida.
- `git status --short`: a pasta não foi reconhecida como repositório Git.

Na inspeção inicial, não foi criado um ambiente virtual utilizável nem foram instalados pacotes.
Não foram baixados modelos ou executada análise/separação de música.

## Retomada recomendada

1. Disponibilizar Python 3.11 de uma distribuição oficial executável nesta
   sessão e FFmpeg/FFprobe no PATH. Corrigir a entrada inválida do FFmpeg.
2. Restaurar acesso aos índices oficiais de pacotes para a instalação.
3. Criar o ambiente com o caminho explícito do Python 3.11, caso `py`
   continue indisponível:

   ```powershell
   cd D:\Dev\karaoke\karaoke-poc\analyzer
   # Substituir o caminho abaixo pelo interpretador Python 3.11 validado.
   & 'C:\caminho\python.exe' -m venv .venv
   .\.venv\Scripts\python.exe -m pip install --upgrade pip
   ```

4. Selecionar Windows/Pip/Python/CUDA no seletor oficial do PyTorch:
   https://pytorch.org/get-started/locally/. Instalar torch e torchaudio
   com versões correspondentes e wheel CUDA; não instalar um build CPU
   como substituição. Não é necessário adicionar torchvision ao analisador.
5. Instalar a base já declarada, validar dependências e executar verificações:

   ```powershell
   .\.venv\Scripts\python.exe -m pip install -e '.[dev]'
   .\.venv\Scripts\python.exe -m pip check
   .\.venv\Scripts\python.exe -m pytest
   .\.venv\Scripts\python.exe -m ruff check .
   .\.venv\Scripts\python.exe -m karaoke_analyzer --help
   .\.venv\Scripts\python.exe -c "import torch, torchaudio; print(torch.__version__, torchaudio.__version__, torch.version.cuda); print(torch.cuda.is_available()); x = torch.ones(4, device='cuda'); print(x.sum().item()); torch.cuda.synchronize()"
   ```

6. Avaliar o extra opcional Demucs separadamente antes de instalá-lo.
   O próprio README alerta sobre compatibilidade de suas dependências com
   PyTorch. Os testes atuais são cinco casos de exportação/segmentação e
   não comprovam decoding, separação, GPU ou integração com Godot.
   A aprovação para baixar pesos continua pendente para uma etapa futura.

Os comandos de retomada acima são recomendações, não execuções realizadas.
