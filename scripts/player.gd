extends CharacterBody2D

const MAX_SPEED := 240.0
const ACCELERATION := 1200.0
const AIR_ACCELERATION := 600.0
const FRICTION := 1400.0
const JUMP_SPEED := -420.0
const SLIPPERY_FRICTION := 200.0
const SLIPPERY_ACCEL_MULT := 4.0
const SLIPPERY_SPEED_MULT := 2.3
const FOOT_SAMPLE_OFFSETS := [Vector2(0, 22), Vector2(-10, 20), Vector2(10, 20)]
const BOUNCY_LAYER_MASK := 32
const CONVEYOR_LAYER_MASK := 64
const VINE_LAYER_MASK := 128
const BOUNCY_DEFAULT_STRENGTH := 900.0
const AIR_FRICTION := 200.0
const SLOPE_DETECTION_NORMAL_Y := 0.995
const SLOPE_MIN_NORMAL_X := 0.08
const SLOPE_SLIDE_ACCEL := 650.0
const SLOPE_SLIDE_MAX_SPEED := 520.0
const SLOPE_STEEP_ACCEL_MULT := 2.2
const SLOPE_STEEP_MAX_MULT := 1.75
const BOUNCE_CHAIN_DECAY := 0.9
const BOUNCE_CHAIN_MIN_MULT := 0.75
const PUSH_FORCE := 320.0
const CAT_MEOW_PATH := "res://assets/sfx/cat-meow.wav"
const CAT_PURR_PATHS := [
    "res://assets/sfx/cat-purr-1.wav",
    "res://assets/sfx/cat-purr-2.wav",
    "res://assets/sfx/cat-purr-3.wav"
]
const CAT_PITCH_VARIATIONS: Array[float] = [0.12, 0.08, 0.04, 0.0, -0.04, -0.08, -0.12]
@export var conveyor_push_speed := 220.0
@export var conveyor_accel := 900.0
@export var climb_speed := 210.0
@export var climb_accel := 900.0
@export var camera_mouse_max_distance := 240.0
@export var camera_mouse_follow_speed := 8.0
@export var camera_edge_padding := Vector2(220.0, 160.0)
@export var bounce_min_speed := 500.0
@export var bounce_max_speed := 1000.0
@export var bounce_base_multiplier := 1.0
@export var bounce_bonus_multiplier := 1.2
const CLIMB_DETECTION_RADIUS := 22.0
const CLIMB_DETECTION_OFFSET := Vector2(0, -8)
const BULLET_TIME_SCALE := 0.1

var gravity: float = 980.0
var _on_slippery_paint := false
var _foot_area: Area2D
var _slippery_contacts := 0
var _slippery_speed_bonus := 0.0
var _slippery_decay_timer := 0.0
var SLIPPERY_ACCEL_GAIN := 150.0
var SLIPPERY_DECAY_RATE := 180.0
var SLIPPERY_DECAY_DELAY := 0.4
var _pending_bounce_strength := 0.0
var _bouncy_cooldown := 0.0
var _bounce_chain_multiplier := 1.0
var _conveyor_contacts := 0
var _conveyor_direction_sum := 0.0
var _on_conveyor := false
var _vine_contacts := 0
var _on_vine := false
var _vine_query_shape := CircleShape2D.new()
var _camera: Camera2D
var _last_fall_speed: float = 0.0
var _bounce_bonus_available := true
var _on_bouncy_surface := false
var _body_sprite: Sprite2D
var _facing_direction := 1
var _body_anim: AnimatedSprite2D
var _body_base_scale := Vector2.ONE
var _body_base_offset := Vector2.ZERO
var _body_base_position := Vector2.ZERO
var _body_texture_size := Vector2.ZERO
var _body_base_bottom := 0.0
var _crouch_scale := Vector2.ONE
var _is_crouching := false
var _scale_tween: Tween
var _collision_shape: CollisionShape2D
var _collision_rect: RectangleShape2D
var _collision_base_size := Vector2.ZERO
var _collision_base_position := Vector2.ZERO
var _collision_base_bottom := 0.0
var _meow_sfx: AudioStreamPlayer
var _purr_sfx: AudioStreamPlayer
var _purr_streams: Array[AudioStream] = []
var _rng := RandomNumberGenerator.new()
var _bullet_time_active := false
var _bullet_time_prev_scale := 1.0
var _slope_slide_speed := 0.0
var _slope_slide_direction := Vector2.ZERO
var _slope_slide_retained_velocity := Vector2.ZERO
var _slope_slide_max_limit := SLOPE_SLIDE_MAX_SPEED

