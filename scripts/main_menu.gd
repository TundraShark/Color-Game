extends Control

func _ready():
    # Focus the first button for keyboard navigation
    $VBoxContainer/ButtonsContainer/PlayButton.grab_focus()

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
