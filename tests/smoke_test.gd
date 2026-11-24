extends SceneTree

## Headless smoke test: godot --headless -s tests/smoke_test.gd
## Exercises the non-UI code paths: ops, erosion, mesh, foliage, bake, glTF.


func _init() -> void:
	var hm := Heightmap.create(257, 128.0)
	var brush := TerrainBrush.new()

	TerrainOps.sculpt(hm, Vector2(0, 0), brush, TerrainOps.Mode.RAISE, 0.1)
	TerrainOps.sculpt(hm, Vector2(0, 0), brush, TerrainOps.Mode.SMOOTH, 0.1)
	TerrainOps.sculpt(hm, Vector2(10, 10), brush, TerrainOps.Mode.PINCH, 0.1)
	TerrainOps.sculpt(hm, Vector2(0, 0), brush, TerrainOps.Mode.LOWER, 0.5, 0.0, 1)
	print("OK sculpt (pinch + one-sided)")

	var t0 := Time.get_ticks_msec()
	HydraulicErosion.erode(hm, 200)
	print("OK erosion 200 droplets in %d ms" % (Time.get_ticks_msec() - t0))

	var builder := TerrainMeshBuilder.new(hm)
	var mesh := builder.merged_mesh()
	print("OK mesh: %d faces" % mesh.get_faces().size())

	var splat := Image.create(257, 257, false, Image.FORMAT_RGBA8)
	splat.fill(Color(1, 0, 0, 0))
	var splat2 := Image.create(257, 257, false, Image.FORMAT_RGBA8)
	TerrainOps.paint([splat, splat2], hm, Vector2(0, 0), brush, 1, 0.5)
	TerrainOps.paint([splat, splat2], hm, Vector2(5, 5), brush, 6, 0.5)
	TerrainOps.sculpt(hm, Vector2(0, 0), brush, TerrainOps.Mode.NOISE, 0.1)
	print("OK paint (8-layer)")

	var foliage_root := Node3D.new()
	root.add_child(foliage_root)
	var fs := FoliageScatter.new()
	fs.scatter(foliage_root, hm, splat, 50)
	var rng2 := RandomNumberGenerator.new()
	fs.brush(foliage_root, hm, Vector2(0, 0), 10.0, 0, rng2)
	print("OK foliage: %d trees %d rocks" % [fs.trees.size(), fs.rocks.size()])
	fs.erase(foliage_root, Vector2(0, 0), 20.0)
	print("OK foliage erase: %d trees left" % fs.trees.size())
	foliage_root.free()

	var layer_images: Array[Image] = []
	for i in 8:
		var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
		img.fill(Color(randf(), randf(), randf()))
		layer_images.append(img)
	var baked := AlbedoBake.bake(splat, splat2, layer_images, 32, 128)
	print("OK bake: ", baked.get_size())

	AutoMaterial.apply(hm, splat, splat2, 18.0, 40.0, 0.0)
	print("OK auto-material")

	var mini := TerrainMinimap.render(hm, splat, splat2)
	print("OK minimap: ", mini.get_size())

	ThermalErosion.erode(hm, 3)
	print("OK thermal")

	var hm_f := Heightmap.create(257, 128.0)
	TerrainOps.sculpt(hm_f, Vector2(0, 0), brush, TerrainOps.Mode.RAISE, 0.2)
	TerrainFilters.terrace(hm_f, 6)
	TerrainFilters.contrast(hm_f, 0.2)
	TerrainFilters.sharpen(hm_f, 0.3)
	TerrainFilters.smooth_all(hm_f, 1)
	TerrainFilters.ramp(hm_f, Vector2(-30, 0), Vector2(30, 0), 8.0)
	print("OK filters (terrace/contrast/sharpen/smooth/ramp)")
	print("OK slope_deg: %.1f" % hm_f.slope_deg(Vector2(128, 128)))

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(baked)
	mi.material_override = mat
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(mi, state)
	print("glTF append: %s" % error_string(err))
	if err == OK:
		err = doc.write_to_filesystem(state, "user://test_export.glb")
		print("glTF write: %s" % error_string(err))
	mi.free()

	# save/load roundtrip
	var proj := TerrainProject.new()
	proj.heightmap = hm.image
	proj.splatmap = splat
	proj.terrain_size = hm.size
	proj.world_size = hm.world_size
	proj.foliage_count = 50
	err = ResourceSaver.save(proj, "user://test_project.tres")
	print("project save: %s" % error_string(err))
	var loaded := ResourceLoader.load("user://test_project.tres")
	if loaded is TerrainProject:
		var hm2 := Heightmap.from_image(loaded.heightmap, loaded.world_size)
		print("OK project load: %d x %d" % [hm2.size, hm2.size])
	else:
		print("FAIL project load")

	print("ALL OK")
	quit()