func _ready() -> void:
    _ensure_input_actions()
    gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity"))
    z_index = 50
    _vine_query_shape.radius = CLIMB_DETECTION_RADIUS
    _rng.randomize()
    _bullet_time_prev_scale = Engine.time_scale
    _camera = get_node_or_null("Camera2D")
    if _camera:
        _camera.make_current()
    _body_sprite = get_node_or_null("Sprite2D")
    _body_anim = get_node_or_null("AnimatedSprite2D")
    if _body_sprite:
        _body_sprite.flip_h = _facing_direction < 0
    if _body_anim:
        _body_anim.flip_h = _facing_direction < 0
        _body_base_scale = _body_anim.scale
        _body_base_offset = _body_anim.offset
        _body_base_position = _body_anim.position
        if _body_anim.sprite_frames:
            var base_texture := _body_anim.sprite_frames.get_frame_texture("idle", 0)
            if base_texture:
                _body_texture_size = base_texture.get_size()
        if _body_texture_size == Vector2.ZERO:
            _body_texture_size = Vector2(1, 1)
        var half_height := (_body_texture_size.y * 0.5)
        _body_base_bottom = _body_base_position.y + (_body_base_offset.y + half_height) * _body_base_scale.y
        _crouch_scale = Vector2(_body_base_scale.x * 1.2, _body_base_scale.y * 0.5)
        _set_body_scale(_body_base_scale)
        _body_anim.play("idle")
    _collision_shape = get_node_or_null("CollisionShape2D")
    if _collision_shape:
        _collision_base_position = _collision_shape.position
        if _collision_shape.shape is RectangleShape2D:
            _collision_rect = _collision_shape.shape
            _collision_base_size = _collision_rect.size
            _collision_base_bottom = _collision_base_position.y + (_collision_base_size.y * 0.5)
        else:
            _collision_rect = null
    _meow_sfx = get_node_or_null("MeowSFX")
    if _meow_sfx:
        if _meow_sfx.stream == null:
            var meow_stream: AudioStream = load(CAT_MEOW_PATH)
            if meow_stream:
                _meow_sfx.stream = meow_stream
        _meow_sfx.bus = "SFX"
    _purr_sfx = get_node_or_null("PurrSFX")
    if _purr_sfx:
        _load_purr_streams()
        _purr_sfx.bus = "SFX"
    _foot_area = get_node_or_null("FootArea")
    if _foot_area:
        _foot_area.monitoring = true
        _foot_area.monitorable = false
        _foot_area.collision_layer = 0
        _foot_area.collision_mask = 16 | BOUNCY_LAYER_MASK | CONVEYOR_LAYER_MASK | VINE_LAYER_MASK
        _foot_area.body_entered.connect(_on_foot_body_entered)
        _foot_area.body_exited.connect(_on_foot_body_exited)
        _foot_area.area_entered.connect(_on_foot_area_entered)
        _foot_area.area_exited.connect(_on_foot_area_exited)
    else:
        pass

func _exit_tree() -> void:
    if _bullet_time_active:
        Engine.time_scale = _bullet_time_prev_scale
        _bullet_time_active = false

