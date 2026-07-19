# Created by PastureStack contributors for repeatable validation.

VERSION ?= v0.3.0
REVISION ?= $(shell git rev-parse HEAD)
IMAGE_REPOSITORY ?= local/system-image-preloader
IMAGE ?= $(IMAGE_REPOSITORY):$(VERSION)

.PHONY: test validate build smoke integration

test:
	bash tests/pull_retry_test.sh

validate:
	bash -n system-image-preloader tests/pull_retry_test.sh scripts/integration-smoke
	python3 -m py_compile tests/mock_platform_server.py

build:
	docker build --pull \
		--build-arg IMAGE_VERSION=$(VERSION) \
		--build-arg IMAGE_REVISION=$(REVISION) \
		-t $(IMAGE) .

smoke:
	docker run --rm --network none $(IMAGE) --help
	docker run --rm --network none $(IMAGE) --version

integration:
	IMAGE=$(IMAGE) bash scripts/integration-smoke
