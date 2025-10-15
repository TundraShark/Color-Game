@tool
extends Node2D

const DEFAULT_SEGMENT_COUNT := 8
const MAX_SEGMENT_COUNT := 32
const SEGMENT_HEIGHT := 25.0
const SEGMENT_WIDTH := 8.0
const SWAY_AMPLITUDE := 12.0
const SWAY_DURATION := 1.6
const SWAY_PERIOD := 0.9
const SEGMENT_PHASE_SHIFT := 0.4
const SWAY_ENERGY_BOOST := 0.6
const ROPE_LAYER_MASK := 256
const PLAYER_SCRIPT := preload("res://scripts/player.gd")

var segments: Array[Area2D] = []
var _base_positions: Array[Vector2] = []
var _sway_active := false
var _sway_direction := 1.0
var _sway_phase_time := 0.0
var _sway_energy := 0.0
var _segment_count := DEFAULT_SEGMENT_COUNT
var _pending_segment_update := false

@export_range(1, MAX_SEGMENT_COUNT, 1) var segment_count := DEFAULT_SEGMENT_COUNT:
    get:
        return _segment_count
    set(value):
        var clamped := clampi(int(value), 1, MAX_SEGMENT_COUNT)
        if clamped == _segment_count:
            return
        _segment_count = clamped
        _schedule_segment_update()

func _ready() -> void:
    _pending_segment_update = false
    _update_segment_structure()

func _setup_segments() -> void:
    segments.clear()
    _base_positions.clear()
    for i in range(_segment_count):
        var segment_name := "Segment" + str(i + 1)
        var segment := get_node_or_null(segment_name)
        if segment:
            segments.append(segment)
            _base_positions.append(segment.position)
            _configure_segment(segment, i)

func _configure_segment(segment: Area2D, _index: int) -> void:
    segment.monitoring = true
    segment.monitorable = false
    if segment.collision_layer == 0:
        segment.collision_layer = ROPE_LAYER_MASK
    segment.collision_mask = segment.collision_mask | 2

    var collision_shape := segment.get_node_or_null("CollisionShape2D")
    if collision_shape and collision_shape.shape == null:
        var shape := RectangleShape2D.new()
        shape.size = Vector2(8, SEGMENT_HEIGHT)
        collision_shape.shape = shape
    if not segment.body_entered.is_connected(_on_segment_body_entered):
        segment.body_entered.connect(_on_segment_body_entered)
    if not segment.area_entered.is_connected(_on_segment_area_entered):
        segment.area_entered.connect(_on_segment_area_entered)

func _physics_process(delta: float) -> void:
    if _sway_active or _sway_energy > 0.0:
        _sway_phase_time += delta
        if _sway_energy > 0.0:
            _sway_energy = max(_sway_energy - (delta / SWAY_DURATION), 0.0)
        _apply_sway()
        if _sway_energy <= 0.0:
            _sway_active = false
    elif segments.size() == _base_positions.size():
        _reset_segments_to_base()

func get_segment_bounds(segment_index: int) -> Array:
    """Get the bounding box for a specific segment"""
    if segment_index < 0 or segment_index >= segments.size():
        return [Vector2.ZERO, Vector2.ZERO]

    var segment := segments[segment_index] as Area2D
    if not segment:
        return [Vector2.ZERO, Vector2.ZERO]

    var pos := segment.global_position
    var size := Vector2(8, SEGMENT_HEIGHT)

    return [pos - size * 0.5, pos + size * 0.5]

func get_all_segments_bounds() -> Array:
    """Get bounding boxes for all segments"""
    var bounds := []
    for i in range(segments.size()):
        bounds.append(get_segment_bounds(i))
    return bounds

func _on_segment_body_entered(body: Node) -> void:
    if body == null:
        return
    if body.is_in_group("paint_projectile"):
        _handle_paint_projectile_hit(body as Node2D)
        return
    var is_player := body.is_in_group("player")
    if not is_player and body.get_script() == PLAYER_SCRIPT:
        is_player = true
    if not is_player and body.name == "Player":
        is_player = true
    if not is_player:
        return
    var direction := _sway_direction
    var should_boost := false
    var body_node := body as Node2D
    if body is CharacterBody2D:
        var velocity_x := (body as CharacterBody2D).velocity.x
        if abs(velocity_x) > 1.0:
            direction = sign(velocity_x)
            should_boost = true
    if not should_boost and body_node:
        var horizontal_delta: float = body_node.global_position.x - global_position.x
        if abs(horizontal_delta) > 1.0:
            direction = sign(horizontal_delta)
            should_boost = true
    if direction == 0.0:
        direction = 1.0
    if should_boost:
        _start_sway(direction)

