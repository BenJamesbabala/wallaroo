# include root makefile
ifndef ROOT_MAKEFILE_MK
include ../../../Makefile
endif

# prevent rules from being evaluated/included multiple times
ifndef $(abspath $(lastword $(MAKEFILE_LIST)))_MK
$(abspath $(lastword $(MAKEFILE_LIST)))_MK := 1

# uncomment to disable generate test related targets in this directory
#TEST_TARGET := false

# uncomment to disable generate pony related targets (build/test/clean) for pony sources in this directory
PONY_TARGET := false

# uncomment to disable generate exs related targets (build/test/clean) for elixir sources in this directory
EXS_TARGET := false

# uncomment to disable generate docker related targets (build/push) for Dockerfile in this directory
DOCKER_TARGET := false

# uncomment to disable generate recursing into Makefiles of subdirectories
RECURSE_SUBMAKEFILES := false

CORRECTNESS_TESTS_PATH := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
CUSTOM_PATH += :$(SEQUENCE_WINDOW_PATH):$(VALIDATOR_PATH):$(EXTERNAL_SENDER_PATH)

build-testing-correctness-tests: build-testing-correctness-apps-sequence_window
build-testing-correctness-tests: build-testing-tools-external_sender
build-testing-correctness-tests: build-machida
test-testing-correctness-tests: build-testing-correctness-tests
test-testing-correctness-tests: correctness_tests

# standard rules generation makefile
include $(rules_mk_path)

correctness_tests:
	cd $(CORRECTNESS_TESTS_PATH) && \
	python2 -m pytest correctness_tests.py --verbose

endif
