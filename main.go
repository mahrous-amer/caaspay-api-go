package main

import (
	"caaspay-api-go/api/config"
	"caaspay-api-go/api/routes"
	"caaspay-api-go/internal/broker"
	"caaspay-api-go/internal/logging"
	"caaspay-api-go/internal/metrics"
	"caaspay-api-go/internal/openapi"
	"caaspay-api-go/internal/rpc"
	"context"
	"fmt"
	"log"

	"github.com/gin-gonic/gin"
	swaggerFiles "github.com/swaggo/files"
	"github.com/swaggo/gin-swagger"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"net/http"
)

func main() {
	ctx := context.Background()
	cfg, err := config.LoadAPIConfig()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}
	// Load route configurations once
	routeConfigs, err := routes.LoadRouteConfigs(cfg)
	if err != nil {
		log.Fatalf("Failed to load route configurations: %v", err)
	}
	// Initialize Datadog metrics and OpenTelemetry tracer if enabled
	var metricsClient *metrics.DataDogMetrics
	if cfg.MetricsEnabled {
		metricsClient, err = metrics.NewDataDogMetrics(cfg.DatadogAddr, cfg.AppName, cfg.Env)
		if err != nil {
			log.Fatalf("Failed to initialize Datadog metrics and tracer: %v", err)
		}
		defer metricsClient.Close()
	}

	logger := logging.NewLogger(cfg.AppName, cfg.Env, cfg.LogLevel, false, metricsClient, ctx)

	// Set up Gin with logger middleware
	if cfg.Env == "production" {
		gin.SetMode(gin.ReleaseMode)
	}
	r := gin.Default()
	r.Use(func(c *gin.Context) {
		logger.Middleware()(c)
	})
	r.Use(otelgin.Middleware(cfg.AppName))

	// Initialize Redis broker with options
	redisOptions := broker.RedisOptions{
		Addrs:     cfg.Redis.Address,
		Prefix:    cfg.Redis.Prefix,
		IsCluster: cfg.Redis.IsCluster, // Set to true if you want to use a Redis cluster
	}
	redisBroker := broker.NewRedisBroker(redisOptions)
	defer redisBroker.Close()

	// Initialize the RPC client pool using the Redis broker
	rpcClientPool := rpc.NewRPCClientPool(ctx, cfg.RPCPool.InitialClients, cfg.RPCPool.MaxClients, cfg.RPCPool.MaxRequestsPerClient, redisBroker, cfg.RPCPool.MonitorInterval, cfg.RPCPool.ScaleDown, logger)
	defer rpcClientPool.Close()

	// Initialize the routes with the route configuration
	if err := routes.SetupRoutes(r, rpcClientPool, cfg, routeConfigs, logger); err != nil {
		logger.LogWithStats("error", "Failed to set up routes", map[string]string{"metric_name": "setup_routes_error", "error": fmt.Sprintf("err %v", err)}, nil)
	}

	if cfg.EnableOpenapiSwagger {
		// Generate OpenAPI spec from routeConfigs and additional static routes
		openAPISpec, err := openapi.GenerateOpenAPISpec(routeConfigs, cfg)
		if err != nil {
			logger.LogWithStats("error", "Failed to generate OpenAPI spec", map[string]string{"error": err.Error()}, nil)
		} else {
			r.GET("/openapi.json", func(c *gin.Context) {
				c.JSON(http.StatusOK, openAPISpec)
			})
		}

		r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler, ginSwagger.URL("/openapi.json")))
	}

	// Start the API server
	if err := r.Run(fmt.Sprintf("%v:%v", cfg.Host, cfg.Port)); err != nil {
		log.Fatalf("Failed to run server: %v", err)
	}

	// Close the broker and RPC client pool when the server shuts down
	defer redisBroker.Close()
	defer rpcClientPool.Close()
}
