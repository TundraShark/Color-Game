extends RigidBody2D

const STICK_MODE := RigidBody2D.FREEZE_MODE_STATIC

func _ready() -> void:
    contact_monitor = true
    max_contacts_reported = 4
    gravity_scale = 1.2
    connect("body_entered", Callable(self, "_stick_to_surface"))

func _stick_to_surface(_other: Node) -> void:
    if freeze_mode == STICK_MODE and freeze:
        return
    linear_velocity = Vector2.ZERO
    angular_velocity = 0.0
    freeze_mode = STICK_MODE
    freeze = true
    sleeping = true
