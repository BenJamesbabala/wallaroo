# Based on:
# https://mischasan.wordpress.com/2013/03/30/non-recursive-make-gmake-part-1-the-basic-gnumakefile-layouts/
# https://github.com/mischasan/aho-corasick/blob/master/rules.mk
# https://github.com/dmoulding/boilermake/blob/master/Makefile
#
# With optimizations from:
# http://www.oreilly.com/openbook/make3/book/ch12.pdf
#
# More advanced functionality should likely use:
# http://gmsl.sourceforge.net/

# detemine makefile that included this one and it's path
PREV_MAKEFILE := $(word $(words $(MAKEFILE_LIST)),x $(MAKEFILE_LIST))
PREV_PATH := $(dir $(PREV_MAKEFILE))

# prevent rules from being evaluated/included multiple times
ifndef RULES_MK
RULES_MK := 1

# path of rules.mk file
RULES_MK_PATH := $(dir $(lastword $(MAKEFILE_LIST)))

# path of original makefile
ROOT_MAKEFILE := $(word 1, $(MAKEFILE_LIST))
ROOT_PATH := $(dir $(ROOT_MAKEFILE))

# if debug shell command output requested
ifdef DEBUG_SHELL
 SHELL = /bin/sh -x
endif

# if verbose output not requested
ifndef VERBOSE
 QUIET := @
endif

# set wallaroo project directory
wallaroo_dir := $(RULES_MK_PATH)
abs_wallaroo_dir := $(abspath $(wallaroo_dir))
wallaroo_path := $(abs_wallaroo_dir)

# Set global path variables
integration_path := $(wallaroo_path)/testing/tools
integration_bin_path := $(integration_path)/integration
wallaroo_lib :=  $(wallaroo_path)/lib
wallaroo_python_path := $(wallaroo_path)/machida
machida_bin_path := $(wallaroo_path)/machida/build

EMPTY :=
SPACE := $(EMPTY) $(EMPTY)

export PYTHONPATH = .:$(integration_path):$(wallaroo_python_path):$(SEQUENCE_WINDOW_PYTHON_PATH)
ORIGNAL_PATH := $(PATH)
export PATH = $(ORIGNAL_PATH):$(subst :$(SPACE),:,$(subst $(SPACE):,:,$(strip $(CUSTOM_PATH))))
CUSTOM_PATH = $(integration_bin_path):$(machida_bin_path)

# initialize default for some normal targets and variables
build-wallarooroot-all :=
test-wallarooroot-all :=
clean-wallarooroot-all :=
build-docker-wallarooroot-all :=
push-docker-wallarooroot-all :=

ifndef TEST_TARGET
  TEST_TARGET :=
endif

ifndef PONY_TARGET
  PONY_TARGET :=
endif

ifndef PONYC_TARGET
  PONYC_TARGET :=
endif

ifndef DOCKER_TARGET
  DOCKER_TARGET :=
endif

ifndef EXS_TARGET
  EXS_TARGET :=
endif

ifndef RECURSE_SUBMAKEFILES
  RECURSE_SUBMAKEFILES :=
endif

ifndef ponyc_docker_args
  ponyc_docker_args :=
endif

ifndef monhub_docker_args
  monhub_docker_args :=
endif

ifndef quote
  quote :=
endif

ifndef ponyc_arch_args
  ponyc_arch_args :=
endif

# function to lazily initialize a variable on first use and to only evaluate the expression once
# see: http://www.oreilly.com/openbook/make3/book/ch10.pdf
# $(call lazy-init,variable-name,value)
define lazy-init
 $1 = $$(redefine-$1) $$($1)
 redefine-$1 = $$(eval $1 := $2)
endef

# how to get the latest ponyc tag
latest_ponyc_tag_src = $(shell curl -s \
  https://hub.docker.com/r/wallaroolabs/ponyc/tags/ | grep -o \
  'wallaroolabs-[0-9.-]*-' | sed 's/wallaroolabs-\([0-9.-]*\)-/\1/' \
  | sort -un | tail -n 1)# latest ponyc tag

# latest_ponyc_tag - a lazy init of latest_ponyc_tag (will only be evaluated if used)
$(eval \
  $(call lazy-init,latest_ponyc_tag,\
    $$(call latest_ponyc_tag_src)))

docker_image_version_src = $(shell git describe --tags --always)# Docker Image Tag to use

# docker_image_version_val - a lazy init of docker_image_version_val (will only be evaluated if used)
$(eval \
  $(call lazy-init,docker_image_version_val,\
    $$(call docker_image_version_src)))

DEBUG_SHELL ?= ## Debug shell commands?
VERBOSE ?= ## Print commands as they're executed?
docker_image_version ?= $(strip $(docker_image_version_val))## Docker Image Tag to use
docker_image_repo_host ?= docker.sendence.com:5043## Docker Repository to use
docker_image_repo ?= $(docker_image_repo_host)/sendence## Docker Repository to use
arch ?= native## Architecture to build for
in_docker ?= false## Whether already in docker or not (used by CI)
ponyc_tag ?= wallaroolabs-$(strip $(latest_ponyc_tag))-release## tag for ponyc docker to use
ponyc_runner ?= wallaroolabs/ponyc## ponyc docker image to use
debug ?= false## Use ponyc debug option (-d)
debug_arg :=# Final argument string for debug option
docker_host ?= $(DOCKER_HOST)## docker host to build/run containers on
ifeq ($(docker_host),)
  docker_host := unix:///var/run/docker.sock
