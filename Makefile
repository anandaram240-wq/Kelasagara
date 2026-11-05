# KELASAGARA BIOMATCH STAGE S6 AUTOMATION MAKEFILE

.PHONY: all analyze test-backend test-client integrity secret-scan drift-watch report replicate

all: integrity secret-scan drift-watch test-backend analyze report

test-backend:
	cd backend && npm run build && node --test --test-concurrency=1 dist/tests/*.test.js

test-client:
	flutter test test/formal_contracts_test.dart test/gps_quality_engine_test.dart test/polyline_regression_test.dart

integrity:
	python3 tools/test_integrity.py

secret-scan:
	python3 tools/secret_scan.py

drift-watch:
	python3 tools/spec_drift_watch.py

analyze:
	python3 analysis/runner.py

report:
	python3 scripts/render_report.py
	python3 scripts/no_orphan_numbers.py

replicate: integrity secret-scan drift-watch analyze report
	@echo "=== REPLICATION VERIFIED ==="
