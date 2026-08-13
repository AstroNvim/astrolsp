.PHONY: test test-prepare test-prepare-ci test-clear test-update-deps test-unit test-semantic test-semantic-attach test-semantic-lifecycle test-unit-environment test-unit-config test-unit-init test-unit-file-operations test-unit-toggles test-unit-health test-contracts test-fingerprint

TEST_TARGETS := test test-unit test-semantic test-semantic-attach test-semantic-lifecycle test-unit-environment test-unit-config test-unit-init test-unit-file-operations test-unit-toggles test-unit-health test-contracts

$(TEST_TARGETS): test-prepare

test:
	@nvim -l tests/minit.lua --minitest tests/unit/*.lua tests/semantic/*.lua

test-unit:
	@nvim -l tests/minit.lua --minitest tests/unit/*.lua

test-semantic:
	@nvim -l tests/minit.lua --minitest tests/semantic/*.lua

test-semantic-attach:
	@nvim -l tests/minit.lua --minitest tests/semantic/attach_spec.lua

test-semantic-lifecycle:
	@nvim -l tests/minit.lua --minitest tests/semantic/init_spec.lua

test-unit-environment:
	@nvim -l tests/minit.lua --minitest tests/unit/test_environment_spec.lua tests/unit/unit_helpers_spec.lua tests/unit/helpers_spec.lua

test-unit-config:
	@nvim -l tests/minit.lua --minitest tests/unit/config_spec.lua

test-unit-init:
	@nvim -l tests/minit.lua --minitest tests/unit/init_spec.lua

test-unit-file-operations:
	@nvim -l tests/minit.lua --minitest tests/unit/file_operations_spec.lua

test-unit-toggles:
	@nvim -l tests/minit.lua --minitest tests/unit/toggles_spec.lua

test-unit-health:
	@nvim -l tests/minit.lua --minitest tests/unit/health_spec.lua

test-contracts:
	@nvim -l tests/minit.lua --minitest tests/unit/contracts_spec.lua

test-prepare:
	@nvim -l tests/bootstrap.lua

test-prepare-ci:
	@nvim -l tests/prepare_test_environment.lua

test-clear:
	@nvim -l tests/clear_test_environment.lua

test-update-deps:
	@$(MAKE) test-clear
	@$(MAKE) test-prepare

test-fingerprint:
	@nvim -l tests/print_fingerprint.lua
