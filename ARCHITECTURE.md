# Chat System Architecture

## Overview

The Chat System is a scalable, distributed chat API designed to handle high-volume concurrent requests with asynchronous message processing and efficient full-text search capabilities.

## System Components

```
┌─────────────────────────────────────────────────────────────┐
│                     Client Applications                      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Rails API (Puma)                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  ChatApplicationsController                          │   │
│  │  ChatsController                                     │   │
│  │  MessagesController                                 │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
    ┌────────┐          ┌─────────┐          ┌──────────┐
    │ MySQL  │          │  Redis  │          │  Elastic │
    │ (Data) │          │ (Queue) │          │ (Search) │
    └────────┘          └─────────┘          └──────────┘
         │                    │
         │                    ▼
         │          ┌──────────────────┐
         │          │  Sidekiq Worker  │
         │          │  (Background Jobs)│
         │          └──────────────────┘
         │                    │
         └────────────────────┘
```

## Data Flow

### Chat Application Creation
```
POST /chat_applications
  └─> Rails Controller
       ├─> Validate input
       ├─> Generate secure token (SecureRandom.hex(16))
       ├─> Save to MySQL
       └─> Return response with token
```

### Chat Creation
```
POST /chat_applications/:token/chats
  └─> Rails Controller
       ├─> Validate chat_application exists
       ├─> Get next chat number from Redis (INCR)
       ├─> Create Chat in MySQL
       ├─> Queue UpdateChatApplicationCountJob
       └─> Return chat number
```

**Race Condition Prevention:**
- Redis INCR is atomic (thread-safe)
- Database unique index `(chat_application_id, number)` prevents duplicates
- If INCR returns same number to two requests, database constraint ensures only one succeeds

### Message Creation
```
POST /chat_applications/:token/chats/:number/messages
  └─> Rails Controller
       ├─> Validate chat exists
       ├─> Get next message number from Redis (INCR)
       ├─> Create Message in MySQL
       ├─> Queue PersistMessageJob (async)
       └─> Return message number immediately
```

**Async Processing:**
- Message created immediately in MySQL
- Elasticsearch indexing happens in background
- Client gets fast response (sub-100ms typical)
- Message indexing completes within seconds

### Message Search
```
GET /chat_applications/:token/chats/:number/messages/search?q=hello
  └─> Rails Controller
       ├─> Validate chat exists
       ├─> Query Elasticsearch with filters:
       │   ├─> Match query on 'body'
       │   └─> Term filter on 'chat_id'
       ├─> Fetch matching records from Elasticsearch
       └─> Return results
```

## Database Schema

### chat_applications
```sql
CREATE TABLE chat_applications (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  token VARCHAR(255) NOT NULL UNIQUE,
  chats_count INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_token (token)
);
```

**Why token?**
- Provides secure identifier without exposing internal ID
- Easier for API clients to work with
- Can be rotated/regenerated without breaking system

**Why chats_count?**
- Avoids expensive COUNT(*) queries
- Updated asynchronously (not real-time)
- Acceptable lag of up to 1 hour per requirements

### chats
```sql
CREATE TABLE chats (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  chat_application_id BIGINT NOT NULL,
  number INT NOT NULL,
  messages_count INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (chat_application_id) REFERENCES chat_applications(id),
  UNIQUE INDEX idx_app_number (chat_application_id, number),
  INDEX idx_app_id (chat_application_id)
);
```

**Composite Key Strategy:**
- Chat number is unique per application (not global)
- Allows number 1 in App A and number 1 in App B
- Efficient queries with `(app_id, number)` index

### messages
```sql
CREATE TABLE messages (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  chat_id BIGINT NOT NULL,
  number INT NOT NULL,
  body TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (chat_id) REFERENCES chats(id),
  UNIQUE INDEX idx_chat_number (chat_id, number),
  INDEX idx_chat_id (chat_id),
  FULLTEXT INDEX idx_body (body)
);
```

## Sequential Numbering Strategy

### Problem
Multiple concurrent requests need to get sequential numbers (1, 2, 3, ...) without conflicts.

### Solution: Redis + Database Constraints

**Step 1: Redis INCR (Fast, Atomic)**
```ruby
number = redis.incr("chat_app:#{app_id}:chat_counter")
# Returns 1, 2, 3, ... atomically
```

**Step 2: Database Unique Index (Safe)**
```sql
UNIQUE INDEX idx_app_number (chat_application_id, number)
```

**Race Condition Handling:**
1. Request A and B both get number 1 from Redis
2. Request A saves successfully
3. Request B tries to save with same number
4. Database unique constraint rejects Request B
5. Request B retries and gets number 2 from Redis

**Trade-off:** Rare retries in extreme race conditions vs. ensuring correctness.

## Redis Usage

### Keys and Purposes

```
chat_app:{app_id}:chat_counter          # Counter for chat numbers
chat:{chat_id}:message_counter          # Counter for message numbers
```

**Why Redis?**
- Atomic INCR operation (thread-safe)
- Fast key-value operations
- Survives application restarts
- Can be persisted or used ephemerally

## Elasticsearch Integration

### Index Mapping

