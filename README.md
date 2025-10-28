# Chat System API

A scalable, production-ready chat system API built with Ruby on Rails that handles concurrent requests, asynchronous message processing, and full-text search capabilities.

> ⚠️ Note: The `.env` file is intentionally included for interview purposes.  
> It contains only non-sensitive development credentials.

## Stack

- **Framework:** Ruby on Rails 8.1 (API only)
- **Database:** MySQL 8.0
- **Cache/Queue:** Redis 7
- **Search Engine:** Elasticsearch 7.17
- **Background Jobs:** Sidekiq 7.0
- **Web Server:** Puma 6.0+
- **Testing:** RSpec 6.0
- **Containerization:** Docker & Docker Compose

## Features

- ✅ Create and manage chat applications with unique tokens
- ✅ Sequential numbering for chats and messages (race-condition safe)
- ✅ Full-text message search via Elasticsearch
- ✅ Asynchronous message processing with Sidekiq
- ✅ Automatic count tracking (chats_count, messages_count)
- ✅ RESTful API with comprehensive error handling
- ✅ Database indices for optimized queries
- ✅ Containerized infrastructure with docker-compose
- ✅ Comprehensive RSpec test suite

## Quick Start

### Prerequisites

- Docker & Docker Compose installed
- No need to install Ruby, MySQL, Redis, or Elasticsearch manually!

### Setup & Run

```bash
# Clone/navigate to the project
cd Chat_system

# Start the entire stack with one command
docker-compose up

# The API will be available at http://localhost:3000
```

The docker-compose will automatically:

1. Start MySQL, Redis, and Elasticsearch containers
2. Build the Rails application
3. Run database migrations
4. Start the Rails server (Puma)
5. Start the Sidekiq worker for background jobs

## API Documentation

### Base URL

```
http://localhost:3000/api/v1
```

### Create Chat Application

**Endpoint:**

```
POST /chat_applications
```

**Request:**

```json
{
  "chat_application": {
    "name": "My Chat App"
  }
}
```

**Response (201 Created):**

```json
{
  "id": 1,
  "name": "My Chat App",
  "token": "a1b2c3d4e5f6...",
  "chats_count": 0
}
```

### Get Chat Application

**Endpoint:**

```
GET /chat_applications/:token
```

**Response (200 OK):**

```json
{
  "id": 1,
  "name": "My Chat App",
  "token": "a1b2c3d4e5f6...",
  "chats_count": 5
}
```

### Create Chat

**Endpoint:**

```
POST /chat_applications/:token/chats
```

**Response (201 Created):**

```json
{
  "number": 1,
  "messages_count": 0
}
```

Note: Chat number is auto-generated sequentially starting from 1.

### Get All Chats for Application

**Endpoint:**

```
GET /chat_applications/:token/chats
```

**Response (200 OK):**

```json
[
  {
    "number": 1,
    "messages_count": 5
  },
  {
    "number": 2,
    "messages_count": 0
  }
]
```

### Get Specific Chat

**Endpoint:**

```
GET /chat_applications/:token/chats/:number
```

**Response (200 OK):**

```json
{
  "number": 1,
  "messages_count": 5
}
```

### Create Message

**Endpoint:**

```
POST /chat_applications/:token/chats/:number/messages
```

**Request:**

```json
{
  "message": {
    "body": "Hello, world!"
  }
}
```

**Response (201 Created):**

```json
{
  "number": 1
}
```

Note: Message number is auto-generated sequentially starting from 1 for each chat.

### Get All Messages in Chat

**Endpoint:**

```
GET /chat_applications/:token/chats/:number/messages
```

**Response (200 OK):**

```json
[
  {
    "number": 1,
    "body": "Hello, world!"
  },
  {
    "number": 2,
    "body": "How are you?"
  }
]
```

### Get Specific Message

**Endpoint:**

```
GET /chat_applications/:token/chats/:number/messages/:number
```

**Response (200 OK):**

```json
{
  "number": 1,
  "body": "Hello, world!"
}
```

### Search Messages in Chat

**Endpoint:**

```
GET /chat_applications/:token/chats/:number/messages/search?q=hello
```

**Query Parameters:**

- `q` (required): Search query for partial matching against message body

**Response (200 OK):**

```json
[
  {
    "number": 1,
    "body": "Hello, world!"
  },
  {
    "number": 3,
    "body": "Hello again!"
  }
]
```

## Running Tests

```bash
# Inside the Docker container
docker-compose exec web bundle exec rspec

# Or locally (if Rails is installed)
bundle exec rspec

# Run specific test file
bundle exec rspec spec/requests/api/v1/chat_applications_spec.rb

# Run with coverage
bundle exec rspec --format coverage
```

