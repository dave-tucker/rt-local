VERSION=0.0
GIT_COMMIT=$(shell git rev-list -1 HEAD)
CMD_PKG=github.com/linuxkit/rtf/cmd
PKGS:=$(shell go list ./... | grep -v vendor)

GOOS?=$(shell uname -s | tr '[:upper:]' '[:lower:]')
GOARCH?=amd64
ifneq ($(GOOS),linux)
CROSS+=-e GOOS=$(GOOS)
endif
ifneq ($(GOARCH),amd64)
CROSS+=-e GOARCH=$(GOARCH)
endif

DEPS=Makefile main.go
DEPS+=$(wildcard cmd/*.go)
DEPS+=$(wildcard local/*.go)
DEPS+=$(wildcard logger/*.go)
DEPS+=$(wildcard sysinfo/*.go)

PREFIX?=/usr/local

GOLINT:=$(shell command -v golint 2> /dev/null)
INEFFASSIGN:=$(shell command -v ineffassign 2> /dev/null)

LDFLAGS=-X $(CMD_PKG).GitCommit=$(GIT_COMMIT) -X $(CMD_PKG).Version=$(VERSION)

default: rtf

# Build with docker
GO_COMPILE=linuxkit/go-compile:7cac05c5588b3dd6a7f7bdb34fc1da90257394c7
.PHONY: build-with-docker
build-with-docker: tmp_rtf_bin.tar
	tar xf $<
	rm $<

tmp_rtf_bin.tar: $(DEPS)
	tar cf - . | docker run --rm --net=none --log-driver=none -i $(CROSS) $(GO_COMPILE) --package github.com/linuxkit/rtf --ldflags "$(LDFLAGS)" -o rtf > $@


# Build local (default)
rtf: $(DEPS)
	go build --ldflags "$(LDFLAGS)" -o $@

.PHONY: lint
lint:
ifndef GOLINT
	$(error "Please install golint! go get -u github.com/tool/lint")
endif
ifndef INEFFASSIGN
	$(error "Please install ineffassign! go get -u github.com/gordonklaus/ineffassign")
endif
	@echo "+ $@: golint, gofmt, go vet, ineffassign"
	# golint
	@test -z "$(shell find . -type f -name "*.go" -not -path "./vendor/*" -exec golint {} \; | tee /dev/stderr)"
	# gofmt
	@test -z "$$(gofmt -s -l .| grep -v .pb. | grep -v vendor/ | tee /dev/stderr)"
ifeq ($(GOOS),)
	# govet
	@test -z "$$(go tool vet -printf=false . 2>&1 | grep -v vendor/ | tee /dev/stderr)"
endif
	# ineffassign
	@test -z $(find . -type f -name "*.go" -not -path "*/vendor/*" -exec ineffassign {} \; | tee /dev/stderr)

.PHONY: install-deps
install-deps:
	go get -u github.com/tool/lint
	go get -u github.com/gordonklaus/ineffassign

.PHONY: test
test: rtf lint
	@go test $(PKGS)

.PHONY: install
install: rtf
	cp -a $^ $(PREFIX)/bin/

.PHONY: docker-image
docker-image: $(DEPS) Dockerfile
	docker build --build-arg LDFLAGS="$(LDFLAGS)" -t linuxkit/rtf:$(GIT_COMMIT) .

.PHONY: push
push: docker-image
	docker tag linuxkit/rtf:$(GIT_COMMIT) linuxkt/rtf:latest
	docker push linuxkit/rtf:$(GIT_COMMIT)
	docker push linuxkit/rtf:latest

.PHONY: clean
clean:
	rm -f rtf
