# Technical Interview Preparation Guide
## Kafka, System Design, Problem Solving, Ruby on Rails & Go

---

## Table of Contents
1. [Apache Kafka](#apache-kafka)
2. [System Design Principles](#system-design-principles)
3. [Problem Solving & Coding](#problem-solving--coding)
4. [Mock Interview Scenarios](#mock-interview-scenarios)
5. [Teaching & Communication Skills](#teaching--communication-skills)
6. [Ruby on Rails Deep Dive](#ruby-on-rails-deep-dive)
7. [Go (Golang) Deep Dive](#go-golang-deep-dive)
8. [Interview Tips & Best Practices](#interview-tips--best-practices)

---

## Apache Kafka

### What is Kafka?
Apache Kafka is a **distributed event streaming platform** used for building real-time data pipelines and streaming applications. It's designed to handle high-throughput, fault-tolerant, publish-subscribe messaging.

### Core Concepts

#### 1. **Topics**
- Logical channels where records are published
- Topics are partitioned for scalability
- Example: `user-events`, `payment-transactions`, `chat-messages`

```
Topic: user-events
├── Partition 0: [msg1, msg2, msg3]
├── Partition 1: [msg4, msg5, msg6]
└── Partition 2: [msg7, msg8, msg9]
```

#### 2. **Producers**
- Applications that publish (write) data to topics
- Can specify partition key for ordered delivery
- Example: Rails app publishing chat messages

```ruby
# Ruby producer example (using ruby-kafka gem)
require 'kafka'

kafka = Kafka.new(['localhost:9092'])
producer = kafka.producer

producer.produce("User created account", topic: "user-events")
producer.deliver_messages
```

#### 3. **Consumers**
- Applications that subscribe to (read) data from topics
- Organized into **consumer groups** for parallel processing
- Each partition is consumed by exactly one consumer in a group

```ruby
# Ruby consumer example
consumer = kafka.consumer(group_id: "chat-processor")
consumer.subscribe("chat-messages")

consumer.each_message do |message|
  puts "Received: #{message.value}"
end
```

#### 4. **Partitions**
- Topics are split into partitions for parallelism
- Messages with the same key go to the same partition (ordering guarantee)
- More partitions = higher throughput

#### 5. **Offsets**
- Unique ID for each message within a partition
- Consumers track their position (offset) in each partition
- Enables replay and fault tolerance

### Kafka Architecture

```
Producers                    Kafka Cluster                    Consumers
   │                              │                              │
   ├──> Topic: orders ──────> Broker 1 (Leader) ────────────> Consumer Group A
   │         ├─ Partition 0       │                              │
   │         ├─ Partition 1   Broker 2 (Replica) ──────────> Consumer Group B
   │         └─ Partition 2       │
   │                           Broker 3 (Replica)
   └──> Topic: payments           │
             └─ Partition 0    ZooKeeper (Coordination)
```

### Key Features

1. **High Throughput**: Millions of messages/sec
2. **Scalability**: Add brokers/partitions as needed
3. **Durability**: Configurable replication (default: 3 replicas)
4. **Fault Tolerance**: Auto-failover if broker dies
5. **Retention**: Keep messages for days/weeks (configurable)

### Common Use Cases

| Use Case | Why Kafka? | Example |
|----------|-----------|---------|
| **Event Sourcing** | Immutable event log | User actions, state changes |
| **Log Aggregation** | Centralized logging | Collect logs from 100s of services |
| **Stream Processing** | Real-time analytics | Fraud detection, recommendations |
| **Messaging** | Decoupling services | Microservices communication |
| **CDC (Change Data Capture)** | Database replication | Sync MySQL → Elasticsearch |

### Kafka vs Other Systems

| Feature | Kafka | RabbitMQ | Redis Pub/Sub |
|---------|-------|----------|---------------|
| **Message Retention** | Days/weeks | Until consumed | No retention |
| **Throughput** | Very High (1M+/sec) | Medium (100K/sec) | High (500K/sec) |
| **Ordering** | Per-partition guarantee | Queue-based | No guarantee |
| **Replay** | Yes (offset-based) | No | No |
| **Best For** | Event streaming, logs | Task queues | Real-time notifications |

### Kafka in This Chat App (How You Could Use It)

```ruby
# Scenario: Process chat messages asynchronously

# 1. Producer: Rails API publishes message event
class MessagesController < ApplicationController
  def create
    # Quick response - don't wait for processing
    kafka_producer.produce(
      params[:body],
      topic: "chat-messages",
      key: params[:chat_token] # Same chat → same partition → ordering
    )

    render json: { status: "queued" }, status: 202
  end
end

# 2. Consumer: Go service processes from Kafka
func main() {
    consumer := kafka.NewConsumer(...)
    consumer.Subscribe("chat-messages")

    for msg := range consumer.Messages() {
        // Process message
        saveToElasticsearch(msg.Value)
        updateChatCounts(msg.Key)
    }
}
```

### Interview Questions on Kafka

**Q: How does Kafka ensure message ordering?**
- Messages are ordered within a partition (not across partitions)
- Use partition keys to route related messages to same partition
- Example: All messages for `chat_123` use chat_token as key

**Q: What happens if a consumer crashes?**
- Kafka rebalances: other consumers in the group take over partitions
- Consumer resumes from last committed offset
- May reprocess some messages if offset not committed

**Q: How do you handle duplicate messages?**
- Kafka guarantees "at-least-once" delivery by default
- Make consumers **idempotent** (process same message multiple times safely)
- Use unique message IDs or database constraints

**Q: When would you choose Kafka over RabbitMQ?**
- Need message replay/retention (log aggregation)
- Very high throughput requirements (millions/sec)
- Building event-driven architecture with multiple consumers
- Don't choose Kafka for: simple task queues, low message volume

---

## System Design Principles

### The Design Process (45-60 minutes)

#### 1. **Clarify Requirements (5-10 min)**
Ask questions before jumping to solution!

**Functional Requirements:**
- What features are needed?
- Who are the users?
- What scale are we targeting?

**Non-Functional Requirements:**
- Latency expectations?
- Consistency vs Availability trade-offs?
- Read-heavy or write-heavy?

**Example: Design a Chat System**
```
Good Questions:
- 1-on-1 chat or group chat?
- How many daily active users?
- Should messages be encrypted?
- Need read receipts/typing indicators?
- File attachments supported?
- Message retention policy?
```

#### 2. **Back-of-the-Envelope Estimation (5 min)**

```
Assumptions:
- 100M daily active users (DAU)
- Each user sends 20 messages/day
- Average message size: 1KB

Calculations:
Messages/day = 100M * 20 = 2B messages/day
Messages/sec = 2B / 86,400 ≈ 23,000 msg/sec
Peak traffic (3x) ≈ 70,000 msg/sec

Storage/day = 2B * 1KB = 2TB/day
Storage/year = 2TB * 365 ≈ 730TB

Bandwidth = 70,000 * 1KB = 70MB/sec
```

#### 3. **High-Level Design (10-15 min)**

Draw boxes and arrows showing major components.

```
┌─────────┐          ┌──────────────┐          ┌──────────┐
│ Clients │ ────────>│ Load Balancer│────────>│  API     │
│(Mobile) │          │   (Nginx)    │          │ Servers  │
└─────────┘          └──────────────┘          └────┬─────┘
                                                     │
                     ┌───────────────────────────────┼─────────┐
                     │                               │         │
                 ┌───▼────┐    ┌─────────┐    ┌─────▼─────┐   │
                 │ MySQL  │    │  Redis  │    │ Kafka     │   │
                 │(Users) │    │(Session)│    │(Messages) │   │
                 └────────┘    └─────────┘    └─────┬─────┘   │
                                                     │         │
                                              ┌──────▼──────┐  │
                                              │ Message     │  │
                                              │ Processor   │  │
                                              └──────┬──────┘  │
                                                     │         │
                                              ┌──────▼──────┐  │
                                              │Elasticsearch│  │
                                              │  (Search)   │  │
                                              └─────────────┘  │
```

#### 4. **Deep Dive (15-20 min)**

Interviewer picks areas to explore. Be ready to discuss:

**Database Schema:**
```sql
-- Users table
CREATE TABLE users (
  id BIGINT PRIMARY KEY,
  username VARCHAR(50) UNIQUE,
  created_at TIMESTAMP
);

-- Chats table
CREATE TABLE chats (
  id BIGINT PRIMARY KEY,
  type ENUM('direct', 'group'),
  created_at TIMESTAMP
);

-- Messages table (partitioned by date)
CREATE TABLE messages (
  id BIGINT PRIMARY KEY,
  chat_id BIGINT,
  sender_id BIGINT,
  body TEXT,
  created_at TIMESTAMP,
  INDEX idx_chat_created (chat_id, created_at)
) PARTITION BY RANGE (TO_DAYS(created_at));
```

**API Design:**
```
POST /api/chats                    # Create chat
GET  /api/chats/:id/messages       # List messages (paginated)
POST /api/chats/:id/messages       # Send message
GET  /api/messages/search?q=hello  # Search messages
```

**Scaling Strategies:**
1. **Database**: Sharding by user_id or chat_id
2. **Caching**: Redis for recent messages, user sessions
3. **CDN**: Static assets, user avatars
4. **Microservices**: Split auth, messaging, search
5. **Message Queue**: Kafka for async processing

#### 5. **Address Bottlenecks (10 min)**

Identify and solve potential issues:

**Problem 1: Database Hotspots**
- Some chats are very active (celebrity group)
- Solution: Cache hot chats in Redis, read replicas

**Problem 2: Message Delivery**
- How to deliver messages to offline users?
- Solution: WebSockets for online, push notifications for offline

**Problem 3: Search Performance**
- Full-text search on MySQL is slow
- Solution: Elasticsearch with async indexing via Kafka

### CAP Theorem

In distributed systems, you can only have 2 of 3:

```
        Consistency
            /\
           /  \
          /    \
         /  CP  \
        / (MySQL)\
       /          \
      /____________\
Partition      Availability
Tolerance       /\
(Network)      /AP\
              /(Cassandra)
```

- **CP (Consistent + Partition Tolerant)**: MySQL, MongoDB
  - Strong consistency, may reject writes during network splits

- **AP (Available + Partition Tolerant)**: Cassandra, DynamoDB
  - Always available, eventual consistency

- **CA (Consistent + Available)**: Single-node databases (not realistic for distributed)

### Common System Design Patterns

#### 1. **Rate Limiting**
```python
# Token bucket algorithm
class RateLimiter:
    def __init__(self, rate, capacity):
        self.rate = rate          # tokens/second
        self.capacity = capacity  # max tokens
        self.tokens = capacity
        self.last_update = time.now()

    def allow_request(self):
        now = time.now()
        elapsed = now - self.last_update

        # Refill tokens
        self.tokens = min(self.capacity,
                         self.tokens + elapsed * self.rate)
        self.last_update = now

        if self.tokens >= 1:
            self.tokens -= 1
            return True
        return False
```

#### 2. **Consistent Hashing**
Used for distributing data across servers

```
Hash Ring (0-360°):
Server A: 45°
Server B: 120°
Server C: 280°

User123 → hash → 100° → routes to Server B (next server clockwise)

If Server B dies:
User123 → 100° → routes to Server C
Only users between A and B are affected!
```

#### 3. **Database Sharding**

**Horizontal Partitioning:**
```
Shard by user_id % 4:

Shard 0: users 0, 4, 8, 12...
Shard 1: users 1, 5, 9, 13...
Shard 2: users 2, 6, 10, 14...
Shard 3: users 3, 7, 11, 15...
```

**Challenges:**
- Cross-shard queries are expensive
- Rebalancing when adding shards
- Hotspots if data is skewed

#### 4. **Caching Strategies**

```
┌──────────┐
│  Client  │
└────┬─────┘
     │
     ▼
┌─────────────┐  Cache Miss  ┌──────────┐
│   Cache     │─────────────>│ Database │
│  (Redis)    │<─────────────│ (MySQL)  │
└─────────────┘  Write Back  └──────────┘
```

**Cache-Aside (Lazy Loading):**
```ruby
def get_user(user_id)
  # Try cache first
  user = redis.get("user:#{user_id}")
  return JSON.parse(user) if user

  # Cache miss - query DB
  user = User.find(user_id)
  redis.setex("user:#{user_id}", 3600, user.to_json)
  user
end
```

**Write-Through:**
```ruby
def update_user(user_id, data)
  # Update DB and cache together
  user = User.find(user_id).update!(data)
  redis.setex("user:#{user_id}", 3600, user.to_json)
end
```

**Write-Behind (Write-Back):**
```ruby
def update_user(user_id, data)
  # Update cache immediately
  redis.setex("user:#{user_id}", 3600, data.to_json)

  # Async DB update
  UpdateUserJob.perform_later(user_id, data)
end
```

### Design Examples

#### Design URL Shortener (like bit.ly)

**Requirements:**
- Shorten URLs: `https://example.com/long/path` → `bit.ly/abc123`
- 100M URLs created per day
- Read-heavy (100:1 read/write ratio)

**API:**
```
POST /shorten    { url: "https://..." } → { short_url: "abc123" }
GET  /:code      Redirect to original URL
GET  /:code/stats Click count, analytics
```

**Schema:**
```sql
CREATE TABLE urls (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  short_code VARCHAR(10) UNIQUE,
  original_url TEXT,
  created_at TIMESTAMP,
  click_count INT DEFAULT 0,
  INDEX idx_code (short_code)
);
```

**Short Code Generation:**
```ruby
# Base62 encoding (a-z, A-Z, 0-9)
def encode(id)
  CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  code = ""
  while id > 0
    code = CHARS[id % 62] + code
    id /= 62
  end
  code
end

# Example: ID 125 → "cb"
```

**Architecture:**
```
Load Balancer
    ├─> API Server 1 ──┐
    ├─> API Server 2 ──┼─> MySQL (Write Master)
    └─> API Server 3 ──┘        │
                                ├─> Read Replica 1
                                └─> Read Replica 2

    Redis (Cache hot URLs)
```

**Scaling:**
- Cache top 20% of URLs (80/20 rule)
- Database sharding by short_code hash
- CDN for static assets
- Rate limiting per user

---

## Problem Solving & Coding

### Problem-Solving Framework

#### 1. **Understand the Problem**
- Restate problem in your own words
- Ask clarifying questions
- Identify inputs and outputs
- Check edge cases

**Example: "Find duplicates in an array"**
```
Clarifying Questions:
- Can I modify the input array?
- What's the expected time/space complexity?
- Are duplicates consecutive?
- How should I return results (all duplicates or just one)?

Edge Cases:
- Empty array → []
- No duplicates → []
- All duplicates → [1,1,1,1]
- Large arrays (10^6 elements)
```

#### 2. **Devise a Plan**
- Think out loud
- Start with brute force, then optimize
- Consider data structures: hash, set, stack, queue, heap
- Consider algorithms: two pointers, sliding window, divide & conquer

#### 3. **Execute**
- Write clean, readable code
- Use meaningful variable names
- Add comments for complex logic
- Test with examples as you go

#### 4. **Test & Optimize**
- Walk through code with test cases
- Check edge cases
- Analyze time/space complexity
- Discuss trade-offs

### Common Coding Patterns

#### Pattern 1: Two Pointers

**Problem: Check if string is palindrome**
```ruby
def palindrome?(s)
  left, right = 0, s.length - 1

  while left < right
    return false if s[left] != s[right]
    left += 1
    right -= 1
  end

  true
end

# Time: O(n), Space: O(1)
```

**Problem: Two Sum (sorted array)**
```ruby
def two_sum(arr, target)
  left, right = 0, arr.length - 1

  while left < right
    sum = arr[left] + arr[right]
    return [left, right] if sum == target
    sum < target ? left += 1 : right -= 1
  end

  nil
end
```

#### Pattern 2: Sliding Window

**Problem: Longest substring without repeating characters**
```ruby
def longest_unique_substring(s)
  char_index = {}
  max_length = 0
  start = 0

  s.chars.each_with_index do |char, end_idx|
    # If char seen and within current window
    if char_index[char] && char_index[char] >= start
      start = char_index[char] + 1
    end

    char_index[char] = end_idx
    max_length = [max_length, end_idx - start + 1].max
  end

  max_length
end

# "abcabcbb" → 3 ("abc")
# Time: O(n), Space: O(min(n, charset))
```

#### Pattern 3: Hash Map for Counting

**Problem: First non-repeating character**
```ruby
def first_non_repeating(s)
  counts = Hash.new(0)

  # Count occurrences
  s.chars.each { |c| counts[c] += 1 }

  # Find first with count 1
  s.chars.each { |c| return c if counts[c] == 1 }

  nil
end

# "leetcode" → "l"
# Time: O(n), Space: O(1) - max 26 letters
```

#### Pattern 4: Stack for Balanced Structures

**Problem: Valid parentheses**
```ruby
def valid_parentheses?(s)
  stack = []
  pairs = { '(' => ')', '[' => ']', '{' => '}' }

  s.chars.each do |char|
    if pairs.key?(char)
      stack.push(char)
    elsif pairs.values.include?(char)
      return false if stack.empty? || pairs[stack.pop] != char
    end
  end

  stack.empty?
end

# "([])" → true
# "([)]" → false
```

#### Pattern 5: Binary Search

**Problem: Find element in rotated sorted array**
```ruby
def search_rotated(arr, target)
  left, right = 0, arr.length - 1

  while left <= right
    mid = (left + right) / 2
    return mid if arr[mid] == target

    # Left half sorted?
    if arr[left] <= arr[mid]
      if arr[left] <= target && target < arr[mid]
        right = mid - 1
      else
        left = mid + 1
      end
    else # Right half sorted
      if arr[mid] < target && target <= arr[right]
        left = mid + 1
      else
        right = mid - 1
      end
    end
  end

  -1
end

# [4,5,6,7,0,1,2], target=0 → 4
# Time: O(log n)
```

### Ruby-Specific Tricks

```ruby
# 1. Array operations
arr = [1, 2, 3, 4, 5]
arr.sum                           # 15
arr.max                           # 5
arr.tally                         # {1=>1, 2=>1, 3=>1, 4=>1, 5=>1}
arr.each_cons(2).to_a            # [[1,2], [2,3], [3,4], [4,5]]
arr.combination(2).to_a          # All pairs

# 2. Hash default values
counts = Hash.new(0)
counts['a'] += 1                 # No need to check if key exists

# 3. Enumerable methods
(1..10).select(&:even?)          # [2, 4, 6, 8, 10]
(1..10).reduce(:+)               # 55
['a', 'bb', 'ccc'].max_by(&:length)  # "ccc"

# 4. String manipulation
"hello".chars.reverse.join       # "olleh"
"hello".scan(/\w/)              # ["h", "e", "l", "l", "o"]
```

### Go-Specific Tricks

```go
// 1. Slices
arr := []int{1, 2, 3, 4, 5}
sum := 0
for _, val := range arr {
    sum += val
}

// 2. Maps
counts := make(map[rune]int)
for _, ch := range "hello" {
    counts[ch]++
}

// 3. Two pointers pattern
func reverse(s []byte) {
    left, right := 0, len(s)-1
    for left < right {
        s[left], s[right] = s[right], s[left]
        left++
        right--
    }
}

// 4. String building (efficient)
var sb strings.Builder
for i := 0; i < 100; i++ {
    sb.WriteString("hello")
}
result := sb.String()

// 5. Sorting
sort.Slice(arr, func(i, j int) bool {
    return arr[i] < arr[j]
})
```

---

## Mock Interview Scenarios

### Scenario 1: System Design - Design Instagram

**Time: 45 minutes**

**Interviewer Opening:**
"Design a photo-sharing service like Instagram. Users can upload photos, follow other users, and see a feed of photos from people they follow."

**Your Approach:**

**1. Clarify (5 min):**
```
You: "Let me clarify the requirements:
- How many users are we targeting?
- Should we support videos or just images?
- Do we need features like likes, comments, and stories?
- What's more important: upload speed or feed loading speed?
- Any geographic considerations?

Interviewer: "100M DAU, images only for now, yes to likes/comments,
feed loading is critical, global service."
```

**2. Estimate (5 min):**
```
You: "Let me do some quick calculations:
- 100M DAU, assume 10% upload daily = 10M photos/day
- Average photo size = 2MB (original), 200KB (compressed)
- Storage/day = 10M * 200KB = 2TB/day
- Storage/year = 730TB
- Each user views 50 photos/day → 5B photo views/day
- Bandwidth = 5B * 200KB / 86400 ≈ 12GB/sec"
```

**3. High-Level Design (15 min):**

Draw on whiteboard:
```
┌──────────┐
│  Client  │
│ (Mobile) │
└────┬─────┘
     │
┌────▼──────────┐         ┌──────────────┐
│  CDN          │         │ Load Balancer│
│ (CloudFront)  │         └──────┬───────┘
└───────────────┘                │
                          ┌──────▼──────┐
                          │  API Servers│
                          └──────┬──────┘
                                 │
          ┌──────────────────────┼─────────────┐
          │                      │             │
    ┌─────▼─────┐         ┌──────▼──────┐    ┌▼────────┐
    │  S3       │         │  MySQL      │    │ Redis   │
    │ (Photos)  │         │ (Metadata)  │    │ (Cache) │
    └───────────┘         └─────────────┘    └─────────┘
```

**API Design:**
```
POST   /photos              # Upload photo
GET    /feed               # Get user feed
POST   /follow/:user_id    # Follow user
GET    /photos/:id         # Get photo details
POST   /photos/:id/like    # Like photo
```

**Database Schema:**
```sql
users (id, username, email, created_at)
photos (id, user_id, s3_url, caption, created_at)
follows (follower_id, followee_id)
likes (user_id, photo_id, created_at)
```

**4. Deep Dive (15 min):**

**Interviewer: "How would you generate the feed?"**

```
You: "There are two main approaches:

Approach 1: Fan-out on Write (Push)
- When user posts photo, add to all followers' feeds immediately
- Pros: Fast feed reads (pre-computed)
- Cons: Slow writes for celebrities (1M followers = 1M writes)

Approach 2: Fan-out on Read (Pull)
- When user opens app, query all followees for recent photos
- Pros: Fast writes, no wasted work for inactive users
- Cons: Slow feed reads (many joins)

Hybrid Approach (Instagram's actual solution):
- Normal users: fan-out on write
- Celebrities: fan-out on read
- Combine both results when loading feed"

Schema:
CREATE TABLE feed_items (
  user_id BIGINT,          -- whose feed
  photo_id BIGINT,         -- which photo
  created_at TIMESTAMP,
  PRIMARY KEY (user_id, created_at)
);
```

**Interviewer: "How do you handle photo uploads at scale?"**

```
You: "Multi-step process:

1. Client uploads to API server
2. API server uploads original to S3
3. Trigger async image processing (Lambda/Sidekiq):
   - Generate thumbnails (150x150, 640x640)
   - Compress images (reduce quality 85%)
   - Extract EXIF data (location, camera)
4. Store metadata in MySQL
5. Invalidate CDN if needed

For faster uploads:
- Presigned URLs: Client uploads directly to S3
- Multipart upload for large files
- Progressive JPEGs (load blurry → sharp)"
```

### Scenario 2: Coding - Tree Problems

**Interviewer:** "Given a binary tree, find the maximum path sum. A path can start and end at any node."

**Your Solution:**

```ruby
class TreeNode
  attr_accessor :val, :left, :right
  def initialize(val)
    @val = val
    @left = @right = nil
  end
end

def max_path_sum(root)
  @max_sum = -Float::INFINITY
  max_gain(root)
  @max_sum
end

# Returns max gain if continuing path through node
def max_gain(node)
  return 0 if node.nil?

  # Recursively get max gain from left and right
  left_gain = [max_gain(node.left), 0].max
  right_gain = [max_gain(node.right), 0].max

  # Update global max (path through this node)
  path_sum = node.val + left_gain + right_gain
  @max_sum = [@max_sum, path_sum].max

  # Return max gain if continuing path
  node.val + [left_gain, right_gain].max
end

# Example tree:
#      10
#     /  \
#    2   10
#   / \    \
#  20  1   -25
#           / \
#          3   4
#
# Max path: 20 → 2 → 10 → 10 = 42

# Time: O(n) - visit each node once
# Space: O(h) - recursion stack height
```

**Walking Through Your Solution:**
```
You: "Let me explain my approach:

1. We need a helper function that returns the max gain if we
   continue the path through a node.

2. At each node, we have 4 options:
   - Just the node itself
   - Node + left path
   - Node + right path
   - Node + left + right (can't continue up)

3. We track the global maximum separately, checking if the
   path through this node (left + node + right) is better.

4. But we return max(left, right) + node because we can only
   continue the path in one direction upward.

Let me trace through with an example..."
```

### Scenario 3: Behavioral - Teaching Code

**Interviewer:** "Tell me about a time you had to explain a complex technical concept to someone."

**STAR Method Response:**

**Situation:**
"In my current role, I built a chat application with a complex race condition solution using Redis atomic operations. A junior developer joined and needed to understand the system."

**Task:**
"I needed to explain why we couldn't use a simple counter and how Redis INCR solved our duplicate message number problem."

**Action:**
"I used a three-step teaching approach:

1. **Started with the problem:** I showed them what happens with naive code:
```ruby
# Bad - race condition!
count = redis.get('count').to_i
count += 1
redis.set('count', count)
# Two threads both read 5, both write 6!
```

2. **Demonstrated the issue:** I wrote a simple script that spawned 100 threads creating messages simultaneously, showing duplicate numbers appearing.

3. **Explained the solution:** I walked through Redis INCR being atomic:
```ruby
# Good - atomic operation
new_number = redis.incr('chat:123:message_count')
# Guaranteed unique even with 1000 concurrent requests
```

4. **Visual analogy:** I compared it to taking a ticket at the DMV - the machine guarantees sequential numbers even if 10 people press the button simultaneously."

**Result:**
"The junior developer not only understood the solution but later identified a similar race condition in our user counter code and fixed it proactively. They also presented the concept at our team knowledge-sharing session."

**Key Takeaway:**
"I learned that effective teaching requires starting with concrete problems, showing real failures, then building up to the solution. Analogies help bridge the gap between abstract concepts and real-world understanding."

---

## Teaching & Communication Skills

### How to Explain Code Effectively

#### 1. **Start with the "Why" Before the "How"**

❌ **Bad:**
"This code uses Redis INCR to increment a counter atomically."

✅ **Good:**
"We had a problem: when two users create messages at the same time, they might get duplicate numbers. To solve this, we use Redis INCR which guarantees atomic increments even under high concurrency."

#### 2. **Use Analogies**

**Explaining Databases:**
- **SQL Database:** Like Excel with strict rules - every row has exact columns
- **NoSQL (MongoDB):** Like a filing cabinet - flexible documents
- **Redis:** Like sticky notes on your desk - fast but temporary

**Explaining Caching:**
```
"Imagine you're a librarian:
- Without cache: Walk to shelf every time someone asks for a book
- With cache: Keep popular books on your desk for instant access
- Cache invalidation: Knowing when to return a book to the shelf"
```

**Explaining CAP Theorem:**
```
"It's like a restaurant:
- Consistency: All waiters see the same menu
- Availability: Restaurant never closes
- Partition Tolerance: Kitchens in different buildings

You can't have all three. If buildings lose connection (partition):
- Choose consistency: Close one kitchen until connection restored
- Choose availability: Both kitchens operate independently (might serve different menus)"
```

#### 3. **Build Up Complexity Gradually**

**Teaching Kafka (Layered Approach):**

**Level 1 - Basic:**
"Kafka is like a message board where apps post messages and other apps read them."

**Level 2 - Intermediate:**
"Kafka stores messages in topics (like categories). When you post a message, it stays there for days, so multiple apps can read it at different times."

**Level 3 - Advanced:**
"Topics are partitioned for parallelism. Messages with the same key go to the same partition, guaranteeing order. Each partition has replicas across brokers for fault tolerance."

#### 4. **Show, Don't Just Tell**

**Example: Teaching Database Indexing**

```ruby
# Without index - slow!
User.where(email: 'john@example.com')  # Scans all 1M rows

# Explain what happens:
# 1. MySQL reads row 1: email='alice@...', nope
# 2. MySQL reads row 2: email='bob@...', nope
# ...
# 3. MySQL reads row 500,000: email='john@...', found!
# Time: O(n) - linear scan

# Add index
add_index :users, :email

# Now:
# MySQL checks index (B-tree) in O(log n) time
# Index points directly to row 500,000
# Time: 10ms → 0.5ms (20x faster!)

# Visual:
# Index is like a book's index - jump directly to page instead of
# reading cover-to-cover
```

#### 5. **Use Diagrams**

**Request Flow Diagram:**
```
Client Request → Load Balancer → Server → Cache?
                                    ├─ Yes → Return (fast!)
                                    └─ No  → Database → Cache → Return
```

**Draw While Explaining:**
- Start with simple boxes
- Add connections
- Label data flow
- Show failure scenarios

#### 6. **Encourage Questions**

Create checkpoints:
- "Does that make sense so far?"
- "What questions do you have about this part?"
- "Would an example help here?"

#### 7. **Relate to Their Experience**

**Teaching React to Rails Developer:**
"You know how Rails has partials (_header.html.erb)? React components are similar - reusable pieces of UI. The difference is React components are JavaScript functions that return HTML-like syntax called JSX."

### Teaching Code Review Best Practices

**Good Code Review Comments:**

❌ **Bad:** "This is wrong."

✅ **Good:**
"This could cause a race condition. If two requests arrive simultaneously, both might read the same counter value before incrementing. Consider using Redis INCR which is atomic. Example: `redis.incr(key)`"

**Template:**
1. **What:** Identify the issue
2. **Why:** Explain the problem
3. **How:** Suggest a solution
4. **Example:** Provide code snippet

---

## Ruby on Rails Deep Dive

### Rails Architecture (MVC)

```
┌─────────────────────────────────────────────┐
│              Browser Request                 │
│        GET /chats/5/messages                │
└─────────────────┬───────────────────────────┘
                  │
        ┌─────────▼──────────┐
        │   Routes            │
        │ (config/routes.rb) │
        └─────────┬───────────┘
                  │
        ┌─────────▼──────────────────┐
        │   Controller               │
        │ ChatsController#show       │
        │ - Handles request          │
        │ - Calls model              │
        │ - Prepares data            │
        └─────────┬──────────────────┘
                  │
        ┌─────────▼──────────┐
        │   Model             │
        │ Chat.find(5)        │
        │ - Business logic    │
        │ - Database queries  │
        │ - Validations       │
        └─────────┬───────────┘
                  │
        ┌─────────▼──────────┐
        │   View              │
        │ show.html.erb       │
        │ - Render HTML       │
        │ - Display data      │
        └─────────────────────┘
```

### Key Rails Concepts

#### 1. **Active Record (ORM)**

Maps database tables to Ruby classes:

```ruby
# app/models/chat.rb
class Chat < ApplicationRecord
  # Associations
  belongs_to :application
  has_many :messages, dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :chat_number, uniqueness: { scope: :application_id }

  # Scopes (reusable queries)
  scope :recent, -> { order(created_at: :desc) }
  scope :with_messages, -> { joins(:messages).distinct }

  # Instance method
  def full_name
    "#{application.name} - Chat ##{chat_number}"
  end

  # Class method
  def self.active_chats
    where('messages_count > 0')
  end
end

# Usage:
chat = Chat.find(1)
chat.messages.create(body: "Hello")
Chat.recent.with_messages.limit(10)
```

**Query Interface:**
```ruby
# SQL generated by ActiveRecord
Chat.where(application_id: 5).order(created_at: :desc).limit(10)
# SELECT * FROM chats WHERE application_id = 5 ORDER BY created_at DESC LIMIT 10

# Joins
Chat.joins(:messages).where(messages: { body: 'hello' })
# SELECT chats.* FROM chats
# INNER JOIN messages ON messages.chat_id = chats.id
# WHERE messages.body = 'hello'

# Eager loading (N+1 query prevention)
chats = Chat.includes(:messages).limit(10)
chats.each do |chat|
  puts chat.messages.count  # No additional queries!
end
```

#### 2. **Controllers**

Handle HTTP requests:

```ruby
# app/controllers/chats_controller.rb
class ChatsController < ApplicationController
  before_action :set_application
  before_action :set_chat, only: [:show, :update, :destroy]

  # GET /applications/:app_token/chats
  def index
    @chats = @application.chats.includes(:messages)
    render json: @chats, include: :messages
  end

  # POST /applications/:app_token/chats
  def create
    @chat = @application.chats.new(chat_params)

    if @chat.save
      render json: @chat, status: :created
    else
      render json: @chat.errors, status: :unprocessable_entity
    end
  end

  # PATCH /applications/:app_token/chats/:chat_number
  def update
    if @chat.update(chat_params)
      render json: @chat
    else
      render json: @chat.errors, status: :unprocessable_entity
    end
  end

  private

  def set_application
    @application = Application.find_by!(token: params[:application_token])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Application not found' }, status: :not_found
  end

  def set_chat
    @chat = @application.chats.find_by!(chat_number: params[:chat_number])
  end

  def chat_params
    params.require(:chat).permit(:name)
  end
end
```

**Strong Parameters (Security):**
```ruby
# Prevents mass assignment vulnerabilities
params.require(:chat).permit(:name, :description)

# Nested attributes
params.require(:chat).permit(:name, messages_attributes: [:body])

# Arrays
params.require(:chat).permit(:name, tags: [])
```

#### 3. **Routes**

Map URLs to controllers:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # RESTful resources
  resources :applications, param: :token do
    resources :chats, param: :chat_number do
      resources :messages, param: :message_number
    end
  end

  # Custom routes
  get 'search', to: 'messages#search'
  post 'applications/:token/chats/:chat_number/messages/bulk',
       to: 'messages#bulk_create'

  # API namespace
  namespace :api do
    namespace :v1 do
      resources :chats
    end
  end
end

# Generated routes:
# GET    /applications/:token/chats                 → chats#index
# POST   /applications/:token/chats                 → chats#create
# GET    /applications/:token/chats/:chat_number    → chats#show
# PATCH  /applications/:token/chats/:chat_number    → chats#update
# DELETE /applications/:token/chats/:chat_number    → chats#destroy
```

#### 4. **Migrations**

Version control for database schema:

```ruby
# db/migrate/20250118_create_chats.rb
class CreateChats < ActiveRecord::Migration[7.0]
  def change
    create_table :chats do |t|
      t.references :application, null: false, foreign_key: true
      t.integer :chat_number, null: false
      t.string :name
      t.integer :messages_count, default: 0
      t.timestamps
    end

    add_index :chats, [:application_id, :chat_number], unique: true
  end
end

# Run migrations:
# rails db:migrate
```

**Common Migration Operations:**
```ruby
# Add column
add_column :chats, :description, :text

# Add index
add_index :chats, :name

# Change column
change_column :chats, :name, :string, null: false

# Rename column
rename_column :chats, :name, :title

# Remove column
remove_column :chats, :description
```

#### 5. **Background Jobs (Sidekiq)**

Process tasks asynchronously:

```ruby
# app/jobs/create_message_job.rb
class CreateMessageJob < ApplicationJob
  queue_as :default

  def perform(chat_id, message_body)
    chat = Chat.find(chat_id)
    message = chat.messages.create!(body: message_body)

    # Index in Elasticsearch
    MessageIndexer.perform_async(message.id)
  end
end

# Enqueue job:
CreateMessageJob.perform_later(chat.id, "Hello")

# Enqueue for specific time:
CreateMessageJob.set(wait: 1.hour).perform_later(chat.id, "Reminder")
```

#### 6. **Validations**

Ensure data integrity:

```ruby
class Message < ApplicationRecord
  validates :body, presence: true, length: { minimum: 1, maximum: 500 }
  validates :message_number, uniqueness: { scope: :chat_id }
  validate :body_not_spam

  private

  def body_not_spam
    if body&.downcase&.include?('viagra')
      errors.add(:body, "contains spam keywords")
    end
  end
end

# Usage:
message = Message.new(body: "")
message.valid?  # false
message.errors.full_messages  # ["Body can't be blank"]
```

#### 7. **Serializers (JSON API)**

Control JSON output:

```ruby
# app/serializers/chat_serializer.rb
class ChatSerializer < ActiveModel::Serializer
  attributes :chat_number, :name, :messages_count, :created_at

  belongs_to :application
  has_many :messages

  def created_at
    object.created_at.iso8601
  end
end

# Usage in controller:
render json: @chat, serializer: ChatSerializer
```

### Rails Performance Tips

#### 1. **N+1 Query Problem**

```ruby
# Bad - N+1 queries
chats = Chat.limit(10)
chats.each do |chat|
  puts chat.application.name  # Queries database 10 times!
end
# SELECT * FROM chats LIMIT 10
# SELECT * FROM applications WHERE id = 1
# SELECT * FROM applications WHERE id = 2
# ... (10 queries total)

# Good - Eager loading
chats = Chat.includes(:application).limit(10)
chats.each do |chat|
  puts chat.application.name  # No additional queries
end
# SELECT * FROM chats LIMIT 10
# SELECT * FROM applications WHERE id IN (1,2,3,...)
# (2 queries total)
```

#### 2. **Counter Cache**

```ruby
# Migration
add_column :chats, :messages_count, :integer, default: 0

# Model
class Message < ApplicationRecord
  belongs_to :chat, counter_cache: true
end

# Now chat.messages.count uses cached value instead of COUNT(*) query
```

#### 3. **Database Indexes**

```ruby
# Slow query
Message.where(chat_id: 5).order(created_at: :desc)

# Add index
add_index :messages, [:chat_id, :created_at]

# Now query uses index (much faster!)
```

#### 4. **Fragment Caching**

```erb
<!-- app/views/chats/show.html.erb -->
<% cache @chat do %>
  <h1><%= @chat.name %></h1>
  <p><%= @chat.messages.count %> messages</p>
<% end %>

<!-- Cached HTML, regenerates only when @chat updates -->
```

### Rails Interview Questions

**Q: Explain the difference between `has_many :through` and `has_and_belongs_to_many`**

```ruby
# has_and_belongs_to_many (simple, no join model)
class User < ApplicationRecord
  has_and_belongs_to_many :groups
end

class Group < ApplicationRecord
  has_and_belongs_to_many :users
end

# Join table: users_groups (id not needed)
# No additional attributes on join

# has_many :through (flexible, join model exists)
class User < ApplicationRecord
  has_many :memberships
  has_many :groups, through: :memberships
end

class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :group
  # Can have additional fields!
  # joined_at, role, etc.
end

class Group < ApplicationRecord
  has_many :memberships
  has_many :users, through: :memberships
end

# Use :through when you need metadata on the relationship
```

**Q: What's the difference between `find` and `find_by`?**

```ruby
User.find(999)          # Raises ActiveRecord::RecordNotFound
User.find_by(id: 999)   # Returns nil

# Use find when you expect the record to exist (show page)
# Use find_by when existence is uncertain (search)
```

---

## Go (Golang) Deep Dive

### Go Basics

#### 1. **Project Structure**

```
my-go-project/
├── cmd/
│   └── server/
│       └── main.go          # Entry point
├── internal/                # Private application code
│   ├── handlers/
│   │   └── message.go       # HTTP handlers
│   ├── models/
│   │   └── message.go       # Data structures
│   └── database/
│       └── mysql.go         # DB connection
├── pkg/                     # Public libraries
│   └── utils/
│       └── response.go
├── go.mod                   # Dependency management
└── go.sum                   # Dependency checksums
```

#### 2. **Key Language Features**

**Structs (like classes):**
```go
type Message struct {
    ID          int64     `json:"id"`
    ChatID      int64     `json:"chat_id"`
    Body        string    `json:"body"`
    CreatedAt   time.Time `json:"created_at"`
}

// Methods on structs
func (m *Message) Validate() error {
    if m.Body == "" {
        return errors.New("body cannot be empty")
    }
    return nil
}

// Usage
msg := Message{ChatID: 1, Body: "Hello"}
err := msg.Validate()
```

**Interfaces:**
```go
// Interface definition
type MessageStore interface {
    Create(msg *Message) error
    FindByID(id int64) (*Message, error)
    List(chatID int64) ([]*Message, error)
}

// MySQL implementation
type MySQLStore struct {
    db *sql.DB
}

func (s *MySQLStore) Create(msg *Message) error {
    query := "INSERT INTO messages (chat_id, body) VALUES (?, ?)"
    result, err := s.db.Exec(query, msg.ChatID, msg.Body)
    if err != nil {
        return err
    }
    id, _ := result.LastInsertId()
    msg.ID = id
    return nil
}

// Redis implementation (same interface!)
type RedisStore struct {
    client *redis.Client
}

func (s *RedisStore) Create(msg *Message) error {
    // Different implementation, same interface
}

// Usage - can swap implementations easily
var store MessageStore
store = &MySQLStore{db: db}
// OR
store = &RedisStore{client: redisClient}

store.Create(&msg)  // Works with either!
```

**Error Handling:**
```go
// Go doesn't have exceptions - return errors explicitly
func CreateMessage(chatID int64, body string) (*Message, error) {
    if body == "" {
        return nil, errors.New("body required")
    }

    msg := &Message{ChatID: chatID, Body: body}
    err := db.Save(msg)
    if err != nil {
        return nil, fmt.Errorf("failed to save: %w", err)
    }

    return msg, nil
}

// Usage
msg, err := CreateMessage(1, "Hello")
if err != nil {
    log.Printf("Error: %v", err)
    return
}
fmt.Printf("Created: %+v\n", msg)
```

#### 3. **Concurrency (Goroutines & Channels)**

**Goroutines (lightweight threads):**
```go
func main() {
    // Synchronous (blocks)
    processMessage(msg1)
    processMessage(msg2)

    // Asynchronous (doesn't block)
    go processMessage(msg1)  // Runs in background
    go processMessage(msg2)  // Runs in parallel

    time.Sleep(2 * time.Second)  // Wait for goroutines
}

func processMessage(msg Message) {
    fmt.Printf("Processing: %s\n", msg.Body)
}
```

**Channels (communication between goroutines):**
```go
func main() {
    jobs := make(chan Message, 100)     // Buffered channel
    results := make(chan string, 100)

    // Start 5 worker goroutines
    for i := 0; i < 5; i++ {
        go worker(jobs, results)
    }

    // Send 20 jobs
    for i := 0; i < 20; i++ {
        jobs <- Message{Body: fmt.Sprintf("Message %d", i)}
    }
    close(jobs)

    // Collect results
    for i := 0; i < 20; i++ {
        result := <-results
        fmt.Println(result)
    }
}

func worker(jobs <-chan Message, results chan<- string) {
    for msg := range jobs {
        // Process message
        time.Sleep(100 * time.Millisecond)
        results <- fmt.Sprintf("Processed: %s", msg.Body)
    }
}
```

**WaitGroup (wait for multiple goroutines):**
```go
func main() {
    var wg sync.WaitGroup

    for i := 0; i < 10; i++ {
        wg.Add(1)
        go func(id int) {
            defer wg.Done()
            processMessage(id)
        }(i)
    }

    wg.Wait()  // Block until all goroutines finish
    fmt.Println("All done!")
}
```

#### 4. **HTTP Server**

```go
package main

import (
    "encoding/json"
    "log"
    "net/http"
)

type Message struct {
    ID   int64  `json:"id"`
    Body string `json:"body"`
}

func main() {
    http.HandleFunc("/messages", messagesHandler)
    http.HandleFunc("/messages/", messageHandler)

    log.Println("Server starting on :8080")
    log.Fatal(http.ListenAndServe(":8080", nil))
}

func messagesHandler(w http.ResponseWriter, r *http.Request) {
    if r.Method == "GET" {
        // List messages
        messages := []Message{
            {ID: 1, Body: "Hello"},
            {ID: 2, Body: "World"},
        }

        w.Header().Set("Content-Type", "application/json")
        json.NewEncoder(w).Encode(messages)

    } else if r.Method == "POST" {
        // Create message
        var msg Message
        if err := json.NewDecoder(r.Body).Decode(&msg); err != nil {
            http.Error(w, err.Error(), http.StatusBadRequest)
            return
        }

        // Save to database...
        msg.ID = 123

        w.WriteHeader(http.StatusCreated)
        json.NewEncoder(w).Encode(msg)
    }
}

func messageHandler(w http.ResponseWriter, r *http.Request) {
    // GET /messages/123
    id := r.URL.Path[len("/messages/"):]

    msg := Message{ID: 123, Body: "Found message " + id}
    json.NewEncoder(w).Encode(msg)
}
```

**Using Gorilla Mux (better routing):**
```go
import "github.com/gorilla/mux"

func main() {
    r := mux.NewRouter()

    r.HandleFunc("/messages", listMessages).Methods("GET")
    r.HandleFunc("/messages", createMessage).Methods("POST")
    r.HandleFunc("/messages/{id}", getMessage).Methods("GET")

    http.ListenAndServe(":8080", r)
}

func getMessage(w http.ResponseWriter, r *http.Request) {
    vars := mux.Vars(r)
    id := vars["id"]

    // Use id...
}
```

#### 5. **Database Operations**

```go
import (
    "database/sql"
    _ "github.com/go-sql-driver/mysql"
)

func main() {
    // Connect
    db, err := sql.Open("mysql", "user:password@tcp(localhost:3306)/chatdb")
    if err != nil {
        log.Fatal(err)
    }
    defer db.Close()

    // Create
    createMessage(db, 1, "Hello from Go!")

    // Read
    msg, _ := getMessageByID(db, 1)
    fmt.Printf("Message: %+v\n", msg)

    // List
    messages, _ := listMessages(db, 1)
    for _, m := range messages {
        fmt.Printf("ID: %d, Body: %s\n", m.ID, m.Body)
    }
}

func createMessage(db *sql.DB, chatID int64, body string) (int64, error) {
    query := "INSERT INTO messages (chat_id, body) VALUES (?, ?)"
    result, err := db.Exec(query, chatID, body)
    if err != nil {
        return 0, err
    }
    return result.LastInsertId()
}

func getMessageByID(db *sql.DB, id int64) (*Message, error) {
    query := "SELECT id, chat_id, body FROM messages WHERE id = ?"

    var msg Message
    err := db.QueryRow(query, id).Scan(&msg.ID, &msg.ChatID, &msg.Body)
    if err != nil {
        return nil, err
    }
    return &msg, nil
}

func listMessages(db *sql.DB, chatID int64) ([]*Message, error) {
    query := "SELECT id, chat_id, body FROM messages WHERE chat_id = ?"

    rows, err := db.Query(query, chatID)
    if err != nil {
        return nil, err
    }
    defer rows.Close()

    var messages []*Message
    for rows.Next() {
        var msg Message
        if err := rows.Scan(&msg.ID, &msg.ChatID, &msg.Body); err != nil {
            return nil, err
        }
        messages = append(messages, &msg)
    }

    return messages, nil
}
```

#### 6. **Testing**

```go
// message_test.go
package main

import "testing"

func TestMessageValidation(t *testing.T) {
    tests := []struct {
        name    string
        msg     Message
        wantErr bool
    }{
        {"valid message", Message{Body: "Hello"}, false},
        {"empty body", Message{Body: ""}, true},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            err := tt.msg.Validate()
            if (err != nil) != tt.wantErr {
                t.Errorf("Validate() error = %v, wantErr %v", err, tt.wantErr)
            }
        })
    }
}

// Benchmark
func BenchmarkCreateMessage(b *testing.B) {
    for i := 0; i < b.N; i++ {
        CreateMessage(1, "test")
    }
}

// Run tests:
// go test
// go test -bench=.
```

### Go vs Ruby Comparison

| Feature | Ruby (Rails) | Go |
|---------|--------------|-----|
| **Type System** | Dynamic | Static (compile-time) |
| **Speed** | ~50ms/request | ~5ms/request (10x faster) |
| **Concurrency** | Threads (GIL limits) | Goroutines (true parallelism) |
| **Memory** | ~100MB/process | ~20MB/process |
| **Learning Curve** | Easy | Moderate |
| **Best For** | CRUD APIs, rapid development | High-performance, concurrent tasks |

**When to Use Go in Your Chat App:**
```ruby
# Rails: Great for CRUD operations
class ChatsController < ApplicationController
  def create
    @chat = Chat.create!(chat_params)
    render json: @chat
  end
end

# Go: Great for high-throughput writes
func CreateMessage(w http.ResponseWriter, r *http.Request) {
    // Handle 10,000 concurrent requests easily
    // Redis INCR for message numbers
    // Fast Elasticsearch indexing
}
```

### Go Interview Questions

**Q: Explain the difference between a pointer and a value receiver**

```go
type Counter struct {
    count int
}

// Value receiver - operates on copy
func (c Counter) IncrementValue() {
    c.count++  // Modifies copy, original unchanged
}

// Pointer receiver - operates on original
func (c *Counter) IncrementPointer() {
    c.count++  // Modifies original
}

func main() {
    c := Counter{count: 0}

    c.IncrementValue()
    fmt.Println(c.count)  // 0 (unchanged)

    c.IncrementPointer()
    fmt.Println(c.count)  // 1 (modified)
}

// Rule of thumb: Use pointer receivers when:
// 1. Method modifies the receiver
// 2. Struct is large (avoid copying)
// 3. Consistency (if one method uses *, all should)
```

**Q: How do you handle graceful shutdown?**

```go
func main() {
    srv := &http.Server{Addr: ":8080"}

    // Start server in goroutine
    go func() {
        if err := srv.ListenAndServe(); err != nil {
            log.Println(err)
        }
    }()

    // Wait for interrupt signal
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, os.Interrupt)
    <-quit

    // Graceful shutdown (finish current requests)
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    if err := srv.Shutdown(ctx); err != nil {
        log.Fatal("Server forced to shutdown:", err)
    }

    log.Println("Server exiting gracefully")
}
```

---

## Interview Tips & Best Practices

### General Tips

1. **Think Out Loud**
   - Share your thought process
   - Discuss trade-offs
   - Ask clarifying questions

2. **Start Simple, Then Optimize**
   - Brute force first
   - Identify bottlenecks
   - Optimize iteratively

3. **Communicate Clearly**
   - Use analogies
   - Draw diagrams
   - Check understanding

4. **Practice Common Patterns**
   - Two pointers
   - Sliding window
   - Hash maps
   - Binary search
   - DFS/BFS

5. **Know Your Complexity**
   - Always state time and space complexity
   - O(1), O(log n), O(n), O(n²)

### Technical Depth by Level

**Junior Engineer:**
- Master one language deeply
- Understand CRUD operations
- Basic data structures (arrays, hashes)
- Simple algorithms (sorting, searching)

**Mid-Level Engineer:**
- Multiple languages/frameworks
- System design basics
- Database optimization (indexes, N+1)
- Caching strategies
- Testing best practices

**Senior Engineer:**
- Architectural decisions
- Scalability patterns
- Trade-off analysis (CAP, consistency)
- Mentoring/teaching ability
- Production debugging

### Resources to Study

**Books:**
- "Designing Data-Intensive Applications" (System Design)
- "Cracking the Coding Interview" (Algorithms)
- "The Go Programming Language" (Go)
- "Agile Web Development with Rails" (Rails)

**Practice:**
- LeetCode (algorithms)
- System Design Primer (GitHub)
- Real projects (like this chat app!)

---

## Summary

This guide covers:
- ✅ **Kafka**: Event streaming, producers/consumers, use cases
- ✅ **System Design**: CAP theorem, scaling, caching, patterns
- ✅ **Problem Solving**: Common patterns, Ruby/Go tricks
- ✅ **Mock Scenarios**: System design, coding, behavioral
- ✅ **Teaching**: Effective communication, analogies, mentoring
- ✅ **Ruby on Rails**: MVC, ActiveRecord, performance
- ✅ **Go**: Concurrency, HTTP servers, interfaces

**Final Advice:**
- Practice explaining your chat app project thoroughly
- Use real-world examples from your codebase
- Show passion and curiosity
- Be honest about what you don't know
- Ask great questions

Good luck with your interview! 🚀