func _physics_process(delta: float) -> void:
    var current_fall_speed: float = max(-velocity.y, 0.0)
    if current_fall_speed > 0.0:
        _last_fall_speed = max(_last_fall_speed, current_fall_speed)
    var current_velocity := self.velocity
    var direction := Input.get_axis("move_left", "move_right")

    _update_bullet_time_state()

    var wants_crouch := Input.is_action_pressed("crouch") and is_on_floor() and not _on_vine
    if _is_crouching and not is_on_floor():
        wants_crouch = false
    if wants_crouch != _is_crouching:
        if wants_crouch:
            _enter_crouch()
        else:
            _exit_crouch()
        _is_crouching = wants_crouch

    var on_slope := _update_slope_slide_state(delta)
    if _is_crouching:
        direction = 0.0

    if Input.is_action_just_pressed("cat_meow"):
        _play_meow()
    if Input.is_action_just_pressed("cat_purr"):
        _play_purr()
    if Input.is_action_just_pressed("level_restart"):
        _restart_level_if_possible()

    _update_facing_direction(direction, current_velocity.x)
    _update_animation_state(direction, current_velocity.x)

    if _bouncy_cooldown > 0.0:
        _bouncy_cooldown = max(_bouncy_cooldown - delta, 0.0)

    _update_slippery_state()
    _update_conveyor_state()
    _update_vine_state()
    _scan_for_bouncy_surfaces(current_velocity)

    if is_on_floor() and not _on_bouncy_surface:
        _last_fall_speed = 0.0
        _bounce_bonus_available = true
        _bounce_chain_multiplier = 1.0

    if _pending_bounce_strength > 0.0:
        current_velocity.y = -abs(_pending_bounce_strength)
        _pending_bounce_strength = 0.0

    if _on_slippery_paint and is_on_floor() and direction != 0.0:
        _slippery_speed_bonus = min(_slippery_speed_bonus + SLIPPERY_ACCEL_GAIN * delta, (MAX_SPEED * SLIPPERY_SPEED_MULT) - MAX_SPEED)
        _slippery_decay_timer = SLIPPERY_DECAY_DELAY
    else:
        _slippery_decay_timer = max(_slippery_decay_timer - delta, 0.0)
        if _slippery_decay_timer <= 0.0:
            _slippery_speed_bonus = max(_slippery_speed_bonus - SLIPPERY_DECAY_RATE * delta, 0.0)

    var max_speed := MAX_SPEED + _slippery_speed_bonus
    var target_speed := direction * max_speed
    var conveyor_active := _on_conveyor and is_on_floor() and not _on_vine
    var conveyor_target := 0.0
    if conveyor_active and _conveyor_contacts > 0:
        var direction_factor: float = clamp(_conveyor_direction_sum / float(max(_conveyor_contacts, 1)), -1.0, 1.0)
        conveyor_target = direction_factor * conveyor_push_speed
    if not is_on_floor() and abs(current_velocity.x) > abs(target_speed):
        target_speed = current_velocity.x
    if on_slope and _is_crouching:
        var slide_velocity: Vector2 = _slope_slide_direction * _slope_slide_speed
        current_velocity = slide_velocity
        _slope_slide_retained_velocity = slide_velocity
    elif direction != 0.0:
        var accel := ACCELERATION if is_on_floor() else AIR_ACCELERATION
        if _on_vine:
            accel = climb_accel
        elif is_on_floor() and _on_slippery_paint:
            accel *= SLIPPERY_ACCEL_MULT
        current_velocity.x = move_toward(current_velocity.x, target_speed, accel * delta)
    elif conveyor_active:
        current_velocity.x = move_toward(current_velocity.x, conveyor_target, conveyor_accel * delta)
    else:
        var applying_ground_friction := not (on_slope and _is_crouching)
        var base_friction := FRICTION if (is_on_floor() or _on_vine) else AIR_FRICTION
        if _on_vine:
            base_friction = climb_accel
        elif is_on_floor() and _on_slippery_paint:
            base_friction = SLIPPERY_FRICTION
        var retaining_slope_speed := not is_on_floor() and _slope_slide_retained_velocity != Vector2.ZERO
        if applying_ground_friction and not retaining_slope_speed:
            var decel := base_friction * delta
            if abs(current_velocity.x) <= decel:
                current_velocity.x = 0.0
            else:
                current_velocity.x -= sign(current_velocity.x) * decel

    if _is_crouching and not on_slope:
        var crouch_decel := FRICTION * 2.0 * delta
        if abs(current_velocity.x) <= crouch_decel:
            current_velocity.x = 0.0
        else:
            current_velocity.x -= sign(current_velocity.x) * crouch_decel

    if _foot_area and Engine.get_frames_drawn() % 15 == 0:
        pass

    var climb_input := Input.get_axis("climb_up", "climb_down")

    if _on_vine:
        if Input.is_action_just_pressed("jump"):
            _on_vine = false
            current_velocity.y = JUMP_SPEED
        else:
            var target_climb := climb_input * climb_speed
            current_velocity.y = move_toward(current_velocity.y, target_climb, climb_accel * delta)
    elif Input.is_action_just_pressed("jump") and is_on_floor():
        current_velocity.y = JUMP_SPEED
        if _is_crouching:
            _exit_crouch()
            _is_crouching = false
        _play_jump_squash()
    else:
        current_velocity.y += gravity * delta

    if on_slope and _is_crouching:
        var clamped_speed: float = clamp(_slope_slide_speed, 0.0, _slope_slide_max_limit)
        var slide_velocity: Vector2 = _slope_slide_direction * clamped_speed
        current_velocity = slide_velocity
        _slope_slide_retained_velocity = slide_velocity
    else:
        var horizontal_cap := max_speed
        if on_slope:
            horizontal_cap = max(horizontal_cap, _slope_slide_max_limit)
        if _slope_slide_retained_velocity != Vector2.ZERO and not is_on_floor():
            if sign(current_velocity.x) == 0 or sign(current_velocity.x) == sign(_slope_slide_retained_velocity.x):
                var retained_x := _slope_slide_retained_velocity.x
                if abs(current_velocity.x) < abs(retained_x):
                    current_velocity.x = retained_x
                horizontal_cap = max(horizontal_cap, abs(retained_x))
            else:
                _slope_slide_retained_velocity = Vector2.ZERO
        current_velocity.x = clamp(current_velocity.x, -horizontal_cap, horizontal_cap)
    self.velocity = current_velocity
    move_and_slide()
    _apply_push_to_bodies()
    _update_camera_offset(delta)

    if is_on_floor() and (not on_slope or not _is_crouching):
        _slope_slide_retained_velocity = Vector2.ZERO

