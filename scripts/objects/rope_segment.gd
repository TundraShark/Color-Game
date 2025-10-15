extends RigidBody2D

@export var segment_mass: float = 0.5
@export var linear_damp_override: float = 4.5
@export var angular_damp_override: float = 6.0

func _ready() -> void:
    mass = clamp(segment_mass, 0.05, 5.0)
    linear_damp = linear_damp_override
    angular_damp = angular_damp_override
    if physics_material_override == null:
        physics_material_override = PhysicsMaterial.new()
    physics_material_override.friction = 0.4
    physics_material_override.bounce = 0.0
