extends PanelContainer

signal sculpt_mode_changed(mode: int)
signal paint_layer_changed(layer: int)
signal brush_changed(radius: float, strength: float, falloff: float)
signal undo_requested
signal redo_requested
signal export_requested
signal export_glb_requested
signal reset_requested
signal erode_requested(iterations: int)
signal foliage_requested(count: int)
signal special_mode_selected(kind: int)
signal auto_material_requested(snowline: float, rock_deg: float, sandline: float)
signal water_toggled(enabled: bool)
signal water_level_changed(level: float)
signal thermal_requested(iterations: int)
signal view_mode_selected(mode: int)
signal filter_requested(kind: int, value: float)

const MODE_NAMES := [
	"Raise",
	"Lower",
	"Smooth",
	"Flatten",
	"Noise",
	"Pinch",
	"Paint Grass",
	"Paint Rock",
	"Paint Snow",
	"Paint Sand",
	"Paint Dirt",
	"Paint Mud",
	"Paint Gravel",
	"Paint Moss",
	"Trees",
	"Rocks",
	"Erase Foliage",
	"Ramp",
]

const VIEW_NAMES := ["Shaded", "Height", "Slope", "Splat", "Contour"]

@onready var _mode_opt: OptionButton = %ModeOption
@onready var _radius_slider: HSlider = %RadiusSlider
@onready var _strength_slider: HSlider = %StrengthSlider
@onready var _falloff_slider: HSlider = %FalloffSlider
@onready var _radius_label: Label = %RadiusLabel
@onready var _strength_label: Label = %StrengthLabel
@onready var _falloff_label: Label = %FalloffLabel
@onready var _erode_slider: HSlider = %ErodeSlider
@onready var _erode_label: Label = %ErodeLabel
@onready var _foliage_slider: HSlider = %FoliageSlider
@onready var _foliage_label: Label = %FoliageLabel


func _ready() -> void:
	_mode_opt.clear()
	for m in MODE_NAMES:
		_mode_opt.add_item(m)
	_mode_opt.item_selected.connect(_on_mode_selected)
	for v in VIEW_NAMES:
		%ViewOption.add_item(v)
	%ViewOption.item_selected.connect(func(i): view_mode_selected.emit(i))
	_radius_slider.value_changed.connect(_on_sliders)
	_strength_slider.value_changed.connect(_on_sliders)
	_falloff_slider.value_changed.connect(_on_sliders)
	_mode_opt.tooltip_text = "Editing mode"
	_radius_slider.tooltip_text = "Brush radius in meters"
	_strength_slider.tooltip_text = "Brush strength (applied per second)"
	_falloff_slider.tooltip_text = "0 = hard edge, 1 = soft dome"
	%ErodeBtn.tooltip_text = "Simulate hydraulic erosion over the whole map"
	%FoliageBtn.tooltip_text = "Scatter trees on grass, rocks on rock — based on the splatmap"
	%UndoBtn.pressed.connect(func(): undo_requested.emit())
	%RedoBtn.pressed.connect(func(): redo_requested.emit())
	%ExportBtn.pressed.connect(func(): export_requested.emit())
	%ExportGlbBtn.pressed.connect(func(): export_glb_requested.emit())
	%ResetBtn.pressed.connect(func(): reset_requested.emit())
	%ErodeBtn.pressed.connect(func(): erode_requested.emit(int(_erode_slider.value)))
	%ThermalBtn.pressed.connect(func(): thermal_requested.emit(int(%ThermalSlider.value)))
	%ThermalSlider.value_changed.connect(func(v): %ThermalLabel.text = "Thermal: %d passes" % int(v))
	%ThermalLabel.text = "Thermal: %d passes" % int(%ThermalSlider.value)
	%FoliageBtn.pressed.connect(func(): foliage_requested.emit(int(_foliage_slider.value)))
	%TerraceBtn.pressed.connect(func(): filter_requested.emit(0, %TerraceSlider.value))
	%ContrastBtn.pressed.connect(func(): filter_requested.emit(1, 0.25))
	%SharpenBtn.pressed.connect(func(): filter_requested.emit(2, 0.4))
	%SmoothAllBtn.pressed.connect(func(): filter_requested.emit(3, 1.0))
	%TerraceSlider.value_changed.connect(func(v): %TerraceLabel.text = "Terraces: %d" % int(v))
	%TerraceLabel.text = "Terraces: %d" % int(%TerraceSlider.value)
	%AutoMatBtn.pressed.connect(func(): auto_material_requested.emit(%SnowlineSlider.value, %RockSlopeSlider.value, %SandlineSlider.value))
	%WaterCheck.toggled.connect(func(on): water_toggled.emit(on))
	%WaterSlider.value_changed.connect(func(v):
		%WaterLabel.text = "Water level: %.1f m" % v
		water_level_changed.emit(v))
	%SnowlineSlider.value_changed.connect(func(v): %SnowlineLabel.text = "Snowline: %.1f m" % v)
	%RockSlopeSlider.value_changed.connect(func(v): %RockSlopeLabel.text = "Rock slope: %.0f°" % v)
	%SandlineSlider.value_changed.connect(func(v): %SandlineLabel.text = "Sandline: %.1f m" % v)
	%SnowlineLabel.text = "Snowline: %.1f m" % %SnowlineSlider.value
	%RockSlopeLabel.text = "Rock slope: %.0f°" % %RockSlopeSlider.value
	%SandlineLabel.text = "Sandline: %.1f m" % %SandlineSlider.value
	%WaterLabel.text = "Water level: %.1f m" % %WaterSlider.value
	_erode_slider.value_changed.connect(func(v): _erode_label.text = "Erosion: %d droplets" % int(v))
	_foliage_slider.value_changed.connect(func(v): _foliage_label.text = "Foliage: %d" % int(v))
	_erode_label.text = "Erosion: %d droplets" % int(_erode_slider.value)
	_foliage_label.text = "Foliage: %d" % int(_foliage_slider.value)
	_on_sliders(0.0)


func set_undo_state(can_undo: bool, can_redo: bool) -> void:
	%UndoBtn.disabled = not can_undo
	%RedoBtn.disabled = not can_redo


func set_brush(radius: float, strength: float) -> void:
	_radius_slider.value = radius
	_strength_slider.value = strength


func _on_mode_selected(i: int) -> void:
	if i < 6:
		sculpt_mode_changed.emit(i)
	elif i < 14:
		sculpt_mode_changed.emit(TerrainOps.Mode.PAINT)
		paint_layer_changed.emit(i - 6)
	else:
		special_mode_selected.emit(i - 14)


func _on_sliders(_v: float) -> void:
	_radius_label.text = "Radius: %.1f m" % _radius_slider.value
	_strength_label.text = "Strength: %.2f" % _strength_slider.value
	_falloff_label.text = "Falloff: %.2f" % _falloff_slider.value
	brush_changed.emit(_radius_slider.value, _strength_slider.value, _falloff_slider.value)
