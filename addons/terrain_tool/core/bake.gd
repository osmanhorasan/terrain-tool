class_name AlbedoBake
extends RefCounted

## Bakes the splat-blended albedo into a single image.
## Used for glTF export, which cannot carry the custom splat shader.


static func bake(splat: Image, splat2: Image, layer_images: Array, tiling: int, out_size := 1024) -> Image:
	var img := Image.create(out_size, out_size, false, Image.FORMAT_RGB8)
	var sn := splat.get_width()
	var lw: int = layer_images[0].get_width()
	for y in out_size:
		for x in out_size:
			var u := float(x) / (out_size - 1)
			var v := float(y) / (out_size - 1)
			var s1 := splat.get_pixel(int(u * (sn - 1)), int(v * (sn - 1)))
			var s2 := splat2.get_pixel(int(u * (sn - 1)), int(v * (sn - 1)))
			var wsum := maxf(s1.r + s1.g + s1.b + s1.a + s2.r + s2.g + s2.b + s2.a, 0.001)
			var lu := int(u * tiling * lw) % lw
			var lv := int(v * tiling * lw) % lw
			var c := Color(0, 0, 0)
			c += layer_images[0].get_pixel(lu, lv) * (s1.r / wsum)
			c += layer_images[1].get_pixel(lu, lv) * (s1.g / wsum)
			c += layer_images[2].get_pixel(lu, lv) * (s1.b / wsum)
			c += layer_images[3].get_pixel(lu, lv) * (s1.a / wsum)
			c += layer_images[4].get_pixel(lu, lv) * (s2.r / wsum)
			c += layer_images[5].get_pixel(lu, lv) * (s2.g / wsum)
			c += layer_images[6].get_pixel(lu, lv) * (s2.b / wsum)
			c += layer_images[7].get_pixel(lu, lv) * (s2.a / wsum)
			img.set_pixel(x, y, c)
	return img
