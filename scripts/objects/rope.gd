extends Node2D

@export var segment_scene: PackedScene = preload("res://scenes/objects/rope_segment.tscn")
@export_range(1, 64) var segment_count: int = 12
@export var segment_spacing: float = 16.0
@export var rebuild_on_ready: bool = true
@export var attach_bottom_anchor: bool = false
@export var joint_stiffness: float = 600.0
@export var joint_damping: float = 30.0
@export var enable_joint_contacts: bool = true
@export var rope_collision_layer: int = 4
@export var rope_collision_mask: int = 5

var _segments: Array[RigidBody2D] = []
var _joints: Array[DampedSpringJoint2D] = []

@onready var _top_anchor: StaticBody2D = get_node("TopAnchor")
@onready var _bottom_anchor: StaticBody2D = get_node("BottomAnchor")

func _ready() -> void:
    if rebuild_on_ready:
        call_deferred("build_rope")

func clear_rope() -> void:
    for joint in _joints:
        if is_instance_valid(joint):
            joint.queue_free()
    _joints.clear()
    for segment in _segments:
        if is_instance_valid(segment):
            segment.queue_free()
    _segments.clear()

func build_rope() -> void:
    clear_rope()
    if segment_scene == null:
        push_warning("segment_scene is not assigned for rope")
        return
    var previous_body: PhysicsBody2D = _top_anchor
    var local_offset := Vector2(0, segment_spacing)
    for i in range(segment_count):
        var segment_instance := segment_scene.instantiate()
        if segment_instance is not RigidBody2D:
            segment_instance.queue_free()
            push_warning("Rope segment scene must be a RigidBody2D")
            return
        var rigid_segment := segment_instance as RigidBody2D
        rigid_segment.position = local_offset * float(i + 1)
        rigid_segment.collision_layer = rope_collision_layer
        rigid_segment.collision_mask = rope_collision_mask
        rigid_segment.contact_monitor = true
        rigid_segment.max_contacts_reported = 4
        add_child(rigid_segment)
        _segments.append(rigid_segment)

        var joint := DampedSpringJoint2D.new()
        joint.rest_length = segment_spacing
        joint.length = segment_spacing
        joint.stiffness = joint_stiffness
        joint.damping = joint_damping
        joint.node_a = previous_body.get_path()
        joint.node_b = rigid_segment.get_path()
        add_child(joint)
        _joints.append(joint)

        previous_body = rigid_segment

    if attach_bottom_anchor and is_instance_valid(_bottom_anchor):
        _bottom_anchor.position = local_offset * float(segment_count + 1)
        var tail_joint := DampedSpringJoint2D.new()
        tail_joint.rest_length = segment_spacing
        tail_joint.length = segment_spacing
        tail_joint.stiffness = joint_stiffness
        tail_joint.damping = joint_damping
        tail_joint.node_a = previous_body.get_path()
        tail_joint.node_b = _bottom_anchor.get_path()
        add_child(tail_joint)
        _joints.append(tail_joint)
        _bottom_anchor.visible = true
        if _bottom_anchor.has_node("CollisionShape2D"):
            var shape_node := _bottom_anchor.get_node("CollisionShape2D")
            if shape_node is CollisionShape2D:
                shape_node.disabled = false
    else:
        if is_instance_valid(_bottom_anchor):
            _bottom_anchor.visible = false
            if _bottom_anchor.has_node("CollisionShape2D"):
                var shape_node := _bottom_anchor.get_node("CollisionShape2D")
                if shape_node is CollisionShape2D:
                    shape_node.disabled = true

func get_segments() -> Array[RigidBody2D]:
    return _segments.duplicate()

func get_joints() -> Array[DampedSpringJoint2D]:
    return _joints.duplicate()
