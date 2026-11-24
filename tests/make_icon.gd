extends SceneTree

## Generates icon.png: stylized mountains for the project/Asset Library icon.
## Run: godot --headless -s tests/make_icon.gd


func _init() -> void:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	# sky gradient
	for y in 128:
		for x in 128:
			img.set_pixel(x, y, Color(0.16, 0.30, 0.52).lerp(Color(0.62, 0.80, 0.95), y / 96.0))
	# back mountain (darker, right)
	_mountain(img, 84, 46, 118, 58, Color(0.30, 0.29, 0.27), Color(0.75, 0.80, 0.88))
	# front mountain (lighter, left)
	_mountain(img, 44, 30, 122, 66, Color(0.40, 0.37, 0.33), Color(0.92, 0.95, 1.0))
	# grassy ground
	for y in range(96, 128):
		for x in 128:
			if img.get_pixel(x, y) == Color(0.40, 0.37, 0.33) or img.get_pixel(x, y) == Color(0.30, 0.29, 0.27):
				continue
			img.set_pixel(x, y, Color(0.25, 0.45, 0.16).lerp(Color(0.35, 0.55, 0.20), (y - 96) / 32.0))
	img.save_png("res://icon.png")
	print("icon.png written")
	quit()


func _mountain(img: Image, ax: int, ay: int, base_y: int, half_w: int, rock: Color, snow: Color) -> void:
	for y in range(ay, base_y + 1):
		var t := float(y - ay) / float(base_y - ay)
		var w := half_w * t
		for x in range(int(ax - w), int(ax + w) + 1):
			if x < 0 or x >= 128:
				continue
			img.set_pixel(x, y, snow if t < 0.28 else rock)
