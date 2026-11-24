class_name TerrainMinimap
extends RefCounted

## Renders a top-down preview: dominant splat color shaded by the heightmap
## normal (cheap hillshade).

const LAYER_COLORS := [
	Color(0.35, 0.5, 0.2), # grass
	Color(0.45, 0.43, 0.4), # rock
	Color(0.9, 0.92, 0.95), # snow
	Color(0.75, 0.65, 0.45), # sand
	Color(0.5, 0.35, 0.18), # dirt
	Color(0.32, 0.24, 0.15), # mud
	Color(0.7, 0.7, 0.68), # gravel
	Color(0.16, 0.4, 0.12), # moss
]

static var _light := Vector3(0.35, 1.0, 0.25).normalized()


static func render(hm: Heightmap, splat: Image, splat2: Image) -> Image:
	var img := Image.create(hm.size, hm.size, false, Image.FORMAT_RGB8)
	for z in hm.size:
		for x in hm.size:
			var s1 := splat.get_pixel(x, z)
			var s2 := splat2.get_pixel(x, z)
			var n := _normal(hm, x, z)
			var c := LAYER_COLORS[0] * s1.r + LAYER_COLORS[1] * s1.g + LAYER_COLORS[2] * s1.b + LAYER_COLORS[3] * s1.a
			c += LAYER_COLORS[4] * s2.r + LAYER_COLORS[5] * s2.g + LAYER_COLORS[6] * s2.b + LAYER_COLORS[7] * s2.a
			var shade := clampf(n.dot(_light), 0.0, 1.0) * 0.7 + 0.3
			img.set_pixel(x, z, Color(c.r * shade, c.g * shade, c.b * shade))
	return img


static func _normal(hm: Heightmap, x: int, z: int) -> Vector3:
	var s := hm.size
	var hl := hm.get_height(maxi(x - 1, 0), z)
	var hr := hm.get_height(mini(x + 1, s - 1), z)
	var hd := hm.get_height(x, maxi(z - 1, 0))
	var hu := hm.get_height(x, mini(z + 1, s - 1))
	return Vector3(hl - hr, 2.0 * hm.spacing(), hd - hu).normalized()
