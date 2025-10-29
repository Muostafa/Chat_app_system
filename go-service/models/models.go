package models

// CreateChatResponse represents the response when creating a chat
type CreateChatResponse struct {
	Number        int64 `json:"number"`
	MessagesCount int   `json:"messages_count"`
}

// CreateMessageRequest represents the request body for creating a message
type CreateMessageRequest struct {
	Message struct {
		Body string `json:"body"`
	} `json:"message"`
}

// CreateMessageResponse represents the response when creating a message
type CreateMessageResponse struct {
	Number int64 `json:"number"`
}

// ErrorResponse represents an error response
type ErrorResponse struct {
	Error string `json:"error"`
}
