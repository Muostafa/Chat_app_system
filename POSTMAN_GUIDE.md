# Postman Testing Guide

Complete step-by-step guide to test all Chat System API endpoints using Postman.

## Prerequisites

1. **Postman installed** - Download from https://www.postman.com/downloads/
2. **Chat System running** - Execute `docker-compose up`
3. **Services healthy** - Wait for all services to start (30-60 seconds)

## Setup Postman Collection

### Option 1: Import Collection (Recommended)

1. Open Postman
2. Click **Import** (top left)
3. Select **Link** tab
4. Paste the collection URL or use file
5. Click **Import**

### Option 2: Manual Setup

1. Create a new **Postman Workspace**
2. Create a new **Collection** named "Chat System API"
3. Add requests as described below

## Environment Variables Setup

Before making requests, set up environment variables for easier testing:

### Create Environment

1. Click **Environments** (left sidebar)
2. Click **+** to create new environment
3. Name it: `Chat System Local`
4. Add these variables:

| Variable | Initial Value | Current Value |
|----------|---------------|---------------|
| `base_url` | `http://localhost:3000/api/v1` | `http://localhost:3000/api/v1` |
| `app_token` | (leave empty) | (will be populated after creation) |
| `chat_number` | (leave empty) | (will be populated after creation) |
| `message_number` | (leave empty) | (will be populated after creation) |

5. Click **Save**
6. Select this environment from dropdown (top right)

## API Testing Workflow

### Step 1: Create Chat Application

**Request Name:** `1. Create Chat Application`

**Method:** POST

**URL:** `{{base_url}}/chat_applications`

**Headers:**
```
Content-Type: application/json
```

**Body (raw JSON):**
```json
{
  "chat_application": {
    "name": "My Test Chat App"
  }
}
```

**Expected Response (201 Created):**
```json
{
  "id": 1,
  "name": "My Test Chat App",
  "token": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
  "chats_count": 0
}
```

**Save Token:**
1. After request succeeds
2. Click **Tests** tab
3. Add this script:
```javascript
if (pm.response.code === 201) {
    var jsonData = pm.response.json();
    pm.environment.set("app_token", jsonData.token);
    console.log("Token saved:", jsonData.token);
}
```
4. Click **Send** again to save the token to environment

---

### Step 2: Get Chat Application

**Request Name:** `2. Get Chat Application`

**Method:** GET

**URL:** `{{base_url}}/chat_applications/{{app_token}}`

**Headers:**
```
Content-Type: application/json
```

**Body:** None

**Expected Response (200 OK):**
```json
{
  "id": 1,
  "name": "My Test Chat App",
  "token": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
  "chats_count": 0
}
```

**What to verify:**
- Status code is 200
- Token matches what you sent
- chats_count is 0

---

### Step 3: List All Chat Applications

**Request Name:** `3. List Chat Applications`

**Method:** GET

**URL:** `{{base_url}}/chat_applications`

**Headers:**
```
Content-Type: application/json
```

**Body:** None

**Expected Response (200 OK):**
```json
[
  {
    "id": 1,
    "name": "My Test Chat App",
    "token": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
    "chats_count": 0
  }
]
```

**What to verify:**
- Status code is 200
- Returns array of applications
- Your created app is in the list

---

### Step 4: Update Chat Application Name

**Request Name:** `4. Update Chat Application`

**Method:** PATCH

**URL:** `{{base_url}}/chat_applications/{{app_token}}`

**Headers:**
```
Content-Type: application/json
```

**Body (raw JSON):**
```json
{
  "chat_application": {
    "name": "Updated Chat App Name"
  }
}
```

**Expected Response (200 OK):**
```json
{
  "id": 1,
  "name": "Updated Chat App Name",
  "token": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
  "chats_count": 0
}
```

**What to verify:**
- Status code is 200
- Name is updated
- Token remains the same

---

### Step 5: Create First Chat

**Request Name:** `5. Create Chat 1`

**Method:** POST

**URL:** `{{base_url}}/chat_applications/{{app_token}}/chats`

**Headers:**
```
Content-Type: application/json
```

**Body:** Empty (no body required)