endif
docker_host_arg := --host=$(docker_host)# docker host argument
dagon_docker_host ?= ## Dagon docker host arg (defaults to docker_host value)
dagon_in_docker ?= false## Run Dagon in a docker container
dagon_docker_repo ?= $(docker_image_repo)/dagon## Dagon docker repository url
dagon_notifier_docker_repo ?= $(docker_image_repo)/dagon-dagon-notifier## Dagon docker repository url
monhub_builder ?= monitoring-hub-builder
monhub_builder_tag ?= latest
unix_timestamp := $(shell date +%s) # unix timestamp for docker network name
demo_cluster_name ?= ## Name of demo cluster
demo_cluster_spot_pricing ?= true## Whether to use spot pricing or not for demo cluster
demo_to_run ?= dagon-identity## Name of demo dagon command to run
autoscale ?= on## Build with Autoscale or not
clustering ?= on## Build with Clustering or not
resilience ?= off## Build with Resilience or not

# validation of variable
ifdef autoscale
  ifeq (,$(filter $(autoscale),on off))
    $(error Unknown autoscale option "$(autoscale)". Valid values are "on off".)
  endif
endif

ifeq ($(autoscale),on)
  autoscale_arg := -D autoscale
endif

# validation of variable
ifdef clustering
  ifeq (,$(filter $(clustering),on off))
    $(error Unknown autoscale option "$(clustering)". Valid values are "on off".)
  endif
endif

ifeq ($(clustering),on)
  clustering_arg := -D clustering
endif

# validation of variable
ifdef resilience
  ifeq (,$(filter $(resilience),on off))
    $(error Unknown autoscale option "$(resilience)". Valid values are "on off".)
  endif
endif

ifeq ($(resilience),on)
  resilience_arg := -D resilience
endif

# validation of variable
ifdef dagon_in_docker
  ifeq (,$(filter $(dagon_in_docker),false true))
    $(error Unknown dagon_in_docker option "$(dagon_in_docker)". Valid values are "false true".)
  endif
endif

# validation of variable
ifdef demo_cluster_spot_pricing
  ifeq (,$(filter $(demo_cluster_spot_pricing),false true))
    $(error Unknown demo_cluster_spot_pricing option "$(demo_cluster_spot_pricing)". Valid values are "false true")
  endif
endif

# validation of variable
ifdef debug
  ifeq (,$(filter $(debug),false true))
    $(error Unknown debug option "$(debug)". Valid values are "false true")
  endif
endif

ifeq ($(dagon_docker_host),)
  dagon_docker_host := $(docker_host)
endif

ifeq ($(shell uname -s),Linux)
  extra_xargs_arg := -r
  docker_user_arg := -u `id -u`
  extra_awk_arg := \\
  host_ip_src = $(shell ifconfig `route -n | grep '^0.0.0.0' | awk '{print $$8}'` | egrep -o 'inet addr:[^ ]+' | awk -F: '{print $$2}')
  system_cpus := $(shell which cset > /dev/null && sudo cset set -l -r | grep '/system' | awk '{print $$2}')
  ifneq (,$(system_cpus))
    docker_cpu_arg := --cpuset-cpus $(system_cpus)
  endif
else
  host_ip_src = $(shell ifconfig `route -n get 0.0.0.0 2>/dev/null | awk '/interface: / {print $$2}'` | egrep -o 'inet [^ ]+' | awk '{print $$2}')
endif

# host_ip - a lazy init of host_ip (will only be evaluated if used)
$(eval \
  $(call lazy-init,host_ip,\
    $$(call host_ip_src)))

ifeq ($(debug),true)
  debug_arg := -d
endif

# validation of variable
ifdef arch
  ifeq (,$(filter $(arch),amd64 armhf native))
    $(error Unknown architecture "$(arch)". Valid values are "amd64 armhf native")
  endif
endif

# validation of variable
ifdef in_docker
  ifeq (,$(filter $(in_docker),false true))
    $(error Unknown in_docker option "$(in_docker)". Valid values are "false true")
  endif
endif

# additional ponyc arguments when building for armhf
ifeq ($(arch),armhf)
  ponyc_arch_args := --triple arm-unknown-linux-gnueabihf --link-arch armv7-a \
                       --linker arm-linux-gnueabihf-gcc
endif

# only set docker arguments if building for a non-native platform and not in docker
ifneq ($(arch),native)
  ifneq ($(in_docker),true)
    quote = '
    ponyc_docker_args = docker run --rm -i $(docker_user_arg) -v \
        $(abs_wallaroo_dir):$(abs_wallaroo_dir) $(docker_cpu_arg) \
        -v $(HOME)/.gitconfig:/.gitconfig \
        -v $(HOME)/.gitconfig:/root/.gitconfig \
        -v $(HOME)/.git-credential-cache:/root/.git-credential-cache \
        -v $(HOME)/.git-credential-cache:/.git-credential-cache \
        -w $(1) --entrypoint bash \
        $(ponyc_runner):$(ponyc_tag) -c $(quote)

    monhub_docker_args = docker run --rm -i -v \
        $(abs_wallaroo_dir):$(abs_wallaroo_dir) $(docker_cpu_arg) \
        -v $(HOME)/.gitconfig:/.gitconfig \
        -v $(HOME)/.gitconfig:/root/.gitconfig \
        -v $(HOME)/.git-credential-cache:/root/.git-credential-cache \
        -v $(HOME)/.git-credential-cache:/.git-credential-cache \
        -w $(1) --entrypoint bash \
        $(docker_image_repo_host)/$(monhub_builder):$(monhub_builder_tag) -c $(quote)
  endif
