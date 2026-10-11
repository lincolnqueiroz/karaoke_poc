# Pontuação do MVP

No menu principal, configure dispositivo e ganho; na preparação, escolha a
oitava. Ativar o microfone permite
testar a entrada sem pontuar. **Começar a cantar** abre o dispositivo caso
necessário e inicia uma contagem de três segundos. Música e avaliação começam
juntas do zero; a oitava fica bloqueada durante a rodada.

A tela final mostra pontos, afinação e cobertura após as últimas amostras.
O microfone é liberado ao concluir. **Jogar novamente** e **Reiniciar rodada**
voltam à preparação, zerando tempo, pontuação e traço, e preservando os ajustes
de voz. Desativar o microfone não pausa a avaliação: trechos vocais seguintes
sem sinal contam como silêncio. **Ouvir e acompanhar sem pontuar** apresenta
um resultado explicitamente sem pontuação, em vez de classificar como zero.

## Regras

- A música é dividida em intervalos de 50 ms, avaliados no centro. Somente
  intervalos com uma nota de referência entram no cálculo. Instrumentais não
  dão pontos nem descontam por cantar.
- A nota cantada recebe o deslocamento de oitava escolhido. Não há correção
  automática para encaixar erros na referência.
- Diferenças de até 50 cents (meio semitom) recebem crédito integral. Entre
  50 e 150 cents, o crédito diminui linearmente; a partir de 150 cents, é zero.
- **Afinação** é o crédito médio dos intervalos com pitch detectado.
  **Canto** é a porcentagem dos intervalos esperados com pitch detectado.
  **Pontos** = 10.000 × crédito médio de todos os intervalos esperados já
  avaliados, incluindo os sem voz. Cantar metade perfeitamente resulta em
  aproximadamente 5.000 pontos, 100% de afinação e 50% de canto.
- O resultado é normalizado pelo trecho já avaliado e pode diminuir durante
  a música. Não é um contador de pontos cumulativos por nota.
- O tempo da amostra desconta a idade da janela e **Microphone Latency
  Seconds**. A referência considera **Visual Offset Seconds**, acompanhando
  as notas que chegam ao cursor. Não há busca por uma nota próxima no tempo:
  entrar cedo ou tarde reduz a cobertura ou gera erro na transição.
- Uma amostra pode cobrir até 100 ms seguintes para acomodar variações normais
  entre callbacks. Não sustenta notas durante uma interrupção prolongada.
  Cada intervalo recebe no máximo um resultado, independentemente do FPS ou
  de callbacks repetidos. A finalização aguarda 300 ms mais a latência adicional.

## Limitações e validação

Os limiares são uma escolha inicial do MVP. O resultado depende da referência
estimada e do pitch capturado: erros de oitava, vazamento do acompanhamento e
notas ausentes podem tornar a avaliação injusta. Ainda não há bônus, combos,
persistência de resultados ou pontuação por verso. A cobertura mede pitch
detectado, não reconhecimento de letra ou identidade do cantor.

Execute `godot --headless --path game --script res://tests/test_scoring.gd`.
Os testes usam sinais/resultados simulados, sem microfone físico ou downloads,
e verificam tolerâncias, silêncio, duração, oitava, alinhamento, início tardio,
reset e prevenção de contagem duplicada. A calibração com canto real fica para
o teste no editor: compare uma frase afinada, a mesma frase deliberadamente
desafinada e um trecho em silêncio.