func _on_segment_area_entered(area: Area2D) -> void:
    if area == null:
        return
    if area.is_in_group("paint_projectile"):
        _handle_paint_projectile_hit(area)

func _start_sway(direction: float) -> void:
    _sway_active = true
    _sway_energy = clamp(_sway_energy + SWAY_ENERGY_BOOST, 0.0, 1.0)
    _sway_direction = clamp(direction, -1.0, 1.0)
    if _sway_direction == 0.0:
        _sway_direction = 1.0

func _apply_sway() -> void:
    if segments.size() != _base_positions.size():
        return
    var amplitude: float = SWAY_AMPLITUDE * _sway_energy
    var wave_speed: float = TAU / SWAY_PERIOD
    for i in range(segments.size()):
        var segment: Area2D = segments[i]
        var base_pos: Vector2 = _base_positions[i]
        var falloff: float = 1.0
        if segments.size() > 1:
            falloff = float(i) / float(segments.size() - 1)
        var phase := wave_speed * _sway_phase_time + float(i) * SEGMENT_PHASE_SHIFT
        var offset: float = sin(phase) * amplitude * falloff * _sway_direction
        segment.position = base_pos + Vector2(offset, 0.0)

func _reset_segments_to_base() -> void:
    if segments.size() != _base_positions.size():
        return
    for i in range(segments.size()):
        segments[i].position = _base_positions[i]

func _schedule_segment_update() -> void:
    if is_inside_tree():
        call_deferred("_update_segment_structure")
    else:
        _pending_segment_update = true

func _update_segment_structure() -> void:
    if _pending_segment_update and not is_inside_tree():
        return
    _pending_segment_update = false
    _ensure_segment_nodes()
    _setup_segments()

func _ensure_segment_nodes() -> void:
    var template := get_node_or_null("Segment1") as Area2D
    if template == null:
        template = _create_segment("Segment1")
        add_child(template)
        if Engine.is_editor_hint():
            _assign_owner_recursive(template, self)
    var template_owner := template.owner if template else null
    var template_sprite := template.get_node_or_null("Sprite2D") as Sprite2D if template else null
    var template_collision := template.get_node_or_null("CollisionShape2D") as CollisionShape2D if template else null
    for i in range(_segment_count):
        var segment_name := "Segment" + str(i + 1)
        var segment := get_node_or_null(segment_name) as Area2D
        if segment == null:
            segment = _create_segment(segment_name, template_sprite, template_collision)
            add_child(segment)
            if Engine.is_editor_hint():
                _assign_owner_recursive(segment, template_owner)
        segment.position = Vector2(0.0, SEGMENT_HEIGHT * float(i + 1))
    var index := _segment_count + 1
    while true:
        var extra_name := "Segment" + str(index)
        var extra_segment := get_node_or_null(extra_name)
        if extra_segment == null:
            break
        extra_segment.queue_free()
        index += 1

func _create_segment(segment_name: String, template_sprite: Sprite2D = null, template_collision: CollisionShape2D = null) -> Area2D:
    var segment := Area2D.new()
    segment.name = segment_name
    segment.collision_layer = 256
    segment.monitoring = true
    segment.monitorable = false

    var sprite := Sprite2D.new()
    if template_sprite:
        sprite.texture = template_sprite.texture
        sprite.self_modulate = template_sprite.self_modulate
        sprite.scale = template_sprite.scale
        sprite.offset = template_sprite.offset
        sprite.position = template_sprite.position
        sprite.rotation = template_sprite.rotation
    else:
        sprite.texture = preload("res://assets/game/paint-orange.png")
        sprite.self_modulate = Color(0.55, 0.27, 0.07, 1.0)
        sprite.scale = Vector2(0.4, 6.75999)
        sprite.position = Vector2.ZERO
    segment.add_child(sprite)
    var collision_shape := CollisionShape2D.new()
    if template_collision and template_collision.shape:
        collision_shape.shape = template_collision.shape.duplicate()
        collision_shape.position = template_collision.position
        collision_shape.rotation = template_collision.rotation
        collision_shape.scale = template_collision.scale
    else:
        var shape := RectangleShape2D.new()
        shape.size = Vector2(8.0, SEGMENT_HEIGHT)
        collision_shape.shape = shape
    segment.add_child(collision_shape)

    return segment

