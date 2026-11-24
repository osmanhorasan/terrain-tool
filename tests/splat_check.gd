extends SceneTree

## Checks whether paint ops can produce all-zero splat pixels (=> black albedo).

func _init() -> void:
	var hm := Heightmap.create(257, 128.0)
	var splat := Image.create(257, 257, false, Image.FORMAT_RGBA8)
	splat.fill(Color(1, 0, 0, 0))
	var brush := TerrainBrush.new()
	brush.radius = 10.0
	var rng := RandomNumberGenerator.new()
	for i in 300:
		var c := Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
		TerrainOps.paint(splat, hm, c, brush, rng.randi_range(0, 3), 0.05)
	var bad := 0
	var min_sum := 1.0
	for z in 257:
		for x in 257:
			var p := splat.get_pixel(x, z)
			var s := p.r + p.g + p.b + p.a
			if s < 0.5:
				bad += 1
			min_sum = minf(min_sum, s)
	print("bad pixels: %d  min_sum: %.3f" % [bad, min_sum])
	quit()
