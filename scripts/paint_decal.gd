extends Node2D

const ALPHA_RANGE := Vector2(0.6, 0.95)
const CONVEYOR_SPEED := 220.0
const CONVEYOR_FORCE := 950.0
const CONVEYOR_TEXTURE_WIDTH := 48
const CONVEYOR_TEXTURE_HEIGHT := 20
const VINE_LAYER := 128
const DEFAULT_VINE_LENGTH := 72.0

@export var vine_scene: PackedScene

const VINE_NONE := 0
const VINE_HORIZONTAL := 1
const VINE_VERTICAL := 2

var paint_color: Color = Color.WHITE
var paint_name: String = ""
var is_slippery := false
var is_bouncy := false
var is_vine := false
var is_conveyor := false
var bounce_strength := 0.0
var _vine_spawned := false
var _surface_normal := Vector2.UP
var _vine_orientation := VINE_NONE
var _conveyor_direction := 0
var _conveyor_axis := Vector2.ZERO
var _conveyor_bodies: Array[PhysicsBody2D] = []
var _default_texture: Texture2D
var _default_area_shape: Shape2D
var _default_area_position := Vector2.ZERO

static var _conveyor_texture_left: Texture2D
static var _conveyor_texture_right: Texture2D
static var _conveyor_textures_ready := false

@onready var area: Area2D = $Area
@onready var swatch: Sprite2D = $Swatch

func _ready() -> void:
    if swatch:
        _default_texture = swatch.texture
    if area:
        var shape_node := area.get_node_or_null("CollisionShape2D")
        if shape_node and shape_node.shape:
            _default_area_shape = shape_node.shape.duplicate()
            _default_area_position = shape_node.position
    _refresh_area_state()
    if is_vine:
        _spawn_vine()
    if is_conveyor:
        _ensure_conveyor_textures()
        _apply_conveyor_texture()
    if area and not area.body_entered.is_connected(_on_area_body_entered):
        area.body_entered.connect(_on_area_body_entered)
        area.body_exited.connect(_on_area_body_exited)
        area.area_entered.connect(_on_area_area_entered)
        area.area_exited.connect(_on_area_area_exited)

func _physics_process(delta: float) -> void:
    if not is_conveyor:
        return
    _apply_conveyor_to_bodies(delta)

func configure(rng: RandomNumberGenerator, normal: Vector2, paint_color_in: Color, paint_name_in: String, impact_velocity: Vector2 = Vector2.ZERO) -> void:
    paint_color = paint_color_in
    paint_name = paint_name_in
    is_slippery = paint_name == "Blue"
    is_bouncy = paint_name == "Yellow"
    is_vine = paint_name == "Green"
    is_conveyor = paint_name == "Orange"
    _surface_normal = normal.normalized()
    if is_vine:
        _vine_orientation = _determine_vine_orientation(_surface_normal)
    bounce_strength = 1050.0 if is_bouncy else 0.0
    if is_conveyor:
        _configure_conveyor(rng, impact_velocity)
        _ensure_conveyor_textures()
        _apply_conveyor_texture()
    elif swatch and _default_texture:
        swatch.texture = _default_texture
    if is_slippery:
        print_debug("[PaintDecal] Slippery decal created at ", global_position)
    elif is_bouncy:
        print_debug("[PaintDecal] Bouncy (yellow) decal created at ", global_position, " strength=", bounce_strength)
    elif is_conveyor:
        print_debug("[PaintDecal] Conveyor decal (orange) created at ", global_position, " dir=", _conveyor_direction)
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

    var sprite_scale := Vector2(rng.randf_range(0.7, 1.3), rng.randf_range(0.6, 1.1))
    for child in get_children():
        if child is Sprite2D:
            var sprite := child as Sprite2D
            if is_vine:
                sprite.modulate = Color(0.2, 0.98, 0.4, 1.0)
                sprite.scale = sprite_scale
            elif is_conveyor:
                sprite.scale = Vector2(1, 1)
                sprite.modulate = Color(1, 1, 1, 1)
            else:
                sprite.scale = sprite_scale
                var alpha := rng.randf_range(ALPHA_RANGE.x, ALPHA_RANGE.y)
                sprite.modulate = Color(paint_color.r, paint_color.g, paint_color.b, alpha)

