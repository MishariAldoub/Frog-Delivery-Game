extends CanvasLayer

signal restart_requested

var pizza_label: Label
var distance_label: Label
var complete_label: Label

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(270, 86)
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	pizza_label = Label.new()
	pizza_label.text = "Pizzas Remaining: 0"
	pizza_label.add_theme_font_size_override("font_size", 24)
	box.add_child(pizza_label)

	distance_label = Label.new()
	distance_label.text = "Distance: 0 m"
	distance_label.add_theme_font_size_override("font_size", 20)
	box.add_child(distance_label)

	var hint := Label.new()
	hint.text = "W/S drive  |  A/D lean  |  Mouse hold: tongue"
	hint.add_theme_font_size_override("font_size", 13)
	box.add_child(hint)

	var restart := Button.new()
	restart.text = "Restart"
	restart.position = Vector2(16, 112)
	restart.custom_minimum_size = Vector2(120, 42)
	restart.pressed.connect(func() -> void: restart_requested.emit())
	root.add_child(restart)

	complete_label = Label.new()
	complete_label.visible = false
	complete_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	complete_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	complete_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	complete_label.add_theme_font_size_override("font_size", 42)
	root.add_child(complete_label)

func set_run_status(count: int, distance: float) -> void:
	if pizza_label:
		pizza_label.text = "Pizzas Remaining: %d" % count
	if distance_label:
		distance_label.text = "Distance: %d m" % int(distance / 10.0)

func show_complete(count: int, total: int) -> void:
	complete_label.text = "Level Complete\nPizzas delivered: %d / %d" % [count, total]
	complete_label.visible = true