**Expected Response (201 Created):**
```json
{
  "number": 1,
  "messages_count": 0
}
```

**Save Chat Number:**
1. Click **Tests** tab
2. Add script:
```javascript
if (pm.response.code === 201) {
    var jsonData = pm.response.json();
    pm.environment.set("chat_number", jsonData.number);
    console.log("Chat number saved:", jsonData.number);
}
```
3. Click **Send** to execute and save

---

### Step 6: Create Second Chat

**Request Name:** `6. Create Chat 2`

**Method:** POST

**URL:** `{{base_url}}/chat_applications/{{app_token}}/chats`

**Headers:**
```
Content-Type: application/json
```

**Body:** Empty

**Expected Response (201 Created):**
```json
{
  "number": 2,
  "messages_count": 0
}
```

**Important:** Notice that the second chat gets number `2`, not `1`. This demonstrates sequential numbering.

---

### Step 7: List All Chats

**Request Name:** `7. List Chats`

**Method:** GET

**URL:** `{{base_url}}/chat_applications/{{app_token}}/chats`

**Headers:**
```
Content-Type: application/json
```

**Body:** None

**Expected Response (200 OK):**
```json
[
  {
    "number": 1,
    "messages_count": 0
  },
  {
    "number": 2,
    "messages_count": 0
  }
]
```

**What to verify:**
- Status code is 200
- Both chats are returned
- Numbers are 1 and 2 (sequential)

---

### Step 8: Get Specific Chat

**Request Name:** `8. Get Chat by Number`

**Method:** GET

**URL:** `{{base_url}}/chat_applications/{{app_token}}/chats/1`

**Headers:**
```
Content-Type: application/json
```

**Body:** None

**Expected Response (200 OK):**
```json
{
  "number": 1,
  "messages_count": 0
}
```

**What to verify:**
- Status code is 200
- Returns chat number 1
- messages_count is 0

---

### Step 9: Create First Message

**Request Name:** `9. Create Message 1`

**Method:** POST

**URL:** `{{base_url}}/chat_applications/{{app_token}}/chats/{{chat_number}}/messages`

**Headers:**
```
Content-Type: application/json
```

**Body (raw JSON):**
```json
{
  "message": {
    "body": "Hello! This is the first message."
  }
}
```

**Expected Response (201 Created):**
```json
{
  "number": 1
}
```

**Save Message Number:**
1. Click **Tests** tab
2. Add script:
```javascript
if (pm.response.code === 201) {
    var jsonData = pm.response.json();
    pm.environment.set("message_number", jsonData.number);
    console.log("Message number saved:", jsonData.number);
}
```
3. Click **Send** to execute and save

---

### Step 10: Create More Messages

**Request Name:** `10. Create Message 2`

**Method:** POST

**URL:** `{{base_url}}/chat_applications/{{app_token}}/chats/{{chat_number}}/messages`

**Headers:**
```
Content-Type: application/json
```

**Body (raw JSON):**
```json
{
  "message": {
    "body": "This is the second message in the chat."
  }
}
```

**Expected Response (201 Created):**
```json
{
  "number": 2
}
```

---

**Request Name:** `11. Create Message 3`

**Method:** POST

**URL:** `{{base_url}}/chat_applications/{{app_token}}/chats/{{chat_number}}/messages`

**Headers:**
```
Content-Type: application/json
```

**Body (raw JSON):**
```json
{
  "message": {
    "body": "Hello world! Testing search functionality."
  }
}
```

**Expected Response (201 Created):**
```json
{
  "number": 3
}
```

---

### Step 11: List All Messages in Chat

**Request Name:** `12. List Messages in Chat`

**Method:** GET

**URL:** `{{base_url}}/chat_applications/{{app_token}}/chats/{{chat_number}}/messages`

**Headers:**
```
Content-Type: application/json
```

**Body:** None

**Expected Response (200 OK):**
```json
[
  {
    "number": 1,
    "body": "Hello! This is the first message."
  },
  {
    "number": 2,
    "body": "This is the second message in the chat."
  },
  {
    "number": 3,
    "body": "Hello world! Testing search functionality."
  }
]
```

