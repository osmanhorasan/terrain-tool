class_name TerrainHistory
extends RefCounted

## Snapshot-based undo/redo. One snapshot per brush stroke / destructive action.

const MAX_DEPTH := 32

var _undo: Array = []
var _redo: Array = []


func push(hm_img: Image, splat_img: Image) -> void:
	_undo.push_back([hm_img.duplicate(), splat_img.duplicate()])
	if _undo.size() > MAX_DEPTH:
		_undo.pop_front()
	_redo.clear()


func undo(hm_img: Image, splat_img: Image) -> bool:
	if _undo.is_empty():
		return false
	_redo.push_back([hm_img.duplicate(), splat_img.duplicate()])
	var s: Array = _undo.pop_back()
	hm_img.copy_from(s[0])
	splat_img.copy_from(s[1])
	return true


func redo(hm_img: Image, splat_img: Image) -> bool:
	if _redo.is_empty():
		return false
	_undo.push_back([hm_img.duplicate(), splat_img.duplicate()])
	var s: Array = _redo.pop_back()
	hm_img.copy_from(s[0])
	splat_img.copy_from(s[1])
	return true


func clear() -> void:
	_undo.clear()
	_redo.clear()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()
