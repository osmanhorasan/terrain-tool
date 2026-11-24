extends SceneTree
func _init():
	var cf := ConfigFile.new()
	var err := cf.load("res://export_presets.cfg")
	print("err=", err, " sections=", cf.get_sections())
	quit()
