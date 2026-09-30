"""Prove the real headless runner fails on a runtime exception before any assertion."""
import subprocess, sys
result = subprocess.run([sys.argv[1], "--headless", "--path", ".", "--script", "tests/run_tests.gd", "--", "--self-test-runtime-error"], capture_output=True, text=True, timeout=60)
log = result.stdout + result.stderr
if result.returncode != 1 or "FAIL  runtime_error.gd::test_exception_before_assertion" not in log or "1 tests, 1 failed" not in log or "Unexpected engine error:" not in log:
    print(log)
    raise SystemExit("Runner self-check did not detect the intended runtime exception")
print("PASS: runtime exception before assertions makes the real runner fail")
