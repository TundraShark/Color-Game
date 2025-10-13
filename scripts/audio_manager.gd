extends Node

const MUSIC_STREAM_PATH := "res://assets/bgm/bgm-1.ogg"
const MUSIC_FADE_DURATION := 1.0
const MUSIC_START_VOLUME_DB := -18.0
const MUSIC_SILENCE_VOLUME_DB := -40.0
const DEFAULT_MASTER_VOLUME := 0.8
const DEFAULT_SFX_VOLUME := 0.9
const DEFAULT_MUSIC_VOLUME := 0.05

var _base_stream: AudioStream
var _music_players: Array[AudioStreamPlayer] = []
var _stream_length: float = 0.0
var _active_index: int = 0
var _crossfade_pending := false
var _player_tweens: Dictionary = {}

func _ready() -> void:
    _base_stream = load(MUSIC_STREAM_PATH)
    if _base_stream:
        if _base_stream is AudioStreamOggVorbis:
            (_base_stream as AudioStreamOggVorbis).loop = false
        _stream_length = _base_stream.get_length()
    else:
        push_warning("AudioManager could not load music stream at %s" % MUSIC_STREAM_PATH)
    _init_music_players()
    _apply_initial_bus_volumes()
    set_process(true)
    ensure_music_playing()

func _process(_delta: float) -> void:
    if _music_players.is_empty():
        return
    if _stream_length <= 0.0:
        return
    var current_player := _music_players[_active_index]
    if current_player == null or not current_player.playing:
        return
    var remaining := _stream_length - current_player.get_playback_position()
    if remaining <= MUSIC_FADE_DURATION and not _crossfade_pending:
        _crossfade_pending = true
        _start_crossfade()

func ensure_music_playing() -> bool:
    if _music_players.is_empty():
        return false
    var current_player := _music_players[_active_index]
    if current_player == null:
        return false
    _ensure_stream(current_player)
    if current_player.playing:
        return true
    _prepare_player(current_player)
    current_player.volume_db = 0.0
    current_player.play()
    _crossfade_pending = false
    return current_player.playing

func stop_music() -> void:
    _crossfade_pending = false
    for player in _music_players:
        if player == null:
            continue
        _stop_tween(player)
        if player.playing:
            player.stop()
        player.volume_db = MUSIC_SILENCE_VOLUME_DB

func get_music_resource_path() -> String:
    return MUSIC_STREAM_PATH

func is_music_playing() -> bool:
    for player in _music_players:
        if player and player.playing:
            return true
    return false

func _init_music_players() -> void:
    _music_players.clear()
    _player_tweens.clear()
    for index in 2:
        var player := AudioStreamPlayer.new()
        player.name = "MusicPlayer_%d" % index
        player.bus = "Music"
        player.autoplay = false
        player.volume_db = MUSIC_SILENCE_VOLUME_DB
        add_child(player)
        _music_players.append(player)
        _ensure_stream(player)

func _ensure_stream(player: AudioStreamPlayer) -> void:
    if player == null or player.stream:
        return
    var stream := _create_stream_instance()
    if stream:
        player.stream = stream

func _prepare_player(player: AudioStreamPlayer) -> void:
    if player == null:
        return
    _ensure_stream(player)
    player.stop()
    player.volume_db = MUSIC_SILENCE_VOLUME_DB

func _apply_initial_bus_volumes() -> void:
    _set_bus_linear("Master", DEFAULT_MASTER_VOLUME)
    _set_bus_linear("SFX", DEFAULT_SFX_VOLUME)
    _set_bus_linear("Music", DEFAULT_MUSIC_VOLUME)

func _set_bus_linear(bus_name: String, value: float) -> void:
    var bus_index := AudioServer.get_bus_index(bus_name)
    if bus_index == -1:
        push_warning("AudioManager could not find audio bus '%s'" % bus_name)
        return
    AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))

func _start_crossfade() -> void:
    if _music_players.size() < 2:
        return
    var next_index := (_active_index + 1) % _music_players.size()
    var next_player := _music_players[next_index]
    _prepare_player(next_player)
    next_player.volume_db = MUSIC_START_VOLUME_DB
    next_player.play()
    _fade_player(next_player, 0.0, MUSIC_FADE_DURATION, false)

    var current_player := _music_players[_active_index]
    _fade_player(current_player, MUSIC_SILENCE_VOLUME_DB, MUSIC_FADE_DURATION, true)

    _active_index = next_index
    _crossfade_pending = false

func _create_stream_instance() -> AudioStream:
    if _base_stream == null:
        return null
    var stream := _base_stream.duplicate()
    if stream is AudioStreamOggVorbis:
        (stream as AudioStreamOggVorbis).loop = false
    return stream

func _fade_player(player: AudioStreamPlayer, target_db: float, duration: float, stop_on_complete: bool) -> void:
    if player == null:
        return
    _stop_tween(player)
    if duration <= 0.0:
        player.volume_db = target_db
        if stop_on_complete and player.playing:
            player.stop()
        return
    var tween: Tween = create_tween()
    tween.tween_property(player, "volume_db", target_db, duration)
    if stop_on_complete:
        tween.tween_callback(Callable(player, "stop"))
    tween.finished.connect(_on_tween_finished.bind(player))
    _player_tweens[player] = tween

func _stop_tween(player: AudioStreamPlayer) -> void:
    if not _player_tweens.has(player):
        return
    var tween: Tween = _player_tweens[player]
    if tween and is_instance_valid(tween):
        tween.kill()
    _player_tweens.erase(player)

func _on_tween_finished(player: AudioStreamPlayer) -> void:
    _player_tweens.erase(player)