endif

# function call for compiling with ponyc and generating dependency info
define PONYC
  $(QUIET)cd $(1) && $(ponyc_docker_args) stable fetch \
    $(if $(filter $(ponyc_docker_args),docker),$(quote))
  $(QUIET)cd $(1) && $(ponyc_docker_args) stable env ponyc $(ponyc_arch_args) \
    $(debug_arg) $(autoscale_arg) $(clustering_arg) $(resilience_arg) \
    $(PONYCFLAGS) . $(if $(filter $(ponyc_docker_args),docker),$(quote))
  $(QUIET)cd $(1) && echo "$@: $(abspath $(1))/bundle.json" | tr '\n' ' ' > $(notdir $(abspath $(1:%/=%))).d
  $(QUIET)cd $(1) && $(ponyc_docker_args) stable env ponyc $(ponyc_arch_args) \
    $(debug_arg) $(autoscale_arg) $(clustering_arg) $(resilience_arg) \
    $(PONYCFLAGS) . --pass import --files $(if $(filter \
    $(ponyc_docker_args),docker),$(quote)) 2>/dev/null | grep -o "$(abs_wallaroo_dir).*.pony" \
    | awk 'BEGIN { a="" } {a=a$$1":\n"; printf "%s ",$$1} END {print "\n"a}' \
    >> $(notdir $(abspath $(1:%/=%))).d
  $(QUIET)cd $(1) && echo "$(abspath $(1))/bundle.json:" >> $(notdir $(abspath $(1:%/=%))).d
endef

# function call for compiling monhub projects
define MONHUBC
  $(QUIET)cd $(1) && $(monhub_docker_args) mix deps.get \
    $(if $(filter $(monhub_docker_args),docker),$(quote))
  $(QUIET)cd $(1) && $(monhub_docker_args) mix compile \
    $(if $(filter $(monhub_docker_args),docker),$(quote))
endef

# function call for compiling ui projects for release
define MONHUBR
  $(QUIET)cd $(1) && $(monhub_docker_args) MIX_ENV=prod mix deps.clean --all \
    $(if $(filter $(monhub_docker_args),docker),$(quote))
  $(QUIET)cd $(1) && $(monhub_docker_args) MIX_ENV=prod mix deps.get --only prod \
    $(if $(filter $(monhub_docker_args),docker),$(quote))
  $(QUIET)cd $(1) && $(monhub_docker_args) MIX_ENV=prod mix compile \
    $(if $(filter $(monhub_docker_args),docker),$(quote))
  $(QUIET)cd $(1) && $(monhub_docker_args) npm install \
    $(if $(filter $(monhub_docker_args),docker),$(quote))
  $(QUIET)cd $(1) && $(monhub_docker_args) npm run build:production \
    $(if $(filter $(monhub_docker_args),docker),$(quote))
  $(QUIET)cd $(1) && $(monhub_docker_args) MIX_ENV=prod mix phoenix.digest \
    $(if $(filter $(monhub_docker_args),docker),$(quote))
  $(QUIET)cd $(1) && $(monhub_docker_args) MIX_ENV=prod mix release.clean \
    $(if $(filter $(monhub_docker_args),docker),$(quote))
  $(QUIET)cd $(1) && $(monhub_docker_args) MIX_ENV=prod mix release \
    $(if $(filter $(monhub_docker_args),docker),$(quote))
endef

# rule to add a new dagon target
define RUN_DAGON
$(if $(filter $5,false true),,\
    $(error Unknown 'include in CI' option "$5"))
dagon-test: $(if $(filter $5,true),$1,)
dagon-docker-test: $(if $(filter $5,true),$(subst dagon-,dagon-docker-,$1),)
$(call RUN_DAGON_TARGET,$1,$2,$3,$4)
endef

# rule to add a new dagon spike target
define RUN_DAGON_SPIKE
$(if $(filter $5,false true),,\
    $(error Unknown 'include in CI' option "$5"))
dagon-spike-test: $(if $(filter $5,true),$1,)
dagon-docker-spike-test: $(if $(filter $5,true),$(subst dagon-,dagon-docker-,$1),)
$(call RUN_DAGON_TARGET,$1,$2,$3,$4)
endef

