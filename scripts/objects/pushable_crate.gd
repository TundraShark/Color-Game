extends RigidBody2D

@export var weight: float = 3.0
@export var friction: float = 0.6
@export var bounce: float = 0.0
@export var linear_damp_override: float = 0.05
@export var angular_damp_override: float = 4.0
@export var allow_sleep: bool = false

func _ready() -> void:
    mass = clamp(weight, 0.1, 25.0)
    if physics_material_override == null:
        physics_material_override = PhysicsMaterial.new()
    physics_material_override.friction = friction
    physics_material_override.bounce = bounce
    physics_material_override.rough = false
    linear_damp = max(linear_damp_override, 0.0)
    angular_damp = max(angular_damp_override, 0.0)
    can_sleep = allow_sleep
    if not allow_sleep:
        sleeping = false
