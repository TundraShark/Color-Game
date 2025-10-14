extends Node2D

signal color_changed(color: Color, name: String)

@export var paint_blob_scene: PackedScene
@export var fire_interval := 0.07
@export var muzzle_offset := Vector2(24, 0)
@export var projectile_speed := 750.0
@export var melee_radius := 96.0
@export var melee_decal_count := 18
@export var melee_cooldown := 0.5

const SHOOT_SFX_PATH := "res://assets/sfx/fire-paintball.wav"
const SHOOT_PITCH_VARIATIONS: Array[float] = [0.12, 0.08, 0.04, 0.0, -0.04, -0.08, -0.12]
const MELEE_SWOOSH_SFX_PATHS := [
    "res://assets/sfx/tail-swoosh-1.wav",
    "res://assets/sfx/tail-swoosh-2.wav",
    "res://assets/sfx/tail-swoosh-3.wav"
]
const MELEE_PITCH_VARIATIONS: Array[float] = SHOOT_PITCH_VARIATIONS

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

var _shared_cooldown := 0.0
var _fire_cooldown := 0.0

var _shoot_sfx: AudioStreamPlayer
var _melee_sfx: AudioStreamPlayer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _decal_scene: PackedScene
var _is_melee_animating := false
var _melee_tween: Tween
var _melee_base_rotation := 0.0
var _recovering_to_mouse := false
var _melee_swoosh_streams: Array[AudioStream] = []

func _ready() -> void:
    if paint_blob_scene == null:
        push_warning("Tail has no paint_blob_scene assigned")
    add_to_group("paint_color_source")
    _rng.randomize()
    _shoot_sfx = get_parent().get_node_or_null("ShootSFX")
    _melee_sfx = get_parent().get_node_or_null("TailSwooshSFX")
    _decal_scene = preload("res://scenes/paint_decal.tscn")
    if _shoot_sfx:
        _shoot_sfx.bus = "SFX"
        if not _shoot_sfx.stream:
            var stream: AudioStream = load(SHOOT_SFX_PATH)
            if stream:
                _shoot_sfx.stream = stream
            else:
                push_warning("Tail could not load shoot SFX at %s" % SHOOT_SFX_PATH)
    if _melee_sfx:
        _melee_sfx.bus = "SFX"
        _load_melee_swoosh_streams()
    _emit_color_changed()

func _process(delta: float) -> void:
    var target := get_global_mouse_position()
    if _recovering_to_mouse:
        var desired := (target - global_position).angle()
        rotation = lerp_angle(rotation, desired, clamp(delta * 12.0, 0.0, 1.0))
        if absf(wrapf(rotation - desired, -PI, PI)) < deg_to_rad(1.5):
            _recovering_to_mouse = false
    elif not _is_melee_animating:
        look_at(target)
    _shared_cooldown = maxf(_shared_cooldown - delta, 0.0)
    _fire_cooldown = maxf(_fire_cooldown - delta, 0.0)

    for key in COLOR_MAP.keys():
        if key != _current_color_key and Input.is_key_pressed(key):
            _set_current_color_key(key)
            break

    var right_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
    var left_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

    if _shared_cooldown > 0.0:
        return

    if right_pressed and _fire_cooldown <= 0.0:
        _fire()
    elif left_pressed:
        _melee_swoosh()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        var mouse_event := event as InputEventMouseButton
        if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _cycle_color(-1)
        elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _cycle_color(1)

func _fire() -> void:
    if paint_blob_scene == null:
        return

    if _shoot_sfx:
        if SHOOT_PITCH_VARIATIONS.size() > 0:
            var pitch_offset: float = SHOOT_PITCH_VARIATIONS[_rng.randi_range(0, SHOOT_PITCH_VARIATIONS.size() - 1)]
            _shoot_sfx.pitch_scale = 1.0 + pitch_offset
        if _shoot_sfx.playing:
            _shoot_sfx.stop()
        _shoot_sfx.play()

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
    _fire_cooldown = fire_interval