# rule to add a new dagon target
define RUN_DAGON_TARGET
$(if $(findstring dagon,$(word 1, $(subst -, ,$1))),,$(error Dagon tests must \
begin with 'dagon-'! Current test name '$(strip $1)' is invalid!))
.PHONY: $1 $(subst dagon-,dagon-docker-,$1)
$(subst dagon-,dagon-docker-,$1): dagon_use_docker=--docker=$$(if $$(custom_dagon_host),$$(custom_dagon_host),$(dagon_docker_host)) \
--docker-tag=$(docker_image_version) --docker-arch=$(if $(filter $(arch),native),amd64,$(arch))
$(subst dagon-,dagon-docker-,$1): dagon_config_file=$$(if $$(custom_dagon_config),$$(custom_dagon_config),$2)
$(subst dagon-,dagon-docker-,$1): dagon_timeout=$$(if $$(custom_dagon_timeout),$$(custom_dagon_timeout),$3)
$(subst dagon-,dagon-docker-,$1): dagon_phone_home=$$(if $$(custom_dagon_phone_home),$$(custom_dagon_phone_home),$$(if $$(filter $$(dagon_in_docker),true),dagon-$(strip $(unix_timestamp)),$(host_ip)):8080)
$(subst dagon-,dagon-docker-,$1): dagon_cmd=$$(if $$(filter $$(dagon_in_docker),true),\
docker --host=$$(if $$(custom_dagon_host),$$(custom_dagon_host),$(dagon_docker_host)) \
run -v $(abs_wallaroo_dir):$(abs_wallaroo_dir) -w $(abs_wallaroo_dir) \
-v /bin:/bin:ro -v /lib:/lib:ro -v /lib64:/lib64:ro -v /usr:/usr:ro -v /tmp:/tmp -w /tmp \
-it --name dagon-$(unix_timestamp) -h dagon-$(unix_timestamp) \
--net wallaroo-$(unix_timestamp) $(dagon_docker_repo).$(if $(filter $(arch),native),amd64,$(arch)):$(docker_image_version), \
cd $(abs_wallaroo_dir) && $(abs_wallaroo_dir:%/=%)/dagon/dagon)
$(subst dagon-,dagon-docker-,$1):
	$$(call run-dagon)
	$$(if $$(filter $$(dont_validate),true),,$4)
$1: dagon_config_file=$$(if $$(custom_dagon_config),$$(custom_dagon_config),$2)
$1: dagon_timeout=$$(if $$(custom_dagon_timeout),$$(custom_dagon_timeout),$3)
$1: dagon_phone_home=$$(if $$(custom_dagon_phone_home),$$(custom_dagon_phone_home),127.0.0.1:8080)
$1: dagon_cmd=$$(if $$(filter $$(dagon_in_docker),true),\
docker --host=$$(if $$(custom_dagon_host),$$(custom_dagon_host),$(dagon_docker_host)) \
run -v $(abs_wallaroo_dir):$(abs_wallaroo_dir) -w $(abs_wallaroo_dir) \
-v /bin:/bin:ro -v /lib:/lib:ro -v /lib64:/lib64:ro -v /usr:/usr:ro -v /tmp:/tmp -w /tmp \
-it --name dagon-$(unix_timestamp) -h dagon-$(unix_timestamp) \
--net wallaroo-$(unix_timestamp) $(dagon_docker_repo).$(if $(filter $(arch),native),amd64,$(arch)):$(docker_image_version), \
cd $(abs_wallaroo_dir) && $(abs_wallaroo_dir:%/=%)/dagon/dagon)
$1:
	$$(call run-dagon)
	$$(if $$(filter $$(dont_validate),true),,$4)
endef

# function call for running dagon
define run-dagon
  $(if $(dagon_use_docker),$(QUIET)docker --host=$(if $(custom_dagon_host),$(custom_dagon_host),$(dagon_docker_host)) \
network create wallaroo-$(unix_timestamp),)
  $(QUIET)$(dagon_cmd) --timeout=$(dagon_timeout) -f $(dagon_config_file) \
          -h $(dagon_phone_home) $(dagon_use_docker) --docker-network=wallaroo-$(unix_timestamp) $(dagon_extra_args)
endef

# function call for running dagon-notifier
define run-dagon-notifier
  $(QUIET)$(if $(filter $(dagon_in_docker),true),\
docker --host=$(if $(custom_dagon_host),$(custom_dagon_host),$(dagon_docker_host)) \
run --privileged -v $(abs_wallaroo_dir):$(abs_wallaroo_dir) -w $(abs_wallaroo_dir) \
-v /bin:/bin:ro -v /lib:/lib:ro -v /lib64:/lib64:ro -v /usr:/usr:ro -v /tmp:/tmp -w /tmp \
-it --name dagon-notifier-$(unix_timestamp) -h dagon-notifier-$(unix_timestamp) \
--net $(if $(custom_dagon_network),$(custom_dagon_network),wallaroo-$(unix_timestamp)) \
$(dagon_notifier_docker_repo).$(if $(filter $(arch),native),amd64,$(arch)):$(docker_image_version),\
cd $(abs_wallaroo_dir) && $(abs_wallaroo_dir:%/=%)/dagon/dagon-notifier/dagon-notifier) \
--dagon-addr=$(dagon_phone_home) --msg-type StartGilesSenders
endef

# rule to generate includes for makefiles in subdirs of first argument
define make-goal
$(eval MAKEDIRS := $(sort $(dir $(wildcard $(1:%/=%)/*/Makefile))))
$(eval MAKEFILES := $(sort $(wildcard $(1:%/=%)/*/Makefile)))
$(foreach mdir,$(MAKEDIRS),$(eval $(notdir $(mdir:%/=%)) := $(mdir)))
$(eval include $(MAKEFILES))
endef

# rule to generate targets for building actual pony executable including dependencies to relevant *.pony files so incremental builds work properly
define ponyc-goal
# include dependencies for already compiled executables
-include $(1:%/=%)/$(notdir $(abspath $(1:%/=%))).d
$(1:%/=%)/$(notdir $(abspath $(1:%/=%))):
	$$(call PONYC,$(abspath $(1:%/=%)))
endef

.PHONY: build-pony-all build-docker-pony-all push-docker-pony-all test-pony-all clean-pony-all

# rule to generate targets for build-* for devs to use
define pony-build-goal
build-pony-all: build-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
build-docker-pony-all: build-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
push-docker-pony-all: push-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
build-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all += build-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
build-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))): $(1:%/=%)/$(notdir $(abspath $(1:%/=%)))
.PHONY: build-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))) build-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))) push-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))) build-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all
endef