**What to verify:**
- Status code is 200
- All 3 messages returned
- Numbers are 1, 2, 3 (sequential)
- Bodies are correct

---

### Step 12: Get Specific Message

**Request Name:** `13. Get Specific Message`

**Method:** GET

**URL:** `{{base_url}}/chat_applications/{{app_token}}/chats/{{chat_number}}/messages/1`

**Headers:**
```
Content-Type: application/json
```

**Body:** None

**Expected Response (200 OK):**
```json
{
  "number": 1,
  "body": "Hello! This is the first message."
}
```

**What to verify:**
- Status code is 200
- Returns message number 1
- Body is correct

---

### Step 13: Search Messages

**Request Name:** `14. Search Messages`

**Method:** GET

**URL:** `{{base_url}}/chat_applications/{{app_token}}/chats/{{chat_number}}/messages/search?q=hello`

**Headers:**
```
Content-Type: application/json
```

**Body:** None

**Expected Response (200 OK):**
```json
[
  {
    "number": 1,
    "body": "Hello! This is the first message."
  },
  {
    "number": 3,
    "body": "Hello world! Testing search functionality."
  }
]
```

**What to verify:**
- Status code is 200
- Returns messages containing "hello"
- Message numbers 1 and 3 are returned
- Messages with "world" don't appear (partial match)

---

### Step 14: Search with Different Query

**Request Name:** `15. Search Messages - World`

**Method:** GET

**URL:** `{{base_url}}/chat_applications/{{app_token}}/chats/{{chat_number}}/messages/search?q=world`

**Headers:**
```
Content-Type: application/json
```

**Body:** None

**Expected Response (200 OK):**
```json
[
  {
    "number": 3,
    "body": "Hello world! Testing search functionality."
  }
]
```

**What to verify:**
- Only message 3 returned (contains "world")

---

## Error Testing Scenarios

### Test 1: Create Application with Missing Name

**Request Name:** `Error Test 1: Missing Name`

**Method:** POST

**URL:** `{{base_url}}/chat_applications`

**Headers:**
```
Content-Type: application/json
```

**Body (raw JSON):**
```json
{
  "chat_application": {
    "name": ""
  }
}
```

**Expected Response (422 Unprocessable Entity):**
```json
{
  "errors": {
    "name": ["can't be blank"]
  }
}
```

---

### Test 2: Get Non-existent Application

**Request Name:** `Error Test 2: Non-existent App`

**Method:** GET

**URL:** `{{base_url}}/chat_applications/invalid_token_12345`

**Headers:**
```
Content-Type: application/json
```

**Body:** None

**Expected Response (404 Not Found):**
```json
{
  "error": "ChatApplication not found"
}
```

---

### Test 3: Create Message with Empty Body

**Request Name:** `Error Test 3: Empty Message Body`

**Method:** POST

**URL:** `{{base_url}}/chat_applications/{{app_token}}/chats/{{chat_number}}/messages`

**Headers:**
```
Content-Type: application/json
```

**Body (raw JSON):**
```json
{
  "message": {
    "body": ""
  }
}
```

**Expected Response (422 Unprocessable Entity):**
```json
{
  "errors": {
    "body": ["can't be blank"]
  }
}
```

---

### Test 4: Search Without Query Parameter

**Request Name:** `Error Test 4: Search Missing Query`

**Method:** GET

**URL:** `{{base_url}}/chat_applications/{{app_token}}/chats/{{chat_number}}/messages/search`

**Headers:**
```
Content-Type: application/json
```

**Body:** None

**Expected Response (400 Bad Request):**
```json
{
  "error": "Query parameter required"
}
```

---

### Test 5: Get Non-existent Chat

**Request Name:** `Error Test 5: Non-existent Chat`

**Method:** GET

**URL:** `{{base_url}}/chat_applications/{{app_token}}/chats/999`

**Headers:**
```
Content-Type: application/json
```

**Body:** None

**Expected Response (404 Not Found):**
```json
{
  "error": "Chat not found"
}
```

---

### Test 6: Get Non-existent Message

**Request Name:** `Error Test 6: Non-existent Message`

**Method:** GET

