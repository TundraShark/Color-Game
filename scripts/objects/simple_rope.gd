extends StaticBody2D

var is_player_touching: bool = false
var touching_player: CharacterBody2D = null

func _ready() -> void:
    # Connect to area entered/exited for player interaction
    var area = get_node_or_null("Area2D")
    if area:
        area.body_entered.connect(_on_body_entered)
        area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
    if body is CharacterBody2D:
        is_player_touching = true
        touching_player = body as CharacterBody2D

        # Try to attach player to this rope
        if touching_player and touching_player.has_method("attach_to_rope"):
            touching_player.attach_to_rope(self)

func _on_body_exited(body: Node) -> void:
    if body == touching_player:
        is_player_touching = false
        touching_player = null

        # Detach player from rope
        if body and body.has_method("detach_from_rope"):
            body.detach_from_rope()
