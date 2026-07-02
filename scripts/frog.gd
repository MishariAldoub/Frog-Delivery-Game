extends Node2D

func _draw() -> void:
	draw_circle(Vector2(0, 0), 24.0, Color("#60bf54"))
	draw_circle(Vector2(-12, -18), 9.0, Color("#76d66d"))
	draw_circle(Vector2(12, -18), 9.0, Color("#76d66d"))
	draw_circle(Vector2(-12, -19), 4.0, Color.BLACK)
	draw_circle(Vector2(12, -19), 4.0, Color.BLACK)
	draw_arc(Vector2(0, 6), 11.0, 0.2, 2.9, 16, Color("#1d4d28"), 2.0)
	draw_line(Vector2(-18, 16), Vector2(-34, 32), Color("#348c40"), 6.0)
	draw_line(Vector2(16, 16), Vector2(31, 32), Color("#348c40"), 6.0)