# rule to generate targets for test-* for devs to use
define pony-test-goal
test-pony-all: test-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
test-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all += test-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
test-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))): build-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
ifneq ($(TEST_TARGET),false)
	cd $(abspath $(1:%/=%)) && ./$(notdir $(abspath $(1:%/=%)))
endif
.PHONY: test-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))) test-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all
endef

# rule to generate targets for clean-* for devs to use
define pony-clean-goal
clean-pony-all: clean-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
clean-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all += clean-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
clean-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))):
	$(QUIET)rm -f $(abspath $1)/$(notdir $(abspath $(1:%/=%))) $(abspath $1)/$(notdir $(abspath $(1:%/=%))).o
	$(QUIET)rm -f $(abspath $1)/$(notdir $(abspath $(1:%/=%))).d
	$(QUIET)rm -rf $(abspath $1)/.deps
	$(QUIET)rm -rf $(abspath $1)/$(notdir $(abspath $(1:%/=%))).dSYM
.PHONY: clean-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))) clean-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all
endef

# rule to generate targets for building actual monhub executable including dependencies to relevant files so incremental builds work properly
define monhub-goal
$(1:%/=%)/../../_build/dev/lib/$(notdir $(abspath $(1:%/=%)))/ebin/$(notdir $(abspath $(1:%/=%))).app: $(shell find $(wildcard $(abspath $1)/config) $(wildcard $(abspath $1)/lib) $(wildcard $(abspath $1)/mix.exs) $(wildcard $(abspath $1)/priv) $(wildcard $(abspath $1)/web) $(wildcard $(abspath $1)/package.json) -type f)
	$$(call MONHUBC,$(abspath $(1:%/=%)))
endef

# rule to generate targets for building actual monhub executable including dependencies to relevant files so incremental builds work properly
define monhub-release-goal
$(1:%/=%)/rel/$(notdir $(abspath $(1:%/=%)))/bin/$(notdir $(abspath $(1:%/=%))): $(shell find $(wildcard $(abspath $1)/config) $(wildcard $(abspath $1)/lib) $(wildcard $(abspath $1)/mix.exs) $(wildcard $(abspath $1)/priv) $(wildcard $(abspath $1)/web) $(wildcard $(abspath $1)/package.json) -type f)
	$$(call MONHUBR,$(abspath $(1:%/=%)))
release-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))): monhub-arch-check $(1:%/=%)/rel/$(notdir $(abspath $(1:%/=%)))/bin/$(notdir $(abspath $(1:%/=%)))
release-monhub-all: release-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
.PHONY: release-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
endef

.PHONY: build-monhub-all build-docker-monhub-all push-docker-monhub-all test-monhub-all clean-monhub-all release-monhub-all

# rule to generate targets for build-* for devs to use
define monhub-build-goal
build-monhub-all: build-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
build-docker-monhub-all: build-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
push-docker-monhub-all: push-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
build-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all += build-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
build-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))): $(1:%/=%)/../../_build/dev/lib/$(notdir $(abspath $(1:%/=%)))/ebin/$(notdir $(abspath $(1:%/=%))).app
.PHONY: build-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))) build-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))) push-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))) build-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all
endef

# rule to generate targets for test-* for devs to use
define monhub-test-goal
test-monhub-all: test-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
test-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all += test-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
test-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))): build-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
ifneq ($(TEST_TARGET),false)
	cd $(abspath $(1:%/=%)) && mix test
endif
.PHONY: test-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))) test-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all
endef

# rule to generate targets for clean-* for devs to use
define monhub-clean-goal
clean-monhub-all: clean-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
clean-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all += clean-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
clean-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))):
	$(QUIET)rm -rf $(abspath $1)/rel
	$(QUIET)rm -rf $(abspath $1)/node_modules
	$(QUIET)rm -rf $(abspath $1)/../../_build
.PHONY: clean-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))) clean-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all
endef

# rule to generate targets for build-docker-* for devs to use
define build-docker-goal
build-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all += build-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
build-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))): docker-arch-check $(if $(wildcard $(PREV_PATH)/package.json),release-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))),)
	docker $(docker_host_arg) build -t \
          $(docker_image_repo)/$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))).$(arch):$(docker_image_version) \
          $(abspath $1)
.PHONY: build-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all build-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
endef

# rule to generate targets for push-docker-* for devs to use
define push-docker-goal
push-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all += push-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
push-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))): build-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
	docker $(docker_host_arg) push \
          $(docker_image_repo)/$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1))).$(arch):$(docker_image_version)
.PHONY: push-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all push-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))
endef

# rule to generate targets for *-all for devs to use
define subdir-goal
$(eval MY_TARGET_SUFFIX := $(if $(filter $(abs_wallaroo_dir),$(abspath $1)),wallarooroot-all,$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all))

