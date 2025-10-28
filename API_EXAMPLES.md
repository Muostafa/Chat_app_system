# API Usage Examples

Complete cURL and HTTP examples for all Chat System API endpoints.

## Base URL

```
http://localhost:3000/api/v1
```

## Chat Applications

### Create Chat Application

**Request:**
```bash
curl -X POST http://localhost:3000/api/v1/chat_applications \
  -H "Content-Type: application/json" \
  -d '{
    "chat_application": {
      "name": "Mobile App Chat"
    }
  }'
```

**Response (201 Created):**
```json
{
  "id": 1,
  "name": "Mobile App Chat",
  "token": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
  "chats_count": 0
}
```

**Important:** Save the `token` - you'll need it for all subsequent requests!

### Get Chat Application

**Request:**
```bash
curl http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
```

**Response (200 OK):**
```json
{
  "id": 1,
  "name": "Mobile App Chat",
  "token": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
  "chats_count": 2
}
```

### List All Chat Applications

**Request:**
```bash
curl http://localhost:3000/api/v1/chat_applications
```

**Response (200 OK):**
```json
[
  {
    "id": 1,
    "name": "Mobile App Chat",
    "token": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
    "chats_count": 2
  },
  {
    "id": 2,
    "name": "Web App Chat",
    "token": "z9y8x7w6v5u4t3s2r1q0p9o8n7m6l5k4",
    "chats_count": 0
  }
]
```

### Update Chat Application Name

**Request:**
```bash
curl -X PATCH http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6 \
  -H "Content-Type: application/json" \
  -d '{
    "chat_application": {
      "name": "Updated Mobile App Chat"
    }
  }'
```

**Response (200 OK):**
```json
{
  "id": 1,
  "name": "Updated Mobile App Chat",
  "token": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
  "chats_count": 2
}
```

---

## Chats

Assuming token: `a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6`

### Create Chat

**Request:**
```bash
curl -X POST http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6/chats \
  -H "Content-Type: application/json"
```

**Response (201 Created):**
```json
{
  "number": 1,
  "messages_count": 0
}
```

**Create Second Chat:**
```bash
curl -X POST http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6/chats \
  -H "Content-Type: application/json"
```

**Response (201 Created):**
```json
{
  "number": 2,
  "messages_count": 0
}
```

### Get All Chats for Application

**Request:**
```bash
curl http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6/chats
```

**Response (200 OK):**
```json
[
  {
    "number": 1,
    "messages_count": 3
  },
  {
    "number": 2,
    "messages_count": 0
  }
]
```

### Get Specific Chat

**Request:**
```bash
curl http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6/chats/1
```

**Response (200 OK):**
```json
{
  "number": 1,
  "messages_count": 3
}
```

---

## Messages

Assuming token: `a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6` and chat number: `1`

### Create Message

**Request:**
```bash
curl -X POST http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6/chats/1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "message": {
      "body": "Hello, how are you?"
    }
  }'
```

**Response (201 Created):**
```json
{
  "number": 1
}
```

**Create Second Message:**
```bash
curl -X POST http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6/chats/1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "message": {
      "body": "I am doing great, thanks for asking!"
    }
  }'
```

**Response (201 Created):**
```json
{
  "number": 2
}
```

### Get All Messages in Chat

**Request:**
```bash
curl http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6/chats/1/messages
```

**Response (200 OK):**
```json
[
  {
    "number": 1,
    "body": "Hello, how are you?"
  },
  {
    "number": 2,
    "body": "I am doing great, thanks for asking!"
  }
]
```

### Get Specific Message

**Request:**
```bash
curl http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6/chats/1/messages/1
```

**Response (200 OK):**
```json
{
  "number": 1,
  "body": "Hello, how are you?"
}
```

### Search Messages in Chat

**Simple Search:**
```bash
curl "http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6/chats/1/messages/search?q=hello"
```

**Response (200 OK):**
```json
[
  {
    "number": 1,
    "body": "Hello, how are you?"
  }
]
```

**Search with Multiple Words:**
```bash
curl "http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6/chats/1/messages/search?q=doing%20great"
```

**Response (200 OK):**
```json
[
  {
    "number": 2,
    "body": "I am doing great, thanks for asking!"
  }
]
```

---

## Error Responses

### Chat Application Not Found

**Request:**
```bash
curl http://localhost:3000/api/v1/chat_applications/invalid_token
```

**Response (404 Not Found):**
```json
{
  "error": "ChatApplication not found"
}
```

### Chat Not Found

**Request:**
```bash
curl http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6/chats/999
```

**Response (404 Not Found):**
```json
{
  "error": "Chat not found"
}
```

### Message Not Found

**Request:**
```bash
curl http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6/chats/1/messages/999
```

**Response (404 Not Found):**
```json
{
  "error": "Message not found"
}
```

### Validation Error (Empty Name)

**Request:**
```bash
curl -X POST http://localhost:3000/api/v1/chat_applications \
  -H "Content-Type: application/json" \
  -d '{
    "chat_application": {
      "name": ""
    }
  }'
```