**URL:** `{{base_url}}/chat_applications/{{app_token}}/chats/{{chat_number}}/messages/999`

**Headers:**
```
Content-Type: application/json
```

**Body:** None

**Expected Response (404 Not Found):**
```json
{
  "error": "Message not found"
}
```

---

## Testing Concurrent Requests

To test race-condition safety of sequential numbering:

### Test Sequential Chat Creation

1. Create 5 chats in rapid succession:
   - Click **Create Chat 1** → Send
   - Click **Create Chat 2** (another instance) → Send
   - Continue for 5 requests

2. Verify:
   - All 5 requests return different numbers (1, 2, 3, 4, 5)
   - No two chats have the same number
   - All requests succeed with 201 status

### Test Sequential Message Creation

1. Create 10 messages in rapid succession:
   - Send Create Message 1, 2, 3... in quick succession

2. Verify:
   - All 10 messages have different numbers (1-10)
   - No two messages have the same number
   - All requests succeed with 201 status

---

## Postman Collection JSON (Ready to Import)

Create a file named `Chat-System-API.postman_collection.json`:

```json
{
  "info": {
    "name": "Chat System API",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "item": [
    {
      "name": "Chat Applications",
      "item": [
        {
          "name": "1. Create Chat Application",
          "request": {
            "method": "POST",
            "header": [
              {
                "key": "Content-Type",
                "value": "application/json"
              }
            ],
            "body": {
              "mode": "raw",
              "raw": "{\"chat_application\": {\"name\": \"My Test Chat App\"}}"
            },
            "url": {
              "raw": "{{base_url}}/chat_applications",
              "host": ["{{base_url}}"],
              "path": ["chat_applications"]
            }
          }
        },
        {
          "name": "2. Get Chat Application",
          "request": {
            "method": "GET",
            "header": [],
            "url": {
              "raw": "{{base_url}}/chat_applications/{{app_token}}",
              "host": ["{{base_url}}"],
              "path": ["chat_applications", "{{app_token}}"]
            }
          }
        },
        {
          "name": "3. List Chat Applications",
          "request": {
            "method": "GET",
            "header": [],
            "url": {
              "raw": "{{base_url}}/chat_applications",
              "host": ["{{base_url}}"],
              "path": ["chat_applications"]
            }
          }
        },
        {
          "name": "4. Update Chat Application",
          "request": {
            "method": "PATCH",
            "header": [
              {
                "key": "Content-Type",
                "value": "application/json"
              }
            ],
            "body": {
              "mode": "raw",
              "raw": "{\"chat_application\": {\"name\": \"Updated Name\"}}"
            },
            "url": {
              "raw": "{{base_url}}/chat_applications/{{app_token}}",
              "host": ["{{base_url}}"],
              "path": ["chat_applications", "{{app_token}}"]
            }
          }
        }
      ]
    },
    {
      "name": "Chats",
      "item": [
        {
          "name": "5. Create Chat",
          "request": {
            "method": "POST",
            "header": [],
            "url": {
              "raw": "{{base_url}}/chat_applications/{{app_token}}/chats",
              "host": ["{{base_url}}"],
              "path": ["chat_applications", "{{app_token}}", "chats"]
            }
          }
        },
        {
          "name": "7. List Chats",
          "request": {
            "method": "GET",
            "header": [],
            "url": {
              "raw": "{{base_url}}/chat_applications/{{app_token}}/chats",
              "host": ["{{base_url}}"],
              "path": ["chat_applications", "{{app_token}}", "chats"]
            }
          }
        },
        {
          "name": "8. Get Chat by Number",
          "request": {
            "method": "GET",
            "header": [],
            "url": {
              "raw": "{{base_url}}/chat_applications/{{app_token}}/chats/1",
              "host": ["{{base_url}}"],
              "path": ["chat_applications", "{{app_token}}", "chats", "1"]
            }
          }
        }
      ]
    },
    {
      "name": "Messages",
      "item": [
        {
          "name": "9. Create Message",
          "request": {
            "method": "POST",
            "header": [
              {
                "key": "Content-Type",
                "value": "application/json"
              }
            ],
            "body": {
              "mode": "raw",
              "raw": "{\"message\": {\"body\": \"Hello! This is a test message.\"}}"
            },
            "url": {
              "raw": "{{base_url}}/chat_applications/{{app_token}}/chats/{{chat_number}}/messages",
              "host": ["{{base_url}}"],
              "path": ["chat_applications", "{{app_token}}", "chats", "{{chat_number}}", "messages"]
            }
          }
        },
        {
          "name": "12. List Messages",
          "request": {
            "method": "GET",
            "header": [],
            "url": {
              "raw": "{{base_url}}/chat_applications/{{app_token}}/chats/{{chat_number}}/messages",
              "host": ["{{base_url}}"],
              "path": ["chat_applications", "{{app_token}}", "chats", "{{chat_number}}", "messages"]
            }
          }
        },
        {
          "name": "13. Get Message by Number",
          "request": {
            "method": "GET",
            "header": [],
            "url": {
              "raw": "{{base_url}}/chat_applications/{{app_token}}/chats/{{chat_number}}/messages/1",
              "host": ["{{base_url}}"],
              "path": ["chat_applications", "{{app_token}}", "chats", "{{chat_number}}", "messages", "1"]
            }
          }
        },
        {
          "name": "14. Search Messages",
          "request": {
            "method": "GET",
            "header": [],
            "url": {
              "raw": "{{base_url}}/chat_applications/{{app_token}}/chats/{{chat_number}}/messages/search?q=hello",
              "host": ["{{base_url}}"],
              "path": ["chat_applications", "{{app_token}}", "chats", "{{chat_number}}", "messages", "search"],
              "query": [
                {
                  "key": "q",
                  "value": "hello"
                }
              ]
            }
          }
        }
      ]
    }
  ]
}
```

