extends Node3D

## Terrain Tool — standalone terrain editor that exports Godot-ready scenes.
## Layers mirror the engine's own architecture:
##   core/    = data model + pure ops (no scene knowledge)
##   systems/ = GPU view, mesh export, foliage (the "server" layer)
##   ui/      = panels
##   main     = glue: camera, picking, input, history, file IO

const DEFAULT_HM_SIZE := 257
const DEFAULT_WORLD_SIZE := 128.0
const UV_TILING := 32
const HM_SIZES := [129, 257, 513, 1025]
const MODES := ["Raise", "Lower", "Smooth", "Flatten", "Noise", "Pinch", "Paint"]
const MODE_TREE_BRUSH := 100
const MODE_ROCK_BRUSH := 101
const MODE_ERASE_FOLIAGE := 102
const MODE_RAMP := 103

enum MenuId { NEW, OPEN, IMPORT, SAVE, SAVE_AS, EXPORT_TSCN, EXPORT_GLB, QUIT }

var hm: Heightmap
var splat: Image
var splat2: Image
var splat_tex: ImageTexture
var splat2_tex: ImageTexture
var builder: TerrainMeshBuilder
var view: GpuTerrainView
var layer_images: Array[Image] = []
var layer_textures: Array[ImageTexture] = []
var foliage := FoliageScatter.new()
var foliage_seed := 99
var rng := RandomNumberGenerator.new()
var minimap_tex: ImageTexture
var _erode_task := -1
var _erode_t0 := 0
var _erode_iters := 0
var _thermal_task := -1
var _thermal_t0 := 0
var _thermal_iters := 0
var _filter_task := -1
var _filter_t0 := 0
var _filter_name := ""
var _ramp_armed := false
var _ramp_a := Vector2.ZERO

var brush := TerrainBrush.new()
var history := TerrainHistory.new()
var mode := TerrainOps.Mode.RAISE
var paint_layer := 0

var painting := false
var flatten_target := 0.0
var hover_ok := false
var hover_pos := Vector3.ZERO
var ui_blocked := false

var current_path := ""
var dirty := false
var _pending_action: Callable

# orbit camera state
var cam_dist := 70.0
var cam_yaw := 0.0
var cam_pitch := -0.6
var orbiting := false
var panning := false

var _new_dialog: ConfirmationDialog
var _size_opt: OptionButton
var _world_spin: SpinBox

@onready var pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var terrain_root: Node3D = $Terrain
@onready var foliage_root: Node3D = $Foliage
@onready var water: MeshInstance3D = $Water
@onready var minimap: TextureRect = $UI/Minimap
@onready var minimap_marker: ColorRect = $UI/Minimap/Marker
@onready var cursor: MeshInstance3D = $BrushCursor
@onready var panel: PanelContainer = $UI/BrushPanel
@onready var status_label: Label = $UI/StatusBar/StatusLabel
@onready var menu_bar: MenuBar = $UI/MenuBar
@onready var export_dialog: FileDialog = $UI/ExportDialog
@onready var export_glb_dialog: FileDialog = $UI/ExportGlbDialog
@onready var save_dialog: FileDialog = $UI/SaveDialog
@onready var open_dialog: FileDialog = $UI/OpenDialog
@onready var import_dialog: FileDialog = $UI/ImportDialog
@onready var notice_dialog: AcceptDialog = $UI/NoticeDialog
@onready var confirm_dialog: ConfirmationDialog = $UI/ConfirmDialog


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_make_layer_textures()
	_init_world(DEFAULT_HM_SIZE, DEFAULT_WORLD_SIZE)
	_build_menus()
	_build_new_dialog()
	_connect_ui()
	_apply_cam()
	_update_title()


