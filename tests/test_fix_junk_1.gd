extends TestCase
## What ships in the repository and the browser pack is only what the game can reach. The art,
## model and audio loaders build every path from a catalogue id, a sound cue or a crew line, so a
## file whose name matches none of them is dead weight that every clone and import carries.

const SOUND := preload("res://scripts/ui/sound_fx.gd")


func _files(dir: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	for name: String in DirAccess.get_files_at(dir):
		if name.get_extension() == ext:
			out.append(name)
	return out


## The catalogue id an art file is named after, and whether that id is in the catalogue under
## its own name (a retired id that DataDB maps onto its replacement does not count: the loaders
## ask for the replacement's art).
func _platform_listed(id: String) -> bool:
	var spec := DataDB.platform(id)
	return spec != null and spec.id == id


func _weapon_listed(id: String) -> bool:
	var spec := DataDB.weapon(id)
	return spec != null and spec.id == id


func test_every_model_belongs_to_a_platform_or_weapon_in_the_catalogue() -> void:
	var models := _files("res://assets/models", "glb")
	assert_true(models.size() > 100, "the model library is found")
	for name: String in models:
		var id := name.get_basename()
		assert_true(_platform_listed(id) or _weapon_listed(id), "%s is the model of a catalogue platform or weapon" % name)


func test_every_render_belongs_to_a_catalogue_entry_of_its_kind() -> void:
	var suffix := RegEx.create_from_string("_(beauty|thumb|plan|profile)$")
	var platforms := _files("res://assets/platforms", "png")
	var weapons := _files("res://assets/weapons", "png")
	assert_true(platforms.size() > 100 and weapons.size() > 100, "the render libraries are found")
	for name: String in platforms:
		var id := suffix.sub(name.get_basename(), "")
		assert_true(_platform_listed(id), "%s is the render of a catalogue platform" % name)
	for name: String in weapons:
		var id := suffix.sub(name.get_basename(), "")
		assert_true(_weapon_listed(id), "%s is the render of a catalogue weapon" % name)


func test_every_sound_file_is_a_cue_the_game_plays() -> void:
	var take := RegEx.create_from_string("^(.+)_(\\d+)$")
	for name: String in _files("res://assets/audio/effects", "ogg"):
		var m := take.search(name.get_basename())
		assert_true(m != null, "%s is a numbered take" % name)
		if m == null:
			continue
		var cue := m.get_string(1)
		var cues: Array = SOUND.CUE_DB.keys().filter(func(c: String) -> bool: return cue == ("complete" if c in ["victory", "defeat"] else c))
		assert_true(not cues.is_empty(), "%s belongs to a sound cue" % name)
		if not cues.is_empty():
			assert_true(int(m.get_string(2)) < int(SOUND.VARIANTS.get(cues[0], 1)), "%s is a take the cue rotates through" % name)
	for name: String in _files("res://assets/audio/ambient", "ogg"):
		var bed := name.get_basename()
		assert_true(bed == "sea" or SOUND.HUM_DB.has(bed), "%s is the sea or a machinery bed" % name)
	var phrases: Dictionary = CrewVoice.load_phrases()
	for profile: String in CrewVoice.PROFILES:
		for name: String in _files("res://assets/audio/crew/" + profile, "ogg"):
			var m := take.search(name.get_basename())
			assert_true(m != null and phrases.has(m.get_string(1)), "%s/%s is a crew event" % [profile, name])
			if m != null and phrases.has(m.get_string(1)):
				assert_true(int(m.get_string(2)) < (phrases[m.get_string(1)] as Array).size(), "%s/%s is a line the crew can speak" % [profile, name])


## A tool nobody can find is a tool nobody runs, and one that stops working without anyone
## noticing: every entry point under tools/ is run by CI, listed in DEVELOPING.md or a README, or
## driven by another tool by path.
func test_every_tool_entry_point_is_run_by_ci_documented_or_driven_by_another_tool() -> void:
	var named := ""
	for doc: String in [".github/workflows/tests.yml", "DEVELOPING.md", "README.md", "assets/README.md", "assets/audio/README.md"]:
		named += FileAccess.get_file_as_string("res://" + doc)
	assert_true(named.contains("tools/passage_playtest.gd"), "the workflow and developer guide are readable")
	var entries: Array[String] = []
	for dir: String in ["tools", "tools/audio"]:
		for name: String in DirAccess.get_files_at("res://" + dir):
			if name.get_extension() in ["gd", "py"]:
				entries.append(dir + "/" + name)
	var sources := {}
	for path: String in entries:
		sources[path] = FileAccess.get_file_as_string("res://" + path)
	for path: String in entries:
		var used := named.contains(path)
		for other: String in entries:
			if not used and other != path and (sources[other] as String).contains(path):
				used = true
		assert_true(used, "%s is run by CI, documented, or driven by another tool" % path)


func _local_links(text: String) -> Array[String]:
	var out: Array[String] = []
	var link := RegEx.create_from_string("\\]\\(([^)#\\s]+)(#[^)]*)?\\)|(?:src|href)=\"([^\"#]+)\"")
	for m: RegExMatch in link.search_all(text):
		var target := m.get_string(1) if m.get_string(1) != "" else m.get_string(3)
		if target.contains("://") or target.begins_with("mailto:") or target == "./":
			continue
		out.append(target)
	return out


## The reading pages: the top-level notes, the notes kept under docs/ and the landing page.
func _pages() -> Array[String]:
	var out: Array[String] = []
	for name: String in DirAccess.get_files_at("res://"):
		if name.get_extension() == "md":
			out.append(name)
	for name: String in DirAccess.get_files_at("res://docs"):
		if name.get_extension() in ["md", "html"]:
			out.append("docs/" + name)
	return out


func test_every_link_in_the_notes_and_landing_page_reaches_a_file() -> void:
	var pages := _pages()
	assert_true(pages.has("README.md") and pages.has("docs/index.html"), "the reading pages are found")
	for page: String in pages:
		for target: String in _local_links(FileAccess.get_file_as_string("res://" + page)):
			var path := (page.get_base_dir() + "/" + target).simplify_path().trim_prefix("/")
			if target.ends_with("/"):
				assert_true(DirAccess.dir_exists_absolute("res://" + path), "%s links to the folder %s" % [page, target])
			else:
				assert_true(FileAccess.file_exists("res://" + path), "%s links to %s, which exists" % [page, target])


## docs/ is the published page, its fonts and pictures, and the few notes that still describe the
## game or that the catalogue cites as its sources; dated milestone records live in git history.
func test_docs_holds_only_what_a_page_or_the_catalogue_reaches() -> void:
	var reached := {"docs/index.html": true}
	for page: String in _pages():
		for target: String in _local_links(FileAccess.get_file_as_string("res://" + page)):
			reached[(page.get_base_dir() + "/" + target).simplify_path().trim_prefix("/")] = true
	var cited := RegEx.create_from_string("docs/[A-Za-z0-9_.-]+\\.md")
	for dir: String in ["res://data/platforms/aircraft", "res://data/platforms/cold_war", "res://data/platforms/helicopters", "res://data/platforms/submarines", "res://data/platforms/surface", "res://data/platforms/theatres", "res://data/sensors", "res://data/weapons"]:
		for name: String in DirAccess.get_files_at(dir):
			for m: RegExMatch in cited.search_all(FileAccess.get_file_as_string(dir + "/" + name)):
				reached[m.get_string()] = true
	var listed := 0
	for name: String in DirAccess.get_files_at("res://docs"):
		if name.begins_with("."):
			continue
		listed += 1
		assert_true(reached.has("docs/" + name), "docs/%s is reached from a page or cited by the catalogue" % name)
	assert_true(listed > 3, "docs/ is found")


func _export_excludes() -> PackedStringArray:
	var config := ConfigFile.new()
	assert_eq(config.load("res://export_presets.cfg"), OK, "the export presets load")
	assert_eq(config.get_value("preset.0", "export_filter", ""), "all_resources", "the browser pack starts from every resource")
	return str(config.get_value("preset.0", "exclude_filter", "")).split(",", false)


func _excluded(path: String, excludes: PackedStringArray) -> bool:
	for pattern: String in excludes:
		if path.matchn(pattern) or path.get_file().matchn(pattern):
			return true
	return false


## The browser pack carries the game, not the suites that drive it. A suite the harness loads by
## path only under its own flag stays out; one a shipped script names by class or preloads must
## stay in, or the shipped script would not compile in the browser.
func test_the_browser_pack_leaves_out_the_flag_only_suites_and_keeps_what_shipped_code_names() -> void:
	var excludes := _export_excludes()
	for suite: String in ["scripts/core/fleet_workshop_smoke.gd", "scripts/core/weapon_control_smoke.gd"]:
		assert_true(_excluded(suite, excludes), "%s, loaded only under its smoke flag, is not packed for players" % suite)
	var scripts: Array[String] = []
	var dirs: Array[String] = ["scripts"]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		for sub: String in DirAccess.get_directories_at("res://" + dir):
			dirs.append(dir + "/" + sub)
		for name: String in DirAccess.get_files_at("res://" + dir):
			if name.get_extension() == "gd":
				scripts.append(dir + "/" + name)
	var class_of := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
	var left_out := {}
	for path: String in scripts:
		if _excluded(path, excludes):
			var m := class_of.search(FileAccess.get_file_as_string("res://" + path))
			left_out[path] = m.get_string(1) if m != null else ""
	for path: String in scripts:
		if _excluded(path, excludes):
			continue
		var source := FileAccess.get_file_as_string("res://" + path)
		for gone: String in left_out:
			assert_true(not source.contains("preload(\"res://%s\")" % gone), "%s preloads %s, which the pack leaves out" % [path, gone])
			var named: String = left_out[gone]
			if named != "":
				assert_true(not RegEx.create_from_string("\\b%s\\b" % named).search(source), "%s names %s, which the pack leaves out" % [path, named])