func _assign_owner_recursive(node: Node, target_owner: Node) -> void:
    if target_owner == null:
        return
    if target_owner != node and not target_owner.is_ancestor_of(node):
        return
    node.owner = target_owner
    for child in node.get_children():
        if child is Node:
            _assign_owner_recursive(child, target_owner)

func _handle_paint_projectile_hit(projectile: Node2D) -> void:
    var hit_position: Vector2 = global_position
    if projectile:
        hit_position = projectile.global_position
    var direction: float = sign(hit_position.x - global_position.x)
    if direction == 0.0:
        direction = 1.0 if _sway_direction >= 0.0 else -1.0
    _start_sway(direction)
    if projectile:
        _handle_rope_damage_from_paint(projectile, hit_position, direction)
        projectile.call_deferred("queue_free")

func _handle_rope_damage_from_paint(projectile: Node, hit_position: Vector2, impulse_direction: float) -> void:
    if projectile == null:
        return
    var color_name := ""
    if "paint_color_name" in projectile:
        color_name = str(projectile.paint_color_name)
    elif projectile.has_method("get_paint_color_name"):
        color_name = str(projectile.get_paint_color_name())
    if color_name != "Red":
        return
    _sever_rope_at_position(hit_position, impulse_direction)

func _sever_rope_at_position(hit_position: Vector2, impulse_direction: float) -> void:
    if segments.is_empty():
        return
    var local_hit_y := to_local(hit_position).y
    var sever_index := -1
    for i in range(segments.size()):
        var segment := segments[i]
        if segment == null:
            continue
        var top := segment.position.y - (SEGMENT_HEIGHT * 0.5)
        var bottom := segment.position.y + (SEGMENT_HEIGHT * 0.5)
        if local_hit_y >= top and local_hit_y <= bottom:
            sever_index = i
            break
    if sever_index == -1:
        sever_index = segments.size() - 1
    if sever_index >= segments.size():
        return
    var detached_data := []
    for j in range(sever_index, segments.size()):
        var seg := segments[j]
        if seg == null:
            continue
        detached_data.append(seg)
    var new_count: int = max(sever_index, 0)
    segments.resize(new_count)
    _base_positions.resize(new_count)
    segment_count = new_count
    if detached_data.is_empty():
        return
    _spawn_falling_rope(detached_data, impulse_direction)

func _spawn_falling_rope(detached_data: Array, impulse_direction: float) -> void:
    if detached_data.is_empty():
        return
    for seg in detached_data:
        if seg == null:
            continue
        _spawn_single_segment_body(seg, impulse_direction)

func _spawn_single_segment_body(segment: Area2D, impulse_direction: float) -> void:
    if segment == null:
        return
    var body := RigidBody2D.new()
    body.collision_layer = 2
    body.collision_mask = 4 | 2
    body.gravity_scale = 1.0
    body.linear_damp = 0.25
    body.angular_damp = 0.6
    body.global_position = segment.global_position

    if segment.get_parent():
        segment.get_parent().remove_child(segment)
    body.add_child(segment)
    segment.position = Vector2.ZERO
    segment.rotation = 0.0
    segment.monitoring = false
    segment.monitorable = false
    segment.collision_layer = 0
    segment.collision_mask = 0

    var collision := CollisionShape2D.new()
    var shape := RectangleShape2D.new()
    shape.size = Vector2(SEGMENT_WIDTH, SEGMENT_HEIGHT)
    collision.shape = shape
    body.add_child(collision)

    var tree := get_tree()
    if tree and tree.current_scene:
        tree.current_scene.add_child(body)
    body.apply_impulse(Vector2(impulse_direction * 120.0, -70.0))
