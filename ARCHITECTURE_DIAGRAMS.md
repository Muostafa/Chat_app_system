# Architecture Diagrams for Whiteboard Interviews

## Diagram 1: System Architecture (Draw this first!)

```
┌─────────────────────────────────────────────────────────────┐
│                   FRONTEND (React)                           │
│                    Port 80 (Nginx)                           │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │App Mgmt  │  │  Chats   │  │Messages  │  │  Search  │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│                                                              │
│  [Service Toggle: Rails ⟷ Go]   [Performance Chart]       │
└───────────────────┬──────────────────┬──────────────────────┘
                    │                  │
           HTTP     │                  │      HTTP
                    │                  │
      ┌─────────────▼──────┐    ┌─────▼────────────┐
      │   RAILS API        │    │   GO SERVICE     │
      │   Port 3000        │    │   Port 8080      │
      │                    │    │                  │
      │ ✓ Full CRUD        │    │ ✓ Write Only     │
      │ ✓ Business Logic   │    │ ✓ 10x Faster     │
      │ ✓ ~50ms response   │    │ ✓ ~5ms response  │
      └─────────┬──────────┘    └─────┬────────────┘
                │                     │
                │ SHARE INFRASTRUCTURE│
                └──────────┬──────────┘
                           │
           ┌───────────────┼───────────────┐
           │               │               │
           ▼               ▼               ▼
      ┌────────┐      ┌────────┐      ┌───────────┐
      │ MYSQL  │      │ REDIS  │      │ELASTICSEARCH│
      │ :3306  │      │ :6379  │      │   :9200    │
      │        │      │        │      │            │
      │Apps    │      │Atomic  │      │Full-text   │
      │Chats   │      │Counters│      │Search      │
      │Messages│      │Job Q   │      │Index       │
      └────────┘      └───┬────┘      └────────────┘
                          │
                          │ Poll for jobs
                          │
                      ┌───▼────┐
                      │SIDEKIQ │
                      │        │
                      │5 workers│
                      │        │
                      │Async   │
                      │Process │
                      └────────┘
```

**What to say while drawing:**
"The system has 7 containerized services. React frontend talks to both Rails and Go backends - user can toggle between them. Both backends share MySQL for data, Redis for atomic counters and job queue, and Elasticsearch for search. Sidekiq workers process background jobs asynchronously."

---

## Diagram 2: Request Flow - Creating a Message

```
┌─────────────────────────────────────────────────────────────┐
│                    TIME: 0-5ms                               │
└─────────────────────────────────────────────────────────────┘

    CLIENT
      │
      │ POST /applications/:token/chats/1/messages
      │ Body: { "body": "Hello World" }
      ▼
┌──────────────┐
│ RAILS/GO API │
│   Controller │
└──────┬───────┘
       │
       │ 1. Validate chat exists
       ▼
┌──────────────┐
│    REDIS     │
│              │  redis.incr("chat:123:message_counter")
│  INCR atomic │  ──────────────────────────────────────► 42
│   operation  │
└──────┬───────┘
       │
       │ 2. Got number: 42
       ▼
┌──────────────┐
│   SIDEKIQ    │
│  Job Queue   │  CreateMessageJob.perform_async(
│   (Redis)    │    chat_id: 123,
│              │    number: 42,
│              │    body: "Hello World"
└──────┬───────┘  )
       │
       │ 3. Job enqueued
       ▼
    CLIENT
      │
      │ Response: { "number": 42 }  ◄─── FAST! < 5ms
      │

┌─────────────────────────────────────────────────────────────┐
│              TIME: 100-500ms (ASYNC)                         │
└─────────────────────────────────────────────────────────────┘

┌──────────────┐
│   SIDEKIQ    │
│    Worker    │
└──────┬───────┘
       │
       │ 4. Process job from queue
       │
       ├──────────────────────────────────┐
       │                                  │
       ▼                                  ▼
┌──────────────┐                  ┌──────────────┐
│    MYSQL     │                  │ELASTICSEARCH │
│              │                  │              │
│ INSERT INTO  │                  │ Index message│
│ messages     │                  │ body for     │
│ (chat_id,    │                  │ full-text    │
│  number,     │                  │ search       │
│  body)       │                  │              │
└──────────────┘                  └──────────────┘
       │
       │ 5. Message persisted
       │
       ▼
┌──────────────┐
│   SIDEKIQ    │
│  Job Queue   │  UpdateChatMessageCountJob.perform_async(123)
│              │
└──────────────┘
```

