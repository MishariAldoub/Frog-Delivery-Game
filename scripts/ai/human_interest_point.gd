extends Marker2D
class_name HumanInterestPoint

enum PointType {
	WORK,
	WANDER,
}

@export var point_type = PointType.WANDER
@export_range(-1, 1, 1) var facing_direction = 1
@export var work_duration_min = 4.0
@export var work_duration_max = 8.0
@export var idle_duration_min = 1.0
@export var idle_duration_max = 3.0

func _ready() -> void:
	add_to_group("human_interest_point")
