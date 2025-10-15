@tool
extends StaticBody2D

var _teeth_color_internal: Color = Color(0.8, 0.8, 0.8)
var _base_color_internal: Color = Color(0.25, 0.25, 0.25)
var _spike_count_internal: int = 1
var _spike_width_internal: float = 48.0
var _spike_height_internal: float = 24.0
var _base_height_internal: float = 12.0

@export var teeth_color: Color = _teeth_color_internal:
    set(value):
        if _teeth_color_internal == value:
            return
        _teeth_color_internal = value
        _schedule_update()
    get:
        return _teeth_color_internal

@export var base_color: Color = _base_color_internal:
    set(value):
        if _base_color_internal == value:
            return
        _base_color_internal = value
        _schedule_update()
    get:
        return _base_color_internal

@export_range(1, 32, 1) var spike_count: int = _spike_count_internal:
    set(value):
        var clamped := clampi(value, 1, 32)
        if _spike_count_internal == clamped:
            return
        _spike_count_internal = clamped
        _schedule_update()
    get:
        return _spike_count_internal

@export var spike_width: float = _spike_width_internal:
    set(value):
        var clamped: float = max(value, 4.0)
        if is_equal_approx(_spike_width_internal, clamped):
            return
        _spike_width_internal = clamped
        _schedule_update()
    get:
        return _spike_width_internal

@export var spike_height: float = _spike_height_internal:
    set(value):
        var clamped: float = max(value, 4.0)
        if is_equal_approx(_spike_height_internal, clamped):
            return
        _spike_height_internal = clamped
        _schedule_update()
    get:
        return _spike_height_internal

@export var base_height: float = _base_height_internal:
    set(value):
        var clamped: float = max(value, 2.0)
        if is_equal_approx(_base_height_internal, clamped):
            return
        _base_height_internal = clamped
        _schedule_update()
    get:
        return _base_height_internal

var _base_polygon: Polygon2D
var _teeth_polygon: Polygon2D
var _base_collision_shape: CollisionShape2D
var _update_requested: bool = false
var _teeth_body_owner: StaticBody2D
var _death_triggered: bool = false
var _last_overlap_count: int = -1

func _cache_nodes() -> void:
    _base_polygon = get_node_or_null("Base") as Polygon2D
    _teeth_polygon = get_node_or_null("Teeth") as Polygon2D
    _base_collision_shape = get_node_or_null("BaseCollision") as CollisionShape2D
    _teeth_body_owner = self as StaticBody2D

func _ready() -> void:
    _schedule_update()

func _schedule_update() -> void:
    if _update_requested:
        return
    _update_requested = true
    call_deferred("_perform_update")

func _perform_update() -> void:
    _update_requested = false
    _ensure_required_nodes()
    _cache_nodes()
    if _teeth_polygon == null:
        return
    _apply_colors_internal()
    _rebuild_geometry_internal()

func _physics_process(_delta: float) -> void:
    var teeth_body := get_node_or_null("TeethBody") as Area2D
    if teeth_body == null:
        return
    var overlaps := teeth_body.get_overlapping_bodies()
    var count := overlaps.size()
    if count != _last_overlap_count:
        _last_overlap_count = count
    if count > 0 and not _death_triggered:
        for body in overlaps:
            var player := _resolve_player_from_node(body)
            if player:
                _trigger_player_death(player)
                break

func _ensure_required_nodes() -> void:
    if get_node_or_null("BaseCollision") == null:
        var base_collision := CollisionShape2D.new()
        base_collision.name = "BaseCollision"
        add_child(base_collision)
        if Engine.is_editor_hint() and get_owner():
            base_collision.owner = get_owner()
    _ensure_teeth_collision_body()

func _ensure_teeth_collision_body() -> void:
    var existing := get_node_or_null("TeethBody") as Area2D
    if existing == null:
        existing = Area2D.new()
        existing.name = "TeethBody"
        add_child(existing)
        if Engine.is_editor_hint() and get_owner():
            existing.owner = get_owner()
        existing.monitoring = true
        existing.monitorable = true
        existing.collision_layer = 4
        existing.collision_mask = 1
        existing.area_entered.connect(_on_teeth_area_entered)
        existing.body_entered.connect(_on_teeth_body_entered)
    _migrate_legacy_teeth_collisions(existing)

