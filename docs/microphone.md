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
