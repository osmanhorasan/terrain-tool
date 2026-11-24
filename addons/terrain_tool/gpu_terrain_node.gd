@tool
@icon("res://addons/terrain_tool/icon.png")
class_name GpuTerrain
extends MeshInstance3D

## Editable terrain node. Heightmap + splatmaps live as exported
## sub-resources, so saving the scene persists the terrain. The plugin's
## dock edits this node in the 3D viewport; it also works standalone.

@export var terrain_size := 257
@export var world_size := 128.0
@export var heightmap_image: Image:
	set(v):
		heightmap_image = v
		_rebuild()
@export var splatmap: Image:
	set(v):
		splatmap = v
		_rebuild()
@export var splatmap2: Image:
	set(v):
		splatmap2 = v
		_rebuild()

var hm: Heightmap
var splat_tex: ImageTexture
var splat2_tex: ImageTexture
var foliage := FoliageScatter.new()
var _ready_done := false


func _ready() -> void:
	_ensure()


func _ensure() -> void:
	if _ready_done:
		return
	_ready_done = true
	if heightmap_image == null:
		heightmap_image = Image.create(terrain_size, terrain_size, false, Image.FORMAT_RF)
	if splatmap == null:
		splatmap = Image.create(terrain_size, terrain_size, false, Image.FORMAT_RGBA8)
		splatmap.fill(Color(1, 0, 0, 0))
	if splatmap2 == null:
		splatmap2 = Image.create(terrain_size, terrain_size, false, Image.FORMAT_RGBA8)
	hm = Heightmap.from_image(heightmap_image, world_size)
	splat_tex = ImageTexture.create_from_image(splatmap)
	splat2_tex = ImageTexture.create_from_image(splatmap2)
	var plane := PlaneMesh.new()
	plane.size = Vector2(world_size, world_size)
	plane.subdivide_width = terrain_size - 1
	plane.subdivide_depth = terrain_size - 1
	mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://addons/terrain_tool/systems/terrain_gpu.gdshader")
	mat.set_shader_parameter("heightmap", ImageTexture.create_from_image(hm.image))
	mat.set_shader_parameter("splatmap", splat_tex)
	mat.set_shader_parameter("splatmap2", splat2_tex)
	mat.set_shader_parameter("world_size", world_size)
	mat.set_shader_parameter("texel_uv", 1.0 / float(terrain_size - 1))
	mat.set_shader_parameter("spacing", hm.spacing())
	var layers := make_layer_textures()
	for i in 8:
		mat.set_shader_parameter("layer%d" % i, layers[i])
	material_override = mat
	foliage.harvest(self)


func _rebuild() -> void:
	if is_inside_tree() and _ready_done:
		_ready_done = false
		_ensure()


func raycast(origin: Vector3, dir: Vector3) -> Vector3:
	return hm.raycast(origin, dir)


func refresh() -> void:
	material_override.get_shader_parameter("heightmap").update(hm.image)


func refresh_splat(layer: int) -> void:
	if layer < 4:
		splat_tex.update(splatmap)
	else:
		splat2_tex.update(splatmap2)


func set_view_mode(m: int) -> void:
	material_override.set_shader_parameter("view_mode", m)


## For undo/redo: captures and restores height + splat state.
func snapshot() -> Dictionary:
	return {"h": hm.image.duplicate(), "s1": splatmap.duplicate(), "s2": splatmap2.duplicate()}


func restore(snap: Dictionary) -> void:
	hm.image.copy_from(snap["h"])
	splatmap.copy_from(snap["s1"])
	splatmap2.copy_from(snap["s2"])
	refresh()
	splat_tex.update(splatmap)
	splat2_tex.update(splatmap2)


static func make_layer_textures() -> Array:
	var defs := [
		[Color(0.24, 0.42, 0.14), Color(0.42, 0.55, 0.20)],
		[Color(0.30, 0.28, 0.26), Color(0.48, 0.46, 0.44)],
		[Color(0.80, 0.84, 0.90), Color(0.95, 0.97, 1.00)],
		[Color(0.62, 0.50, 0.32), Color(0.78, 0.66, 0.45)],
		[Color(0.40, 0.28, 0.16), Color(0.52, 0.38, 0.22)],
		[Color(0.26, 0.20, 0.13), Color(0.36, 0.27, 0.17)],
		[Color(0.52, 0.52, 0.50), Color(0.66, 0.66, 0.64)],
		[Color(0.14, 0.34, 0.10), Color(0.26, 0.44, 0.16)],
	]
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.06
	noise.fractal_octaves = 3
	var noise_img := noise.get_image(256, 256)
	var out := []
	for i in 8:
		var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
		for y in 256:
			for x in 256:
				var t: float = noise_img.get_pixel(x, y).r
				img.set_pixel(x, y, defs[i][0].lerp(defs[i][1], t))
		out.append(ImageTexture.create_from_image(img))
	return out
