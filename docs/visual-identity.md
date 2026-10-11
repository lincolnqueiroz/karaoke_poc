# Identidade visual

A interface usa uma estética noturna de karaokê: fundo quase preto e azul-escuro,
painéis escuros, texto claro e contornos luminosos. A paleta e o tema estão em
`game/scripts/neon_theme.gd`, compartilhados pelo menu, importação e gameplay.

- Azul néon `#35deff`: navegação, biblioteca e notas de referência.
- Magenta `#ff55cc`: configurações, título principal e detalhes.
- Verde `#64f5a6`: importar e iniciar a rodada; a voz mantém seu traço verde.
- Amarelo `#ffe16a`: foco de teclado, saída e destaques; o cursor continua amarelo.

Títulos, navegação e ações usam caixa alta e a fonte sem serifa padrão do Godot.
Títulos e artistas das músicas, letras e textos informativos mantêm sua escrita.
O resultado preserva a escala 0.0–10.0 e o gradiente vermelho–amarelo–verde.

O brilho usa sombras suaves de `StyleBoxFlat` e contornos de texto, sem depender
de pós-processamento HDR. O fundo dos menus usa a imagem local
`game/assets/images/backgrounds/menu.jpg`, cobrindo a janela sem distorção,
com recorte central quando a proporção difere e uma camada escura de 22%.
Os painéis opacos preservam a leitura dos controles. Sem a imagem, o tema
mantém o fundo em shader estático compatível com Compatibility.
O fundo da visualização de notas continua escuro. Os ícones lineares são vetoriais definidos no
código e renderizados pelo Godot; não requerem fontes ou imagens externas.

Os menus ficam centralizados, sem barra lateral. Jogar, Configurações e Sair
ficam no menu principal; Importar fica no seletor de músicas. Durante a análise,
os comandos de navegação não podem interromper a importação.

A trilha local `game/assets/audio/music/menu.mp3` toca em loop no menu principal,
seletor, configurações e importação, sem reiniciar a cada troca de página.
A trilha continua sem reiniciar na sala de espera antes de cantar. Ela para ao
começar a contagem regressiva e permanece parada durante o canto e o resultado.
Ao preparar outra rodada ou voltar ao menu ela recomeça. `lobby.mp3` ainda não
é usado. O arquivo de música fica ignorado pelo Git.

O canal `MenuMusic` envia para `Master`, separado de `Music` (canção) e `Effects`.
O controle Música de fundo (menus) começa em 30%, aplica o ajuste imediatamente
e salva junto com as configurações quando o usuário escolhe Salvar configurações.
O preset de exportação permite o MP3 da trilha, preservando a exclusão de músicas
locais em `demo/`. Nenhum novo executável foi gerado; a inclusão no pacote deverá
ser verificada no próximo build solicitado pelo usuário.

O efeito local `game/assets/audio/sfx/click.mp3` toca uma vez ao ativar botões
ou escolher itens de menus, inclusive com teclado. O autoload `UISounds`
conecta controles criados dinamicamente e mantém o som durante trocas de tela.
O efeito usa o canal `Effects`, respeitando os volumes geral e dos efeitos;
não altera o volume da música. Cliques rápidos reiniciam o efeito, evitando
acumular sons. O arquivo MP3 do efeito também fica ignorado pelo Git.

`game/assets/audio/sfx/countdown.mp3` toca uma única vez ao iniciar a contagem
de três segundos, tanto ao cantar quanto no acompanhamento. Usa `Effects` e
para ao reiniciar ou sair da cena. O arquivo local tem aproximadamente 3,53 s:
o último beep começa perto de 3 s e sua cauda termina naturalmente sobre o
início da canção, sem alongar a contagem visual ou alterar o relógio da música.

Validação: testes de menu, importação, gameplay, timeline e microfone sintético;
capturas renderizadas em OpenGL na RTX 3070, com janelas 1280×720 e 1100×640.
As páginas cabem na janela mínima e a importação mantém apenas rolagem vertical.
Não foi gerado um novo build. A avaliação final de conforto e legibilidade
durante uma sessão real permanece com o usuário.