**What to say while drawing:**
"The magic is in the async flow. When a request comes in, we validate, get an atomic number from Redis INCR, enqueue a background job, and return immediately - all in under 5ms. The heavy work happens later in Sidekiq: writing to MySQL, indexing to Elasticsearch, updating cached counters. This decouples response time from database latency."

---

## Diagram 3: Sequential Numbering - Race Condition Solution

```
┌─────────────────────────────────────────────────────────────┐
│              CONCURRENT REQUESTS                             │
└─────────────────────────────────────────────────────────────┘

Request A                Request B               Request C
(Thread 1)              (Thread 2)              (Thread 3)
    │                       │                       │
    │ Create message        │ Create message        │ Create message
    │ in Chat 123           │ in Chat 123           │ in Chat 123
    │                       │                       │
    └───────────┬───────────┴───────────┬───────────┘
                │                       │
                ▼                       ▼
        ┌───────────────────────────────────┐
        │         REDIS (Single-threaded)   │
        │                                   │
        │  INCR "chat:123:message_counter"  │
        │                                   │
        │  Atomic operation - no locks!     │
        │  Processes one at a time:         │
        │                                   │
        │  Request A: 0 → 1   ✓             │
        │  Request B: 1 → 2   ✓             │
        │  Request C: 2 → 3   ✓             │
        │                                   │
        │  NO DUPLICATES POSSIBLE!          │
        └───────────────┬───────────────────┘
                        │
        ┌───────────────┼───────────────────┐
        │               │                   │
        ▼               ▼                   ▼
    Number 1        Number 2            Number 3
        │               │                   │
        ▼               ▼                   ▼
    ┌───────────────────────────────────────────┐
    │            MYSQL (Safety Net)             │
    │                                           │
    │  UNIQUE INDEX (chat_id, number)           │
    │                                           │
    │  If somehow Redis gave duplicate:         │
    │  ► UniqueConstraintViolation              │
    │  ► Sidekiq retries with new number        │
    │                                           │
    └───────────────────────────────────────────┘
```

**What to say while drawing:**
"This is the key distributed systems challenge. Three concurrent requests all want sequential numbers. Redis INCR is our single point of serialization - it's atomic, so even though requests arrive simultaneously, Redis processes them one at a time. No race condition possible. The database unique constraint is our safety net in case Redis has a bug or network issue."

---

## Diagram 4: Data Model & Relationships

```
┌─────────────────────────────────────┐
│      CHAT_APPLICATIONS              │
│─────────────────────────────────────│
│  id (PK)              INTEGER       │
│  name                 VARCHAR       │
│  token                VARCHAR(32)   │◄─── Unique, indexed
│  chats_count          INTEGER       │     (API uses this, not ID)
│  created_at           TIMESTAMP     │
│  updated_at           TIMESTAMP     │
└────────────┬────────────────────────┘
             │
             │ has_many
             │
             ▼
┌─────────────────────────────────────┐
│           CHATS                     │
│─────────────────────────────────────│
│  id (PK)              INTEGER       │
│  chat_application_id (FK)INTEGER    │
│  number               INTEGER       │◄─── Sequential (1,2,3...)
│  messages_count       INTEGER       │     Generated by Redis
│  created_at           TIMESTAMP     │
│  updated_at           TIMESTAMP     │
│                                     │
│  UNIQUE INDEX (chat_application_id, number)
└────────────┬────────────────────────┘
             │
             │ has_many
             │
             ▼
┌─────────────────────────────────────┐
│         MESSAGES                    │
│─────────────────────────────────────│
│  id (PK)              INTEGER       │
│  chat_id (FK)         INTEGER       │
│  number               INTEGER       │◄─── Sequential (1,2,3...)
│  body                 TEXT          │     Generated by Redis
│  created_at           TIMESTAMP     │     ┌────────────────┐
│  updated_at           TIMESTAMP     │────►│ ELASTICSEARCH  │
│                                     │     │   messages     │
│  UNIQUE INDEX (chat_id, number)     │     │   index        │
│  FULLTEXT INDEX (body) ← MySQL      │     │                │
└─────────────────────────────────────┘     │ Async indexed  │
                                            │ by Sidekiq job │
                                            └────────────────┘

REDIS STRUCTURE:

"chat_app:1:chat_counter"      → 5    (Chat app 1 has 5 chats)
"chat_app:2:chat_counter"      → 3    (Chat app 2 has 3 chats)
"chat:1:message_counter"       → 42   (Chat 1 has 42 messages)
"chat:2:message_counter"       → 100  (Chat 2 has 100 messages)
```

