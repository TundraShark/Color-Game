extends Node2D

@export var pulse_duration: float = 2.5
@export var pulse_duration_randomness: float = 0.3
@export var pulse_hold_time: float = 0.15
@export var pulse_hold_randomness: float = 0.3
@export_range(0.0, 1.0, 0.01) var fill_min_y: float = 0.9
@export_range(0.0, 1.0, 0.01) var fill_max_y: float = 1.0
@export var energy_variation: float = 0.8
@export var texture_scale_variation: float = 0.12
@export var color_shift_strength: float = 0.08
@export var flicker_min_duration: float = 0.8
@export var flicker_max_duration: float = 1.6
@export_range(0.0, 1.0, 0.01) var blackout_chance: float = 0.15
@export var blackout_fade_min: float = 0.08
@export var blackout_fade_max: float = 0.18
@export var blackout_hold_min: float = 0.0
@export var blackout_hold_max: float = 0.04

var _light: PointLight2D
var _gradient_texture: GradientTexture2D
var _pulse_tween: Tween
var _flicker_tween: Tween
var _blackout_tween: Tween
var _fill_to_y_internal: float = 0.0
var _base_energy: float = 0.0
var _base_texture_scale: float = 1.0
var _base_color: Color = Color.WHITE
var _rng := RandomNumberGenerator.new()
var _pulse_direction_up: bool = true
var _is_blackout_active: bool = false
var fill_to_y: float = fill_min_y:
    set(value):
        var clamped: float = clamp(value, fill_min_y, fill_max_y)
        _fill_to_y_internal = clamped
        if _gradient_texture:
            var target: Vector2 = _gradient_texture.fill_to
            target.x = 0.5
            target.y = _fill_to_y_internal
            _gradient_texture.fill_to = target
    get:
        return _fill_to_y_internal

func _ready() -> void:
    _light = $Glow
    if _light == null:
        return
    _rng.randomize()
    if _light.texture is GradientTexture2D:
        _gradient_texture = (_light.texture as GradientTexture2D).duplicate(true)
        _gradient_texture.fill_to = Vector2(0.5, fill_min_y)
        _light.texture = _gradient_texture
    else:
        _gradient_texture = GradientTexture2D.new()
        _gradient_texture.fill_to = Vector2(0.5, fill_min_y)
        _light.texture = _gradient_texture
    _base_energy = _light.energy
    _base_texture_scale = _light.texture_scale
    _base_color = _light.color
    _fill_to_y_internal = fill_min_y
    fill_to_y = fill_min_y
    _start_pulse()
    _start_flicker()

func _start_pulse() -> void:
    if _pulse_tween:
        _pulse_tween.kill()
    _pulse_direction_up = true
    _queue_next_pulse_segment()

func _queue_next_pulse_segment() -> void:
    if _pulse_tween:
        _pulse_tween.kill()
    var duration_variation: float = clamp(pulse_duration_randomness, 0.0, 0.95)
    var duration_scale: float = 1.0 + _rng.randf_range(-duration_variation, duration_variation)
    var target_duration: float = max(pulse_duration * duration_scale, 0.05)
    var hold_variation: float = clamp(pulse_hold_randomness, 0.0, 0.95)
    var hold_scale: float = 1.0 + _rng.randf_range(-hold_variation, hold_variation)
    var target_hold: float = max(pulse_hold_time * hold_scale, 0.0)
    var direction_target: float = fill_max_y if _pulse_direction_up else fill_min_y
    _pulse_tween = create_tween()
    if _pulse_tween == null:
        return
    _pulse_tween.tween_property(self, "fill_to_y", direction_target, target_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    if target_hold > 0.0:
        _pulse_tween.tween_interval(target_hold)
    _pulse_direction_up = not _pulse_direction_up
    _pulse_tween.tween_callback(Callable(self, "_queue_next_pulse_segment"))

func _start_flicker() -> void:
    if _light == null:
        return
    _schedule_next_flicker()

func _schedule_next_flicker() -> void:
    if _light == null:
        return
    if flicker_max_duration < flicker_min_duration:
        var temp := flicker_min_duration
        flicker_min_duration = flicker_max_duration
        flicker_max_duration = temp
    if _flicker_tween:
        _flicker_tween.kill()
        _flicker_tween = null
    if _blackout_tween:
        _blackout_tween.kill()
        _blackout_tween = null
    if not _is_blackout_active:
        var chance: float = clamp(blackout_chance, 0.0, 1.0)
        if chance > 0.0 and _rng.randf() <= chance:
            _start_blackout()
            return
    var duration: float = _rng.randf_range(flicker_min_duration, flicker_max_duration)
    var target_energy: float = _base_energy + _rng.randf_range(-energy_variation, energy_variation)
    var target_scale: float = clamp(_base_texture_scale + _rng.randf_range(-texture_scale_variation, texture_scale_variation), 0.1, 8.0)
    var color_mix_amount: float = clamp(0.5 + _rng.randf_range(-color_shift_strength, color_shift_strength), 0.0, 1.0)
    var warm_color: Color = Color(_base_color.r, _base_color.g * 0.9, _base_color.b * 0.8, _base_color.a)
    var target_color: Color = _base_color.lerp(warm_color, color_mix_amount)
    _flicker_tween = create_tween()
    if _flicker_tween == null:
        return
    _flicker_tween.tween_property(_light, "energy", target_energy, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    _flicker_tween.parallel().tween_property(_light, "texture_scale", target_scale, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    _flicker_tween.parallel().tween_property(_light, "color", target_color, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    _flicker_tween.tween_callback(Callable(self, "_schedule_next_flicker"))

func _start_blackout() -> void:
    if _light == null:
        return
    if _blackout_tween:
        _blackout_tween.kill()
    if _flicker_tween:
        _flicker_tween.kill()
        _flicker_tween = null
    _is_blackout_active = true
    var fade_out: float = max(_rng.randf_range(min(blackout_fade_min, blackout_fade_max), max(blackout_fade_min, blackout_fade_max)), 0.01)
    var fade_in: float = max(_rng.randf_range(min(blackout_fade_min, blackout_fade_max), max(blackout_fade_min, blackout_fade_max)), 0.01)
    var hold_duration: float = max(_rng.randf_range(min(blackout_hold_min, blackout_hold_max), max(blackout_hold_min, blackout_hold_max)), 0.0)
    var dim_energy: float = max(_base_energy * 0.75, 0.05)
    var dim_color: Color = _light.color
    dim_color.a = max(dim_color.a * 0.75, 0.05)
    var restore_energy: float = _light.energy
    var restore_scale: float = _light.texture_scale
    var restore_color: Color = _light.color
    _blackout_tween = create_tween()
    if _blackout_tween == null:
        _is_blackout_active = false
        _schedule_next_flicker()
        return
    _blackout_tween.tween_property(_light, "energy", dim_energy, fade_out).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    _blackout_tween.parallel().tween_property(_light, "color", dim_color, fade_out).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    if hold_duration > 0.0:
        _blackout_tween.tween_interval(hold_duration)
    _blackout_tween.tween_property(_light, "energy", restore_energy, fade_in).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    _blackout_tween.parallel().tween_property(_light, "texture_scale", restore_scale, fade_in).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    _blackout_tween.parallel().tween_property(_light, "color", restore_color, fade_in).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    _blackout_tween.tween_callback(Callable(self, "_finish_blackout"))

func _finish_blackout() -> void:
    _is_blackout_active = false
    _blackout_tween = null
    _schedule_next_flicker()
