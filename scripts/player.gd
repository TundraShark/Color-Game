extends CharacterBody2D

const MAX_SPEED := 240.0
const ACCELERATION := 1200.0
const AIR_ACCELERATION := 600.0
const FRICTION := 1400.0
const AIR_FRICTION := 200.0
const JUMP_SPEED := -420.0

var gravity: float = 980.0

func _ready() -> void:
    _ensure_input_actions()
    gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity"))

func _physics_process(delta: float) -> void:
    var velocity := self.velocity
    var direction := Input.get_axis("move_left", "move_right")

    var target_speed := direction * MAX_SPEED
    if direction != 0.0:
        var accel := ACCELERATION if is_on_floor() else AIR_ACCELERATION
        velocity.x = move_toward(velocity.x, target_speed, accel * delta)
    else:
        var decel := (FRICTION if is_on_floor() else AIR_FRICTION) * delta
        if abs(velocity.x) <= decel:
            velocity.x = 0.0
        else:
            velocity.x -= sign(velocity.x) * decel

    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = JUMP_SPEED
    else:
        velocity.y += gravity * delta

    velocity.x = clamp(velocity.x, -MAX_SPEED, MAX_SPEED)
    self.velocity = velocity
    move_and_slide()

func _ensure_input_actions() -> void:
    _ensure_action("move_left", [KEY_A, KEY_LEFT])
    _ensure_action("move_right", [KEY_D, KEY_RIGHT])
    _ensure_action("jump", [KEY_SPACE, KEY_W, KEY_UP])

func _ensure_action(action_name: String, keycodes: Array) -> void:
    if not InputMap.has_action(action_name):
        InputMap.add_action(action_name)
    for keycode in keycodes:
        if typeof(keycode) != TYPE_INT:
            continue
        if _has_key_event(action_name, keycode):
            continue
        var event := InputEventKey.new()
        event.physical_keycode = keycode
        event.keycode = keycode
        InputMap.action_add_event(action_name, event)

func _has_key_event(action_name: String, keycode: int) -> bool:
    for event in InputMap.action_get_events(action_name):
        if event is InputEventKey and event.physical_keycode == keycode:
            return true
    return false
