package cache

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/redis/go-redis/v9"
)

var RedisClient *redis.Client
var Ctx = context.Background()

// InitRedis initializes the Redis client connection
func InitRedis() error {
	redisURL := os.Getenv("REDIS_URL")
	if redisURL == "" {
		redisURL = "localhost:6379"
	}

	RedisClient = redis.NewClient(&redis.Options{
		Addr:     redisURL,
		Password: "", // no password
		DB:       0,  // default DB
	})

	// Test connection
	_, err := RedisClient.Ping(Ctx).Result()
	if err != nil {
		return fmt.Errorf("failed to connect to Redis: %v", err)
	}

	log.Println("Redis connected successfully")
	return nil
}

// NextChatNumber generates the next sequential chat number for a chat application
// Mimics Rails SequentialNumberService.next_chat_number
func NextChatNumber(chatApplicationID int64) (int64, error) {
	key := fmt.Sprintf("chat_app:%d:chat_counter", chatApplicationID)

	result, err := RedisClient.Incr(Ctx, key).Result()
	if err != nil {
		return 0, fmt.Errorf("failed to increment chat counter: %v", err)
	}

	log.Printf("Generated chat number %d for app %d", result, chatApplicationID)
	return result, nil
}

// NextMessageNumber generates the next sequential message number for a chat
// Mimics Rails SequentialNumberService.next_message_number
func NextMessageNumber(chatID int64) (int64, error) {
	key := fmt.Sprintf("chat:%d:message_counter", chatID)

	result, err := RedisClient.Incr(Ctx, key).Result()
	if err != nil {
		return 0, fmt.Errorf("failed to increment message counter: %v", err)
	}

	log.Printf("Generated message number %d for chat %d", result, chatID)
	return result, nil
}

// CloseRedis closes the Redis connection
func CloseRedis() error {
	if RedisClient != nil {
		return RedisClient.Close()
	}
	return nil
}
