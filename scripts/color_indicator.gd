extends Control

const COLOR_PRESET := [
    {"name": "Blue", "color": Color(0.4, 0.7, 1.0)},
    {"name": "Yellow", "color": Color(1.0, 0.9, 0.0)},
    {"name": "Green", "color": Color(0.0, 0.9, 0.3)},
    {"name": "Purple", "color": Color(0.6, 0.2, 0.9)},
    {"name": "Orange", "color": Color(1.0, 0.6, 0.0)},
    {"name": "Red", "color": Color(1.0, 0.1, 0.1)}
]

const COLOR_TEXTURES := {
    "Blue": preload("res://assets/game/paint-blue.png"),
    "Purple": preload("res://assets/game/paint-purple.png"),
    "Red": preload("res://assets/game/paint-red.png"),
    "Yellow": preload("res://assets/game/paint-yellow.png")
}

const ACTIVE_SIZE := 28.0
const INACTIVE_SIZE := 18.0
const ACTIVE_ALPHA := 1.0
const INACTIVE_ALPHA := 0.55

var _source_node: Node = null
var _slot_nodes: Dictionary = {}
var _circle_nodes: Dictionary = {}
var _circle_styles: Dictionary = {}

@onready var _palette: HBoxContainer = $Palette

func _ready() -> void:
    _build_palette()
    _connect_to_color_source()
    get_tree().node_added.connect(_on_node_added)

func _build_palette() -> void:
    var children := _palette.get_children()
    for i in range(min(children.size(), COLOR_PRESET.size())):
        var slot_control := children[i] as Control
        if slot_control == null:
            continue
        var circle_panel := slot_control.get_node_or_null("Circle")
        if circle_panel == null:
            continue
        var circle := circle_panel as Panel
        if circle == null:
            continue
        var color_name := String(COLOR_PRESET[i]["name"])
        var style: StyleBox
        if COLOR_TEXTURES.has(color_name):
            var texture_style := StyleBoxTexture.new()
            texture_style.texture = COLOR_TEXTURES[color_name]
            texture_style.draw_center = true
            style = texture_style
        else:
            var flat_style := StyleBoxFlat.new()
            flat_style.bg_color = COLOR_PRESET[i]["color"]
            var initial_radius := int(round(INACTIVE_SIZE * 0.5))
            _set_flat_style_radius(flat_style, initial_radius)
            style = flat_style
        circle.add_theme_stylebox_override("panel", style)
        circle.modulate = Color(1, 1, 1, INACTIVE_ALPHA)
        _slot_nodes[color_name] = slot_control
        _circle_nodes[color_name] = circle
        _circle_styles[color_name] = style
        _apply_slot_style(slot_control, circle, style, false)

func _connect_to_color_source() -> void:
    if _source_node and is_instance_valid(_source_node):
        if _source_node.has_signal("color_changed") and _source_node.color_changed.is_connected(_on_color_changed):
            _source_node.color_changed.disconnect(_on_color_changed)
    _source_node = null

    var source := get_tree().get_first_node_in_group("paint_color_source")
    if source == null:
        return
    if source.has_signal("color_changed"):
        if not source.color_changed.is_connected(_on_color_changed):
            source.color_changed.connect(_on_color_changed)
    if source.has_method("get_current_color_info"):
        var info: Dictionary = source.get_current_color_info()
        if info.has("color") and info.has("name"):
            _on_color_changed(info["color"], info["name"])
    _source_node = source

func _on_node_added(node: Node) -> void:
    if node.is_in_group("paint_color_source"):
        _connect_to_color_source()

func _exit_tree() -> void:
    if _source_node and is_instance_valid(_source_node):
        if _source_node.has_signal("color_changed") and _source_node.color_changed.is_connected(_on_color_changed):
            _source_node.color_changed.disconnect(_on_color_changed)
    if get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.disconnect(_on_node_added)

func _on_color_changed(_color: Color, color_name: String) -> void:
    for preset in COLOR_PRESET:
        var color_name_key := String(preset["name"])
        var slot := _slot_nodes.get(color_name_key) as Control
        var circle := _circle_nodes.get(color_name_key) as Panel
        if slot == null or circle == null:
            continue
        var is_active := color_name_key == color_name
        circle.modulate = Color(1, 1, 1, ACTIVE_ALPHA if is_active else INACTIVE_ALPHA)
        var style: StyleBox = _circle_styles.get(color_name_key) as StyleBox
        if style is StyleBoxFlat:
            (style as StyleBoxFlat).bg_color = preset["color"]
        _apply_slot_style(slot, circle, style, is_active)
    _palette.queue_sort()

func _apply_slot_style(slot: Control, circle: Panel, style: StyleBox, is_active: bool) -> void:
    var circle_size := ACTIVE_SIZE if is_active else INACTIVE_SIZE
    slot.custom_minimum_size = Vector2(circle_size, circle_size)
    slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    circle.custom_minimum_size = Vector2(circle_size, circle_size)
    if style is StyleBoxFlat:
        var radius := int(round(circle_size * 0.5))
        _set_flat_style_radius(style, radius)

func _set_flat_style_radius(style: StyleBox, radius: int) -> void:
    if style == null or not (style is StyleBoxFlat):
        return
    var flat_style := style as StyleBoxFlat
    flat_style.corner_radius_top_left = radius
    flat_style.corner_radius_top_right = radius
    flat_style.corner_radius_bottom_right = radius
    flat_style.corner_radius_bottom_left = radius
