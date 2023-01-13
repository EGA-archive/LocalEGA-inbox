SHELL := /bin/bash
COMMIT ?= $(shell git rev-parse HEAD)
ARGS = 

IMG=crg/fega-inbox:$(COMMIT)

.PHONY: build latest

all: latest

build: ARGS+=--target=BUILD
build latest:
	docker build $(ARGS) \
	       --build-arg COMMIT=$(COMMIT) \
               --build-arg BUILD_DATE="$(shell date +%Y-%m-%d_%H.%M.%S)" \
               --build-arg LEGA_GID=$(shell id -g lega) \
	       -t $(IMG) .
	docker tag $(IMG) crg/fega-inbox:$@

