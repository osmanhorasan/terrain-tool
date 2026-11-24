class_name Heightmap
extends RefCounted

## Float heightmap backed by an Image (FORMAT_RF).
## Map coords are [0, size). World space is centered on the origin, Y-up.

var size: int
var world_size: float
var image: Image


static func create(p_size: int, p_world_size: float) -> Heightmap:
	var hm := Heightmap.new()
	hm.size = p_size
	hm.world_size = p_world_size
	hm.image = Image.create(p_size, p_size, false, Image.FORMAT_RF)
	hm.image.fill(Color(0.0, 0.0, 0.0))
	return hm


static func from_image(img: Image, p_world_size: float) -> Heightmap:
	var hm := Heightmap.new()
	hm.image = img.duplicate()
	if hm.image.get_format() != Image.FORMAT_RF:
		hm.image.convert(Image.FORMAT_RF)
	hm.size = img.get_width()
	hm.world_size = p_world_size
	return hm


func spacing() -> float:
	return world_size / float(size - 1)


func get_height(x: int, z: int) -> float:
	return image.get_pixel(x, z).r


func set_height(x: int, z: int, v: float) -> void:
	image.set_pixel(x, z, Color(v, 0.0, 0.0))


## Central-difference normal at integer map coords.
func normal_at(x: int, z: int) -> Vector3:
	var s := size
	var hl := get_height(maxi(x - 1, 0), z)
	var hr := get_height(mini(x + 1, s - 1), z)
	var hd := get_height(x, maxi(z - 1, 0))
	var hu := get_height(x, mini(z + 1, s - 1))
	return Vector3(hl - hr, 2.0 * spacing(), hd - hu).normalized()


func slope_deg(m: Vector2) -> float:
	return rad_to_deg(acos(clampf(normal_at(int(m.x), int(m.y)).y, -1.0, 1.0)))


func max_height() -> float:
	var m := -INF
	for z in size:
		for x in size:
			m = maxf(m, image.get_pixel(x, z).r)
	return m


func map_to_world(x: int, z: int) -> Vector3:
	var half := world_size * 0.5
	return Vector3(x * spacing() - half, get_height(x, z), z * spacing() - half)


func world_to_map_f(wx: float, wz: float) -> Vector2:
	var half := world_size * 0.5
	return Vector2((wx + half) / spacing(), (wz + half) / spacing())


func in_bounds_f(m: Vector2) -> bool:
	return m.x >= 0.0 and m.y >= 0.0 and m.x < float(size) and m.y < float(size)


## Bilinear height sample at fractional map coords.
func sample_height(m: Vector2) -> float:
	m.x = clampf(m.x, 0.0, size - 1.001)
	m.y = clampf(m.y, 0.0, size - 1.001)
	var x0 := int(m.x)
	var z0 := int(m.y)
	var x1 := mini(x0 + 1, size - 1)
	var z1 := mini(z0 + 1, size - 1)
	var fx := m.x - x0
	var fz := m.y - z0
	var h00 := get_height(x0, z0)
	var h10 := get_height(x1, z0)
	var h01 := get_height(x0, z1)
	var h11 := get_height(x1, z1)
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


## Marches a world-space ray along the heightfield.
## Returns the hit position, or (INF, INF, INF) on miss.
func raycast(origin: Vector3, dir: Vector3, max_dist := 2000.0) -> Vector3:
	var t := 0.0
	var prev_t := 0.0
	var step := spacing() * 0.9
	while t < max_dist:
		var p := origin + dir * t
		var m := world_to_map_f(p.x, p.z)
		if in_bounds_f(m) and p.y <= sample_height(m):
			var lo := prev_t
			var hi := t
			for i in 14:
				var mid := (lo + hi) * 0.5
				var pm := origin + dir * mid
				var mm := world_to_map_f(pm.x, pm.z)
				if in_bounds_f(mm) and pm.y <= sample_height(mm):
					hi = mid
				else:
					lo = mid
			return origin + dir * hi
		prev_t = t
		t += step
	return Vector3(INF, INF, INF)
