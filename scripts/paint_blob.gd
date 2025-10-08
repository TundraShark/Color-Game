extends RigidBody2D

const DECAL_COUNT := 5
const CEILING_PROBE_THRESHOLD := 8.0
const FLOOR_PROBE_THRESHOLD := 10.0
const WALL_PROBE_THRESHOLD := 8.0
const VINE_LAYER := 128
const VINE_AREA_WIDTH := 12.0
const VINE_AREA_LENGTH := 56.0

@export var decal_scene: PackedScene
@export var vine_scene: PackedScene

var paint_color: Color = Color(1, 0.6, 0.2)
var paint_color_name: String = "Orange"

var _rng := RandomNumberGenerator.new()
var _decals_spawned := false
var _sprite: Sprite2D

func _ready() -> void:
    contact_monitor = true
    max_contacts_reported = 4
    gravity_scale = 1.2
    _rng.randomize()
    _sprite = get_node_or_null("Sprite2D")
    _apply_color_to_sprite()

func set_color(new_color: Color, color_name: String = "") -> void:
    paint_color = new_color
    if color_name != "":
        paint_color_name = color_name
    _apply_color_to_sprite()

func _apply_color_to_sprite() -> void:
    if _sprite:
        _sprite.modulate = paint_color

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
    if _decals_spawned:
        return
    var velocity := state.linear_velocity
    if velocity.length() > 0.0:
        rotation = velocity.angle()

    var contact_count := state.get_contact_count()
    if contact_count <= 0:
        return

    _decals_spawned = true

    var contact_point := state.get_contact_collider_position(0)
    var averaged_normal := Vector2.ZERO
    for i in range(contact_count):
        var local_normal := state.get_contact_local_normal(i)
        var world_normal := global_transform.basis_xform(local_normal).normalized()
        averaged_normal += world_normal
    if averaged_normal == Vector2.ZERO:
        averaged_normal = state.get_contact_local_normal(0)
        averaged_normal = global_transform.basis_xform(averaged_normal)
    var contact_normal := averaged_normal.normalized()

    _spawn_decals(contact_point, contact_normal, velocity)
    call_deferred("queue_free")

func _spawn_decals(point: Vector2, normal: Vector2, impact_velocity: Vector2) -> void:
    var safe_normal := normal
    if safe_normal == Vector2.ZERO:
        safe_normal = Vector2.UP
    safe_normal = safe_normal.normalized()

    if paint_color_name == "Green":
        var orientation_value: int = _classify_surface_orientation(point, safe_normal)
        if orientation_value == -1:
            orientation_value = _determine_vine_orientation(safe_normal)
        _log_green_hit(point, safe_normal, orientation_value)
        _spawn_vine(point, orientation_value)
        return

    if decal_scene == null:
        return

    var tangent := Vector2(-safe_normal.y, safe_normal.x).normalized()
    var base_rotation := safe_normal.angle() + deg_to_rad(90.0)
    var parent_node: Node = get_tree().current_scene

    for i in range(DECAL_COUNT):
        var decal_instance := decal_scene.instantiate()
        if decal_instance is Node2D:
            var tangent_offset := tangent * _rng.randf_range(-12.0, 12.0)
            var normal_offset := safe_normal * _rng.randf_range(-3.0, 3.0)
            var node2d := decal_instance as Node2D
            node2d.global_position = point + tangent_offset + normal_offset
            node2d.rotation = base_rotation + deg_to_rad(_rng.randf_range(-35.0, 35.0))
        if decal_instance.has_method("configure"):
            decal_instance.configure(_rng, safe_normal, paint_color, paint_color_name, impact_velocity)
        parent_node.add_child(decal_instance)

func _spawn_vine(point: Vector2, orientation_value: int) -> void:
    if orientation_value == 0:
        return
    if vine_scene == null:
        var parent_node := get_tree().current_scene
        if parent_node == null:
            return
        var placeholder := Node2D.new()
        placeholder.name = "VinePlaceholder"
        placeholder.global_position = point

        var vine_line := Line2D.new()
        vine_line.default_color = paint_color
        vine_line.width = 8.0
        vine_line.joint_mode = Line2D.LINE_JOINT_ROUND
        vine_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
        vine_line.end_cap_mode = Line2D.LINE_CAP_ROUND

        var length := 72.0
        match orientation_value:
            2:
                vine_line.points = [Vector2.ZERO, Vector2(0, length)]
            1:
                var half_length := length * 0.5
                vine_line.points = [Vector2(-half_length, 0), Vector2(half_length, 0)]
            _:
                vine_line.points = [Vector2.ZERO, Vector2(length, 0)]

        placeholder.add_child(vine_line)
        parent_node.add_child(placeholder)
        _create_vine_area(parent_node, point, orientation_value)
        return

    var vine_instance := vine_scene.instantiate()
    if vine_instance is Node2D:
        var vine_node := vine_instance as Node2D
        vine_node.global_position = point
    if vine_instance.has_method("set_vine_orientation"):
        vine_instance.set_vine_orientation(orientation_value)
    elif vine_instance.has_method("set_orientation"):
        vine_instance.set_orientation(orientation_value)
    else:
        vine_instance.set_meta("vine_orientation", orientation_value)
    var parent := get_tree().current_scene
    if parent:
        parent.add_child(vine_instance)
        _create_vine_area(parent, point, orientation_value)