**Response (422 Unprocessable Entity):**
```json
{
  "errors": {
    "name": ["can't be blank"]
  }
}
```

### Validation Error (Empty Message Body)

**Request:**
```bash
curl -X POST http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6/chats/1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "message": {
      "body": ""
    }
  }'
```

**Response (422 Unprocessable Entity):**
```json
{
  "errors": {
    "body": ["can't be blank"]
  }
}
```

### Missing Search Query

**Request:**
```bash
curl "http://localhost:3000/api/v1/chat_applications/a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6/chats/1/messages/search"
```

**Response (400 Bad Request):**
```json
{
  "error": "Query parameter required"
}
```

---

## Complete Workflow Example

Here's a complete workflow showing how to use the API:

```bash
#!/bin/bash

# 1. Create a chat application
APP_RESPONSE=$(curl -s -X POST http://localhost:3000/api/v1/chat_applications \
  -H "Content-Type: application/json" \
  -d '{
    "chat_application": {
      "name": "My Chat App"
    }
  }')

# Extract token from response
TOKEN=$(echo $APP_RESPONSE | grep -o '"token":"[^"]*' | cut -d'"' -f4)
echo "Created app with token: $TOKEN"

# 2. Create a chat
CHAT_RESPONSE=$(curl -s -X POST http://localhost:3000/api/v1/chat_applications/$TOKEN/chats \
  -H "Content-Type: application/json")
CHAT_NUMBER=$(echo $CHAT_RESPONSE | grep -o '"number":[0-9]*' | cut -d':' -f2)
echo "Created chat number: $CHAT_NUMBER"

# 3. Add multiple messages
for i in {1..3}; do
  MSG_RESPONSE=$(curl -s -X POST http://localhost:3000/api/v1/chat_applications/$TOKEN/chats/$CHAT_NUMBER/messages \
    -H "Content-Type: application/json" \
    -d "{
      \"message\": {
        \"body\": \"This is message number $i\"
      }
    }")
  MSG_NUMBER=$(echo $MSG_RESPONSE | grep -o '"number":[0-9]*' | cut -d':' -f2)
  echo "Created message number: $MSG_NUMBER"
done

# 4. Retrieve all messages
echo "All messages:"
curl -s http://localhost:3000/api/v1/chat_applications/$TOKEN/chats/$CHAT_NUMBER/messages | jq

# 5. Search for a specific message
echo "Search results for 'number':"
curl -s "http://localhost:3000/api/v1/chat_applications/$TOKEN/chats/$CHAT_NUMBER/messages/search?q=number" | jq
```

---

## Using with REST Clients

### Postman

1. Import the collection (example below):

```json
{
  "info": {
    "name": "Chat System API",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "item": [
    {
      "name": "Create Chat Application",
      "request": {
        "method": "POST",
        "url": {
          "raw": "http://localhost:3000/api/v1/chat_applications",
          "protocol": "http",
          "host": ["localhost"],
          "port": "3000",
          "path": ["api", "v1", "chat_applications"]
        },
        "body": {
          "mode": "raw",
          "raw": "{\"chat_application\": {\"name\": \"Test App\"}}"
        }
      }
    }
  ]
}
```

### HTTPie

```bash
# Create chat application
http POST localhost:3000/api/v1/chat_applications \
  chat_application:='{"name": "My Chat App"}'

# Get chat application
http GET localhost:3000/api/v1/chat_applications/TOKEN

# Create message
http POST localhost:3000/api/v1/chat_applications/TOKEN/chats/1/messages \
  message:='{"body": "Hello world"}'

# Search messages
http GET "localhost:3000/api/v1/chat_applications/TOKEN/chats/1/messages/search?q=hello"
```

### JavaScript Fetch

```javascript
// Create chat application
const createApp = async (name) => {
  const response = await fetch('http://localhost:3000/api/v1/chat_applications', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ chat_application: { name } })
  });
  return response.json();
};

// Create message
const createMessage = async (token, chatNumber, body) => {
  const response = await fetch(
    `http://localhost:3000/api/v1/chat_applications/${token}/chats/${chatNumber}/messages`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: { body } })
    }
  );
  return response.json();
};

// Usage
const app = await createApp('My Chat App');
const msg = await createMessage(app.token, 1, 'Hello world');
console.log('Message created:', msg);
```

### Python Requests

```python
import requests

BASE_URL = 'http://localhost:3000/api/v1'

# Create chat application
response = requests.post(
    f'{BASE_URL}/chat_applications',
    json={'chat_application': {'name': 'My Chat App'}}
)
app = response.json()
token = app['token']

# Create message
response = requests.post(
    f'{BASE_URL}/chat_applications/{token}/chats/1/messages',
    json={'message': {'body': 'Hello world'}}
)
message = response.json()
print(f'Message {message["number"]} created')

# Search messages
response = requests.get(
    f'{BASE_URL}/chat_applications/{token}/chats/1/messages/search',
    params={'q': 'hello'}
)
results = response.json()
print(f'Found {len(results)} messages')
```
