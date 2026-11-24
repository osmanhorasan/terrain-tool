class_name TerrainOps
extends RefCounted

## Stateless terrain editing operations.
## `center` is world-space XZ. Each op returns the dirty rect in map coords.

enum Mode { RAISE, LOWER, SMOOTH, FLATTEN, NOISE, PINCH, PAINT }

static var _noise := _make_noise()


static func _make_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = 1337
	n.frequency = 0.15
	n.fractal_octaves = 3
	return n


static func brush_rect(hm: Heightmap, center: Vector2, brush: TerrainBrush) -> Rect2i:
	var r := int(ceil(brush.radius / hm.spacing())) + 1
	var c := hm.world_to_map_f(center.x, center.y)
	var rect := Rect2i(int(floor(c.x)) - r, int(floor(c.y)) - r, 2 * r + 1, 2 * r + 1)
	return rect.intersection(Rect2i(0, 0, hm.size, hm.size))


## side: 0 = both directions, 1 = raise only, -1 = lower only.
static func sculpt(hm: Heightmap, center: Vector2, brush: TerrainBrush, mode: Mode, dt: float, flatten_target := 0.0, side := 0) -> Rect2i:
	var rect := brush_rect(hm, center, brush)
	if rect.size.x <= 0:
		return rect
	var c := hm.world_to_map_f(center.x, center.y)
	var sp := hm.spacing()
	var amount := dt * 6.0
	for z in rect.size.y:
		for x in rect.size.x:
			var mx: int = rect.position.x + x
			var mz: int = rect.position.y + z
			var w := brush.weight(Vector2(mx - c.x, mz - c.y).length() * sp)
			if w <= 0.0:
				continue
			var orig := hm.get_height(mx, mz)
			var h := orig
			match mode:
				Mode.RAISE:
					h += w * amount
				Mode.LOWER:
					h -= w * amount
				Mode.SMOOTH:
					h = lerpf(h, _neighbor_avg(hm, mx, mz), w * amount)
				Mode.FLATTEN:
					h = lerpf(h, flatten_target, w * amount)
				Mode.NOISE:
					h += w * amount * _noise.get_noise_2d(mx, mz) * 3.0
				Mode.PINCH:
					var out_dir := Vector2(mx - c.x, mz - c.y)
					if out_dir.length() > 0.001:
						h = hm.sample_height(Vector2(mx, mz) + out_dir.normalized() * w * amount * 4.0)
			if side == 1:
				h = maxf(orig, h)
			elif side == -1:
				h = minf(orig, h)
			hm.set_height(mx, mz, h)
	return rect


## `splats` holds the two splatmap images; `layer` is 0..7.
static func paint(splats: Array, hm: Heightmap, center: Vector2, brush: TerrainBrush, layer: int, dt: float) -> Rect2i:
	var splat: Image = splats[layer / 4]
	var channel := layer % 4
	var rect := brush_rect(hm, center, brush)
	if rect.size.x <= 0:
		return rect
	var c := hm.world_to_map_f(center.x, center.y)
	var sp := hm.spacing()
	var amount := dt * 3.0
	for z in rect.size.y:
		for x in rect.size.x:
			var mx: int = rect.position.x + x
			var mz: int = rect.position.y + z
			var w := brush.weight(Vector2(mx - c.x, mz - c.y).length() * sp)
			if w <= 0.0:
				continue
			var px := splat.get_pixel(mx, mz)
			var v := [px.r, px.g, px.b, px.a]
			var target := clampf(v[channel] + w * amount, 0.0, 1.0)
			var others_sum: float = 1.0 - v[channel]
			if others_sum > 0.0001:
				var k: float = (1.0 - target) / others_sum
				for i in 4:
					v[i] = target if i == channel else v[i] * k
			else:
				for i in 4:
					v[i] = target if i == channel else (1.0 - target) / 3.0
			splat.set_pixel(mx, mz, Color(v[0], v[1], v[2], v[3]))
	return rect


static func _neighbor_avg(hm: Heightmap, x: int, z: int) -> float:
	var s := 0.0
	var n := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var sx := x + dx
			var sz := z + dz
			if sx >= 0 and sz >= 0 and sx < hm.size and sz < hm.size:
				s += hm.get_height(sx, sz)
				n += 1
	return s / n
