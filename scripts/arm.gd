extends Node2D

signal color_changed(color: Color, name: String)

@export var paint_blob_scene: PackedScene
@export var fire_interval := 0.07
@export var muzzle_offset := Vector2(24, 0)
@export var projectile_speed := 750.0

const SHOOT_SFX_PATH := "res://assets/sfx/fire-paintball.wav"
const SHOOT_PITCH_VARIATIONS: Array[float] = [0.12, 0.08, 0.04, 0.0, -0.04, -0.08, -0.12]

const COLOR_MAP := {
    KEY_1: {"color": Color(0.4, 0.7, 1.0), "name": "Blue"},
    KEY_2: {"color": Color(1.0, 0.9, 0.0), "name": "Yellow"},
    KEY_3: {"color": Color(0.0, 0.9, 0.3), "name": "Green"},
    KEY_4: {"color": Color(0.6, 0.2, 0.9), "name": "Purple"},
    KEY_5: {"color": Color(1.0, 0.6, 0.0), "name": "Orange"},
    KEY_6: {"color": Color(1.0, 0.1, 0.1), "name": "Red"}
}

const COLOR_ORDER := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]

var _current_color_key: int = KEY_1
var _current_color: Color = COLOR_MAP[_current_color_key]["color"]
var _current_color_name: String = COLOR_MAP[_current_color_key]["name"]

var _cooldown := 0.0

var _shoot_sfx: AudioStreamPlayer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
    if paint_blob_scene == null:
        push_warning("Arm has no paint_blob_scene assigned")
    add_to_group("paint_color_source")
    _rng.randomize()
    _shoot_sfx = get_parent().get_node_or_null("ShootSFX")
    if _shoot_sfx:
        _shoot_sfx.bus = "SFX"
        if not _shoot_sfx.stream:
            var stream: AudioStream = load(SHOOT_SFX_PATH)
            if stream:
                _shoot_sfx.stream = stream
            else:
                push_warning("Arm could not load shoot SFX at %s" % SHOOT_SFX_PATH)
        print("[Arm] SFX node ready stream=", _shoot_sfx.stream)
    else:
        print("[Arm] Error: ShootSFX node not found")
    _emit_color_changed()

func _process(delta: float) -> void:
    var target := get_global_mouse_position()
    look_at(target)
    _cooldown = maxf(_cooldown - delta, 0.0)

    for key in COLOR_MAP.keys():
        if key != _current_color_key and Input.is_key_pressed(key):
            _set_current_color_key(key)
            break

    if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        _fire()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        var mouse_event := event as InputEventMouseButton
        if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _cycle_color(-1)
        elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _cycle_color(1)

func _fire() -> void:
    if _cooldown > 0.0 or paint_blob_scene == null:
        return

    if _shoot_sfx:
        if SHOOT_PITCH_VARIATIONS.size() > 0:
            var pitch_offset: float = SHOOT_PITCH_VARIATIONS[_rng.randi_range(0, SHOOT_PITCH_VARIATIONS.size() - 1)]
            _shoot_sfx.pitch_scale = 1.0 + pitch_offset
        if _shoot_sfx.playing:
            _shoot_sfx.stop()
        _shoot_sfx.play()
        print("[Arm] SFX playing for fire action")
    else:
        print("[Arm] Error: Cannot play SFX, node not found")

    var muzzle_global := global_position + (global_transform.x * muzzle_offset.x) + (global_transform.y * muzzle_offset.y)
    var paint_blob := paint_blob_scene.instantiate()
    paint_blob.global_position = muzzle_global
    var direction := (get_global_mouse_position() - muzzle_global).normalized()
    var impulse := direction * projectile_speed
    paint_blob.rotation = direction.angle()
    if paint_blob.has_method("apply_impulse"):
        paint_blob.apply_impulse(impulse)
    paint_blob.linear_velocity = impulse

    if paint_blob.has_method("set_color"):
        paint_blob.set_color(_current_color, _current_color_name)

    if "color" in paint_blob:
        paint_blob.color = _current_color

    get_tree().root.add_child(paint_blob)
    _cooldown = fire_interval

func _set_current_color_key(key: int) -> void:
    if not COLOR_MAP.has(key):
        return
    _current_color_key = key
    var info: Dictionary = COLOR_MAP[key]
    _current_color = info["color"]
    _current_color_name = info["name"]
    _emit_color_changed()

func _cycle_color(step: int) -> void:
    if step == 0:
        return
    var count := COLOR_ORDER.size()
    if count == 0:
        return
    var current_index := COLOR_ORDER.find(_current_color_key)
    if current_index == -1:
        current_index = 0
    var next_index := (current_index + step) % count
    if next_index < 0:
        next_index += count
    var next_key := int(COLOR_ORDER[next_index])
    if next_key != _current_color_key:
        _set_current_color_key(next_key)

func _emit_color_changed() -> void:
    emit_signal("color_changed", _current_color, _current_color_name)

func get_current_color_info() -> Dictionary:
    return {
        "color": _current_color,
        "name": _current_color_name
    }
