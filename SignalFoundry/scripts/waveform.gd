extends Control

var preview: FoundryPreview

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var middle = size.y * 0.5
	for i in 5:
		var y = size.y * float(i) / 4.0
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.18, 0.22, 0.28, 0.5))
	for i in 17:
		var x = size.x * float(i) / 16.0
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.18, 0.22, 0.28, 0.4))
	if preview == null or not preview.active or preview.trace.size() < 2:
		draw_line(Vector2(0, middle), Vector2(size.x, middle), Color("536272"), 1.5)
		return
	var points = PackedVector2Array()
	for i in preview.trace.size():
		points.append(Vector2(float(i) / (preview.trace.size() - 1) * size.x, middle - preview.trace[i] * size.y * 2.5))
	draw_polyline(points, Color("7ce4bf"), 1.5, true)