**What to say while drawing:**
"Three-tier hierarchy: Applications contain Chats, Chats contain Messages. Each level uses sequential numbering. The number field is NOT the primary key - it's scoped to the parent. So Chat 1 has Messages 1,2,3... and Chat 2 also has Messages 1,2,3... The (chat_id, number) composite unique index ensures no duplicates within a chat. Redis stores the counter for each parent entity."

---

## Diagram 5: Polyglot Architecture - Rails + Go Integration

```
┌─────────────────────────────────────────────────────────────┐
│                      FRONTEND                                │
└───────────┬──────────────────────────┬──────────────────────┘
            │                          │
     User chooses:                User chooses:
     [Use Rails]                 [Use Go]
            │                          │
            ▼                          ▼
┌─────────────────────┐    ┌──────────────────────┐
│   RAILS API (Ruby)  │    │  GO SERVICE (Go)     │
│                     │    │                      │
│ Full CRUD:          │    │ Write-only:          │
│ ✓ Create            │    │ ✓ Create chats       │
│ ✓ Read              │    │ ✓ Create messages    │
│ ✓ Update            │    │                      │
│ ✓ Delete            │    │ (No reads/updates)   │
│ ✓ Search            │    │                      │
│                     │    │                      │
│ Language: Ruby      │    │ Language: Go         │
│ Response: ~50ms     │    │ Response: ~5ms       │
│ Throughput: 200/s   │    │ Throughput: 2000/s   │
└──────┬──────────────┘    └──────┬───────────────┘
       │                          │
       │  Both enqueue same job:  │
       │                          │
       │  CreateMessageJob        │
       │  (chat_id, number, body) │
       │                          │
       └────────┬─────────────────┘
                │
                ▼
┌───────────────────────────────────────┐
│      REDIS (Shared Job Queue)         │
│                                       │
│  Rails format:                        │
│  {                                    │
│    "class": "CreateMessageJob",       │
│    "args": [123, 42, "Hello"],        │
│    "queue": "default"                 │
│  }                                    │
│                                       │
│  Go must match this format! ──────────┼──┐
└───────────────────────────────────────┘  │
                │                          │
                │                          │
                ▼                          │
┌───────────────────────────────────────┐  │
│    SIDEKIQ WORKER (Rails process)     │  │
│                                       │  │
│  Polls Redis queue                    │  │
│  Deserializes JSON                    │  │
│  Executes CreateMessageJob            │  │
│                                       │  │
│  (Works for both Rails & Go jobs!)    │◄─┘
└───────────────────────────────────────┘
                │
                ├─────────────────┐
                │                 │
                ▼                 ▼
           ┌────────┐      ┌─────────────┐
           │ MYSQL  │      │ELASTICSEARCH│
           └────────┘      └─────────────┘
```

**What to say while drawing:**
"This is a real-world polyglot pattern. Rails handles complex logic and all reads. Go handles high-throughput writes - it's 10x faster because it's compiled and has better concurrency. The trick is Go must enqueue jobs in ActiveJob format so Rails Sidekiq workers can process them. Both languages share the same infrastructure - no data duplication. This lets us use the right tool for each job."

---

## Diagram 6: Error Handling & Resilience