## Builds or rebuilds the whole world state (new project / open project).
func _init_world(size: int, world: float, proj: TerrainProject = null) -> void:
	if proj:
		hm = Heightmap.from_image(proj.heightmap, proj.world_size)
		splat = proj.splatmap.duplicate()
		splat2 = proj.splatmap2.duplicate() if proj.splatmap2 else Image.create(hm.size, hm.size, false, Image.FORMAT_RGBA8)
		for s in [splat, splat2]:
			if s.get_width() != hm.size:
				s.resize(hm.size, hm.size, Image.INTERPOLATE_BILINEAR)
	else:
		hm = Heightmap.create(size, world)
		_seed_terrain()
		splat = Image.create(size, size, false, Image.FORMAT_RGBA8)
		splat.fill(Color(1.0, 0.0, 0.0, 0.0))
		splat2 = Image.create(size, size, false, Image.FORMAT_RGBA8)
	if splat_tex and splat_tex.get_width() == splat.get_width():
		splat_tex.update(splat)
		splat2_tex.update(splat2)
	else:
		splat_tex = ImageTexture.create_from_image(splat)
		splat2_tex = ImageTexture.create_from_image(splat2)
	if view:
		view.node.free()
	view = GpuTerrainView.new(hm, splat_tex, splat2_tex, layer_textures)
	terrain_root.add_child(view.node)
	builder = TerrainMeshBuilder.new(hm)
	foliage.clear(foliage_root)
	if proj:
		foliage.trees.assign(proj.tree_transforms)
		foliage.rocks.assign(proj.rock_transforms)
		foliage.restore_cells()
		foliage.rebuild(foliage_root)
	history.clear()
	_sync_history()
	_refresh_minimap()


func _seed_terrain() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 42
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var half := hm.world_size * 0.5
	for z in hm.size:
		for x in hm.size:
			var wx := x * hm.spacing() - half
			var wz := z * hm.spacing() - half
			hm.set_height(x, z, noise.get_noise_2d(wx, wz) * 12.0)


func _make_layer_textures() -> void:
	var defs := [
		[Color(0.24, 0.42, 0.14), Color(0.42, 0.55, 0.20)], # grass
		[Color(0.30, 0.28, 0.26), Color(0.48, 0.46, 0.44)], # rock
		[Color(0.80, 0.84, 0.90), Color(0.95, 0.97, 1.00)], # snow
		[Color(0.62, 0.50, 0.32), Color(0.78, 0.66, 0.45)], # sand
		[Color(0.40, 0.28, 0.16), Color(0.52, 0.38, 0.22)], # dirt
		[Color(0.26, 0.20, 0.13), Color(0.36, 0.27, 0.17)], # mud
		[Color(0.52, 0.52, 0.50), Color(0.66, 0.66, 0.64)], # gravel
		[Color(0.14, 0.34, 0.10), Color(0.26, 0.44, 0.16)], # moss
	]
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.06
	noise.fractal_octaves = 3
	var noise_img := noise.get_image(256, 256)
	for i in 8:
		var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
		for y in 256:
			for x in 256:
				var t: float = noise_img.get_pixel(x, y).r
				img.set_pixel(x, y, defs[i][0].lerp(defs[i][1], t))
		layer_images.append(img)
		layer_textures.append(ImageTexture.create_from_image(img))


func _build_menus() -> void:
	var file := PopupMenu.new()
	file.name = "File"
	menu_bar.add_child(file)
	file.add_item("New Project", MenuId.NEW)
	file.set_item_accelerator(0, KEY_MASK_CTRL | KEY_N)
	file.add_item("Open...", MenuId.OPEN)
	file.set_item_accelerator(1, KEY_MASK_CTRL | KEY_O)
	file.add_item("Import Heightmap...", MenuId.IMPORT)
	file.add_separator()
	file.add_item("Save", MenuId.SAVE)
	file.set_item_accelerator(4, KEY_MASK_CTRL | KEY_S)
	file.add_item("Save As...", MenuId.SAVE_AS)
	file.set_item_accelerator(5, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_S)
	file.add_separator()
	file.add_item("Export .tscn...", MenuId.EXPORT_TSCN)
	file.add_item("Export .glb...", MenuId.EXPORT_GLB)
	file.add_separator()
	file.add_item("Quit", MenuId.QUIT)
	file.id_pressed.connect(_on_menu_id)


