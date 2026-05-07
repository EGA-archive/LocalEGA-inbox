SHELL := /bin/bash
COMMIT ?= $(shell git rev-parse HEAD)
ARGS = 

IMG=crg/fega-inbox:$(COMMIT)

.PHONY: build latest

all: latest

ARCH=$(shell uname -m)
ifeq ($(ARCH), arm64) # reset for MacOS
	ARCH=aarch64
endif


build: ARGS+=--target=BUILD
build latest:
ifeq ($(LEGA_GID),)
	$(error "Please specify the group id via the LEGA_GID variable")
endif
	docker build $(ARGS) \
	       --build-arg ARCH=$(ARCH) \
               --build-arg LEGA_UID=$(LEGA_UID) \
               --build-arg LEGA_GID=$(LEGA_GID) \
	       -t $(IMG) .
	docker tag $(IMG) crg/fega-inbox:$@


up:
	docker run -d --rm --name inbox-test \
	-v $(shell pwd)/conf/mq:/etc/rabbitmq \
	-p 15675:15672 \
	--entrypoint /bin/sleep crg/fega-inbox:latest 365d

run:
	docker run -d --rm --name inbox-test --entrypoint /bin/sleep crg/fega-inbox:build 365d

exec:
	docker exec -it --user root inbox-test bash

down:
	-docker stop inbox-test