```
┌─────────────────────────────────────────────────────────────┐
│                    HAPPY PATH                                │
└─────────────────────────────────────────────────────────────┘

Request → Redis INCR → Enqueue Job → Response (5ms)
                           │
                           ▼
               Sidekiq → MySQL → Elasticsearch
                           │         │
                           ✓         ✓
                        Success   Success


┌─────────────────────────────────────────────────────────────┐
│               FAILURE SCENARIOS                              │
└─────────────────────────────────────────────────────────────┘

SCENARIO 1: Redis Down
─────────────────────────
Request → ✗ Redis (timeout)
           │
           └─► Return 503 Service Unavailable
               "Sequential numbering unavailable"

Impact: No writes (can't generate numbers)
Reads: Still work (don't need Redis)


SCENARIO 2: MySQL Duplicate (Race Condition Edge Case)
───────────────────────────────────────────────────────
Sidekiq Job → MySQL INSERT
               │
               ✗ UniqueConstraintViolation
               │
               └─► Sidekiq retry logic:
                   Attempt 1: Wait 3s, retry
                   Attempt 2: Wait 9s, retry
                   ...
                   Attempt 25: Wait ~21 days
                   │
                   └─► Eventually succeeds with new number
                       (Or moves to Dead queue)


SCENARIO 3: Elasticsearch Down
───────────────────────────────
Sidekiq Job → MySQL ✓
               │
               ├─► Elasticsearch ✗ (timeout)
               │    │
               │    └─► Log error, DON'T fail job
               │
               └─► Job completes successfully
                   (Message in MySQL, search broken)

Recovery:
  Manual: Run ReindexMessagesJob
  Result: All messages reindexed to Elasticsearch


SCENARIO 4: Sidekiq Overload (Queue Backup)
─────────────────────────────────────────────
1000 requests/sec → Redis INCR ✓
                     │
                     └─► Queue: 10,000 jobs
                         Workers: Only 5
                         Processing: 50 jobs/sec
                         │
                         ├─► Queue grows (ALERT!)
                         │
                         └─► Solution: Add more workers
                             Scale Sidekiq horizontally


┌─────────────────────────────────────────────────────────────┐
│                   MONITORING & ALERTS                        │
└─────────────────────────────────────────────────────────────┘

Monitor:
  ✓ Redis connection pool usage
  ✓ Sidekiq queue depth (alert > 10k)
  ✓ MySQL connection pool
  ✓ Elasticsearch lag (time since last index)
  ✓ API error rate (alert > 1%)
  ✓ Response time p95 (alert > 500ms)

Health Checks:
  /health endpoint checks:
    - MySQL ping
    - Redis ping
    - Elasticsearch cluster health
  Returns 200 if all healthy, 503 if any down
```

**What to say while drawing:**
"The system has multiple failure modes. Redis down = no writes but reads work. MySQL duplicate = Sidekiq retries. Elasticsearch down = we log it but don't fail the job, search temporarily broken but can reindex later. The key is graceful degradation - don't let one component's failure break the whole system. We monitor queue depth, error rates, and response times to catch issues early."

---

## Diagram 7: Scaling Strategy

