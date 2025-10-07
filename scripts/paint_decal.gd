extends Node2D

const ALPHA_RANGE := Vector2(0.6, 0.95)

@export var vine_scene: PackedScene

const VINE_NONE := 0
const VINE_HORIZONTAL := 1
const VINE_VERTICAL := 2

var paint_color: Color = Color.WHITE
var paint_name: String = ""
var is_slippery := false
var is_bouncy := false
var is_vine := false
var bounce_strength := 0.0
var _vine_spawned := false
var _surface_normal := Vector2.UP
var _vine_orientation := VINE_NONE

@onready var area: Area2D = $Area

func _ready() -> void:
    _refresh_area_state()
    if is_vine:
        _spawn_vine()

func configure(rng: RandomNumberGenerator, normal: Vector2, paint_color_in: Color, paint_name_in: String) -> void:
    paint_color = paint_color_in
    paint_name = paint_name_in
    is_slippery = paint_name == "Blue"
    is_bouncy = paint_name == "Yellow"
    is_vine = paint_name == "Green"
    _surface_normal = normal.normalized()
    if is_vine:
        _vine_orientation = _determine_vine_orientation(_surface_normal)
    bounce_strength = 1050.0 if is_bouncy else 0.0
    if is_slippery:
        print_debug("[PaintDecal] Slippery decal created at ", global_position)
    elif is_bouncy:
        print_debug("[PaintDecal] Bouncy (yellow) decal created at ", global_position, " strength=", bounce_strength)
    else:
        print_debug("[PaintDecal] Non-slippery decal created at ", global_position, " color=", paint_name)

    var safe_normal := normal
    if safe_normal == Vector2.ZERO:
        safe_normal = Vector2.UP
    var tangent := Vector2(-safe_normal.y, safe_normal.x)
    if tangent == Vector2.ZERO:
        tangent = Vector2.RIGHT
    var angle_variation := deg_to_rad(rng.randf_range(-20.0, 20.0))
    rotation = tangent.angle() + angle_variation

    var scale_base := rng.randf_range(0.8, 1.25)
    scale = Vector2(scale_base, scale_base * rng.randf_range(0.7, 1.1))

    _refresh_area_state()

    for child in get_children():
        if child is Sprite2D:
            var sprite := child as Sprite2D
            sprite.scale = Vector2(rng.randf_range(0.7, 1.3), rng.randf_range(0.6, 1.1))
            var alpha := rng.randf_range(ALPHA_RANGE.x, ALPHA_RANGE.y)
            sprite.modulate = Color(paint_color.r, paint_color.g, paint_color.b, alpha)

func _refresh_area_state() -> void:
    if area == null:
        return
    area.monitorable = true
    area.collision_layer = 16 if is_slippery else (32 if is_bouncy else 0)
    area.collision_mask = 1 if (is_slippery or is_bouncy) else 0
    area.set_meta("bounce_strength", bounce_strength)
    if is_slippery:
        if not area.is_in_group("slippery_paint"):
            area.add_to_group("slippery_paint")
        if not is_in_group("slippery_paint"):
            add_to_group("slippery_paint")
        print_debug("[PaintDecal] Area enabled for slippery paint at ", global_position)
    else:
        if area.is_in_group("slippery_paint"):
            area.remove_from_group("slippery_paint")
        if is_in_group("slippery_paint"):
            remove_from_group("slippery_paint")
        print_debug("[PaintDecal] Area disabled for non-slippery paint at ", global_position)

    if is_bouncy:
        if not area.is_in_group("bouncy_paint"):
            area.add_to_group("bouncy_paint")
        if not is_in_group("bouncy_paint"):
            add_to_group("bouncy_paint")
        print_debug("[PaintDecal] Area enabled for bouncy paint at ", global_position)
    else:
        if is_in_group("bouncy_paint"):
            remove_from_group("bouncy_paint")

func _spawn_vine() -> void:
    if _vine_spawned or _vine_orientation == VINE_NONE:
        return
    if vine_scene == null:
        _spawn_placeholder_vine()
        return
    var parent_node := get_parent()
    if parent_node == null:
        return
    var vine := vine_scene.instantiate()
    if vine is Node2D:
        var vine_node := vine as Node2D
        vine_node.global_position = global_position
    parent_node.add_child(vine)
    if vine.has_method("set_vine_orientation"):
        vine.set_vine_orientation(_vine_orientation)
    elif vine.has_method("set_orientation"):
        vine.set_orientation(_vine_orientation)
    else:
        vine.set_meta("vine_orientation", _vine_orientation)
    _vine_spawned = true

func _spawn_placeholder_vine() -> void:
    if _vine_spawned or _vine_orientation == VINE_NONE:
        return
    var parent_node := get_parent()
    if parent_node == null:
        return
    var vine_root := Node2D.new()
    vine_root.name = "VinePlaceholder"
    vine_root.global_position = global_position

    var vine_line := Line2D.new()
    vine_line.default_color = Color(1.0, 0.2, 0.8)
    vine_line.width = 8.0
    vine_line.joint_mode = Line2D.LINE_JOINT_ROUND
    vine_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
    vine_line.end_cap_mode = Line2D.LINE_CAP_ROUND

    var length := 72.0
    match _vine_orientation:
        VINE_VERTICAL:
            vine_line.points = [Vector2.ZERO, Vector2(0, length)]
        VINE_HORIZONTAL:
            var half_length := length * 0.5
            vine_line.points = [Vector2(-half_length, 0), Vector2(half_length, 0)]
        _:
            vine_line.points = [Vector2.ZERO, Vector2(length, 0)]

    vine_root.add_child(vine_line)
    parent_node.add_child(vine_root)
    _vine_spawned = true

func _determine_vine_orientation(surface_normal: Vector2) -> int:
    var n := surface_normal.normalized()
    if abs(n.y) >= abs(n.x):
        if n.y > 0.3:
            return VINE_VERTICAL
        return VINE_NONE
    if abs(n.x) > 0.3:
        return VINE_HORIZONTAL
    return VINE_NONE
