extends Control
## Schematic instrument output for fictional electronic components.
var kind: String = ""
var value: Variant

func configure(type: String, sample: Variant) -> void:
	kind = type
	value = sample
	custom_minimum_size = Vector2(104, 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color("#39473d"))
	draw_rect(r, Color("#718272"), false, 1.0)
	if kind == "component_texture":
		var paper := Color("#a7ada0")
		match value:
			"pore":
				for x: int in range(7):
					for y: int in range(3):
						draw_circle(Vector2(8 + x * (size.x - 16) / 7.0 + (y % 2) * 4, 6 + y * (size.y - 12) / 2.0), 1.8, paper)
			"parallel", "cross":
				for x: int in range(16):
					var px: float = 4 + x * (size.x - 8) / 16.0
					draw_line(Vector2(px, 4), Vector2(px, size.y - 4), paper, 1.2)
				if value == "cross":
					for y: int in range(4):
						var py: float = 5 + y * (size.y - 10) / 4.0
						draw_line(Vector2(4, py), Vector2(size.x - 4, py), paper, 1.0)
	elif kind == "component_damage":
		var width: float = size.x - 12
		draw_rect(Rect2(6, 13, width * 0.26, 9), Color("#788e73"))
		draw_rect(Rect2(6 + width * 0.26, 13, width * 0.40, 9), Color("#c4b16e"))
		draw_rect(Rect2(6 + width * 0.66, 13, width * 0.34, 9), Color("#ae6c60"))
		var needle: float = 6 + width * clampf(float(value), 0, 100) / 100.0
		draw_line(Vector2(needle, 6), Vector2(needle, 26), Color("#f0e6ce"), 2.0)
	elif kind == "component_mark":
		draw_string(get_theme_default_font(), Vector2(8, 22), str(value), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#d7d8aa"))
	elif kind == "component_function":
		var healthy: bool = (value is bool and value) or (value is String and value == "serviceable")
		var color: Color = Color("#83bd92") if healthy else (Color("#c4b16e") if value is String and value == "partial" else Color("#c28777"))
		draw_circle(size * 0.5, 7, color)
