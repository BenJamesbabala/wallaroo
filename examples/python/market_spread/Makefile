# include root makefile
ifndef ROOT_MAKEFILE_MK
include ../../../Makefile
endif

# prevent rules from being evaluated/included multiple times
ifndef $(abspath $(lastword $(MAKEFILE_LIST)))_MK
$(abspath $(lastword $(MAKEFILE_LIST)))_MK := 1

# uncomment to disable generate test related targets in this directory
TEST_TARGET := false

# uncomment to disable generate pony related targets (build/test/clean) for pony sources in this directory
PONY_TARGET := false

# uncomment to disable generate exs related targets (build/test/clean) for elixir sources in this directory
EXS_TARGET := false

# uncomment to disable generate docker related targets (build/push) for Dockerfile in this directory
DOCKER_TARGET := false

# uncomment to disable generate recursing into Makefiles of subdirectories
RECURSE_SUBMAKEFILES := false

MARKET_SPREAD_PY_PATH := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# standard rules generation makefile
include $(rules_mk_path)

build-examples-python-market_spread: build-machida
test-examples-python-market_spread: build-examples-python-market_spread

test-examples-python-market_spread: market_spread_py_test

market_spread_py_test:
	cd $(MARKET_SPREAD_PY_PATH) && \
	python _test/gen.py && \
	integration_test --framed-file-sender _market.txt 1 \
		--framed-file-sender _orders.txt 0 \
	  --log-level error \
		--command 'machida --application-module market_spread' \
		--validation-cmd 'python _test/validate.py --expected $(MARKET_SPREAD_PY_PATH)/_expected.txt --output' \
		--output 'received.txt' \
		--workers 5 \
		--sources 2 \
		--sink-expect 1000

clean-examples-python-market_spread: market_spread_py_clean

market_spread_py_clean:
	$(QUIET)rm -f $(MARKET_SPREAD_PY_PATH)/received.txt $(MARKET_SPREAD_PY_PATH)/_expected.txt $(MARKET_SPREAD_PY_PATH)/_orders.txt $(MARKET_SPREAD_PY_PATH)/_market.txt

endif
