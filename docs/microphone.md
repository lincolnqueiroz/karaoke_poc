# Captura de microfone no Godot

Abra `game/project.godot` e execute com F5. Em **Configurações**, selecione o
dispositivo e o ganho e clique em **Salvar configurações**. Os valores são
salvos localmente em `user://settings.cfg`. Em **Jogar**, escolha uma música e
clique em **Ativar microfone** na preparação. Use fones para evitar que a música reproduzida
entre no microfone. O traço verde mostra o pitch estimado da sua voz; as notas
azuis continuam sendo a referência. O indicador mostra nota, frequência e nível
de entrada. **Desativar microfone** libera a captura e limpa o traço.
Na preparação, teste a entrada sem avançar a música. Clique em **Começar a
cantar** para iniciar uma rodada após uma contagem de três segundos.

A captura começa somente após o clique. Não grava arquivos nem envia áudio pela
rede. Um bus com volume de saída zero permite analisar o sinal sem reproduzir
a voz nas caixas. A captura também alimenta a [pontuação do MVP](scoring.md).

## Ajustes e limites

### Testar microfone sem música

Em **Configurações**, selecione o microfone e o ganho e clique em **Testar
microfone**. A tela de canto livre mostra somente o traço verde da captura,
com histórico móvel de oito segundos, sem carregar uma canção ou pontuar.
Notas graves aparecem embaixo e agudas em cima; silêncio ou áudio sem pitch
interrompem o traço. O indicador mostra nota, frequência e nível em dB com ganho.

O teste usa os valores selecionados na tela, mesmo antes de salvar. A calibração
salva é usada quando dispositivo e ganho correspondem ao perfil; se você mudar
esses valores, calibre novamente para adaptar os demais parâmetros.
A música de fundo pausa durante o teste. **Desativar microfone** interrompe a
captura; **Ativar microfone** retoma. **Voltar** libera o dispositivo, retorna às
configurações preservando os campos e retoma a música de fundo se ela tocava.
Este modo não grava nem reproduz a voz nas caixas.

### Calibração por dispositivo

Em **Configurações**, escolha o microfone e clique em **Calibrar microfone**.
A música de fundo é interrompida durante a medição e retomada ao fechar a janela.

1. Clique em **Medir silêncio** e fique em silêncio por três segundos.
2. Clique em **Medir voz** e sustente “aaa” por cinco segundos no seu tom
   confortável. Para investigar dificuldades com voz grave, use esse registro;
   não cante agudo apenas para conseguir uma detecção.
3. Clique em **Aplicar calibração**. Ganho, limiar e sensibilidade são salvos
   localmente e aplicados às próximas rodadas para o dispositivo selecionado.

A calibração mede a entrada sem ganho digital. Usa o ruído observado para
definir o limiar e o nível da voz para sugerir ganho entre 0 e +30 dB. Pode
relaxar o critério de periodicidade do estimador de 0,15 até no máximo 0,30;
sem calibração permanece o critério original de 0,15. Exige voz reconhecível
em pelo menos 60% das janelas, separação de pelo menos 10 dB do ruído e
ausência de som tonal significativo na etapa de silêncio. A faixa de pitch
continua sendo 65–1000 Hz e não há encaixe na referência da música.

Mudar manualmente o dispositivo ou o ganho e salvar descarta a calibração
anterior; calibre novamente nas novas condições. O perfil é associado ao nome
do dispositivo informado pelo Godot, incluindo `Default` quando escolhido;
prefira selecionar o dispositivo explicitamente.

A calibração não recupera frequências ausentes ou sinal distorcido. No teste
relatado com um headset Bluetooth, apenas vozes muito agudas geravam pitch.
A causa ainda não foi isolada; a função deve ser validada com esse headset,
comparando também outro microfone se a medição de voz falhar. Não há ajuste
automático de latência nesta etapa.

- **Ganho** em Configurações começa em +12 dB e pode variar de 0 a +30 dB.
  Amplifica digitalmente a entrada antes do filtro de nível; não altera o ganho
  físico nem as configurações do Windows. O nível mostrado já inclui esse ganho.
  Aumente aos poucos se a voz ficar abaixo do limiar. Se ruído começar a gerar
  pitch ou aparecer o aviso de nível alto, reduza. Ganho também amplifica ruído
  e não recupera um sinal já distorcido ou uma voz encoberta pelo ambiente.
