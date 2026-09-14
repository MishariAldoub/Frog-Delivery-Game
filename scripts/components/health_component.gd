extends Node
class_name HealthComponent

signal health_changed(current_health: float, max_health: float)
signal died

@export var max_health = 100.0:
	set(value):
		max_health = max(value, 1.0)
		current_health = clamp(current_health, 0.0, max_health)
		health_changed.emit(current_health, max_health)

var current_health = 100.0
var is_dead = false

func _ready() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)

func take_damage(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_health = clamp(current_health - amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		die()

func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_health = clamp(current_health + amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)

func die() -> void:
	if is_dead:
		return
	is_dead = true
	current_health = 0.0
	health_changed.emit(current_health, max_health)
	died.emit()
