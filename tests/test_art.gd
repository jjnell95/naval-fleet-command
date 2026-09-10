extends TestCase
## The rendered recognition art is built from data/platforms by tools/blender; these tests keep
## the two in step so a new platform cannot ship without a picture, and check the loader's
## contract that the display code relies on.


func test_every_platform_has_profile_and_plan_art() -> void:
	var specs := DataDB.all_platforms()
	assert_true(specs.size() >= 30, "platform catalogue loads")
	for spec: PlatformSpec in specs:
		var profile := PlatformArt.profile(spec.id)
		var plan := PlatformArt.plan(spec.id)
		assert_true(profile != null, spec.id + " has a profile render")
		assert_true(plan != null, spec.id + " has a plan render")
		if plan != null:
			assert_true(plan.get_width() >= 8 and plan.get_height() >= 8, spec.id + " plan has a usable size")
		if profile != null:
			assert_true(profile.get_width() > profile.get_height(), spec.id + " profile is landscape")


func test_plan_art_is_landscape_for_hulls_and_scaled_from_width() -> void:
	# A ship's plan is far longer than it is wide; the map divides the real length by the
	# texture width times the frame margin, so that ratio must hold for every hull.
	for spec: PlatformSpec in DataDB.all_platforms():
		if spec.domain != "surface" and spec.domain != "subsurface":
			continue
		var plan := PlatformArt.plan(spec.id)
		if plan == null:
			continue
		assert_true(plan.get_width() > plan.get_height() * 2, spec.id + " plan is a long hull")
	assert_near(PlatformArt.PLAN_MARGIN, 1.10, 1e-6, "frame margin matches the Blender build")


func test_missing_art_returns_null_and_is_cached() -> void:
	assert_true(PlatformArt.profile("no_such_platform") == null, "unknown id has no profile")
	assert_true(PlatformArt.plan("no_such_platform") == null, "unknown id has no plan")
	assert_true(PlatformArt.profile("no_such_platform") == null, "second lookup is still null")
