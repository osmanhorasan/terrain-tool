class_name ThermalErosion
extends RefCounted

## Talus/landslide simulation: material slides from a cell to its lowest
## neighbor whenever the local slope exceeds the talus threshold.

const TALUS := 0.5 # min height difference (m) before material moves
const MOVE := 0.25 # fraction of the excess moved per pass


static func erode(hm: Heightmap, iterations: int) -> void:
	var n := hm.size
	for i in iterations:
		for z in range(1, n - 1):
			for x in range(1, n - 1):
				var h := hm.get_height(x, z)
				var lowest := h
				var lx := x
				var lz := z
				for dz in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if dx == 0 and dz == 0:
							continue
						var hn := hm.get_height(x + dx, z + dz)
						if hn < lowest:
							lowest = hn
							lx = x + dx
							lz = z + dz
				var diff := h - lowest
				if diff > TALUS:
					var move := (diff - TALUS) * MOVE
					hm.set_height(x, z, h - move)
					hm.set_height(lx, lz, lowest + move)
