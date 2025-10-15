extends CPUParticles2D

@export var extra_free_delay := 0.4

func _ready() -> void:
    emitting = true
    if one_shot:
        var total_time: float = maxf(lifetime, 0.1) + preprocess + extra_free_delay
        var timer := get_tree().create_timer(total_time)
        timer.timeout.connect(queue_free)
    else:
        var timer := get_tree().create_timer(extra_free_delay)
        timer.timeout.connect(queue_free)
