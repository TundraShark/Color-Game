extends Control

# Default volume values
const DEFAULT_MASTER_VOLUME = 0.8
const DEFAULT_SFX_VOLUME = 0.9
const DEFAULT_MUSIC_VOLUME = 0.7

var audio_bus_master = AudioServer.get_bus_index("Master")
var audio_bus_sfx = AudioServer.get_bus_index("SFX")
var audio_bus_music = AudioServer.get_bus_index("Music")

func _ready():
    # Initialize UI with current settings
    _load_settings()

func _load_settings():
    # Load fullscreen setting
    var is_fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
    $VBoxContainer/OptionsContainer/FullscreenContainer/FullscreenCheckBox.button_pressed = is_fullscreen

    # Load volume settings
    var master_volume = AudioServer.get_bus_volume_db(audio_bus_master)
    var sfx_volume = AudioServer.get_bus_volume_db(audio_bus_sfx)
    var music_volume = AudioServer.get_bus_volume_db(audio_bus_music)

    # Convert dB to linear for sliders (assuming default volumes if not set)
    var master_linear = db_to_linear(master_volume) if master_volume != 0 else DEFAULT_MASTER_VOLUME
    var sfx_linear = db_to_linear(sfx_volume) if sfx_volume != 0 else DEFAULT_SFX_VOLUME
    var music_linear = db_to_linear(music_volume) if music_volume != 0 else DEFAULT_MUSIC_VOLUME

    $VBoxContainer/OptionsContainer/VolumeContainer/MasterVolumeContainer/MasterVolumeSlider.value = master_linear
    $VBoxContainer/OptionsContainer/VolumeContainer/SFXVolumeContainer/SFXVolumeSlider.value = sfx_linear
    $VBoxContainer/OptionsContainer/VolumeContainer/MusicVolumeContainer/MusicVolumeSlider.value = music_linear

    # Update display values
    _update_volume_display(master_linear, sfx_linear, music_linear)

func _on_fullscreen_toggled(button_pressed):
    if button_pressed:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
    else:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_master_volume_changed(value):
    var db_value = linear_to_db(value)
    AudioServer.set_bus_volume_db(audio_bus_master, db_value)
    _update_master_volume_display(value)

func _on_sfx_volume_changed(value):
    var db_value = linear_to_db(value)
    AudioServer.set_bus_volume_db(audio_bus_sfx, db_value)
    _update_sfx_volume_display(value)

func _on_music_volume_changed(value):
    var db_value = linear_to_db(value)
    AudioServer.set_bus_volume_db(audio_bus_music, db_value)
    _update_music_volume_display(value)

func _update_volume_display(master_val, sfx_val, music_val):
    _update_master_volume_display(master_val)
    _update_sfx_volume_display(sfx_val)
    _update_music_volume_display(music_val)

func _update_master_volume_display(value):
    var percentage = int(value * 100)
    $VBoxContainer/OptionsContainer/VolumeContainer/MasterVolumeContainer/MasterVolumeValue.text = str(percentage) + "%"

func _update_sfx_volume_display(value):
    var percentage = int(value * 100)
    $VBoxContainer/OptionsContainer/VolumeContainer/SFXVolumeContainer/SFXVolumeValue.text = str(percentage) + "%"

func _update_music_volume_display(value):
    var percentage = int(value * 100)
    $VBoxContainer/OptionsContainer/VolumeContainer/MusicVolumeContainer/MusicVolumeValue.text = str(percentage) + "%"

func _on_back_pressed():
    # Go back to main menu
    get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
