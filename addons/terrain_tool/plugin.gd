@tool
extends EditorPlugin

## Terrain Tool editor plugin: adds the brush dock and forwards viewport
## mouse input to the selected GpuTerrain node.

const MODE_TREE_BRUSH := 100
const MODE_ROCK_BRUSH := 101
const MODE_ERASE_FOLIAGE := 102
const MODE_RAMP := 103

var dock: Control
var current: GpuTerrain
var _painting := false
var _stroke_before: Dictionary = {}
var _mode := 0
var _paint_layer := 0
var _brush := TerrainBrush.new()
var _flatten_target := 0.0
var _rng := RandomNumberGenerator.new()
var _ramp_armed := false
var _ramp_a := Vector2.ZERO


func _enter_tree() -> void:
	dock = preload("res://addons/terrain_tool/ui/brush_panel.tscn").instantiate()
	dock.set_plugin_mode()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	_wire()
	get_editor_interface().get_selection().selection_changed.connect(_update_current)
	_update_current()


func _exit_tree() -> void:
	remove_control_from_docks(dock)
	dock.free()


func _handles(object: Object) -> bool:
	return object is GpuTerrain


func _update_current() -> void:
	var sel := get_editor_interface().get_selection().get_selected_nodes()
	current = sel[0] if sel.size() == 1 and sel[0] is GpuTerrain else null
	dock.visible = current != null


func _wire() -> void:
	dock.sculpt_mode_changed.connect(func(m): _mode = m)
	dock.paint_layer_changed.connect(func(l): _paint_layer = l)
	dock.brush_changed.connect(func(r, s, f):
		_brush.radius = r
		_brush.strength = s
		_brush.falloff = f)
	dock.special_mode_selected.connect(func(kind): _mode = MODE_TREE_BRUSH + kind)
	dock.undo_requested.connect(func(): get_undo_redo().undo())
	dock.redo_requested.connect(func(): get_undo_redo().redo())
	dock.view_mode_selected.connect(func(m): if_node(func(n): n.set_view_mode(m)))
	dock.erode_requested.connect(func(it): _big_op("Erosion", func(): HydraulicErosion.erode(current.hm, it)))
	dock.thermal_requested.connect(func(it): _big_op("Thermal erosion", func(): ThermalErosion.erode(current.hm, it)))
	dock.filter_requested.connect(func(k, v): _big_op("Filter", func(): _run_filter(k, v)))
	dock.auto_material_requested.connect(func(sn, rk, sa):
		_big_op("Auto-material", func(): AutoMaterial.apply(current.hm, current.splatmap, current.splatmap2, sn, rk, sa)))
	dock.foliage_requested.connect(func(c): if_node(func(n): n.foliage.scatter(n, n.hm, n.splatmap, c, 99)))
	dock.reset_requested.connect(func(): if_node(_reset))


## Helper: only run when a terrain node is selected.
func if_node(fn: Callable) -> void:
	if is_instance_valid(current):
		fn.call(current)


func _reset(n: GpuTerrain) -> void:
	_big_op("Reset terrain", func():
		n.hm.image.fill(Color(0, 0, 0))
		n.splatmap.fill(Color(1, 0, 0, 0))
		n.splatmap2.fill(Color(0, 0, 0, 0)))


func _run_filter(kind: int, value: float) -> void:
	match kind:
		0: TerrainFilters.terrace(current.hm, int(value))
		1: TerrainFilters.contrast(current.hm, value)
		2: TerrainFilters.sharpen(current.hm, value)
		3: TerrainFilters.smooth_all(current.hm, int(value))


## Whole-map op wrapped in a single undoable editor action.
func _big_op(label: String, work: Callable) -> void:
	if not is_instance_valid(current):
		return
	var before := current.snapshot()
	work.call()
	var ur := get_undo_redo()
	ur.create_action(label)
	ur.add_do_method(current, "restore", current.snapshot())
	ur.add_undo_method(current, "restore", before)
	ur.commit_action(false)


func _begin_stroke() -> void:
	_stroke_before = current.snapshot()


func _end_stroke() -> void:
	var ur := get_undo_redo()
	ur.create_action("Terrain stroke")
	ur.add_do_method(current, "restore", current.snapshot())
	ur.add_undo_method(current, "restore", _stroke_before)
	ur.commit_action(false)


## Transforms the screen-space ray into the node's local space, since the
## GpuTerrain node may be moved/rotated inside the user's scene.
func _pick(cam: Camera3D, pos: Vector2) -> Vector3:
	var inv := current.global_transform.affine_inverse()
	var origin: Vector3 = inv * cam.project_ray_origin(pos)
	var dir: Vector3 = (inv.basis * cam.project_ray_normal(pos)).normalized()
	return current.raycast(origin, dir)


func _ramp_click(hit: Vector3) -> void:
	if not _ramp_armed:
		_ramp_a = Vector2(hit.x, hit.z)
		_ramp_armed = true
		_begin_stroke()
	else:
		_ramp_armed = false
		TerrainFilters.ramp(current.hm, _ramp_a, Vector2(hit.x, hit.z), _brush.radius)
		current.refresh()
		_end_stroke()


func _apply_dab(hit: Vector3, dt: float, ctrl: bool, alt: bool, shift: bool) -> void:
	var center := Vector2(hit.x, hit.z)
	if _mode == TerrainOps.Mode.PAINT:
		var layer := _paint_layer if not ctrl else (_paint_layer / 4) * 4
		TerrainOps.paint([current.splatmap, current.splatmap2], current.hm, center, _brush, layer, dt)
		current.refresh_splat(layer)
	elif _mode == MODE_TREE_BRUSH or _mode == MODE_ROCK_BRUSH:
		current.foliage.brush(current, current.hm, center, _brush.radius, _mode - MODE_TREE_BRUSH, _rng)
	elif _mode == MODE_ERASE_FOLIAGE:
		current.foliage.erase(current, center, _brush.radius)
	else:
		var eff := _mode
		var side := 0
		if shift:
			eff = TerrainOps.Mode.SMOOTH
		elif alt:
			side = -1 if ctrl else 1
		elif ctrl:
			if eff == TerrainOps.Mode.RAISE:
				eff = TerrainOps.Mode.LOWER
			elif eff == TerrainOps.Mode.LOWER:
				eff = TerrainOps.Mode.RAISE
		TerrainOps.sculpt(current.hm, center, _brush, eff, dt, _flatten_target, side)
		current.refresh()


func _forward_3d_gui_input(cam: Camera3D, event: InputEvent) -> int:
	if not is_instance_valid(current):
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := _pick(cam, event.position)
			if not is_finite(hit.x):
				return AFTER_GUI_INPUT_PASS
			if _mode == MODE_RAMP:
				_ramp_click(hit)
				return AFTER_GUI_INPUT_STOP
			_begin_stroke()
			_painting = true
			_flatten_target = current.hm.sample_height(current.hm.world_to_map_f(hit.x, hit.z))
			_apply_dab(hit, 0.06, event.ctrl_pressed, event.alt_pressed, event.shift_pressed)
			return AFTER_GUI_INPUT_STOP
		elif _painting:
			_painting = false
			_end_stroke()
			return AFTER_GUI_INPUT_STOP
	elif event is InputEventMouseMotion and _painting:
		var hit := _pick(cam, event.position)
		if is_finite(hit.x):
			_apply_dab(hit, 0.03, event.ctrl_pressed, event.alt_pressed, event.shift_pressed)
			return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS
