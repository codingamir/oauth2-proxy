GO ?= go
GOLANGCILINT ?= golangci-lint

BINARY := oauth2-proxy
VERSION:=$(shell if [ -n "${GIT_TAG}" ]; then echo ${GIT_TAG}; else echo "0.0.0"; fi;)
# Allow to override image registry.
REGISTRY ?= intechww-docker-local.jfrog.io
.NOTPARALLEL:

GO_MAJOR_VERSION = $(shell $(GO) version | cut -c 14- | cut -d' ' -f1 | cut -d'.' -f1)
GO_MINOR_VERSION = $(shell $(GO) version | cut -c 14- | cut -d' ' -f1 | cut -d'.' -f2)
MINIMUM_SUPPORTED_GO_MAJOR_VERSION = 1
MINIMUM_SUPPORTED_GO_MINOR_VERSION = 18
GO_VERSION_VALIDATION_ERR_MSG = Golang version is not supported, please update to at least $(MINIMUM_SUPPORTED_GO_MAJOR_VERSION).$(MINIMUM_SUPPORTED_GO_MINOR_VERSION)

ifeq ($(COVER),true)
TESTCOVER ?= -coverprofile c.out
endif

.PHONY: all
all: lint $(BINARY)

.PHONY: clean
clean:
	-rm -rf release
	-rm -f $(BINARY)

.PHONY: distclean
distclean: clean
	rm -rf vendor

.PHONY: lint
lint: validate-go-version
	GO111MODULE=off $(GOLANGCILINT) run

.PHONY: build
build: validate-go-version clean $(BINARY)

$(BINARY):
	CGO_ENABLED=0 $(GO) build -a -installsuffix cgo -ldflags="-X main.VERSION=${VERSION}" -o $@ github.com/oauth2-proxy/oauth2-proxy/v7

DOCKER_BUILD_PLATFORM ?= linux/amd64,linux/ppc64le,linux/arm/v6,linux/arm/v8
#DOCKER_BUILD_RUNTIME_IMAGE ?= alpine:3.15
#DOCKER_BUILDX_ARGS ?= --build-arg RUNTIME_IMAGE=${DOCKER_BUILD_RUNTIME_IMAGE}
DOCKER_BUILDX := docker buildx build #${DOCKER_BUILDX_ARGS} --build-arg VERSION=${VERSION}
DOCKER_BUILDX_X_PLATFORM := $(DOCKER_BUILDX) --platform ${DOCKER_BUILD_PLATFORM}
DOCKER_BUILDX_PUSH := docker buildx build --push ${DOCKER_BUILDX_ARGS} --build-arg VERSION=${VERSION}
DOCKER_BUILDX_PUSH_X_PLATFORM := $(DOCKER_BUILDX_PUSH) --platform ${DOCKER_BUILD_PLATFORM}

.PHONY: docker
docker:
	docker build -t $(REGISTRY)/oauth2-proxy:$(VERSION) .
	
.PHONY: docker-push
docker-push:
	docker image push $(REGISTRY)/oauth2-proxy:$(VERSION)

.PHONY: publish-chart
publish-chart:
	@echo Publishing helm package version: $(VERSION)
# add '' after -i if using macOS
	sed -i "s/^version:.*$$/version: $(VERSION)/" helm/oauth2/Chart.yaml
	sed -i "s/^appVersion:.*$$/appVersion: $(VERSION)/" helm/oauth2/Chart.yaml
	helm repo add helm https://intechww.jfrog.io/artifactory/helm --username $$JFROG_USERNAME --password $$JFROG_PASSWORD
	helm repo update
	helm package --dependency-update helm/oauth2
	curl -u $(JFROG_USERNAME):$(JFROG_PASSWORD) -XPUT https://intechww.jfrog.io/artifactory/helm-local/$(BINARY)/ -T $(BINARY)-$(VERSION).tgz
	@echo Version: $(VERSION) helm package published

.PHONY: generate
generate:
	go generate ./pkg/...

.PHONY: verify-generate
verify-generate: generate
	git diff --exit-code

.PHONY: test
test: lint
	GO111MODULE=on $(GO) test $(TESTCOVER) -v -race ./...

.PHONY: release
release: validate-go-version lint test
	BINARY=${BINARY} VERSION=${VERSION} ./dist.sh

.PHONY: validate-go-version
validate-go-version:
	@if [ $(GO_MAJOR_VERSION) -gt $(MINIMUM_SUPPORTED_GO_MAJOR_VERSION) ]; then \
		exit 0 ;\
	elif [ $(GO_MAJOR_VERSION) -lt $(MINIMUM_SUPPORTED_GO_MAJOR_VERSION) ]; then \
		echo '$(GO_VERSION_VALIDATION_ERR_MSG)';\
		exit 1; \
	elif [ $(GO_MINOR_VERSION) -lt $(MINIMUM_SUPPORTED_GO_MINOR_VERSION) ] ; then \
		echo '$(GO_VERSION_VALIDATION_ERR_MSG)';\
		exit 1; \
	fi

# local-env can be used to interact with the local development environment
# eg:
#    make local-env-up 					# Bring up a basic test environment
#    make local-env-down 				# Tear down the basic test environment
#    make local-env-nginx-up 		# Bring up an nginx based test environment
#    make local-env-nginx-down 	# Tead down the nginx based test environment
#docker build -t $(REGISTRY)/oauth2-proxy:latest .
.PHONY: local-env-%
local-env-%:
	make -C contrib/local-environment $*