$(eval build-$(MY_TARGET_SUFFIX:%-all=%):)
$(eval test-$(MY_TARGET_SUFFIX:%-all=%):)
$(eval clean-$(MY_TARGET_SUFFIX:%-all=%):)
$(eval build-$(MY_TARGET_SUFFIX): build-$(MY_TARGET_SUFFIX:%-all=%) $(build-$(MY_TARGET_SUFFIX)))
$(eval test-$(MY_TARGET_SUFFIX): test-$(MY_TARGET_SUFFIX:%-all=%) $(test-$(MY_TARGET_SUFFIX)))
$(eval clean-$(MY_TARGET_SUFFIX): clean-$(MY_TARGET_SUFFIX:%-all=%) $(clean-$(MY_TARGET_SUFFIX)))

$(eval build-docker-$(MY_TARGET_SUFFIX): $(build-docker-$(MY_TARGET_SUFFIX)))
$(eval push-docker-$(MY_TARGET_SUFFIX): $(push-docker-$(MY_TARGET_SUFFIX)))

.PHONY: build-$(MY_TARGET_SUFFIX) test-$(MY_TARGET_SUFFIX) clean-$(MY_TARGET_SUFFIX) build-docker-$(MY_TARGET_SUFFIX) push-docker-$(MY_TARGET_SUFFIX)
endef