func _build_new_dialog() -> void:
	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = "New Terrain"
	var vb := VBoxContainer.new()
	var size_row := HBoxContainer.new()
	size_row.add_child(_label("Resolution:"))
	_size_opt = OptionButton.new()
	for s in HM_SIZES:
		_size_opt.add_item("%d x %d" % [s, s])
	_size_opt.selected = 1
	size_row.add_child(_size_opt)
	vb.add_child(size_row)
	var world_row := HBoxContainer.new()
	world_row.add_child(_label("World size:"))
	_world_spin = SpinBox.new()
	_world_spin.min_value = 16.0
	_world_spin.max_value = 1024.0
	_world_spin.step = 16.0
	_world_spin.value = DEFAULT_WORLD_SIZE
	_world_spin.suffix = " m"
	world_row.add_child(_world_spin)
	vb.add_child(world_row)
	_new_dialog.add_child(vb)
	_new_dialog.register_text_enter(_world_spin.get_line_edit())
	_new_dialog.confirmed.connect(_on_new_confirmed)
	$UI.add_child(_new_dialog)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 90.0
	return l


func _connect_ui() -> void:
	panel.sculpt_mode_changed.connect(func(m): mode = m)
	panel.paint_layer_changed.connect(func(l): paint_layer = l)
	panel.brush_changed.connect(func(r, s, f):
		brush.radius = r
		brush.strength = s
		brush.falloff = f)
	panel.undo_requested.connect(_undo)
	panel.redo_requested.connect(_redo)
	panel.reset_requested.connect(_reset_terrain)
	panel.erode_requested.connect(_erode)
	panel.foliage_requested.connect(_scatter_foliage)
	panel.special_mode_selected.connect(func(kind): mode = MODE_TREE_BRUSH + kind)
	panel.auto_material_requested.connect(_auto_material)
	panel.water_toggled.connect(func(on): water.visible = on)
	panel.water_level_changed.connect(func(v): water.position.y = v)
	panel.thermal_requested.connect(_thermal)
	panel.filter_requested.connect(_filter)
	panel.view_mode_selected.connect(func(m): view.material.set_shader_parameter("view_mode", m))
	panel.export_requested.connect(func(): export_dialog.popup_centered())
	panel.export_glb_requested.connect(func(): export_glb_dialog.popup_centered())
	export_dialog.dir_selected.connect(_export_tscn)
	export_glb_dialog.file_selected.connect(_export_glb)
	save_dialog.file_selected.connect(func(p): _save(p))
	open_dialog.file_selected.connect(_open)
	import_dialog.file_selected.connect(_import_heightmap)
	minimap.gui_input.connect(_on_minimap_input)
	confirm_dialog.confirmed.connect(func(): _pending_action.call())
	_sync_history()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_try_discard(func(): get_tree().quit())


