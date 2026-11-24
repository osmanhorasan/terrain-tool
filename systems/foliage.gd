class_name FoliageScatter
extends RefCounted

## Stateful foliage manager — trees on the grass channel, rocks on the rock
## channel, rendered as MultiMeshes (zero external assets, one draw call each).
## Instances live in `trees`/`rocks` so they survive save/load and support
## incremental brush placement.

const MAX_TREE_SLOPE := 0.85 # min normal.y (~32 deg)
const MAX_ROCK_SLOPE := 0.5
const TREE_CELL := 2.5 # min spacing, meters
const ROCK_CELL := 1.2

var trees: Array[Transform3D] = []
var rocks: Array[Transform3D] = []
var _cells := {} # Vector2i -> true (spatial occupancy)


func scatter(root: Node3D, hm: Heightmap, splat: Image, count: int, seed_: int = 99) -> void:
	clear(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var mask_noise := FastNoiseLite.new()
	mask_noise.seed = seed_ + 1
	mask_noise.frequency = 0.03
	var half := hm.world_size * 0.5
	var attempts := count * 10
	while (trees.size() < count or rocks.size() < count) and attempts > 0:
		attempts -= 1
		var px := rng.randf_range(-half, half)
		var pz := rng.randf_range(-half, half)
		var m := hm.world_to_map_f(px, pz)
		var mx := int(m.x)
		var mz := int(m.y)
		var s := splat.get_pixel(mx, mz)
		var n := _normal(hm, mx, mz)
		var h := hm.sample_height(m)
		var mask := mask_noise.get_noise_2d(px, pz) * 0.5 + 0.5
		if trees.size() < count and s.r > 0.45 and n.y > MAX_TREE_SLOPE and rng.randf() < s.r * mask * 1.4:
			if _claim_cell(px, pz, TREE_CELL):
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.45, 0.85))
				trees.append(Transform3D(basis, Vector3(px, h, pz)))
		elif rocks.size() < count and s.g > 0.4 and n.y > MAX_ROCK_SLOPE and rng.randf() < s.g:
			if _claim_cell(px, pz, ROCK_CELL):
				var sc := rng.randf_range(0.6, 2.0)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.5, 0.8), sc))
				rocks.append(Transform3D(basis, Vector3(px, h - 0.15 * sc, pz)))
	rebuild(root)
	print("Foliage: %d trees, %d rocks" % [trees.size(), rocks.size()])


## kind: 0 = tree, 1 = rock. Places a few instances inside the brush radius.
## Returns true if anything was placed.
func brush(root: Node3D, hm: Heightmap, center: Vector2, radius: float, kind: int, rng: RandomNumberGenerator) -> bool:
	var added := false
	for i in 3:
		var ang := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * radius
		var px := center.x + cos(ang) * dist
		var pz := center.y + sin(ang) * dist
		var m := hm.world_to_map_f(px, pz)
		if not hm.in_bounds_f(m):
			continue
		var mx := int(m.x)
		var mz := int(m.y)
		var n := _normal(hm, mx, mz)
		var h := hm.sample_height(m)
		if kind == 0:
			if n.y <= 0.75 or not _claim_cell(px, pz, TREE_CELL):
				continue
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.45, 0.85))
			trees.append(Transform3D(basis, Vector3(px, h, pz)))
			added = true
		else:
			if not _claim_cell(px, pz, ROCK_CELL):
				continue
			var sc := rng.randf_range(0.6, 2.0)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.5, 0.8), sc))
			rocks.append(Transform3D(basis, Vector3(px, h - 0.15 * sc, pz)))
			added = true
	if added:
		rebuild(root)
	return added


## Removes every instance within `radius` of world-space `center`.
func erase(root: Node3D, center: Vector2, radius: float) -> bool:
	var changed := false
	for arr in [trees, rocks]:
		for i in range(arr.size() - 1, -1, -1):
			var o: Vector3 = arr[i].origin
			if Vector2(o.x - center.x, o.z - center.y).length() < radius:
				arr.remove_at(i)
				changed = true
	if changed:
		rebuild(root)
		restore_cells()
	return changed


func rebuild(root: Node3D) -> void:
	for c in root.get_children():
		c.free()
	if not trees.is_empty():
		root.add_child(_mm_from("Foliage_Trunk", _trunk_mesh(), _mat(Color(0.35, 0.22, 0.12)), trees))
		root.add_child(_mm_from("Foliage_Leaves", _leaves_mesh(), _mat(Color(0.16, 0.42, 0.17)), trees))
	if not rocks.is_empty():
		root.add_child(_mm_from("Foliage_Rocks", _rock_mesh(), _mat(Color(0.46, 0.44, 0.42)), rocks))


func clear(root: Node3D = null) -> void:
	trees.clear()
	rocks.clear()
	_cells.clear()
	if root:
		for c in root.get_children():
			c.free()


## Rebuilds the occupancy grid after transforms are restored from a project.
func restore_cells() -> void:
	_cells.clear()
	for t in trees:
		_cells[Vector2i(int(t.origin.x / TREE_CELL), int(t.origin.z / TREE_CELL))] = true
	for r in rocks:
		_cells[Vector2i(int(r.origin.x / ROCK_CELL), int(r.origin.z / ROCK_CELL))] = true


func _claim_cell(px: float, pz: float, cell_size: float) -> bool:
	var cell := Vector2i(int(px / cell_size), int(pz / cell_size))
	if _cells.has(cell):
		return false
	_cells[cell] = true
	return true


func _mm_from(pname: String, mesh: Mesh, mat: Material, xforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = pname
	mi.multimesh = mm
	mi.material_override = mat
	return mi


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m


func _trunk_mesh() -> Mesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.2
	cyl.height = 1.6
	cyl.radial_segments = 6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(cyl, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.8, 0.0)))
	return st.commit()


func _leaves_mesh() -> Mesh:
	var big := CylinderMesh.new()
	big.top_radius = 0.0
	big.bottom_radius = 1.1
	big.height = 2.0
	big.radial_segments = 7
	var small := CylinderMesh.new()
	small.top_radius = 0.0
	small.bottom_radius = 0.75
	small.height = 1.4
	small.radial_segments = 7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(big, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 2.3, 0.0)))
	st.append_from(small, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 3.5, 0.0)))
	return st.commit()


func _rock_mesh() -> Mesh:
	var sph := SphereMesh.new()
	sph.radius = 0.55
	sph.height = 1.1
	sph.radial_segments = 7
	sph.rings = 4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(sph, 0, Transform3D.IDENTITY)
	return st.commit()


func _normal(hm: Heightmap, x: int, z: int) -> Vector3:
	var s := hm.size
	var hl := hm.get_height(maxi(x - 1, 0), z)
	var hr := hm.get_height(mini(x + 1, s - 1), z)
	var hd := hm.get_height(x, maxi(z - 1, 0))
	var hu := hm.get_height(x, mini(z + 1, s - 1))
	return Vector3(hl - hr, 2.0 * hm.spacing(), hd - hu).normalized()
