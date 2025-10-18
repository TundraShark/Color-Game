extends Node2D

@export var brush_size: float = 24.0
@export var background_color: Color = Color.WHITE
@export var canvas_size: Vector2 = Vector2(1024, 576)
@export var submit_url: String = "https://tundra.ngrok.io/submit-art"
@export var uploader_path: NodePath

var _current_color: Color = Color.BLACK
var _drawing: bool = false
var _previous_position: Vector2

var _image: Image
var _texture: ImageTexture
var _canvas_rect := Rect2(Vector2.ZERO, Vector2.ZERO)
var _uploader: HTTPRequest
var _is_submitting: bool = false

func _ready() -> void:
    _initialize_canvas()
    _resolve_uploader()
    queue_redraw()

func _resolve_uploader() -> void:
    if uploader_path != NodePath():
        _uploader = get_node_or_null(uploader_path) as HTTPRequest
    if _uploader == null:
        var parent := get_parent()
        while parent and _uploader == null:
            _uploader = parent.get_node_or_null("Uploader") as HTTPRequest
            parent = parent.get_parent()
    if _uploader == null:
        var current := get_tree().current_scene
        if current:
            _uploader = current.get_node_or_null("Uploader") as HTTPRequest
    if _uploader and not _uploader.request_completed.is_connected(_on_submit_completed):
        _uploader.request_completed.connect(_on_submit_completed)

func _initialize_canvas() -> void:
    var width: int = int(canvas_size.x)
    var height: int = int(canvas_size.y)
    _image = Image.create(width, height, false, Image.FORMAT_RGBA8)
    _image.fill(background_color)
    _texture = ImageTexture.create_from_image(_image)
    _canvas_rect = Rect2(Vector2.ZERO, Vector2(width, height))

func set_color(color: Color) -> void:
    _current_color = color

func set_brush_size(size: float) -> void:
    brush_size = clampf(size, 1.0, 256.0)

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            var local_pos: Vector2 = get_local_mouse_position()
            if _canvas_rect.has_point(local_pos):
                _drawing = true
                _previous_position = local_pos
                _draw_circle(_previous_position)
                queue_redraw()
        else:
            _drawing = false
    elif event is InputEventMouseMotion and _drawing:
        var position: Vector2 = get_local_mouse_position()
        _draw_line(_previous_position, position)
        _previous_position = position
        queue_redraw()

func _draw() -> void:
    if _texture:
        draw_texture(_texture, Vector2.ZERO)

func clear_canvas() -> void:
    _image.fill(background_color)
    _texture.update(_image)
    queue_redraw()

func submit_canvas() -> void:
    if _uploader == null:
        _resolve_uploader()
    if _uploader == null:
        push_warning("Uploader node not found; cannot submit art.")
        return
    if _is_submitting:
        push_warning("Upload already in progress.")
        return
    if submit_url.is_empty():
        push_warning("Submit URL is empty; cannot upload.")
        return
    var png_image: Image = _image.duplicate()
    var png_data: PackedByteArray = png_image.save_png_to_buffer()
    if png_data.is_empty():
        push_warning("Failed to encode image to PNG.")
        return
    var headers := PackedStringArray(["Content-Type: image/png"])
    var err := _uploader.request_raw(submit_url, headers, HTTPClient.METHOD_POST, png_data)
    if err != OK:
        push_warning("Failed to submit art. Error code: %s" % err)
        return
    _is_submitting = true

func _on_submit_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
    _is_submitting = false
    if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
        push_warning("Art submission failed (HTTP %s)." % response_code)
        return
    print("Art submitted successfully (HTTP %s)." % response_code)

func _draw_circle(position: Vector2) -> void:
    if _image == null:
        return
    var clamped: Vector2 = position.clamp(_canvas_rect.position, _canvas_rect.end)
    var center: Vector2 = clamped.round()
    _stamp_brush(center)
    _texture.update(_image)

func _stamp_brush(center: Vector2) -> void:
    var radius: int = int(max(brush_size * 0.5, 1.0))
    for x in range(center.x - radius, center.x + radius + 1):
        for y in range(center.y - radius, center.y + radius + 1):
            if (Vector2(x, y) - center).length() <= radius:
                if x >= 0 and x < _image.get_width() and y >= 0 and y < _image.get_height():
                    _image.set_pixel(x, y, _current_color)

func _draw_line(from_point: Vector2, to_point: Vector2) -> void:
    if _image == null:
        return
    var start: Vector2 = from_point.clamp(_canvas_rect.position, _canvas_rect.end).round()
    var end: Vector2 = to_point.clamp(_canvas_rect.position, _canvas_rect.end).round()
    var delta: Vector2 = end - start
    var distance: float = delta.length()
    if distance < 1.0:
        _stamp_brush(start)
        _texture.update(_image)
        return
    var step: float = max(brush_size * 0.5, 1.0)
    var steps: int = int(ceil(distance / step))
    for i in range(steps + 1):
        var t: float = float(i) / float(max(steps, 1))
        var point: Vector2 = start.lerp(end, t)
        _stamp_brush(point.round())
    _texture.update(_image)