# rule to generate targets for *-all for devs to use
define subdir-recurse-goal
$(eval MAKEDIRS := $(sort $(dir $(wildcard $(1:%/=%)/*/Makefile))))
$(eval MY_TARGET_SUFFIX := $(if $(filter $(abs_wallaroo_dir),$(abspath $1)),wallarooroot-all,$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $1)))-all))
$(foreach mdir,$(MAKEDIRS),$(eval build-$(MY_TARGET_SUFFIX) += build-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $(mdir))))-all))
$(foreach mdir,$(MAKEDIRS),$(eval test-$(MY_TARGET_SUFFIX) += test-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $(mdir))))-all))
$(foreach mdir,$(MAKEDIRS),$(eval clean-$(MY_TARGET_SUFFIX) += clean-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $(mdir))))-all))
$(foreach mdir,$(MAKEDIRS),$(eval build-docker-$(MY_TARGET_SUFFIX) += build-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $(mdir))))-all))
$(foreach mdir,$(MAKEDIRS),$(eval push-docker-$(MY_TARGET_SUFFIX) += push-docker-$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $(mdir))))-all))
endef

ROOT_TARGET_SUFFIX := $(if $(filter $(abs_wallaroo_dir),$(abspath $(ROOT_PATH))),wallarooroot-all,$(subst /,-,$(subst $(abs_wallaroo_dir)/,,$(abspath $(ROOT_PATH))))-all)

# phony targets
.PHONY: build build-docker build-monhub build-pony clean clean-docker clean-monhub clean-pony dagon-spike-test dagon-test list push-docker test-monhub test-pony test docker-arch-check monhub-arch-check help build-docker-pony push-docker-pony build-docker-monhub push-docker-monhub dagon-docker-test dagon-docker-spike-test

# default targets
.DEFAULT_GOAL := build
build: build-$(ROOT_TARGET_SUFFIX) ## Build all projects (pony & monhub) (DEFAULT)
test: test-$(ROOT_TARGET_SUFFIX) ## Test all projects (pony & monhub)
build-pony: build-pony-all ## Build all pony projects
test-pony: test-pony-all ## Test all pony projects
clean-pony: clean-pony-all ## Clean all pony projects
build-docker-pony: build-docker-pony-all ## Build docker containers for all pony projects
push-docker-pony: push-docker-pony-all ## Push docker containers for all pony projects
build-monhub: build-monhub-all ## Build all monhub projects
release-monhub: release-monhub-all ## Create release packages for all monhub projects
test-monhub: test-monhub-all ## Test all monhub projects
clean-monhub: clean-monhub-all ## Clean all monhub projects
build-docker-monhub: build-docker-monhub-all ## Build docker containers for all monhub projects
push-docker-monhub: push-docker-monhub-all ## Push docker containers for all monhub projects
build-docker: build-docker-$(ROOT_TARGET_SUFFIX) ## Build all docker images
push-docker: push-docker-$(ROOT_TARGET_SUFFIX) ## Push all docker images

start-demo: setup-demo ## Signal senders to start sending data for a demo
	$(call run-dagon-notifier)

setup-demo: temp_dagon_host=$(if $(demo_cluster_name),$(shell aws ec2 describe-instances \
              --filters Name=tag:Name,Values=$(demo_cluster_name):wallaroo-leader-1 --query \
              'Reservations[*].Instances[*].PublicIpAddress' --output text),127.0.0.1)
setup-demo: custom_dagon_phone_home=$(if $(demo_cluster_name),$(shell ps aux | \
              grep -o 'name.*dagon' | awk '{print $$2}'),$(temp_dagon_host)):8080
setup-demo: custom_dagon_host=$(temp_dagon_host):2375
setup-demo: custom_dagon_network=$(shell ps aux | grep -o 'net.*dagon' | awk '{print $$2}')
setup-demo: dont_validate=true
setup-demo: dagon_extra_args=-D --docker-path /usr/bin/docker
setup-demo: dagon_in_docker=$(if $(demo_cluster_name),true,false)
setup-demo:
	$(if $(demo_cluster_name),$(QUIET)echo "running demo on $(temp_dagon_host)",\
$(QUIET)echo "running demo locally")
	$(eval custom_dagon_phone_home=$(custom_dagon_phone_home))
	$(eval dagon_phone_home=$(custom_dagon_phone_home))
	$(eval custom_dagon_host=$(custom_dagon_host))
	$(eval custom_dagon_network=$(custom_dagon_network))
	$(eval dont_validate=$(dont_validate))
	$(eval dagon_extra_args=$(dagon_extra_args))
	$(eval dagon_in_docker=$(dagon_in_docker))
	$(if $(demo_cluster_name), $(QUIET)cd orchestration/terraform && \
          make sync-wallaroo cluster_name=$(demo_cluster_name),)

run-demo: setup-demo $(if $(demo_cluster_name),dagon-docker-,dagon-)$(subst dagon-,,$(subst dagon-docker-,,$(demo_to_run)))## Run demo locally or on a cluster with senders waiting to send

create-demo: $(if $(demo_cluster_name),create-demo-cluster check-demo-cluster final-check-demo-cluster) run-demo ## Create/start a demo with senders waiting to send
	$(QUIET)echo "done running demo"

demo-cluster-options = num_followers=0 force_instance=c4.4xlarge spot_bid_factor=100 \
          # ansible_system_cpus=0,8 ansible_isolcpus=true

check-demo-cluster: demo_host=$(shell aws ec2 describe-instances --filters Name=tag:Name,Values=$(demo_cluster_name):wallaroo-leader-1 --query 'Reservations[*].Instances[*].PublicIpAddress' --output text)
check-demo-cluster: # Check a cluster for running the demo
	$(if $(demo_host),,$(QUIET)cd orchestration/terraform && make configure cluster_name=$(demo_cluster_name) \
          $(demo-cluster-options) \
          no_spot=$(if $(filter $(demo_cluster_spot_pricing),false),true,false))

final-check-demo-cluster: demo_host=$(shell aws ec2 describe-instances --filters Name=tag:Name,Values=$(demo_cluster_name):wallaroo-leader-1 --query 'Reservations[*].Instances[*].PublicIpAddress' --output text)
final-check-demo-cluster: # Final check a cluster for running the demo
	$(if $(demo_host),,$(error unable to look up demo host! destroy and try again.))

create-demo-cluster: demo_host=$(shell aws ec2 describe-instances --filters Name=tag:Name,Values=$(demo_cluster_name):wallaroo-leader-1 --query 'Reservations[*].Instances[*].PublicIpAddress' --output text)
create-demo-cluster: demo_cluster_command=$(if $(demo_host),configure,cluster)
create-demo-cluster: ## Create a cluster for running the demo
	$(if $(demo_cluster_name),,$(error Must supply demo_cluster_name when creating demo cluster!))
	$(QUIET)cd orchestration/terraform && make $(demo_cluster_command) cluster_name=$(demo_cluster_name) \
          $(demo-cluster-options) \
          no_spot=$(if $(filter $(demo_cluster_spot_pricing),false),true,false)

destroy-demo: $(if $(demo_cluster_name),destroy-demo-cluster,) ## Destroy/stop a demo

destroy-demo-cluster: ## Create a cluster for running the demo
	$(if $(demo_cluster_name),,$(error Must supply demo_cluster_name when destroying demo cluster!))
	$(QUIET)cd orchestration/terraform && make destroy cluster_name=$(demo_cluster_name) \
          $(demo-cluster-options) \
          no_spot=$(if $(filter $(demo_cluster_spot_pricing),false),true,false)

# rule to print info about make variables, works only with make 3.81 and above
# to use invoke make with a target of print-VARNAME, e.g.,
# make print-CCFLAGS
print-%:
	$(QUIET)echo '$*=$($*)'
	$(QUIET)echo '  origin = $(origin $*)'
	$(QUIET)echo '  flavor = $(flavor $*)'
	$(QUIET)echo '   value = $(value  $*)'


dagon-test: ## Run dagon tests

dagon-docker-test: ## Run dagon tests (using docker)

dagon-spike-test: ## Run dagon spike tests

dagon-docker-spike-test: ## Run dagon spike tests (using docker)

# rule to confirm we are building for a real docker architecture we support
docker-arch-check:
	$(if $(filter $(arch),native),$(error Arch cannot be 'native' \
          for docker build!),)

# rule to confirm we are building for a real monitoring architecture we support
monhub-arch-check:
	$(if $(filter $(arch),armhf),$(error Arch cannot be 'armhf' \
          for building of monitoring hub!),)

# different types of docker images
exited = $(shell docker $(docker_host_arg) ps -a -q -f status=exited)
untagged = $(shell (docker $(docker_host_arg) images | grep "^<none>" | awk \
              -F " " '{print $$3}'))
dangling = $(shell docker $(docker_host_arg) images -f "dangling=true" -q)
tag = $(shell docker $(docker_host_arg) images | grep \
         "$(docker_image_version)" | awk -F " " '{print $$1 ":" $$2}')

# rule to clean up docker images/containers
clean-docker: ## cleanup docker images and containers
	$(if $(strip $(exited)),$(QUIET)echo "Cleaning exited containers: $(exited)",)
	$(if $(strip $(exited)),$(QUIET)docker $(docker_host_arg) rm -v $(exited),)
	$(if $(strip $(tag)),$(QUIET)echo "Removing tag $(tag) image",)
	$(if $(strip $(tag)),$(QUIET)docker $(docker_host_arg) rmi $(tag),)
	$(if $(strip $(dangling)),$(QUIET)echo "Cleaning dangling images: $(dangling)",)
	$(if $(strip $(dangling)),$(QUIET)docker $(docker_host_arg) rmi $(dangling),)

# rule to clean everything
clean: clean-$(ROOT_TARGET_SUFFIX) ## Clean all projects (pony & monhub) and cleanup docker images
	$(QUIET)rm -f lib/wallaroo/wallaroo lib/wallaroo/wallaroo.o
	$(QUIET)rm -f sent.txt received.txt
	$(QUIET)echo 'Done cleaning.'

list: ## List all targets (including automagically generated ones)
	$(QUIET)$(MAKE) -pRrq -f $(lastword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | egrep -v -e '^[^[:alnum:]]' -e '^$@$$'

help: ## this help message
	$(QUIET)echo 'Usage: make [option1=value] [option2=value,...] [target]'
	$(QUIET)echo ''
	$(QUIET)echo 'Options:'
	$(QUIET)grep -h -E '^[a-zA-Z0-9_-]+ *\?=.*?## .*$$' $(MAKEFILE_LIST) | sort -u | awk \
          'BEGIN {FS = "$(extra_awk_arg)?="}; {printf "\033[36m%-40s\033[0m ##%s\n", $$1, \
          $$2}' | awk 'BEGIN {FS = "## "}; {printf "%s%s \033[36m(Default:\
 %s)\033[0m\n", $$1, $$3, $$2}'
	$(QUIET)grep -h -E 'ifeq.*filter.*\)$$' $(MAKEFILE_LIST) | sort -u | awk \
          'BEGIN {FS = "[(),]"}; {printf "\033[36m%-40s\033[0m %s\n", \
          " Valid values for " $$5 ":", $$7}'
	$(QUIET)echo ''
	$(QUIET)echo 'Targets:'
	$(QUIET)echo "\033[36m{command}-{dir}-all                      \033[0mRun command for a directory and all it's sub-projects."
	$(QUIET)echo "                                         Where command is one of: build,test,clean,build-docker,push-docker"
	$(QUIET)grep -h -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort -u | awk \
          'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-40s\033[0m %s\n", \
          $$1, $$2}'
	$(QUIET)grep -h -E '^#[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort -u | awk \
          'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-40s\033[0m %s\n", \
          substr($$1,2), $$2; str=$$1; sub(/#dagon-/,"dagon-docker-",str); printf \
          "\033[36m%-40s\033[0m %s (using docker)\n", str, $$2}'

endif # RULES_MK

# if there's a pony source file, create the appropriate rules for it unless disabled
ifneq ($(PONY_TARGET),false)
  ifneq ($(wildcard $(PREV_PATH)/*.pony),)
    ifneq ($(PONYC_TARGET),false)
      $(eval $(call ponyc-goal,$(PREV_PATH)))
    endif
    $(eval $(call pony-build-goal,$(PREV_PATH)))
    $(eval $(call pony-test-goal,$(PREV_PATH)))
    $(eval $(call pony-clean-goal,$(PREV_PATH)))
  endif
endif

# if there's a exs source file, create the appropriate rules for it unless disabled
ifneq ($(EXS_TARGET),false)
  ifneq ($(wildcard $(PREV_PATH)/*.exs),)
    $(eval $(call monhub-goal,$(PREV_PATH)))
    $(eval $(call monhub-build-goal,$(PREV_PATH)))
    $(eval $(call monhub-test-goal,$(PREV_PATH)))
    $(eval $(call monhub-clean-goal,$(PREV_PATH)))
    ifneq ($(wildcard $(PREV_PATH)/package.json),)
      $(eval $(call monhub-release-goal,$(PREV_PATH)))
    endif
  endif
endif

# if there's a Dockerfile, create the appropriate rules for it unless disabled
ifneq ($(DOCKER_TARGET),false)
  ifneq ($(wildcard $(PREV_PATH)/Dockerfile),)
    $(eval $(call build-docker-goal,$(PREV_PATH)))
    $(eval $(call push-docker-goal,$(PREV_PATH)))
  endif
endif

# include rules for directory level "-all" targets for recursing
ifneq ($(RECURSE_SUBMAKEFILES),false)
  $(eval $(call subdir-recurse-goal,$(PREV_PATH)))
endif

# include rules for directory level "-all" targets
$(eval $(call subdir-goal,$(PREV_PATH)))

# reset variables before including sub-makefiles
TEST_TARGET :=
PONY_TARGET :=
PONYC_TARGET :=
DOCKER_TARGET :=
EXS_TARGET :=

# include makefiles from 1 level down in directory tree if they exist (and by recursion every makefile in the tree that is referenced) unless disabled
ifneq ($(RECURSE_SUBMAKEFILES),false)
  RECURSE_SUBMAKEFILES :=
  $(eval $(call make-goal,$(PREV_PATH)))
else
  RECURSE_SUBMAKEFILES :=
endif

include $(wallaroo_dir)/Makefile
