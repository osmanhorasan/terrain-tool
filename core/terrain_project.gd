class_name TerrainProject
extends Resource

## Serializable terrain project — save/load via ResourceSaver/ResourceLoader.

@export var heightmap: Image
@export var splatmap: Image
@export var splatmap2: Image
@export var terrain_size := 257
@export var world_size := 128.0
@export var foliage_count := 0
@export var foliage_seed := 99
@export var tree_transforms: Array[Transform3D] = []
@export var rock_transforms: Array[Transform3D] = []
