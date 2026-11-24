class_name AutoMaterial
extends RefCounted

## Rule-based splatmap generation:
##   steep slope   -> rock
##   high altitude -> snow (only where not too steep)
##   low + flat    -> sand
##   remainder     -> grass


static func apply(hm: Heightmap, splat: Image, splat2: Image, snowline: float, rock_deg: float, sandline: float) -> void:
	splat2.fill(Color(0, 0, 0, 0))
	var rock_thresh := 1.0 - cos(deg_to_rad(rock_deg))
	for z in hm.size:
		for x in hm.size:
			var h := hm.get_height(x, z)
			var n := _normal(hm, x, z)
			var steep := 1.0 - n.y
			var snow := smoothstep(snowline - 3.0, snowline + 3.0, h)
			snow *= 1.0 - smoothstep(rock_thresh * 0.7, rock_thresh, steep)
			var rock := smoothstep(rock_thresh * 0.85, rock_thresh * 1.15, steep)
			var sand := (1.0 - smoothstep(sandline, sandline + 2.0, h))
			sand *= 1.0 - smoothstep(0.03, 0.15, steep)
			sand = maxf(0.0, sand - rock - snow)
			var grass := maxf(0.0, 1.0 - snow - rock - sand)
			var total := maxf(snow + rock + sand + grass, 0.001)
			splat.set_pixel(x, z, Color(grass / total, rock / total, snow / total, sand / total))


static func _normal(hm: Heightmap, x: int, z: int) -> Vector3:
	var s := hm.size
	var hl := hm.get_height(maxi(x - 1, 0), z)
	var hr := hm.get_height(mini(x + 1, s - 1), z)
	var hd := hm.get_height(x, maxi(z - 1, 0))
	var hu := hm.get_height(x, mini(z + 1, s - 1))
	return Vector3(hl - hr, 2.0 * hm.spacing(), hd - hu).normalized()
