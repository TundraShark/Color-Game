extends Control

func _ready():
    # Focus the first button for keyboard navigation
    $VBoxContainer/ButtonsContainer/PlayButton.grab_focus()
    # Set BGM to loop
    var audio_manager = get_node_or_null("/root/AudioManager")
    if audio_manager and audio_manager.has_method("ensure_music_playing"):
        audio_manager.ensure_music_playing()
    # Debug autoplay
    if audio_manager and audio_manager.has_method("is_music_playing"):
        audio_manager.is_music_playing()

func _process(_delta):
    var audio_manager = get_node_or_null("/root/AudioManager")
    if audio_manager and audio_manager.has_method("is_music_playing") and audio_manager.is_music_playing():
        pass  # Could add a periodic check if needed

func _on_play_pressed():
    # Change to the main game scene
    get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_options_pressed():
    # Change to options scene
    get_tree().change_scene_to_file("res://scenes/options.tscn")

func _on_credits_pressed():
    # Change to credits scene
    get_tree().change_scene_to_file("res://scenes/credits.tscn")

func _on_exit_pressed():
    # Quit the game
    get_tree().quit()
