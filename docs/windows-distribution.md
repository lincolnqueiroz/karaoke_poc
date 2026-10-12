# Distribuição Windows do MVP

No editor, o projeto mantém o venv e `workspace/`. O jogo exportado procura
`analyzer/karaoke-analyzer.exe` e `tools/ffmpeg/` ao lado de `Karaoke.exe`.
Os campos de Python/FFmpeg aparecem somente no editor. Músicas, status,
diagnósticos e caches ficam em `user://`, normalmente
`%APPDATA%/Godot/app_userdata/Karaoke PoC/`. A biblioteca workspace não é migrada.

O analisador recebe o caminho absoluto por `--data-root` e restringe suas
saídas a essa pasta. Sem essa opção, o executável usa
`%LOCALAPPDATA%/KaraokePoC`. Demucs roda em subprocesso pelo mesmo executável
com a opção interna `--demucs`. Não há mudança no contrato song.json v1.

## Build

Na raiz, com pesos oficiais já baixados:

```powershell
.\analyzer\.venv\Scripts\python.exe -m pip install 'pyinstaller>=6,<7'
.\analyzer\build_windows.ps1 `
  -FFmpegDirectory 'D:\Downloads\ffmpeg-master-latest-win64-gpl-shared\ffmpeg-master-latest-win64-gpl-shared\bin' `
  -HuggingFaceCache "$env:USERPROFILE\.cache\huggingface"
```

`HuggingFaceCache` é HF_HOME, contendo `hub/models--adefossez--HTDemucs`.
Para pesos legados, use `-ModelCache` apontando para TORCH_HOME, contendo
`hub/checkpoints`; ambos podem ser fornecidos. Somente caches dos modelos são
copiados, não tokens. O script não baixa modelos/executáveis e recusa substituir
`dist/Karaoke` existente.

O pacote onedir inclui Python, dependências e o PyTorch atual do venv;
não troca a instalação CUDA. O script copia FFmpeg/FFprobe, DLLs e pesos e
executa `--help`. Os caches são copiados para os dados do jogador ao importar,
exigindo espaço adicional. CPU/CUDA permanecem opções explícitas.
Librosa é coletado como arquivos Python, pois seu código compilado via Numba
precisa desses caminhos para criar caches; apenas módulos no arquivo PYZ
causavam o erro `cannot cache function ... no locator available`.

Instale os templates correspondentes à versão do Godot e use o preset
**Windows Desktop**, ou:

```powershell
godot --headless --path game --export-release 'Windows Desktop' '../dist/Karaoke/Karaoke.exe'
```

O preset exclui testes e subpastas locais de demo. Antes da distribuição,
confira o pacote e inclua os avisos/licenças e materiais de redistribuição
exigidos pelas versões empacotadas, especialmente pelo FFmpeg GPL atual.
O instalador v0.1 e a coleta de avisos locais estão descritos abaixo. A coleta
não substitui a verificação das condições de redistribuição das dependências.

## Instalador v0.1

O build desta release fica em `dist/releases/v0.1/Karaoke`, preservando
`dist/Karaoke`. Para gerar outro pacote sem sobrescrever o anterior, passe
`-PackageDirectory` ao script de build do analisador e ajuste o destino da
exportação Godot para essa mesma pasta.

Depois de preparar o pacote completo, com Inno Setup 6/7 instalado:

```powershell
.\analyzer\.venv\Scripts\python.exe installer/collect_notices.py `
  dist/releases/v0.1/Karaoke --ffmpeg-license 'CAMINHO\LICENSE.txt'
.\installer\build_installer.ps1 -Compiler 'D:\Inno Setup 6\ISCC.exe'
```

`installer/karaoke.iss` instala por usuário em
`%LOCALAPPDATA%/Programs/KaraokePoC`, cria atalho no Menu Iniciar e oferece
atalho na área de trabalho. O desinstalador preserva biblioteca e configurações
em `user://`. O instalador produz um Setup.exe e partes `.bin` de até 1,5 GB em
`dist/releases/v0.1/installer`; todos devem ficar juntos para instalar.
Não copiar a pasta `Karaoke Smoke` antiga.

O relatório em inglês, incluindo verificações e pendências da versão, fica em
[release-v0.1.md](release-v0.1.md). A publicação da release não é automática.

Na geração v0.1, PyInstaller, exportação Godot e compilação Inno Setup 6.7.3
concluíram com sucesso. O instalador tem um EXE e dois BINs, totalizando 2,05 GB;
os checksums estão em `dist/releases/v0.1/SHA256SUMS.txt`. Os 82 testes Python e
as oito suítes Godot passaram; Ruff completo ainda aponta dois problemas antigos
de organização de imports. O pacote importou um tom sintético em CPU e separou
offline em CUDA, sem Python/FFmpeg externos no PATH.

O teste silencioso do instalador não conseguiu resolver a constante de pasta
`localappdata`: `SHGetFolderPath` retornou `0x80070002` neste ambiente de execução.
Não houve instalação de arquivos do aplicativo. A instalação e desinstalação
precisam ser validadas em uma sessão Windows normal. O helper de teste está em
`installer/test_installation.ps1`; preserva os dados e logs da tentativa em
`workspace/environment-check/v0.1 installer smoke/`.

## Validação pendente do pacote

`--help` não valida análise ou CUDA. Testar fora do repositório, em caminho
com espaços e sem Python/FFmpeg no PATH: importar MP3 sintético/LRC, separar
offline em CPU e CUDA, reproduzir, capturar microfone, pontuar e reabrir a
biblioteca. Hooks, imports dinâmicos e DLLs podem exigir ajustes após o build.
Não considerar o executável validado antes desses testes reais.

## Verificação realizada nesta etapa

O pacote final foi gerado em `dist/Karaoke`, com aproximadamente 4,78 GB.
`karaoke-analyzer.exe --help` passou. Com diretório de trabalho em uma pasta
de testes, em pastas com espaços e com PATH restrito ao System32,
o executável importou um MP3 sintético de 1,5 s em CPU sem separação (nota MIDI
69 por 1,5 s), e com Demucs offline em CPU e na RTX 3070/CUDA. A separação do
tom sem voz resultou em referência vazia, com o aviso esperado; esse teste
valida execução e publicação, não qualidade musical. MP3 e LRC foram copiados
para a biblioteca isolada e os diagnósticos permaneceram na pasta de dados.

78 testes Python, Ruff nos arquivos alterados e os testes Godot de menu e
importação passaram. Após o usuário instalar os templates 4.7.2, a exportação
Windows release concluiu com sucesso e gerou `Karaoke.exe` e `Karaoke.pck`.
O executável iniciou em headless com PATH restrito ao System32 e encerrou
após 30 frames com código 0, sem erros de GDScript. O log está em
`workspace/environment-check/karaoke-release.log`. O Godot emitiu o aviso de
certificados já observado neste ambiente. O usuário confirmou que o executável
funcionou bem no computador atual. **Pendente, adiado pelo usuário:** teste em
outro Windows sem Python/FFmpeg instalados, incluindo importação offline,
microfone, pontuação e persistência da biblioteca.

Resultados locais: `workspace/environment-check/package smoke/` e logs
`package-build-source.log` em `workspace/environment-check/`. O pacote
`dist/Karaoke Smoke` é uma tentativa anterior com o erro de cache; não distribuí-lo.