func _update_slope_slide_state(delta: float) -> bool:
    if not is_on_floor():
        _slope_slide_speed = 0.0
        _slope_slide_direction = Vector2.ZERO
        return false
    var floor_normal: Vector2 = get_floor_normal()
    if floor_normal == Vector2.ZERO:
        _slope_slide_speed = 0.0
        _slope_slide_direction = Vector2.ZERO
        return false
    floor_normal = floor_normal.normalized()
    var alignment: float = abs(floor_normal.dot(Vector2.UP))
    if alignment >= SLOPE_DETECTION_NORMAL_Y and abs(floor_normal.x) < SLOPE_MIN_NORMAL_X:
        _slope_slide_speed = 0.0
        _slope_slide_direction = Vector2.ZERO
        return false
    var tangent := Vector2(-floor_normal.y, floor_normal.x)
    var tangent_length := tangent.length()
    if tangent_length < 0.0001:
        _slope_slide_speed = 0.0
        _slope_slide_direction = Vector2.ZERO
        return false
    tangent /= tangent_length
    if tangent.dot(Vector2.DOWN) <= 0.0:
        tangent = -tangent
    _slope_slide_direction = tangent
    var steepness: float = clamp(abs(floor_normal.x), 0.0, 1.0)
    var accel_multiplier: float = lerp(1.0, SLOPE_STEEP_ACCEL_MULT, steepness)
    var max_multiplier: float = lerp(1.0, SLOPE_STEEP_MAX_MULT, steepness)
    _slope_slide_max_limit = SLOPE_SLIDE_MAX_SPEED * max_multiplier
    if not _is_crouching:
        _slope_slide_speed = 0.0
        return false
    var velocity_along_slope := self.velocity.dot(_slope_slide_direction)
    var gravity_along_slope: float = max(0.0, gravity * delta * _slope_slide_direction.dot(Vector2.DOWN))
    var base_speed: float = max(_slope_slide_speed, abs(velocity_along_slope))
    _slope_slide_speed = clamp(base_speed + gravity_along_slope + SLOPE_SLIDE_ACCEL * accel_multiplier * delta, 0.0, _slope_slide_max_limit)
    return true

