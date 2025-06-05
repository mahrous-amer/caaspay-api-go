APP_NAME        ?= caaspay-api-go
GO_CMD          ?= go
GIN_MODE        ?= development
ENV             ?= development
DOCKER_IMAGE_NAME ?= $(APP_NAME)
DOCKER_IMAGE_TAG  ?= latest
CONTAINER_NAME  ?= $(APP_NAME)-dev
DEFAULT_PORT    ?= 8080
HOST_PORT       ?= $(DEFAULT_PORT)

# For linting and testing
GO_FILES        := $(shell find . -name '*.go' -not -path "./vendor/*")

# Determine Gin mode based on ENV
ifeq ($(ENV),production)
    GIN_MODE := release
else
    GIN_MODE := debug
endif

.PHONY: all help build run dev test lint prod clean

.DEFAULT_GOAL := help

all: build

help: ## Display this help screen
	@echo "Makefile for $(APP_NAME)"
	@echo "-------------------------"
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## Build the Go binary and Docker image
	@echo "Building Go binary..."
	@CGO_ENABLED=0 $(GO_CMD) build -o $(APP_NAME) main.go
	@echo "Building Docker image $(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)..."
	@docker build -t $(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG) .
	@echo "Build complete."

run: ## Run the application as a Docker container in development mode
	@echo "Running $(APP_NAME) in Docker container (dev mode)..."
	@docker run --rm -p $(HOST_PORT):$(DEFAULT_PORT) \
		--name $(CONTAINER_NAME) \
		-v $(shell pwd)/config:/app/config \
		-e GOAPI_ENV=$(ENV) \
		-e GOAPI_GIN_MODE=$(GIN_MODE) \
		$(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)

dev: ## Run the API in development mode with local Go environment (live reload not included by default)
	@echo "Starting $(APP_NAME) in development mode (local Go environment)..."
	@echo "Environment: $(ENV), Gin Mode: $(GIN_MODE)"
	@echo "API will be available on http://localhost:$(DEFAULT_PORT)"
	@echo "Note: Live reload is not enabled by default with this target."
	@echo "Consider using tools like 'air' or 'gin' for live reloading: air -c .air.toml"
	@GOAPI_ENV=$(ENV) GOAPI_GIN_MODE=$(GIN_MODE) GOAPI_PORT=$(DEFAULT_PORT) $(GO_CMD) run main.go

test: ## Run unit tests
	@echo "Running unit tests..."
	@$(GO_CMD) test ./... -v

lint: ## Run linter (golangci-lint)
	@echo "Running linter (golangci-lint)..."
	@echo "Please ensure golangci-lint is installed (https://golangci-lint.run/usage/install/)."
	@golangci-lint run ./... || echo "Linting found issues. Please review."

prod: ## Run the application as a Docker container in production mode
	@echo "Running $(APP_NAME) in Docker container (production mode)..."
	@docker run --rm -p $(HOST_PORT):$(DEFAULT_PORT) \
		--name $(APP_NAME)-prod \
		-v $(shell pwd)/config:/app/config \
		-e GOAPI_ENV=production \
		-e GOAPI_GIN_MODE=release \
		$(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	@if [ -f $(APP_NAME) ]; then $(RM) $(APP_NAME); fi
	@echo "Clean complete."

# Example .air.toml for live reloading (user needs to create this file and install air)
# root = "."
# tmp_dir = "tmp"
#
# [build]
#   cmd = "go build -o ./tmp/main main.go"
#   bin = "./tmp/main"
#   full_bin = "APP_ENV=development APP_PORT=8080 ./tmp/main"
#   delay = 1000 # ms
#   include_ext = ["go", "tpl", "tmpl", "html"]
#   exclude_dir = ["assets", "tmp", "vendor"]
#   log = "air.log"
#
# [log]
#   time = true
#
# [misc]
#   clean_on_exit = true
#
# [screen]
#   clear_on_rebuild = true
#
# [colors]
#   main = "magenta"
#   watcher = "cyan"
#   build = "yellow"
#   runner = "green"

# Note on Dockerfile:
# A Dockerfile is required for the 'build' and 'run'/'prod' targets to work.
# Example Dockerfile:
#
# FROM golang:1.21-alpine AS builder
# WORKDIR /app
# COPY go.mod go.sum ./
# RUN go mod download
# COPY . .
# RUN CGO_ENABLED=0 go build -o /app/caaspay-api-go main.go
#
# FROM alpine:latest
# WORKDIR /app
# COPY --from=builder /app/caaspay-api-go /app/caaspay-api-go
# # Copy config files - alternatively, mount them via docker run -v
# # COPY config /app/config
# EXPOSE 8080
# ENTRYPOINT ["/app/caaspay-api-go"]
#
# Ensure your config files (api.yaml, routes.yaml, credentials.yaml) are handled correctly,
# either by copying them in the Dockerfile or by mounting a volume as shown in 'run' and 'prod' targets.
# For production, it's often better to build them into the image unless they change very frequently.
# Environment variables are generally preferred for configuring Dockerized applications.
