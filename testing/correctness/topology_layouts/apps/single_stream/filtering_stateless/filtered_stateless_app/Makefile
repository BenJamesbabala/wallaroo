# include root makefile
ifndef ROOT_MAKEFILE_MK
include ../../../../../../../Makefile
endif

# prevent rules from being evaluated/included multiple times
ifndef $(abspath $(lastword $(MAKEFILE_LIST)))_MK
$(abspath $(lastword $(MAKEFILE_LIST)))_MK := 1

# uncomment to disable generate test related targets in this directory
TEST_TARGET := false

# uncomment to disable generate pony related targets (build/test/clean) for pony sources in this directory
#PONY_TARGET := false

# uncomment to disable generate exs related targets (build/test/clean) for elixir sources in this directory
EXS_TARGET := false

# uncomment to disable generate docker related targets (build/push) for Dockerfile in this directory
DOCKER_TARGET := false

# uncomment to disable generate recursing into Makefiles of subdirectories
# RECURSE_SUBMAKEFILES := false

SINGLE_STREAM_FILTERING_STATELESS_FILTERERED_STATELESS_APP_PATH := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# standard rules generation makefile
include $(rules_mk_path)


test-testing-correctness-topology_layouts-apps-single_stream-filtering_stateless-filtered_stateless_app: single_worker_filtering_stateless_filtered_stateless_app_test

single_worker_filtering_stateless_filtered_stateless_app_test:
	cd $(SINGLE_STREAM_FILTERING_STATELESS_FILTERERED_STATELESS_APP_PATH) && \
	integration_test \
	--framed-file-sender ../doubled_data_gen/_test.msg \
	--validation-cmp \
	--expected-file ../doubled_data_gen/_expected.msg \
	--log-level error \
	--command './filtered_stateless_app' \
	--sink-expect 50

test-testing-correctness-topology_layouts-apps-single_stream-filtering_stateless-filtered_stateless_app: two_worker_single_worker_filtering_stateless_filtered_stateless_app_test

two_worker_single_worker_filtering_stateless_filtered_stateless_app_test:
	rm -f /tmp/filtered_stateless_app*
	cd $(SINGLE_STREAM_FILTERING_STATELESS_FILTERERED_STATELESS_APP_PATH) && \
	integration_test \
	--framed-file-sender ../doubled_data_gen/_test.msg \
	--workers 2 \
	--validation-cmp \
	--expected-file ../doubled_data_gen/_expected.msg \
	--log-level error \
	--command './filtered_stateless_app' \
	--sink-expect 50

test-testing-correctness-topology_layouts-apps-single_stream-filtering_stateless-filtered_stateless_app: three_worker_single_worker_filtering_stateless_filtered_stateless_app_test

three_worker_single_worker_filtering_stateless_filtered_stateless_app_test:
	rm -f /tmp/filtered_stateless_app*
	cd $(SINGLE_STREAM_FILTERING_STATELESS_FILTERERED_STATELESS_APP_PATH) && \
	integration_test \
	--framed-file-sender ../doubled_data_gen/_test.msg \
	--workers 3 \
	--validation-cmp \
	--expected-file ../doubled_data_gen/_expected.msg \
	--log-level error \
	--command './filtered_stateless_app' \
	--sink-expect 50

# end of prevent rules from being evaluated/included multiple times
endif
