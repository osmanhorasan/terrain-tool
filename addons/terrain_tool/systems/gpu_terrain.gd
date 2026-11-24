class_name GpuTerrainView
extends RefCounted

## Renders the heightmap via GPU vertex displacement on a static grid mesh.
## The CPU-side Image stays the source of truth; refresh() re-uploads it.

var node: MeshInstance3D
var hm_tex: ImageTexture
var material: ShaderMaterial


func _init(hm: Heightmap, splat_tex: ImageTexture, splat2_tex: ImageTexture, layer_textures: Array) -> void:
	hm_tex = ImageTexture.create_from_image(hm.image)
	var plane := PlaneMesh.new()
	plane.size = Vector2(hm.world_size, hm.world_size)
	plane.subdivide_width = hm.size - 1
	plane.subdivide_depth = hm.size - 1
	material = ShaderMaterial.new()
	material.shader = load("res://addons/terrain_tool/systems/terrain_gpu.gdshader")
	material.set_shader_parameter("heightmap", hm_tex)
	material.set_shader_parameter("splatmap", splat_tex)
	material.set_shader_parameter("splatmap2", splat2_tex)
	material.set_shader_parameter("world_size", hm.world_size)
	material.set_shader_parameter("texel_uv", 1.0 / float(hm.size - 1))
	material.set_shader_parameter("spacing", hm.spacing())
	for i in 8:
		material.set_shader_parameter("layer%d" % i, layer_textures[i])
	node = MeshInstance3D.new()
	node.name = "TerrainView"
	node.mesh = plane
	node.material_override = material


func refresh(hm: Heightmap) -> void:
	hm_tex.update(hm.image)
