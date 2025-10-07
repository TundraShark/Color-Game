extends Node2D

@export var paint_blob_scene: PackedScene
@export var fire_interval := 0.07
@export var muzzle_offset := Vector2(24, 0)
@export var projectile_speed := 750.0

var _cooldown := 0.0

func _ready() -> void:
    if paint_blob_scene == null:
        push_warning("Arm has no paint_blob_scene assigned")

func _process(delta: float) -> void:
    var target := get_global_mouse_position()
    look_at(target)
    _cooldown = maxf(_cooldown - delta, 0.0)

    if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        _fire()

func _fire() -> void:
    if _cooldown > 0.0 or paint_blob_scene == null:
        return

    var muzzle_global := global_position + (global_transform.x * muzzle_offset.x) + (global_transform.y * muzzle_offset.y)
    var paint_blob := paint_blob_scene.instantiate()
    paint_blob.global_position = muzzle_global
    var direction := (get_global_mouse_position() - muzzle_global).normalized()
    var impulse := direction * projectile_speed
    if paint_blob.has_method("apply_impulse"):
        paint_blob.apply_impulse(impulse)
    paint_blob.linear_velocity = impulse

    get_tree().root.add_child(paint_blob)
    _cooldown = fire_interval
