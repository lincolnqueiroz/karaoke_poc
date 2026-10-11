# Importar músicas pelo seletor

Execute o projeto com F5 e abra **Jogar → Importar música**.

1. Escolha um MP3 que você tenha autorização para usar.
2. Informe o **Título** (obrigatório) e, se desejar, o **Artista**. Ambos têm
   limite de 200 caracteres; o seletor mostra o título e o artista informado.
3. Escolha uma única opção de letra: **Sem letra**, **Importar arquivo LRC**
   em UTF-8, ou **Buscar letra online — LRCLIB**. Para buscar, informe título
   e artista, clique em buscar, selecione a gravação e confira a prévia.
   Resultados sem LRC válido são omitidos. Uma diferença de duração acima
   de 2 s entre resultado e MP3 gera aviso; não implica ajuste automático.
   Alterar título, artista ou MP3 invalida a seleção online.
3. O Python do venv é preenchido a partir de `analyzer/.venv/Scripts/python.exe`.
   Confira esse caminho. Não é necessário ativar o venv no terminal.
4. Se FFmpeg/FFprobe não estiverem no PATH herdado pelo Godot, selecione a pasta
   que contém ambos. Reiniciar o editor também atualiza um PATH recém-alterado.
5. Mantenha **Separar voz com Demucs** para melhor estimativa da melodia e
   escolha CUDA ou CPU. CUDA exige o PyTorch CUDA instalado no venv e um
   dispositivo disponível; não há troca automática para CPU em caso de erro.
6. Por padrão, somente pesos em cache podem ser usados. Marque a autorização
   de download se quiser permitir que a biblioteca Demucs baixe seus pesos
   oficiais. Desmarcar a separação evita modelos, mas estima pitch na mistura
   completa e pode produzir uma referência menos confiável.
7. Clique em **Importar música**. A interface continua respondendo e informa
   a etapa atual. Ao concluir, o seletor atualiza a biblioteca automaticamente.

A barra representa etapas do pipeline, não uma estimativa precisa de tempo
restante. Separação e pitch podem levar vários minutos em uma música inteira.
O pitch é conferido em duas janelas de análise; essa etapa adicional pode
aumentar o tempo de importação. Os resultados brutos de ambas são preservados.
Nesta versão, espere a conclusão antes de voltar ou fechar; ainda não há
cancelamento ou fila de importações. Os controles são bloqueados durante o job.

## Arquivos e falhas

O analisador roda em um processo Python separado. Godot não executa ML nem
decodificação Python dentro do jogo. Os resultados ficam em
`workspace/songs/<nome>/`: cópia do MP3, manifesto v1, diagnósticos e, com
separação, stems. O LRC fica em `lyrics/`. O MP3 e o LRC de origem não são
alterados. Uma nova importação com o mesmo nome recebe um sufixo, sem substituir
o conteúdo anterior. Não há alteração do contrato de dados.

O processamento usa uma pasta temporária em `workspace/import-jobs/`, e só
publica a pasta final após concluir a análise. Falhas informam o motivo e
mantêm diagnósticos temporários, sem criar uma entrada incompleta no seletor.
Passe o mouse sobre a mensagem de erro para ver o diretório de diagnóstico.
MP3, LRC, modelos e resultados continuam fora do Git.

Ausência de FFmpeg/FFprobe, dependências Python ou CUDA gera erro explícito.
Se nenhuma nota for detectada, a importação avisa: a música pode ser ouvida,
mas é necessário conferir sua referência antes de usá-la para pontuação.
O parser de letras do jogo continua validando o conteúdo LRC ao abrir a música.

No editor, esta integração usa a estrutura local do repositório e o venv.
No jogo exportado, usa o analisador e o FFmpeg incluídos no pacote, com dados
na pasta do usuário; veja [distribuição Windows](windows-distribution.md).
A importação atual recebe arquivos locais, sem buscar YouTube ou LRCLIB.

## Verificação

```powershell
.\analyzer\.venv\Scripts\python.exe -m pytest analyzer/tests
godot --headless --path game --script res://tests/test_import.gd
godot --headless --path game --script res://tests/test_menu.gd
```

Os testes de unidade simulam análise, modelos e subprocessos. Na sessão de
implementação, um MP3 sintético de 1,5 segundo também percorreu o pipeline
real com FFmpeg, e a chamada pelo Godot passou com Demucs/CUDA e pesos em cache.
Os artefatos desse teste ficam em `workspace/environment-check/import-integration/`,
fora da biblioteca de músicas do usuário.