## Architecture

### Database Schema

**chat_applications:**

- `id`: Primary key
- `name`: Application name
- `token`: Unique identifier (generated automatically)
- `chats_count`: Cached count of chats
- `created_at`, `updated_at`: Timestamps

**chats:**

- `id`: Primary key
- `chat_application_id`: Foreign key to chat_applications
- `number`: Sequential number within application (starts from 1)
- `messages_count`: Cached count of messages
- `created_at`, `updated_at`: Timestamps

**messages:**

- `id`: Primary key
- `chat_id`: Foreign key to chats
- `number`: Sequential number within chat (starts from 1)
- `body`: Message content
- `created_at`: Timestamp

### Key Design Decisions

1. **Sequential Numbering:**

   - Implemented using Redis atomic INCR operations
   - Race-condition safe for concurrent requests
   - Database unique indices provide final safeguard

2. **Async Processing:**

   - Message creation returns immediately (optimized for latency)
   - Sidekiq jobs handle Elasticsearch indexing
   - Count updates queued asynchronously

3. **Search:**

   - Elasticsearch provides full-text search
   - Messages indexed automatically on creation
   - Supports partial matching on message body

4. **Indices:**

   - Unique index on (chat_application_id, chat.number)
   - Unique index on (chat_id, message.number)
   - Full-text index on message body for search
   - Composite index on (chat_application_id) for fast lookups

5. **Token Generation:**
   - Using SecureRandom.hex(16) for 128-bit unique tokens
   - Prevents ID enumeration attacks

## Environment Variables

Configure in docker-compose.yml or .env:

```
RAILS_ENV=development
DATABASE_USER=chat_user
DATABASE_PASSWORD=password
DATABASE_HOST=mysql
DATABASE_PORT=3306
REDIS_URL=redis://redis:6379/0
ELASTICSEARCH_URL=http://elasticsearch:9200
RAILS_MASTER_KEY=insecure (for development only)
```

## Troubleshooting

### Elasticsearch not ready

```
Wait for Elasticsearch to fully start (30-60 seconds)
Check: curl http://localhost:9200/_cluster/health
```

### Database migration errors

```
docker-compose exec web rails db:reset
docker-compose exec web rails db:migrate
```

### Redis connection issues

```
docker-compose exec redis redis-cli ping
# Should return: PONG
```

### Sidekiq worker not processing jobs

```
docker-compose logs sidekiq
docker-compose restart sidekiq
```

## Performance Considerations

1. **Concurrent Request Handling:**

   - Redis atomic operations prevent race conditions
   - Connection pooling configured per Rails guidelines
   - Sidekiq workers scale independently

2. **Database Optimization:**

   - All queries use indexed columns
   - Count caches reduce COUNT(\*) queries
   - Foreign key constraints ensure data integrity

3. **Search Performance:**

   - Elasticsearch handles full-text search efficiently
   - Index size managed automatically
   - Search results cached in client layer

4. **Message Throughput:**
   - Asynchronous processing enables high message volume
   - Sidekiq queue can process thousands of messages/minute
   - Redis provides fast queue operations

## Development

### File Structure

```
Chat_system/
├── app/
│   ├── controllers/api/v1/
│   │   ├── chat_applications_controller.rb
│   │   ├── chats_controller.rb
│   │   └── messages_controller.rb
│   ├── models/
│   │   ├── chat_application.rb
│   │   ├── chat.rb
│   │   └── message.rb
│   ├── jobs/
│   │   ├── persist_message_job.rb
│   │   ├── update_chat_application_count_job.rb
│   │   └── update_chat_message_count_job.rb
│   └── services/
│       └── sequential_number_service.rb
├── config/
│   ├── database.yml
│   ├── routes.rb
│   └── initializers/
│       ├── elasticsearch.rb
│       ├── redis.rb
│       └── sidekiq.rb
├── db/
│   └── migrate/
├── spec/
│   ├── models/
│   ├── requests/
│   └── factories/
├── docker-compose.yml
└── Dockerfile
```

### Adding Features

1. Create migration: `rails generate migration ...`
2. Update model: `app/models/`
3. Add tests: `spec/models/` or `spec/requests/`
4. Create controller/action if needed
5. Run tests: `bundle exec rspec`

## Support & Contact

For issues, please check the troubleshooting section or examine logs:

```
docker-compose logs web      # Rails logs
docker-compose logs sidekiq  # Worker logs
docker-compose logs mysql    # Database logs
docker-compose logs redis    # Cache logs
```
