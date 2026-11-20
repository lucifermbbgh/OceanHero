extends SceneTree
func _init():
	await create_timer(1.0).timeout
	var dr = root.get_node_or_null("DataRegistry")
	print("DR=", dr != null)
	if dr != null:
		print("GEAR_COUNT=", dr.gear.size())
		print("HAS_PLATE=", dr.get_gear(&"plate_iron") != null)
	var f := FileAccess.open("res://data/manifest.txt", FileAccess.READ)
	var n := 0
	while not f.eof_reached():
		var l := f.get_line()
		if l.begins_with("res://data/gear/"):
			n += 1
	print("MANIFEST_GEAR=", n)
	quit()
