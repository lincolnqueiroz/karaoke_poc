# Validação de pitch — execução inicial

Execução em 11/10/2026, seguindo [o plano](pitch-validation-plan.md). Os artefatos
ficam em `workspace/pitch-validation/20261011-183539`: `REPORT.md`, `summary.json`,
diagnósticos por frame e saídas individuais. Os MP3s originais e a biblioteca
existente foram preservados. Não foi realizado build do jogo.

## Ambiente e verificação

- Python 3.11.9 no venv; PyTorch 2.14.1+cu126 com CUDA disponível, RTX 3070.
- SwiftF0 0.3.0 e ONNX Runtime 1.31.0 instalados pelo usuário após autorização.
  Dependência opcional `.[benchmark]`; pYIN permanece em produção.
- `python -m pytest analyzer/tests -q`: **97 passed, 2 xfailed**, em 13,05 s.
- Ruff nos scripts e testes adicionados: aprovado. `git diff --check`: aprovado.
- Três avisos do audioread sobre módulos descontinuados em Python 3.13; a
  execução usa 3.11 e concluiu os testes de FFmpeg.

Os testes novos cobrem extração real de tons graves/agudos, vibrato, ruído,
silêncio, taxas de amostragem, MP3 CBR/VBR, caminhos com espaços/Unicode,
arquivo corrompido e integração MP3 → notas sem GPU ou pesos.

## Achados

Concluíram com sucesso **12 execuções**: as cinco músicas completas, cada uma
na mistura e com separação Demucs/CUDA, e um trecho de 20 s em CPU e CUDA.
Os hashes confirmaram preservação dos originais em todas as execuções.

| Música | Duração (s) | Pipeline com separação (s) | pYIN 2048 / 4096 (s) | SwiftF0, F0 apenas (s) |
| --- | ---: | ---: | ---: | ---: |
| a_thousand_miles | 237,61 | 196,85 | 90,59 / 92,88 | 2,53 |
| amiga_da_minha_mulher | 248,08 | 243,98 | 113,30 / 117,21 | 2,30 |
| como_eu_quero | 273,43 | 224,96 | 113,47 / 97,05 | 3,20 |
| i_want_it_that_way | 219,27 | 189,52 | 91,10 / 86,38 | 2,34 |
| we_are | 112,42 | 99,17 | 46,61 / 44,58 | 1,00 |

Os tempos SwiftF0 usam os mesmos stems e a faixa mínima de 65,4 Hz;
as comparações adicionais com 46,875 Hz também concluíram. O pYIN das
comparações reutiliza os diagnósticos das execuções completas da mesma entrada.
Seu tempo acima vem da extração realmente executada no benchmark de produção.
Ambos os passes de pYIN somam aproximadamente 92–94% do pipeline com separação.

No trecho de 20 s, Demucs levou 15,87 s em CPU e 5,40 s em CUDA; o pipeline
completo levou 42,76 s e 36,89 s, respectivamente. Essa execução verifica ambos
os caminhos, mas não é uma comparação controlada de desempenho. pYIN continua
executando em CPU nos dois casos. O pico de RAM do processo pai nas músicas
completas ficou aproximadamente entre 967 e 2079 MiB, excluindo subprocessos.
O gráfico `timings.png` está junto ao relatório agregado.

Nos intervalos relatados anteriormente pelo usuário, o pipeline com separação
produziu cobertura de 58,0% em 00:26–00:28 e 47,6% em 01:08–01:10 de
`amiga_da_minha_mulher`. Em `como_eu_quero`, cobriu 93,3% de 00:52–00:57,
mas ainda gerou notas em 56,1% de 01:49–01:55, relatado como sem vocal.
Esses relatos aproximados orientam revisão; não constituem notas de referência
e não permitem atribuir os erros a uma etapa específica sem ouvir os stems.

As duas passagens de pYIN são o principal custo. O SwiftF0 é uma alternativa
promissora para experimentar, mas a comparação atual isola extração de F0 e
segmentação de passagem única: não inclui consenso/recuperação de produção e
não comprova melhora de precisão. Sua inicialização também fica fora do tempo
medido de detecção.

Nos tons sintéticos com harmônicos, ambos acertaram a faixa 65,4–1760 Hz
na região central medida quando o SwiftF0 usou `--swift-fmin 46.875`. Limitar
essa faixa a 65,4 Hz deixou o tom mais grave sem detecção; tons puros graves
também exigem cuidado. Não reduzir limiares indiscriminadamente para aumentar
cobertura.

Duas limitações foram reproduzidas e registradas como `xfail(strict=True)`:
cancelamento na média de canais estéreo em oposição de fase e fusão de ataques
repetidos na mesma altura com uma interrupção de 20 ms. Os testes documentam
essas limitações; nenhuma correção do algoritmo foi aplicada nesta execução.

## Limites e próximos passos

O usuário não possui notas revisadas. Precisão de pitch, F1 de notas,
erros de oitava e seleção correta da voz principal continuam sem medição nas
músicas reais. Cobertura temporal e quantidade de notas não substituem essas
métricas. Backing vocals e canto em grupo continuam casos ambíguos.

O conjunto disponível tem cinco músicas, abaixo das 20–30 previstas. Faltam
classificação do corpus, referências humanas, divisão por artista para
avaliação independente, estresse com arquivos longos e repetições controladas
com cache frio/quente. Houve testes simultâneos; os tempos são observacionais.
RAM mede somente o processo pai. A VRAM amostrada, quando disponível, mede o
dispositivo inteiro e inclui outros aplicativos.

O próximo passo é revisar trechos graves, ataques e vozes sobrepostas das
cinco músicas, comparando os diagnósticos de ambos os estimadores. Depois,
repetir os tempos com carga controlada antes de escolher um backend de
produção ou alterar a segmentação. O contrato JSON v1 permanece intacto.
