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
@export var conveyor_push_speed := 220.0
@export var conveyor_accel := 900.0
@export var climb_speed := 210.0
@export var climb_accel := 900.0
@export var camera_mouse_max_distance := 240.0
@export var camera_mouse_follow_speed := 8.0
@export var camera_edge_padding := Vector2(220.0, 160.0)
@export var bounce_min_speed := 140.0
@export var bounce_max_multiplier := 1.3
@export var bounce_min_multiplier := 0.35
const CLIMB_DETECTION_RADIUS := 22.0
const CLIMB_DETECTION_OFFSET := Vector2(0, -8)

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
var _conveyor_contacts := 0
var _conveyor_direction_sum := 0.0
var _on_conveyor := false
var _vine_contacts := 0
var _on_vine := false
var _vine_query_shape := CircleShape2D.new()
var _camera: Camera2D

func _ready() -> void:
    _ensure_input_actions()
    gravity = float(ProjectSettings.get_setting("physics/2d/default_gravity"))
    z_index = 50
    _vine_query_shape.radius = CLIMB_DETECTION_RADIUS
    _camera = get_node_or_null("Camera2D")
    if _camera:
        _camera.make_current()
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

func _physics_process(delta: float) -> void:
    var current_velocity := self.velocity
    var direction := Input.get_axis("move_left", "move_right")

    if _bouncy_cooldown > 0.0:
        _bouncy_cooldown = max(_bouncy_cooldown - delta, 0.0)

    _update_slippery_state()
    _update_conveyor_state()
    _update_vine_state()
    _scan_for_bouncy_surfaces(current_velocity)

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
    if direction != 0.0:
        var accel := ACCELERATION if is_on_floor() else AIR_ACCELERATION
        if _on_vine:
            accel = climb_accel
        elif is_on_floor() and _on_slippery_paint:
            accel *= SLIPPERY_ACCEL_MULT
        current_velocity.x = move_toward(current_velocity.x, target_speed, accel * delta)
    elif conveyor_active:
        current_velocity.x = move_toward(current_velocity.x, conveyor_target, conveyor_accel * delta)
    else:
        var base_friction := FRICTION if (is_on_floor() or _on_vine) else AIR_FRICTION
        if _on_vine:
            base_friction = climb_accel
        elif is_on_floor() and _on_slippery_paint:
            base_friction = SLIPPERY_FRICTION
        var decel := base_friction * delta
        if abs(current_velocity.x) <= decel:
            current_velocity.x = 0.0
        else:
            current_velocity.x -= sign(current_velocity.x) * decel

    if _foot_area and Engine.get_frames_drawn() % 15 == 0:
        pass

    var climb_input := Input.get_axis("climb_up", "climb_down")
    if _on_vine:
        if Input.is_action_just_pressed("jump"):
            _on_vine = false
            current_velocity.y = JUMP_SPEED
            print("[Player] Jumped off vine")
        else:
            var target_climb := climb_input * climb_speed
            current_velocity.y = move_toward(current_velocity.y, target_climb, climb_accel * delta)
            print("[Player] Climbing vine climb_input=", climb_input, " velocity=", current_velocity)
    elif Input.is_action_just_pressed("jump") and is_on_floor():
        current_velocity.y = JUMP_SPEED
    else:
        current_velocity.y += gravity * delta

    current_velocity.x = clamp(current_velocity.x, -max_speed, max_speed)
    self.velocity = current_velocity
    move_and_slide()
    _update_camera_offset(delta)

func _ensure_input_actions() -> void:
    _ensure_action("move_left", [KEY_A, KEY_LEFT])
    _ensure_action("move_right", [KEY_D, KEY_RIGHT])
    _ensure_action("jump", [KEY_SPACE, KEY_W, KEY_UP])
    _ensure_action("climb_up", [KEY_W, KEY_UP])
    _ensure_action("climb_down", [KEY_S, KEY_DOWN])

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
    var space := get_world_2d().direct_space_state
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
    var space := get_world_2d().direct_space_state
    var params := PhysicsPointQueryParameters2D.new()
    params.collision_mask = BOUNCY_LAYER_MASK
    params.collide_with_areas = true
    params.collide_with_bodies = false

    for offset in FOOT_SAMPLE_OFFSETS:
        params.position = global_position + offset
        var results := space.intersect_point(params, 1)
        if results.size() == 0:
            continue
        var entry := results[0]
        if entry.has("collider"):
            var collider: Object = entry.get("collider")
            if collider:
                _handle_bouncy_contact(collider)
        break

func _queue_bounce(strength: float) -> void:
    _pending_bounce_strength = max(_pending_bounce_strength, strength)
    _slippery_decay_timer = SLIPPERY_DECAY_DELAY
    _bouncy_cooldown = 0.1

func _handle_bouncy_contact(target: Object) -> void:
    if _bouncy_cooldown > 0.0:
        return
    var strength: float = BOUNCY_DEFAULT_STRENGTH
    if target.has_meta("bounce_strength"):
        strength = float(target.get_meta("bounce_strength"))

    var downward_speed: float = max(-velocity.y, 0.0)
    if downward_speed < bounce_min_speed:
        return

    var normalized: float = clamp((downward_speed - bounce_min_speed) / max(bounce_min_speed, 1.0), 0.0, 1.0)
    var multiplier: float = lerp(bounce_min_multiplier, bounce_max_multiplier, normalized)
    var final_strength: float = strength * multiplier
    _queue_bounce(final_strength)

func _update_conveyor_state() -> void:
    if not is_on_floor():
        if _on_conveyor:
            _conveyor_contacts = 0
            _conveyor_direction_sum = 0.0
            _on_conveyor = false
        return

    var space := get_world_2d().direct_space_state
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
    var space := get_world_2d().direct_space_state
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
    var previous_on_vine := _on_vine
    _vine_contacts = results.size()
    _on_vine = _vine_contacts > 0
    if _on_vine and not previous_on_vine:
        print("[Player] Vine contact detected at ", global_position, " offset=", CLIMB_DETECTION_OFFSET, " radius=", CLIMB_DETECTION_RADIUS, " contacts=", _vine_contacts)
        for result in results:
            if result.has("collider") and result.collider:
                print("[Player] Vine collider=", result.collider.name)
    elif not _on_vine and previous_on_vine:
        print("[Player] Vine contact lost")

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
