package handlers

import (
	"encoding/json"
	"log"
	"net/http"

	"github.com/gorilla/mux"
	"github.com/luciq/chat-go-service/cache"
	"github.com/luciq/chat-go-service/db"
	"github.com/luciq/chat-go-service/models"
	"github.com/luciq/chat-go-service/queue"
)

// CreateChat handles POST /api/v1/chat_applications/:token/chats
func CreateChat(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	token := vars["token"]

	log.Printf("CreateChat request for token: %s", token)

	// 1. Validate chat application exists
	chatAppID, err := db.GetChatApplicationID(token)
	if err != nil {
		log.Printf("Chat application not found: %v", err)
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(models.ErrorResponse{
			Error: "ChatApplication not found",
		})
		return
	}

	// 2. Get next chat number from Redis (atomic)
	chatNumber, err := cache.NextChatNumber(chatAppID)
	if err != nil {
		log.Printf("Failed to generate chat number: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(models.ErrorResponse{
			Error: "Failed to generate chat number",
		})
		return
	}

	// 3. Queue Sidekiq job to persist chat
	err = queue.EnqueueCreateChatJob(chatAppID, chatNumber)
	if err != nil {
		log.Printf("Failed to enqueue CreateChatJob: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(models.ErrorResponse{
			Error: "Failed to create chat",
		})
		return
	}

	// 4. Return response immediately (async processing)
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(models.CreateChatResponse{
		Number:        chatNumber,
		MessagesCount: 0,
	})

	log.Printf("Chat created: app_id=%d, number=%d", chatAppID, chatNumber)
}
