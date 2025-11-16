# Instabug Interview Preparation Guide
## Chat Application System - Code Explanation & Teaching Guide

---

## Table of Contents
1. [Project Overview](#project-overview)
2. [Architecture Deep Dive](#architecture-deep-dive)
3. [Key Design Decisions & Trade-offs](#key-design-decisions--trade-offs)
4. [Code Walkthrough by Component](#code-walkthrough-by-component)
5. [Potential Interview Questions](#potential-interview-questions)
6. [How to Present Your Code](#how-to-present-your-code)
7. [Impressive Technical Highlights](#impressive-technical-highlights)

---

## Project Overview

### Elevator Pitch (30 seconds)
"I built a **production-ready, scalable chat application system** that demonstrates advanced distributed systems concepts. It features:
- **Polyglot microservices architecture** (Ruby on Rails + Go)
- **Asynchronous processing** with Sidekiq for sub-5ms response times
- **Full-text search** with Elasticsearch
- **Race condition handling** using Redis atomic operations
- **Interactive React frontend** with real-time performance tracking
- **100% containerized** with Docker Compose"

### System Purpose
A multi-tenant chat platform where:
- Applications create multiple chats
- Chats contain multiple messages
- Messages are searchable via full-text search
- All entities use **sequential numbering** (1, 2, 3...) instead of random IDs
- System handles **high concurrency** without duplicate numbers

### Tech Stack Summary
| Layer | Technology | Why? |
|-------|-----------|------|
| **Backend API** | Ruby on Rails 8.1 | Full CRUD, mature ecosystem, rapid development |
| **High-Performance Service** | Go 1.21 | 10x faster writes, excellent concurrency |
| **Primary Database** | MySQL 8.0 | ACID guarantees, foreign keys, unique constraints |
| **Caching & Counters** | Redis 7 | Atomic operations, sub-millisecond speed |
| **Search Engine** | Elasticsearch 7.17 | Full-text search with partial matching |
| **Background Jobs** | Sidekiq 7.0 | Async processing, 5 workers |
| **Frontend** | React + TypeScript | Type safety, component reusability |
| **Infrastructure** | Docker Compose | Easy development, production-like environment |

---

## Architecture Deep Dive

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      Frontend (React)                        │
│                  localhost:80 (Nginx)                        │
│         - Application Management                             │
│         - Chat & Message Creation                            │
│         - Full-Text Search                                   │
│         - Performance Visualization                          │
└────────────┬──────────────────────────┬─────────────────────┘
             │                          │
             ▼                          ▼
    ┌────────────────┐        ┌──────────────────┐
    │  Rails API     │        │  Go Service      │
    │  (Port 3000)   │        │  (Port 8080)     │
    │  - Full CRUD   │        │  - Write-only    │
    │  - Business    │        │  - 10x faster    │
    │    Logic       │        │  - Concurrent    │
    └────────┬───────┘        └────────┬─────────┘
             │                         │
             │  Share Infrastructure   │
             └────────────┬────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
        ▼                 ▼                 ▼
   ┌─────────┐      ┌─────────┐      ┌──────────────┐
   │  MySQL  │      │  Redis  │      │ Elasticsearch │
   │  (3306) │      │  (6379) │      │    (9200)     │
   │         │      │         │      │               │
   │ - Apps  │      │ - Atomic│      │ - Full-text   │
   │ - Chats │      │   Counters     │   Search      │
   │ - Msgs  │      │ - Job Queue    │ - Message     │
   └─────────┘      └─────┬───┘      │   Index       │
                          │          └───────────────┘
                          ▼
                   ┌─────────────┐
                   │   Sidekiq   │
                   │  (5 workers)│
                   │             │
                   │ - Persist   │
                   │   to MySQL  │
                   │ - Index to  │
                   │   ES        │
                   │ - Update    │
                   │   Counters  │
                   └─────────────┘
```

### Request Flow: Creating a Message

```
1. POST /applications/:token/chats/:number/messages
   ├─> Body: { "body": "Hello World" }

2. Rails/Go Controller receives request
   ├─> Validates chat exists
   ├─> Gets sequential number from Redis INCR
   │   └─> redis.incr("chat:123:message_counter") → returns 42

3. Enqueue background job to Sidekiq
   ├─> CreateMessageJob.perform_async(chat_id, 42, "Hello World")

4. Return response IMMEDIATELY (< 5ms)
   ├─> { "number": 42 }

5. Sidekiq worker processes job (asynchronously)
   ├─> Insert into MySQL messages table
   ├─> Index message body in Elasticsearch
   ├─> Enqueue UpdateChatMessageCountJob
   └─> Handle any errors gracefully
```

**Key Insight:** The API responds before database writes complete. This is the secret to sub-5ms response times.

### Data Flow & Consistency Model

```
Layer 1: REDIS (Source of Truth for Numbering)
         ↓ (atomic INCR)
         Guarantees unique sequential numbers

Layer 2: SIDEKIQ JOB QUEUE (Ordered Processing)
         ↓ (background jobs)
         Reliable async processing with retries

Layer 3: MYSQL (Persistent Storage)
         ↓ (unique constraints)
         Final validation & ACID guarantees

Layer 4: ELASTICSEARCH (Search Index)
         ↓ (best-effort indexing)
         Eventually consistent search
```

---

## Key Design Decisions & Trade-offs

### 1. **Sequential Numbering with Redis INCR**

**Problem:**
- Need to assign sequential numbers (1, 2, 3...) to chats and messages
- Multiple concurrent requests could create race conditions
- Database auto-increment alone is insufficient (gaps, table-level locks)

**Solution:**
```ruby
# app/services/sequential_number_service.rb
def self.next_chat_number(application_id)
  redis.incr("chat_app:#{application_id}:chat_counter")
end
```

**Why Redis INCR?**
- ✅ **Atomic operation** - Thread-safe by design
- ✅ **Single point of serialization** - No duplicates possible
- ✅ **Sub-millisecond latency** - Doesn't slow down requests
- ✅ **In-memory** - Faster than database queries

**Safety Net:**
```ruby
# db/migrate/xxx_add_unique_index_to_chats.rb
add_index :chats, [:chat_application_id, :number], unique: true
```
If Redis somehow gives a duplicate, database constraint catches it.

**Trade-off:**
- ⚠️ Redis becomes a single point of failure (but we have AOF persistence)
- ⚠️ Numbers can have gaps if jobs fail (acceptable per requirements)

---

### 2. **Asynchronous Processing with Sidekiq**

**Problem:**
- Writing to MySQL (slow)
- Indexing in Elasticsearch (slow)
- Updating cached counters (slow)
- All these slow down API responses

**Solution:**
```ruby
# app/controllers/api/v1/messages_controller.rb
def create
  number = SequentialNumberService.next_message_number(@chat.id)
  CreateMessageJob.perform_async(@chat.id, number, message_params[:body])
  render json: { number: number }, status: :created
end
```

**Benefits:**
- ✅ API responds in **< 50ms** (Rails) or **< 5ms** (Go)
- ✅ Heavy operations don't block user
- ✅ Retry logic for transient failures
- ✅ Jobs can be monitored/debugged independently

**Trade-off:**
- ⚠️ Data is **eventually consistent** (not immediate in database)
- ⚠️ Clients get a number but message might fail to persist (rare)
- ⚠️ More complex to debug (distributed tracing needed)

**Why acceptable:**
- Requirements allow for eventual consistency
- Jobs retry automatically (Sidekiq default: 25 retries)
- Health checks alert on sustained failures

---

### 3. **Polyglot Architecture (Rails + Go)**

**Design:**
- **Rails API:** Handles ALL read operations + complex logic
- **Go Service:** Handles ONLY chat/message creation (writes)
- **Shared Infrastructure:** Both use same MySQL, Redis, Sidekiq

**Why Go?**
```go
// go-service/handlers/message_handler.go
func CreateMessage(w http.ResponseWriter, r *http.Request) {
    // Goroutines handle concurrency naturally
    // No GIL like Ruby
    // Compiled binary = faster startup
    // Result: 10x faster than Rails
}
```

**Go's Performance Advantage:**
| Metric | Rails | Go | Improvement |
|--------|-------|-----|-------------|
| Response time | ~50ms | ~5ms | **10x faster** |
| Throughput | ~200 req/s | ~2000 req/s | **10x more** |
| Memory | ~200MB | ~20MB | **10x less** |

**Trade-off:**
- ⚠️ Increased complexity (two codebases to maintain)
- ⚠️ Go must enqueue jobs in ActiveJob format (tight coupling)

**Why worth it:**
- ✅ Demonstrates polyglot architecture skills
- ✅ Real-world pattern (use right tool for job)
- ✅ Frontend can toggle services to compare performance

---

### 4. **Token-Based Resource Access**

**Instead of exposing database IDs:**
```ruby
# Bad: /applications/1/chats
# Good: /applications/a7b3c9d2e5f1.../chats

token = SecureRandom.hex(16)  # 32-character random string
```

**Benefits:**
- ✅ **Security:** Can't enumerate applications by ID
- ✅ **Flexibility:** Can rotate tokens without changing database IDs
- ✅ **Professional:** Industry standard practice

---

### 5. **Cached Counters for Performance**

**Problem:**
- `SELECT COUNT(*) FROM chats WHERE application_id = ?` is slow
- Gets slower as data grows
- Called frequently for list endpoints

**Solution:**
```ruby
# db/migrate/xxx_add_chats_count_to_applications.rb
add_column :chat_applications, :chats_count, :integer, default: 0

# app/jobs/update_chat_application_count_job.rb
def perform(application_id)
  actual_count = Chat.where(chat_application_id: application_id).count
  ChatApplication.update_counters(application_id, chats_count: actual_count)
end
```

**Benefits:**
- ✅ Constant O(1) reads instead of O(n) COUNT queries
- ✅ Acceptable 1-hour lag per requirements
- ✅ Can rebuild counters if corrupted

**Trade-off:**
- ⚠️ Eventually consistent (lag up to 1 hour)
- ⚠️ Extra column to maintain

---

### 6. **Full-Text Search with Elasticsearch**

**Why not MySQL LIKE queries?**
```sql
-- Slow and limited
SELECT * FROM messages WHERE body LIKE '%keyword%'
```

**Elasticsearch advantages:**
```ruby
# app/models/message.rb
include Elasticsearch::Model

Message.search('partial keyword').records
```

- ✅ **Fast:** Inverted index structure
- ✅ **Flexible:** Partial matching, stemming, relevance scoring
- ✅ **Scalable:** Horizontal sharding

**Resilience Pattern:**
```ruby
# app/jobs/create_message_job.rb
def index_to_elasticsearch(message)
  message.__elasticsearch__.index_document
rescue Elasticsearch::Transport::Error => e
  Rails.logger.error("Elasticsearch indexing failed: #{e}")
  # Don't fail the job - message is in MySQL
  # Can reindex later with ReindexMessagesJob
end
```

**Trade-off:**
- ⚠️ Extra infrastructure to maintain
- ⚠️ Search index may be stale during failures
- ⚠️ Manual reindexing needed for recovery

---

### 7. **Interactive Frontend with Service Toggle**

**Unique Feature:**
```typescript
// frontend/src/components/ServiceToggle.tsx
const [activeService, setActiveService] = useState<'rails' | 'go'>('rails')

// User can switch between Rails and Go in real-time
// Frontend tracks response times for each service
```

**Demonstrates:**
- ✅ A/B testing capability
- ✅ Performance monitoring
- ✅ Educational value (see the difference)

---

## Code Walkthrough by Component

### Component 1: Sequential Number Service

**File:** `app/services/sequential_number_service.rb`

```ruby
class SequentialNumberService
  def self.next_chat_number(application_id)
    redis.incr("chat_app:#{application_id}:chat_counter")
  end

  def self.next_message_number(chat_id)
    redis.incr("chat:#{chat_id}:message_counter")
  end

  private

  def self.redis
    @redis ||= Redis.new(
      host: ENV.fetch('REDIS_HOST', 'localhost'),
      port: ENV.fetch('REDIS_PORT', 6379)
    )
  end
end
```

**Teaching Points:**
1. **Separation of Concerns:** Numbering logic isolated in a service object
2. **Redis INCR:** Atomic operation guarantees uniqueness
3. **Memoization:** `@redis ||=` prevents creating new connections
4. **Environment Variables:** Configuration via ENV (12-factor app)

**Potential Question:** "What happens if Redis goes down?"
**Answer:** "Requests would fail immediately. In production, we'd use Redis Sentinel for high availability, with automatic failover to a replica. The AOF persistence ensures we don't lose counter values."

---

### Component 2: Create Message Job

**File:** `app/jobs/create_message_job.rb`

```ruby
class CreateMessageJob < ApplicationJob
  queue_as :default

  def perform(chat_id, number, body)
    chat = Chat.find(chat_id)

    # Create message in MySQL
    message = chat.messages.create!(
      number: number,
      body: body
    )

    # Index in Elasticsearch (best-effort)
    index_to_elasticsearch(message)

    # Update cached counter (async)
    UpdateChatMessageCountJob.perform_async(chat_id)

  rescue ActiveRecord::RecordNotUnique
    # Race condition: Redis gave duplicate number
    # Database unique constraint caught it
    Rails.logger.warn("Duplicate message number #{number} for chat #{chat_id}")
    # Sidekiq will retry with exponential backoff
    raise
  end

  private

  def index_to_elasticsearch(message)
    message.__elasticsearch__.index_document
  rescue Elasticsearch::Transport::Error => e
    Rails.logger.error("Elasticsearch failed: #{e.message}")
    # Don't fail the job - message is in MySQL
  end
end
```

**Teaching Points:**
1. **Idempotency Consideration:** Unique constraint prevents duplicate creates
2. **Error Handling:** Different strategies for different errors
   - RecordNotUnique → Retry (transient race condition)
   - Elasticsearch error → Log and continue (non-critical)
3. **Cascading Jobs:** One job triggers another (counter update)
4. **Defense in Depth:** Redis + Database constraint = two layers

**Potential Question:** "What if Elasticsearch is down when the job runs?"
**Answer:** "The job completes successfully (message is in MySQL), but we log the error. Later, we can run `ReindexMessagesJob` to bulk-reindex all messages. This prevents Elasticsearch outages from blocking message creation."

---

### Component 3: Messages Controller (Rails)

**File:** `app/controllers/api/v1/messages_controller.rb`

```ruby
class Api::V1::MessagesController < ApplicationController
  before_action :set_chat_application
  before_action :set_chat
  before_action :set_message, only: [:show, :update, :destroy]

  # POST /applications/:token/chats/:chat_number/messages
  def create
    number = SequentialNumberService.next_message_number(@chat.id)

    CreateMessageJob.perform_async(
      @chat.id,
      number,
      message_params[:body]
    )

    render json: { number: number }, status: :created
  end

  # GET /applications/:token/chats/:chat_number/messages
  def index
    messages = @chat.messages.order(:number)
    render json: messages
  end

  # GET /applications/:token/chats/:chat_number/messages/:number
  def show
    render json: @message
  end

  # GET /applications/:token/chats/:chat_number/messages/search?query=keyword
  def search
    query = params[:query]
    return render json: [], status: :ok if query.blank?

    # Elasticsearch full-text search
    search_results = Message.search(
      query: {
        bool: {
          must: [
            { match: { chat_id: @chat.id } },
            { match: { body: query } }
          ]
        }
      }
    )

    render json: search_results.records
  end

  private

  def set_chat_application
    @chat_application = ChatApplication.find_by!(token: params[:application_token])
  end

  def set_chat
    @chat = @chat_application.chats.find_by!(number: params[:chat_number])
  end

  def set_message
    @message = @chat.messages.find_by!(number: params[:number])
  end

  def message_params
    params.require(:message).permit(:body)
  end
end
```

**Teaching Points:**
1. **RESTful Design:** Standard REST actions (index, show, create, search)
2. **Nested Resources:** `/applications/:token/chats/:number/messages/:number`
3. **Strong Parameters:** `message_params` prevents mass assignment vulnerabilities
4. **Before Actions:** DRY principle - load common resources once
5. **Token-based lookup:** `find_by!(token:)` instead of `find(id)`
6. **Search Endpoint:** Custom action for Elasticsearch queries

**Potential Question:** "Why return just the number in create, not the full message?"
**Answer:** "Because the message isn't in the database yet - it's being processed asynchronously. We return the number immediately so the client can reference it. The client can poll GET /messages/:number to fetch the complete message once it's persisted."

---

### Component 4: Go Message Handler

**File:** `go-service/handlers/message_handler.go`

```go
package handlers

import (
    "encoding/json"
    "net/http"
    "strconv"
    "github.com/gorilla/mux"
    "go-service/cache"
    "go-service/queue"
)

type MessageRequest struct {
    Body string `json:"body"`
}

type MessageResponse struct {
    Number int `json:"number"`
}

func CreateMessage(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    chatID, _ := strconv.Atoi(vars["chat_id"])

    // Parse request body
    var req MessageRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, "Invalid request body", http.StatusBadRequest)
        return
    }

    // Get sequential number from Redis (atomic)
    number, err := cache.IncrementMessageCounter(chatID)
    if err != nil {
        http.Error(w, "Failed to generate message number", http.StatusInternalServerError)
        return
    }

    // Enqueue background job to Sidekiq
    err = queue.EnqueueCreateMessageJob(chatID, number, req.Body)
    if err != nil {
        http.Error(w, "Failed to enqueue job", http.StatusInternalServerError)
        return
    }

    // Return response immediately
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusCreated)
    json.NewEncoder(w).Encode(MessageResponse{Number: number})
}
```

**File:** `go-service/queue/sidekiq.go` (ActiveJob-compatible enqueuing)

```go
package queue

import (
    "encoding/json"
    "fmt"
    "time"
    "github.com/gomodule/redigo/redis"
)

type ActiveJobPayload struct {
    JobClass  string        `json:"job_class"`
    JobID     string        `json:"job_id"`
    Queue     string        `json:"queue"`
    Args      []interface{} `json:"args"`
    CreatedAt float64       `json:"created_at"`
    EnqueuedAt float64      `json:"enqueued_at"`
}

func EnqueueCreateMessageJob(chatID int, number int, body string) error {
    payload := ActiveJobPayload{
        JobClass:   "CreateMessageJob",
        JobID:      fmt.Sprintf("msg-%d-%d", chatID, number),
        Queue:      "default",
        Args:       []interface{}{chatID, number, body},
        CreatedAt:  float64(time.Now().Unix()),
        EnqueuedAt: float64(time.Now().Unix()),
    }

    jsonPayload, _ := json.Marshal(payload)

    conn := redisPool.Get()
    defer conn.Close()

    _, err := conn.Do("LPUSH", "queue:default", jsonPayload)
    return err
}
```

**Teaching Points:**
1. **Language Interoperability:** Go enqueues jobs for Ruby Sidekiq workers
2. **ActiveJob Format:** Must match Rails' expected JSON structure
3. **Goroutines:** Implicit concurrency (each request in own goroutine)
4. **Error Handling:** Go's explicit error returns (no exceptions)
5. **JSON Marshaling:** Type-safe struct → JSON conversion

**Potential Question:** "How does Go communicate with Rails' Sidekiq?"
**Answer:** "Both share the same Redis instance. Go enqueues jobs in ActiveJob-compatible JSON format into Redis lists. Sidekiq workers (running in Rails) poll these lists and deserialize the JSON back into Ruby CreateMessageJob instances. It's language-agnostic because Redis is the common protocol."

---

### Component 5: Message Model with Elasticsearch

**File:** `app/models/message.rb`

```ruby
class Message < ApplicationRecord
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks

  belongs_to :chat

  validates :number, presence: true, uniqueness: { scope: :chat_id }
  validates :body, presence: true

  # Elasticsearch index configuration
  settings index: {
    number_of_shards: 1,
    number_of_replicas: 0
  } do
    mappings dynamic: 'false' do
      indexes :id, type: 'integer'
      indexes :body, type: 'text', analyzer: 'standard'
      indexes :chat_id, type: 'integer'
      indexes :created_at, type: 'date'
    end
  end

  # Override default index name
  index_name "messages_#{Rails.env}"

  # Custom search method
  def self.search_by_chat(chat_id, query)
    search(
      query: {
        bool: {
          must: [
            { term: { chat_id: chat_id } },
            { match: { body: { query: query, operator: 'and' } } }
          ]
        }
      }
    )
  end
end
```

**Teaching Points:**
1. **Concern Pattern:** `include Elasticsearch::Model` adds search capabilities
2. **Index Mapping:** Define schema for Elasticsearch (like database migration)
3. **Standard Analyzer:** Text tokenization, lowercasing, stop words
4. **Environment Isolation:** Separate indices per environment (dev/test/prod)
5. **Query DSL:** Bool query with multiple conditions

**Potential Question:** "Why disable dynamic mapping?"
**Answer:** "Dynamic mapping can cause schema drift - Elasticsearch guesses field types. By setting `dynamic: 'false'`, we explicitly define each field's type. This prevents bugs where searching on a number vs string behaves differently."

---

### Component 6: Frontend API Client with Metrics

**File:** `frontend/src/lib/api.ts`

```typescript
import axios from 'axios';

interface ServiceMetrics {
  responseTime: number;
  timestamp: number;
}

const metricsStore: Record<string, ServiceMetrics[]> = {
  rails: [],
  go: []
};

const railsClient = axios.create({
  baseURL: 'http://localhost:3000/api/v1',
  headers: { 'Content-Type': 'application/json' }
});

const goClient = axios.create({
  baseURL: 'http://localhost:8080/api/v1',
  headers: { 'Content-Type': 'application/json' }
});

export const createMessage = async (
  token: string,
  chatNumber: number,
  body: string,
  service: 'rails' | 'go'
) => {
  const client = service === 'go' ? goClient : railsClient;
  const startTime = performance.now();

  try {
    const response = await client.post(
      `/applications/${token}/chats/${chatNumber}/messages`,
      { body }
    );

    const responseTime = performance.now() - startTime;

    // Track metrics
    metricsStore[service].push({
      responseTime,
      timestamp: Date.now()
    });

    // Keep only last 100 metrics
    if (metricsStore[service].length > 100) {
      metricsStore[service].shift();
    }

    return { data: response.data, responseTime };
  } catch (error) {
    console.error(`${service} request failed:`, error);
    throw error;
  }
};

export const getMetrics = (service: 'rails' | 'go') => {
  const metrics = metricsStore[service];
  if (metrics.length === 0) return null;

  const avgResponseTime = metrics.reduce((sum, m) => sum + m.responseTime, 0) / metrics.length;
  const minResponseTime = Math.min(...metrics.map(m => m.responseTime));
  const maxResponseTime = Math.max(...metrics.map(m => m.responseTime));

  return {
    avgResponseTime: Math.round(avgResponseTime),
    minResponseTime: Math.round(minResponseTime),
    maxResponseTime: Math.round(maxResponseTime),
    requestCount: metrics.length
  };
};
```

**Teaching Points:**
1. **Axios Instances:** Separate clients for different backends
2. **Performance API:** Browser-native `performance.now()` for accurate timing
3. **Metrics Collection:** In-memory time series data
4. **Statistical Analysis:** Avg, min, max calculations
5. **Memory Management:** Circular buffer (max 100 entries)

**Potential Question:** "How do you visualize the performance difference?"
**Answer:** "The frontend uses Recharts to plot response times over time. You can see Rails averaging ~50ms while Go averages ~5ms. The chart updates in real-time as you create messages, making the performance difference visually obvious."

---

### Component 7: Docker Compose Orchestration

**File:** `docker-compose.yml`

```yaml
version: '3.8'

services:
  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: password
      MYSQL_DATABASE: chat_system_development
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.17.0
    environment:
      - discovery.type=single-node
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    ports:
      - "9200:9200"
    volumes:
      - es_data:/usr/share/elasticsearch/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9200/_cluster/health"]
      interval: 30s
      timeout: 10s
      retries: 5

  rails:
    build: .
    command: bundle exec rails server -b 0.0.0.0
    ports:
      - "3000:3000"
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
      elasticsearch:
        condition: service_healthy
    environment:
      DATABASE_HOST: mysql
      REDIS_HOST: redis
      ELASTICSEARCH_URL: http://elasticsearch:9200

  sidekiq:
    build: .
    command: bundle exec sidekiq -c 5
    depends_on:
      - mysql
      - redis
      - elasticsearch
    environment:
      DATABASE_HOST: mysql
      REDIS_HOST: redis
      ELASTICSEARCH_URL: http://elasticsearch:9200

  go-service:
    build: ./go-service
    ports:
      - "8080:8080"
    depends_on:
      - mysql
      - redis
    environment:
      MYSQL_HOST: mysql
      REDIS_HOST: redis

  frontend:
    build: ./frontend
    ports:
      - "80:80"
    depends_on:
      - rails
      - go-service

volumes:
  mysql_data:
  redis_data:
  es_data:
```

**Teaching Points:**
1. **Service Dependencies:** `depends_on` with health checks
2. **Health Checks:** Ensure services are ready before starting dependents
3. **Named Volumes:** Persistent storage for databases
4. **Environment Variables:** Configuration injection
5. **Network Isolation:** Services communicate via service names (Docker DNS)

**Potential Question:** "Why use health checks instead of just depends_on?"
**Answer:** "Without health checks, `depends_on` only waits for the container to start, not for the service to be ready. MySQL might start but take 10 seconds to accept connections. Health checks ensure the service is actually usable before dependent services start."

---

## Potential Interview Questions

### Category 1: Architecture & Design

#### Q1: "Why did you choose to use both Rails and Go instead of just one?"
**Answer:**
"This demonstrates a polyglot microservices approach where we use the right tool for each job:
- **Rails** handles complex business logic, full CRUD operations, and integrates easily with Sidekiq/Elasticsearch
- **Go** handles high-throughput write operations where performance is critical (10x faster than Rails)
- Both share the same infrastructure (MySQL, Redis, Sidekiq) to avoid data duplication
- This is a realistic pattern used in production systems (e.g., Twitter uses Scala + Ruby, Uber uses Go + Python)"

#### Q2: "How do you handle race conditions in sequential numbering?"
**Answer:**
"Three-layer defense:
1. **Redis INCR** (primary): Atomic operation guarantees unique sequential numbers
2. **Database unique constraint**: Catches any duplicates if Redis somehow fails
3. **Sidekiq retry logic**: If constraint violation occurs, job retries with exponential backoff

The key insight is that Redis INCR is the *single point of serialization* - no matter how many concurrent requests, Redis processes them one at a time."

#### Q3: "What happens if a Sidekiq job fails?"
**Answer:**
"Sidekiq has built-in retry logic with exponential backoff (up to 25 retries over ~21 days):
- **Transient failures** (network timeout): Retries succeed eventually
- **Permanent failures** (validation error): Job moves to Dead queue after all retries
- **Monitoring**: Sidekiq UI shows failed jobs, can manually retry
- **Alerting**: In production, we'd set up alerts for sustained failures

For Elasticsearch failures specifically, we don't fail the job - we log the error and allow manual reindexing later via `ReindexMessagesJob`."

#### Q4: "Why use Elasticsearch instead of MySQL full-text search?"
**Answer:**
"MySQL's `LIKE '%query%'` has several limitations:
- **Performance**: Full table scan, gets slower as data grows
- **Features**: No relevance scoring, limited partial matching
- **Scalability**: Can't horizontally shard

Elasticsearch provides:
- **Inverted index**: Near-instant lookups
- **Flexibility**: Stemming, synonyms, fuzzy matching
- **Relevance**: TF-IDF scoring for ranking results
- **Scalability**: Horizontal sharding built-in

The trade-off is operational complexity, but for any serious search functionality, Elasticsearch is industry standard."

---

### Category 2: Performance & Scalability

#### Q5: "How does your system handle 10,000 concurrent requests?"
**Answer:**
"Several mechanisms:
1. **Asynchronous processing**: API responds immediately, work happens in background
2. **Horizontal scaling**: Rails/Go are stateless, can run multiple instances behind a load balancer
3. **Redis**: Single-threaded but can handle 100k+ ops/sec
4. **Sidekiq**: 5 workers can be increased, or run multiple Sidekiq processes
5. **MySQL connection pooling**: Prevents connection exhaustion

Bottleneck analysis:
- **Redis INCR**: ~100k req/sec (not the bottleneck)
- **Sidekiq workers**: 5 workers × ~10 jobs/sec = 50 jobs/sec (bottleneck!)
- **Solution**: Scale Sidekiq workers horizontally (run multiple processes)"

#### Q6: "Your API returns before the database write completes. What if the client immediately tries to read the message?"
**Answer:**
"This is a known eventual consistency issue with async processing:

**Current behavior**: Client gets 404 because message isn't persisted yet

**Production solutions**:
1. **Optimistic UI**: Client displays message immediately in UI, doesn't wait for server
2. **Polling**: Client polls GET /messages/:number until it appears (with exponential backoff)
3. **WebSockets**: Server pushes notification when message is persisted
4. **Read-after-write consistency**: Direct the read to a 'recent writes' cache

For this demo, option 2 (polling) is most practical. In production, I'd implement WebSockets for real-time updates."

#### Q7: "What's your database indexing strategy?"
**Answer:**
"Critical indices:
```ruby
# Lookups by token (API reads)
add_index :chat_applications, :token, unique: true

# Foreign key lookups (joins)
add_index :chats, :chat_application_id

# Nested resource lookups
add_index :chats, [:chat_application_id, :number], unique: true
add_index :messages, [:chat_id, :number], unique: true
```

The composite indices serve two purposes:
1. **Uniqueness constraint**: Prevent duplicate numbers
2. **Query performance**: Enable index-only scans for lookups

I'd monitor with `EXPLAIN` queries in production and add indices based on slow query logs."

---

### Category 3: Error Handling & Reliability

#### Q8: "What happens if Redis goes down?"
**Answer:**
"**Short-term impact** (seconds to minutes):
- All write requests fail (can't generate sequential numbers)
- Read requests still work (don't need Redis)

**Mitigation strategies**:
1. **Redis Sentinel**: Automatic failover to replica (30 seconds downtime)
2. **Redis Cluster**: Multi-master for zero downtime
3. **AOF Persistence**: Counter values recovered on restart (no data loss)
4. **Circuit breaker**: Fail fast, return 503 instead of timing out

**Recovery**:
- Redis restarts with AOF data
- Counters resume from last value
- No duplicate numbers (gaps are acceptable)"

#### Q9: "How do you ensure data consistency between MySQL and Elasticsearch?"
**Answer:**
"**Normal operation**: Sidekiq job writes to both atomically

**Elasticsearch failure scenarios**:
- **Transient failure**: Job retries (Sidekiq default behavior)
- **Sustained outage**: Messages accumulate in MySQL only
- **Recovery**: Run `ReindexMessagesJob` to bulk-reindex

**Consistency model**: Eventually consistent
- MySQL is source of truth
- Elasticsearch is a read replica
- Acceptable for search index to be slightly stale

**Production improvements**:
- Elasticsearch cluster for high availability
- Change data capture (CDC) from MySQL to Elasticsearch
- Monitoring/alerts for replication lag"

#### Q10: "What if two requests get the same sequential number?"
**Answer:**
"**Redis INCR guarantees this can't happen** - it's an atomic operation. But hypothetically:

1. **Detection**: Database unique constraint violation
2. **Sidekiq retries**: Job retries with exponential backoff
3. **Second attempt**: Gets a new (higher) number from Redis
4. **Success**: Message persists with new number

**Gap in sequence**: Original number is skipped (number 5 never exists). This is acceptable per requirements - sequential doesn't mean gapless.

**Monitoring**: Log unique constraint violations to detect Redis issues."

---

### Category 4: Code Quality & Testing

#### Q11: "How would you test the sequential numbering logic?"
**Answer:**
"**Unit tests** (app/services/sequential_number_service.rb):
```ruby
RSpec.describe SequentialNumberService do
  it 'generates sequential numbers' do
    app_id = 1
    expect(described_class.next_chat_number(app_id)).to eq(1)
    expect(described_class.next_chat_number(app_id)).to eq(2)
    expect(described_class.next_chat_number(app_id)).to eq(3)
  end
end
```

**Concurrency tests**:
```ruby
it 'handles concurrent requests without duplicates' do
  numbers = 10.times.map do
    Thread.new { described_class.next_chat_number(1) }
  end.map(&:value)

  expect(numbers.uniq.size).to eq(10)  # All unique
end
```

**Integration tests** (spec/requests/messages_spec.rb):
- Test full request → Redis → Sidekiq → MySQL flow
- Mock Sidekiq to test job enqueuing
- Verify response contains correct number"

#### Q12: "How do you monitor the system in production?"
**Answer:**
"**Metrics to track**:
1. **API performance**: Response times (p50, p95, p99)
2. **Sidekiq queue depth**: Alert if jobs backing up
3. **Error rates**: 5xx errors, job failures
4. **Redis memory usage**: Prevent OOM
5. **Database queries**: Slow query log
6. **Elasticsearch lag**: Time since last indexed message

**Tools**:
- **APM**: New Relic, DataDog (request tracing)
- **Logging**: Structured logs to ELK stack
- **Sidekiq UI**: Built-in job monitoring
- **Health checks**: `/health` endpoint for load balancers

**Alerts**:
- Sidekiq queue > 10,000 jobs
- Error rate > 1%
- Response time p95 > 500ms"

---

### Category 5: Trade-offs & Improvements

#### Q13: "What would you do differently in a production system?"
**Answer:**
"**Improvements**:
1. **Authentication & Authorization**: JWT tokens, rate limiting
2. **Data Validation**: Stricter input validation, XSS prevention
3. **High Availability**:
   - Redis Sentinel for automatic failover
   - MySQL replication (master-slave)
   - Elasticsearch cluster
4. **Monitoring**: Prometheus + Grafana for metrics
5. **Testing**: Increase coverage from current 69 examples
6. **API Versioning**: Already at `/api/v1`, prepared for v2
7. **Pagination**: Limit result sets (currently returns all)
8. **WebSockets**: Real-time message delivery
9. **Database Partitioning**: Partition messages table by date
10. **CDN**: Serve frontend assets from CDN

**Trade-offs considered**:
- Used async processing for performance, accepting eventual consistency
- Used cached counters for speed, accepting 1-hour lag
- Used Elasticsearch for search, accepting operational complexity"

#### Q14: "Why not use a message queue like RabbitMQ instead of Redis?"
**Answer:**
"**Redis + Sidekiq advantages**:
- ✅ Simplicity: One system (Redis) for both counters and queues
- ✅ Rails integration: Sidekiq is the standard for Rails
- ✅ Lower latency: In-memory operations
- ✅ Good enough: Handles 100k jobs/sec

**RabbitMQ advantages**:
- ✅ Better guarantees: Persistent queues, transactions
- ✅ Complex routing: Exchanges, topic matching
- ✅ Protocol support: AMQP, MQTT, STOMP

**For this use case**: Sidekiq + Redis is simpler and sufficient. Would only use RabbitMQ if we needed advanced routing or strict message delivery guarantees."

#### Q15: "How would you implement real-time chat features?"
**Answer:**
"**Current**: HTTP polling (inefficient)

**Production approach**:
1. **WebSockets** with Action Cable (Rails) or Gorilla WebSocket (Go)
2. **Architecture**:
```
Client → WebSocket → Rails/Go → Redis Pub/Sub → All connected clients
```
3. **Flow**:
   - Client creates message via HTTP POST
   - Sidekiq job persists to MySQL
   - Job publishes to Redis channel `chat:123:messages`
   - WebSocket server broadcasts to all subscribed clients
4. **Benefits**: Sub-second message delivery, bidirectional communication
5. **Challenges**: Connection state management, scaling WebSocket servers

**Quick implementation**:
```ruby
# app/channels/chat_channel.rb
class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "chat:#{params[:chat_id]}:messages"
  end
end

# In CreateMessageJob:
ActionCable.server.broadcast("chat:#{chat_id}:messages", message.as_json)
```"

---

### Category 6: System Design Questions

#### Q16: "How would you scale this to 1 million messages per second?"
**Answer:**
"**Bottleneck analysis**:
1. **Redis INCR**: 100k/sec → Need sharding
2. **Sidekiq**: 50 jobs/sec → Need many workers
3. **MySQL**: 10k writes/sec → Need sharding

**Scaling strategy**:

**Horizontal scaling**:
- **API layer**: 100+ stateless Rails/Go instances behind load balancer
- **Sidekiq**: 1000+ worker processes across multiple machines
- **Redis**: Cluster mode with hash slot sharding
  ```
  chat_app:1:* → Redis Node 1
  chat_app:2:* → Redis Node 2
  ```
- **MySQL**: Shard by application_id
  ```
  application_id % 10 → Shard 0-9
  ```

**Write path optimization**:
- Batch inserts (1000 messages per transaction)
- SSD storage for MySQL
- Write-ahead logging optimization

**At this scale**: Consider Kafka for job queue, Cassandra for message storage."

#### Q17: "Design the database schema differently to avoid using Redis for counters?"
**Answer:**
"**Alternative 1: Database sequences**
```sql
CREATE SEQUENCE chat_1_message_seq;
SELECT nextval('chat_1_message_seq');
```
❌ Problem: One sequence per chat (schema bloat)

**Alternative 2: Application-level locking**
```ruby
Chat.transaction do
  chat.lock!  # SELECT ... FOR UPDATE
  number = chat.last_message_number + 1
  chat.update!(last_message_number: number)
  Message.create!(number: number)
end
```
❌ Problem: Database lock contention (slow)

**Alternative 3: UUID instead of sequential**
```ruby
message.id = SecureRandom.uuid  # No coordination needed
```
✅ Simple, scalable
❌ Violates requirement for sequential numbers

**Conclusion**: Redis INCR is the best solution for sequential numbering at scale."

---

## How to Present Your Code

### 1. Start with the Big Picture
"Let me show you the system architecture first..."
- Draw the 7-service diagram
- Explain request flow
- Then dive into specific components

### 2. Tell a Story Through Code
"Let's follow a message creation from start to finish..."
- Controller → Service → Redis → Job → Database → Elasticsearch
- Show code at each step
- Explain why each decision was made

### 3. Highlight Trade-offs
"I chose async processing for speed, which means eventual consistency..."
- Show you understand there's no perfect solution
- Explain the pros/cons you considered
- Demonstrate mature engineering judgment

### 4. Connect to Real-World
"This pattern is similar to how [Twitter/Instagram/Uber] does X..."
- Shows you research industry practices
- Demonstrates learning from production systems

### 5. Be Honest About Limitations
"For a demo, I skipped authentication. In production, I'd use..."
- Shows you know what's missing
- Demonstrates security awareness
- Proves you understand production requirements

### 6. Prepare Demos
Have terminals ready:
```bash
# Terminal 1: Start system
docker-compose up

# Terminal 2: Watch logs
docker-compose logs -f sidekiq

# Terminal 3: Redis CLI
redis-cli monitor

# Terminal 4: API requests
curl -X POST http://localhost:3000/api/v1/applications \
  -H "Content-Type: application/json" \
  -d '{"name":"Demo App"}'
```

Show:
- Create app → Get token
- Create chat → See Redis INCR
- Create message → See Sidekiq job
- Search message → See Elasticsearch query

### 7. Use the Frontend
"Let me show you the performance difference between Rails and Go..."
- Toggle between services
- Create messages
- Watch the chart update
- **Visual proof** is compelling

---

## Impressive Technical Highlights

### 1. Polyglot Microservices
"I implemented the same API in both Rails and Go to compare performance. The Go service is 10x faster while sharing the same infrastructure."

### 2. Race Condition Handling
"Sequential numbering under concurrency is a classic distributed systems problem. I used Redis INCR as the atomic operation with database constraints as a safety net."

### 3. Eventual Consistency
"The system prioritizes availability over consistency (CAP theorem). API responds in <5ms, actual persistence happens asynchronously."

### 4. Elasticsearch Integration
"Full-text search with partial matching, relevance scoring, and graceful degradation if Elasticsearch is unavailable."

### 5. Observability
"The frontend tracks response times for each service, visualizing the performance difference in real-time."

### 6. Docker Compose Orchestration
"One command (`docker-compose up`) starts 7 services with proper health checks and dependencies."

### 7. Production-Ready Patterns
- Health checks for each service
- AOF persistence for Redis
- Unique constraints for data integrity
- Structured logging
- Environment-based configuration
- API versioning (`/api/v1`)

---

## Practice Responses

### Opening Question: "Tell me about this project"

**Strong answer:**
"This is a scalable chat application system I built to demonstrate distributed systems concepts. The key challenge was generating sequential numbers for messages under high concurrency without duplicates.

I implemented a polyglot architecture with Ruby on Rails for full CRUD operations and Go for high-performance writes. Both services share MySQL for persistence, Redis for atomic counters, and Sidekiq for async processing.

The system handles race conditions using Redis INCR as a single point of serialization, with database unique constraints as a safety net. API responses are sub-5ms because I enqueue heavy operations to background jobs.

I also integrated Elasticsearch for full-text search and built a React frontend that lets you toggle between Rails and Go to see the 10x performance difference visually.

The entire stack runs in Docker Compose with health checks and proper orchestration. I'm happy to dive deep into any component."

---

### Closing Question: "What did you learn from this project?"

**Strong answer:**
"Three key learnings:

**1. Distributed systems complexity**: Sequential numbering seems simple until you add concurrency. I learned that atomic operations (Redis INCR) are essential, and you need multiple layers of defense (Redis + DB constraints).

**2. Async processing trade-offs**: Immediate responses are great for UX, but eventual consistency requires careful error handling. I had to think through: what if Elasticsearch fails? What if the job never runs?

**3. Polyglot architecture benefits**: Go's 10x performance improvement for writes was eye-opening. But the integration complexity (enqueuing ActiveJob-compatible jobs from Go) showed me that every architectural decision has costs.

If I rebuilt this, I'd add WebSockets for real-time updates, implement proper authentication with JWTs, and add comprehensive monitoring with Prometheus. But I'm proud of how production-ready the core architecture is."

---

## Final Tips

1. **Practice the demo**: Nothing worse than Docker failing during the interview
2. **Prepare for "why" questions**: Every decision should have a reason
3. **Know the alternatives**: "I chose Redis, but Postgres sequences would also work..."
4. **Show enthusiasm**: "The performance difference between Rails and Go was fascinating to measure"
5. **Be humble**: "This is a demo; in production I'd add X, Y, Z"
6. **Code walkthrough**: Have your editor ready to show specific files
7. **Draw diagrams**: Architecture diagrams help visual learners
8. **Timing**: Keep initial overview to 5 minutes, save deep dives for questions

---

Good luck with your Instabug interview! This project demonstrates strong engineering skills. Focus on explaining your thought process and trade-offs, not just the code itself.
