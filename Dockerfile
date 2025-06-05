FROM golang:1.23 AS base

WORKDIR /app

# Copy go mod files to leverage Docker caching
COPY go.mod go.sum ./

# Download dependencies before copying source to maximize cache usage
RUN go mod download

# Build the Application
FROM base AS builder

ARG BUILD_ENV=prod
ENV GOOS=linux GOARCH=amd64 CGO_ENABLED=0

# Copy the full source code
COPY . .

# Conditional compilation flags for different environments
RUN if [ "$BUILD_ENV" = "prod" ]; then \
        go build -ldflags="-s -w" -o /app/caaspay-api-go . ; \
    else \
        go build -gcflags="all=-N -l" -o /app/caaspay-api-go  . ; \
    fi

# Minimal Final Image
FROM scratch AS final

WORKDIR /app

# Add CA certificates for secure HTTPS connections
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy compiled binary
COPY --from=builder /app/caaspay-api-go .

# Use a non-root user for security
USER 1001

# Expose the application port
EXPOSE 8080

# Default command
ENTRYPOINT ["/app/caaspay-api-go"]

