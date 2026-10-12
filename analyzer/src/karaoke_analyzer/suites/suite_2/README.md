# Suíte 2 — Demucs duplo

Experimento de segunda filtragem do vocal. Identificador `suite_2`, versão 1.

A primeira passagem aplica o Demucs ao MP3 original. A segunda aplica o mesmo
modelo `htdemucs` ao `vocals.wav` da primeira passagem, preservando o WAV estéreo.
O pitch é estimado sobre o vocal da segunda passagem. A atividade vocal compara
esse vocal com o mix original; o áudio reproduzido continua sendo o MP3 original.

Pitch, consenso, recuperação e segmentação reutilizam explicitamente a
implementação preservada da suíte 1, com os mesmos parâmetros. Esta suíte testa
somente o efeito da segunda separação. A suíte 1 continua sendo o padrão.

## Arquivos e execução

- `stems/htdemucs/<nome>/vocals.wav`: primeira passagem.
- `stems-pass-2/htdemucs/vocals/vocals.wav`: segunda passagem.
- Ambos os diretórios mantêm também o áudio rejeitado pelo Demucs.
- `song.json`, CSVs de diagnóstico e `analysis-suite.json`: resultado e identificação.

No Godot em depuração, selecione **Suíte 2 — Demucs duplo** na importação.
A separação fica obrigatória; escolha CPU ou CUDA normalmente. Downloads de
pesos continuam dependendo da opção existente. Nenhum novo modelo é necessário.

```powershell
.\analyzer\.venv\Scripts\python.exe -m karaoke_analyzer analyze workspace\downloads\we_are.mp3 --output workspace\suite-tests\suite_2\we_are --separate --device cuda --suite suite_2
```

Sem separação, o analisador rejeita a configuração explicitamente. Uma nova
importação preserva a música anteriormente importada para comparação.

## Hipótese e riscos

A segunda passagem pode remover instrumentos residuais, mas também remover voz,
introduzir artefatos ou manter a contaminação anterior. Não há garantia de melhora
nem de isolamento do vocal principal em coros. A separação aproximadamente dobra
seu trabalho e aumenta o uso de disco; o custo do pYIN permanece igual.

Compare os dois stems ouvindo-os e confira os intervalos `we_are` 00:17–00:19,
00:36–00:38 e 01:41–01:48. Use a suíte 1 nas mesmas músicas como controle e
verifique possíveis perdas de notas em músicas que já funcionavam bem.
