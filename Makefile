SHELL := /bin/bash
COMMIT ?= $(shell git rev-parse HEAD)
ARGS = 

.PHONY: build latest

all: latest

build: ARGS+=--target=BUILD
build latest:
	docker build $(ARGS) \
	       --build-arg COMMIT=$(COMMIT) \
               --build-arg BUILD_DATE="$(shell date +%Y-%m-%d_%H.%M.%S)" \
               --build-arg LEGA_GID=$(shell id -g lega) \
	       -t crg/fega-test:$(COMMIT) .
	docker tag crg/fega-test:$(COMMIT) crg/fega-test:$@