func _determine_vine_orientation(surface_normal: Vector2) -> int:
    var n: Vector2 = surface_normal.normalized()
    if n.y <= -0.45:
        return 2
    if n.y >= 0.45:
        return 0
    if abs(n.x) >= 0.35:
        return 1
    return 0

func _classify_surface_orientation(point: Vector2, surface_normal: Vector2) -> int:
    var space := get_world_2d().direct_space_state
    if space == null:
        return -1

    var up_distance: float = _probe_distance(space, point, Vector2.UP)
    var down_distance: float = _probe_distance(space, point, Vector2.DOWN)
    var left_distance: float = _probe_distance(space, point, Vector2.LEFT)
    var right_distance: float = _probe_distance(space, point, Vector2.RIGHT)

    var orientation_from_normal: int = _determine_vine_orientation(surface_normal)

    var floor_hit: bool = down_distance < INF and down_distance <= FLOOR_PROBE_THRESHOLD
    if floor_hit:
        return 0

    var ceiling_hit: bool = up_distance < INF and up_distance <= CEILING_PROBE_THRESHOLD
    if ceiling_hit:
        return 2

    var best_wall: float = min(left_distance, right_distance)
    var wall_hit: bool = best_wall < INF and best_wall <= WALL_PROBE_THRESHOLD
    if wall_hit and not floor_hit:
        return 1

    if orientation_from_normal == 2:
        return 2
    if orientation_from_normal == 0:
        return 0
    if orientation_from_normal == 1 and wall_hit:
        return 1

    return -1

func _probe_distance(space: PhysicsDirectSpaceState2D, origin: Vector2, direction: Vector2) -> float:
    if direction == Vector2.ZERO:
        return INF
    var distances := [4.0, 8.0, 16.0]
    for distance in distances:
        var params := PhysicsPointQueryParameters2D.new()
        params.position = origin + direction * distance
        params.collide_with_areas = true
        params.collide_with_bodies = true
        params.exclude = [self]
        var results := space.intersect_point(params, 1)
        if results.size() > 0:
            return distance
    return INF

func _log_green_hit(point: Vector2, normal: Vector2, orientation_value: int) -> void:
    var orientation_label := "None"
    match orientation_value:
        1:
            orientation_label = "Horizontal"
        2:
            orientation_label = "Vertical"
    print_debug("[PaintBlob] Green hit at ", point, " normal=", normal, " orientation=", orientation_label)

func _create_vine_area(parent: Node, point: Vector2, orientation_value: int) -> void:
    if parent == null:
        return
    var area := Area2D.new()
    area.name = "VineClimbArea"
    area.global_position = point
    area.monitoring = true
    area.monitorable = true
    area.collision_layer = VINE_LAYER
    area.collision_mask = 1
    if not area.is_in_group("vine_paint"):
        area.add_to_group("vine_paint")
    area.set_meta("is_vine", true)

    var shape := RectangleShape2D.new()
    var size := Vector2(VINE_AREA_WIDTH, VINE_AREA_LENGTH)
    var offset := Vector2(0, VINE_AREA_LENGTH * 0.35)
    if orientation_value == 1:
        size = Vector2(VINE_AREA_LENGTH, VINE_AREA_WIDTH)
        offset = Vector2(0, 0)
    elif orientation_value == 0:
        size = Vector2(VINE_AREA_WIDTH, VINE_AREA_WIDTH)
        offset = Vector2(0, VINE_AREA_WIDTH * 0.5)
    shape.size = size

    var collider := CollisionShape2D.new()
    collider.name = "VineClimbShape"
    collider.shape = shape
    collider.position = offset
    area.add_child(collider)

    parent.add_child(area)
    print_debug("[PaintBlob] Vine climb area created at ", point, " size=", size, " offset=", offset, " orientation=", orientation_value)