func _apply_push_to_bodies() -> void:
    if abs(velocity.x) <= 0.01:
        return
    var push_direction := Vector2(sign(velocity.x), 0.0)
    var impulse_strength := PUSH_FORCE * push_direction.x
    if impulse_strength == 0.0:
        return
    for i in range(get_slide_collision_count()):
        var collision := get_slide_collision(i)
        if collision == null:
            continue
        var collider := collision.get_collider()
        if collider == null:
            continue
        if collider is RigidBody2D:
            var rigid := collider as RigidBody2D
            var normal := collision.get_normal()
            if abs(normal.x) < 0.7:
                continue
            var contact_point := collision.get_position()
            rigid.apply_impulse(push_direction * abs(impulse_strength) * 0.1, contact_point - rigid.global_position)

func _update_facing_direction(move_input: float, current_velocity_x: float) -> void:
    var desired_direction := _facing_direction
    if move_input != 0.0:
        desired_direction = int(sign(move_input))
    elif current_velocity_x != 0.0:
        desired_direction = int(sign(current_velocity_x))

    if desired_direction == 0:
        desired_direction = _facing_direction

    if desired_direction != _facing_direction:
        _facing_direction = desired_direction
        if _body_sprite:
            _body_sprite.flip_h = _facing_direction < 0
        if _body_anim:
            _body_anim.flip_h = _facing_direction < 0

func _update_animation_state(move_input: float, current_velocity_x: float) -> void:
    if _body_anim == null:
        return
    if _is_crouching:
        if _body_anim.animation != "idle":
            _body_anim.play("idle")
        return
    var moving: bool = absf(move_input) > 0.01 or absf(current_velocity_x) > 10.0
    var target := "run" if moving else "idle"
    if _body_anim.animation != target:
        _body_anim.play(target)

