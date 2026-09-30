extends TestCase
## Deliberately broken, run only by the runner's isolated self-check.
func test_exception_before_assertion() -> void:
	var missing: Object = null
	missing.call("example")
	assert_true(true)