func _refresh_area_state() -> void:
    if area == null:
        return
    area.monitorable = true
    area.monitoring = is_slippery or is_bouncy or is_conveyor or is_vine
    if is_slippery:
        area.collision_layer = 16
        area.collision_mask = 1
    elif is_bouncy:
        area.collision_layer = 32
        area.collision_mask = 1
    elif is_conveyor:
        area.collision_layer = 64
        area.collision_mask = 1
    elif is_vine:
        area.collision_layer = VINE_LAYER
        area.collision_mask = 1
    else:
        area.collision_layer = 0
        area.collision_mask = 0
    area.set_meta("bounce_strength", bounce_strength)
    if is_conveyor:
        area.set_meta("conveyor_direction", _conveyor_direction)
    elif area.has_meta("conveyor_direction"):
        area.remove_meta("conveyor_direction")
    if is_vine:
        area.set_meta("is_vine", true)
    elif area.has_meta("is_vine"):
        area.remove_meta("is_vine")
    if is_vine:
        _configure_vine_collision_shape()
    else:
        _restore_default_area_shape()
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
    if is_conveyor:
        if not area.is_in_group("conveyor_paint"):
            area.add_to_group("conveyor_paint")
        if not is_in_group("conveyor_paint"):
            add_to_group("conveyor_paint")
    else:
        if area.is_in_group("conveyor_paint"):
            area.remove_from_group("conveyor_paint")
        if is_in_group("conveyor_paint"):
            remove_from_group("conveyor_paint")
    if is_vine:
        if not area.is_in_group("vine_paint"):
            area.add_to_group("vine_paint")
        if not is_in_group("vine_paint"):
            add_to_group("vine_paint")
    else:
        if area.is_in_group("vine_paint"):
            area.remove_from_group("vine_paint")
        if is_in_group("vine_paint"):
            remove_from_group("vine_paint")

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
        _attach_vine_area(vine_node, _vine_orientation)
        print_debug("[PaintDecal] Vine scene spawned at ", vine_node.global_position, " orientation=", _vine_orientation)
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
    _attach_vine_area(vine_root, _vine_orientation)
    print_debug("[PaintDecal] Vine placeholder spawned at ", vine_root.global_position, " orientation=", _vine_orientation)
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

func _configure_conveyor(rng: RandomNumberGenerator, impact_velocity: Vector2) -> void:
    var horizontal_speed := impact_velocity.x
    if abs(horizontal_speed) >= 40.0:
        _conveyor_direction = -1 if horizontal_speed < 0.0 else 1
    else:
        _conveyor_direction = -1 if rng.randf() < 0.5 else 1
    _conveyor_axis = Vector2(_conveyor_direction, 0).normalized()
    _conveyor_bodies.clear()

func _ensure_conveyor_textures() -> void:
    if _conveyor_textures_ready:
        return
    _conveyor_texture_left = _create_conveyor_texture(-1)
    _conveyor_texture_right = _create_conveyor_texture(1)
    _conveyor_textures_ready = true

func _apply_conveyor_texture() -> void:
    if swatch == null:
        return
    if _conveyor_direction < 0:
        swatch.texture = _conveyor_texture_left
    else:
        swatch.texture = _conveyor_texture_right
    swatch.scale = Vector2(1, 1)

func _create_conveyor_texture(direction: int) -> Texture2D:
    var img := Image.create(CONVEYOR_TEXTURE_WIDTH, CONVEYOR_TEXTURE_HEIGHT, false, Image.FORMAT_RGBA8)
    if direction < 0:
        img.fill(Color(0.36, 0.18, 0.58, 1.0))   # solid violet
    else:
        img.fill(Color(0.08, 0.48, 0.42, 1.0))   # solid teal

    var tex := ImageTexture.create_from_image(img)
    return tex

