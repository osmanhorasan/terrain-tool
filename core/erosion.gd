class_name HydraulicErosion
extends RefCounted

## Droplet-based hydraulic erosion (Beyer/Lague style).
## Runs on the CPU heightmap; one call = one undoable operation.

const MAX_LIFETIME := 30
const INERTIA := 0.05
const SEDIMENT_CAPACITY := 4.0
const MIN_SLOPE := 0.01
const ERODE_SPEED := 0.3
const DEPOSIT_SPEED := 0.3
const EVAPORATE := 0.01
const GRAVITY := 4.0


static func erode(hm: Heightmap, iterations: int, seed_: int = 12345) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var n := hm.size
	for i in iterations:
		var pos := Vector2(rng.randf_range(2.0, n - 3.0), rng.randf_range(2.0, n - 3.0))
		var dir := Vector2.ZERO
		var speed := 1.0
		var water := 1.0
		var sediment := 0.0
		for step in MAX_LIFETIME:
			var xi := int(floor(pos.x))
			var zi := int(floor(pos.y))
			var fx := pos.x - xi
			var fz := pos.y - zi
			var gh := _grad_and_height(hm, xi, zi, fx, fz)
			var h_old: float = gh[1]
			dir = dir * INERTIA - gh[0] * (1.0 - INERTIA)
			if dir == Vector2.ZERO:
				dir = Vector2(rng.randf() - 0.5, rng.randf() - 0.5)
			dir = dir.normalized()
			pos += dir
			if pos.x < 1.0 or pos.y < 1.0 or pos.x >= n - 2 or pos.y >= n - 2:
				break
			var xi2 := int(floor(pos.x))
			var zi2 := int(floor(pos.y))
			var h_new: float = _grad_and_height(hm, xi2, zi2, pos.x - xi2, pos.y - zi2)[1]
			var dh := h_new - h_old
			var capacity := maxf(-dh * speed * water * SEDIMENT_CAPACITY, MIN_SLOPE)
			if sediment > capacity or dh > 0.0:
				var amount := minf(dh, sediment) if dh > 0.0 else (sediment - capacity) * DEPOSIT_SPEED
				sediment -= amount
				_apply(hm, xi, zi, fx, fz, amount)
			else:
				var amount := minf((capacity - sediment) * ERODE_SPEED, -dh)
				_apply(hm, xi, zi, fx, fz, -amount)
				sediment += amount
			speed = sqrt(maxf(speed * speed - dh * GRAVITY, 0.0))
			water *= 1.0 - EVAPORATE


## Returns [gradient: Vector2, height: float] bilinearly sampled at cell (x,z)+frac.
static func _grad_and_height(hm: Heightmap, x: int, z: int, fx: float, fz: float) -> Array:
	var h00 := hm.get_height(x, z)
	var h10 := hm.get_height(x + 1, z)
	var h01 := hm.get_height(x, z + 1)
	var h11 := hm.get_height(x + 1, z + 1)
	var gx := (h10 - h00) * (1.0 - fz) + (h11 - h01) * fz
	var gz := (h01 - h00) * (1.0 - fx) + (h11 - h10) * fx
	var h := h00 * (1.0 - fx) * (1.0 - fz) + h10 * fx * (1.0 - fz) + h01 * (1.0 - fx) * fz + h11 * fx * fz
	return [Vector2(gx, gz), h]


## Adds `delta` to the four cells around (x,z)+frac, weighted bilinearly.
static func _apply(hm: Heightmap, x: int, z: int, fx: float, fz: float, delta: float) -> void:
	hm.set_height(x, z, hm.get_height(x, z) + delta * (1.0 - fx) * (1.0 - fz))
	hm.set_height(x + 1, z, hm.get_height(x + 1, z) + delta * fx * (1.0 - fz))
	hm.set_height(x, z + 1, hm.get_height(x, z + 1) + delta * (1.0 - fx) * fz)
	hm.set_height(x + 1, z + 1, hm.get_height(x + 1, z + 1) + delta * fx * fz)
