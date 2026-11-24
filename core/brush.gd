class_name TerrainBrush
extends RefCounted

var radius := 6.0 # meters
var strength := 0.4 # 0..1
var falloff := 0.5 # 0 = hard edge, 1 = soft dome


## Weight at a given world-space distance from the brush center.
func weight(dist: float) -> float:
	if dist >= radius:
		return 0.0
	var t := 1.0 - dist / radius
	return pow(t, lerpf(0.2, 4.0, falloff)) * strength
