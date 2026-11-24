class_name TerrainFilters
extends RefCounted

## Whole-map filters, Unity Terrain Tools style. Each is one undoable op.


## Quantizes heights into `steps` terraces with a smooth edge band.
static func terrace(hm: Heightmap, steps: int) -> void:
	var minv := INF
	var maxv := -INF
	for z in hm.size:
		for x in hm.size:
			var h := hm.get_height(x, z)
			minv = minf(minv, h)
			maxv = maxf(maxv, h)
	var range_ := maxf(maxv - minv, 0.001)
	var step := range_ / float(maxi(steps, 1))
	for z in hm.size:
		for x in hm.size:
			var h := hm.get_height(x, z)
			var q: float = (h - minv) / step
			var f: float = q - floor(q)
			var snapped: float = (floor(q) + smoothstep(0.3, 0.7, f)) * step + minv
			hm.set_height(x, z, lerpf(h, snapped, 0.9))


## Expands or compresses the height range around the mean.
static func contrast(hm: Heightmap, amount: float) -> void:
	var mean := 0.0
	for z in hm.size:
		for x in hm.size:
			mean += hm.get_height(x, z)
	mean /= hm.size * hm.size
	for z in hm.size:
		for x in hm.size:
			var h := hm.get_height(x, z)
			hm.set_height(x, z, mean + (h - mean) * (1.0 + amount))


## Sharpens peaks and deepens valleys: |deviation|^p around the mean.
static func sharpen(hm: Heightmap, amount: float) -> void:
	var mean := 0.0
	for z in hm.size:
		for x in hm.size:
			mean += hm.get_height(x, z)
	mean /= hm.size * hm.size
	var p := 1.0 + amount
	for z in hm.size:
		for x in hm.size:
			var h := hm.get_height(x, z)
			var d := h - mean
			hm.set_height(x, z, mean + signf(d) * pow(absf(d), p))


## Box-blur passes over the whole map.
static func smooth_all(hm: Heightmap, passes: int) -> void:
	var tmp := hm.image.duplicate()
	for p in passes:
		for z in hm.size:
			for x in hm.size:
				var s := 0.0
				var n := 0
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var sx := clampi(x + dx, 0, hm.size - 1)
						var sz := clampi(z + dz, 0, hm.size - 1)
						s += tmp.get_pixel(sx, sz).r
						n += 1
				hm.set_height(x, z, s / n)
		tmp.copy_from(hm.image)


## Applies a graded ramp between world points a and b: pixels within
## half_width of the segment are lerped toward the a->b height profile.
static func ramp(hm: Heightmap, a: Vector2, b: Vector2, half_width: float) -> void:
	var ab := b - a
	var ab_len := ab.length()
	if ab_len < 0.001:
		return
	var ha := hm.sample_height(hm.world_to_map_f(a.x, a.y))
	var hb := hm.sample_height(hm.world_to_map_f(b.x, b.y))
	var ab_n := ab / ab_len
	for z in hm.size:
		for x in hm.size:
			var w := hm.map_to_world(x, z)
			var p := Vector2(w.x, w.z) - a
			var t := clampf(p.dot(ab_n) / ab_len, 0.0, 1.0)
			var dist := absf(p.dot(Vector2(-ab_n.y, ab_n.x)))
			if dist >= half_width:
				continue
			var target := lerpf(ha, hb, t)
			var k := 1.0 - dist / half_width
			hm.set_height(x, z, lerpf(hm.get_height(x, z), target, smoothstep(0.0, 1.0, k)))