func _process(delta: float) -> void:
	if _erode_task != -1 and WorkerThreadPool.is_task_completed(_erode_task):
		WorkerThreadPool.wait_for_task_completion(_erode_task)
		_erode_task = -1
		view.refresh(hm)
		_refresh_minimap()
		_notice("Erosion: %d droplets in %d ms" % [_erode_iters, Time.get_ticks_msec() - _erode_t0])
	if _thermal_task != -1 and WorkerThreadPool.is_task_completed(_thermal_task):
		WorkerThreadPool.wait_for_task_completion(_thermal_task)
		_thermal_task = -1
		view.refresh(hm)
		_refresh_minimap()
		_notice("Thermal: %d passes in %d ms" % [_thermal_iters, Time.get_ticks_msec() - _thermal_t0])
	if _filter_task != -1 and WorkerThreadPool.is_task_completed(_filter_task):
		WorkerThreadPool.wait_for_task_completion(_filter_task)
		_filter_task = -1
		view.refresh(hm)
		_refresh_minimap()
		_notice("%s done in %d ms" % [_filter_name, Time.get_ticks_msec() - _filter_t0])
	if orbiting:
		_fly(delta)
	var mpos := get_viewport().get_mouse_position()
	ui_blocked = panel.get_global_rect().has_point(mpos)
	var hit := hm.raycast(camera.project_ray_origin(mpos), camera.project_ray_normal(mpos))
	hover_ok = is_finite(hit.x)
	if hover_ok:
		hover_pos = hit
	cursor.visible = hover_ok and not ui_blocked
	if cursor.visible:
		cursor.global_position = hit + Vector3(0.0, 0.05, 0.0)
		cursor.scale = Vector3(brush.radius, 1.5, brush.radius)
	if painting and hover_ok and not ui_blocked and _erode_task == -1 and _thermal_task == -1 and _filter_task == -1:
		var center := Vector2(hit.x, hit.z)
		var ctrl := Input.is_key_pressed(KEY_CTRL)
		var alt := Input.is_key_pressed(KEY_ALT)
		if mode == TerrainOps.Mode.PAINT:
			# Ctrl+paint = erase back to the splat's base channel (grass/dirt).
			var layer := paint_layer if not ctrl else (paint_layer / 4) * 4
			TerrainOps.paint([splat, splat2], hm, center, brush, layer, delta)
			if layer < 4:
				splat_tex.update(splat)
			else:
				splat2_tex.update(splat2)
		elif mode == MODE_TREE_BRUSH or mode == MODE_ROCK_BRUSH:
			if foliage.brush(foliage_root, hm, center, brush.radius, mode - MODE_TREE_BRUSH, rng):
				_mark_dirty()
		elif mode == MODE_ERASE_FOLIAGE:
			if foliage.erase(foliage_root, center, brush.radius):
				_mark_dirty()
		else:
			# Shift = smooth, Alt = raise-only, Ctrl+Alt = lower-only,
			# Ctrl alone = invert raise/lower (Terrain3D conventions).
			var eff := mode
			var side := 0
			if Input.is_key_pressed(KEY_SHIFT):
				eff = TerrainOps.Mode.SMOOTH
			elif alt:
				side = -1 if ctrl else 1
			elif ctrl:
				if eff == TerrainOps.Mode.RAISE:
					eff = TerrainOps.Mode.LOWER
				elif eff == TerrainOps.Mode.LOWER:
					eff = TerrainOps.Mode.RAISE
			TerrainOps.sculpt(hm, center, brush, eff, delta, flatten_target, side)
			view.refresh(hm)
	_update_minimap_marker()
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					if hover_ok and not ui_blocked:
						if mode == MODE_RAMP:
							_ramp_click()
						else:
							_push_history()
							painting = true
							flatten_target = hm.sample_height(hm.world_to_map_f(hover_pos.x, hover_pos.z))
				else:
					if painting:
						_refresh_minimap()
					painting = false
			MOUSE_BUTTON_RIGHT:
				orbiting = event.pressed
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if orbiting else Input.MOUSE_MODE_VISIBLE
			MOUSE_BUTTON_MIDDLE:
				panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					cam_dist = clampf(cam_dist * 0.9, 4.0, 500.0)
					_apply_cam()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					cam_dist = clampf(cam_dist * 1.1, 4.0, 500.0)
					_apply_cam()
	elif event is InputEventMouseMotion:
		if orbiting:
			cam_yaw -= event.relative.x * 0.005
			cam_pitch = clampf(cam_pitch - event.relative.y * 0.005, -1.5, -0.05)
			_apply_cam()
		elif panning:
			var right := camera.global_transform.basis.x
			var fwd := -camera.global_transform.basis.z
			fwd.y = 0.0
			pivot.global_position += (-right * event.relative.x + fwd.normalized() * event.relative.y) * cam_dist * 0.0015
	elif event is InputEventKey and event.pressed:
		if event.ctrl_pressed:
			match event.keycode:
				KEY_Z:
					_redo() if event.shift_pressed else _undo()
				KEY_Y:
					_redo()
				KEY_S:
					if event.shift_pressed:
						save_dialog.popup_centered()
					else:
						_save()
				KEY_O:
					_try_discard(func(): open_dialog.popup_centered())
				KEY_N:
					_try_discard(func(): _new_dialog.popup_centered())
		elif event.keycode == KEY_ESCAPE:
			painting = false
			_ramp_armed = false
		elif event.keycode == KEY_F12:
			_screenshot()
		elif event.keycode == KEY_BRACKETLEFT:
			panel.set_brush(brush.radius / 1.15, brush.strength)
		elif event.keycode == KEY_BRACKETRIGHT:
			panel.set_brush(brush.radius * 1.15, brush.strength)
		elif event.keycode == KEY_MINUS:
			panel.set_brush(brush.radius, maxf(brush.strength - 0.05, 0.01))
		elif event.keycode == KEY_EQUAL:
			panel.set_brush(brush.radius, minf(brush.strength + 0.05, 1.0))


