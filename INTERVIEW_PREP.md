# Interview Preparation Guide: Chat System Project

## Table of Contents
1. [Architecture & Design Questions](#architecture--design-questions)
2. [Concurrency & Race Conditions](#concurrency--race-conditions)
3. [Performance & Scalability](#performance--scalability)
4. [Database & Indexing](#database--indexing)
5. [Search Implementation](#search-implementation)
6. [Docker & Deployment](#docker--deployment)
7. [API Design](#api-design)
8. [Background Jobs & Queue System](#background-jobs--queue-system)
9. [Redis Implementation](#redis-implementation)
10. [Trade-offs & Improvements](#trade-offs--improvements)

---

## Architecture & Design Questions

### Q1: Walk me through the overall architecture of this system.

**Answer:**
"This is a multi-tenant chat system built with Rails that supports multiple applications, each with multiple chats containing messages. The architecture follows these key principles:

**Three-tier hierarchy:**
- ChatApplications (identified by tokens)
- Chats (numbered sequentially per application)
- Messages (numbered sequentially per chat)

**Async-first design:**
- HTTP requests return immediately with allocated numbers
- Actual database persistence happens asynchronously via background jobs
- This allows us to handle high request volumes without blocking

**Key components:**
- **Rails API**: Stateless REST endpoints
- **MySQL**: Primary data store with optimized indices
- **Redis**: Sequential number generation and job queue
- **Elasticsearch**: Full-text search with partial matching
- **Sidekiq**: Background job processor

**Why this design?**
- Separates fast operations (number allocation) from slow ones (DB writes)
- Horizontal scalability through stateless design
- Race condition protection through atomic Redis operations"

---

### Q2: Why did you choose to make chat/message creation asynchronous?

**Answer:**
"The requirement explicitly stated to 'avoid writing directly to MySQL while serving requests' and that 'it is allowed for chats and messages to take time to be persisted.'

**Benefits of async approach:**

1. **Performance**: Request handling takes ~5ms (Redis INCR) instead of ~50-100ms (MySQL write + transaction)

2. **Scalability**: Can handle 10-20x more requests per second since we're not blocked on database I/O

3. **Resilience**: If database is temporarily slow or unavailable, we can still accept requests and queue them

4. **Decoupling**: Web servers don't need to wait for write confirmations, reducing resource usage

**Trade-off accepted:**
- Eventual consistency: There's a small delay (typically < 1 second) before entities appear in database
- This is acceptable per requirements and common in high-traffic systems (like Twitter's tweet creation)

**Implementation:**
- Generate sequential number from Redis (atomic, fast)
- Return immediately with 201 Created
- Queue job to persist to MySQL + update counters + index in Elasticsearch"

---

### Q3: How do you ensure data consistency in an async system?

**Answer:**
"Great question. There are several layers of consistency guarantees:

**1. Sequential number uniqueness (CRITICAL):**
- Redis INCR is atomic across all servers
- Returns unique numbers even under high concurrency
- Database unique constraints as secondary protection

**2. Job idempotency:**
- CreateChatJob and CreateMessageJob are idempotent
- If a job runs twice due to retry, unique constraint prevents duplicates
- Errors are logged but don't corrupt data

**3. Counter consistency:**
- Optimistic: Increment counter atomically in creation job
- Pessimistic: SyncCountersJob recalculates every 30 minutes
- Uses database locking (with_lock) to prevent race conditions

**4. Monitoring & recovery:**
- Job failures are logged with IDs
- Can replay failed jobs from logs
- Database constraints prevent corruption even if jobs fail

**Example scenario:**
```
1. Client requests chat creation
2. Redis INCR returns number 42
3. We return { number: 42 } immediately
4. If CreateChatJob fails:
   - Job is retried automatically (Sidekiq)
   - If retry fails, error is logged with chat_application_id + number
   - DBA can manually create the record later
   - Number 42 is permanently allocated (Redis doesn't decrement)
```

**Result:** Eventually consistent, but never corrupted."

---

## Concurrency & Race Conditions

### Q4: How do you handle race conditions when multiple servers create chats simultaneously?

**Answer:**
"This is handled through atomic operations at multiple levels:

**Level 1: Sequential Number Generation (Redis)**
```ruby
def self.next_chat_number(chat_application_id)
  redis = Redis.new
  key = "chat_app:#{chat_application_id}:chat_counter"
  redis.incr(key)  # ATOMIC operation
end
```

**Why Redis INCR?**
- Single-threaded command execution in Redis
- Returns unique value even if 1000 servers call simultaneously
- Guaranteed no duplicates

**Level 2: Database Unique Constraints**
```sql
CREATE UNIQUE INDEX index_chats_on_chat_application_id_and_number
  ON chats (chat_application_id, number);
```
- Catch-all if Redis somehow fails
- Database rejects duplicate combinations

**Level 3: Model Validation**
```ruby
validates :number, uniqueness: { scope: :chat_application_id }
```
- Application-level check before INSERT

**Real-world scenario:**
```
Time T0: Server A calls Redis INCR → gets 5
Time T0: Server B calls Redis INCR → gets 6
Time T1: Both queue CreateChatJob(app_id: 123, number: 5/6)
Time T2: Both jobs run in parallel
Result: Two different chats created successfully, no conflict
```

**Counter race conditions:**
```ruby
# In UpdateChatApplicationCountJob
chat_application.with_lock do
  actual_count = chat_application.chats.count
  chat_application.update_column(:chats_count, actual_count)
end
```
- Pessimistic locking prevents concurrent counter updates
- Each job waits its turn to update"

---

### Q5: What happens if Redis goes down?

**Answer:**
"Excellent failure scenario question. Here's the impact and mitigation:

**Immediate Impact:**
- SequentialNumberService.next_chat_number would raise exception
- Chat/message creation endpoints would return 500 error
- Existing chats/messages still work (reads from MySQL)
- Search still works (Elasticsearch)

**Mitigation Strategy:**

**1. Circuit Breaker Pattern (what I'd add):**
```ruby
def self.next_chat_number(chat_application_id)
  redis = Redis.new
  redis.incr("chat_app:#{chat_application_id}:chat_counter")
rescue Redis::CannotConnectError
  # Fallback to database-based counter
  ChatApplication.find(chat_application_id).increment!(:last_chat_number)
  ChatApplication.find(chat_application_id).last_chat_number
end
```

**2. Redis High Availability (production setup):**
- Redis Sentinel (automatic failover)
- Redis Cluster (distributed)
- Master-Replica setup with automatic promotion

**3. Graceful Degradation:**
- Return 503 Service Temporarily Unavailable
- Queue requests in memory buffer for short outages
- Once Redis recovers, sync numbers

**4. Monitoring & Alerting:**
- Redis health check every 10 seconds
- Alert if connection fails
- Automatic restart via Docker/Kubernetes

**Recovery:**
```ruby
# After Redis comes back up
ChatApplication.find_each do |app|
  max_number = app.chats.maximum(:number) || 0
  Redis.new.set("chat_app:#{app.id}:chat_counter", max_number)
end
```

**Bottom line:** Redis is single point of failure in current design, but easily mitigated with HA setup or fallback logic."

---

### Q6: How do you prevent duplicate message numbers if two requests come in at the exact same millisecond?

**Answer:**
"This is exactly what atomic operations solve. Let me break down what happens:

**Scenario: 2 requests for the same chat at T=0ms**

```
Request A (Server 1)                Request B (Server 2)
─────────────────────────────────── ───────────────────────────────────
T=0ms: Receives POST /messages      T=0ms: Receives POST /messages
T=1ms: Calls Redis INCR chat:5      T=1ms: Calls Redis INCR chat:5
       ↓                                   ↓
       Redis internal queue:
       [INCR chat:5 from Server1] → Returns 1
       [INCR chat:5 from Server2] → Returns 2
       ↓                                   ↓
T=2ms: Gets number 1                T=2ms: Gets number 2
T=3ms: Returns {number: 1}          T=3ms: Returns {number: 2}
T=4ms: Queues CreateMessageJob(1)   T=4ms: Queues CreateMessageJob(2)
```

**Why no duplicates?**

1. **Redis is single-threaded**: Commands execute serially, never in parallel
2. **INCR is atomic**: Entire read-increment-write happens as one operation
3. **No time-of-check-to-time-of-use (TOCTOU) bug**: No gap between reading and writing

**Comparison to naive approach (WRONG):**
```ruby
# BAD - Race condition
current = redis.get("counter")      # Server A reads 5
current = redis.get("counter")      # Server B reads 5
new_value = current + 1             # A calculates 6
new_value = current + 1             # B calculates 6
redis.set("counter", new_value)     # A writes 6
redis.set("counter", new_value)     # B writes 6
# Result: Both got 6! DUPLICATE!
```

**Our approach (CORRECT):**
```ruby
# GOOD - Atomic
number = redis.incr("counter")  # Server A gets 6
number = redis.incr("counter")  # Server B gets 7
# Result: Unique numbers guaranteed
```

**Proof it works:**
- Redis INCR documentation guarantees atomicity
- Used in production by millions of apps (GitHub, Twitter, etc.)
- We have database unique constraints as backup safety net"

---

## Performance & Scalability

### Q7: How many requests per second can this system handle?

**Answer:**
"Let me break this down by endpoint type and bottlenecks:

**Message Creation (Most Critical):**

**Current capacity:**
- Redis INCR: ~100,000 ops/sec (single instance)
- Our overhead: ~0.5ms (validation + job queuing)
- **Theoretical**: ~2,000 requests/sec per web server
- **Practical**: ~1,000 requests/sec per server (50% safety margin)

**With 5 web servers:** 5,000 messages/sec = 432M messages/day

**Bottleneck analysis:**

1. **Redis (current bottleneck):**
   - Single instance: 100k ops/sec
   - Solution: Redis Cluster → 1M ops/sec

2. **Web servers (scalable):**
   - Stateless design → add more servers linearly
   - Each server: 1k req/sec
   - 10 servers → 10k req/sec

3. **MySQL (potential bottleneck):**
   - Async writes via jobs reduces pressure
   - Writes: ~5k/sec with proper tuning
   - Reads: 50k/sec with read replicas
   - Solution: Shard by chat_application_id

4. **Sidekiq workers (scalable):**
   - Each worker: ~100 jobs/sec
   - 50 workers → 5k jobs/sec
   - Matches write capacity

**Read operations (GET /messages):**
- Cache hit (Redis): 50k req/sec per server
- Cache miss (MySQL): 10k req/sec per server
- With 5 servers: 250k reads/sec cached, 50k uncached

**Search operations:**
- Elasticsearch: ~2k queries/sec per node
- 3-node cluster: 6k queries/sec

**Realistic production estimate:**
- **Writes**: 5,000 messages/sec sustained
- **Reads**: 50,000 reads/sec
- **Search**: 2,000 searches/sec

**For reference:**
- WhatsApp: ~100k messages/sec (needs ~20 Redis instances)
- Slack: ~10k messages/sec
- Our system: Comparable to mid-size chat platform"

---

### Q8: How would you scale this system to handle 10x more traffic?

**Answer:**
"Great question. Here's my scaling roadmap from 5k to 50k messages/sec:

**Phase 1: Vertical Scaling (Quick Win - 2x improvement)**

1. **Upgrade Redis:**
   - Current: Single instance
   - New: Redis Cluster (6 nodes)
   - Result: 600k ops/sec capacity

2. **Add Read Replicas:**
   - 3 MySQL read replicas
   - Route reads to replicas
   - Result: 10x read capacity

3. **More Sidekiq Workers:**
   - Current: 1 container with 5 threads
   - New: 10 containers with 10 threads each
   - Result: 20x job processing capacity

**Cost:** ~$500/month additional → 10k msg/sec

---

**Phase 2: Horizontal Scaling (20x improvement)**

4. **Web Server Auto-scaling:**
   - Kubernetes HPA (Horizontal Pod Autoscaler)
   - Scale from 5 → 50 pods based on CPU
   - Result: 50k req/sec capacity

5. **Database Sharding:**
```ruby
# Shard by chat_application_id
shard = Digest::MD5.hexdigest(application_token)[0] % 4
# Shard 0: apps 0, 4, 8, 12...
# Shard 1: apps 1, 5, 9, 13...
# Each shard: 12.5k msg/sec
```

6. **Elasticsearch Scaling:**
   - 3 → 12 nodes
   - Index per month (chats_2025_01, chats_2025_02)
   - Result: 8k queries/sec

**Cost:** ~$3k/month → 50k msg/sec

---

**Phase 3: Architecture Changes (100x improvement)**

7. **Event Streaming (Kafka):**
```
Client → API → Kafka → [MySQL Worker, ES Worker, Counter Worker]
```
- Decouples write path
- Better failure isolation
- Supports 100k+ msg/sec

8. **Message Caching:**
```ruby
# Cache last 100 messages per chat in Redis
REDIS.lpush("chat:#{id}:messages", message.to_json)
REDIS.ltrim("chat:#{id}:messages", 0, 99)
```
- 90% of reads hit cache
- Reduces MySQL load by 10x

9. **Geographic Distribution:**
- Multi-region deployment (US-East, US-West, EU, Asia)
- Chat affinity routing (sticky chats to regions)
- Result: Lower latency + higher throughput

10. **Denormalization:**
```ruby
# Store message count in Redis instead of MySQL
REDIS.incr("chat:#{id}:message_count")
# Sync to MySQL hourly
```

**Cost:** ~$15k/month → 200k+ msg/sec

---

**Monitoring Setup:**
```ruby
# Key metrics to track
- Redis ops/sec (alert at 80k)
- MySQL connections (alert at 80%)
- Sidekiq queue depth (alert at 10k)
- API response time (alert at 500ms p99)
```

**Bottleneck Evolution:**
```
Current:    Redis INCR (100k ops/sec)
10x scale:  MySQL writes (50k/sec)
100x scale: Network bandwidth (10 Gbps)
```

**Bottom line:** System is architected for linear scaling up to ~200k msg/sec with incremental improvements."

---

## Database & Indexing

### Q9: Walk me through your database schema and why you designed it this way.

**Answer:**
"The schema follows a hierarchical model optimized for both writes and reads:

**Schema Overview:**
```sql
chat_applications
├── id (PK, internal)
├── token (UNIQUE, external identifier)
├── name
├── chats_count (denormalized counter)

chats
├── id (PK, internal)
├── chat_application_id (FK)
├── number (sequential per application)
├── messages_count (denormalized counter)
├── UNIQUE(chat_application_id, number)

messages
├── id (PK, internal)
├── chat_id (FK)
├── number (sequential per chat)
├── body (TEXT)
├── UNIQUE(chat_id, number)
```

**Design Decisions:**

**1. Dual Identifier System:**
- Internal: Auto-increment IDs for foreign keys (never exposed)
- External: token/number for API (exposed to clients)

**Why?**
- Security: Can't guess other applications/chats
- Flexibility: Can migrate data without breaking client code
- Performance: Integer joins faster than string joins

**2. Sequential Numbers Instead of UUIDs:**
- Requirement: "Numbering starts from 1"
- User-friendly: Easier to reference ("message 42")
- Sortable: Natural chronological order
- Compact: 4 bytes vs 16 bytes for UUID

**3. Denormalized Counters:**
```sql
chats_count INTEGER DEFAULT 0 NOT NULL
messages_count INTEGER DEFAULT 0 NOT NULL
```

**Why not COUNT(*)every time?**
```sql
-- Slow - O(n) full table scan
SELECT COUNT(*) FROM chats WHERE chat_application_id = 123;

-- Fast - O(1) index lookup
SELECT chats_count FROM chat_applications WHERE id = 123;
```
- 1000x faster for apps with millions of chats
- Trade-off: Eventual consistency (acceptable per requirements)

**4. No Polymorphic Associations:**
- Each table has clear single purpose
- Easier to index and query
- Better query performance

**5. NOT NULL Constraints:**
```sql
token VARCHAR(255) NOT NULL
number INTEGER NOT NULL
body TEXT NOT NULL
```
- Database-level validation
- Prevents NULL pointer issues
- Self-documenting schema

**Schema Evolution:**
```sql
-- Initial version
CREATE TABLE chats (id, chat_application_id, number)

-- What I'd add for scale:
created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
archived_at TIMESTAMP NULL (soft delete)
```

**Result:** Clean, normalized where it matters, denormalized for performance."

---

### Q10: Explain your indexing strategy. Why these specific indices?

**Answer:**
"Indices are critical for performance. Every index was chosen based on actual query patterns:

**Index 1: Applications by Token**
```sql
CREATE UNIQUE INDEX index_chat_applications_on_token
  ON chat_applications(token);
```

**Query it optimizes:**
```ruby
ChatApplication.find_by!(token: params[:token])
```

**Why UNIQUE?**
- Enforces business rule (one app per token)
- Enables using token as identifier in URLs
- B-tree index: O(log n) lookup

**Without index:** Full table scan - O(n)
**With index:** Binary search - O(log n)
**Example:** 1M apps: 1M ops → 20 ops (50,000x faster)

---

**Index 2: Composite Unique on Chats**
```sql
CREATE UNIQUE INDEX index_chats_on_chat_application_id_and_number
  ON chats(chat_application_id, number);
```

**Queries it optimizes:**
```ruby
# Lookup specific chat
@chat_application.chats.find_by!(number: params[:number])

# List all chats for app (range scan)
@chat_application.chats.all
```

**Why composite?**
- Enforces uniqueness per application
- Supports both equality and range queries
- Left-prefix rule: Can use for `chat_application_id` alone

**Index ordering matters:**
```sql
-- Good: (chat_application_id, number)
WHERE chat_application_id = 123 AND number = 5  -- Uses index
WHERE chat_application_id = 123                 -- Uses index

-- Bad: (number, chat_application_id)
WHERE chat_application_id = 123                 -- Doesn't use index
```

---

**Index 3: Foreign Key on chat_application_id**
```sql
CREATE INDEX index_chats_on_chat_application_id
  ON chats(chat_application_id);
```

**Wait, isn't this redundant with Index 2?**

Actually, no. This is for:
```ruby
# COUNT operations for counter sync
app.chats.count  # Uses this index for fast counting

# CASCADE DELETE operations
DELETE FROM chats WHERE chat_application_id = 123
```

**Without FK index:**
- DELETE requires full table scan to find related records
- Can lock table for seconds

---

**Index 4: Composite Unique on Messages**
```sql
CREATE UNIQUE INDEX index_messages_on_chat_id_and_number
  ON messages(chat_id, number);
```

**Same reasoning as chats:**
- Uniqueness enforcement
- Fast lookups by number
- Range queries for pagination

---

**Index 5: Full-Text Index on Message Body**
```sql
CREATE FULLTEXT INDEX index_messages_on_body
  ON messages(body);
```

**Why full-text instead of regular B-tree?**

**B-tree index:**
```sql
-- Only works for prefix matching
WHERE body LIKE 'hello%'  -- Uses index
WHERE body LIKE '%hello%' -- Full table scan
```

**Full-text index:**
```sql
-- Works for any word in text
MATCH(body) AGAINST('hello')  -- Uses index
```

**Our approach:**
- Use Elasticsearch for search (better than MySQL full-text)
- Keep MySQL index as backup/fallback
- MySQL FT index also helps with analytics queries

---

**Index Maintenance Overhead:**

**Write cost:**
```
Without indices: INSERT takes 1ms
With 5 indices:  INSERT takes ~2ms (each index updated)
```

**Trade-off:** 2x slower writes for 10,000x faster reads

**Monitoring index usage:**
```sql
-- Check if index is used
EXPLAIN SELECT * FROM chats WHERE chat_application_id = 123;

-- Check index size
SELECT index_name,
       ROUND(stat_value * @@innodb_page_size / 1024 / 1024, 2) size_mb
FROM mysql.innodb_index_stats
WHERE table_name = 'chats';
```

**What I didn't index (and why):**
- `created_at`: No queries filter by this alone
- `chats_count`: Only used for SELECT, not WHERE
- `body` field in B-tree: Would be huge, full-text is better

**Result:** Every query uses an index, no full table scans, optimized for read-heavy workload."

---

### Q11: How do you handle database migrations in a zero-downtime deployment?

**Answer:**
"This is critical for production systems. Here's my approach:

**General Strategy: Expand-Migrate-Contract**

**Example: Adding `archived_at` column**

**Phase 1: EXPAND (Deploy v1)**
```ruby
# Migration
class AddArchivedAtToChats < ActiveRecord::Migration[7.0]
  def change
    add_column :chats, :archived_at, :timestamp, null: true
  end
end
```

**Deployment:**
```bash
# On one server at a time:
1. Deploy new code (handles NULL archived_at)
2. Run migration (adds column)
3. Old servers still work (ignore new column)
```

**Zero downtime:** Old and new code both work

---

**Phase 2: MIGRATE (Background Job)**
```ruby
# Backfill data for existing records
Chat.where(archived_at: nil, active: false).find_in_batches do |batch|
  batch.each do |chat|
    chat.update_column(:archived_at, chat.updated_at)
  end
  sleep 0.1  # Don't overwhelm database
end
```

---

**Phase 3: CONTRACT (Deploy v2, weeks later)**
```ruby
# Migration
class MakeArchivedAtNotNull < ActiveRecord::Migration[7.0]
  def change
    change_column_null :chats, :archived_at, false, Time.current
  end
end
```

**Deployment:**
- All records now have archived_at
- Safe to make NOT NULL

---

**Handling Index Additions:**

**Problem:** Index creation locks table (can take minutes on large tables)

**Solution: CONCURRENT index creation**
```ruby
class AddIndexToMessages < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!  # Required for concurrent

  def change
    add_index :messages, :chat_id, algorithm: :concurrently
  end
end
```

**What this does:**
- Builds index without locking table
- Writes can continue during build
- Takes longer but zero downtime

---

**Handling Column Renames:**

**Bad (causes downtime):**
```ruby
rename_column :messages, :content, :body
```

**Good (3-phase deployment):**

**Phase 1:** Add new column
```ruby
add_column :messages, :body, :text
# App writes to both columns
```

**Phase 2:** Backfill data
```ruby
Message.where(body: nil).update_all("body = content")
```

**Phase 3:** Remove old column
```ruby
remove_column :messages, :content
```

---

**Handling Data Type Changes:**

**Example: token from VARCHAR(32) to VARCHAR(64)**

**Approach:**
```ruby
# Safe - no downtime
change_column :chat_applications, :token, :string, limit: 64

# MySQL executes as:
# CREATE TABLE chat_applications_new ...
# INSERT INTO chat_applications_new SELECT * FROM chat_applications
# RENAME TABLE chat_applications TO old, chat_applications_new TO chat_applications
```

**For large tables:** Use pt-online-schema-change (Percona Toolkit)

---

**Migration Testing:**
```ruby
# Always test rollback
def change
  add_column :chats, :archived_at, :timestamp
end

def down
  remove_column :chats, :archived_at
end
```

**Pre-deployment checklist:**
1. Run migration on staging database dump
2. Measure time (estimate production 10x longer)
3. Test rollback
4. If > 5 seconds, use concurrent or background

**Monitoring during deployment:**
```sql
-- Check for long-running queries
SELECT * FROM information_schema.processlist
WHERE time > 5 AND command != 'Sleep';

-- Check for locks
SHOW ENGINE INNODB STATUS;
```

**Result:** Safe, reversible migrations with zero user-facing downtime."

---

## Search Implementation

### Q12: Why did you choose Elasticsearch over MySQL full-text search?

**Answer:**
"Great question. Both could work, but Elasticsearch is superior for this use case:

**Requirements:**
- Partial matching ('hel' → 'hello')
- Scale to millions of messages
- Fast search (< 100ms)
- Eventually consistent (acceptable per requirements)

**Comparison:**

| Feature | MySQL Full-Text | Elasticsearch |
|---------|----------------|---------------|
| Partial matching | Limited (wildcard slow) | Excellent (n-gram, wildcard) |
| Scalability | Single server | Distributed cluster |
| Speed (1M docs) | 200-500ms | 20-50ms |
| Relevance ranking | Basic | Advanced (TF-IDF, BM25) |
| Language support | Limited | 40+ languages |
| Analytics | No | Yes (aggregations) |
| Maintenance | Low | Medium |

**Technical Deep Dive:**

**1. Partial Matching:**

**MySQL approach (slow):**
```sql
SELECT * FROM messages
WHERE body LIKE '%hel%';  -- Full table scan!
```
- Can't use B-tree index for middle wildcards
- Scans every row
- 1M messages: ~2 seconds

**MySQL with full-text (better but limited):**
```sql
SELECT * FROM messages
WHERE MATCH(body) AGAINST('+hel*' IN BOOLEAN MODE);
```
- Works for prefix ('hel*')
- Doesn't work for infix ('*hel*')
- No fuzzy matching

**Elasticsearch approach (fast):**
```json
{
  "query": {
    "wildcard": { "body.keyword": "*hel*" }
  }
}
```
- Uses inverted index with term dictionary
- FST (Finite State Transducer) for fast prefix matching
- 1M messages: ~30ms

**2. Scalability:**

**MySQL:**
- Single server bottleneck
- Read replicas help, but still limited
- Vertical scaling only ($$$)

**Elasticsearch:**
```
Index: messages (1B documents)
├── Shard 0 (Node 1): 250M docs
├── Shard 1 (Node 2): 250M docs
├── Shard 2 (Node 3): 250M docs
└── Shard 3 (Node 4): 250M docs

Query distributed across all nodes in parallel
Result: 4x faster than single node
```

**3. Advanced Features We Get:**

**Typo tolerance:**
```json
{
  "query": {
    "fuzzy": { "body": { "value": "helo", "fuzziness": 1 } }
  }
}
```
Finds "hello" even with typo

**Highlighting:**
```json
"highlight": { "fields": { "body": {} } }
```
Returns: "... say <em>hello</em> to the world ..."

**Aggregations (for analytics):**
```json
{
  "aggs": {
    "messages_per_day": {
      "date_histogram": { "field": "created_at", "interval": "day" }
    }
  }
}
```

**4. Integration:**

**Elasticsearch-Model gem:**
```ruby
class Message < ApplicationRecord
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks  # Auto-sync
end
```

**Auto-indexing:**
- New messages indexed automatically in CreateMessageJob
- Updates/deletes synced via callbacks
- Async so doesn't block user requests

**Fallback strategy:**
```ruby
def search(query)
  Message.search(query).records
rescue Elasticsearch::Transport::Transport::Error
  # Fallback to MySQL if ES is down
  Message.where("body LIKE ?", "%#{query}%")
end
```

**5. Cost Comparison:**

**MySQL:**
- Single large instance: $500/month
- Storage: $100/month
- Total: $600/month

**Elasticsearch:**
- 3-node cluster: $600/month
- Storage (with replicas): $200/month
- Total: $800/month

**Extra $200/month for:**
- 10x faster search
- Better partial matching
- Horizontal scalability
- Advanced features

**Trade-offs:**

**Elasticsearch Cons:**
- More complex (another service to maintain)
- Eventual consistency (index lag ~1 second)
- Higher memory usage (needs 2GB+ per node)

**When MySQL FT would be better:**
- < 10k messages total
- Only prefix matching needed ('hello%')
- Strong consistency required
- Simpler deployment

**For this project:** Elasticsearch is the right choice because requirements explicitly state 'partial matching' and we need to scale to many applications with millions of messages."

---

### Q13: Explain how your Elasticsearch indexing works and potential issues.

**Answer:**
"Let me walk through the complete indexing lifecycle and challenges:

**Index Configuration:**
```ruby
# In Message model
settings do
  mapping do
    indexes :body, type: :text, analyzer: :standard do
      indexes :keyword, type: :keyword  # For wildcard queries
    end
    indexes :chat_id, type: :integer
  end
end
```

**Why two fields for body?**

**body (analyzed):**
- Tokenized: "Hello World" → ["hello", "world"]
- Lowercased, stemmed
- Good for: Word matching, relevance ranking

**body.keyword (not analyzed):**
- Stored as-is: "Hello World" → "Hello World"
- Case-sensitive by default (we lowercase in query)
- Good for: Wildcard queries, exact matching

**Indexing Flow:**

**1. Message Creation:**
```ruby
# Controller returns immediately
POST /messages → { number: 42 }

# Background job runs
CreateMessageJob:
  1. message = chat.messages.create!(number: 42, body: "Hello")
  2. Message.__elasticsearch__.index_document(message)
  3. Chat.increment_counter(:messages_count, chat_id)
```

**2. Elasticsearch Indexing:**
```json
POST /messages/_doc/123
{
  "id": 123,
  "body": "Hello World",
  "chat_id": 456,
  "created_at": "2025-01-15T10:30:00Z"
}
```

**3. ES Internal Processing:**
- Analyze text: "Hello World" → tokens
- Build inverted index:
  ```
  Term     → Document IDs
  ----        ------------
  hello    → [123, 456, 789]
  world    → [123, 234, 789]
  ```
- Store keyword: "hello world" (lowercased in our query)
- Refresh interval: 1 second (document becomes searchable)

---

**Potential Issues & Solutions:**

**Issue 1: Indexing Lag**

**Problem:**
```
T=0: Client creates message
T=0: Returns { number: 42 }
T=1: Client searches for message
T=1: Message not found (not indexed yet)
```

**Solutions:**
```ruby
# Option 1: Synchronous indexing (bad for performance)
def create
  message.save!
  Message.__elasticsearch__.refresh_index!  # Force immediate refresh
  render json: message
end

# Option 2: Accept eventual consistency (what we do)
# Documentation: "Messages may take 1-2 seconds to appear in search"

# Option 3: Optimistic UI (frontend)
# Show message immediately in UI, even before indexed
```

**Issue 2: Index Out of Sync**

**Scenario:**
```ruby
# Job fails after DB write but before ES indexing
message = Message.create!(...)
# Network error: Elasticsearch::Transport::Transport::Error
Message.__elasticsearch__.index_document(message)  # FAILS
```

**Result:** Message in MySQL but not in Elasticsearch

**Detection:**
```ruby
# Reconciliation job (runs nightly)
class ReconcileElasticsearchJob < ApplicationJob
  def perform
    Message.find_in_batches do |batch|
      batch.each do |message|
        unless Message.search(query: { term: { id: message.id } }).any?
          Message.__elasticsearch__.index_document(message)
        end
      end
    end
  end
end
```

**Issue 3: Index Corruption**

**Problem:** Elasticsearch node crashes during write

**Solution: Replicas**
```json
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 2  // Each shard has 2 copies
  }
}
```

**Result:** Even if 1-2 nodes crash, data is safe

**Issue 4: Storage Growth**

**Problem:** 1M messages/day = 365M messages/year = 500GB+ index

**Solution: Time-based Indices**
```ruby
# Instead of single 'messages' index:
messages-2025-01  # Jan messages
messages-2025-02  # Feb messages
messages-2025-03  # Mar messages

# Search across all:
GET /messages-*/_search { ... }

# Delete old indices:
DELETE /messages-2024-*
```

**Issue 5: Search Performance Degradation**

**Problem:** As index grows, searches slow down

**Solution: Optimize**
```ruby
# Quarterly optimization (off-peak hours)
POST /messages/_forcemerge?max_num_segments=1
```

**Reduces:**
- Segment count (fewer files to search)
- Disk I/O
- Search latency by 30-50%

---

**Monitoring:**

```ruby
# Index health
GET /_cluster/health

# Index size
GET /messages/_stats

# Slow queries (> 1 second)
GET /messages/_search
{
  "profile": true,  // Shows query breakdown
  "query": { ... }
}
```

**Alerting:**
- Index lag > 10 seconds
- Failed indexing jobs > 1%
- Disk usage > 80%
- Search latency p99 > 500ms

**Result:** Robust, self-healing search infrastructure with <0.1% data loss tolerance."

---

## Docker & Deployment

### Q14: Walk me through what happens when someone runs `docker-compose up`.

**Answer:**
"Great question. Let me trace through the entire startup sequence:

**Stage 1: Image Building (if needed)**
```bash
docker-compose up
```

**Output:**
```
Building web
Step 1/15 : FROM ruby:3.4.7-slim as base
 ---> Pulling image
Step 2/15 : RUN apt-get update && apt-get install -y mysql-client
 ---> Running in container_xyz
...
Successfully built abc123
```

**What happens:**
1. Reads `docker-compose.yml`
2. Checks if image `chat_system_web` exists
3. If not, builds from `Dockerfile`:
   - Base stage: Install system dependencies
   - Build stage: Bundle install gems
   - Final stage: Copy app code, set permissions

---

**Stage 2: Service Startup (Dependency Order)**

**Order determined by `depends_on`:**
```yaml
web:
  depends_on:
    mysql:
      condition: service_healthy
    redis:
      condition: service_healthy
    elasticsearch:
      condition: service_healthy
```

**Startup Sequence:**

**T=0s: MySQL starts**
```bash
[mysql] Initializing database
[mysql] Creating user 'root'@'%'
[mysql] Starting MySQL 8.0
```

**Health check (every 2 seconds):**
```bash
mysqladmin ping -h localhost -u root -ppassword
```

**T=10s: MySQL healthy** ✓

---

**T=0s: Redis starts (parallel with MySQL)**
```bash
[redis] Ready to accept connections
```

**Health check:**
```bash
redis-cli ping  # Returns PONG
```

**T=2s: Redis healthy** ✓

---

**T=0s: Elasticsearch starts (parallel)**
```bash
[es] Starting Elasticsearch 7.17.0
[es] Cluster health: yellow → green
```

**Health check:**
```bash
curl -f http://localhost:9200/_cluster/health
```

**T=30s: Elasticsearch healthy** ✓

---

**T=30s: Web service starts (waits for all dependencies)**

**Command executed:**
```bash
bundle exec rails db:create && \
bundle exec rails db:migrate && \
bundle exec rails runner 'Message.__elasticsearch__.create_index! force: true rescue nil' && \
bundle exec puma -b tcp://0.0.0.0:3000
```

**Step-by-step:**

**1. Database Creation:**
```ruby
rails db:create
# Connects to mysql:3306
# CREATE DATABASE chat_system_development;
# CREATE DATABASE chat_system_test;
```

**Output:**
```
Created database 'chat_system_development'
Created database 'chat_system_test'
```

**2. Migrations:**
```ruby
rails db:migrate
# Runs all migrations in db/migrate/
```

**Output:**
```
== 20251028170739 CreateChatApplications: migrating ==
-- create_table(:chat_applications)
   -> 0.0234s
== 20251028170748 CreateChats: migrating ==
-- create_table(:chats)
   -> 0.0189s
...
```

**Tables created:**
- chat_applications
- chats
- messages
- ar_internal_metadata
- schema_migrations

**3. Elasticsearch Index:**
```ruby
Message.__elasticsearch__.create_index! force: true
```

**What happens:**
```
DELETE /messages  # If exists
PUT /messages
{
  "mappings": {
    "properties": {
      "body": { "type": "text", ... },
      "body.keyword": { "type": "keyword" },
      "chat_id": { "type": "integer" }
    }
  }
}
```

**4. Puma Starts:**
```ruby
Puma starting in single mode...
* Listening on tcp://0.0.0.0:3000
Use Ctrl-C to stop
```

**T=35s: Web service ready** ✓

---

**T=35s: Sidekiq starts (parallel with web after dependencies)**

**Command:**
```bash
bundle exec sidekiq -C config/sidekiq.yml -c 5
```

**Output:**
```
         s
    ss
sss  sss         ss
s  sss s   ssss sss   ____  _     _      _    _
s   s  ssss ssss     / ___|(_) __| | ___| | _(_) __ _
   s     s         \\___ \\| |/ _` |/ _ \\ |/ / |/ _` |
  s         s       ___) | | (_| |  __/   <| | (_| |
   sssss  ssss     |____/|_|\\__,_|\\___|_|\\_\\_|\\__, |
                                                |_|

Sidekiq 7.x starting
Queues: [default, mailers]
```

**T=37s: Sidekiq ready** ✓

---

**Stage 3: System Ready**

**T=40s: All services running**

**Verify:**
```bash
docker-compose ps
```

**Output:**
```
NAME                    STATUS              PORTS
chat_system_mysql       Up (healthy)        3306->3306
chat_system_redis       Up (healthy)        6379->6379
chat_system_elasticsearch Up (healthy)      9200->9200
chat_system_web         Up                  3000->3000
chat_system_sidekiq     Up
```

**Access:**
- Application: http://localhost:3000
- MySQL: localhost:3306
- Redis: localhost:6379
- Elasticsearch: http://localhost:9200

---

**Log Output (All Services):**

**Terminal shows interleaved logs:**
```
mysql | [Note] Ready for connections
redis | Ready to accept connections
elasticsearch | Cluster health status changed to [GREEN]
web | Puma starting in single mode
web | Listening on tcp://0.0.0.0:3000
sidekiq | Booting Sidekiq with redis options {:url=>...}
```

---

**Testing the System:**

**1. Health check:**
```bash
curl http://localhost:3000/api/v1/chat_applications
# Returns: []
```

**2. Create application:**
```bash
curl -X POST http://localhost:3000/api/v1/chat_applications \
  -H "Content-Type: application/json" \
  -d '{"chat_application": {"name": "Test App"}}'

# Returns: {"name":"Test App","token":"abc123...","chats_count":0}
```

**3. Check Sidekiq is processing:**
```bash
docker-compose logs sidekiq -f
# Should show: "Done: 0, Fail: 0, Busy: 0"
```

---

**Stopping the System:**

**Graceful shutdown:**
```bash
docker-compose down
```

**What happens:**
1. Sends SIGTERM to all containers
2. Sidekiq finishes current jobs (up to 25 seconds)
3. Puma finishes current requests (up to 30 seconds)
4. MySQL flushes to disk
5. Containers stop
6. **Volumes preserved** (data persists)

**Nuclear option (loses data):**
```bash
docker-compose down -v
# Deletes volumes: mysql_data, redis_data, elasticsearch_data
```

---

**Common Issues:**

**Issue 1: Port already in use**
```
Error: bind: address already in use
```

**Solution:**
```bash
# Change ports in docker-compose.yml
ports:
  - "3001:3000"  # Use 3001 instead of 3000
```

**Issue 2: Out of memory**
```
elasticsearch | OutOfMemoryError
```

**Solution:**
```bash
# Increase Docker memory limit
# Docker Desktop → Settings → Resources → Memory: 8GB
```

**Issue 3: Database not ready**
```
web | PG::ConnectionBad: could not connect to server
```

**Solution:**
- Health checks should prevent this
- If happens, restart: `docker-compose restart web`

**Result:** Fully automated, reproducible development environment in ~40 seconds."

---

## API Design

### Q15: Why did you design the API with nested resources instead of flat endpoints?

**Answer:**
"This was a deliberate choice based on REST principles and the hierarchical nature of the data:

**Our Design (Nested):**
```
POST   /api/v1/chat_applications/:token/chats
GET    /api/v1/chat_applications/:token/chats/:number
POST   /api/v1/chat_applications/:token/chats/:number/messages
GET    /api/v1/chat_applications/:token/chats/:number/messages/:number
GET    /api/v1/chat_applications/:token/chats/:number/messages/search
```

**Alternative (Flat):**
```
POST   /api/v1/chats
GET    /api/v1/chats/:id
POST   /api/v1/messages
GET    /api/v1/messages/:id
GET    /api/v1/messages/search
```

**Why Nested is Better Here:**

**1. Clear Resource Relationships**

**Nested makes hierarchy explicit:**
```
Application
  └─ Chat
      └─ Message
```

**URL tells you:**
- This message belongs to chat #5
- That chat belongs to app with token abc123
- Clear scope and ownership

**Flat is ambiguous:**
- `/messages/42` - which chat? which app?
- Need to query DB to find relationships
- Client must track relationships separately

---

**2. Authorization is Simpler**

**Nested:**
```ruby
def set_chat_application
  @chat_application = ChatApplication.find_by!(token: params[:chat_application_token])
end

def set_chat
  # Automatically scoped to the application
  @chat = @chat_application.chats.find_by!(number: params[:chat_number])
end

def set_message
  # Automatically scoped to the chat (and transitively to app)
  @message = @chat.messages.find_by!(number: params[:number])
end
```

**Security benefit:**
```
GET /api/v1/chat_applications/app1/chats/5/messages/10
```
- Verifies: app1 exists
- Verifies: chat 5 belongs to app1
- Verifies: message 10 belongs to chat 5

**Attacker can't:**
- Access chat 5 if it belongs to app2
- Access message 10 if it belongs to chat 6

**Flat version (less secure):**
```ruby
# This is WRONG - allows cross-app access
def show
  @message = Message.find(params[:id])
end

# Have to manually check ownership
def show
  @message = Message.find(params[:id])
  @chat = @message.chat
  @app = @chat.chat_application
  authorize @app  # Easy to forget!
end
```

---

**3. API Discovery & Documentation**

**Nested is self-documenting:**
```
# Developer sees URL and understands:
POST /api/v1/chat_applications/:token/chats/:number/messages

# "To create a message, I need:"
# 1. An application token
# 2. A chat number within that application
# 3. Then I can post a message
```

**Flat requires documentation:**
```
POST /api/v1/messages
Body: { chat_id: 5, body: "Hello" }

# "Wait, what's a chat_id? How do I get one?"
# "Can I use any chat_id?"
# Documentation needed to explain relationships
```

---

**4. Query Scoping**

**Nested enables natural scoping:**
```ruby
# List all chats in an application
GET /api/v1/chat_applications/abc123/chats

# List all messages in a chat
GET /api/v1/chat_applications/abc123/chats/5/messages

# Search messages in a specific chat
GET /api/v1/chat_applications/abc123/chats/5/messages/search?q=hello
```

**Flat requires query parameters:**
```ruby
# Awkward and error-prone
GET /api/v1/chats?application_token=abc123
GET /api/v1/messages?chat_id=5
GET /api/v1/messages/search?chat_id=5&q=hello
```

---

**5. Cache Key Simplicity**

**Nested:**
```ruby
# Cache key naturally scoped
cache_key = "app:#{token}:chats:#{number}:messages"
```

**Flat:**
```ruby
# Need to lookup relationships for cache key
message = Message.find(id)
cache_key = "app:#{message.chat.chat_application.token}:..."
# Extra DB queries!
```

---

**When Flat is Better:**

**Use cases for flat design:**

1. **Independent resources:**
```
GET /api/v1/users
GET /api/v1/products
```
No hierarchy, no ownership

2. **Global search:**
```
GET /api/v1/search?q=hello&type=message
```
Searches across all apps/chats

3. **Cross-cutting concerns:**
```
GET /api/v1/notifications
GET /api/v1/audit_logs
```
Don't belong to specific parent

---

**Trade-offs of Nested Design:**

**Cons:**

1. **Longer URLs:**
   - `/api/v1/chat_applications/abc123/chats/5/messages/10`
   - vs `/api/v1/messages/10`

2. **More route parameters:**
   - Need to extract :token, :chat_number, :number
   - More params to validate

3. **Rigid structure:**
   - Can't easily access message directly without knowing chat
   - Would need separate endpoint: `GET /api/v1/messages/:id` (acceptable to add if needed)

**Pros outweigh cons for this use case:**
- Hierarchical data model
- Strong ownership relationships
- Security-critical (multi-tenant)
- Clear resource scoping

---

**Real-world Examples:**

**Nested (similar to ours):**
- GitHub: `/repos/:owner/:repo/issues/:number`
- Stripe: `/customers/:id/subscriptions/:sub_id`
- AWS: `/accounts/:id/instances/:instance_id`

**Flat:**
- Twitter: `/tweets/:id` (tweets are global, not owned)
- Dropbox: `/files/:id` (files accessed by ID, not path)

**Result:** Our nested design accurately reflects the domain model, improves security, and makes the API intuitive for developers."

---

### Q16: How do you handle API versioning?

**Answer:**
"API versioning is critical for backwards compatibility. Here's our strategy:

**Current Approach: URL Versioning**

**Structure:**
```
/api/v1/chat_applications
/api/v1/chat_applications/:token/chats
```

**Implementation:**
```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :chat_applications, param: :token do
      resources :chats, param: :number do
        resources :messages, param: :number
      end
    end
  end
end
```

---

**Why URL Versioning?**

**Alternatives considered:**

**1. Header Versioning:**
```http
GET /api/chat_applications
Accept: application/vnd.chatapp.v1+json
```

**Pros:** Clean URLs
**Cons:** Hard to test (can't just curl), caching issues

**2. Query Parameter:**
```http
GET /api/chat_applications?version=1
```

**Pros:** Easy to implement
**Cons:** Ugly, easy to forget, caching issues

**3. URL Versioning (chosen):**
```http
GET /api/v1/chat_applications
```

**Pros:**
- Explicit and visible
- Easy to test (curl, browser)
- Easy to cache (different URLs)
- Clear deprecation path

**Cons:**
- URL duplication (v1, v2, v3)

---

**Version Strategy:**

**When to bump version:**

**Major version (v1 → v2):**
- Breaking changes
- Changed response format
- Removed fields
- Changed authentication

**Example:**
```ruby
# v1: Returns numbers
GET /api/v1/chats
{"number": 5, "messages_count": 10}

# v2: Returns IDs instead (BREAKING)
GET /api/v2/chats
{"id": "chat_abc123", "message_count": 10}
```

**Minor version (keep v1):**
- Added fields (backwards compatible)
- New endpoints
- Optional parameters

**Example:**
```ruby
# v1: Add new field (backwards compatible)
GET /api/v1/chats
{"number": 5, "messages_count": 10, "created_at": "2025-01-15"}
```

---

**Version Support Policy:**

**Production guideline:**
```
- v1: Current version (100% traffic)
- v2: Release alongside v1 (gradual migration)
- v1 deprecated: 6 months notice
- v1 sunset: 12 months after v2 release
```

**Implementation:**
```ruby
# app/controllers/api/v1/base_controller.rb
class Api::V1::BaseController < ApplicationController
  # Log deprecation warnings
  after_action :warn_if_deprecated

  def warn_if_deprecated
    if deprecation_date_passed?
      response.headers['Warning'] = '299 - "API v1 is deprecated. Migrate to v2 by 2026-01-15"'
      Rails.logger.warn("V1 API used: #{request.path}")
    end
  end
end
```

---

**How to Add v2:**

**Step 1: Duplicate controller namespace**
```ruby
# app/controllers/api/v2/
# - chat_applications_controller.rb (new format)
# - chats_controller.rb
# - messages_controller.rb
```

**Step 2: Shared logic in concerns**
```ruby
# app/controllers/concerns/chat_operations.rb
module ChatOperations
  def create_chat_logic(application)
    number = SequentialNumberService.next_chat_number(application.id)
    CreateChatJob.perform_later(application.id, number)
    number
  end
end

# app/controllers/api/v1/chats_controller.rb
include ChatOperations

def create
  number = create_chat_logic(@chat_application)
  render json: { number: number }  # v1 format
end

# app/controllers/api/v2/chats_controller.rb
include ChatOperations

def create
  number = create_chat_logic(@chat_application)
  render json: {
    id: "chat_#{@chat_application.token}_#{number}",
    number: number
  }  # v2 format with extra fields
end
```

**Step 3: Route both versions**
```ruby
namespace :api do
  namespace :v1 do
    # ... v1 routes
  end

  namespace :v2 do
    # ... v2 routes (potentially different structure)
  end
end
```

---

**Testing Multiple Versions:**

```ruby
# spec/requests/api/v1/chats_spec.rb
describe 'API V1' do
  it 'returns number field' do
    post '/api/v1/chat_applications/token123/chats'
    expect(json_response).to have_key('number')
    expect(json_response).not_to have_key('id')
  end
end

# spec/requests/api/v2/chats_spec.rb
describe 'API V2' do
  it 'returns both id and number fields' do
    post '/api/v2/chat_applications/token123/chats'
    expect(json_response).to have_key('id')
    expect(json_response).to have_key('number')
  end
end
```

---

**Client Migration Path:**

**1. Documentation:**
```markdown
# Migration Guide: v1 → v2

## Breaking Changes
- Chat identifier changed from `number` to `id`
- Message count field renamed: `messages_count` → `message_count`

## Migration Steps
1. Update all endpoints: /api/v1/ → /api/v2/
2. Update response parsing:
   - Old: chat.number
   - New: chat.id
3. Test in staging
4. Deploy to production
```

**2. SDK Support:**
```ruby
# Ruby SDK
ChatApp::Client.new(api_version: :v1)  # Default
ChatApp::Client.new(api_version: :v2)  # Opt-in to v2
```

**3. Analytics:**
```ruby
# Track version usage
class Api::V1::BaseController
  after_action :track_version_usage

  def track_version_usage
    VersionUsageMetrics.increment('api.v1.requests')
  end
end

# Dashboard shows:
# v1: 80% of traffic (sunset when < 5%)
# v2: 20% of traffic
```

---

**Alternatives for Non-Breaking Changes:**

**Instead of bumping version:**

**1. Expand response (backwards compatible):**
```ruby
# Old clients ignore new fields
{
  "number": 5,
  "messages_count": 10,
  "created_at": "2025-01-15"  # New field, old clients ignore
}
```

**2. Optional query parameters:**
```ruby
# New feature, opt-in
GET /api/v1/chats?include=participants
```

**3. Request header feature flags:**
```ruby
# X-Features: include-metadata
if request.headers['X-Features']&.include?('include-metadata')
  render json: chat, include: :metadata
end
```

**Result:** Clear versioning strategy that balances stability with evolution."

---

## Background Jobs & Queue System

### Q17: Explain your background job architecture and why you chose Sidekiq.

**Answer:**
"Let me walk through the complete job architecture and the choice of Sidekiq:

**Job Architecture:**

**Current Jobs:**
```
CreateChatJob
├── Purpose: Persist chat to MySQL
├── Queue: default
├── Priority: high (user-facing)
└── Retry: 25 times

CreateMessageJob
├── Purpose: Persist message + ES indexing
├── Queue: default
├── Priority: high (user-facing)
└── Retry: 25 times

UpdateChatApplicationCountJob
├── Purpose: Recalculate chats_count
├── Queue: default
├── Priority: low
└── Retry: 3 times

UpdateChatMessageCountJob
├── Purpose: Recalculate messages_count
├── Queue: default
├── Priority: low
└── Retry: 3 times

SyncCountersJob
├── Purpose: Periodic counter reconciliation
├── Queue: maintenance
├── Priority: low
└── Scheduled: every 30 minutes
```

---

**Job Processing Flow:**

**1. Job Enqueuing:**
```ruby
# In controller (fast, non-blocking)
CreateChatJob.perform_later(app_id, number)

# What happens:
# 1. Serialize job: {class: CreateChatJob, args: [123, 42]}
# 2. Push to Redis: LPUSH queue:default "{job_json}"
# 3. Return immediately (< 1ms)
```

**2. Job Processing:**
```ruby
# Sidekiq worker (separate process)
loop do
  job = Redis.new.brpop('queue:default', timeout: 2)
  execute_job(job)
end
```

**3. Job Execution:**
```ruby
class CreateChatJob
  def perform(app_id, number)
    chat = ChatApplication.find(app_id).chats.create!(number: number)
    ChatApplication.increment_counter(:chats_count, app_id)
  rescue => e
    # Sidekiq automatically retries with exponential backoff
    raise e
  end
end
```

---

**Why Sidekiq over Alternatives?**

**Comparison:**

| Feature | Sidekiq | Solid Queue | Delayed Job | Resque |
|---------|---------|-------------|-------------|--------|
| Backend | Redis | PostgreSQL | MySQL/PG | Redis |
| Performance | 5000 jobs/sec | 500 jobs/sec | 100 jobs/sec | 1000 jobs/sec |
| Memory | Low | Very Low | High | Medium |
| Reliability | High | Very High | Medium | High |
| Concurrency | Threads | Processes | Threads | Processes |
| Scheduled Jobs | ✓ | ✓ | ✓ | ✗ |
| Web UI | ✓ (excellent) | ✓ (basic) | ✗ | ✓ (basic) |
| Priority Queues | ✓ | ✓ | ✓ | ✓ |
| Maturity | 12+ years | New (2024) | 10+ years | 12+ years |

---

**Why Sidekiq Won:**

**1. Performance:**
```ruby
# Sidekiq: Thread-based (low overhead)
# 1 Sidekiq process = 25 threads = handles 25 jobs concurrently
# Memory: ~100MB per process

# vs Resque: Process-based (high overhead)
# 25 concurrent jobs = 25 processes
# Memory: ~100MB × 25 = 2.5GB
```

**Benchmark:**
- Sidekiq: 5000 jobs/sec on single process
- Resque: 1000 jobs/sec on single process
- Delayed Job: 100 jobs/sec

**Our load:** ~1000 jobs/sec peak → Sidekiq handles easily

---

**2. Redis Alignment:**
```
Our Architecture:
Redis (already running)
  ├── Sequential numbers (SequentialNumberService)
  ├── Cache (message cache)
  └── Job queue (Sidekiq)

Why add PostgreSQL job queue (Solid Queue)?
  - Extra dependency
  - Extra database load
  - Doesn't leverage existing Redis
```

**Decision:** Use infrastructure we already have

---

**3. Excellent Monitoring:**

**Sidekiq Web UI:**
```ruby
# config/routes.rb
require 'sidekiq/web'

mount Sidekiq::Web => '/sidekiq'
```

**Dashboard shows:**
- Real-time job processing rate
- Queue depths (alerts if > 10k)
- Failed jobs with full stack traces
- Retry schedules
- Memory usage per worker
- Latency p50/p95/p99

**Example:**
```
Processed: 1,234,567 jobs
Failed: 23 jobs (0.002% failure rate)
Busy: 12 threads
Enqueued: 156 jobs
Scheduled: 2,345 jobs
Retries: 45 jobs
Dead: 5 jobs (exceeded retry limit)
```

---

**4. Retry Logic:**

**Automatic exponential backoff:**
```ruby
class CreateChatJob
  # Retry 25 times over ~21 days
  # Delay: 15s, 30s, 1m, 2m, 4m, 8m, ... 24h, 24h, 24h
  sidekiq_options retry: 25
end
```

**Why this matters:**
```
Scenario: MySQL is down for 5 minutes

Without retry:
  - 5000 jobs fail permanently
  - Data loss

With Sidekiq retry:
  - Jobs retry after 15s, 30s, 1m, 2m, 4m
  - MySQL back up after 5m
  - All jobs succeed on retry
  - Zero data loss
```

---

**5. Dead Job Queue:**

**Jobs that fail after 25 retries:**
```ruby
# Sidekiq saves them in 'dead' queue
# Can replay manually:
Sidekiq::DeadSet.new.each do |job|
  job.retry  # Try again
end
```

**Contrast with fire-and-forget systems:**
- No way to recover failed jobs
- Data loss is permanent

---

**Why Not Solid Queue?**

**Solid Queue** (new in Rails 8):

**Pros:**
- No Redis dependency
- ACID guarantees (PostgreSQL)
- Better for financial transactions

**Cons:**
- Much slower (500 vs 5000 jobs/sec)
- Adds DB load (writes to job table)
- Less mature (released 2024)
- We already have Redis

**When to use Solid Queue:**
- No Redis infrastructure
- DB-heavy app (PostgreSQL for everything)
- Absolute consistency required (bank transactions)

**Our case:**
- Already have Redis
- High throughput needed
- Eventual consistency acceptable

**Result:** Sidekiq is the right choice

---

**Configuration:**

**docker-compose.yml:**
```yaml
sidekiq:
  build: .
  command: ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml", "-c", "5"]
  environment:
    REDIS_URL: redis://redis:6379/0
```

**config/sidekiq.yml:**
```yaml
:concurrency: 5
:queues:
  - [default, 2]      # Process 2 jobs from 'default'
  - [maintenance, 1]  # Process 1 job from 'maintenance'
```

**Tuning:**
```ruby
# For production (more workers)
:concurrency: 25

# For development (fewer resources)
:concurrency: 5
```

---

**Monitoring & Alerts:**

**Metrics to track:**
```ruby
# Queue depth (alert if > 10k)
Sidekiq::Queue.new('default').size

# Processing rate (alert if < 100/sec under load)
Sidekiq::Stats.new.processed / Time.now.to_i

# Failure rate (alert if > 1%)
stats = Sidekiq::Stats.new
failure_rate = stats.failed / stats.processed.to_f

# Latency (alert if > 30 seconds)
Sidekiq::Queue.new('default').latency
```

**Production setup:**
```ruby
# Prometheus exporter
gem 'sidekiq-prometheus-exporter'

# Grafana dashboard shows:
# - Jobs processed/sec (gauge)
# - Queue depth (gauge)
# - Job duration p99 (histogram)
# - Failure rate (counter)
```

---

**Scaling Strategy:**

**Current:** 1 Sidekiq process, 5 threads

**10x scale:** 5 processes, 10 threads each = 50 concurrent jobs

**100x scale:** 50 processes across 10 servers

**Bottleneck:** Redis throughput (100k ops/sec)

**Solution:** Redis Cluster (1M ops/sec)

**Result:** Mature, battle-tested, high-performance job system that matches our architecture perfectly."

---

## Redis Implementation

### Q18: Explain how you use Redis and why it's critical to your architecture.

**Answer:**
"Redis is absolutely central to this system's ability to handle concurrency. Let me break down each use case:

**Three Critical Use Cases:**

```
Redis
├── Sequential Number Generation (CRITICAL)
│   ├── chat_app:{id}:chat_counter
│   └── chat:{id}:message_counter
│
├── Job Queue (HIGH PRIORITY)
│   ├── queue:default
│   └── queue:maintenance
│
└── Caching (OPTIONAL - not yet implemented)
    ├── app:{token}:data
    └── chat:{id}:messages
```

---

**Use Case 1: Sequential Number Generation (Most Critical)**

**The Problem:**
```
Server 1: Gets next chat number → reads 5 → increments → writes 6
Server 2: Gets next chat number → reads 5 → increments → writes 6
Result: DUPLICATE! Both chats have number 6 ❌
```

**Why Database Auto-Increment Doesn't Work:**
```sql
-- MySQL auto-increment
INSERT INTO chats (chat_application_id) VALUES (123);
-- Returns: id = 456

-- Problem: We need number per application, not global ID
-- Application A: chats should be numbered 1, 2, 3...
-- Application B: chats should be numbered 1, 2, 3... (overlapping IDs ok)
```

**Redis INCR Solution:**
```ruby
def self.next_chat_number(application_id)
  redis = Redis.new
  key = "chat_app:#{application_id}:chat_counter"

  # ATOMIC operation - guaranteed unique
  redis.incr(key)
end
```

**Why This Works:**

**1. Atomicity:**
```
Redis is single-threaded. Commands execute serially:

T0: Server 1 → INCR chat_app:123:chat_counter → returns 5
T1: Server 2 → INCR chat_app:123:chat_counter → returns 6

Impossible to get same value even if requests are simultaneous
```

**2. Speed:**
```ruby
Benchmark.measure { redis.incr('key') }
# => 0.0003 seconds (0.3ms)

# vs MySQL approach:
Benchmark.measure do
  ActiveRecord::Base.connection.execute("UPDATE counters SET value = value + 1 WHERE id = 1")
  ActiveRecord::Base.connection.execute("SELECT value FROM counters WHERE id = 1")
end
# => 0.015 seconds (15ms)

# Redis is 50x faster
```

**3. Scalability:**
- Single Redis handles 100k INCR/sec
- No database locking needed
- No transaction overhead
- Works across unlimited web servers

**4. Persistence:**
```ruby
# Redis RDB (default)
# Snapshots every 60 seconds
# Acceptable: If Redis crashes, worst case is numbering jumps

# Example:
# Last snapshot: counter = 1000
# Redis crashes after counter = 1050
# On restart: counter = 1000
# Next chat: 1001 (1001-1050 are skipped)
# Acceptable: Numbers are unique, just not contiguous
```

---

**Use Case 2: Job Queue**

**Why Redis for Jobs?**

**In-Memory Speed:**
```ruby
# Enqueue job (push to Redis list)
redis.lpush('queue:default', job_data)  # 0.3ms

# vs Database queue:
JobQueue.create!(class: 'CreateChatJob', args: ...)  # 15ms

# Redis is 50x faster for enqueueing
```

**Atomic Pop:**
```ruby
# Worker polls queue
job = redis.brpop('queue:default', timeout: 2)

# BRPOP is atomic - only ONE worker gets each job
# Even if 100 workers are waiting, no duplicates
```

**Persistence:**
```ruby
# Redis AOF (Append-Only File)
# Logs every write command
# On crash: Replay log, zero job loss

# Trade-off: 2x disk I/O
# Acceptable: Job reliability > performance
```

---

**Use Case 3: Caching (Future Enhancement)**

**Current State:** Not implemented yet

**Planned:**
```ruby
# Cache last 100 messages per chat
class MessagesController
  def index
    cached = REDIS.lrange("chat:#{@chat.id}:messages", 0, 99)

    if cached.present?
      render json: cached.map { |m| JSON.parse(m) }
    else
      messages = @chat.messages.limit(100)
      messages.each { |m| REDIS.lpush("chat:#{@chat.id}:messages", m.to_json) }
      REDIS.ltrim("chat:#{@chat.id}:messages", 0, 99)
      render json: messages
    end
  end
end
```

**Benefit:**
- 90% of reads hit cache (Redis: 0.5ms)
- 10% of reads hit MySQL (MySQL: 20ms)
- Average latency: 0.5 * 0.9 + 20 * 0.1 = 2.45ms
- 8x faster than always hitting MySQL

---

**Redis Configuration:**

**docker-compose.yml:**
```yaml
redis:
  image: redis:7-alpine
  ports:
    - "6379:6379"
  volumes:
    - redis_data:/data
  command: redis-server --appendonly yes
```

**What `--appendonly yes` does:**
```
Every write command logged to disk:
INCR chat_app:123:chat_counter
LPUSH queue:default {...}
INCR chat:456:message_counter

On crash and restart:
Replay all commands → full recovery
```

**Trade-off:**
- Performance: -20% (disk writes)
- Reliability: +100% (zero data loss)
- Worth it for production

---

**Failure Scenarios:**

**Scenario 1: Redis Temporarily Unavailable**

**Current behavior:**
```ruby
redis.incr('key')
# => Redis::CannotConnectError

# Request fails with 500 error
```

**Improvement (would add):**
```ruby
def self.next_chat_number(application_id)
  redis = Redis.new
  redis.incr("chat_app:#{application_id}:chat_counter")
rescue Redis::CannotConnectError => e
  # Fallback: Use database-based counter
  app = ChatApplication.find(application_id)
  app.with_lock do
    app.increment!(:last_chat_number)
    app.last_chat_number
  end
end
```

---

**Scenario 2: Redis Data Loss**

**Problem:** Redis crashes, loses all data

**Recovery:**
```ruby
# Rebuild counters from MySQL
ChatApplication.find_each do |app|
  max_chat = app.chats.maximum(:number) || 0
  Redis.new.set("chat_app:#{app.id}:chat_counter", max_chat)
end

Chat.find_each do |chat|
  max_message = chat.messages.maximum(:number) || 0
  Redis.new.set("chat:#{chat.id}:message_counter", max_message)
end
```

**Automation:**
```ruby
# On app startup
if Redis.new.keys('chat_app:*').empty?
  RebuildRedisCountersJob.perform_now
end
```

---

**Scenario 3: Redis Out of Memory**

**Problem:** Redis hits memory limit, can't accept new writes

**Solution 1: Eviction Policy**
```ruby
# redis.conf
maxmemory 4gb
maxmemory-policy volatile-lru

# Only evict keys with expiration set
# Counters (no expiration) → never evicted
# Cache (with expiration) → evicted when memory full
```

**Solution 2: Monitoring**
```ruby
# Check memory usage
info = Redis.new.info
used_memory_mb = info['used_memory'].to_i / 1024 / 1024

if used_memory_mb > 3500  # Alert at 87% of 4GB
  alert('Redis memory high')
end
```

---

**Production Redis Setup:**

**High Availability:**
```
Redis Sentinel (3 nodes)
  ├── Master (writes)
  ├── Replica 1 (reads + failover)
  └── Replica 2 (reads + failover)

If master fails:
1. Sentinels detect failure (< 30 seconds)
2. Elect new master (Replica 1)
3. Update config
4. App reconnects automatically
5. Downtime: < 60 seconds
```

**Scaling:**
```
Redis Cluster (6 nodes)
  ├── Shard 1 (apps 0-16383)
  ├── Shard 2 (apps 16384-32767)
  └── Shard 3 (apps 32768-49151)

Throughput: 100k → 600k ops/sec
```

---

**Monitoring:**

**Key Metrics:**
```ruby
# Operations per second
info = Redis.new.info
ops_per_sec = info['instantaneous_ops_per_sec']
# Alert if > 80k (80% of capacity)

# Memory usage
used_memory_percent = info['used_memory'] / info['maxmemory'].to_f
# Alert if > 85%

# Evicted keys (should be 0 for counters)
evicted_keys = info['evicted_keys']
# Alert if > 0

# Connected clients
connected_clients = info['connected_clients']
# Alert if > 1000 (potential leak)
```

**Health Check:**
```ruby
# Liveness probe
Redis.new.ping  # Returns 'PONG' if healthy

# Latency check
start = Time.now
Redis.new.incr('health:check')
latency = Time.now - start
# Alert if latency > 10ms
```

---

**Why Redis is Critical:**

**Without Redis:**
- No atomic number generation → duplicates
- Database locking → 10x slower, doesn't scale
- Job queue in database → 50x slower

**With Redis:**
- Atomic operations → no duplicates
- 100k ops/sec → handles high traffic
- Minimal latency → fast user experience

**Bottom line:** Redis is the foundation that makes the entire async, multi-server architecture possible. Without it, the system fundamentally cannot work at scale."

---

## Trade-offs & Improvements

### Q19: What are the biggest trade-offs in your current design?

**Answer:**
"Every architecture makes trade-offs. Let me outline the key ones:

**Trade-off 1: Eventual Consistency vs Strong Consistency**

**What we chose:**
```ruby
# Client creates message
POST /messages → returns { number: 42 }

# Message not in DB yet (async job running)
# Appears in MySQL ~100ms later
# Appears in Elasticsearch ~1 second later
```

**Trade-off:**
- ✓ Pro: 10x higher throughput (async writes)
- ✓ Pro: Handles traffic spikes (queue absorbs load)
- ✗ Con: Client can't immediately read what they wrote

**When this matters:**
```ruby
# User posts message
POST /messages → { number: 42 }

# User immediately refreshes
GET /messages → [] (message not there yet!)

# 1 second later
GET /messages → [{ number: 42, body: "Hello" }]
```

**Mitigation:**
```javascript
// Frontend: Optimistic UI
function postMessage(body) {
  const tempMessage = { number: '...', body, status: 'sending' }
  addToUI(tempMessage)  // Show immediately

  api.post('/messages', { body })
    .then(response => {
      updateUI(tempMessage, { ...response, status: 'sent' })
    })
}
```

**Alternative (strong consistency):**
```ruby
# Synchronous write
def create
  message = @chat.messages.create!(message_params)
  render json: message
end

# ✓ Immediately available in DB
# ✗ 50ms response time (vs 5ms async)
# ✗ Can't handle 5k req/sec (maxes at 500 req/sec)
```

**Verdict:** Eventual consistency is correct choice for chat system (Twitter, Slack do the same)

---

**Trade-off 2: Redis as Single Point of Failure**

**What we chose:**
```ruby
# All number generation depends on Redis
redis.incr('chat_app:123:chat_counter')

# If Redis is down:
# - Can't create new chats/messages
# - Entire creation flow blocked
```

**Trade-off:**
- ✓ Pro: Atomic operations (no race conditions)
- ✓ Pro: Extremely fast (0.3ms vs 15ms for DB)
- ✗ Con: Single point of failure
- ✗ Con: Must maintain Redis high availability

**Mitigation strategies:**

**1. High Availability (production):**
```
Redis Sentinel
├── Master (primary)
├── Replica 1 (hot standby)
└── Replica 2 (hot standby)

Automatic failover: < 30 seconds downtime
```

**2. Fallback to Database (not implemented yet):**
```ruby
def next_chat_number(app_id)
  redis.incr("chat_app:#{app_id}:chat_counter")
rescue Redis::CannotConnectError
  # Fallback: slower but reliable
  ChatApplication.find(app_id).with_lock do
    app.increment!(:last_chat_number)
  end
end
```

**3. Circuit Breaker (not implemented):**
```ruby
if Redis down for > 5 minutes:
  Enable database fallback mode
  Alert ops team
  Continue serving requests (degraded performance)
```

**Alternative (no Redis):**
```ruby
# Database-only approach
def next_chat_number(app_id)
  ChatApplication.find(app_id).with_lock do
    app.increment!(:last_chat_number)
  end
end

# ✓ No Redis dependency
# ✗ 50x slower (15ms vs 0.3ms)
# ✗ Database becomes bottleneck
# ✗ Doesn't scale horizontally
```

**Verdict:** Redis SPOF is acceptable with HA setup

---

**Trade-off 3: Database Denormalization (Counter Columns)**

**What we chose:**
```sql
-- Denormalized counters
chat_applications.chats_count
chats.messages_count

-- Updated asynchronously
-- May be stale (up to 30 minutes)
```

**Trade-off:**
- ✓ Pro: O(1) reads (single column lookup)
- ✓ Pro: No expensive COUNT(*) queries
- ✗ Con: Eventually consistent (30 min lag)
- ✗ Con: Can drift if jobs fail

**Example of staleness:**
```ruby
# At T=0:
app.chats_count = 100
app.chats.count = 100 (in sync)

# T=1: Create 10 chats (jobs queued)
app.chats_count = 100 (not updated yet)
app.chats.count = 110 (in DB)

# T=5: Jobs complete
app.chats_count = 110 (now in sync)
```

**When this causes problems:**
```ruby
# Admin dashboard showing statistics
"Application has #{app.chats_count} chats"
# Might be off by a few during high traffic
```

**Mitigation:**
```ruby
# For critical use cases, use real count
def accurate_count
  app.chats.count  # Slower but accurate
end

# For dashboards, cached count is fine
def display_count
  app.chats_count  # Faster, slightly stale
end
```

**Alternative (no denormalization):**
```ruby
# Always COUNT(*) in real-time
def chats_count
  chats.count  # Always accurate
end

# ✓ Always accurate
# ✗ O(n) query on large tables
# ✗ Slows down every API call
# ✗ Can't add index (COUNT requires full scan or index scan)
```

**Benchmark:**
```ruby
# 1M chats for an application
Benchmark.measure { app.chats.count }
# => 2.5 seconds

Benchmark.measure { app.chats_count }
# => 0.001 seconds (2500x faster)
```

**Verdict:** Denormalization is correct for read-heavy workload

---

**Trade-off 4: No Built-in Rate Limiting**

**What we chose:**
- No rate limiting in application code
- Rely on infrastructure (Nginx, load balancer)

**Trade-off:**
- ✓ Pro: Simpler application code
- ✓ Pro: Better performance (no rate limit checks)
- ✗ Con: Vulnerable to abuse without infrastructure
- ✗ Con: Can't do application-level rate limits (per application token)

**Why this matters:**
```ruby
# Malicious client
1000.times do
  POST /api/v1/chat_applications/token123/chats
end

# Without rate limiting:
# - Creates 1000 Redis keys
# - Queues 1000 jobs
# - Could exhaust resources
```

**Would add (per-application rate limiting):**
```ruby
class Api::V1::ChatsController
  before_action :check_rate_limit

  def check_rate_limit
    key = "rate_limit:#{@chat_application.token}:chats"
    count = REDIS.incr(key)
    REDIS.expire(key, 60) if count == 1  # Reset every minute

    if count > 100  # Max 100 chats/minute per application
      render json: { error: 'Rate limit exceeded' }, status: 429
      return
    end
  end
end
```

**Alternative (strict rate limiting):**
```ruby
# Rack::Attack at infrastructure level
Rack::Attack.throttle('req/ip', limit: 300, period: 5.minutes) do |req|
  req.ip
end

# ✓ Protects all endpoints
# ✗ Blocks all traffic from IP (even legitimate)
```

**Verdict:** Should add application-level rate limiting for production

---

**Trade-off 5: No Pagination**

**What we chose:**
```ruby
def index
  @messages = @chat.messages.all  # Returns ALL messages
  render json: @messages
end
```

**Trade-off:**
- ✓ Pro: Simpler API
- ✓ Pro: Works for small chats (< 1000 messages)
- ✗ Con: Breaks for large chats (> 10k messages)
- ✗ Con: Slow response time, high memory usage

**Example problem:**
```ruby
# Chat with 100k messages
GET /api/v1/chat_applications/token/chats/1/messages

# Response:
# - Size: 50MB JSON
# - Time: 30 seconds
# - Memory: 500MB on server
# Result: Server OOM crash
```

**Would add:**
```ruby
# Pagination
GET /messages?page=1&per_page=50

def index
  @messages = @chat.messages
                   .order(number: :desc)
                   .page(params[:page])
                   .per(params[:per_page] || 50)

  render json: {
    messages: @messages,
    pagination: {
      current_page: @messages.current_page,
      total_pages: @messages.total_pages,
      total_count: @chat.messages_count  # From counter
    }
  }
end
```

**Alternative (cursor-based):**
```ruby
# Better for real-time data
GET /messages?after=42&limit=50

def index
  @messages = @chat.messages
                   .where('number > ?', params[:after] || 0)
                   .order(number: :asc)
                   .limit(params[:limit] || 50)

  render json: {
    messages: @messages,
    next_cursor: @messages.last&.number
  }
end
```

**Verdict:** Pagination is critical missing feature for production

---

**Summary of Trade-offs:**

| Trade-off | Current Choice | Impact | Priority to Fix |
|-----------|---------------|---------|-----------------|
| Eventual consistency | Async writes | Medium | Low (acceptable) |
| Redis SPOF | Single instance | High | High (add HA) |
| Counter staleness | 30 min lag | Low | Low (acceptable) |
| No rate limiting | No limits | Medium | High (add per-app limits) |
| No pagination | Return all | High | High (add before production) |

**Overall:** System is well-designed for interview/MVP, but needs rate limiting and pagination for production."

---

### Q20: If you had another week, what would you improve?

**Answer:**
"Great question. Here's my prioritized improvement list:

**Priority 1: Production-Critical Features**

**1. Pagination (2 days)**
```ruby
# Add cursor-based pagination
class PaginatedMessagesController < Api::V1::MessagesController
  def index
    @messages = @chat.messages
                     .where('number > ?', params[:after] || 0)
                     .order(number: :asc)
                     .limit(params[:limit] || 50)

    render json: {
      data: @messages.map { |m| message_json(m) },
      meta: {
        next_cursor: @messages.last&.number,
        has_more: @messages.count == params[:limit].to_i
      }
    }
  end
end
```

**Why critical:** Prevents OOM crashes on large chats

---

**2. Rate Limiting (1 day)**
```ruby
# Per-application rate limiting
class RateLimiter
  def self.check!(token, endpoint, limit:, period:)
    key = "rate_limit:#{token}:#{endpoint}"
    count = REDIS.incr(key)
    REDIS.expire(key, period) if count == 1

    raise RateLimitError if count > limit
  end
end

# In controller
before_action -> { RateLimiter.check!(@chat_application.token, 'chats', limit: 100, period: 60) }
```

**Why critical:** Prevents resource exhaustion from abusive clients

---

**3. Redis Fallback (1 day)**
```ruby
# Graceful degradation when Redis is down
module SequentialNumberService
  def self.next_chat_number(app_id)
    redis.incr("chat_app:#{app_id}:chat_counter")
  rescue Redis::CannotConnectError, Redis::TimeoutError
    # Fallback to database
    ChatApplication.find(app_id).with_lock do
      app.increment!(:last_chat_number)
      app.last_chat_number
    end
  ensure
    log_error($!) if $!
  end
end
```

**Why critical:** System continues working during Redis outages

---

**Priority 2: Performance Optimizations**

**4. Message Caching (1 day)**
```ruby
# Cache last 100 messages per chat in Redis
class MessagesController
  def index
    cache_key = "chat:#{@chat.id}:messages:recent"

    cached = REDIS.get(cache_key)
    if cached
      render json: JSON.parse(cached)
    else
      messages = @chat.messages.order(number: :desc).limit(100)
      REDIS.setex(cache_key, 300, messages.to_json)  # Cache 5 minutes
      render json: messages
    end
  end
end
```

**Impact:** 10x faster reads (0.5ms vs 5ms)

---

**5. Database Query Optimization (0.5 days)**
```ruby
# Add compound indices
add_index :messages, [:chat_id, :created_at]  # For time-based queries
add_index :chats, [:chat_application_id, :updated_at]  # For activity queries

# N+1 query fixes
class ChatsController
  def index
    # Before: N+1 (queries messages_count for each chat)
    @chats = @chat_application.chats.all

    # After: Single query
    @chats = @chat_application.chats.includes(:messages)
  end
end
```

**Impact:** 50% faster on list endpoints

---

**6. Elasticsearch Optimization (1 day)**
```ruby
# Add search optimizations
class Message
  settings do
    mapping do
      # Current: Standard analyzer
      # Problem: Slow for large messages

      # Improvement: Add custom analyzer
      indexes :body, type: :text do
        analyzer: 'custom_analyzer'
        indexes :keyword, type: :keyword
        indexes :ngram, type: :text, analyzer: 'ngram_analyzer'  # For autocomplete
      end
    end

    # Define analyzers
    analysis do
      analyzer :custom_analyzer do
        tokenizer :standard
        filter [:lowercase, :stop, :snowball]
      end

      analyzer :ngram_analyzer do
        tokenizer :ngram_tokenizer
        filter [:lowercase]
      end
    end
  end
end
```

**Impact:** 2x faster searches, better relevance

---

**Priority 3: Observability**

**7. Comprehensive Logging (1 day)**
```ruby
# Structured logging with request IDs
class ApplicationController
  around_action :log_request

  def log_request
    request_id = SecureRandom.uuid
    Thread.current[:request_id] = request_id

    Rails.logger.info({
      event: 'request_start',
      request_id: request_id,
      method: request.method,
      path: request.path,
      params: filtered_params,
      user_agent: request.user_agent
    }.to_json)

    start = Time.now
    yield
    duration = Time.now - start

    Rails.logger.info({
      event: 'request_complete',
      request_id: request_id,
      status: response.status,
      duration_ms: (duration * 1000).round(2)
    }.to_json)
  end
end

# In jobs
class CreateChatJob
  def perform(app_id, number)
    Rails.logger.info({
      event: 'job_start',
      job: self.class.name,
      app_id: app_id,
      number: number,
      request_id: Thread.current[:request_id]
    }.to_json)

    # ... job logic

    Rails.logger.info({
      event: 'job_complete',
      job: self.class.name,
      duration_ms: ...
    }.to_json)
  end
end
```

**Impact:** Full request tracing, easier debugging

---

**8. Metrics & Monitoring (1 day)**
```ruby
# Prometheus metrics
gem 'prometheus-client'

class MetricsCollector
  def self.collect
    registry = Prometheus::Client.registry

    # Custom metrics
    chats_created = registry.counter(:chats_created_total, 'Total chats created')
    messages_created = registry.counter(:messages_created_total, 'Total messages created')
    search_duration = registry.histogram(:search_duration_seconds, 'Search duration')

    # System metrics
    redis_ops = registry.gauge(:redis_ops_per_second, 'Redis ops/sec')
    sidekiq_queue_depth = registry.gauge(:sidekiq_queue_depth, 'Jobs in queue')
  end
end

# Grafana dashboard
# - API request rate
# - Response time p50/p95/p99
# - Error rate
# - Redis throughput
# - Job queue depth
```

**Impact:** Proactive problem detection, capacity planning

---

**9. Health Check Endpoint (0.5 days)**
```ruby
# Kubernetes liveness/readiness probes
class HealthController < ApplicationController
  skip_before_action :authenticate  # Public endpoint

  def show
    checks = {
      mysql: check_mysql,
      redis: check_redis,
      elasticsearch: check_elasticsearch,
      sidekiq: check_sidekiq
    }

    status = checks.values.all? ? :ok : :service_unavailable

    render json: {
      status: status,
      checks: checks,
      timestamp: Time.current
    }, status: status
  end

  private

  def check_mysql
    ActiveRecord::Base.connection.execute('SELECT 1')
    true
  rescue => e
    false
  end

  def check_redis
    Redis.new.ping == 'PONG'
  rescue => e
    false
  end
end
```

**Impact:** Automated health monitoring, faster incident response

---

**Priority 4: Developer Experience**

**10. Comprehensive Test Suite (2 days)**
```ruby
# Integration tests for async flow
RSpec.describe 'Chat Creation Flow' do
  it 'creates chat asynchronously' do
    # Act
    post '/api/v1/chat_applications/token123/chats'

    # Assert immediate response
    expect(response.status).to eq(201)
    expect(json['number']).to eq(1)

    # Assert not in DB yet
    expect(Chat.count).to eq(0)

    # Process background job
    perform_enqueued_jobs

    # Assert now in DB
    expect(Chat.count).to eq(1)
    expect(Chat.last.number).to eq(1)
  end

  it 'handles race conditions' do
    # Simulate concurrent requests
    threads = 10.times.map do
      Thread.new do
        post '/api/v1/chat_applications/token123/chats'
      end
    end
    threads.each(&:join)

    # Assert all got unique numbers
    numbers = Chat.pluck(:number)
    expect(numbers.uniq).to eq(numbers)
    expect(numbers.sort).to eq((1..10).to_a)
  end
end

# Load tests
RSpec.describe 'Performance' do
  it 'handles 1000 requests/sec' do
    benchmark = Benchmark.measure do
      1000.times do
        post '/api/v1/chat_applications/token123/messages',
          params: { message: { body: 'Test' } }
      end
    end

    expect(benchmark.real).to be < 5.0  # < 5ms per request
  end
end
```

**Impact:** Confidence in refactoring, regression prevention

---

**Timeline Summary:**

```
Week 1 (Priority 1 - Production Critical):
  Mon-Tue: Pagination
  Wed: Rate limiting
  Thu: Redis fallback
  Fri: Testing and deployment prep

Week 2 (Priority 2 - Performance):
  Mon: Message caching
  Tue: Database optimization
  Wed: Elasticsearch tuning
  Thu-Fri: Load testing and tuning

Week 3 (Priority 3 - Observability):
  Mon: Structured logging
  Tue: Metrics collection
  Wed: Grafana dashboards
  Thu: Health checks
  Fri: Alerting setup

Week 4 (Priority 4 - DX):
  Mon-Tue: Comprehensive test suite
  Wed-Thu: Documentation
  Fri: Knowledge transfer
```

**ROI Analysis:**

| Improvement | Dev Time | Impact | Priority |
|-------------|----------|--------|----------|
| Pagination | 2 days | Prevents crashes | Critical |
| Rate limiting | 1 day | Prevents abuse | Critical |
| Redis fallback | 1 day | Improves reliability | Critical |
| Message caching | 1 day | 10x faster reads | High |
| DB optimization | 0.5 days | 50% faster | High |
| ES tuning | 1 day | 2x faster search | Medium |
| Logging | 1 day | Easier debugging | Medium |
| Metrics | 1 day | Proactive monitoring | Medium |
| Health checks | 0.5 days | Better ops | Low |
| Test suite | 2 days | Code confidence | Low (but recommended) |

**Realistic week plan:**
1. Pagination (critical for production)
2. Rate limiting (critical for security)
3. Redis fallback (critical for reliability)
4. Logging & metrics (essential for operations)
5. Test suite (time permitting)

This would make the system truly production-ready."

---

## Closing

### Q21: What did you learn from building this project?

**Answer:**
"This project reinforced several key architectural principles:

**1. Async-First Design is Powerful**
- Learned: Separating 'fast' operations (number allocation) from 'slow' ones (DB writes) enables massive scalability
- Realized: Users care about response time, not when data hits disk
- Trade-off: Eventual consistency requires careful UX design (optimistic UI)

**2. Redis is More Than a Cache**
- Learned: Redis atomic operations (INCR) are perfect for distributed counters
- Realized: 0.3ms operations enable 100k req/sec with zero race conditions
- Trade-off: Single point of failure requires HA setup

**3. Database Design Matters**
- Learned: Composite unique indices serve dual purpose (uniqueness + performance)
- Realized: Denormalization (counter caching) trades consistency for speed
- Trade-off: Must implement reconciliation to prevent drift

**4. Elasticsearch is Worth the Complexity**
- Learned: Purpose-built search engines outperform SQL by orders of magnitude
- Realized: Inverted indices enable sub-100ms searches on millions of documents
- Trade-off: Additional service to maintain, eventual consistency

**5. Docker Simplifies Everything**
- Learned: Reproducible environments eliminate 'works on my machine'
- Realized: Health checks prevent startup race conditions
- Trade-off: Adds layer of complexity for debugging

**6. Testing Concurrent Systems is Hard**
- Learned: Race conditions only manifest under real load
- Realized: Integration tests with background jobs are critical
- Challenge: Simulating true concurrency in tests is difficult

**What I'd do differently:**
- Start with pagination from day 1
- Add rate limiting earlier
- Implement comprehensive logging sooner
- Write load tests alongside features

**Most surprising insight:**
The hardest part wasn't the code—it was understanding the trade-offs between consistency, performance, and complexity. Every decision has pros and cons."

---

## Final Advice

**How to Use This Guide:**

1. **Don't memorize answers word-for-word**
   - Interviewers want to see your thinking process
   - Use these as frameworks to structure your own answers

2. **Practice explaining with whiteboard**
   - Draw the architecture
   - Diagram the request flow
   - Show the data model

3. **Be honest about what you don't know**
   - "I haven't implemented X, but here's how I'd approach it..."
   - Shows humility and problem-solving ability

4. **Ask clarifying questions**
   - "Are you asking about the current implementation or production-ready version?"
   - Shows you understand context matters

5. **Connect to real-world systems**
   - "This is similar to how Twitter handles tweet creation..."
   - Shows broader understanding

**Good luck with your interview! 🚀**
