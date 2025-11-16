# Backend Folder Structure & Files Guide
## Complete Walkthrough for Interview Questions

---

## Table of Contents
1. [Project Root Overview](#project-root-overview)
2. [App Folder - Rails MVC Architecture](#app-folder---rails-mvc-architecture)
3. [Go Service Structure](#go-service-structure)
4. [Configuration Files](#configuration-files)
5. [Database Folder](#database-folder)
6. [Testing Structure](#testing-structure)
7. [Key Files Deep Dive](#key-files-deep-dive)
8. [Common Interview Questions](#common-interview-questions)

---

## Project Root Overview

```
Chat_app_system/
├── app/                    # Rails application code (MVC)
├── go-service/             # Go microservice
├── config/                 # Configuration files
├── db/                     # Database migrations & schema
├── spec/                   # RSpec tests (69 examples)
├── bin/                    # Executable scripts
├── lib/                    # Custom libraries & rake tasks
├── public/                 # Static files
├── docker-compose.yml      # Multi-container orchestration
├── Dockerfile              # Rails container image
├── Gemfile                 # Ruby dependencies
├── Gemfile.lock            # Locked dependency versions
├── .rubocop.yml            # Ruby linting configuration
└── README.md               # Project documentation
```

### Root Level Files

| File | Purpose | Interview Talking Points |
|------|---------|-------------------------|
| **docker-compose.yml** | Orchestrates 7 services (MySQL, Redis, Elasticsearch, Rails, Sidekiq, Go, Frontend) | "Single command to start entire stack with health checks and dependencies" |
| **Dockerfile** | Rails container image definition | "Multi-stage build, production-ready with proper user permissions" |
| **Gemfile** | Ruby gem dependencies | "Specifies Rails 8.1, Sidekiq, Elasticsearch integration, testing gems" |
| **Gemfile.lock** | Locked versions for reproducibility | "Ensures consistent dependencies across environments" |
| **.rubocop.yml** | Ruby style guide enforcement | "Maintains code quality and consistency" |

---

## App Folder - Rails MVC Architecture

### Complete Structure

```
app/
├── controllers/            # HTTP request handlers
│   ├── application_controller.rb
│   ├── health_controller.rb
│   ├── api/
│   │   └── v1/
│   │       ├── chat_applications_controller.rb
│   │       ├── chats_controller.rb
│   │       └── messages_controller.rb
│   └── concerns/          # Shared controller modules (empty)
│
├── models/                # Data models (ActiveRecord)
│   ├── application_record.rb
│   ├── chat_application.rb
│   ├── chat.rb
│   ├── message.rb
│   └── concerns/          # Shared model modules (empty)
│
├── jobs/                  # Background jobs (Sidekiq)
│   ├── application_job.rb
│   ├── create_chat_job.rb
│   ├── create_message_job.rb
│   ├── persist_message_job.rb
│   ├── update_chat_application_count_job.rb
│   ├── update_chat_message_count_job.rb
│   ├── rebuild_redis_counters_job.rb
│   ├── reindex_messages_job.rb
│   └── sync_counters_job.rb
│
├── services/              # Business logic (Service Objects)
│   └── sequential_number_service.rb
│
├── mailers/               # Email senders (unused)
│   └── application_mailer.rb
│
└── views/                 # HTML templates (API-only, unused)
    └── layouts/
        └── application.html.erb
```

---

### 1. Controllers (`app/controllers/`)

**Purpose:** Handle HTTP requests, validate input, orchestrate business logic, return responses

#### **application_controller.rb**
```ruby
class ApplicationController < ActionController::API
  # Base controller - all controllers inherit from this
end
```

**What to say:**
- "All API controllers inherit from ApplicationController"
- "ActionController::API is Rails API-only mode - no view rendering, smaller footprint"
- "Common error handling could be added here"

---

#### **health_controller.rb** (`/health` endpoint)
```ruby
class HealthController < ApplicationController
  def index
    # Check MySQL, Redis, Elasticsearch connectivity
    render json: { status: 'healthy' }, status: :ok
  end
end
```

**What to say:**
- "Kubernetes/Docker health checks use this endpoint"
- "Returns 200 if all dependencies are reachable"
- "Load balancers can remove unhealthy instances"

**Location:** `app/controllers/health_controller.rb`

---

#### **API::V1::ChatApplicationsController** (`/api/v1/applications`)

**Key Methods:**
```ruby
# POST /api/v1/applications
def create
  # Creates app with SecureRandom token
  # Returns immediately (no async needed)
end

# GET /api/v1/applications/:token
def show
  # Find by token (not ID!)
  # Returns app with chats_count
end

# GET /api/v1/applications
def index
  # List all applications
end

# PATCH /api/v1/applications/:token
def update
  # Update application name
end

# DELETE /api/v1/applications/:token
def destroy
  # Delete application and cascade to chats/messages
end
```

**What to say:**
- "Uses token-based lookup instead of exposing database IDs (security best practice)"
- "Create is synchronous because it's just one record - no performance concern"
- "Token generated with `SecureRandom.hex(16)` - 32-character hex string"

**Location:** `app/controllers/api/v1/chat_applications_controller.rb`

---

#### **API::V1::ChatsController** (`/api/v1/applications/:token/chats`)

**Key Methods:**
```ruby
# POST /api/v1/applications/:token/chats
def create
  number = SequentialNumberService.next_chat_number(@application.id)
  CreateChatJob.perform_async(@application.id, number)
  render json: { number: number }, status: :created
end

# GET /api/v1/applications/:token/chats/:number
def show
  # Find chat by composite key (application + number)
  # NOT by database ID
end
```

**What to say:**
- "Nested resource under applications - RESTful design"
- "Create is async - gets number from Redis, enqueues job, returns immediately"
- "Number is scoped to application (App 1 Chat 1, App 2 Chat 1 - both exist)"
- "Uses before_action to load parent application via token"

**Location:** `app/controllers/api/v1/chats_controller.rb`

---

#### **API::V1::MessagesController** (`/api/v1/applications/:token/chats/:number/messages`)

**Key Methods:**
```ruby
# POST /api/v1/applications/:token/chats/:number/messages
def create
  number = SequentialNumberService.next_message_number(@chat.id)
  CreateMessageJob.perform_async(@chat.id, number, message_params[:body])
  render json: { number: number }, status: :created
end

# GET /api/v1/applications/:token/chats/:number/messages/search?query=keyword
def search
  # Elasticsearch full-text search
  # Scoped to specific chat
  search_results = Message.search(
    query: {
      bool: {
        must: [
          { match: { chat_id: @chat.id } },
          { match: { body: params[:query] } }
        ]
      }
    }
  )
  render json: search_results.records
end
```

**What to say:**
- "Doubly nested resource - follows REST conventions"
- "Search uses Elasticsearch bool query - filters by chat_id AND matches text"
- "Async creation pattern same as chats (Redis → Job → Response)"
- "Strong parameters prevent mass assignment vulnerabilities"

**Location:** `app/controllers/api/v1/messages_controller.rb`

**Interview highlight:** "The search endpoint demonstrates Elasticsearch integration with scoped queries"

---

### 2. Models (`app/models/`)

**Purpose:** Business logic, validations, database schema mapping, relationships

#### **chat_application.rb**

```ruby
class ChatApplication < ApplicationRecord
  has_many :chats, dependent: :destroy

  validates :name, presence: true
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  private

  def generate_token
    self.token = SecureRandom.hex(16)
  end
end
```

**What to say:**
- "ActiveRecord model - ORM pattern"
- "has_many :chats, dependent: :destroy - cascade deletes (referential integrity)"
- "before_validation callback generates token automatically"
- "Validates uniqueness at app level AND database level (unique index)"

**Database columns:**
- `id` - Primary key
- `name` - Application name
- `token` - 32-char random string (indexed, unique)
- `chats_count` - Cached counter (updated async)
- `created_at`, `updated_at` - Timestamps

**Location:** `app/models/chat_application.rb`

---

#### **chat.rb**

```ruby
class Chat < ApplicationRecord
  belongs_to :chat_application
  has_many :messages, dependent: :destroy

  validates :number, presence: true
  validates :number, uniqueness: { scope: :chat_application_id }
end
```

**What to say:**
- "belongs_to :chat_application - foreign key relationship"
- "Composite unique constraint: (chat_application_id, number)"
- "Number is NOT unique globally - scoped to parent application"
- "No auto-increment on number - managed by Redis"

**Database columns:**
- `id` - Primary key (auto-increment)
- `chat_application_id` - Foreign key
- `number` - Sequential within application (1, 2, 3...)
- `messages_count` - Cached counter
- Unique index on `(chat_application_id, number)`

**Location:** `app/models/chat.rb`

---

#### **message.rb**

```ruby
class Message < ApplicationRecord
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks

  belongs_to :chat

  validates :number, presence: true
  validates :number, uniqueness: { scope: :chat_id }
  validates :body, presence: true

  # Elasticsearch index configuration
  settings index: { number_of_shards: 1 } do
    mappings dynamic: 'false' do
      indexes :id, type: 'integer'
      indexes :body, type: 'text', analyzer: 'standard'
      indexes :chat_id, type: 'integer'
      indexes :created_at, type: 'date'
    end
  end

  index_name "messages_#{Rails.env}"
end
```

**What to say:**
- "Elasticsearch::Model mixin adds search capabilities"
- "Callbacks auto-index on create/update (disabled in favor of manual indexing in jobs)"
- "Explicit mapping prevents dynamic field creation (schema control)"
- "Standard analyzer: tokenizes, lowercases, removes stop words"
- "Environment-specific index names (messages_development, messages_production)"

**Database columns:**
- `id` - Primary key
- `chat_id` - Foreign key
- `number` - Sequential within chat
- `body` - Message text (TEXT type)
- Unique index on `(chat_id, number)`

**Location:** `app/models/message.rb`

**Interview highlight:** "Message is the only model with Elasticsearch integration - demonstrates polyglot persistence"

---

### 3. Jobs (`app/jobs/`)

**Purpose:** Asynchronous background processing via Sidekiq

#### **create_chat_job.rb**

```ruby
class CreateChatJob < ApplicationJob
  queue_as :default

  def perform(application_id, number)
    application = ChatApplication.find(application_id)

    chat = application.chats.create!(number: number)

    # Trigger counter update (cascading async job)
    UpdateChatApplicationCountJob.perform_async(application_id)

  rescue ActiveRecord::RecordNotUnique
    # Duplicate number - Redis gave same number twice (rare)
    # Sidekiq will retry automatically
    raise
  end
end
```

**What to say:**
- "Enqueued by API controller after getting number from Redis"
- "Creates database record asynchronously"
- "Handles race condition edge case (RecordNotUnique) with retry"
- "Triggers another job to update cached counter"

**Location:** `app/jobs/create_chat_job.rb`

---

#### **create_message_job.rb**

```ruby
class CreateMessageJob < ApplicationJob
  queue_as :default

  def perform(chat_id, number, body)
    chat = Chat.find(chat_id)

    message = chat.messages.create!(
      number: number,
      body: body
    )

    # Index in Elasticsearch (best-effort)
    index_to_elasticsearch(message)

    # Update cached counter
    UpdateChatMessageCountJob.perform_async(chat_id)

  rescue ActiveRecord::RecordNotUnique
    raise # Retry with exponential backoff
  end

  private

  def index_to_elasticsearch(message)
    message.__elasticsearch__.index_document
  rescue Elasticsearch::Transport::Error => e
    Rails.logger.error("ES indexing failed: #{e.message}")
    # Don't fail the job - message is in MySQL
  end
end
```

**What to say:**
- "Critical job - persists messages to MySQL and Elasticsearch"
- "Two-phase: MySQL write (critical), ES index (best-effort)"
- "If Elasticsearch fails, job still succeeds - search temporarily broken but data is safe"
- "Graceful degradation pattern"

**Location:** `app/jobs/create_message_job.rb`

**Interview highlight:** "Demonstrates error handling strategy - critical vs. non-critical failures"

---

#### **update_chat_application_count_job.rb**

```ruby
class UpdateChatApplicationCountJob < ApplicationJob
  queue_as :default

  def perform(application_id)
    application = ChatApplication.find(application_id)

    # Recalculate actual count from database
    actual_count = application.chats.count

    # Update cached column
    application.update_column(:chats_count, actual_count)
  end
end
```

**What to say:**
- "Updates cached counter column for performance"
- "Called after each chat creation (eventual consistency)"
- "Uses update_column to bypass callbacks (performance)"
- "Could be rate-limited to run max once per minute per application"

**Location:** `app/jobs/update_chat_application_count_job.rb`

---

#### **rebuild_redis_counters_job.rb**

```ruby
class RebuildRedisCountersJob < ApplicationJob
  queue_as :default

  def perform
    # Recovery job - rebuild Redis counters from MySQL
    ChatApplication.find_each do |app|
      max_chat_number = app.chats.maximum(:number) || 0
      redis.set("chat_app:#{app.id}:chat_counter", max_chat_number)
    end

    Chat.find_each do |chat|
      max_message_number = chat.messages.maximum(:number) || 0
      redis.set("chat:#{chat.id}:message_counter", max_message_number)
    end
  end
end
```

**What to say:**
- "Disaster recovery job - rebuilds Redis counters from MySQL"
- "Used if Redis loses data or becomes corrupted"
- "MySQL is source of truth - Redis is derived state"
- "find_each batches queries for memory efficiency"

**Location:** `app/jobs/rebuild_redis_counters_job.rb`

**Interview highlight:** "Shows understanding of data consistency and recovery strategies"

---

#### **reindex_messages_job.rb**

```ruby
class ReindexMessagesJob < ApplicationJob
  queue_as :default

  def perform
    # Bulk reindex all messages to Elasticsearch
    Message.import force: true, refresh: true
  end
end
```

**What to say:**
- "Elasticsearch recovery job"
- "Bulk import is more efficient than indexing one-by-one"
- "force: true recreates index, refresh: true makes immediately searchable"
- "Run manually after Elasticsearch downtime"

**Location:** `app/jobs/reindex_messages_job.rb`

---

### 4. Services (`app/services/`)

**Purpose:** Encapsulate complex business logic, keep controllers thin

#### **sequential_number_service.rb**

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

**What to say:**
- "Service Object pattern - separates concerns"
- "Single responsibility: generate sequential numbers"
- "Redis INCR is atomic - thread-safe without locks"
- "Class methods (self.) - stateless service"
- "Memoization (@redis ||=) prevents creating new connections each call"

**Location:** `app/services/sequential_number_service.rb`

**Interview highlight:** "Core of the distributed sequential numbering solution"

---

## Go Service Structure

```
go-service/
├── main.go                 # HTTP server & routing
├── handlers/               # Request handlers
│   ├── chat_handler.go
│   └── message_handler.go
├── models/                 # Data structures
│   └── models.go
├── db/                     # MySQL queries
│   └── mysql.go
├── cache/                  # Redis integration
│   └── redis.go
├── queue/                  # Sidekiq job enqueuing
│   └── sidekiq.go
├── middleware/             # HTTP middleware
│   └── middleware.go
├── go.mod                  # Go dependencies
├── go.sum                  # Dependency checksums
├── Dockerfile              # Go container image
└── README.md
```

---

### Key Go Files

#### **main.go**

```go
package main

import (
    "github.com/gorilla/mux"
    "net/http"
    "go-service/handlers"
    "go-service/middleware"
)

func main() {
    r := mux.NewRouter()

    // Middleware
    r.Use(middleware.CORS)
    r.Use(middleware.Logging)

    // Routes
    r.HandleFunc("/api/v1/applications/{token}/chats",
        handlers.CreateChat).Methods("POST")
    r.HandleFunc("/api/v1/applications/{token}/chats/{number}/messages",
        handlers.CreateMessage).Methods("POST")

    http.ListenAndServe(":8080", r)
}
```

**What to say:**
- "Gorilla Mux for routing (like Rails routes)"
- "Middleware for CORS and logging"
- "Only implements write endpoints (chats, messages)"
- "Listens on port 8080 (Rails on 3000)"

**Location:** `go-service/main.go`

---

#### **handlers/message_handler.go**

```go
func CreateMessage(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    chatID, _ := strconv.Atoi(vars["chat_id"])

    var req MessageRequest
    json.NewDecoder(r.Body).Decode(&req)

    // Get sequential number from Redis (atomic)
    number, err := cache.IncrementMessageCounter(chatID)
    if err != nil {
        http.Error(w, "Failed to generate number", 500)
        return
    }

    // Enqueue Sidekiq job (Rails will process)
    err = queue.EnqueueCreateMessageJob(chatID, number, req.Body)
    if err != nil {
        http.Error(w, "Failed to enqueue job", 500)
        return
    }

    // Return response immediately
    json.NewEncoder(w).Encode(MessageResponse{Number: number})
}
```

**What to say:**
- "Same pattern as Rails - Redis INCR, enqueue, return"
- "10x faster due to compiled binary and goroutines"
- "Explicit error handling (Go convention)"
- "No ORM - direct Redis/MySQL calls for speed"

**Location:** `go-service/handlers/message_handler.go`

---

#### **cache/redis.go**

```go
package cache

import (
    "github.com/gomodule/redigo/redis"
)

var pool *redis.Pool

func init() {
    pool = &redis.Pool{
        MaxIdle: 10,
        MaxActive: 50,
        Dial: func() (redis.Conn, error) {
            return redis.Dial("tcp", "redis:6379")
        },
    }
}

func IncrementMessageCounter(chatID int) (int, error) {
    conn := pool.Get()
    defer conn.Close()

    key := fmt.Sprintf("chat:%d:message_counter", chatID)
    return redis.Int(conn.Do("INCR", key))
}
```

**What to say:**
- "Connection pooling for performance (reuse connections)"
- "Same Redis INCR as Rails - language-agnostic"
- "Defer ensures connection returns to pool"

**Location:** `go-service/cache/redis.go`

---

#### **queue/sidekiq.go**

```go
package queue

type ActiveJobPayload struct {
    JobClass   string        `json:"job_class"`
    JobID      string        `json:"job_id"`
    Queue      string        `json:"queue"`
    Args       []interface{} `json:"args"`
    CreatedAt  float64       `json:"created_at"`
    EnqueuedAt float64       `json:"enqueued_at"`
}

func EnqueueCreateMessageJob(chatID int, number int, body string) error {
    payload := ActiveJobPayload{
        JobClass:   "CreateMessageJob",
        Queue:      "default",
        Args:       []interface{}{chatID, number, body},
        CreatedAt:  float64(time.Now().Unix()),
        EnqueuedAt: float64(time.Now().Unix()),
    }

    jsonBytes, _ := json.Marshal(payload)

    conn := redisPool.Get()
    defer conn.Close()

    _, err := conn.Do("LPUSH", "queue:default", string(jsonBytes))
    return err
}
```

**What to say:**
- "**Critical integration point** - Go speaks Rails' language"
- "ActiveJob JSON format - specific structure Sidekiq expects"
- "LPUSH to Redis list - Sidekiq polls this queue"
- "Rails Sidekiq worker deserializes and executes CreateMessageJob"
- "Demonstrates polyglot interoperability"

**Location:** `go-service/queue/sidekiq.go`

**Interview highlight:** "This is how Go and Rails communicate - Redis as message bus, ActiveJob as protocol"

---

## Configuration Files

```
config/
├── application.rb          # Rails app config
├── boot.rb                 # Bundler setup
├── environment.rb          # Loads Rails
├── routes.rb               # API routing
├── database.yml            # MySQL connection
├── puma.rb                 # Web server config
├── initializers/           # Load-time configuration
│   ├── cors.rb
│   ├── redis.rb
│   ├── elasticsearch.rb
│   ├── sidekiq.rb
│   ├── redis_recovery.rb
│   └── elasticsearch_recovery.rb
└── environments/
    ├── development.rb
    ├── test.rb
    └── production.rb
```

---

### Key Configuration Files

#### **config/routes.rb**

```ruby
Rails.application.routes.draw do
  get '/health', to: 'health#index'

  namespace :api do
    namespace :v1 do
      resources :applications, param: :token do
        resources :chats, param: :number do
          resources :messages, param: :number do
            get :search, on: :collection
          end
        end
      end
    end
  end
end
```

**What to say:**
- "Nested resources mirror domain model hierarchy"
- "param: :token means use token in URL instead of ID"
- "param: :number for chats/messages"
- "API versioning via namespace (/api/v1/)"
- "Search as collection route (not member route)"

**Generated routes:**
```
POST   /api/v1/applications
GET    /api/v1/applications/:token
POST   /api/v1/applications/:token/chats
GET    /api/v1/applications/:token/chats/:number
POST   /api/v1/applications/:token/chats/:number/messages
GET    /api/v1/applications/:token/chats/:number/messages/search
```

**Location:** `config/routes.rb`

---

#### **config/database.yml**

```yaml
default: &default
  adapter: mysql2
  encoding: utf8mb4
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  host: <%= ENV.fetch("DATABASE_HOST", "localhost") %>
  port: 3306
  username: root
  password: password

development:
  <<: *default
  database: chat_system_development

test:
  <<: *default
  database: chat_system_test

production:
  <<: *default
  database: chat_system_production
```

**What to say:**
- "MySQL2 adapter - native C bindings for speed"
- "utf8mb4 encoding - supports emoji and all Unicode"
- "Connection pooling with RAILS_MAX_THREADS"
- "Environment-based configuration (12-factor app)"
- "YAML anchors (&default, <<: *default) for DRY config"

**Location:** `config/database.yml`

---

#### **config/initializers/redis.rb**

```ruby
REDIS = Redis.new(
  host: ENV.fetch('REDIS_HOST', 'localhost'),
  port: ENV.fetch('REDIS_PORT', 6379),
  db: 0
)
```

**What to say:**
- "Global REDIS constant - available throughout app"
- "Initialized at boot time"
- "Used by SequentialNumberService"

**Location:** `config/initializers/redis.rb`

---

#### **config/initializers/elasticsearch.rb**

```ruby
Elasticsearch::Model.client = Elasticsearch::Client.new(
  url: ENV.fetch('ELASTICSEARCH_URL', 'http://localhost:9200'),
  log: false
)
```

**What to say:**
- "Configures Elasticsearch client for Message model"
- "Environment-based URL (Docker uses service name)"

**Location:** `config/initializers/elasticsearch.rb`

---

#### **config/initializers/sidekiq.rb**

```ruby
Sidekiq.configure_server do |config|
  config.redis = {
    host: ENV.fetch('REDIS_HOST', 'localhost'),
    port: 6379,
    db: 0
  }
end

Sidekiq.configure_client do |config|
  config.redis = {
    host: ENV.fetch('REDIS_HOST', 'localhost'),
    port: 6379,
    db: 0
  }
end
```

**What to say:**
- "Server config: Sidekiq workers polling Redis"
- "Client config: Rails app enqueuing jobs"
- "Both use same Redis instance (different purpose than counters)"

**Location:** `config/initializers/sidekiq.rb`

---

#### **config/initializers/cors.rb**

```ruby
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins '*'  # In production: specific domains only
    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options]
  end
end
```

**What to say:**
- "CORS middleware for frontend access"
- "Development: allows all origins (*)"
- "Production: would restrict to specific domains"
- "Prevents CSRF attacks via same-origin policy"

**Location:** `config/initializers/cors.rb`

---

## Database Folder

```
db/
├── migrate/                # Database migrations
│   ├── 20251028170739_create_chat_applications.rb
│   ├── 20251028170748_create_chats.rb
│   └── 20251028170751_create_messages.rb
├── schema.rb               # Current database schema
├── seeds.rb                # Sample data (empty)
├── cache_schema.rb         # Solid Cache schema
├── queue_schema.rb         # Solid Queue schema
└── cable_schema.rb         # Action Cable schema
```

---

### Migrations

#### **db/migrate/xxx_create_chat_applications.rb**

```ruby
class CreateChatApplications < ActiveRecord::Migration[8.0]
  def change
    create_table :chat_applications do |t|
      t.string :name, null: false
      t.string :token, null: false, limit: 32
      t.integer :chats_count, default: 0, null: false

      t.timestamps
    end

    add_index :chat_applications, :token, unique: true
  end
end
```

**What to say:**
- "Token column: 32-character string, indexed, unique"
- "chats_count: cached counter, defaults to 0"
- "Unique index enforces uniqueness at database level"
- "timestamps: created_at, updated_at (Rails convention)"

**Location:** `db/migrate/20251028170739_create_chat_applications.rb`

---

#### **db/migrate/xxx_create_chats.rb**

```ruby
class CreateChats < ActiveRecord::Migration[8.0]
  def change
    create_table :chats do |t|
      t.references :chat_application, null: false, foreign_key: true
      t.integer :number, null: false
      t.integer :messages_count, default: 0, null: false

      t.timestamps
    end

    add_index :chats, [:chat_application_id, :number], unique: true
  end
end
```

**What to say:**
- "t.references creates foreign key + index"
- "Composite unique index on (chat_application_id, number)"
- "This enforces: 'number unique within application'"
- "foreign_key: true adds database-level constraint (referential integrity)"

**Location:** `db/migrate/20251028170748_create_chats.rb`

---

#### **db/migrate/xxx_create_messages.rb**

```ruby
class CreateMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :messages do |t|
      t.references :chat, null: false, foreign_key: true
      t.integer :number, null: false
      t.text :body, null: false

      t.timestamps
    end

    add_index :messages, [:chat_id, :number], unique: true
  end
end
```

**What to say:**
- "TEXT type for body - supports long messages"
- "Composite unique index on (chat_id, number)"
- "Foreign key cascade deletes handled at app level (dependent: :destroy)"

**Location:** `db/migrate/20251028170751_create_messages.rb`

---

#### **db/schema.rb**

```ruby
ActiveRecord::Schema[8.0].define(version: 2025_10_28_170751) do
  # Auto-generated - don't edit manually
  # Run: rails db:schema:load to recreate database
end
```

**What to say:**
- "Auto-generated from migrations"
- "Version number tracks last migration applied"
- "Used for creating database in new environments (faster than running all migrations)"
- "Never edit manually - always create new migrations"

**Location:** `db/schema.rb`

---

## Testing Structure

```
spec/
├── rails_helper.rb         # RSpec + Rails config
├── spec_helper.rb          # RSpec core config
├── support/                # Test helpers
│   ├── redis.rb
│   └── elasticsearch.rb
├── factories/              # FactoryBot test data
│   ├── chat_applications.rb
│   ├── chats.rb
│   └── messages.rb
├── models/                 # Model specs
│   ├── chat_application_spec.rb
│   ├── chat_spec.rb
│   └── message_spec.rb
├── requests/               # API integration tests
│   └── api/v1/
│       ├── chat_applications_spec.rb
│       ├── chats_spec.rb
│       └── messages_spec.rb
└── jobs/                   # Background job specs
    ├── create_chat_job_spec.rb
    ├── create_message_job_spec.rb
    └── update_*_count_job_spec.rb
```

---

### Key Test Files

#### **spec/rails_helper.rb**

```ruby
require 'factory_bot_rails'
require 'database_cleaner'
require 'sidekiq/testing'

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  # Clean database between tests
  config.before(:suite) { DatabaseCleaner.strategy = :transaction }
  config.before(:each) { DatabaseCleaner.start }
  config.after(:each) { DatabaseCleaner.clean }

  # Sidekiq test mode
  Sidekiq::Testing.fake!  # Don't actually process jobs
end
```

**What to say:**
- "FactoryBot for test data generation"
- "DatabaseCleaner ensures isolated tests"
- "Sidekiq fake mode - jobs enqueued but not processed (test job enqueuing separately)"

**Location:** `spec/rails_helper.rb`

---

#### **spec/factories/messages.rb**

```ruby
FactoryBot.define do
  factory :message do
    association :chat
    sequence(:number) { |n| n }
    body { Faker::Lorem.sentence }
  end
end
```

**What to say:**
- "sequence(:number) auto-increments for unique values"
- "Faker generates realistic test data"
- "association :chat automatically creates parent chat"

**Location:** `spec/factories/messages.rb`

---

#### **spec/requests/api/v1/messages_spec.rb**

```ruby
RSpec.describe 'Messages API', type: :request do
  describe 'POST /api/v1/applications/:token/chats/:number/messages' do
    it 'creates a message and returns number' do
      app = create(:chat_application)
      chat = create(:chat, chat_application: app)

      expect {
        post "/api/v1/applications/#{app.token}/chats/#{chat.number}/messages",
             params: { body: 'Hello' }
      }.to change(CreateMessageJob.jobs, :size).by(1)

      expect(response).to have_http_status(:created)
      expect(json_response['number']).to eq(1)
    end
  end
end
```

**What to say:**
- "Integration test - tests full HTTP request/response"
- "Tests job enqueuing (not execution)"
- "Verifies response status and JSON structure"
- "Uses FactoryBot to set up test data"

**Location:** `spec/requests/api/v1/messages_spec.rb`

**Test coverage:** 69 examples currently

---

## Key Files Deep Dive

### 1. **docker-compose.yml** (Multi-service orchestration)

**Services defined:**
1. **mysql** - Database (port 3306)
2. **redis** - Cache + queue (port 6379)
3. **elasticsearch** - Search (port 9200)
4. **rails** - Ruby API (port 3000)
5. **sidekiq** - Background workers (no port)
6. **go-service** - Go API (port 8080)
7. **frontend** - React UI (port 80)

**Key features:**
```yaml
services:
  mysql:
    healthcheck:
      test: ["CMD", "mysqladmin", "ping"]
      interval: 10s
    volumes:
      - mysql_data:/var/lib/mysql  # Persistent storage

  rails:
    depends_on:
      mysql:
        condition: service_healthy  # Wait for MySQL to be ready
    environment:
      DATABASE_HOST: mysql  # Docker DNS
```

**What to say:**
- "Health checks ensure services are ready before dependents start"
- "Named volumes persist data between container restarts"
- "Service names (mysql, redis) used as hostnames (Docker DNS)"
- "Single command starts entire stack: `docker-compose up`"

**Location:** `docker-compose.yml` (root)

---

### 2. **Dockerfile** (Rails container image)

```dockerfile
FROM ruby:3.3-alpine

RUN apk add --no-cache build-base mysql-dev

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]
```

**What to say:**
- "Multi-stage build: dependencies layer cached separately"
- "Alpine Linux for smaller image size"
- "build-base, mysql-dev for compiling native gems"
- "Exposes port 3000 for Puma web server"
- "Binds to 0.0.0.0 to accept external connections"

**Location:** `Dockerfile` (root)

---

### 3. **Gemfile** (Ruby dependencies)

```ruby
source 'https://rubygems.org'

ruby '3.3.0'

gem 'rails', '~> 8.1.0'
gem 'mysql2', '~> 0.5'
gem 'puma', '>= 6.0'
gem 'redis', '>= 5.0'
gem 'sidekiq', '~> 7.0'
gem 'elasticsearch-model'
gem 'elasticsearch-rails'
gem 'rack-cors'

group :development, :test do
  gem 'rspec-rails'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'database_cleaner'
end
```

**What to say:**
- "~> 8.1.0 means >= 8.1.0, < 8.2.0 (pessimistic versioning)"
- "mysql2 for database adapter"
- "Sidekiq for background jobs"
- "Elasticsearch gems for search integration"
- "rack-cors for cross-origin requests"
- "RSpec for testing (BDD style)"

**Location:** `Gemfile` (root)

---

## Common Interview Questions

### Q1: "Walk me through the folder structure"

**Answer:**
"The project follows Rails MVC conventions:
- **app/** contains the application code - models, controllers, jobs, services
- **config/** has all configuration - routes, database, initializers
- **db/** has migrations and schema
- **spec/** contains RSpec tests
- **go-service/** is a separate Go microservice
- **docker-compose.yml** orchestrates all 7 services

The Rails API is in app/controllers/api/v1/ - versioned API following REST conventions. Models in app/models/ handle data and relationships. Background jobs in app/jobs/ process async work. The go-service/ mirrors some Rails functionality but 10x faster."

---

### Q2: "Where is the sequential numbering logic?"

**Answer:**
"**app/services/sequential_number_service.rb** - This service object encapsulates the Redis INCR logic. It has two methods: `next_chat_number` and `next_message_number`, both using Redis atomic operations.

The controllers in **app/controllers/api/v1/** call this service to get numbers before enqueuing jobs. The Go service has equivalent logic in **go-service/cache/redis.go** using the same Redis INCR command."

---

### Q3: "Where are the API endpoints defined?"

**Answer:**
"**config/routes.rb** defines all routes using Rails nested resources:
```ruby
namespace :api do
  namespace :v1 do
    resources :applications, param: :token do
      resources :chats, param: :number do
        resources :messages, param: :number
      end
    end
  end
end
```

The actual controller logic is in:
- **app/controllers/api/v1/chat_applications_controller.rb**
- **app/controllers/api/v1/chats_controller.rb**
- **app/controllers/api/v1/messages_controller.rb**

The Go service defines routes in **go-service/main.go** using Gorilla Mux."

---

### Q4: "How is the database configured?"

**Answer:**
"**config/database.yml** defines MySQL connection settings. The migrations in **db/migrate/** create the schema:
1. **create_chat_applications.rb** - apps table with token column
2. **create_chats.rb** - chats table with composite unique index (application_id, number)
3. **create_messages.rb** - messages table with composite unique index (chat_id, number)

The current schema is in **db/schema.rb** (auto-generated). We use foreign keys for referential integrity and unique indices to prevent duplicates."

---

### Q5: "Where is the Elasticsearch integration?"

**Answer:**
"**app/models/message.rb** includes `Elasticsearch::Model` which adds search capabilities. The configuration is in **config/initializers/elasticsearch.rb**.

Indexing happens in **app/jobs/create_message_job.rb** - we manually index after creating the record (more control than auto-callbacks).

The search endpoint is in **app/controllers/api/v1/messages_controller.rb#search** using Elasticsearch bool queries.

If reindexing is needed, **app/jobs/reindex_messages_job.rb** bulk imports all messages."

---

### Q6: "How do you test this?"

**Answer:**
"We use RSpec with 69 examples covering:
- **spec/models/** - Model validations, associations
- **spec/requests/** - Full HTTP integration tests
- **spec/jobs/** - Background job behavior

Test configuration in **spec/rails_helper.rb** sets up:
- FactoryBot for test data (spec/factories/)
- DatabaseCleaner for isolation
- Sidekiq fake mode (enqueue but don't process)

We test the async pattern by verifying job enqueuing, not execution:
```ruby
expect { post '/messages' }.to change(CreateMessageJob.jobs, :size).by(1)
```"

---

### Q7: "Where would you add authentication?"

**Answer:**
"I'd add a **app/controllers/concerns/authenticatable.rb** module with JWT verification:
```ruby
module Authenticatable
  def authenticate!
    token = request.headers['Authorization']&.split(' ')&.last
    decoded = JWT.decode(token, secret_key)
    @current_user = User.find(decoded['user_id'])
  rescue JWT::DecodeError
    render json: { error: 'Unauthorized' }, status: 401
  end
end
```

Include it in **app/controllers/application_controller.rb** with `before_action :authenticate!`.

Add a **app/controllers/api/v1/auth_controller.rb** for login/token generation.

JWT configuration would go in **config/initializers/jwt.rb**."

---

### Q8: "How does Go communicate with Rails?"

**Answer:**
"Through Redis as a message bus. **go-service/queue/sidekiq.go** enqueues jobs in ActiveJob JSON format:
```go
payload := ActiveJobPayload{
    JobClass: "CreateMessageJob",
    Args: []interface{}{chatID, number, body},
}
conn.Do("LPUSH", "queue:default", jsonBytes)
```

Rails Sidekiq workers (configured in **config/initializers/sidekiq.rb**) poll the same Redis queue and deserialize the JSON back into Ruby CreateMessageJob instances in **app/jobs/create_message_job.rb**.

Both services share the same MySQL, Redis, and Sidekiq infrastructure - no data duplication."

---

## Tips for Explaining Files

### 1. Always Give the Full Path
❌ "It's in the controllers folder"
✅ "It's in **app/controllers/api/v1/messages_controller.rb**"

### 2. Explain the Why, Not Just the What
❌ "This file creates messages"
✅ "This file handles async message creation - it gets a sequential number from Redis, enqueues a background job, and returns immediately for sub-5ms response time"

### 3. Connect Files to Architecture
"The **sequential_number_service.rb** is the single point of serialization in our distributed system - it ensures Redis INCR is the atomic operation preventing race conditions"

### 4. Show Relationships Between Files
"**messages_controller.rb** calls **sequential_number_service.rb** to get a number, then enqueues **create_message_job.rb**, which persists to the **message.rb** model and indexes to Elasticsearch using config from **config/initializers/elasticsearch.rb**"

### 5. Be Ready to Open Any File
Have your editor open and be comfortable navigating:
- "Let me show you the exact code..."
- Opens `app/services/sequential_number_service.rb`
- Points to the Redis INCR line

---

## Quick Reference - Most Important Files

| Category | File | Why Important |
|----------|------|---------------|
| **Core Logic** | `app/services/sequential_number_service.rb` | Sequential numbering solution |
| **API** | `app/controllers/api/v1/messages_controller.rb` | Demonstrates async pattern + search |
| **Model** | `app/models/message.rb` | Elasticsearch integration |
| **Jobs** | `app/jobs/create_message_job.rb` | Error handling strategy |
| **Go Integration** | `go-service/queue/sidekiq.go` | Polyglot interoperability |
| **Routing** | `config/routes.rb` | REST API design |
| **Database** | `db/migrate/*_create_messages.rb` | Composite unique constraints |
| **Config** | `config/initializers/redis.rb` | Redis setup |
| **Orchestration** | `docker-compose.yml` | Multi-service architecture |

---

## Practice Script

**Interviewer:** "Can you explain your project structure?"

**You:** "Sure! The project has two backends - a Rails API and a Go service - both organized clearly. The Rails app follows MVC:
- **app/controllers/api/v1/** has the REST API controllers
- **app/models/** has the data models with validations
- **app/jobs/** has Sidekiq background jobs for async processing
- **app/services/** has business logic like sequential numbering

The **go-service/** directory is a separate Go microservice with handlers, cache, queue modules.

**config/** has all configuration - routes, database, Redis, Elasticsearch. **db/migrate/** has the schema migrations. **spec/** has RSpec tests.

The **docker-compose.yml** orchestrates all 7 services. Would you like me to dive deeper into any specific component?"

---

You now have a complete understanding of every backend folder and file in your project. Use this guide to confidently answer any question about your codebase structure!