func _play_jump_squash() -> void:
    if _body_anim == null:
        return
    if _is_crouching:
        return
    if _scale_tween and _scale_tween.is_running():
        _scale_tween.kill()
    _scale_tween = create_tween()
    var stretch_scale := Vector2(_body_base_scale.x * 0.8, _body_base_scale.y * 1.2)
    _scale_tween.tween_method(Callable(self, "_set_body_scale"), _body_base_scale, stretch_scale, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _scale_tween.tween_method(Callable(self, "_set_body_scale"), stretch_scale, _body_base_scale, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _set_body_scale(value: Vector2) -> void:
    if _body_anim == null:
        return
    _body_anim.scale = value
    var half_height := (_body_texture_size.y * 0.5)
    var new_y := _body_base_bottom - (_body_base_offset.y + half_height) * value.y
    _body_anim.position = Vector2(_body_base_position.x, new_y)

func _enter_crouch() -> void:
    if _body_anim == null:
        return
    if _scale_tween and _scale_tween.is_running():
        _scale_tween.kill()
    _scale_tween = create_tween()
    _scale_tween.tween_method(Callable(self, "_set_body_scale"), _body_anim.scale, _crouch_scale, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    _body_anim.play("idle")
    _apply_collider_crouch_scale(_crouch_scale.y / _body_base_scale.y)

func _exit_crouch() -> void:
    if _body_anim == null:
        return
    if _scale_tween and _scale_tween.is_running():
        _scale_tween.kill()
    _scale_tween = create_tween()
    _scale_tween.tween_method(Callable(self, "_set_body_scale"), _body_anim.scale, _body_base_scale, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    _apply_collider_crouch_scale(1.0)

func _apply_collider_crouch_scale(scale_factor: float) -> void:
    if _collision_rect == null or _collision_shape == null:
        return
    scale_factor = clamp(scale_factor, 0.1, 1.5)
    var new_height := _collision_base_size.y * scale_factor
    _collision_rect.size = Vector2(_collision_base_size.x, new_height)
    var new_pos_y := _collision_base_bottom - (new_height * 0.5)
    _collision_shape.position = Vector2(_collision_base_position.x, new_pos_y)

func _play_meow() -> void:
    if _meow_sfx == null or _meow_sfx.stream == null:
        return
    _apply_random_pitch(_meow_sfx)
    if _meow_sfx.playing:
        _meow_sfx.stop()
    _meow_sfx.play()

func _play_purr() -> void:
    if _purr_sfx == null:
        return
    if _purr_streams.is_empty():
        _load_purr_streams()
    if _purr_streams.is_empty():
        return
    var stream_index := _rng.randi_range(0, _purr_streams.size() - 1)
    var stream := _purr_streams[stream_index]
    if stream == null:
        return
    _purr_sfx.stream = stream
    _apply_random_pitch(_purr_sfx)
    if _purr_sfx.playing:
        _purr_sfx.stop()
    _purr_sfx.play()

func _apply_random_pitch(player: AudioStreamPlayer) -> void:
    if player == null:
        return
    if CAT_PITCH_VARIATIONS.is_empty():
        player.pitch_scale = 1.0
        return
    var index := _rng.randi_range(0, CAT_PITCH_VARIATIONS.size() - 1)
    var variation := CAT_PITCH_VARIATIONS[index]
    player.pitch_scale = 1.0 + variation

func _load_purr_streams() -> void:
    _purr_streams.clear()
    for path in CAT_PURR_PATHS:
        var stream: AudioStream = load(path)
        if stream:
            _purr_streams.append(stream)

func _restart_level_if_possible() -> void:
    var tree := get_tree()
    if tree == null:
        return
    var current_scene := tree.current_scene
    if current_scene == null:
        return
    var scene_path := current_scene.scene_file_path
    var reload_path := ""
    if not scene_path.is_empty() and scene_path.find("/scenes/levels/") != -1:
        reload_path = scene_path
    else:
        var level_path := _find_level_scene_path(current_scene)
        if not level_path.is_empty():
            reload_path = scene_path if not scene_path.is_empty() else level_path
    if reload_path.is_empty():
        return
    tree.change_scene_to_file(reload_path)

func _find_level_scene_path(node: Node) -> String:
    if node == null:
        return ""
    var path := node.scene_file_path
    if not path.is_empty() and path.find("/scenes/levels/") != -1:
        return path
    for child in node.get_children():
        if child is Node:
            var result := _find_level_scene_path(child)
            if not result.is_empty():
                return result
    return ""

func _ensure_input_actions() -> void:
    _ensure_action("move_left", [KEY_A, KEY_LEFT])
    _ensure_action("move_right", [KEY_D, KEY_RIGHT])
    _ensure_action("jump", [KEY_SPACE, KEY_W, KEY_UP])
    _ensure_action("climb_up", [KEY_W, KEY_UP])
    _ensure_action("climb_down", [KEY_S, KEY_DOWN])
    _ensure_action("crouch", [KEY_S, KEY_DOWN])
    _ensure_action("cat_meow", [KEY_M])
    _ensure_action("cat_purr", [KEY_P])
    _ensure_action("level_restart", [KEY_R])
    _ensure_action("bullet_time", [KEY_B])

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

func _on_foot_body_entered(body: Node) -> void:
    if body.is_in_group("slippery_paint"):
        _slippery_contacts += 1
        _on_slippery_paint = _slippery_contacts > 0
    elif body.is_in_group("bouncy_paint"):
        _handle_bouncy_contact(body)

func _on_foot_body_exited(body: Node) -> void:
    if body.is_in_group("slippery_paint"):
        _slippery_contacts = max(_slippery_contacts - 1, 0)
        _on_slippery_paint = _slippery_contacts > 0

func _on_foot_area_entered(area: Area2D) -> void:
    if area.is_in_group("slippery_paint"):
        _slippery_contacts += 1
        _on_slippery_paint = true
    elif area.is_in_group("bouncy_paint"):
        _handle_bouncy_contact(area)

func _on_foot_area_exited(area: Area2D) -> void:
    if area.is_in_group("slippery_paint"):
        _slippery_contacts = max(_slippery_contacts - 1, 0)
        _on_slippery_paint = _slippery_contacts > 0

func _update_slippery_state() -> void:
    if not is_on_floor():
        return
    var world := get_world_2d()
    if world == null:
        return
    var space := world.direct_space_state
    if space == null:
        return
    var params := PhysicsPointQueryParameters2D.new()
    params.collision_mask = 16
    params.collide_with_areas = true
    params.collide_with_bodies = false

    var slippery_detected := false
    for offset in FOOT_SAMPLE_OFFSETS:
        params.position = global_position + offset
        var results := space.intersect_point(params, 1)
        if results.size() > 0:
            slippery_detected = true
            break
    if slippery_detected:
        _on_slippery_paint = true
    else:
        _on_slippery_paint = false

func _scan_for_bouncy_surfaces(current_velocity: Vector2) -> void:
    if _bouncy_cooldown > 0.0:
        return
    if current_velocity.y < -20.0:
        return
    var world := get_world_2d()
    if world == null:
        return
    var space := world.direct_space_state
    if space == null:
        return
    var params := PhysicsPointQueryParameters2D.new()
    params.collision_mask = BOUNCY_LAYER_MASK
    params.collide_with_areas = true
    params.collide_with_bodies = false

    _on_bouncy_surface = false
    for offset in FOOT_SAMPLE_OFFSETS:
        params.position = global_position + offset
        var results: Array = space.intersect_point(params, 1)
        if results.size() == 0:
            continue
        var entry: Dictionary = results[0]
        if entry.has("collider"):
            var collider: Object = entry.get("collider")
            if collider:
                _on_bouncy_surface = true
                _handle_bouncy_contact(collider)
        break

func _queue_bounce(strength: float) -> void:
    var adjusted_strength: float = clamp(strength * _bounce_chain_multiplier, bounce_min_speed, bounce_max_speed)
    _pending_bounce_strength = max(_pending_bounce_strength, adjusted_strength)
    _slippery_decay_timer = SLIPPERY_DECAY_DELAY
    _bouncy_cooldown = 0.1
    _last_fall_speed = 0.0
    _bounce_chain_multiplier = max(_bounce_chain_multiplier * BOUNCE_CHAIN_DECAY, BOUNCE_CHAIN_MIN_MULT)

func _handle_bouncy_contact(target: Object) -> void:
    if _bouncy_cooldown > 0.0:
        return
    var strength: float = BOUNCY_DEFAULT_STRENGTH
    if target.has_meta("bounce_strength"):
        strength = float(target.get_meta("bounce_strength"))

    var downward_speed: float = max(_last_fall_speed, max(-velocity.y, 0.0))
    if downward_speed <= 0.0:
        return

    var capped_fall_speed: float = min(downward_speed, bounce_max_speed)
    var base_speed: float = max(capped_fall_speed, bounce_min_speed)

    var base_multiplier: float = max(1.0, bounce_base_multiplier)
    var multiplier: float = base_multiplier
    if _bounce_bonus_available:
        var bonus_multiplier: float = clamp(bounce_bonus_multiplier, base_multiplier, 1.2)
        multiplier = bonus_multiplier
        _bounce_bonus_available = false

    var target_speed: float = base_speed * multiplier
    var max_bonus_speed: float = capped_fall_speed * 1.2
    var metadata_speed: float = clamp(strength, 0.0, max_bonus_speed)
    target_speed = max(target_speed, metadata_speed)
    target_speed = clamp(target_speed, base_speed, max_bonus_speed)

    _queue_bounce(target_speed)

func _update_conveyor_state() -> void:
    if not is_on_floor():
        if _on_conveyor:
            _conveyor_contacts = 0
            _conveyor_direction_sum = 0.0
            _on_conveyor = false
        return

    var world := get_world_2d()
    if world == null:
        _conveyor_contacts = 0
        _conveyor_direction_sum = 0.0
        _on_conveyor = false
        return
    var space := world.direct_space_state
    if space == null:
        _conveyor_contacts = 0
        _conveyor_direction_sum = 0.0
        _on_conveyor = false
        return

    var params := PhysicsPointQueryParameters2D.new()
    params.collision_mask = CONVEYOR_LAYER_MASK
    params.collide_with_areas = true
    params.collide_with_bodies = false

    var contacts := 0
    var direction_sum := 0.0

    for offset in FOOT_SAMPLE_OFFSETS:
        params.position = global_position + offset
        var results: Array = space.intersect_point(params, 4)
        for entry in results:
            var collider: Object = entry.get("collider")
            if collider == null:
                continue
            if collider.has_meta("conveyor_direction"):
                direction_sum += float(collider.get_meta("conveyor_direction"))
                contacts += 1

    _conveyor_contacts = contacts
    _conveyor_direction_sum = direction_sum
    _on_conveyor = contacts > 0
    if not _on_conveyor:
        _conveyor_direction_sum = 0.0

func _update_vine_state() -> void:
    var world := get_world_2d()
    if world == null:
        _vine_contacts = 0
        _on_vine = false
        return
    var space := world.direct_space_state
    if space == null:
        _vine_contacts = 0
        _on_vine = false
        return

    var params := PhysicsShapeQueryParameters2D.new()
    params.shape = _vine_query_shape
    params.transform = Transform2D(0.0, global_position + CLIMB_DETECTION_OFFSET)
    params.collision_mask = VINE_LAYER_MASK
    params.collide_with_areas = true
    params.collide_with_bodies = false

    var results := space.intersect_shape(params, 8)
    _vine_contacts = results.size()
    _on_vine = _vine_contacts > 0

func _update_camera_offset(delta: float) -> void:
    if _camera == null:
        return
    var viewport := get_viewport()
    if viewport == null:
        return
    var viewport_size: Vector2 = viewport.get_visible_rect().size
    if viewport_size == Vector2.ZERO:
        return

    var mouse_view: Vector2 = viewport.get_mouse_position()
    var center: Vector2 = viewport_size * 0.5
    var desired_offset: Vector2 = Vector2.ZERO

    var padding_x: float = clamp(camera_edge_padding.x, 0.0, center.x - 1.0)
    var padding_y: float = clamp(camera_edge_padding.y, 0.0, center.y - 1.0)
    var dx: float = mouse_view.x - center.x
    var dy: float = mouse_view.y - center.y

    if abs(dx) > padding_x:
        var excess_x: float = abs(dx) - padding_x
        var range_x: float = max(center.x - padding_x, 1.0)
        var factor_x: float = clamp(excess_x / range_x, 0.0, 1.0)
        desired_offset.x = sign(dx) * camera_mouse_max_distance * factor_x

    if abs(dy) > padding_y:
        var excess_y: float = abs(dy) - padding_y
        var range_y: float = max(center.y - padding_y, 1.0)
        var factor_y: float = clamp(excess_y / range_y, 0.0, 1.0)
        desired_offset.y = sign(dy) * camera_mouse_max_distance * factor_y

    var t: float = clamp(delta * camera_mouse_follow_speed, 0.0, 1.0)
    _camera.offset = _camera.offset.lerp(desired_offset, t)

func _update_bullet_time_state() -> void:
    var wants_bullet_time := Input.is_action_pressed("bullet_time")
    if wants_bullet_time and not _bullet_time_active:
        _bullet_time_prev_scale = Engine.time_scale
        Engine.time_scale = clamp(BULLET_TIME_SCALE, 0.01, _bullet_time_prev_scale)
        _bullet_time_active = true
    elif not wants_bullet_time and _bullet_time_active:
        Engine.time_scale = _bullet_time_prev_scale
        _bullet_time_active = false
