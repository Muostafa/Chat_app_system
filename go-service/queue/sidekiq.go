package queue

import (
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/luciq/chat-go-service/cache"
)

// ActiveJobPayload represents the structure Rails ActiveJob expects
type ActiveJobPayload struct {
	JobClass  string        `json:"job_class"`
	JobID     string        `json:"job_id"`
	QueueName string        `json:"queue_name"`
	Arguments []interface{} `json:"arguments"`
	Locale    string        `json:"locale"`
}

// EnqueueCreateChatJob queues a CreateChatJob via ActiveJob
func EnqueueCreateChatJob(chatApplicationID int64, chatNumber int64) error {
	payload := ActiveJobPayload{
		JobClass:  "CreateChatJob",
		JobID:     generateJobID(),
		QueueName: "default",
		Arguments: []interface{}{chatApplicationID, chatNumber},
		Locale:    "en",
	}

	return enqueueActiveJob(payload)
}

// EnqueueCreateMessageJob queues a CreateMessageJob via ActiveJob
func EnqueueCreateMessageJob(chatID int64, messageNumber int64, messageBody string) error {
	payload := ActiveJobPayload{
		JobClass:  "CreateMessageJob",
		JobID:     generateJobID(),
		QueueName: "default",
		Arguments: []interface{}{chatID, messageNumber, messageBody},
		Locale:    "en",
	}

	return enqueueActiveJob(payload)
}

// generateJobID creates a unique job ID
func generateJobID() string {
	return fmt.Sprintf("%d", time.Now().UnixNano())
}

// enqueueActiveJob marshals the ActiveJob payload and pushes it to Sidekiq
func enqueueActiveJob(payload ActiveJobPayload) error {
	// Wrap in ActiveJob::QueueAdapters::SidekiqAdapter format
	wrapper := map[string]interface{}{
		"class": "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
		"wrapped": payload.JobClass,
		"queue": payload.QueueName,
		"args": []interface{}{payload},
		"retry": true,
		"jid": payload.JobID,
		"created_at": float64(time.Now().Unix()),
	}

	jobJSON, err := json.Marshal(wrapper)
	if err != nil {
		return fmt.Errorf("failed to marshal job: %v", err)
	}

	queueKey := fmt.Sprintf("queue:%s", payload.QueueName)

	// Push to Redis list (LPUSH for Sidekiq compatibility)
	err = cache.RedisClient.LPush(cache.Ctx, queueKey, string(jobJSON)).Err()
	if err != nil {
		return fmt.Errorf("failed to enqueue job: %v", err)
	}

	log.Printf("Enqueued %s: %s", payload.JobClass, string(jobJSON))
	return nil
}