- O seletor de oitava começa em **Oitava original**. Para cantar uma oitava
  abaixo da gravação, escolha **Voz grave (+1 oitava)**; uma oitava acima,
  **Voz aguda (-1 oitava)**. O ajuste desloca apenas o traço verde em 12 semitons;
  frequência/nota no indicador continuam sendo as medidas reais. Desvios de
  afinação dentro da oitava permanecem visíveis. A gravação e a referência não
  são transpostas. Escolha conforme o registro cantado, independentemente do
  gênero da pessoa. Isso não corrige canto em outra tonalidade nem erros do
  estimador; não há encaixe automático do pitch na nota de referência.
  A oitava escolhida também se aplica à pontuação.

- No nó `Microphone`, **Noise Gate Db** define o limiar de entrada, inicialmente
  -45 dB. Reduza para uma entrada muito baixa; aumente se ruído gerar detecções.
- No nó raiz, **Microphone Latency Seconds** compensa atraso adicional do
  dispositivo. Comece em zero e ajuste após comparar o canto com a referência.
  A idade do centro da janela de análise já é descontada automaticamente.
- **Visual Offset Seconds** continua ajustando a referência; não desloca o
  traço ao vivo em relação ao cursor.
- O estimador usa janelas de 1024 amostras a aproximadamente 12 kHz e atualiza
  a cada 50 ms ou mais. A faixa estimada é 65–1000 Hz. A grade visual permanece
  em MIDI 48–84 por padrão e se expande para incluir notas graves ou agudas
  presentes na referência; alturas fora dessa faixa expandida aparecem nas bordas.
- Ruído, acompanhamento vazando no microfone, harmonias e erros de oitava
  podem afetar o resultado. O pitch é uma estimativa monofônica contínua,
  ainda sem segmentação ou quantização das notas cantadas.

Se a abertura falhar, confira o dispositivo e as permissões de microfone para
aplicativos desktop nas configurações de privacidade do Windows. Dispositivos
conectados após abrir a rodada exigem voltar ao menu. Ao reabrir Configurações,
a lista de dispositivos é atualizada. Se o
dispositivo salvo não estiver disponível, selecione e salve outro antes de jogar.

## Validação

### Diagnóstico de “Sem pitch estável”

Esse feedback significa que o jogo recebeu sinal acima do limiar de entrada,
mas o estimador não encontrou periodicidade suficiente na faixa de 65–1000 Hz.
Não confirma que o sinal recebido seja a voz do jogador. O nível em dB mostrado
já inclui o ganho digital configurado no jogo.

1. Selecione explicitamente o microfone em **Configurações** e salve.
2. Na preparação, reduza temporariamente o volume da música de fundo a zero.
   Compare o nível em silêncio com o nível ao sustentar “aaa”.
3. Confira se uma gravação pelo Windows contém sua voz claramente usando o
   mesmo dispositivo. Se o nível quase não variar no jogo, investigue entrada
   incorreta ou ruído predominante antes de aumentar o ganho.
4. Se a voz estiver clara no Windows mas continuar sem pitch no jogo, registre
   dispositivo, tipo de conexão, ganho e os dois níveis para investigar o
   estimador. Não trate a redução do critério de confiança como correção
   automática: ela também pode aceitar ruído como nota e afetar a pontuação.

O usuário relatou esse problema no teste em outro computador. A causa e a
compatibilidade desse dispositivo ainda estão em investigação.

Da raiz do projeto, usando o executável Godot disponível:

```powershell
godot --headless --path game --script res://tests/test_microphone.gd
godot --headless --audio-driver WASAPI --path game --script res://tests/test_microphone.gd
```

O primeiro comando verifica tons conhecidos, silêncio, ruído, harmônicos e
consumo de buffers estéreo sem hardware de entrada. O segundo também verifica
a captura de áudio gerado em um bus silencioso; não abre o microfone físico.
Execute ainda `test_timeline.gd` e `test_lyrics.gd` pelo mesmo mecanismo.

Na sessão de implementação, os testes sintéticos e o bus WASAPI passaram.
A abertura do microfone físico retornou acesso negado do Windows
(`0x80070005`); portanto, canto real, latência do dispositivo e alinhamento
precisam ser validados no terminal/editor do usuário.
