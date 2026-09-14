class_name HumanNoise
extends RefCounted

static func emit_noise(source: Node, world_position: Vector2, loudness: float = 1.0, radius: float = 220.0, noise_type: StringName = &"generic") -> void:
	if not source or not source.is_inside_tree():
		return
	source.get_tree().call_group(
		"human_noise_listener",
		"hear_noise",
		world_position,
		loudness,
		radius,
		noise_type,
		source
	)
