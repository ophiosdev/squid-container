IMAGE ?= squid:dev
COMPOSE := docker compose
BUILD_CTX := .

.PHONY: build run stop restart update clean

build:
	@echo "🔨 Building image $(IMAGE)..."
	docker build -t $(IMAGE) $(BUILD_CTX)

run: build
	@echo "▶️  Starting docker compose with SQUID_CONTAINER_IMAGE=$(IMAGE)"
	@SQUID_CONTAINER_IMAGE=$(IMAGE) $(COMPOSE) up -d && echo "✅ Started SQUID container using $(IMAGE)"

stop:
	@echo "⏹️  Force stopping docker compose..."
	@SQUID_CONTAINER_IMAGE=$(IMAGE) $(COMPOSE) down --timeout 0 && echo "✅ Stopped SQUID container"

restart:
	@echo "🔁 Force restarting docker compose to reload configuration..."
	@SQUID_CONTAINER_IMAGE=$(IMAGE) $(COMPOSE) up -d --force-recreate --timeout 0 && echo "✅ Restarted SQUID container"

update: build stop run
	@echo "🔄 Updated SQUID container"

sbom: build
	docker create --name temp-squid-container $(IMAGE)
	docker cp temp-squid-container:/sbom.spdx.json ./sbom.spdx.json
	docker rm temp-squid-container

clean: stop
	@echo "🧹 Cleaning up: stopping compose and removing image/container if present"
	@-docker rm -f squid >/dev/null 2>&1 || true
	@if docker image inspect $(IMAGE) >/dev/null 2>&1; then \
		echo "🗑️  Removing image $(IMAGE)"; \
		docker image rm -f $(IMAGE); \
	else \
		echo "⚠️  Image $(IMAGE) not found, skipping"; \
	fi