func _apply_cam() -> void:
	pivot.rotation = Vector3(cam_pitch, cam_yaw, 0.0)
	camera.position = Vector3(0.0, 0.0, cam_dist)


## WASD/QE fly while RMB is held.
func _fly(delta: float) -> void:
	var b := camera.global_transform.basis
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move -= b.z
	if Input.is_key_pressed(KEY_S):
		move += b.z
	if Input.is_key_pressed(KEY_A):
		move -= b.x
	if Input.is_key_pressed(KEY_D):
		move += b.x
	if Input.is_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		move -= Vector3.UP
	if move != Vector3.ZERO:
		pivot.global_position += move.normalized() * cam_dist * delta * 0.8


func _screenshot() -> void:
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if dir == "":
		dir = "user://"
	var p := dir.path_join("terrain_%d.png" % int(Time.get_unix_time_from_system()))
	var err := get_viewport().get_texture().get_image().save_png(p)
	_notice("Screenshot: " + p if err == OK else "Screenshot failed")


# --- Menus, title, status -------------------------------------------------

func _on_menu_id(id: int) -> void:
	match id:
		MenuId.NEW:
			_try_discard(func(): _new_dialog.popup_centered())
		MenuId.OPEN:
			_try_discard(func(): open_dialog.popup_centered())
		MenuId.IMPORT:
			import_dialog.popup_centered()
		MenuId.SAVE:
			_save()
		MenuId.SAVE_AS:
			save_dialog.popup_centered()
		MenuId.EXPORT_TSCN:
			export_dialog.popup_centered()
		MenuId.EXPORT_GLB:
			export_glb_dialog.popup_centered()
		MenuId.QUIT:
			_try_discard(func(): get_tree().quit())


func _update_title() -> void:
	var file := current_path.get_file() if current_path != "" else "untitled"
	DisplayServer.window_set_title("Terrain Tool — %s%s" % [file, "*" if dirty else ""])


func _update_status() -> void:
	var s := "%d x %d  |  %.0f m" % [hm.size, hm.size, hm.world_size]
	if hover_ok:
		var slope := hm.slope_deg(hm.world_to_map_f(hover_pos.x, hover_pos.z))
		s += "  |  x %.1f  z %.1f  h %.2f  %.0f°" % [hover_pos.x, hover_pos.z, hover_pos.y, slope]
	var mname: String
	if mode == MODE_TREE_BRUSH:
		mname = "Trees"
	elif mode == MODE_ROCK_BRUSH:
		mname = "Rocks"
	elif mode == MODE_ERASE_FOLIAGE:
		mname = "Erase Foliage"
	elif mode == MODE_RAMP:
		mname = "Ramp" + (" (pick end)" if _ramp_armed else " (pick start)")
	elif mode == TerrainOps.Mode.PAINT:
		mname = "Paint %d" % (paint_layer + 1)
	else:
		mname = MODES[mode]
	s += "  |  %s" % mname
	if _erode_task != -1:
		s += "  |  eroding..."
	if _thermal_task != -1:
		s += "  |  thermaling..."
	if _filter_task != -1:
		s += "  |  filtering..."
	status_label.text = s


func _notice(text: String) -> void:
	status_label.text = text
	print(text)


func _popup_error(text: String) -> void:
	notice_dialog.dialog_text = text
	notice_dialog.popup_centered()
	push_error(text)


## Runs `action` immediately if clean, otherwise asks to discard changes.
func _try_discard(action: Callable) -> void:
	if dirty:
		_pending_action = action
		confirm_dialog.popup_centered()
	else:
		action.call()


func _mark_dirty() -> void:
	if not dirty:
		dirty = true
		_update_title()


# --- History ---------------------------------------------------------------

func _push_history() -> void:
	history.push(hm.image, splat)
	_mark_dirty()
	_sync_history()


func _sync_history() -> void:
	panel.set_undo_state(history.can_undo(), history.can_redo())


func _undo() -> void:
	if history.undo(hm.image, splat):
		_refresh_all()
	_sync_history()


