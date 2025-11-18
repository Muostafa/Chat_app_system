# Designing Data-Intensive Applications
## Complete Chapter Summaries for Interview Prep

**By Martin Kleppmann**

---

## Table of Contents

### Part I: Foundations of Data Systems
1. [Reliable, Scalable, and Maintainable Applications](#chapter-1-reliable-scalable-and-maintainable-applications)
2. [Data Models and Query Languages](#chapter-2-data-models-and-query-languages)
3. [Storage and Retrieval](#chapter-3-storage-and-retrieval)
4. [Encoding and Evolution](#chapter-4-encoding-and-evolution)

### Part II: Distributed Data
5. [Replication](#chapter-5-replication)
6. [Partitioning](#chapter-6-partitioning)
7. [Transactions](#chapter-7-transactions)
8. [The Trouble with Distributed Systems](#chapter-8-the-trouble-with-distributed-systems)
9. [Consistency and Consensus](#chapter-9-consistency-and-consensus)

### Part III: Derived Data
10. [Batch Processing](#chapter-10-batch-processing)
11. [Stream Processing](#chapter-11-stream-processing)
12. [The Future of Data Systems](#chapter-12-the-future-of-data-systems)

---

# Part I: Foundations of Data Systems

## Chapter 1: Reliable, Scalable, and Maintainable Applications

### Summary

This chapter introduces the three key concerns for data-intensive applications:

**1. Reliability** - System works correctly even when things go wrong
**2. Scalability** - Ability to handle growth (data volume, traffic, complexity)
**3. Maintainability** - Easy for teams to work on the system productively

### Key Concepts

#### Reliability

**Definition:** System continues to work correctly even in the face of faults (hardware, software, human errors).

**Types of Faults:**

1. **Hardware Faults**
   - Hard disk crashes
   - RAM becomes faulty
   - Power outage

**Solution:** Redundancy
```yaml
# My chat app example: MySQL with replication
master:
  host: db-master
replicas:
  - host: db-replica-1
  - host: db-replica-2

# If master fails, promote replica
```

2. **Software Errors**
   - Bug that crashes all instances simultaneously
   - Runaway process consuming resources
   - Cascading failures

**Solution:** Defensive programming, monitoring, testing
```ruby
# My chat app: Handle errors gracefully
def create_message
  number = SequentialNumberService.next_message_number(chat_id)
  CreateMessageJob.perform_async(chat_id, number, body)
rescue Redis::ConnectionError => e
  # Redis down - fail gracefully
  render json: { error: 'Service temporarily unavailable' }, status: 503
end
```

3. **Human Errors**
   - Configuration mistakes
   - Deploying wrong version
   - Accidental data deletion

**Solutions:**
- Well-designed APIs (minimize errors)
- Sandbox environments (separate dev/staging/prod)
- Thorough testing (unit, integration, end-to-end)
- Quick rollback (blue/green deployment)
- Monitoring and telemetry

---

#### Scalability

**Definition:** System's ability to cope with increased load.

**Describing Load:**

Load parameters vary by system:
- Requests per second (web server)
- Read/write ratio (database)
- Concurrent users (chat app)
- Cache hit rate

**Example - Twitter's Home Timeline:**
```
Load parameters:
- 300k tweets/sec (avg)
- 4.6k tweets/sec (peak)
- 12M followers for celebrity (fan-out problem!)

Challenge: When @celebrity tweets, update 12M timelines?

Solution 1: Query on read (slow for 12M users)
SELECT * FROM tweets WHERE user_id IN (following_list) ORDER BY timestamp

Solution 2: Pre-compute on write (fan-out)
When tweet posted → Write to 12M followers' timeline caches
```

**My Chat App Load Parameters:**
```ruby
# Current load (demo):
- 10 applications
- 100 chats per application
- 1000 messages per chat
- 10 requests/second

# Instabug scale (hypothetical):
- 100k applications
- 1M bug events/hour = 278 events/second
- 10M searches/day
- 1B total events stored
```

**Describing Performance:**

1. **Throughput** - Number of records processed per second
2. **Response Time** - Time between request and response

```ruby
# Percentiles matter more than averages
# p50 (median): 50% of requests faster than this
# p95: 95% of requests faster than this
# p99: 99% of requests faster than this

# My chat app metrics:
response_times = [10, 15, 20, 25, 30, 50, 100, 200, 500, 1000]  # ms

p50 = percentile(response_times, 50)  # 30ms - typical user
p95 = percentile(response_times, 95)  # 500ms - slower users
p99 = percentile(response_times, 99)  # 1000ms - worst case
```

**Tail Latency Amplification:**
```
User request → 10 backend services
If each service p99 = 100ms
Overall p99 = ~1000ms (10x worse!)

Solution: Circuit breakers, timeouts, fallbacks
```

**Approaches for Coping with Load:**

1. **Vertical Scaling (Scale Up):** More powerful machine
   - Pros: Simple
   - Cons: Expensive, single point of failure

2. **Horizontal Scaling (Scale Out):** More machines
   - Pros: Cost-effective, fault-tolerant
   - Cons: Complex

**My Chat App Scaling:**
```ruby
# Current: Single Rails instance
# Scale to: Multiple instances behind load balancer

# Stateless design allows horizontal scaling:
- No in-memory state (uses Redis)
- Database connection pooling
- Shared session store (Redis)
```

**For Instabug:**
```
API Layer: 100+ stateless instances (horizontal)
Database: Sharding by application_id (horizontal)
Cache: Redis cluster (horizontal)
Search: Elasticsearch cluster (horizontal)
```

---

#### Maintainability

**Definition:** Making life better for engineering and operations teams.

**Three Design Principles:**

1. **Operability** - Easy for operations to keep system running
   - Good monitoring/logging
   - Good documentation
   - Automation support

2. **Simplicity** - Easy for new engineers to understand
   - Abstraction (hide complexity)
   - Good naming
   - Avoid unnecessary complexity

3. **Evolvability** - Easy to make changes
   - Agility (adapt to changing requirements)
   - Extensibility
   - Modifiability

**My Chat App Example:**

```ruby
# Operability: Health checks
get '/health', to: 'health#index'

# Simplicity: Clear service object
class SequentialNumberService
  def self.next_message_number(chat_id)
    REDIS.incr("chat:#{chat_id}:message_counter")
  end
end

# Evolvability: Easy to add new features
# To add message reactions:
# 1. Add migration
# 2. Add model
# 3. Add controller action
# 4. Existing message creation untouched
```

---

### Interview Questions on Chapter 1

**Q1: How do you design a reliable system?**

**Answer:**
"Design for failure. Assume everything will fail - hard drives, networks, services. Use redundancy (multiple instances, database replicas), graceful degradation (return cached data if service down), and comprehensive monitoring.

In my chat app, if Redis is down, I return 503 instead of crashing. If Elasticsearch fails during message creation, I log the error but still save the message to MySQL - search is temporarily broken but data is safe."

**Q2: What's the difference between latency and response time?**

**Answer:**
"Response time is what the client sees - total time from sending request to receiving response. Latency is time waiting for service - excludes network time and queuing delays.

Response time = Network time + Queue time + Service time
Latency = Service time only

For monitoring, we care about response time (user experience). For optimization, we care about latency (our service's actual work)."

**Q3: Why use percentiles instead of averages?**

**Answer:**
"Averages hide outliers. If 99% of requests take 10ms but 1% take 10 seconds, average is ~110ms (misleading). p99 = 10s tells the true story - 1% of users have terrible experience.

Percentiles matter for SLAs: 'p95 response time < 200ms' is better than 'average < 100ms'. Amazon found even p99.9 matters because slowest requests are often from customers with most data (valuable customers)."

**Q4: How do you scale a system?**

**Answer:**
"First, identify the bottleneck through profiling/monitoring. Then:

1. **Vertical scaling:** Bigger machine (quick fix, limited)
2. **Horizontal scaling:** More machines (requires stateless design)
3. **Caching:** Redis for hot data
4. **Async processing:** Queue heavy work (my chat app pattern)
5. **Database sharding:** Split data across multiple databases
6. **Read replicas:** Separate read and write databases

For Instabug's scale (millions of events), horizontal scaling is essential - can't fit on one machine."

---

## Chapter 2: Data Models and Query Languages

### Summary

Data models are the most important part of software - they affect how we think about the problem and how software is written.

**Hierarchy of Data Models:**
```
Application (objects, data structures)
    ↓
Database (relational, document, graph)
    ↓
Storage (bytes on disk, memory, network)
    ↓
Hardware (electrical currents, magnetic fields)
```

### Key Concepts

#### Relational Model (SQL)

**Invented:** 1970 by Edgar Codd (IBM)

**Structure:** Data organized into relations (tables), each a collection of tuples (rows).

**My Chat App Example:**
```sql
-- Relational model with foreign keys
CREATE TABLE chat_applications (
  id BIGINT PRIMARY KEY,
  token VARCHAR(32) UNIQUE,
  name VARCHAR(255)
);

CREATE TABLE chats (
  id BIGINT PRIMARY KEY,
  chat_application_id BIGINT REFERENCES chat_applications(id),
  number INTEGER,
  UNIQUE(chat_application_id, number)
);

CREATE TABLE messages (
  id BIGINT PRIMARY KEY,
  chat_id BIGINT REFERENCES chats(id),
  number INTEGER,
  body TEXT,
  UNIQUE(chat_id, number)
);

-- Query with JOIN
SELECT m.*, c.number as chat_number, ca.name as app_name
FROM messages m
JOIN chats c ON m.chat_id = c.id
JOIN chat_applications ca ON c.chat_application_id = ca.id
WHERE ca.token = 'abc123';
```

**Pros:**
- ✅ Strong schema (data integrity)
- ✅ JOINs for complex queries
- ✅ ACID transactions
- ✅ Mature tooling

**Cons:**
- ❌ Impedance mismatch (objects ≠ tables)
- ❌ Schema migrations required
- ❌ JOINs can be slow at scale

---

#### Document Model (NoSQL)

**Examples:** MongoDB, CouchDB, RethinkDB

**Structure:** Self-contained documents (JSON/BSON), no schema required.

**Instabug Bug Report Example:**
```javascript
// MongoDB document - natural nesting
{
  _id: ObjectId("..."),
  bug_id: "bug-12345",
  timestamp: ISODate("2025-01-17T10:30:00Z"),

  // Nested user object (no JOIN needed)
  user: {
    id: "user-123",
    email: "user@example.com",
    device: {
      model: "iPhone 15",
      os_version: "iOS 18.2",
      app_version: "1.2.3"
    }
  },

  // Nested crash data
  crash: {
    exception: "NullPointerException",
    message: "Attempted to access null object",
    stack_trace: [
      "at com.app.MainActivity.onCreate(MainActivity.java:42)",
      "at android.app.Activity.performCreate(Activity.java:6876)"
    ],
    thread_state: [
      { thread_id: 1, name: "main", state: "RUNNABLE" }
    ]
  },

  // Variable fields (no schema migration!)
  custom_data: {
    feature_flag_xyz: true,
    experiment_group: "A"
  },

  tags: ["crash", "critical", "android"]
}

// Query without JOIN
db.bugs.find({
  "user.device.os_version": "iOS 18.2",
  "crash.exception": "NullPointerException",
  timestamp: { $gte: ISODate("2025-01-01") }
})
```

**Pros:**
- ✅ Schema flexibility (add fields without migration)
- ✅ Locality (related data stored together)
- ✅ Natural mapping to objects
- ✅ Good for hierarchical data

**Cons:**
- ❌ Weak schema (can cause bugs)
- ❌ Data duplication (denormalization)
- ❌ Limited JOIN support

**When to Use Document Model:**
- Data has document-like structure (self-contained)
- Relationships between documents are rare
- Schema changes frequently
- Need high write throughput

**My Chat App - Why I Used Relational:**
```ruby
# Relationships are important:
# Application has_many Chats
# Chat has_many Messages
# Message belongs_to Chat belongs_to Application

# Foreign keys enforce referential integrity
# JOINs are needed for queries like "show all messages for application X"
```

---

#### Graph Model

**Examples:** Neo4j, Amazon Neptune, ArangoDB

**Structure:** Vertices (nodes) and edges (relationships).

**Use Case - Social Network:**
```cypher
// Cypher query (Neo4j)
// Find friends of friends who like the same movies

MATCH (me:Person {name: 'Alice'})-[:FRIEND]->(friend)-[:FRIEND]->(fof)
WHERE NOT (me)-[:FRIEND]->(fof)
  AND (me)-[:LIKES]->(:Movie)<-[:LIKES]-(fof)
RETURN fof.name, COUNT(*) as common_movies
ORDER BY common_movies DESC
LIMIT 10
```

**Use Case - Instabug Bug Grouping:**
```cypher
// Graph model for bug similarity
CREATE (b1:Bug {id: "bug-1", stack_trace: "..."})
CREATE (b2:Bug {id: "bug-2", stack_trace: "..."})

// Create similarity relationship
MATCH (b1:Bug {id: "bug-1"}), (b2:Bug {id: "bug-2"})
CREATE (b1)-[:SIMILAR_TO {score: 0.95}]->(b2)

// Find all bugs similar to bug-1 (transitive)
MATCH (b:Bug {id: "bug-1"})-[:SIMILAR_TO*1..3]-(similar)
RETURN similar
```

**When to Use Graph Model:**
- Many-to-many relationships
- Recursive relationships (friends of friends)
- Complex queries on relationships
- Data naturally forms a graph

---

#### Query Languages

**Declarative (SQL):**
```sql
-- Describe WHAT you want, not HOW to get it
SELECT * FROM messages
WHERE created_at > '2025-01-01'
ORDER BY created_at DESC
LIMIT 10;

-- Database optimizer chooses execution plan
```

**Imperative (Code):**
```ruby
# Describe HOW to get it, step-by-step
messages = []
Message.each do |message|
  if message.created_at > Date.parse('2025-01-01')
    messages << message
  end
end
messages.sort_by(&:created_at).reverse.take(10)
```

**Declarative Benefits:**
- Database can optimize (use indexes, reorder operations)
- Easier to parallelize
- More concise

**MapReduce (MongoDB):**
```javascript
// Hybrid: declarative + imperative

// Map function (imperative)
function map() {
  emit(this.chat_id, 1);
}

// Reduce function (imperative)
function reduce(key, values) {
  return Array.sum(values);
}

// Query (declarative)
db.messages.mapReduce(
  map,
  reduce,
  { out: "message_counts_by_chat" }
)

// Modern MongoDB: Aggregation pipeline (more declarative)
db.messages.aggregate([
  { $group: { _id: "$chat_id", count: { $sum: 1 } } },
  { $sort: { count: -1 } },
  { $limit: 10 }
])
```

---

### Interview Questions on Chapter 2

**Q1: Relational vs Document databases - when to use which?**

**Answer:**
"Use relational (PostgreSQL, MySQL) when:
- Data has clear relationships (foreign keys)
- Need ACID transactions
- Schema is stable and well-defined
- Complex JOINs are common

Example: Financial transactions, user accounts

Use document (MongoDB) when:
- Data is hierarchical/self-contained
- Schema evolves frequently
- Need high write throughput
- Relationships are rare

Example: Bug reports with variable fields, log storage, content management

My chat app uses relational because the hierarchy (Application → Chat → Message) benefits from foreign keys and JOINs. For Instabug's bug reports with custom fields, document model might be better."

**Q2: What is impedance mismatch?**

**Answer:**
"Mismatch between object-oriented code and relational databases. In code, we have nested objects:

```ruby
user = {
  name: 'Alice',
  address: {
    street: '123 Main St',
    city: 'NYC'
  }
}
```

In relational DB, we need separate tables:
```sql
users: id, name
addresses: id, user_id, street, city
```

We need ORM (ActiveRecord) to translate between them. Document databases reduce this mismatch - JSON structure matches code objects directly."

**Q3: Why are document databases called "schemaless"?**

**Answer:**
"They're not truly schemaless - they're 'schema-on-read' vs relational 'schema-on-write'.

Schema-on-write (SQL):
```sql
ALTER TABLE messages ADD COLUMN priority INTEGER;
-- Must migrate all rows before writing new schema
```

Schema-on-read (MongoDB):
```javascript
// Just start writing new field
db.messages.insert({ body: 'Hi', priority: 1 })

// Old documents don't have it (handled in code)
messages.forEach(msg => {
  const priority = msg.priority || 0;  // Default if missing
})
```

Pros: Flexibility, no downtime for schema changes
Cons: Schema errors surface at runtime, not database level"

---

## Chapter 3: Storage and Retrieval

### Summary

How databases store and retrieve data internally. Understanding storage engines helps choose the right database and tune performance.

**Two families of storage engines:**
1. **Log-structured** (LSM-trees) - Optimized for writes
2. **Page-oriented** (B-trees) - Optimized for reads

### Key Concepts

#### Hash Indexes (Simplest)

**Concept:** In-memory hash map where keys point to byte offsets in data file.

```ruby
# Simple implementation
class SimpleDB
  def initialize
    @index = {}  # Hash map: key => byte_offset
    @file = File.open('data.log', 'a+')
  end

  def set(key, value)
    offset = @file.pos
    @file.write("#{key},#{value}\n")
    @file.flush
    @index[key] = offset
  end

  def get(key)
    offset = @index[key]
    return nil unless offset

    @file.seek(offset)
    line = @file.readline
    line.split(',')[1]
  end
end

# Usage
db = SimpleDB.new
db.set('user:123', 'Alice')  # Writes to disk, updates index
db.get('user:123')           # Looks up offset in index, reads from disk
```

**Pros:**
- ✅ Fast writes (append-only)
- ✅ Fast reads (one disk seek)

**Cons:**
- ❌ Hash table must fit in memory
- ❌ Range queries inefficient

**Used by:** Bitcask (Riak's default storage engine)

**Compaction:** Periodically merge segments and remove duplicates
```
Segment 1: user:1=Alice, user:2=Bob, user:1=Alice2
Segment 2: user:2=Bob2, user:3=Charlie

After compaction:
Segment: user:1=Alice2, user:2=Bob2, user:3=Charlie
```

---

#### SSTables (Sorted String Tables)

**Concept:** Like hash index, but keys are sorted. Enables efficient range queries.

**Structure:**
```
Segment file (sorted by key):
chat:1  = "General"
chat:2  = "Random"
chat:10 = "Tech"
chat:20 = "Design"

Sparse index (in memory):
chat:1  => offset 0
chat:10 => offset 64
chat:20 => offset 128

// To find chat:15:
// 1. Look in index: chat:10 < chat:15 < chat:20
// 2. Start at offset 64, scan until chat:20
// 3. Much faster than full scan!
```

**Writes:**
```
1. Write to memtable (in-memory balanced tree, e.g., Red-Black tree)
2. When memtable full, flush to disk as SSTable
3. Keep write-ahead log for crash recovery

Memtable:
  chat:5  = "Support"
  chat:3  = "Sales"
  chat:7  = "Engineering"

Sorted on flush:
  chat:3  = "Sales"
  chat:5  = "Support"
  chat:7  = "Engineering"
```

**Reads:**
```
1. Check memtable
2. Check most recent SSTable
3. Check next-most-recent SSTable
4. ...

// Optimization: Bloom filter (avoid checking SSTables that definitely don't have key)
```

**Compaction:**
```
Merge multiple SSTables, keep only latest value for each key

SSTable 1: a=1, c=3, e=5
SSTable 2: b=2, c=4, f=6

Merged:    a=1, b=2, c=4, e=5, f=6
```

**Used by:** LevelDB, RocksDB, Cassandra, HBase

---

#### LSM-Trees (Log-Structured Merge-Trees)

**Concept:** Keep multiple SSTables at different "levels", compact them periodically.

**Structure:**
```
Level 0: [SSTable1] [SSTable2] [SSTable3]  (10 MB each, overlapping keys)
Level 1: [SSTable4] [SSTable5]              (100 MB each, non-overlapping)
Level 2: [SSTable6]                         (1 GB, non-overlapping)

Compaction:
- When Level 0 has 4 SSTables, merge into Level 1
- When Level 1 exceeds size, merge into Level 2
```

**Write Amplification:**
```
Write 1 MB to database →
- Write to memtable
- Flush to Level 0 (1 MB)
- Compact to Level 1 (write 10 MB)
- Compact to Level 2 (write 100 MB)

Total disk writes: 111 MB for 1 MB logical write
```

**Pros:**
- ✅ High write throughput (sequential writes)
- ✅ Good compression (SSTables compacted)
- ✅ Can handle datasets larger than memory

**Cons:**
- ❌ Compaction can interfere with performance
- ❌ Slower reads than B-trees (check multiple SSTables)

**My Chat App - Why MySQL Uses B-trees:**
```ruby
# Chat app has more reads than writes
# Messages are queried frequently (show chat history)
# B-tree gives better read performance
```

**Instabug Use Case - Where LSM-trees Win:**
```ruby
# Bug event ingestion: Very high write throughput
# Writes: 1000 events/sec
# Reads: Occasional (view specific bug)

# LSM-tree (Cassandra, HBase) would be better
# Optimized for write-heavy workload
```

---

#### B-Trees

**Concept:** Most common index structure. Balanced tree with fixed-size pages.

**Structure:**
```
                    [50]
                   /    \
           [25, 40]      [75, 90]
          /   |   \      /   |    \
     [1-24][26-39][41-49][51-74][76-89][91-100]

Page size: Typically 4 KB
Branching factor: ~500 (each page has ~500 references)

Depth: log₅₀₀(n)
For 1 billion keys: 4 levels (500⁴ = 625 billion)
```

**Writes:**
```
Insert key=32, value="Hello"

1. Find leaf page containing key 32 (page [26-39])
2. If page has space: Write in place
3. If page full: Split into two pages, update parent

      [25, 40]           [25, 35, 40]
     /   |   \    →     /    |    |    \
[1-24][26-39][41-49]  [1-24][26-34][36-39][41-49]
```

**Write-Ahead Log (WAL):**
```
Problem: B-tree writes are not atomic
- Split page requires updating parent
- If crash during split, tree corrupted

Solution: Write-ahead log
1. Write change to append-only log
2. Apply change to B-tree
3. If crash, replay log to recover
```

**Latches (Locks):**
```ruby
# Multiple threads can read/write B-tree concurrently
# Need latches (lightweight locks) to protect tree structure

thread_1: Insert 32 (modifying page [26-39])
thread_2: Insert 33 (modifying same page)

# Use latch to serialize:
thread_1.lock_page([26-39])
thread_1.insert(32)
thread_1.unlock_page([26-39])

thread_2.lock_page([26-39])
thread_2.insert(33)
thread_2.unlock_page([26-39])
```

**Pros:**
- ✅ Faster reads (each key in one place)
- ✅ Consistent performance (balanced tree)
- ✅ Better for transactions (easier to lock ranges)

**Cons:**
- ❌ Slower writes (random disk access)
- ❌ Write amplification (entire page rewritten)
- ❌ Fragmentation over time

**Used by:** PostgreSQL, MySQL InnoDB, Oracle, SQL Server

---

#### Comparing B-Trees and LSM-Trees

| Aspect | B-Trees | LSM-Trees |
|--------|---------|-----------|
| **Write Performance** | Slower (random writes) | Faster (sequential writes) |
| **Read Performance** | Faster (one lookup) | Slower (check multiple SSTables) |
| **Write Amplification** | Higher (whole page) | Higher (multiple compactions) |
| **Space Amplification** | Lower (no duplicates) | Higher (multiple copies during compaction) |
| **Transaction Support** | Better (page-level locks) | Weaker |
| **Use Case** | Read-heavy, transactions | Write-heavy, append-only |

**Real-World Examples:**

```ruby
# My Chat App (MySQL/B-tree)
# - Read-heavy: Display messages in chat
# - Transactions: Creating message + updating counter
# - Foreign keys: Referential integrity

# Instabug Event Ingestion (Cassandra/LSM-tree)
# - Write-heavy: 1000 events/sec
# - Reads rare: View specific bug
# - No transactions needed: Events are immutable
```

---

#### Column-Oriented Storage

**Problem:** Analytics queries scan millions of rows but only a few columns.

**Row-Oriented (Traditional):**
```
Disk layout:
Row 1: id=1, name="Alice", email="alice@x.com", age=25, ...
Row 2: id=2, name="Bob", email="bob@x.com", age=30, ...
Row 3: id=3, name="Charlie", email="charlie@x.com", age=35, ...

Query: SELECT age FROM users WHERE age > 30
Problem: Read entire rows, discard most columns
```

**Column-Oriented:**
```
Disk layout:
id:    [1, 2, 3, 4, 5, ...]
name:  ["Alice", "Bob", "Charlie", ...]
email: ["alice@x.com", "bob@x.com", ...]
age:   [25, 30, 35, 40, 45, ...]

Query: SELECT age FROM users WHERE age > 30
Solution: Read only age column (compress well!)
```

**Compression:**
```
age column: [25, 25, 25, 30, 30, 35, 35, 35, 35, 40, 40, 45]

Run-length encoding:
[(25, count=3), (30, count=2), (35, count=4), (40, count=2), (45, count=1)]

Bitmap encoding (for low cardinality):
age=25: [1,1,1,0,0,0,0,0,0,0,0,0]
age=30: [0,0,0,1,1,0,0,0,0,0,0,0]
age=35: [0,0,0,0,0,1,1,1,1,0,0,0]
```

**Used by:** Redshift, BigQuery, Snowflake, Parquet, ORC

**Instabug Analytics Example:**
```sql
-- Query: How many crashes per day for each app?
SELECT
  date_trunc('day', timestamp) as day,
  app_id,
  COUNT(*) as crash_count
FROM bug_events
WHERE event_type = 'crash'
  AND timestamp > NOW() - INTERVAL '30 days'
GROUP BY day, app_id

-- Column-oriented advantages:
-- 1. Only read: timestamp, app_id, event_type (not all 50 columns)
-- 2. Timestamp sorted → fast range scan
-- 3. app_id compressed (many duplicates)
-- 4. event_type compressed (only a few values)
```

---

### Interview Questions on Chapter 3

**Q1: Explain the difference between B-trees and LSM-trees.**

**Answer:**
"B-trees optimize for reads - each key is stored once, lookups are fast. Writes are slower because they require in-place updates to fixed-size pages (random disk access).

LSM-trees optimize for writes - all writes are sequential (append to memtable, flush to disk). Reads are slower because you might need to check multiple SSTables.

For my chat app (read-heavy), MySQL's B-tree is better. For Instabug's event ingestion (write-heavy), Cassandra's LSM-tree would be better."

**Q2: What is write amplification?**

**Answer:**
"Write amplification is when a database writes more data to disk than the logical data written by the application.

B-tree example:
- Change 1 byte → Rewrite entire 4 KB page
- Write amplification = 4 KB / 1 byte = 4096x

LSM-tree example:
- Write 1 MB → Flush to Level 0 → Compact to Level 1 (10 MB) → Compact to Level 2 (100 MB)
- Write amplification = 111 MB / 1 MB = 111x

Both have write amplification but for different reasons. B-trees: page granularity. LSM-trees: compaction."

**Q3: When would you use a column-oriented database?**

**Answer:**
"For analytics workloads where:
1. Queries scan many rows (millions)
2. But select few columns (5 out of 50)
3. Aggregations are common (SUM, COUNT, AVG)
4. Data is read-only or append-only

Example for Instabug:
```sql
-- Daily crash report analytics
SELECT app_id, COUNT(*)
FROM events
WHERE date = '2025-01-17' AND type = 'crash'
GROUP BY app_id
```

Column-oriented (Redshift) reads only app_id, date, type columns. Row-oriented (PostgreSQL) reads all 50 columns. 10x+ faster!"

---

(Continuing with chapters 4-12 in next section due to length...)

Would you like me to continue with the remaining chapters (4-12)?

## Chapter 4: Encoding and Evolution

### Summary

How data is encoded for storage and transmission. Applications evolve over time - need backward and forward compatibility.

**Key Challenge:** Old and new versions of code running simultaneously.

### Key Concepts

#### Encoding Formats

**1. Language-Specific (Bad for Interop):**
```ruby
# Ruby Marshal
data = { user_id: 123, name: "Alice" }
encoded = Marshal.dump(data)  # Binary format
decoded = Marshal.load(encoded)

# Problems:
# - Only Ruby can read it
# - Security issues (arbitrary code execution)
# - Versioning problems
```

**2. JSON/XML (Human-Readable):**
```javascript
// JSON
{
  "user_id": 123,
  "name": "Alice",
  "created_at": "2025-01-17T10:30:00Z"
}

// Problems:
// - No schema (typos not caught)
// - Ambiguous numbers (int vs float vs string)
// - No binary data support
// - Verbose (larger size)
```

**3. Binary Formats (Efficient):**

**Thrift (Facebook):**
```thrift
// Schema definition
struct BugReport {
  1: required i64 bug_id,
  2: required string title,
  3: optional string description,
  4: list<string> tags
}

// Encoded: [field_type][field_id][value][field_type][field_id][value]...
// Compact, self-describing
```

**Protocol Buffers (Google):**
```protobuf
// Schema
message BugReport {
  required int64 bug_id = 1;
  required string title = 2;
  optional string description = 3;
  repeated string tags = 4;
}

// Each field has tag number (1, 2, 3, 4)
// Enables schema evolution
```

**Avro (Hadoop):**
```json
// Schema
{
  "type": "record",
  "name": "BugReport",
  "fields": [
    {"name": "bug_id", "type": "long"},
    {"name": "title", "type": "string"},
    {"name": "description", "type": ["null", "string"]},
    {"name": "tags", "type": {"type": "array", "items": "string"}}
  ]
}

// No field tags - reader/writer schemas must match
// Great for big data (Hadoop)
```

---

#### Schema Evolution

**Problem:** Need to change schema without breaking old code.

**Backward Compatibility:** New code can read old data
**Forward Compatibility:** Old code can read new data

**Protocol Buffers Example:**

```protobuf
// Version 1
message User {
  required int64 id = 1;
  required string name = 2;
}

// Version 2 - Add optional field
message User {
  required int64 id = 1;
  required string name = 2;
  optional string email = 3;  // NEW FIELD
}

// Backward compatibility:
// New code reads old data (no email field) → email = null

// Forward compatibility:
// Old code reads new data (has email field) → ignores unknown field
```

**Rules for Compatibility:**

1. **Can add optional fields** (backward compatible)
2. **Can remove optional fields** (forward compatible)
3. **Cannot change field types** (breaks both)
4. **Cannot reuse field numbers** (breaks forward compatibility)

**My Chat App Example:**

```ruby
# API v1
{
  "number": 1,
  "body": "Hello"
}

# API v2 - Add priority (backward compatible)
{
  "number": 1,
  "body": "Hello",
  "priority": 1  # Old clients ignore this field
}

# Client code must handle missing fields:
priority = message[:priority] || 0  # Default if missing
```

---

#### Dataflow Modes

**1. Database:**
```
Process A (new code) → Database → Process B (old code)

Process A writes:
{ id: 1, name: "Alice", email: "alice@x.com" }

Process B reads:
{ id: 1, name: "Alice" }  # Ignores email field

Process B updates name, writes back:
{ id: 1, name: "Alice Updated" }  # email field lost!

Solution: Unknown field preservation
Process B must preserve unknown fields when writing back
```

**2. Services (REST/RPC):**
```
Client (old version) → Server (new version)

Client sends:
{ user_id: 123 }

Server expects:
{ user_id: 123, api_version: "v2" }

Server must provide default for missing field:
api_version = request[:api_version] || "v1"
```

**3. Message Queues:**
```
Publisher (new version) → Message Queue → Consumer (old version)

Publisher sends:
{ event: "bug.created", bug_id: 123, priority: 1 }

Consumer reads:
{ event: "bug.created", bug_id: 123 }  # Ignores priority

Solution: Use schema registry (Avro)
Consumers fetch schema for each message
```

---

### Interview Questions on Chapter 4

**Q1: Why use binary encoding instead of JSON?**

**Answer:**
"Binary encodings (Protobuf, Thrift, Avro) have several advantages:

1. **Smaller size:** No field names in every message, compact encoding
   - JSON: `{"user_id":123,"name":"Alice"}` (32 bytes)
   - Protobuf: ~10 bytes

2. **Faster parsing:** No string parsing, direct binary reads

3. **Schema enforcement:** Catch errors at compile time, not runtime

4. **Better evolution:** Field tags enable backward/forward compatibility

Trade-off: Not human-readable, need schema to decode. For Instabug's millions of events per hour, bandwidth savings are significant."

**Q2: What's the difference between backward and forward compatibility?**

**Answer:**
"Backward compatibility: New code reads old data
Forward compatibility: Old code reads new data

Example:
```
Version 1 schema: { id, name }
Version 2 schema: { id, name, email }

Backward (new code, old data):
- Code expects email
- Data doesn't have email
- Code must handle missing email (default value)

Forward (old code, new data):
- Code expects id, name
- Data has id, name, email
- Code must ignore unknown email field
```

Both are needed for rolling deployments - some servers run old code, some run new code simultaneously."

---

# Part II: Distributed Data

## Chapter 5: Replication

### Summary

Keeping copies of the same data on multiple machines connected via network.

**Reasons for Replication:**
1. **Reduce latency** - Keep data geographically close to users
2. **Increase availability** - System continues working even if some parts fail
3. **Increase read throughput** - Scale out read queries

**Challenge:** Handling changes to replicated data (keeping replicas in sync).

### Key Concepts

#### Single-Leader Replication (Master-Slave)

**Structure:**
```
Writes → Leader (Master)
            ├─→ Follower 1 (Slave)
            ├─→ Follower 2
            └─→ Follower 3

Reads ← Leader or any Follower
```

**My Chat App Could Use This:**
```yaml
# MySQL replication
master:
  host: db-master.example.com
  writes: ALL writes go here

replicas:
  - host: db-replica-1.example.com
    lag: ~1s
  - host: db-replica-2.example.com
    lag: ~1s

# Rails config
production:
  primary:
    host: db-master
  replica:
    host: db-replica-1
    replica: true

# Usage
User.using(:primary).create!(name: "Alice")  # Write to master
User.using(:replica).all                      # Read from replica
```

**Replication Methods:**

**1. Statement-Based:**
```sql
-- Leader executes:
INSERT INTO messages (chat_id, number, body) VALUES (1, 5, 'Hello');

-- Sends statement to followers
-- Followers execute same statement

-- Problems:
-- - NOW(), RAND() give different values on different servers
-- - Auto-increment depends on execution order
-- - Triggers/stored procedures can have side effects
```

**2. Write-Ahead Log (WAL) Shipping:**
```
Leader's WAL:
LSN 100: Page 5, offset 20, write "Hello"
LSN 101: Page 7, offset 0, write "World"

Followers apply same WAL entries

Problems:
- WAL is very low-level (storage engine specific)
- Can't replicate between different database versions
```

**3. Logical (Row-Based):**
```
Leader sends logical log:
INSERT INTO messages: chat_id=1, number=5, body='Hello'
UPDATE messages: chat_id=1, number=5, body='Hello World'
DELETE FROM messages: chat_id=1, number=5

Followers parse and apply

Advantages:
- Decoupled from storage engine
- Can replicate to different database versions
- Can parse for external systems (data warehouse)
```

**Replication Lag:**

```ruby
# Write to leader
message = Message.create!(chat_id: 1, number: 5, body: "Hello")

# Immediately read from follower
message = Message.using(:replica).find_by(chat_id: 1, number: 5)
# => nil (replication lag!)

# Problems this causes:

# 1. Read your own writes
user.create_message("Hello")
user.show_messages  # Doesn't see own message yet!

# Solution: Read from leader for your own data
if reading_own_data?
  Message.using(:primary).find(...)
else
  Message.using(:replica).find(...)
end

# 2. Monotonic reads
request_1 → replica_1 (up-to-date) → sees message
request_2 → replica_2 (lagging)    → doesn't see message
# User sees data go backward in time!

# Solution: Route user's requests to same replica
replica = hash(user_id) % replica_count

# 3. Consistent prefix reads
User A: "What time is it?"
User B: "It's 5 PM"

# If replication lagging:
Replica 1: B's message arrives first
Replica 2: A's message arrives first

# User sees B answering before A asks!

# Solution: Causally related writes go to same partition
```

---

#### Multi-Leader Replication

**Use Cases:**
1. **Multi-datacenter operation**
2. **Offline clients** (mobile apps)
3. **Collaborative editing** (Google Docs)

**Structure:**
```
Datacenter 1:          Datacenter 2:
  Leader 1               Leader 2
  ↓      ↑               ↓      ↑
Follower Follower      Follower Follower

   ↓←←←←←←←←←←←←→→→→→→→→↑
   Cross-datacenter replication
```

**Instabug Example:**
```
US Datacenter:
  Leader (accepts writes from US customers)
  ↓
EU Datacenter:
  Leader (accepts writes from EU customers)

Both leaders replicate to each other

Benefits:
- Low latency (write to nearby datacenter)
- Fault tolerance (if US datacenter down, EU still works)

Problems:
- Write conflicts!
```

**Conflict Handling:**

**Example Conflict:**
```
User A (in US): Changes bug title to "Cannot login"
User B (in EU): Changes same bug title to "Login broken"

Both writes succeed in their local datacenter
Then replicate to each other

Which title wins?
```

**Conflict Resolution Strategies:**

**1. Last Write Wins (LWW):**
```ruby
# Timestamp-based
conflict_resolution: :last_write_wins

# Record with latest timestamp wins
# Loss of data! One update is discarded
```

**2. Application-Level:**
```ruby
# Present both versions to user
bug.title_us = "Cannot login"
bug.title_eu = "Login broken"

# User chooses or merges
```

**3. CRDTs (Conflict-Free Replicated Data Types):**
```javascript
// Google Docs uses this
// Operations are commutative (order doesn't matter)

User A: Insert "Hello" at position 0
User B: Insert "World" at position 0

CRDT ensures both edits preserved:
Result: "WorldHello" or "HelloWorld" (deterministic)
```

---

#### Leaderless Replication (Dynamo-style)

**Examples:** Cassandra, Riak, Voldemort

**Structure:**
```
Write to N replicas in parallel
Read from N replicas in parallel
Quorum: W + R > N ensures consistency

Example: N=3, W=2, R=2
Write succeeds when 2 of 3 replicas acknowledge
Read queries 2 of 3 replicas, takes latest value
```

**Quorum Writes and Reads:**

```ruby
# N = 3 replicas
# W = 2 (write quorum)
# R = 2 (read quorum)

# Write to replicas A, B, C
result = write_to_replicas([A, B, C], value: "Hello", quorum: 2)
# Succeeds when A and B acknowledge (C might still be writing)

# Read from replicas A, B, C
results = read_from_replicas([A, B, C], quorum: 2)
# Waits for 2 responses
# A: "Hello" (version 5)
# B: "Hello" (version 5)
# C: "Hi"    (version 3)  (lagging)

# Returns "Hello" (latest version based on timestamp/vector clock)
```

**Advantages:**
- ✅ No single point of failure (no leader)
- ✅ Can tolerate node failures (still have quorum)
- ✅ Low latency (don't wait for all replicas)

**Disadvantages:**
- ❌ More complex conflict resolution
- ❌ Weaker consistency guarantees
- ❌ Higher latency than leader-based (wait for multiple responses)

**Sloppy Quorum & Hinted Handoff:**

```
Normal: Write to replicas A, B, C (quorum 2)

If A is down:
Sloppy quorum: Write to B, C, D (temporary replica)
When A comes back online:
Hinted handoff: D forwards writes to A
```

---

### Interview Questions on Chapter 5

**Q1: Explain the trade-offs of single-leader vs multi-leader replication.**

**Answer:**
"Single-leader (master-slave):
Pros: Simple, no write conflicts, strong consistency
Cons: Single point of failure for writes, all writes go through leader (bottleneck)

Multi-leader:
Pros: Low latency (write to nearby datacenter), fault tolerance (no single point of failure)
Cons: Write conflicts, more complex

For my chat app (single datacenter, low write volume), single-leader is sufficient. For Instabug (global users, high write volume), multi-leader in multiple datacenters makes sense."

**Q2: What is replication lag and how do you handle it?**

**Answer:**
"Replication lag is the delay between write on leader and visibility on follower.

Problems:
1. Read-your-writes: User creates message, immediately doesn't see it
2. Monotonic reads: User sees data, refresh shows old data
3. Consistent prefix: See effect before cause

Solutions:
1. Read-your-writes: Read from leader for user's own data
2. Monotonic reads: Route user to same replica
3. Consistent prefix: Causally related writes to same partition

For critical data (user just created), read from leader. For non-critical data (other users' messages), read from replica OK."

**Q3: Explain quorum reads and writes.**

**Answer:**
"In leaderless replication (Cassandra), write to multiple replicas in parallel.

N = number of replicas (usually 3)
W = write quorum (usually 2)
R = read quorum (usually 2)

As long as W + R > N, reads see latest writes:
- W=2, R=2, N=3: At least 1 replica in read set has latest write

Example:
```
Write "Hello" with W=2
✓ Replica A: "Hello"
✓ Replica B: "Hello"
✗ Replica C: still writing...

Read with R=2
Query A and B → both return "Hello" → consistent!
```

Trade-off: Higher latency (wait for multiple replicas) vs consistency."

---

## Chapter 6: Partitioning (Sharding)

### Summary

Break large dataset into smaller partitions (shards) for scalability.

**Goal:** Distribute data and query load across multiple machines.

### Key Concepts

#### Partitioning by Key Range

**Concept:** Assign continuous range of keys to each partition.

```
Partition 1: keys A-G
Partition 2: keys H-N
Partition 3: keys O-Z

Example: Instabug partitioning by app_id
Partition 1: app_ids 1-1000
Partition 2: app_ids 1001-2000
Partition 3: app_ids 2001-3000
```

**Advantages:**
- ✅ Range queries efficient (keys sorted within partition)
- ✅ Simple to understand

**Disadvantages:**
- ❌ Hotspots (uneven data distribution)

**Hotspot Example:**
```ruby
# Partition by timestamp
Partition 1: 2025-01-01 to 2025-01-10
Partition 2: 2025-01-11 to 2025-01-20
Partition 3: 2025-01-21 to 2025-01-31

# Problem: All writes go to Partition 3 (current date)!
# Other partitions idle

# Solution: Add another dimension
# Partition by (app_id, timestamp)
```

---

#### Partitioning by Hash

**Concept:** Hash function distributes keys evenly across partitions.

```ruby
# Hash function
hash("app_123") = 2847629384

# Partition assignment
partition = hash(key) % num_partitions

partition = hash("app_123") % 3  # → 2
partition = hash("app_456") % 3  # → 1
partition = hash("app_789") % 3  # → 0
```

**Consistent Hashing:**

```
Problem: hash(key) % num_partitions

If num_partitions changes (add/remove server):
All keys need to move! (rehashing entire dataset)

Solution: Consistent hashing
Hash servers AND keys to same ring
Key goes to next server clockwise

Ring: [Server A at 0°] [Server B at 120°] [Server C at 240°]

Key "app_123" hashes to 50° → goes to Server B
Key "app_456" hashes to 200° → goes to Server C

Add Server D at 60°:
Only keys in 50°-60° range need to move (not all keys!)
```

**Cassandra Partitioning Example:**
```sql
CREATE TABLE bug_events (
  app_id text,
  timestamp timestamp,
  event_data text,
  PRIMARY KEY ((app_id), timestamp)  -- app_id is partition key
)

-- All events for same app_id on same partition
-- Range queries on timestamp efficient (within partition)
```

---

#### Partitioning and Secondary Indexes

**Problem:** Secondary indexes don't map neatly to partitions.

**Example:**
```sql
-- Primary key: bug_id (partitioned)
-- Secondary index: app_id, created_at

SELECT * FROM bugs WHERE app_id = 'app_123' AND created_at > '2025-01-01'

-- Which partition to query? bug_id determines partition, but we're querying by app_id!
```

**Solution 1: Document-Partitioned Indexes (Local Index)**

```
Partition 1 (bug_ids 1-1000):
  Secondary index: app_id → bug_ids
    app_123 → [5, 27, 103, 456]
    app_456 → [89, 234]

Partition 2 (bug_ids 1001-2000):
  Secondary index: app_id → bug_ids
    app_123 → [1234, 1567]
    app_789 → [1100, 1900]

Query for app_123:
  Must check ALL partitions (scatter/gather)
  Combine results from each partition
```

**Solution 2: Term-Partitioned Indexes (Global Index)**

```
Global secondary index (partitioned by app_id):

Index Partition 1 (app_ids A-M):
  app_123 → bug_ids [5, 27, 103, 456, 1234, 1567]

Index Partition 2 (app_ids N-Z):
  app_789 → bug_ids [1100, 1900]

Query for app_123:
  Check only Index Partition 1 (efficient!)
  Then fetch bug_ids from bug partitions

Trade-off: Writes slower (update index on different partition)
```

**My Chat App - Doesn't Need Partitioning Yet:**
```ruby
# Current scale: Single MySQL instance handles it
# 10 apps × 100 chats × 1000 messages = 1M records (fits on one server)

# When to partition?
# - 100k apps × 1000 chats × 10k messages = 1B records
# - Partition by application_id (all chats/messages for app on same partition)
```

**Instabug - Needs Partitioning:**
```ruby
# Scale: 100k apps, 1B events
# Partition strategy: Hash by app_id

# Benefits:
# - Even distribution (hash function)
# - All events for app on same partition (efficient queries)
# - Can add partitions as data grows

# Cassandra config:
CREATE TABLE events (
  app_id text,
  event_id uuid,
  timestamp timestamp,
  event_data text,
  PRIMARY KEY ((app_id), event_id)
) WITH CLUSTERING ORDER BY (event_id DESC)
```

---

#### Rebalancing Partitions

**When partitions need to change:**
- Data volume increased → Need more partitions
- Machine added/removed
- Failure recovery

**Strategies:**

**1. Fixed Number of Partitions:**
```
Start: 1000 partitions, 10 nodes (100 partitions per node)
Add node: 1000 partitions, 11 nodes (91 partitions per node)

Move partitions from old nodes to new node
Data doesn't need rehashing!

Problem: Need to choose partition count upfront
```

**2. Dynamic Partitioning:**
```
Start: 1 partition
Grows to 10 GB → Split into 2 partitions
Each grows to 10 GB → Split again

Automatically adjusts to data volume

Used by: HBase, RethinkDB
```

**3. Partitioning Proportional to Nodes:**
```
Fixed number of partitions per node (e.g., 100)

10 nodes = 1000 partitions
Add 11th node:
- Create 100 new empty partitions
- Move some data from old partitions

Used by: Cassandra
```

---

### Interview Questions on Chapter 6

**Q1: How would you partition Instabug's bug events?**

**Answer:**
"Partition by app_id using hash partitioning:

```ruby
partition = hash(app_id) % num_partitions
```

Reasoning:
1. Even distribution (hash function prevents hotspots)
2. All events for same app on same partition (efficient queries)
3. Can scale by adding partitions

Example query:
```sql
SELECT * FROM events
WHERE app_id = 'app_123'
  AND timestamp > '2025-01-01'
```
Only hits one partition (app_id determines partition), fast range scan on timestamp within partition.

Alternative considered: Partition by timestamp - rejected because creates hotspot (all writes to current date's partition)."

**Q2: What is consistent hashing and why is it useful?**

**Answer:**
"Consistent hashing minimizes data movement when nodes added/removed.

Traditional hashing:
```
partition = hash(key) % 10  # 10 nodes
Add 11th node:
partition = hash(key) % 11  # All keys rehash!
```

Consistent hashing:
```
Hash ring: Nodes and keys both hashed to 0-360°
Key goes to next node clockwise
Add node: Only keys in that range move
```

Used by: Amazon Dynamo, Cassandra, Memcached

Benefit: Adding/removing nodes only affects ~1/N of data, not all data."

---

## Chapter 7: Transactions

### Summary

Group several reads/writes into logical unit - all succeed or all fail.

**ACID:**
- **Atomicity:** All or nothing
- **Consistency:** Invariants always preserved
- **Isolation:** Concurrent transactions don't interfere
- **Durability:** Committed data not lost

### Key Concepts

#### Atomicity

**Problem:** Multi-step operations can fail partway through.

```ruby
# Transfer money (non-atomic)
account_a.balance -= 100
# CRASH HERE!
account_b.balance += 100

# Result: $100 disappeared!
```

**Solution: Transaction**
```ruby
ActiveRecord::Base.transaction do
  account_a.update!(balance: account_a.balance - 100)
  account_b.update!(balance: account_b.balance + 100)
end

# If crash: Both updates rolled back (atomicity)
# If success: Both updates committed together
```

**My Chat App Example:**
```ruby
# Create message + update counter (atomic)
ActiveRecord::Base.transaction do
  message = chat.messages.create!(number: 5, body: "Hello")
  chat.update!(messages_count: chat.messages_count + 1)
end

# If message.create! fails → counter not updated
# If counter update fails → message not created
# All or nothing!
```

---

#### Isolation Levels

**Problem:** Concurrent transactions can cause anomalies.

**Read Committed (Weakest):**

Guarantees:
1. No dirty reads (don't see uncommitted data)
2. No dirty writes (don't overwrite uncommitted data)

```ruby
# Transaction A
account.update!(balance: 100)  # Not yet committed

# Transaction B (concurrent)
puts account.balance  # → 50 (old value, not 100)

# Transaction A commits
puts account.balance  # → 100 (now visible)
```

**Snapshot Isolation (Repeatable Read):**

```ruby
# Transaction A starts
balance_a = account.balance  # → 50

# Transaction B updates and commits
account.update!(balance: 100)

# Transaction A reads again
balance_b = account.balance  # → 50 (same as before!)

# Each transaction sees consistent snapshot
```

**Implementation: Multi-Version Concurrency Control (MVCC)**
```sql
-- Database keeps multiple versions
id=1, balance=50,  created_by=tx1, valid_from=tx1, valid_to=tx2
id=1, balance=100, created_by=tx2, valid_from=tx2, valid_to=∞

-- Transaction sees version valid at its snapshot time
```

**Serializable (Strongest):**

Guarantees: Equivalent to running transactions serially (no concurrency).

**Methods:**

1. **Actual Serial Execution:** Run one transaction at a time (Redis does this)
2. **Two-Phase Locking (2PL):** Readers block writers, writers block readers
3. **Serializable Snapshot Isolation (SSI):** Optimistic concurrency control

---

#### Common Anomalies

**1. Dirty Read:**
```ruby
# Transaction A
user.update!(email: "new@example.com")  # Not committed

# Transaction B
puts user.email  # → "new@example.com" (dirty read!)

# Transaction A rolls back
puts user.email  # → "old@example.com" (data changed!)
```

**2. Dirty Write:**
```ruby
# Transaction A
listing.update!(seller_id: 1)  # Not committed

# Transaction B
listing.update!(seller_id: 2)  # Overwrites uncommitted value

# Transaction A rolls back
# Now listing.seller_id = 2 (unexpected!)
```

**3. Read Skew (Non-Repeatable Read):**
```ruby
# Account A = 500, Account B = 500, Total = 1000

# Transaction (backup process)
balance_a = account_a.balance  # → 500

# Concurrent transaction
account_a.update!(balance: 400)
account_b.update!(balance: 600)

# Transaction continues
balance_b = account_b.balance  # → 600
total = balance_a + balance_b  # → 1100 (wrong!)

# Solution: Snapshot isolation (consistent view)
```

**4. Write Skew:**
```ruby
# Constraint: At least 1 doctor on call

# Transaction A (Dr. Alice)
on_call_doctors = Doctor.where(on_call: true).count  # → 2
if on_call_doctors > 1
  alice.update!(on_call: false)  # Go off-call
end

# Transaction B (Dr. Bob, concurrent)
on_call_doctors = Doctor.where(on_call: true).count  # → 2
if on_call_doctors > 1
  bob.update!(on_call: false)  # Go off-call
end

# Both commit
# Result: 0 doctors on call! (violated constraint)

# Solution: SELECT FOR UPDATE (lock)
on_call_doctors = Doctor.where(on_call: true).lock.count
```

**5. Phantom Reads:**
```ruby
# Transaction A
meetings = Meeting.where(room_id: 1, time: '10:00').count  # → 0
Meeting.create!(room_id: 1, time: '10:00')  # Book room

# Transaction B (concurrent)
meetings = Meeting.where(room_id: 1, time: '10:00').count  # → 0
Meeting.create!(room_id: 1, time: '10:00')  # Also books!

# Both commit
# Result: Double-booked!

# Solution: Serializable isolation or index range lock
```

---

### Interview Questions on Chapter 7

**Q1: Explain ACID.**

**Answer:**
"ACID guarantees for database transactions:

**Atomicity:** All operations in transaction succeed or all fail. No partial updates.
Example: Transfer money - debit and credit must both happen or neither.

**Consistency:** Database invariants always true. Application-defined constraints preserved.
Example: Account balance never negative.

**Isolation:** Concurrent transactions don't interfere. Each sees consistent view.
Example: Two transactions updating same row don't corrupt each other.

**Durability:** Committed data survives crashes. Written to non-volatile storage.
Example: After 'transaction complete' message, data is permanent.

In my chat app, creating message + updating counter must be atomic - don't want counter incremented without message created."

**Q2: What's the difference between snapshot isolation and serializable?**

**Answer:**
"Snapshot isolation: Each transaction sees consistent snapshot of database. Prevents dirty reads, non-repeatable reads.

But doesn't prevent write skew:
```ruby
# Both transactions see count=2, both decrement, final count=0
# Violated constraint: count must be >= 1
```

Serializable: Strongest isolation. Equivalent to running transactions one at a time. Prevents all anomalies including write skew.

Trade-off: Serializable has lower performance (more locking or conflict detection). Use snapshot isolation for most cases, serializable only when necessary."

---

(Continuing with chapters 8-12 shortly - let me know if you want me to continue!)


## Chapter 8: The Trouble with Distributed Systems

### Summary

Things go wrong in distributed systems in surprising ways. Need to build tolerance for these faults.

**Types of Faults:**
1. **Network faults** - Packets lost, delayed, duplicated
2. **Clock issues** - Time disagreement between nodes
3. **Process pauses** - GC, VM suspension, OS scheduling

### Key Concepts

#### Unreliable Networks

**Problems:**

1. **Packet Loss:**
```
Client → [Network] → Server
   Request sent, never arrives

Client doesn't know:
- Did request get lost?
- Did response get lost?
- Is server slow or down?
```

2. **Network Partitions:**
```
Node A ←→ Node B ✓
Node A ←X Node C (partition!)

Node A and C can't communicate
But both think they're primary!
```

**Solution: Timeouts**
```ruby
begin
  response = HTTP.timeout(5).get('http://server/data')
rescue Net::ReadTimeout
  # Server didn't respond in 5 seconds
  # Retry or fail gracefully
end
```

**Problem with Timeouts:**
```
Too short: False positives (server is slow, not down)
Too long: Users wait unnecessarily

Solution: Exponential backoff
Retry 1: 1s timeout
Retry 2: 2s timeout
Retry 3: 4s timeout
```

---

#### Unreliable Clocks

**System Clocks (Time of Day):**
```ruby
# Based on NTP (Network Time Protocol)
Time.now  # → 2025-01-17 10:30:00

# Problem: Can jump backward!
# NTP sync: "Your clock is 30 seconds fast"
# Time goes backward!

# Bad for ordering events:
event_1 = { timestamp: Time.now, data: "A" }
sleep 1
event_2 = { timestamp: Time.now, data: "B" }

# If clock jumped backward between events:
# event_2.timestamp < event_1.timestamp (wrong order!)
```

**Monotonic Clocks (Elapsed Time):**
```ruby
# Based on CPU counter, always increases
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
# Do work
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

# Good for timeouts, durations
# Never jumps backward
# But not synchronized across machines!
```

**Clock Skew:**
```
Server A: 10:30:00
Server B: 10:30:05  (5 seconds ahead)

If both servers write events with timestamps:
A writes event at 10:30:03
B writes event at 10:30:02

Events out of order!
```

**Last Write Wins with Clock Skew:**
```ruby
# Server A (clock 5 seconds behind)
user.update!(name: "Alice", timestamp: Time.now)  # 10:30:00

# Server B (clock correct)
user.update!(name: "Bob", timestamp: Time.now)    # 10:30:05

# Last write wins (by timestamp)
# Bob's write (10:30:05) > Alice's write (10:30:00)
# Alice's update lost!

# But Alice's update happened later in real time!
```

**Solution: Logical Clocks (Lamport Timestamps)**
```ruby
# Each node maintains counter
# Increment on each event
# Send counter with messages

# Node A
counter_a = 0
counter_a += 1  # → 1
send_message(event: "A", counter: 1)

# Node B receives
counter_b = max(counter_b, received_counter) + 1

# Ordering based on counters, not wall-clock time
```

---

#### Process Pauses

**Problem:** Thread can pause mid-execution.

**Causes:**
1. **Garbage Collection** - Stop-the-world GC
2. **VM Suspension** - Hypervisor suspends VM
3. **OS Scheduling** - Process preempted
4. **Disk I/O** - Blocking read/write
5. **Swapping** - Memory paged to disk

**Example:**
```ruby
# Distributed lock
def with_lock(key, timeout: 10)
  lock = acquire_lock(key, ttl: timeout)

  # GC PAUSE FOR 15 SECONDS HERE!
  # Lock expired! Other process now has lock!

  yield  # Critical section

  release_lock(lock)  # Too late!
end

# Both processes think they have the lock!
```

**Solution: Fencing Tokens**
```ruby
# Incrementing token with each lock
lock_1 = acquire_lock("resource")  # token = 33
lock_2 = acquire_lock("resource")  # token = 34

# Storage rejects writes with old tokens
storage.write("resource", value, token: 33)  # ✗ Rejected (34 > 33)
storage.write("resource", value, token: 34)  # ✓ Accepted
```

---

### Interview Questions on Chapter 8

**Q1: What is a network partition?**

**Answer:**
"Network partition is when network failure splits cluster into isolated groups.

Example:
```
Node A ←→ Node B ✓
Node A ←X Node C (partition!)

A and B can communicate
A and C cannot
```

Problem: Split brain - both A and C think they're primary leader.

Solution:
1. **Quorum:** Require majority (2 of 3 nodes) to make decisions
2. **Fencing:** Use tokens to reject old writes
3. **ZooKeeper/etcd:** Consensus service to elect single leader

For Instabug: If using multi-datacenter replication, partition between datacenters is possible. Use quorum or designate one datacenter as authoritative."

**Q2: Why are unreliable clocks a problem?**

**Answer:**
"Clocks can't be trusted in distributed systems:

1. **Clock skew:** Different nodes have different times
   - Server A: 10:30:00
   - Server B: 10:30:05

2. **Clock jumps:** NTP sync can move time backward
   - Time 10:30:00 → NTP sync → Time 10:29:30

Problems:
- Last-write-wins uses timestamps (wrong if clocks skewed)
- Event ordering broken (event B has earlier timestamp than A but happened later)
- Timeouts/TTLs unreliable

Solutions:
- Use logical clocks (Lamport timestamps, version vectors) for ordering
- Use monotonic clocks for timeouts
- Use clock drift detection (reject nodes with excessive skew)

My chat app doesn't have this problem (single database, single source of time). But Instabug's multi-datacenter setup needs logical clocks for event ordering."

---

## Chapter 9: Consistency and Consensus

### Summary

How to build reliable systems from unreliable components. Consensus algorithms enable nodes to agree despite failures.

**Key Concepts:**
1. **Linearizability** - Strongest consistency guarantee
2. **Consensus** - Getting nodes to agree
3. **Atomic Commitment** - All nodes commit or all abort

### Key Concepts

#### Linearizability

**Definition:** Operations appear to take effect atomically at some point between start and completion.

**Example:**
```ruby
# Two clients, one register

Client A: write(x, 1) ──────────────────► (completed)
Client B: write(x, 2) ──► (completed)
Client C: read(x) → 2
Client D: read(x) → 2
Client E: read(x) → 1  # ✗ Impossible with linearizability!

# Once C sees x=2, all subsequent reads must see x=2 (or later value)
# Can't "go back in time" to x=1
```

**Linearizable vs Non-Linearizable:**

```ruby
# Linearizable (strong consistency)
# MySQL with master-slave, reading from master only

user.update!(balance: 100)  # Write to master
balance = user.balance      # Read from master → 100 ✓

# Non-linearizable (eventual consistency)
# Reading from replicas with lag

user.update!(balance: 100)  # Write to master
balance = user.using(:replica).balance  # Read from replica → 50 (stale!)

# Replica will eventually catch up, but not linearizable
```

**CAP Theorem:**
```
Can't have all three in presence of network partitions:
- Consistency (linearizability)
- Availability (every request gets non-error response)
- Partition tolerance (system works despite network failures)

Must choose 2:

CP: Consistent + Partition-tolerant
- Sacrifice availability
- Example: Wait for majority quorum (reject requests if can't reach majority)

AP: Available + Partition-tolerant
- Sacrifice consistency
- Example: Accept writes on both sides of partition (resolve conflicts later)

CA: Consistent + Available
- Sacrifice partition tolerance
- Example: Single datacenter (no partitions possible)
```

**Instabug Example:**
```ruby
# Bug reporting API: Choose AP (availability over consistency)
# Reason: Can't afford to reject bug reports due to partition
# Solution: Accept writes on both sides, use conflict-free counters

# User dashboard: Choose CP (consistency over availability)
# Reason: Better to show error than incorrect data
# Solution: Read from majority quorum
```

---

#### Consensus

**Problem:** Multiple nodes need to agree on a value.

**Use Cases:**
1. **Leader election** - Which node is leader?
2. **Atomic commit** - Did all nodes commit transaction?
3. **Configuration** - What's current cluster state?

**Properties:**
1. **Agreement** - All nodes decide on same value
2. **Integrity** - No node decides twice
3. **Validity** - If all nodes propose same value, that value is chosen
4. **Termination** - All non-faulty nodes eventually decide

**Raft Consensus Algorithm:**

```
Nodes: A, B, C (quorum = 2)

1. Election
   - Node A times out, becomes candidate
   - Requests votes from B and C
   - B and C vote for A
   - A becomes leader (got majority)

2. Log Replication
   - Client sends write to A (leader)
   - A appends to own log: [1: x=5]
   - A sends to B and C
   - B and C append: [1: x=5]
   - B and C send ack
   - A commits (got majority acks)
   - A responds to client: "write committed"
   - A sends commit notification to B and C

3. Failure Handling
   - If A crashes, B times out
   - B becomes candidate, requests votes
   - C votes for B
   - B becomes new leader
   - B has log [1: x=5], continues from there
```

**Used by:** etcd, Consul, ZooKeeper (uses similar Zab algorithm)

**My Chat App - Doesn't Need Consensus:**
```ruby
# Single MySQL master - no consensus needed
# If needed multi-master: Use etcd for leader election

# Example: Elect primary for counter generation
lock = Etcd.lock("counter_service", ttl: 10)
if lock.acquired?
  # This instance is primary
  # Generate sequential numbers
else
  # Forward requests to primary
end
```

**Instabug - Needs Consensus:**
```ruby
# Multi-datacenter deployment
# Use ZooKeeper for:
# 1. Leader election (which datacenter is authoritative)
# 2. Configuration management (cluster state)
# 3. Service discovery (which services are running where)
```

---

#### Two-Phase Commit (2PC)

**Problem:** Atomic commit across multiple databases.

**Example:**
```ruby
# Transfer money across two banks
Bank A: debit $100
Bank B: credit $100

# Both must commit or both must abort
```

**Protocol:**

```
Phase 1: Prepare
Coordinator → Participant A: "Can you commit?"
Coordinator → Participant B: "Can you commit?"

Participant A → Coordinator: "Yes" (locks resources)
Participant B → Coordinator: "Yes" (locks resources)

Phase 2: Commit
Coordinator → Participant A: "Commit"
Coordinator → Participant B: "Commit"

Participant A: Commits and releases locks
Participant B: Commits and releases locks
```

**Failure Scenarios:**

```
1. Participant votes "No"
   → Coordinator sends "Abort" to all

2. Coordinator crashes after prepare
   → Participants blocked (holding locks!)
   → Must wait for coordinator recovery

3. Coordinator crashes after commit decision
   → Participants commit anyway (decision in log)
```

**Problems:**
- ✅ Guarantees atomicity
- ❌ Blocking (participants wait for coordinator)
- ❌ Single point of failure (coordinator)
- ❌ High latency (two network round-trips)

**Alternative: Saga Pattern (Eventual Consistency)**
```ruby
# Instead of 2PC, use compensating transactions

# Step 1: Debit bank A
debit_result = BankA.debit(100)

# Step 2: Credit bank B
credit_result = BankB.credit(100)

# If step 2 fails:
# Compensating transaction: Credit back to bank A
if credit_result.failed?
  BankA.credit(100)  # Undo step 1
end

# Eventually consistent, but no distributed locking!
```

---

### Interview Questions on Chapter 9

**Q1: Explain the CAP theorem.**

**Answer:**
"CAP theorem: In presence of network partitions, can't have both consistency and availability - must choose one.

**Consistency:** All nodes see same data (linearizability)
**Availability:** Every request gets non-error response
**Partition tolerance:** System works despite network failures

Example:
```
Network partition: Nodes A and B can't communicate

CP (choose consistency):
- Reject writes unless can reach majority
- Some requests fail (sacrificing availability)
- Example: Banking (can't afford wrong balance)

AP (choose availability):
- Accept writes on both sides
- Resolve conflicts later (sacrificing consistency)
- Example: Shopping cart (better to accept item addition than error)
```

For Instabug: Bug ingestion is AP (can't afford to reject bug reports). User dashboard is CP (better to show error than wrong data)."

**Q2: What is consensus and why is it hard?**

**Answer:**
"Consensus is getting multiple nodes to agree on a value despite failures.

Hard because:
1. **Network unreliable:** Messages can be lost, delayed, duplicated
2. **Nodes can crash:** Mid-consensus
3. **Nodes can be slow:** Indistinguishable from crashed
4. **Clocks unreliable:** Can't use timeouts reliably

Solutions (Raft, Paxos):
- Use quorum (majority must agree)
- Leader election (one node coordinates)
- Log replication (persist decisions)
- Failure detection (heartbeats, timeouts)

Used for:
- Leader election (ZooKeeper)
- Distributed locks (etcd)
- Configuration management (Consul)

My chat app doesn't need it (single database). Instabug would use it for multi-datacenter coordination."

---

# Part III: Derived Data

## Chapter 10: Batch Processing

### Summary

Process large amounts of data offline, without serving user requests. Think MapReduce, Spark.

**Characteristics:**
- Input: Bounded dataset (entire log file, entire database table)
- Output: Derived data (reports, indices, aggregations)
- Performance: Throughput (not latency)

### Key Concepts

#### MapReduce

**Concept:** Process data in two phases - Map (transform) and Reduce (aggregate).

**Example: Word Count**

```ruby
# Input: Text documents
doc1: "Hello world"
doc2: "Hello Ruby"
doc3: "World of Ruby"

# Map phase (transform)
map(doc1) → [("Hello", 1), ("world", 1)]
map(doc2) → [("Hello", 1), ("Ruby", 1)]
map(doc3) → [("World", 1), ("of", 1), ("Ruby", 1)]

# Shuffle (group by key)
"Hello" → [(1), (1)]
"world" → [(1)]
"World" → [(1)]
"Ruby"  → [(1), (1)]
"of"    → [(1)]

# Reduce phase (aggregate)
reduce("Hello", [1, 1]) → 2
reduce("world", [1])    → 1
reduce("World", [1])    → 1
reduce("Ruby", [1, 1])  → 2
reduce("of", [1])       → 1

# Output
Hello: 2
world: 1
World: 1
Ruby: 2
of: 1
```

**Instabug Example: Aggregate Bug Counts by App**

```javascript
// Input: Bug events from database
{ app_id: "app_123", timestamp: "2025-01-17", type: "crash" }
{ app_id: "app_456", timestamp: "2025-01-17", type: "error" }
{ app_id: "app_123", timestamp: "2025-01-17", type: "crash" }

// Map phase
function map(event) {
  emit(event.app_id, 1);
}

// Shuffle
"app_123" → [1, 1]
"app_456" → [1]

// Reduce phase
function reduce(app_id, counts) {
  return sum(counts);
}

// Output
app_123: 2
app_456: 1
```

**Advantages:**
- ✅ Scalable (add more machines)
- ✅ Fault-tolerant (retry failed tasks)
- ✅ Simple programming model

**Disadvantages:**
- ❌ High latency (batch processing, not real-time)
- ❌ Requires entire dataset (can't process streams)

---

#### Join Patterns

**1. Reduce-Side Join (Sort-Merge Join):**

```ruby
# Input: Users and Activity logs
users:     { user_id: 1, name: "Alice" }
           { user_id: 2, name: "Bob" }
activity:  { user_id: 1, action: "click" }
           { user_id: 2, action: "view" }
           { user_id: 1, action: "purchase" }

# Map phase: Tag records and emit by join key
map(user) → [(user_id: 1, type: "user", data: "Alice")]
map(activity) → [(user_id: 1, type: "activity", data: "click")]

# Shuffle: Group by user_id
user_id 1 → [("user", "Alice"), ("activity", "click"), ("activity", "purchase")]
user_id 2 → [("user", "Bob"), ("activity", "view")]

# Reduce: Join
reduce(user_id 1, records) → ("Alice", "click"), ("Alice", "purchase")
reduce(user_id 2, records) → ("Bob", "view")
```

**2. Broadcast Join (Replicated Join):**

```ruby
# Small dataset (users) broadcast to all mappers
# Large dataset (activity) partitioned

# Mapper loads users into memory hash table
user_map = { 1 => "Alice", 2 => "Bob" }

# Mapper processes activity
map(activity) →
  user_name = user_map[activity.user_id]
  emit(user_name, activity)

# No shuffle needed! Join done in map phase
# Much faster if one dataset small enough to fit in memory
```

**Instabug Example: Join bugs with user info**
```sql
-- Reduce-side join
SELECT b.bug_id, u.email, b.stack_trace
FROM bugs b
JOIN users u ON b.user_id = u.user_id

-- Broadcast join (if users table small)
-- Broadcast users to all nodes
-- Each node has full user table in memory
```

---

### Interview Questions on Chapter 10

**Q1: Explain MapReduce.**

**Answer:**
"MapReduce is a programming model for processing large datasets in parallel.

Map phase: Transform each input record into key-value pairs
Shuffle: Group all values for same key together
Reduce phase: Aggregate values for each key

Example word count:
```
Map: doc → [(word, 1), (word, 1), ...]
Shuffle: Group by word
Reduce: Sum counts for each word
```

Advantages: Scalable (add machines), fault-tolerant (retry failed tasks)
Disadvantages: High latency (batch), requires entire dataset

For Instabug analytics (daily bug reports), MapReduce makes sense. For real-time dashboards, need stream processing."

**Q2: How do you join two large datasets in MapReduce?**

**Answer:**
"Two approaches:

**Reduce-side join (sort-merge):**
- Map both datasets, emit by join key
- Shuffle groups matching keys together
- Reduce performs join
- Works for any size datasets
- Requires shuffle (network overhead)

**Broadcast join:**
- Small dataset broadcast to all mappers (loaded in memory)
- Large dataset processed in map phase
- Map phase does lookup in in-memory hash table
- No shuffle needed!
- Only works if one dataset fits in memory

For Instabug: Join bugs (large) with apps (small) → use broadcast join (apps fit in memory)."

---

## Chapter 11: Stream Processing

### Summary

Process unbounded data (continuous stream of events) in real-time.

**Difference from Batch:**
- Input: Unbounded (never-ending stream)
- Timing: Real-time (process as data arrives)
- Use cases: Monitoring, alerting, real-time analytics

### Key Concepts

#### Message Brokers

**Purpose:** Buffer and route events between producers and consumers.

**Examples:** Kafka, RabbitMQ, Amazon Kinesis

**Kafka Architecture:**
```
Producers → Topic (partitioned) → Consumer Groups

Topic "bugs":
  Partition 0: [Event1, Event3, Event5, ...]
  Partition 1: [Event2, Event4, Event6, ...]
  Partition 2: [Event7, Event8, Event9, ...]

Consumer Group A:
  Consumer 1 reads Partition 0
  Consumer 2 reads Partition 1
  Consumer 3 reads Partition 2

Consumer Group B:
  Consumer 1 reads Partition 0, 1
  Consumer 2 reads Partition 2
```

**Kafka Guarantees:**
- Messages within partition are ordered
- Messages persisted to disk (durable)
- Consumers track offset (position in partition)

**My Chat App - Could Use Kafka:**
```ruby
# Instead of Sidekiq for job queue
# Produce events to Kafka
producer.produce({
  type: "message.created",
  chat_id: 123,
  number: 5,
  body: "Hello"
}, topic: "messages")

# Multiple consumers can process same event
# Consumer 1: Store to database
# Consumer 2: Index to Elasticsearch
# Consumer 3: Send notifications
# Consumer 4: Update analytics
```

---

#### Stream Processing Patterns

**1. Stateless Processing:**
```ruby
# Transform each event independently
stream.map do |event|
  {
    app_id: event[:app_id],
    bug_count: 1,
    timestamp: Time.now
  }
end
```

**2. Windows:**
```ruby
# Tumbling window (fixed, non-overlapping)
stream
  .window(size: 1.minute)
  .reduce { |sum, event| sum + 1 }

# Output: Count of events per minute

# Sliding window (overlapping)
stream
  .window(size: 1.minute, slide: 10.seconds)
  .reduce { |sum, event| sum + 1 }

# Output: Count of events in last minute, updated every 10 seconds
```

**3. Joins:**
```ruby
# Stream-stream join
clicks = stream("clicks")
purchases = stream("purchases")

clicks
  .join(purchases, within: 1.hour)
  .where { |click, purchase| click.user_id == purchase.user_id }

# Output: Clicks that led to purchase within 1 hour

# Stream-table join
bugs = stream("bugs")
apps = table("applications")  # Change log stream compacted into table

bugs.join(apps) { |bug| bug.app_id }

# Output: Bugs enriched with app metadata
```

**Instabug Example:**
```ruby
# Real-time crash rate monitoring
stream("bug_events")
  .filter { |event| event[:type] == "crash" }
  .window(size: 5.minutes, slide: 1.minute)
  .groupBy { |event| event[:app_id] }
  .count
  .filter { |app_id, count| count > 100 }
  .forEach { |app_id, count|
    alert("High crash rate for #{app_id}: #{count} crashes in 5 minutes")
  }
```

---

#### Event Time vs Processing Time

**Processing Time:** When event processed by stream processor
**Event Time:** When event actually occurred (timestamp in event)

**Problem:**
```
Event 1: occurred 10:00, processed 10:05 (5 min delay)
Event 2: occurred 10:02, processed 10:03 (1 min delay)

If using processing time:
10:00-10:01 window: []
10:01-10:02 window: []
10:02-10:03 window: [Event 2]
10:03-10:04 window: []
10:04-10:05 window: []
10:05-10:06 window: [Event 1]  # Wrong window!

If using event time:
10:00-10:01 window: [Event 1]  # Correct!
10:01-10:02 window: []
10:02-10:03 window: [Event 2]  # Correct!
```

**Watermarks:** Track progress of event time
```
Watermark = "All events with timestamp < T have been seen"

Example:
Watermark advances to 10:03
→ Can close 10:00-10:01 window (no more events for that window)
→ Output results for 10:00-10:01 window

Late events (timestamp < watermark) can be:
- Dropped
- Sent to late-data side output
- Included with late results flag
```

---

### Interview Questions on Chapter 11

**Q1: Difference between batch and stream processing?**

**Answer:**
"Batch processing:
- Input: Bounded (entire dataset)
- Timing: Offline (process when convenient)
- Latency: Minutes to hours
- Use case: Daily reports, analytics
- Example: MapReduce job running overnight

Stream processing:
- Input: Unbounded (continuous events)
- Timing: Real-time (process as arrives)
- Latency: Milliseconds to seconds
- Use case: Monitoring, alerting, real-time dashboards
- Example: Crash rate monitoring

For Instabug: Use batch for daily bug reports (MapReduce). Use stream for real-time crash alerts (Kafka + Flink)."

**Q2: Explain event time vs processing time.**

**Answer:**
"Event time: When event occurred (timestamp in event payload)
Processing time: When event processed by system

Differ due to:
1. Network delays
2. Queueing
3. System failures (replay old events)

Example:
```
Event timestamp: 10:00 (event time)
Processed at: 10:05 (processing time)
Delay: 5 minutes
```

Use event time for:
- Accurate windows (count bugs in last hour based on when they occurred)
- Correct ordering

Use processing time for:
- Monitoring system itself
- When event time not available

Challenge: Late events (event time < current watermark). Solution: Allow late events for configurable grace period."

---

## Chapter 12: The Future of Data Systems

### Summary

Trends and future directions for data-intensive applications.

**Key Ideas:**
1. **Unbundling databases** - Compose specialized components
2. **Dataflow across systems** - Event logs as integration mechanism
3. **End-to-end data flow** - Derived data kept in sync

### Key Concepts

#### Lambda Architecture

**Concept:** Combine batch and stream processing.

```
                     ┌─→ Batch Layer (MapReduce)
                     │      ↓
Incoming Events ─────┤   Batch Views (precomputed)
                     │
                     └─→ Speed Layer (Stream Processing)
                            ↓
                         Real-time Views

Serving Layer: Merge batch + real-time views
```

**Example for Instabug:**
```ruby
# Batch layer (run overnight)
# Compute bug counts per app for all history
MapReduce:
  Input: All bugs from database
  Output: app_id → total_bugs (stored in Cassandra)

# Speed layer (real-time)
# Compute bug counts for last 24 hours
Stream Processing:
  Input: Bug events from Kafka
  Output: app_id → bugs_last_24h (stored in Redis)

# Serving layer (query time)
total_bugs = cassandra.get(app_id)      # Batch layer
recent_bugs = redis.get(app_id)         # Speed layer
combined = total_bugs + recent_bugs     # Merge
```

**Challenges:**
- ❌ Maintaining two codebases (batch + stream)
- ❌ Eventual consistency between layers
- ❌ Complexity

---

#### Kappa Architecture

**Concept:** Stream processing only (no batch layer).

```
Incoming Events → Kafka (infinite retention)
                    ↓
                  Stream Processing (Flink, Spark Streaming)
                    ↓
                  Materialized Views
```

**Reprocessing:**
```
If stream processing logic changes:
1. Deploy new version consuming from offset 0
2. Reprocess entire history from Kafka
3. Switch traffic to new version
4. Shutdown old version
```

**Advantage:**
- ✅ Single codebase (stream processing only)
- ✅ Simpler than Lambda

**Disadvantage:**
- ❌ Requires stream processor that can handle full reprocessing

**Instabug Example:**
```ruby
# All bug events in Kafka (retained forever)
# Stream processor computes materialized views:
#  - Bug count per app
#  - Crash rate per app
#  - Top errors

# If add new view (e.g., crash rate by OS version):
#  - Deploy new stream processor starting from offset 0
#  - Recomputes view from full history
```

---

#### Change Data Capture (CDC)

**Concept:** Treat database as event log. Capture all changes as stream.

```
Database Writes → Transaction Log (WAL)
                        ↓
                   CDC Tool (Debezium)
                        ↓
                   Event Stream (Kafka)
                        ↓
            ┌───────────┴────────────┐
            ↓                        ↓
    Elasticsearch              Data Warehouse
   (search index)              (analytics)
```

**Benefits:**
- All derived data stays in sync
- Low latency (near real-time)
- No dual writes (database is source of truth)

**Example:**
```ruby
# PostgreSQL WAL
INSERT INTO messages (chat_id, number, body) VALUES (1, 5, 'Hello')

# CDC captures change
{
  operation: "INSERT",
  table: "messages",
  data: { chat_id: 1, number: 5, body: "Hello" }
}

# Kafka topic "db.messages"
Consumers:
  - Elasticsearch consumer: Index message for search
  - Redis consumer: Invalidate cache
  - Webhook consumer: Notify clients
```

**My Chat App Could Use This:**
```ruby
# Instead of manually indexing to Elasticsearch in job:

# 1. Write to MySQL only
Message.create!(chat_id: 1, number: 5, body: "Hello")

# 2. CDC captures change from MySQL WAL
# 3. Streams to Kafka
# 4. Elasticsearch consumer indexes automatically

# Benefits:
# - Single write path (MySQL only)
# - Elasticsearch eventually consistent (acceptable)
# - Can add new consumers without changing code
```

---

### Interview Questions on Chapter 12

**Q1: What is Lambda architecture?**

**Answer:**
"Lambda architecture combines batch and stream processing:

**Batch layer:** Process full dataset overnight (accurate but slow)
**Speed layer:** Process recent data real-time (fast but approximate)
**Serving layer:** Merge both for queries

Example for Instabug:
- Batch: Nightly MapReduce computes bug counts from full history
- Speed: Real-time stream processing counts today's bugs
- Serving: Total = batch_count + stream_count

Pros: Combines accuracy of batch with speed of stream
Cons: Two codebases to maintain, eventual consistency

Alternative: Kappa architecture (stream only, reprocess from Kafka when needed)"

**Q2: What is change data capture (CDC)?**

**Answer:**
"CDC treats database as event log - captures all changes as stream.

How it works:
1. Database writes to transaction log (WAL)
2. CDC tool (Debezium) reads WAL
3. Publishes changes to Kafka
4. Consumers update derived data (Elasticsearch, cache, data warehouse)

Benefits:
- Database is single source of truth
- Derived data stays in sync
- Low latency (near real-time)
- No dual writes (one write path)

For my chat app:
Instead of manually indexing messages to Elasticsearch in Sidekiq job, CDC would automatically stream changes from MySQL to Kafka to Elasticsearch consumer. Simpler, more reliable."

---

## Summary: Key Takeaways for Instabug Interview

### Most Important Concepts

**1. Replication (Chapter 5)**
- Single-leader: Master-slave replication
- Multi-leader: Multi-datacenter with conflict resolution
- Leaderless: Quorum reads/writes (Cassandra)
- **Instabug:** Multi-datacenter → Multi-leader or leaderless

**2. Partitioning (Chapter 6)**
- Hash partitioning: Even distribution
- Range partitioning: Efficient range queries, hotspots possible
- **Instabug:** Partition bug events by app_id (hash)

**3. Consistency Trade-offs (Chapter 9)**
- CAP theorem: Choose consistency or availability during partition
- Linearizability: Strongest consistency
- Eventual consistency: High availability
- **Instabug:** Bug ingestion (AP), dashboard (CP)

**4. Storage Engines (Chapter 3)**
- LSM-trees: Write-optimized (Cassandra)
- B-trees: Read-optimized (MySQL, PostgreSQL)
- **Instabug:** Write-heavy event ingestion → LSM-trees

**5. Stream Processing (Chapter 11)**
- Real-time event processing
- Windowing, aggregations
- **Instabug:** Crash rate monitoring, real-time alerts

### How This Applies to Your Chat App

| Concept | Your Chat App | Instabug Scale |
|---------|---------------|----------------|
| **Replication** | Could use MySQL master-slave | Multi-datacenter active-active |
| **Partitioning** | Not needed (1M records) | Essential (1B+ events) |
| **Storage** | MySQL (B-tree) for reads | Cassandra (LSM) for writes |
| **Consistency** | Strong (single DB) | Eventual (distributed) |
| **Processing** | Sidekiq (queue) | Kafka + Flink (stream) |

### Interview Strategy

**For each question, follow this pattern:**

1. **Current implementation (chat app):**
   "My chat app uses MySQL with B-tree indexes..."

2. **Why it works:**
   "For 1M records, single database handles it..."

3. **How to scale (Instabug):**
   "For Instabug's 1B events, I'd partition by app_id using Cassandra..."

4. **Trade-offs:**
   "This gives high write throughput but eventual consistency..."

Good luck with your Instabug interview! You now understand the foundational concepts from "Designing Data-Intensive Applications"! 🚀

