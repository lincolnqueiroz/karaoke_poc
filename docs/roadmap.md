# Plano de evolução

## Validação da distribuição

- O usuário confirmou que o executável Windows funcionou bem no computador atual.
- **Pendente, adiado pelo usuário:** testar `dist/Karaoke` em outro computador
  Windows sem Python nem FFmpeg instalados. Conferir importação offline,
  reprodução, microfone, pontuação e persistência da biblioteca; validar CPU
  e CUDA quando houver GPU compatível.

## Próxima etapa do MVP

- Captura, ganho, ajuste de oitava e traço de pitch validados pelo usuário.
- Pontuação inicial implementada com afinação e cobertura; calibrar tolerâncias
  com canto real e conferir justiça nas transições e nos trechos problemáticos
  da referência. Ver [regras e testes](scoring.md).

O fluxo de preparação, contagem regressiva, resultado e novas rodadas está
implementado; validar apresentação e uso completo no editor com microfone.

A importação de MP3 e LRC pelo seletor também está implementada, com análise
Python separada e publicação da música após conclusão. Validar agora uma
segunda música completa e conferir a qualidade da referência antes de pontuar.

## Importação opcional de letras do LRCLIB

Integração de busca e seleção implementada com [LRCLIB](https://lrclib.net/),
aproveitando o suporte atual a LRC. Ver [fluxo e configuração](song-import.md#letras-online).
Pendente: validar a busca real por HTTPS no computador do usuário.

A documentação oficial foi conferida: `/api/search` permite buscar por título
e artista; `/api/get/{id}` recupera o resultado escolhido. `syncedLyrics`
contém LRC com tempos por verso e pode estar ausente. A API atualmente permite
acesso anônimo sem chave obrigatória. Proposta: usar HTTPRequest do Godot na
tela de importação, sem dependências Python adicionais, com seleção e prévia
do resultado antes de salvar. Validar HTTPS também no executável exportado.

- Consultar a [documentação oficial](https://lrclib.net/docs) e validar os
  endpoints, condições de uso e limites disponíveis na época da implementação.
- Buscar candidatos por título, artista e, quando disponível, álbum e duração.
- Exibir os resultados para selecionar a gravação correta; versões ao vivo,
  remixes e edições diferentes podem ter tempos incompatíveis.
- Priorizar letras sincronizadas em LRC. Informar quando houver apenas texto
  sem tempos, sem inventar sincronização.
- Validar o LRC com o parser existente e conferir duração/alinhamento com o áudio.
- Salvar o arquivo na pasta `lyrics/` da música, em `workspace/songs/` no editor
  ou na biblioteca em `user://songs/` no executável, preservando arquivos
  existentes e registrando a origem e o identificador do resultado localmente.
- Associar a letra salva pelo mecanismo existente de descoberta da biblioteca,
  sem mudar o contrato de notas.
- Manter busca/download como preparação opcional: a reprodução no Godot deve
  continuar funcionando offline, sem chamadas ao LRCLIB durante a música.
- Tratar ausência de resultados e falhas de rede explicitamente. Testes devem
  usar respostas simuladas, sem depender do serviço.

A importação manual de LRC permanece disponível. A integração não inclui
transcrição automática, download de áudio ou envio de MP3s ao serviço.