```json
{
  "mappings": {
    "properties": {
      "id": { "type": "keyword" },
      "body": { "type": "text", "analyzer": "standard" },
      "chat_id": { "type": "integer" },
      "created_at": { "type": "date" }
    }
  }
}
```

### Indexing Process

**On Message Creation:**
1. Message created in MySQL
2. PersistMessageJob queued in Sidekiq
3. Job indexes message in Elasticsearch
4. Search available within seconds

**Why Async?**
- Elasticsearch writes are slower than MySQL
- Decouples API response from indexing
- Sidekiq provides retry logic automatically

### Search Query

```json
{
  "query": {
    "bool": {
      "must": [
        { "match": { "body": "hello" } },
        { "term": { "chat_id": 123 } }
      ]
    }
  }
}
```

**Features:**
- Partial matching (text analysis)
- Chat isolation (term filter)
- Efficient scoring

## Sidekiq Background Jobs

### Jobs

**PersistMessageJob**
- Triggered: After message creation
- Action: Index in Elasticsearch, queue count update
- Retry: Automatic (configurable)
- Impact: Search availability

**UpdateChatApplicationCountJob**
- Triggered: After chat creation
- Action: Count chats, update chats_count field
- Retry: Automatic
- Impact: Application count accuracy

**UpdateChatMessageCountJob**
- Triggered: After message creation
- Action: Count messages, update messages_count field
- Retry: Automatic
- Impact: Chat count accuracy

### Queue Configuration

```
Default: High priority queue
Workers: 5 (configurable in docker-compose.yml)
Retry: Automatic up to 25 times
```

## Concurrency Handling

### Scenario: 1000 messages created simultaneously

**Without proper design:**
- Race condition on message number
- Multiple messages with same number
- Inconsistent state

**With this design:**
1. Redis serves 1000 INCR requests atomically
2. Each gets unique number (1-1000)
3. All saved to MySQL with correct numbers
4. Database indices prevent duplicates
5. Elasticsearch indexed asynchronously
6. System remains consistent

## Performance Optimizations

### 1. Connection Pooling
```yml
pool: 5  # Per Rails guidelines
```
- Reuses database connections
- Reduces connection overhead

### 2. Query Optimization
- All lookups use indexed columns
- No N+1 queries in API responses
- Cached counts reduce aggregation

### 3. Async Processing
- Message creation returns immediately
- Heavy lifting (indexing) in background
- Throughput not blocked by slow operations

### 4. Redis Caching
- Sequential numbers cached in Redis
- No database hit for incrementing
- Microsecond-level response times

### 5. Elasticsearch
- Full-text search without database hits
- Parallel indexing in background
- Scales independently

## Scaling Considerations

### Horizontal Scaling

**Multiple Rails Servers:**
- Share same MySQL, Redis, Elasticsearch
- Load balancer distributes requests
- All instances use same Redis counters (atomic)
- All instances queue to same Sidekiq queues

**Multiple Sidekiq Workers:**
- Scale independently
- Process jobs in parallel
- Auto-retry failed jobs
- Monitor with Sidekiq UI

**Database Replication:**
- MySQL primary-replica setup
- Replica for reads (search, listings)
- Primary for writes
- Connection pooling handles failover

### Vertical Scaling
- Increase container resources
- More Puma threads
- More Sidekiq workers
- Larger MySQL buffer pool

## Monitoring & Observability

### Application Logs
```
docker-compose logs web      # API logs
docker-compose logs sidekiq  # Worker logs
```

### Health Checks
```bash
# Rails health
curl http://localhost:3000/up

# MySQL
docker-compose exec mysql mysqladmin ping

# Redis
docker-compose exec redis redis-cli ping

# Elasticsearch
curl http://localhost:9200/_cluster/health
```

### Key Metrics
- Request latency (API response time)
- Job queue depth (Sidekiq)
- Elasticsearch index size
- MySQL slow query log
- Redis hit/miss ratio

## Security Considerations

### Token Generation
- SecureRandom.hex(16) = 128 bits entropy
- Not guessable or enumerable
- Unique constraint in database

### SQL Injection Prevention
- Rails ORM (ActiveRecord) prevents injection
- All queries parameterized
- No raw SQL in application code

### Access Control
- Token required for all operations
- No global enumeration endpoints
- Clients isolated by token

## Disaster Recovery

### Data Backup
```bash
# MySQL backup
docker-compose exec mysql mysqldump -u chat_user -p \
  chat_system_development > backup.sql

# Redis persistence
Redis data persisted to volume
```

### Recovery Procedures
```bash
# Rebuild database
docker-compose exec web rails db:migrate

# Reindex Elasticsearch
docker-compose exec web rails Message.__elasticsearch__.create_index!
Message.import
```

## Future Improvements

1. **Message Pagination**
   - Limit results per page
   - Cursor-based pagination for efficiency

2. **Rate Limiting**
   - Per-token rate limits
   - Prevent abuse

3. **WebSocket Support**
   - Real-time message delivery
   - Reduce polling

4. **Read Replicas**
   - Separate read/write databases
   - Better scalability

5. **Message Encryption**
   - End-to-end encryption
   - Improved privacy

6. **Audit Logging**
   - Track all operations
   - Compliance/debugging