func _attach_vine_area(parent: Node2D, orientation_value: int) -> void:
    if parent.get_node_or_null("VineArea") != null:
        return
    var vine_area := Area2D.new()
    vine_area.name = "VineArea"
    vine_area.monitoring = true
    vine_area.monitorable = true
    vine_area.collision_layer = VINE_LAYER
    vine_area.collision_mask = 1
    if not vine_area.is_in_group("vine_paint"):
        vine_area.add_to_group("vine_paint")
    vine_area.set_meta("is_vine", true)

    var shape := RectangleShape2D.new()
    var size := Vector2(36.0, DEFAULT_VINE_LENGTH)
    var area_offset := Vector2(0, DEFAULT_VINE_LENGTH * 0.5)
    if orientation_value == VINE_HORIZONTAL:
        size = Vector2(DEFAULT_VINE_LENGTH, 36.0)
        area_offset = Vector2(0, 0)
    shape.size = size

    var collider := CollisionShape2D.new()
    collider.name = "VineShape"
    collider.shape = shape
    vine_area.add_child(collider)

    vine_area.position = area_offset
    parent.add_child(vine_area)
    print_debug("[PaintDecal] VineArea added", " parent=", parent.name, " local_offset=", area_offset, " size=", shape.size)

func _configure_vine_collision_shape() -> void:
    if area == null:
        return
    var shape_node := area.get_node_or_null("CollisionShape2D")
    if shape_node == null:
        return
    var rect := RectangleShape2D.new()
    var size := Vector2(48.0, DEFAULT_VINE_LENGTH + 24.0)
    var offset := Vector2(0, (DEFAULT_VINE_LENGTH + 24.0) * 0.5)
    if _vine_orientation == VINE_HORIZONTAL:
        size = Vector2(DEFAULT_VINE_LENGTH + 24.0, 48.0)
        offset = Vector2(0, 0)
    rect.size = size
    shape_node.shape = rect
    shape_node.position = offset
    print_debug("[PaintDecal] Decal vine collision shape configured size=", size, " offset=", offset)

func _restore_default_area_shape() -> void:
    if area == null:
        return
    var shape_node := area.get_node_or_null("CollisionShape2D")
    if shape_node == null:
        return
    if _default_area_shape:
        shape_node.shape = _default_area_shape.duplicate()
    shape_node.position = _default_area_position
    print_debug("[PaintDecal] Decal area reset to default shape")

func _on_area_body_entered(body: Node) -> void:
    if not is_conveyor:
        return
    if body is RigidBody2D and body not in _conveyor_bodies:
        _conveyor_bodies.append(body)

func _on_area_body_exited(body: Node) -> void:
    if not is_conveyor:
        return
    if body in _conveyor_bodies:
        _conveyor_bodies.erase(body)

func _on_area_area_entered(_other_area: Area2D) -> void:
    pass

func _on_area_area_exited(_other_area: Area2D) -> void:
    pass

func _apply_conveyor_to_bodies(delta: float) -> void:
    var speed := CONVEYOR_SPEED * _conveyor_direction
    var force := CONVEYOR_FORCE * _conveyor_direction
    for i in range(_conveyor_bodies.size() - 1, -1, -1):
        var body := _conveyor_bodies[i]
        if body == null or not is_instance_valid(body):
            _conveyor_bodies.remove_at(i)
            continue
        if body is RigidBody2D:
            var rb := body as RigidBody2D
            var vel := rb.linear_velocity
            vel.x = lerp(vel.x, speed, clamp(delta * 4.0, 0.0, 1.0))
            rb.linear_velocity = vel
            rb.apply_central_force(Vector2(force, 0))
