IMAGE ?= squid:dev
COMPOSE := docker compose
BUILD_CTX := .

.PHONY: build run clean

build:
	@echo "🔨 Building image $(IMAGE)..."
	docker build -t $(IMAGE) $(BUILD_CTX)

run:
	@echo "▶️  Starting docker compose with SQUID_CONTAINER_IMAGE=$(IMAGE)"
	@SQUID_CONTAINER_IMAGE=$(IMAGE) $(COMPOSE) up -d && echo "✅ Started SQUID container using $(IMAGE)"

sbom: build
	docker create --name temp-squid-container $(IMAGE)
	docker cp temp-squid-container:/sbom.spdx.json ./sbom.spdx.json
	docker rm temp-squid-container

clean:
	@echo "🧹 Cleaning up: stopping compose and removing image/container if present"
	-$(COMPOSE) down -v >/dev/null 2>&1 || true
	-docker rm -f squid >/dev/null 2>&1 || true
	@if docker image inspect $(IMAGE) >/dev/null 2>&1; then \
		echo "🗑️  Removing image $(IMAGE)"; \
		docker image rm -f $(IMAGE); \
	else \
		echo "⚠️  Image $(IMAGE) not found, skipping"; \
	fi