---

## Complete Testing Checklist

Use this checklist to verify all functionality:

### Chat Applications ✅
- [ ] Create application
- [ ] Get application by token
- [ ] List all applications
- [ ] Update application name
- [ ] Verify token is unique
- [ ] Verify chats_count updates

### Chats ✅
- [ ] Create first chat (gets number 1)
- [ ] Create second chat (gets number 2)
- [ ] List all chats for application
- [ ] Get specific chat by number
- [ ] Verify sequential numbering

### Messages ✅
- [ ] Create first message (gets number 1)
- [ ] Create second message (gets number 2)
- [ ] Create third message (gets number 3)
- [ ] List all messages in chat
- [ ] Get specific message by number
- [ ] Verify sequential numbering

### Search ✅
- [ ] Search for "hello" (returns matching messages)
- [ ] Search for "world" (returns different messages)
- [ ] Verify partial matching works
- [ ] Verify chat isolation (search only in current chat)

### Error Handling ✅
- [ ] Missing required field (422)
- [ ] Non-existent application (404)
- [ ] Non-existent chat (404)
- [ ] Non-existent message (404)
- [ ] Missing search query (400)

---

## Tips for Postman

1. **Use Collections:** Organize requests into logical folders
2. **Use Variables:** Store app_token, chat_number for easy reference
3. **Use Tests Tab:** Write scripts to automatically extract and save data
4. **Use Pre-request Scripts:** Set up data before requests
5. **Export Results:** Save test results for documentation
6. **Use Environments:** Different configs for dev/test/prod

---

## Troubleshooting

### Error: "Cannot read property 'json' of undefined"
- Make sure request completed successfully before running Tests
- Check response is valid JSON

### Error: "No response received"
- Verify Chat System is running: `docker-compose ps`
- Check all services are healthy: `docker-compose logs`

### Error: "404 Not Found"
- Verify URL is correct
- Check you're using correct token/number/chat_number variables
- Verify environment variables are set

### Error: "422 Unprocessable Entity"
- Check request body format is correct JSON
- Verify all required fields are present
- Check field values are not empty

---

## Next Steps

1. Download Postman
2. Start Chat System: `docker-compose up`
3. Wait for services to be healthy (30-60 seconds)
4. Import collection or create requests manually
5. Set up environment variables
6. Execute requests in order
7. Verify all responses match expected results
8. Test error scenarios
9. Test concurrent requests for race conditions
