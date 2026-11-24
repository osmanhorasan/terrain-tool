class_name TerrainImporter
extends RefCounted

## Loads an external heightmap image (PNG/JPG/EXR...) and normalizes it into
## an FORMAT_RF image spanning [0, world_size * peak_fraction] meters.


static func import_heightmap(path: String, world_size: float, peak_fraction := 0.25) -> Image:
	var img := Image.new()
	if img.load(path) != OK:
		return null
	img.convert(Image.FORMAT_RF)
	var w := img.get_width()
	var h := img.get_height()
	var minv := INF
	var maxv := -INF
	for z in h:
		for x in w:
			var v := img.get_pixel(x, z).r
			minv = minf(minv, v)
			maxv = maxf(maxv, v)
	var range_ := maxf(maxv - minv, 0.0001)
	var scale := world_size * peak_fraction / range_
	for z in h:
		for x in w:
			var v := img.get_pixel(x, z).r
			img.set_pixel(x, z, Color((v - minv) * scale, 0, 0))
	return img
