class_name TerrainMeshBuilder
extends RefCounted

## Builds a CPU-baked ArrayMesh from a Heightmap.
## Used for export — the live preview displaces on the GPU instead.

var hm: Heightmap


func _init(p_hm: Heightmap) -> void:
	hm = p_hm


func merged_mesh() -> ArrayMesh:
	return _build_mesh(0, 0, hm.size - 1)


func _build_mesh(x0: int, z0: int, quads: int) -> ArrayMesh:
	var side := quads + 1
	var n := hm.size
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(side * side)
	normals.resize(side * side)
	uvs.resize(side * side)
	var i := 0
	for z in side:
		for x in side:
			var mx := x0 + x
			var mz := z0 + z
			verts[i] = hm.map_to_world(mx, mz)
			normals[i] = _normal_at(mx, mz)
			uvs[i] = Vector2(mx, mz) / float(n - 1)
			i += 1
	var idx := PackedInt32Array()
	idx.resize(quads * quads * 6)
	var t := 0
	for z in quads:
		for x in quads:
			var a := z * side + x
			var b := a + 1
			var c := a + side
			var d := c + 1
			idx[t] = a
			idx[t + 1] = c
			idx[t + 2] = b
			idx[t + 3] = b
			idx[t + 4] = c
			idx[t + 5] = d
			t += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _normal_at(x: int, z: int) -> Vector3:
	var s := hm.size
	var hl := hm.get_height(maxi(x - 1, 0), z)
	var hr := hm.get_height(mini(x + 1, s - 1), z)
	var hd := hm.get_height(x, maxi(z - 1, 0))
	var hu := hm.get_height(x, mini(z + 1, s - 1))
	return Vector3(hl - hr, 2.0 * hm.spacing(), hd - hu).normalized()