func _melee_swoosh() -> void:
    if _decal_scene == null:
        return
    var parent_node := get_tree().current_scene
    if parent_node == null:
        return
    var world := get_world_2d()
    if world == null:
        return
    var space := world.direct_space_state
    if space == null:
        return

    var effective_radius: float = melee_radius * 0.5
    var surfaces: Array[Dictionary] = []
    var ray_count: int = max(melee_decal_count, 12)
    for i in range(ray_count):
        var angle_ratio: float = float(i) / float(ray_count)
        var angle: float = angle_ratio * TAU
        var direction: Vector2 = Vector2.RIGHT.rotated(angle)
        var ray_from: Vector2 = global_position
        var ray_to: Vector2 = global_position + direction * effective_radius
        var params := PhysicsRayQueryParameters2D.new()
        params.from = ray_from
        params.to = ray_to
        params.collide_with_areas = true
        params.collide_with_bodies = true
        params.hit_from_inside = true
        params.exclude = [self, get_parent()]
        var hit: Dictionary = space.intersect_ray(params)
        if hit.is_empty():
            continue
        surfaces.append(hit)

    if not surfaces.is_empty():
        var is_red := _current_color_name.to_lower() == "red"
        var decals_per_surface: int = max(1, int(ceil(float(melee_decal_count) / float(surfaces.size()))))
        for hit_data in surfaces:
            var hit_dict: Dictionary = hit_data
            var base_position: Vector2 = hit_dict["position"]
            var hit_normal: Vector2 = hit_dict["normal"]
            if hit_normal == Vector2.ZERO:
                hit_normal = (base_position - global_position).normalized()
            var tangent: Vector2 = Vector2(-hit_normal.y, hit_normal.x).normalized()
            var surface_radius: float = effective_radius * 0.45
            for j in range(decals_per_surface):
                var spread_ratio: float = 0.0
                if decals_per_surface > 1:
                    spread_ratio = float(j) / float(decals_per_surface - 1)
                var offset_amount: float = lerp(-surface_radius, surface_radius, spread_ratio)
                var tangent_offset: Vector2 = tangent * offset_amount
                var probe_distance: float = 6.0
                var probe_start: Vector2 = base_position + tangent_offset + hit_normal * probe_distance
                var probe_end: Vector2 = base_position + tangent_offset - hit_normal * probe_distance
                var probe_params := PhysicsRayQueryParameters2D.new()
                probe_params.from = probe_start
                probe_params.to = probe_end
                probe_params.collide_with_areas = true
                probe_params.collide_with_bodies = true
                probe_params.hit_from_inside = true
                probe_params.exclude = [self, get_parent()]
                var probe_hit: Dictionary = space.intersect_ray(probe_params)
                if probe_hit.is_empty():
                    continue
                var placement_position: Vector2 = probe_hit["position"]
                var placement_normal: Vector2 = probe_hit["normal"]
                if placement_normal == Vector2.ZERO:
                    placement_normal = hit_normal
                if is_red:
                    _clear_paint_decals(placement_position)
                    _clear_vines(placement_position)
                    continue
                var decal := _decal_scene.instantiate()
                if decal is Node2D:
                    var node2d := decal as Node2D
                    node2d.global_position = placement_position
                    node2d.rotation = placement_normal.angle() + deg_to_rad(90.0)
                if decal.has_method("configure"):
                    decal.configure(_rng, placement_normal, _current_color, _current_color_name, Vector2.ZERO)
                parent_node.add_child(decal)

    _shared_cooldown = melee_cooldown
    _start_melee_animation()
    _play_melee_sfx()

func _start_melee_animation() -> void:
    if _is_melee_animating:
        _finish_melee_animation()
    _is_melee_animating = true
    _melee_base_rotation = rotation
    _recovering_to_mouse = false
    if _melee_tween and _melee_tween.is_running():
        _melee_tween.kill()
    var full_rotation := TAU
    _melee_tween = create_tween()
    _melee_tween.tween_property(self, "rotation", _melee_base_rotation + full_rotation * 0.7, melee_cooldown * 0.7).set_trans(Tween.TRANS_LINEAR)
    _melee_tween.tween_property(self, "rotation", _melee_base_rotation + full_rotation, melee_cooldown * 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    _melee_tween.finished.connect(Callable(self, "_finish_melee_animation"), CONNECT_ONE_SHOT)

func _finish_melee_animation() -> void:
    if _melee_tween and _melee_tween.is_running():
        _melee_tween.kill()
    rotation = _melee_base_rotation
    _melee_tween = null
    _is_melee_animating = false
    _recovering_to_mouse = true

func _load_melee_swoosh_streams() -> void:
    _melee_swoosh_streams.clear()
    for path in MELEE_SWOOSH_SFX_PATHS:
        var stream: AudioStream = load(path)
        if stream:
            _melee_swoosh_streams.append(stream)
        else:
            push_warning("Tail could not load melee SFX at %s" % path)

func _play_melee_sfx() -> void:
    if _melee_sfx == null:
        return
    if _melee_swoosh_streams.is_empty():
        return
    if _melee_sfx.stream == null:
        return
    _melee_sfx.stream = _melee_swoosh_streams[_rng.randi_range(0, _melee_swoosh_streams.size() - 1)]
    _melee_sfx.pitch_scale = 1.0 + MELEE_PITCH_VARIATIONS[_rng.randi_range(0, MELEE_PITCH_VARIATIONS.size() - 1)]
    _melee_sfx.play()

func _clear_paint_decals(point: Vector2, radius: float = 40.0) -> void:
    var tree := get_tree()
    if tree == null:
        return
    for node in tree.get_nodes_in_group("paint_decal"):
        if node is Node2D:
            var decal := node as Node2D
            if not decal.is_inside_tree():
                continue
            if decal.global_position.distance_to(point) <= radius:
                decal.queue_free()

func _clear_vines(point: Vector2, radius: float = 80.0) -> void:
    var tree := get_tree()
    if tree == null:
        return
    var radius_sq := radius * radius
    var nodes_to_free: Array[Node] = []
    for node in tree.get_nodes_in_group("vine_paint"):
        if node == null or not node.is_inside_tree():
            continue
        if node is Node2D:
            var node2d := node as Node2D
            if node2d.global_position.distance_squared_to(point) <= radius_sq and node2d not in nodes_to_free:
                nodes_to_free.append(node2d)
        elif node is Area2D:
            var area := node as Area2D
            if area.global_position.distance_squared_to(point) <= radius_sq and area not in nodes_to_free:
                nodes_to_free.append(area)
        var parent := node.get_parent()
        if parent is Node2D:
            var parent2d := parent as Node2D
            if parent2d.global_position.distance_squared_to(point) <= radius_sq and parent2d not in nodes_to_free:
                nodes_to_free.append(parent2d)
    for target in nodes_to_free:
        if target != null and target.is_inside_tree():
            target.queue_free()

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
