package handlers

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"

	"github.com/gorilla/mux"
	"github.com/luciq/chat-go-service/cache"
	"github.com/luciq/chat-go-service/db"
	"github.com/luciq/chat-go-service/models"
	"github.com/luciq/chat-go-service/queue"
)

// CreateMessage handles POST /api/v1/chat_applications/:token/chats/:number/messages
func CreateMessage(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	token := vars["token"]
	chatNumberStr := vars["number"]

	chatNumber, err := strconv.ParseInt(chatNumberStr, 10, 64)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(models.ErrorResponse{
			Error: "Invalid chat number",
		})
		return
	}

	log.Printf("CreateMessage request for token: %s, chat: %d", token, chatNumber)

	// 1. Parse request body
	var req models.CreateMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("Failed to decode request: %v", err)
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(models.ErrorResponse{
			Error: "Invalid request body",
		})
		return
	}

	// 2. Validate message body
	if req.Message.Body == "" {
		w.WriteHeader(http.StatusUnprocessableEntity)
		json.NewEncoder(w).Encode(models.ErrorResponse{
			Error: "Message body can't be blank",
		})
		return
	}

	// 3. Validate chat application exists
	chatAppID, err := db.GetChatApplicationID(token)
	if err != nil {
		log.Printf("Chat application not found: %v", err)
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(models.ErrorResponse{
			Error: "ChatApplication not found",
		})
		return
	}

	// 4. Validate chat exists
	chatID, err := db.GetChatID(chatAppID, chatNumber)
	if err != nil {
		log.Printf("Chat not found: %v", err)
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(models.ErrorResponse{
			Error: "Chat not found",
		})
		return
	}

	// 5. Get next message number from Redis (atomic)
	messageNumber, err := cache.NextMessageNumber(chatID)
	if err != nil {
		log.Printf("Failed to generate message number: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(models.ErrorResponse{
			Error: "Failed to generate message number",
		})
		return
	}

	// 6. Queue Sidekiq job to persist message
	err = queue.EnqueueCreateMessageJob(chatID, messageNumber, req.Message.Body)
	if err != nil {
		log.Printf("Failed to enqueue CreateMessageJob: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(models.ErrorResponse{
			Error: "Failed to create message",
		})
		return
	}

	// 7. Return response immediately (async processing)
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(models.CreateMessageResponse{
		Number: messageNumber,
	})

	log.Printf("Message created: chat_id=%d, number=%d, body=%s", chatID, messageNumber, req.Message.Body)
}