```
┌─────────────────────────────────────────────────────────────┐
│              CURRENT (Single Instance)                       │
└─────────────────────────────────────────────────────────────┘

        1 Rails API ──┐
                      ├──► 1 MySQL
        1 Go Service ─┤    1 Redis
                      │    1 Elasticsearch
        5 Sidekiq ────┘

Capacity: ~200 req/sec (Rails), ~2000 req/sec (Go)


┌─────────────────────────────────────────────────────────────┐
│         HORIZONTAL SCALING (100x traffic)                    │
└─────────────────────────────────────────────────────────────┘

                  ┌─────────────────┐
                  │  LOAD BALANCER  │
                  │   (nginx/HAProxy)│
                  └────────┬─────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
   ┌────────┐         ┌────────┐        ┌────────┐
   │Rails #1│         │Rails #2│   ...  │Rails #N│
   └────────┘         └────────┘        └────────┘
   ┌────────┐         ┌────────┐        ┌────────┐
   │ Go #1  │         │ Go #2  │   ...  │ Go #N  │
   └────┬───┘         └────┬───┘        └────┬───┘
        │                  │                  │
        └──────────────────┼──────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
   ┌─────────┐       ┌─────────┐       ┌─────────┐
   │ MySQL   │       │  Redis  │       │  Elastic│
   │ Master  │       │ Cluster │       │ Cluster │
   │    │    │       │ (sharded)│       │(sharded)│
   │    ▼    │       │         │       │         │
   │ Replica │       │ Node 1  │       │ Node 1  │
   │ Replica │       │ Node 2  │       │ Node 2  │
   └─────────┘       │ Node 3  │       │ Node 3  │
                     └────┬────┘       └─────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
        ▼                 ▼                 ▼
   ┌────────┐        ┌────────┐       ┌────────┐
   │Sidekiq │        │Sidekiq │  ...  │Sidekiq │
   │Host #1 │        │Host #2 │       │Host #N │
   │10 workers│      │10 workers│     │10 workers│
   └────────┘        └────────┘       └────────┘

Bottleneck Analysis:
  ✓ Rails/Go: Stateless → Add more instances
  ✓ Sidekiq: Add more workers/processes
  ✗ Redis INCR: Single-threaded
      → Solution: Redis Cluster with sharding
        chat_app:1:* → Node 1
        chat_app:2:* → Node 2
        (Hash slot based on app ID)
  ✗ MySQL Writes: Single master
      → Solution: Shard by application_id
        app_id % 10 → Shard 0-9
```

**What to say while drawing:**
"The current setup handles thousands of requests per second, but to scale to millions we need horizontal scaling. Rails and Go are stateless - easy to add instances behind a load balancer. Sidekiq workers can scale to hundreds of processes. The bottlenecks are Redis INCR (single-threaded) and MySQL writes. We'd shard both by application_id - each app's chats/messages go to a specific shard. This is the pattern used by systems like WhatsApp and Discord."

---

## Quick Whiteboard Tips

### 1. Start Simple, Add Complexity
```
First draw:
  Client → Server → Database

Then expand:
  Client → [Rails, Go] → [MySQL, Redis, ES] → Sidekiq
```

### 2. Use Consistent Symbols
```
┌──────┐
│ Box  │  = Service/Component
└──────┘

  │
  ▼      = Data flow

  ✓      = Success
  ✗      = Failure

  PK     = Primary Key
  FK     = Foreign Key
```

### 3. Label Everything
- Write the port number: "MySQL :3306"
- Write the purpose: "Redis (atomic counters)"
- Write the timing: "< 5ms response"

### 4. Use Colors (if available)
- Blue = Services
- Green = Success path
- Red = Error path
- Yellow = Async operations

### 5. Draw Flow with Time
```
TIME: 0-5ms
  [Fast synchronous stuff]

TIME: 100-500ms (ASYNC)
  [Slow background stuff]
```

---

## Practice Script

**Interviewer:** "Can you explain your system architecture?"

**You:**
1. "Let me draw the high-level architecture first" [Draw Diagram 1]
2. "The key challenge was sequential numbering under concurrency" [Draw Diagram 3]
3. "Let me show you how a request flows through the system" [Draw Diagram 2]
4. "Would you like to see how Rails and Go integrate?" [Draw Diagram 5]

**Interviewer:** "How do you handle failures?"

**You:**
[Draw Diagram 6 - Error Handling]
"Each component has its own failure strategy - graceful degradation is key"

**Interviewer:** "How would you scale this?"

**You:**
[Draw Diagram 7 - Scaling]
"The bottlenecks are Redis INCR and MySQL writes - we'd shard both by application_id"

---

## Remember:

- **Draw WHILE you talk** - Keeps them engaged
- **Point to the diagram** - "Here's where the magic happens"
- **Use arrows** - Show data flow clearly
- **Ask questions** - "Should I go deeper on this part?"
- **Iterate** - Start simple, add detail as needed

Your diagrams should tell a story: "This is what we built → This is why it's hard → This is how we solved it → This is how it scales"

Good luck! 🚀
