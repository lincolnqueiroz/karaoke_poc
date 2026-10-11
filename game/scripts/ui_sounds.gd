extends Node

const CLICK_PATH = "res://assets/audio/sfx/click.mp3"
var click_player: AudioStreamPlayer

func _ready() -> void:
    click_player = AudioStreamPlayer.new()
    click_player.bus = &"Effects"
    add_child(click_player)
    if ResourceLoader.exists(CLICK_PATH):
        var stream = load(CLICK_PATH) as AudioStreamMP3
        if stream != null:
            stream = stream.duplicate() as AudioStreamMP3
            stream.loop = false
            click_player.stream = stream
        else:
            push_warning("Não foi possível carregar o efeito de clique: " + CLICK_PATH)
    else:
        push_warning("Efeito de clique não encontrado: " + CLICK_PATH)
    get_tree().node_added.connect(connect_control)
    connect_existing(get_tree().root)

func connect_existing(node: Node) -> void:
    connect_control(node)
    for child in node.get_children():
        connect_existing(child)

func connect_control(node: Node) -> void:
    if node is BaseButton and not node.pressed.is_connected(play_click):
        node.pressed.connect(play_click)
    elif node is PopupMenu and not node.id_pressed.is_connected(on_item_selected):
        node.id_pressed.connect(on_item_selected)

func on_item_selected(_id: int) -> void:
    play_click()

func play_click() -> void:
    if click_player.stream != null:
        click_player.play() # Restart the short effect rather than stacking many clicks.

func _exit_tree() -> void:
    if is_instance_valid(click_player):
        click_player.stop()
