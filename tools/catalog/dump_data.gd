extends SceneTree
## Writes the roster numbers in scripts/data.gd to JSON for tools/catalog/build_roster.py.
##   $G --headless --path . --script tools/catalog/dump_data.gd -- [--out=screenshots/catalog/roster_data.json]

const Data := preload("res://scripts/data.gd")


func _initialize() -> void:
	var out := "res://screenshots/catalog/roster_data.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = "res://" + arg.trim_prefix("--out=")
	var factions := []
	for f in Data.FACTIONS:
		var d: Dictionary = f.duplicate(true)
		d["color"] = (f["color"] as Color).to_html(false)
		factions.append(d)
	var dump := {
		"factions": factions,
		"structures": Data.STRUCTURES,
		"units": Data.UNITS,
		"techs": Data.TECHS,
		"abilities": Data.ABILITIES,
		"constants": {"pop_cap": Data.POP_CAP, "thrall_decay": Data.THRALL_DECAY, "host_range": Data.HOST_RANGE,
			"infect_chance": Data.INFECT_CHANCE, "infect_stalker": Data.INFECT_STALKER, "infect_dose": Data.INFECT_DOSE},
	}
	var fa := FileAccess.open(out, FileAccess.WRITE)
	fa.store_string(JSON.stringify(dump, " ", false))
	fa.close()
	print("wrote " + ProjectSettings.globalize_path(out))
	quit()