func _migrate_legacy_teeth_collisions(target_area: Area2D) -> void:
    if target_area == null:
        return
    var legacy_nodes: Array = []
    var legacy_container := get_node_or_null("TeethCollisions")
    if legacy_container:
        legacy_nodes.append_array(legacy_container.get_children())
    for child in get_children():
        if child is CollisionPolygon2D and child.get_parent() == self and child.name.begins_with("TeethCollision"):
            legacy_nodes.append(child)
    for node in legacy_nodes:
        if node is CollisionPolygon2D:
            if node.get_parent() != target_area:
                node.get_parent().remove_child(node)
                target_area.add_child(node)
                if Engine.is_editor_hint():
                    var target_owner := target_area.owner
                    if target_owner == null:
                        target_owner = get_owner()
                    if target_owner:
                        node.owner = target_owner

func _on_teeth_area_entered(area: Area2D) -> void:
    var player := _resolve_player_from_node(area)
    if player:
        _trigger_player_death(player)

func _on_teeth_body_entered(body: Node) -> void:
    var player := _resolve_player_from_node(body)
    if player:
        _trigger_player_death(player)

func _resolve_player_from_node(node: Node) -> Node:
    var current := node
    while current:
        if current.is_in_group("player"):
            return current
        if current.has_method("kill_player"):
            return current
        current = current.get_parent()
    return null

func _trigger_player_death(player: Node) -> void:
    if _death_triggered:
        return
    _death_triggered = true
    var target := player
    if player and not player.has_method("kill_player"):
        target = player.get_parent()
    if target and target.has_method("kill_player"):
        target.kill_player("spike_trap")
    else:
        var tree := get_tree()
        if tree:
            tree.reload_current_scene()

func _apply_colors_internal() -> void:
    if _base_polygon:
        _base_polygon.color = _base_color_internal
    if _teeth_polygon:
        _teeth_polygon.color = _teeth_color_internal

func _rebuild_collision_segments(start_x: float, tooth_width: float, tooth_height: float, segment_count: int) -> void:
    var teeth_body := get_node_or_null("TeethBody") as Area2D
    if teeth_body == null:
        return

    var existing := {}
    for child in teeth_body.get_children():
        if child is CollisionPolygon2D and child.name.begins_with("TeethCollision"):
            var index := int(child.name.substr(14)) - 1
            existing[index] = child

    for i in range(segment_count):
        var node_name := "TeethCollision" + str(i + 1)
        var collision: CollisionPolygon2D
        if existing.has(i):
            collision = existing[i]
            existing.erase(i)
        else:
            collision = CollisionPolygon2D.new()
            teeth_body.add_child(collision)
        collision.name = node_name
        collision.position = Vector2.ZERO
        collision.rotation = 0.0
        collision.scale = Vector2.ONE
        var poly := PackedVector2Array()
        var left_x: float = start_x + tooth_width * float(i)
        var mid_x: float = left_x + tooth_width * 0.5
        var right_x: float = left_x + tooth_width
        poly.append(Vector2(left_x, 0.0))
        poly.append(Vector2(mid_x, -tooth_height))
        poly.append(Vector2(right_x, 0.0))
        collision.polygon = poly
        if Engine.is_editor_hint():
            var target_owner := teeth_body.owner
            if target_owner == null:
                target_owner = get_owner()
            if target_owner:
                collision.owner = target_owner

    for leftover in existing.values():
        leftover.queue_free()

func _rebuild_geometry_internal() -> void:
    var clamped_count: int = _spike_count_internal
    var clamped_width: float = _spike_width_internal
    var clamped_height: float = _spike_height_internal
    var clamped_base_height: float = _base_height_internal

    var total_width: float = float(clamped_count) * clamped_width
    var half_width: float = total_width * 0.5

    var teeth_points: PackedVector2Array = PackedVector2Array()
    var start_x: float = -half_width
    teeth_points.append(Vector2(start_x, 0.0))
    for i in range(clamped_count):
        var left_x: float = start_x + clamped_width * float(i)
        var mid_x: float = left_x + clamped_width * 0.5
        var right_x: float = left_x + clamped_width
        teeth_points.append(Vector2(mid_x, -clamped_height))
        teeth_points.append(Vector2(right_x, 0.0))

    _teeth_polygon.polygon = teeth_points
    _rebuild_collision_segments(start_x, clamped_width, clamped_height, clamped_count)

    if _base_polygon:
        var base_points := PackedVector2Array()
        base_points.append(Vector2(-half_width, 0.0))
        base_points.append(Vector2(half_width, 0.0))
        base_points.append(Vector2(half_width, clamped_base_height))
        base_points.append(Vector2(-half_width, clamped_base_height))
        _base_polygon.polygon = base_points

    if _base_collision_shape:
        var rect := _base_collision_shape.shape as RectangleShape2D
        if rect == null:
            rect = RectangleShape2D.new()
            _base_collision_shape.shape = rect
        rect.size = Vector2(total_width, clamped_base_height)
        _base_collision_shape.position = Vector2(0.0, clamped_base_height * 0.5)
