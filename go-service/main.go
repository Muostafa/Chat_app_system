package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gorilla/mux"
	"github.com/luciq/chat-go-service/cache"
	"github.com/luciq/chat-go-service/db"
	"github.com/luciq/chat-go-service/handlers"
	"github.com/luciq/chat-go-service/middleware"
)

func main() {
	log.Println("Starting Go Chat Service...")

	// Initialize Redis
	if err := cache.InitRedis(); err != nil {
		log.Fatalf("Failed to initialize Redis: %v", err)
	}
	defer cache.CloseRedis()

	// Initialize MySQL
	if err := db.InitDB(); err != nil {
		log.Fatalf("Failed to initialize MySQL: %v", err)
	}
	defer db.CloseDB()

	// Create router
	router := mux.NewRouter()

	// Apply middleware
	router.Use(middleware.LoggingMiddleware)
	router.Use(middleware.RecoveryMiddleware)
	router.Use(middleware.CORSMiddleware)

	// Health check endpoint
	router.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"healthy"}`))
	}).Methods("GET")

	// API routes - matching Rails pattern
	apiRouter := router.PathPrefix("/api/v1").Subrouter()

	// POST /api/v1/chat_applications/:token/chats
	apiRouter.HandleFunc("/chat_applications/{token}/chats", handlers.CreateChat).Methods("POST")

	// POST /api/v1/chat_applications/:token/chats/:number/messages
	apiRouter.HandleFunc("/chat_applications/{token}/chats/{number}/messages", handlers.CreateMessage).Methods("POST")

	// Get port from environment or default to 8080
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Create HTTP server
	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Start server in goroutine
	go func() {
		log.Printf("Go Chat Service listening on port %s", port)
		log.Println("Endpoints:")
		log.Println("  POST /api/v1/chat_applications/:token/chats")
		log.Println("  POST /api/v1/chat_applications/:token/chats/:number/messages")
		log.Println("  GET  /health")

		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	// Wait for interrupt signal for graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	// Graceful shutdown with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited gracefully")
}
