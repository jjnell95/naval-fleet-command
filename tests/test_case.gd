class_name TestCase
extends RefCounted
## Minimal assertion base for headless tests. Methods named test_* are run by run_tests.gd.

var failures: Array[String] = []


func assert_true(cond: bool, msg := "") -> void:
	if not cond:
		failures.append("assert_true: %s" % msg)


func assert_eq(a, b, msg := "") -> void:
	if a != b:
		failures.append("assert_eq: %s != %s %s" % [a, b, msg])


func assert_near(a: float, b: float, tol := 1e-4, msg := "") -> void:
	if absf(a - b) > tol:
		failures.append("assert_near: %s vs %s (tol %s) %s" % [a, b, tol, msg])