func _redo() -> void:
	if history.redo(hm.image, splat):
		_refresh_all()
	_sync_history()


func _refresh_all() -> void:
	splat_tex.update(splat)
	splat2_tex.update(splat2)
	view.refresh(hm)
	_refresh_minimap()


func _refresh_minimap() -> void:
	var img := TerrainMinimap.render(hm, splat, splat2)
	if minimap_tex and minimap_tex.get_width() == img.get_width():
		minimap_tex.update(img)
	else:
		minimap_tex = ImageTexture.create_from_image(img)
	minimap.texture = minimap_tex


func _update_minimap_marker() -> void:
	var p := pivot.global_position
	var u := (p.x / hm.world_size + 0.5) * minimap.size.x
	var v := (p.z / hm.world_size + 0.5) * minimap.size.y
	minimap_marker.position = Vector2(u - 3.0, v - 3.0)


func _on_minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var uv: Vector2 = event.position / minimap.size
		pivot.global_position = Vector3((uv.x - 0.5) * hm.world_size, 0.0, (uv.y - 0.5) * hm.world_size)


func _reset_terrain() -> void:
	_push_history()
	hm.image.fill(Color(0.0, 0.0, 0.0))
	splat.fill(Color(1.0, 0.0, 0.0, 0.0))
	splat2.fill(Color(0.0, 0.0, 0.0, 0.0))
	_refresh_all()


func _erode(iterations: int) -> void:
	if _erode_task != -1:
		return
	_push_history()
	_erode_iters = iterations
	_erode_t0 = Time.get_ticks_msec()
	_erode_task = WorkerThreadPool.add_task(HydraulicErosion.erode.bind(hm, iterations))


func _thermal(iterations: int) -> void:
	if _thermal_task != -1 or _erode_task != -1:
		return
	_push_history()
	_thermal_iters = iterations
	_thermal_t0 = Time.get_ticks_msec()
	_thermal_task = WorkerThreadPool.add_task(ThermalErosion.erode.bind(hm, iterations))


func _scatter_foliage(count: int) -> void:
	foliage.scatter(foliage_root, hm, splat, count, foliage_seed)
	foliage_seed += 1
	_mark_dirty()
	_notice("Foliage scattered: %d requested" % count)


## kind: 0 = terrace (value = step count), 1 = contrast, 2 = sharpen,
## 3 = smooth (value = pass count). Runs on a worker thread like erosion.
func _filter(kind: int, value: float) -> void:
	if _erode_task != -1 or _thermal_task != -1 or _filter_task != -1:
		return
	_push_history()
	var work: Callable
	match kind:
		0:
			_filter_name = "Terrace"
			work = TerrainFilters.terrace.bind(hm, int(value))
		1:
			_filter_name = "Contrast"
			work = TerrainFilters.contrast.bind(hm, value)
		2:
			_filter_name = "Sharpen"
			work = TerrainFilters.sharpen.bind(hm, value)
		_:
			_filter_name = "Smooth"
			work = TerrainFilters.smooth_all.bind(hm, int(value))
	_filter_t0 = Time.get_ticks_msec()
	_filter_task = WorkerThreadPool.add_task(work)


## Two-click ramp: first click arms the start point, second applies.
func _ramp_click() -> void:
	if not _ramp_armed:
		_ramp_a = Vector2(hover_pos.x, hover_pos.z)
		_ramp_armed = true
		_push_history()
	else:
		_ramp_armed = false
		TerrainFilters.ramp(hm, _ramp_a, Vector2(hover_pos.x, hover_pos.z), brush.radius)
		view.refresh(hm)
		_refresh_minimap()
		_mark_dirty()


func _auto_material(snowline: float, rock_deg: float, sandline: float) -> void:
	_push_history()
	AutoMaterial.apply(hm, splat, splat2, snowline, rock_deg, sandline)
	splat_tex.update(splat)
	splat2_tex.update(splat2)
	_refresh_minimap()
	_notice("Auto-material applied")


func _import_heightmap(path: String) -> void:
	var img := TerrainImporter.import_heightmap(path, hm.world_size)
	if img == null:
		_popup_error("Failed to load image: " + path)
		return
	if img.get_width() != hm.size:
		img.resize(hm.size, hm.size, Image.INTERPOLATE_BILINEAR)
	_push_history()
	hm.image.copy_from(img)
	view.refresh(hm)
	_refresh_minimap()
	_notice("Imported heightmap: " + path.get_file())


# --- Save / Load -----------------------------------------------------------

func _on_new_confirmed() -> void:
	_init_world(HM_SIZES[_size_opt.selected], _world_spin.value)
	current_path = ""
	dirty = false
	_update_title()
	_notice("New terrain: %d x %d, %.0f m" % [hm.size, hm.size, hm.world_size])


func _save(path := "") -> void:
	var target := path if path != "" else current_path
	if target == "":
		save_dialog.popup_centered()
		return
	var proj := TerrainProject.new()
	proj.heightmap = hm.image
	proj.splatmap = splat
	proj.splatmap2 = splat2
	proj.terrain_size = hm.size
	proj.world_size = hm.world_size
	proj.foliage_count = foliage.trees.size() + foliage.rocks.size()
	proj.foliage_seed = foliage_seed
	proj.tree_transforms = foliage.trees.duplicate()
	proj.rock_transforms = foliage.rocks.duplicate()
	var err := ResourceSaver.save(proj, target)
	if err == OK:
		current_path = target
		dirty = false
		_update_title()
		_notice("Saved: " + target)
	else:
		_popup_error("Save failed: " + error_string(err))


func _open(path: String) -> void:
	var res := ResourceLoader.load(path)
	if res is TerrainProject:
		_init_world(0, 0.0, res)
		current_path = path
		dirty = false
		_update_title()
		_notice("Opened: " + path)
	else:
		_popup_error("Not a terrain project: " + path)


# --- Export ----------------------------------------------------------------

## Exports a ready-to-drop-in scene: baked mesh + splat material + textures,
## plus any scattered foliage.
func _export_tscn(dir: String) -> void:
	var mesh := builder.merged_mesh()
	ResourceSaver.save(mesh, dir.path_join("terrain_mesh.res"))
	ResourceSaver.save(hm.image, dir.path_join("terrain_heightmap.res"))
	splat.save_png(dir.path_join("terrain_splatmap.png"))
	splat2.save_png(dir.path_join("terrain_splatmap2.png"))
	var export_mat := ShaderMaterial.new()
	export_mat.shader = load("res://addons/terrain_tool/systems/terrain.gdshader")
	export_mat.set_shader_parameter("uv_tiling", UV_TILING)
	export_mat.set_shader_parameter("splatmap", _save_pct(splat, dir.path_join("terrain_splatmap_tex.res")))
	export_mat.set_shader_parameter("splatmap2", _save_pct(splat2, dir.path_join("terrain_splatmap2_tex.res")))
	for i in 8:
		export_mat.set_shader_parameter("layer%d" % i, _save_pct(layer_images[i], dir.path_join("terrain_layer%d.res" % i)))
	var root := Node3D.new()
	root.name = "TerrainExport"
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.material_override = export_mat
	root.add_child(mi)
	mi.owner = root
	for f in foliage_root.get_children():
		var dup: Node3D = f.duplicate()
		root.add_child(dup)
		dup.owner = root
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, dir.path_join("terrain.tscn"))
	root.free()
	if err == OK:
		_notice("Terrain exported to: " + dir)
	else:
		_popup_error("Export failed: " + error_string(err))


## Exports geometry as glTF with a baked albedo texture (splat shader can't
## be represented in glTF's standard material model).
func _export_glb(path: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = builder.merged_mesh()
	var baked := AlbedoBake.bake(splat, splat2, layer_images, UV_TILING)
	baked.save_png(path.get_basename() + "_albedo.png")
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(baked)
	mat.roughness = 0.9
	mi.material_override = mat
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(mi, state)
	if err == OK:
		err = doc.write_to_filesystem(state, path)
	mi.free()
	if err == OK:
		_notice("glTF exported to: " + path)
	else:
		_popup_error("glTF export failed: " + error_string(err))


func _save_pct(img: Image, path: String) -> PortableCompressedTexture2D:
	var pct := PortableCompressedTexture2D.new()
	pct.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	ResourceSaver.save(pct, path)
	return pct
