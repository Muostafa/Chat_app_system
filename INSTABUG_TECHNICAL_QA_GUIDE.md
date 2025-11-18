# Instabug Technical Interview Q&A Guide
## Backend II - Complete Question Bank with Answers

---

## Table of Contents
1. [Core Backend / System Design](#1-core-backend--system-design)
2. [Databases & Storage](#2-databases--storage)
3. [Practical Backend Coding](#3-practical-backend-coding)
4. [Concurrency & Performance](#4-concurrency--performance)
5. [Microservices & Architecture](#5-microservices--architecture)
6. [DevOps Knowledge](#6-devops-knowledge)
7. [Monitoring, Logging, and Observability](#7-monitoring-logging-and-observability)
8. [Backend Language Knowledge](#8-backend-language-knowledge)
9. [Culture Fit (Technical Judgment)](#9-culture-fit-technical-judgment)

---

## 1. Core Backend / System Design

### API Design & Architecture

#### Q: Design a rate-limited API for receiving bug reports from mobile apps.

**Answer:**

**Requirements Analysis:**
- Millions of mobile apps sending bug reports
- Need to prevent abuse/DDoS
- Different rate limits per subscription tier
- Must be fast (< 50ms response)
- Fair quota distribution

**Design:**

```ruby
# 1. Token Bucket Algorithm (like my chat app's Redis counters)
class RateLimiter
  def initialize(redis)
    @redis = redis
  end

  # Check if request is allowed
  def allow?(api_key, limit: 100, window: 60)
    key = "rate_limit:#{api_key}:#{Time.now.to_i / window}"

    current = @redis.incr(key)
    @redis.expire(key, window) if current == 1

    current <= limit
  end
end

# 2. API Controller with rate limiting
class BugReportsController < ApplicationController
  before_action :check_rate_limit

  def create
    # Enqueue to background job (async like my chat app)
    ProcessBugReportJob.perform_async(params[:bug_data])
    render json: { status: 'accepted' }, status: :accepted
  end

  private

  def check_rate_limit
    api_key = request.headers['X-API-Key']
    tier = get_tier(api_key)  # free: 100/min, pro: 1000/min, enterprise: unlimited

    unless rate_limiter.allow?(api_key, limit: tier[:limit])
      render json: {
        error: 'Rate limit exceeded',
        retry_after: 60
      }, status: :too_many_requests
    end
  end
end
```

**Architecture:**
```
Mobile Apps (millions)
    │
    ├─> Load Balancer (nginx)
    │       │
    ├───────┼────> API Server 1 ─┐
    │       │                      │
    └───────┴────> API Server N ─┤
                                  │
                                  ├─> Redis (rate limit counters)
                                  │
                                  └─> Kafka/SQS (bug report queue)
                                         │
                                         └─> Worker Pool
                                               │
                                               ├─> Parse & validate
                                               ├─> Store in S3/DB
                                               └─> Trigger notifications
```

**Key Features:**
1. **Sliding Window** - More accurate than fixed window
2. **Distributed** - Redis shared across API servers
3. **Async Processing** - Accept quickly, process later (like my chat app)
4. **Graceful Degradation** - Return 429 instead of dropping requests
5. **Tiered Limits** - Different quotas per subscription

**Connection to my project:**
"In my chat app, I use Redis INCR for sequential numbering - same atomic operation works for rate limiting. The async pattern (accept request → enqueue → return) is identical to my message creation flow."

---

#### Q: How would you design an API for uploading large attachments (videos, logs, screenshots)?

**Answer:**

**Approach: Multi-part Upload with Pre-signed URLs**

```ruby
# Step 1: Client requests upload URL
class AttachmentsController < ApplicationController
  def create_upload_url
    # Validate file metadata
    filename = params[:filename]
    content_type = params[:content_type]
    size = params[:size].to_i

    # Size limits
    return render json: { error: 'File too large' }, status: :bad_request if size > 500.megabytes

    # Generate S3 pre-signed URL (expires in 1 hour)
    s3 = Aws::S3::Resource.new
    object = s3.bucket('instabug-attachments').object("#{SecureRandom.uuid}/#{filename}")

    presigned_url = object.presigned_url(:put,
      expires_in: 3600,
      content_type: content_type,
      acl: 'private'
    )

    # Create pending attachment record
    attachment = Attachment.create!(
      key: object.key,
      filename: filename,
      size: size,
      status: 'pending'
    )

    render json: {
      upload_url: presigned_url,
      attachment_id: attachment.id,
      expires_at: 1.hour.from_now
    }
  end

  # Step 2: Client uploads directly to S3
  # Step 3: Client confirms upload completion
  def confirm_upload
    attachment = Attachment.find(params[:id])

    # Verify file exists in S3
    if s3_object_exists?(attachment.key)
      attachment.update!(status: 'uploaded')

      # Enqueue background job for virus scanning, thumbnail generation
      ProcessAttachmentJob.perform_async(attachment.id)

      render json: { status: 'success' }
    else
      render json: { error: 'Upload not found' }, status: :not_found
    end
  end
end
```

**Architecture:**
```
Mobile App
    │
    ├─> 1. POST /attachments/upload_url
    │      ← Returns pre-signed S3 URL
    │
    ├─> 2. PUT to S3 directly (bypasses API)
    │      (Multipart upload for large files)
    │
    └─> 3. POST /attachments/:id/confirm
           ← API verifies & processes
```

**Benefits:**
- **Scalability** - S3 handles upload traffic, not API servers
- **Cost** - No bandwidth through API servers
- **Resume** - Multipart upload supports resume
- **Security** - Pre-signed URL expires, temporary access only

**For Very Large Files (> 500MB):**
```ruby
# Multipart upload with chunking
def initiate_multipart
  s3.create_multipart_upload(...)

  # Return array of pre-signed URLs for each part
  parts = (1..num_parts).map do |part|
    {
      part_number: part,
      upload_url: presigned_url_for_part(part)
    }
  end

  render json: { upload_id: upload_id, parts: parts }
end
```

**Connection to my project:**
"Similar to my async message creation - API validates and returns immediately, heavy lifting (file processing) happens in background jobs."

---

#### Q: Explain REST vs GraphQL. Which would you choose for Instabug's APIs and why?

**Answer:**

**REST (my chat app uses this):**

**Pros:**
- ✅ Simple, well-understood
- ✅ Cacheable (HTTP caching works)
- ✅ Stateless
- ✅ Good for CRUD operations

**Cons:**
- ❌ Over-fetching (get whole object when you need one field)
- ❌ Under-fetching (multiple requests for related data)
- ❌ Versioning challenges (`/v1`, `/v2`)

**GraphQL:**

**Pros:**
- ✅ Fetch exactly what you need (no over-fetching)
- ✅ Single endpoint
- ✅ Strongly typed schema
- ✅ Great for complex, nested data

**Cons:**
- ❌ Harder to cache
- ❌ More complex to implement
- ❌ Can expose too much (N+1 query issues)
- ❌ Harder to rate-limit (queries vary)

**My Choice for Instabug: Hybrid Approach**

```
REST for:
- Bug report ingestion (high volume, simple)
  POST /v1/bugs

- Attachment uploads (standard HTTP)
  POST /v1/attachments

GraphQL for:
- Dashboard/web interface (complex queries)
  query {
    project(id: "123") {
      bugs(status: OPEN, limit: 10) {
        title
        stackTrace
        user { email, device }
        attachments { thumbnailUrl }
      }
    }
  }
```

**Reasoning:**
1. **Ingest API (REST)** - Mobile SDKs send millions of events. REST is simpler, more cacheable, easier to rate-limit.
2. **Dashboard (GraphQL)** - Web dashboards need flexible queries, avoid over-fetching.

**Rate Limiting Consideration:**
```ruby
# REST - easy to rate limit
rate_limit(key: api_key, limit: 1000)

# GraphQL - need query complexity analysis
max_query_complexity = 100
actual_complexity = calculate_complexity(query)  # Count fields, depth
reject if actual_complexity > max_query_complexity
```

**Connection to my project:**
"My chat app uses REST with nested resources (`/applications/:token/chats/:number/messages`) which works well for hierarchical data. For Instabug's dashboard, GraphQL would reduce mobile bandwidth - SDKs could fetch exactly the fields they need."

---

#### Q: How do you design APIs that must handle idempotency (duplicate bug events from mobile)?

**Answer:**

**Problem:** Mobile apps might retry failed requests, send duplicate crash reports, or network issues cause duplicate submissions.

**Solution: Idempotency Keys**

```ruby
class BugReportsController < ApplicationController
  def create
    idempotency_key = request.headers['Idempotency-Key']

    # Require idempotency key for POST/PUT
    return render json: { error: 'Idempotency-Key required' }, status: :bad_request unless idempotency_key

    # Check if we've seen this key before
    cached = check_idempotency_cache(idempotency_key)
    return render json: cached[:response], status: cached[:status] if cached

    # Process new request
    bug_report = BugReport.create!(bug_params)
    response_data = { id: bug_report.id, status: 'created' }

    # Cache response for 24 hours
    cache_idempotency_response(idempotency_key, response_data, :created)

    render json: response_data, status: :created
  end

  private

  def check_idempotency_cache(key)
    cached = REDIS.get("idempotency:#{key}")
    JSON.parse(cached, symbolize_names: true) if cached
  end

  def cache_idempotency_response(key, response, status)
    REDIS.setex(
      "idempotency:#{key}",
      24.hours.to_i,
      { response: response, status: status }.to_json
    )
  end
end
```

**Idempotency Key Generation (Client-side):**
```javascript
// Mobile SDK
const idempotencyKey = `${appId}-${timestamp}-${uuid()}`;

fetch('https://api.instabug.com/v1/bugs', {
  method: 'POST',
  headers: {
    'Idempotency-Key': idempotencyKey,
    'X-API-Key': apiKey
  },
  body: JSON.stringify(bugData)
});
```

**Database-Level Idempotency (Unique Constraint):**
```ruby
# Migration
create_table :bug_reports do |t|
  t.string :idempotency_key, null: false
  t.text :stack_trace
  t.timestamps
end

add_index :bug_reports, :idempotency_key, unique: true

# Model
class BugReport < ApplicationRecord
  validates :idempotency_key, presence: true, uniqueness: true
end

# Controller - handle unique constraint violation
def create
  bug_report = BugReport.create!(bug_params)
  render json: bug_report, status: :created
rescue ActiveRecord::RecordNotUnique
  # Duplicate key - return existing record
  existing = BugReport.find_by!(idempotency_key: params[:idempotency_key])
  render json: existing, status: :ok
end
```

**Connection to my project:**
"My chat app handles race conditions with database unique constraints on (chat_id, number). Same principle - if Redis INCR gives duplicate numbers (rare), the database catches it. For Instabug, idempotency keys work the same way - Redis cache for speed, database constraint for safety."

---

### Scalability & High-Throughput Systems

#### Q: How would you design a system to ingest millions of bug events per hour?

**Answer:**

**Target:** 1M events/hour = ~278 events/second (peak: 1000+ events/sec)

**Architecture:**

```
Mobile SDKs (millions)
    │
    ├─> CDN/Edge Locations (geographic distribution)
    │       │
    │       ▼
    ├─> Load Balancer (AWS ALB)
    │       │
    │       ├─> API Server 1 ─┐
    │       ├─> API Server 2 ─┤
    │       ├─> API Server N ─┤  (Auto-scaling: 10-100 instances)
    │                         │
    │                         ├─> Validation (lightweight)
    │                         │
    │                         └─> Kafka/Kinesis (event stream)
    │                                  │
    │                                  ├─> Consumer Group 1 (Storage)
    │                                  │     └─> S3 (raw events)
    │                                  │     └─> DynamoDB (metadata)
    │                                  │
    │                                  ├─> Consumer Group 2 (Processing)
    │                                  │     └─> Parse stack traces
    │                                  │     └─> Group similar bugs
    │                                  │     └─> ElasticSearch (search)
    │                                  │
    │                                  └─> Consumer Group 3 (Real-time)
    │                                        └─> WebSocket notifications
    │                                        └─> Slack/email alerts
```

**Implementation:**

```ruby
# 1. API Layer - Accept & Validate Only
class EventsController < ApplicationController
  def create
    # Lightweight validation only
    return render json: { error: 'Invalid' }, status: :bad_request unless valid_event?

    # Publish to Kafka (async, non-blocking)
    event_id = SecureRandom.uuid
    kafka_producer.produce({
      event_id: event_id,
      timestamp: Time.now.to_i,
      app_id: params[:app_id],
      payload: params[:event_data]
    }.to_json, topic: 'bug-events')

    # Return immediately (< 5ms)
    render json: { event_id: event_id }, status: :accepted
  end
end

# 2. Kafka Consumer - Heavy Processing
class BugEventConsumer
  def consume
    kafka_consumer.each_message do |message|
      event = JSON.parse(message.value)

      # Store raw event
      store_raw_event(event)

      # Parse and enrich
      parsed = parse_stack_trace(event[:payload])

      # Group similar bugs (ML/hashing)
      group = find_or_create_bug_group(parsed)

      # Index for search
      index_to_elasticsearch(event, parsed)

      # Real-time notifications
      notify_if_critical(event, group)
    end
  end
end
```

**Scalability Techniques:**

**1. Horizontal Scaling:**
- API servers: Stateless, scale to 100+ instances
- Kafka: Partition by app_id (parallel consumption)
- Consumers: Multiple consumer groups for different tasks

**2. Batching:**
```ruby
# Batch writes to S3 (reduce API calls)
class S3BatchWriter
  def initialize
    @batch = []
    @batch_size = 100
  end

  def add(event)
    @batch << event
    flush if @batch.size >= @batch_size
  end

  def flush
    # Single S3 multipart upload for 100 events
    s3.put_object(
      bucket: 'events',
      key: "#{Date.today}/#{SecureRandom.uuid}.jsonl",
      body: @batch.map(&:to_json).join("\n")
    )
    @batch.clear
  end
end
```

**3. Caching:**
```ruby
# Cache user/app metadata to avoid DB lookups
@app_cache = Redis.new
app_data = @app_cache.get("app:#{app_id}") || fetch_and_cache(app_id)
```

**4. Connection Pooling:**
```ruby
# Reuse database connections
ActiveRecord::Base.establish_connection(pool: 50)

# Reuse HTTP connections
http = Net::HTTP.new(uri.host, uri.port)
http.start  # Keep-alive
```

**5. Circuit Breaker:**
```ruby
# If Elasticsearch is down, don't fail event ingestion
class CircuitBreaker
  def call
    return open_fallback if open?

    begin
      yield
      reset_failure_count
    rescue => e
      increment_failures
      raise if failures < threshold
      open!
    end
  end
end
```

**Performance Targets:**
- API Response: < 50ms (p99)
- Throughput: 10,000 events/sec
- Latency to Storage: < 1s
- Latency to Search: < 30s

**Connection to my project:**
"My chat app uses the same pattern: API accepts request quickly (< 5ms), enqueues to Sidekiq, processes asynchronously. For Instabug's scale, Kafka replaces Sidekiq for higher throughput."

---

#### Q: How do you ensure horizontal scalability for microservices?

**Answer:**

**Principles:**

**1. Statelessness**
```ruby
# BAD - State in memory
class ApiController
  @request_count = 0  # Breaks horizontal scaling!

  def index
    @request_count += 1
  end
end

# GOOD - State in external store
class ApiController
  def index
    REDIS.incr("request_count")  # Shared across all instances
  end
end
```

**2. Database Connection Pooling**
```ruby
# Each instance has its own pool
# config/database.yml
production:
  pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5) %>

# Auto-scaling: Add instances, not connections per instance
```

**3. Shared Cache (Redis)**
```ruby
# All instances share same Redis cluster
cache_store :redis_cache_store, {
  url: ENV['REDIS_URL'],
  pool_size: 5,
  pool_timeout: 5
}
```

**4. Load Balancing Strategy**
```nginx
# nginx.conf
upstream api_servers {
  least_conn;  # Route to least busy server

  server api1:3000 max_fails=3 fail_timeout=30s;
  server api2:3000 max_fails=3 fail_timeout=30s;
  server api3:3000 max_fails=3 fail_timeout=30s;
}
```

**5. Health Checks**
```ruby
# Each instance reports health
# Load balancer removes unhealthy instances
class HealthController < ApplicationController
  def index
    render json: { status: 'healthy' }, status: :ok
  end
end
```

**6. Session Management**
```ruby
# BAD - Sessions in memory
config.session_store :cookie_store

# GOOD - Sessions in Redis (shared)
config.session_store :redis_store, {
  servers: ENV['REDIS_URL'],
  expire_after: 1.week
}
```

**7. Auto-Scaling Rules**
```yaml
# Kubernetes HPA
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 3
  maxReplicas: 50
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Pods
    pods:
      metric:
        name: requests_per_second
      target:
        type: AverageValue
        averageValue: "1000"
```

**Connection to my project:**
"My chat app's Rails API is stateless - uses Redis for counters, MySQL for data. Can run 10 instances behind a load balancer with zero code changes. Same for the Go service - shares same Redis/MySQL infrastructure."

---

#### Q: What is backpressure, and how would you implement it?

**Answer:**

**Definition:** Backpressure is when a downstream system (consumer) tells an upstream system (producer) to slow down because it can't keep up.

**Problem Without Backpressure:**
```
Producers (1000 events/sec) → Queue → Consumer (100 events/sec)
                                ↓
                        Queue grows infinitely
                        Eventually: OutOfMemory
```

**Solution 1: Bounded Queue (Blocking)**
```ruby
# Sidekiq with limited queue size
class BugReportJob < ApplicationJob
  queue_as :default

  def perform(bug_data)
    process_bug(bug_data)
  end
end

# sidekiq.yml
:queues:
  - [default, 2]
  - [critical, 5]

# If queue is full, enqueue blocks or raises exception
begin
  BugReportJob.perform_async(data)
rescue Sidekiq::QueueFull
  # Return 503 to client (apply backpressure upstream)
  render json: { error: 'System overloaded, retry later' }, status: :service_unavailable
end
```

**Solution 2: Rate Limiting**
```ruby
# Limit ingestion rate
class EventsController < ApplicationController
  def create
    # Check queue depth
    queue_size = Sidekiq::Queue.new('default').size

    if queue_size > 10_000
      # Queue too full, reject new requests
      return render json: {
        error: 'Service temporarily unavailable',
        retry_after: 60
      }, status: :service_unavailable
    end

    ProcessEventJob.perform_async(params[:event])
    render json: { status: 'accepted' }, status: :accepted
  end
end
```

**Solution 3: Kafka Consumer Group (Pull-based)**
```ruby
# Consumer pulls at its own pace
class BugEventConsumer
  def consume
    kafka.each_message(max_wait_time: 1) do |message|
      # Process at consumer's speed
      # If consumer is slow, messages wait in Kafka (durable)
      process_event(message.value)
    end
  end
end

# Kafka config
fetch_min_bytes: 1024      # Wait for batch
fetch_max_wait_time: 100   # Max wait time
max_poll_records: 100      # Limit batch size
```

**Solution 4: Circuit Breaker**
```ruby
class CircuitBreaker
  def initialize(threshold: 5, timeout: 60)
    @threshold = threshold
    @timeout = timeout
    @failures = 0
    @state = :closed
    @opened_at = nil
  end

  def call
    if open?
      # Reject immediately (backpressure)
      raise CircuitOpenError, 'Circuit breaker open'
    end

    begin
      yield
      reset_failures
    rescue => e
      record_failure
      raise
    end
  end

  def open?
    @state == :open && (Time.now - @opened_at) < @timeout
  end

  def record_failure
    @failures += 1
    if @failures >= @threshold
      @state = :open
      @opened_at = Time.now
    end
  end
end

# Usage
breaker = CircuitBreaker.new
begin
  breaker.call { slow_service.process(data) }
rescue CircuitOpenError
  # Apply backpressure to client
  render json: { error: 'Service degraded' }, status: :service_unavailable
end
```

**Solution 5: HTTP/2 Flow Control**
```ruby
# HTTP/2 has built-in backpressure
# Client sends WINDOW_UPDATE frames to control flow

# Puma config for HTTP/2
workers ENV.fetch("WEB_CONCURRENCY") { 4 }
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count

# Enable flow control
preload_app!
```

**Monitoring Backpressure:**
```ruby
# Metrics to track
Metrics.gauge('queue.depth', Sidekiq::Queue.new.size)
Metrics.gauge('consumer.lag', kafka_consumer_lag)
Metrics.gauge('circuit_breaker.state', breaker.open? ? 1 : 0)

# Alert when queue depth > 10k
```

**Connection to my project:**
"My chat app doesn't implement backpressure yet (low scale), but in production I'd add queue depth checks. If Sidekiq queue > threshold, return 503 with Retry-After header."

---

#### Q: How to handle burst traffic from mobile applications?

**Answer:**

**Scenario:** Mobile apps wake up at 9 AM, send thousands of crash reports simultaneously.

**Strategy 1: Rate Limiting (Smooth Traffic)**
```ruby
# Token bucket algorithm
class RateLimiter
  def allow?(client_id, burst: 100, refill_rate: 10)
    key = "rate:#{client_id}"
    now = Time.now.to_f

    # Get current tokens
    tokens, last_refill = get_bucket(key)

    # Refill tokens based on time elapsed
    elapsed = now - last_refill
    tokens = [burst, tokens + (elapsed * refill_rate)].min

    if tokens >= 1
      # Allow request, consume token
      tokens -= 1
      save_bucket(key, tokens, now)
      true
    else
      # Reject
      false
    end
  end
end
```

**Strategy 2: Queue-Based Buffering**
```
Burst Traffic (10k req/sec) → Kafka (buffer) → Consumers (1k req/sec)
                                  ↓
                         Queue absorbs burst
                         Consumers process at steady rate
```

**Strategy 3: Auto-Scaling**
```yaml
# Kubernetes HPA - scale based on requests/sec
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  minReplicas: 3
  maxReplicas: 100
  metrics:
  - type: Pods
    pods:
      metric:
        name: requests_per_second
      target:
        averageValue: "1000"  # Scale when > 1k req/sec per pod
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0  # Scale up immediately
      policies:
      - type: Percent
        value: 100  # Double pods each cycle
        periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 300  # Wait 5 min before scaling down
```

**Strategy 4: CDN/Edge Caching**
```
# Cache API responses at edge
# For read-heavy endpoints
Cache-Control: public, max-age=60

# Reduce load on origin servers
CDN handles 80% of traffic
```

**Strategy 5: Client-Side Strategies**
```javascript
// Mobile SDK - implement exponential backoff
async function sendBugReport(data, retries = 3) {
  for (let i = 0; i < retries; i++) {
    try {
      const response = await fetch('/api/bugs', { method: 'POST', body: data });

      if (response.status === 429) {
        // Rate limited - wait and retry
        const retryAfter = response.headers.get('Retry-After') || (2 ** i);
        await sleep(retryAfter * 1000);
        continue;
      }

      return response;
    } catch (error) {
      if (i === retries - 1) throw error;
      await sleep(2 ** i * 1000);  // Exponential backoff
    }
  }
}
```

**Strategy 6: Priority Queue**
```ruby
# Critical bugs bypass queue
class BugReportJob < ApplicationJob
  def perform(bug_data)
    if critical?(bug_data)
      # High priority queue
      queue_as :critical
    else
      # Normal queue
      queue_as :default
    end

    process_bug(bug_data)
  end
end

# Sidekiq processes critical queue first
:queues:
  - [critical, 5]   # 5x weight
  - [default, 1]
```

**Strategy 7: Graceful Degradation**
```ruby
class BugReportsController < ApplicationController
  def create
    queue_depth = Sidekiq::Queue.new.size

    if queue_depth > 50_000
      # System overloaded - accept but don't process immediately
      store_to_s3_backup(params[:bug_data])

      return render json: {
        status: 'queued_for_later',
        message: 'High load, will process within 1 hour'
      }, status: :accepted
    end

    # Normal processing
    ProcessBugJob.perform_async(params[:bug_data])
    render json: { status: 'accepted' }, status: :accepted
  end
end
```

**Monitoring:**
```ruby
# Track burst metrics
Metrics.gauge('requests.per_second', calculate_rps)
Metrics.gauge('queue.depth', queue_size)
Metrics.gauge('pod.count', current_replicas)

# Alert on burst
if rps > 5000
  alert("Burst traffic detected: #{rps} req/sec")
end
```

**Connection to my project:**
"My chat app handles small bursts with Sidekiq queue buffering. For Instabug scale, I'd add auto-scaling, rate limiting, and CDN caching."

---

### Distributed Systems & Event Processing

#### Q: How do you design an event pipeline with Kafka/RabbitMQ/SQS?

**Answer:**

**Comparison:**

| Feature | Kafka | RabbitMQ | SQS |
|---------|-------|----------|-----|
| **Use Case** | Event streaming, high throughput | Task queues, routing | Simple queues, AWS-native |
| **Throughput** | Millions/sec | Thousands/sec | Thousands/sec |
| **Ordering** | Per partition | Per queue | FIFO queues only |
| **Persistence** | Disk (retained) | Memory (optional disk) | Managed by AWS |
| **Replay** | ✅ Yes (offset) | ❌ No | ❌ Limited |
| **Complexity** | High | Medium | Low |

**My Choice for Instabug: Kafka**

**Architecture:**
```
Mobile SDKs
    │
    ├─> API (Producer)
    │      ↓
    ├─> Kafka Topic: "bug-events"
    │      Partitions: 10 (by app_id hash)
    │      Retention: 7 days
    │      Replication: 3
    │
    ├─> Consumer Group 1: "storage-service"
    │      └─> Store to S3 + DynamoDB
    │
    ├─> Consumer Group 2: "processing-service"
    │      └─> Parse, group, ML classification
    │
    └─> Consumer Group 3: "notification-service"
           └─> Real-time alerts (Slack, email)
```

**Implementation:**

```ruby
# Producer (API)
class EventProducer
  def initialize
    @kafka = Kafka.new(['kafka1:9092', 'kafka2:9092', 'kafka3:9092'])
    @producer = @kafka.async_producer(
      delivery_threshold: 100,  # Batch 100 messages
      delivery_interval: 1      # Or every 1 second
    )
  end

  def publish_bug_event(app_id, event_data)
    @producer.produce(
      event_data.to_json,
      topic: 'bug-events',
      partition_key: app_id.to_s  # Same app_id → same partition (ordering)
    )
  end
end

# Consumer (Storage Service)
class StorageConsumer
  def initialize
    @kafka = Kafka.new(['kafka1:9092', 'kafka2:9092'])
    @consumer = @kafka.consumer(
      group_id: 'storage-service',
      offset_commit_interval: 10,
      offset_commit_threshold: 100
    )
    @consumer.subscribe('bug-events')
  end

  def consume
    @consumer.each_message(automatically_mark_as_processed: false) do |message|
      event = JSON.parse(message.value)

      begin
        # Store to S3
        store_to_s3(event)

        # Store metadata to DynamoDB
        store_to_dynamodb(event)

        # Commit offset (mark as processed)
        @consumer.mark_message_as_processed(message)
      rescue => e
        # Don't commit - will retry on next poll
        logger.error("Failed to process: #{e}")
      end
    end
  end
end
```

**Kafka Configuration:**

```yaml
# Topic config
num.partitions: 10          # Parallel processing
replication.factor: 3       # Durability
retention.ms: 604800000     # 7 days (604800000 ms)
min.insync.replicas: 2      # At least 2 replicas

# Producer config
acks: all                   # Wait for all replicas
compression.type: snappy    # Compress messages
max.in.flight.requests: 5   # Pipeline requests

# Consumer config
enable.auto.commit: false   # Manual commit for exactly-once
max.poll.records: 500       # Batch size
```

**Error Handling:**

```ruby
# Retry with DLQ (Dead Letter Queue)
class RobustConsumer
  def process_message(message)
    begin
      process(message)
      commit(message)
    rescue RetryableError => e
      # Retry up to 3 times
      retry_count = get_retry_count(message)
      if retry_count < 3
        increment_retry_count(message)
        # Don't commit - will reprocess
      else
        # Send to DLQ
        send_to_dlq(message, error: e)
        commit(message)
      end
    rescue FatalError => e
      # Immediately to DLQ
      send_to_dlq(message, error: e)
      commit(message)
    end
  end
end
```

**Connection to my project:**
"My chat app uses Sidekiq (simple queue). For Instabug's scale and need to replay events, Kafka is better. Similar async pattern - API produces, background consumes."

---

(Continuing in next section due to length...)

## 2. Databases & Storage

### SQL

#### Q: Normalize and denormalize a database schema—when to do which?

**Answer:**

**Normalization (my chat app does this):**

**Example - Normalized (3NF):**
```sql
-- Separate tables, no duplication
CREATE TABLE chat_applications (
  id BIGINT PRIMARY KEY,
  name VARCHAR(255),
  token VARCHAR(32) UNIQUE
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
```

**Pros:**
- ✅ No duplicate data
- ✅ Easy to update (one place)
- ✅ Data integrity enforced

**Cons:**
- ❌ Requires JOINs for queries
- ❌ Slower reads

**Denormalization (for performance):**

**Example - Denormalized:**
```sql
-- Duplicate data for faster reads
CREATE TABLE messages (
  id BIGINT PRIMARY KEY,
  chat_id BIGINT,
  number INTEGER,
  body TEXT,

  -- Denormalized fields (duplicated from parent tables)
  chat_number INTEGER,           -- From chats table
  app_name VARCHAR(255),         -- From chat_applications table
  app_token VARCHAR(32),         -- From chat_applications table

  -- Cached counts (my chat app does this)
  chat_messages_count INTEGER    -- Avoids COUNT(*) query
);

-- Single query, no JOINs needed
SELECT * FROM messages WHERE app_token = 'abc123';
```

**When to Normalize:**
1. **Write-heavy workloads** - Updates are easier
2. **Storage is expensive** - No duplication
3. **Data changes frequently** - One place to update
4. **Data integrity is critical** - Foreign keys enforce consistency

**When to Denormalize:**
1. **Read-heavy workloads** - Avoid expensive JOINs
2. **Performance is critical** - Trading space for speed
3. **Data is read-only or rarely changes** - Analytics, logs
4. **Aggregations are common** - Pre-calculate counts, sums

**Hybrid Approach (my chat app):**
```ruby
# Normalized: Foreign keys for integrity
class Chat < ApplicationRecord
  belongs_to :chat_application
  has_many :messages
end

# Denormalized: Cached counters for performance
class ChatApplication < ApplicationRecord
  has_many :chats
  # chats_count column - avoids COUNT(*)
end

# Update counter asynchronously
Chat.increment_counter(:messages_count, chat_id)
```

**Real-World Example for Instabug:**

**Normalized (OLTP - Transactional):**
```sql
-- Production database - normalized
bugs
bug_occurrences (many per bug)
stack_traces
user_sessions
```

**Denormalized (OLAP - Analytics):**
```sql
-- Data warehouse - denormalized for reporting
CREATE TABLE bug_analytics (
  bug_id BIGINT,
  bug_title VARCHAR,
  app_name VARCHAR,
  user_email VARCHAR,
  device_model VARCHAR,
  os_version VARCHAR,
  occurred_at TIMESTAMP,
  stack_trace TEXT
);

-- Fast query - no JOINs
SELECT app_name, COUNT(*)
FROM bug_analytics
WHERE occurred_at > NOW() - INTERVAL '7 days'
GROUP BY app_name;
```

---

#### Q: How would you optimize a slow SQL query?

**Answer:**

**Step 1: Identify the Problem**
```sql
-- Use EXPLAIN to see execution plan
EXPLAIN ANALYZE
SELECT m.* FROM messages m
JOIN chats c ON m.chat_id = c.id
JOIN chat_applications ca ON c.chat_application_id = ca.id
WHERE ca.token = 'abc123'
  AND m.created_at > NOW() - INTERVAL '7 days'
ORDER BY m.created_at DESC
LIMIT 10;

-- Look for:
-- - Seq Scan (bad - full table scan)
-- - Index Scan (good)
-- - High cost/rows
```

**Step 2: Add Indexes**
```sql
-- Index on foreign keys
CREATE INDEX idx_messages_chat_id ON messages(chat_id);
CREATE INDEX idx_chats_app_id ON chats(chat_application_id);

-- Index on filter columns
CREATE INDEX idx_messages_created_at ON messages(created_at);
CREATE INDEX idx_apps_token ON chat_applications(token);

-- Composite index for common query pattern
CREATE INDEX idx_messages_chat_created ON messages(chat_id, created_at DESC);
```

**Step 3: Rewrite Query**
```sql
-- BAD - Subquery in SELECT
SELECT m.*,
  (SELECT COUNT(*) FROM messages WHERE chat_id = m.chat_id) as msg_count
FROM messages m;

-- GOOD - Use cached counter (my chat app does this)
SELECT m.*, c.messages_count
FROM messages m
JOIN chats c ON m.chat_id = c.id;

-- BAD - OR conditions (doesn't use index)
WHERE app_id = 1 OR app_id = 2;

-- GOOD - IN condition (can use index)
WHERE app_id IN (1, 2);
```

**Step 4: Limit Result Set**
```sql
-- BAD - Load all then filter in code
SELECT * FROM messages;  -- Returns 1M rows!

-- GOOD - Filter in database
SELECT * FROM messages
WHERE chat_id = 123
LIMIT 100;
```

**Step 5: Use Covering Index**
```sql
-- Query only needs: id, body, created_at
-- Create index that includes all columns
CREATE INDEX idx_messages_covering ON messages(chat_id, created_at) INCLUDE (id, body);

-- Query can use index-only scan (no table access)
SELECT id, body, created_at
FROM messages
WHERE chat_id = 123;
```

**Step 6: Partition Large Tables**
```sql
-- Partition by date (time-series data)
CREATE TABLE messages (
  id BIGINT,
  chat_id BIGINT,
  body TEXT,
  created_at TIMESTAMP
) PARTITION BY RANGE (created_at);

CREATE TABLE messages_2025_01 PARTITION OF messages
  FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

CREATE TABLE messages_2025_02 PARTITION OF messages
  FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');

-- Query only scans relevant partition
SELECT * FROM messages WHERE created_at > '2025-01-15';
```

**Step 7: Analyze Query Patterns**
```sql
-- If many queries filter by created_at and chat_id
-- Create partial index (smaller, faster)
CREATE INDEX idx_recent_messages ON messages(chat_id, created_at)
WHERE created_at > NOW() - INTERVAL '30 days';
```

**Real Example from My Chat App:**
```ruby
# Slow query (N+1 problem)
chats = Chat.all
chats.each do |chat|
  puts chat.messages.count  # N queries!
end

# Optimized - eager loading
chats = Chat.includes(:messages).all
chats.each do |chat|
  puts chat.messages.size  # 0 additional queries
end

# Or use counter cache
Chat.increment_counter(:messages_count, chat_id)
chat.messages_count  # No query at all
```

**Connection to my project:**
"My chat app has indexes on all foreign keys, unique constraints for composite keys, and cached counters to avoid COUNT(*) queries. For Instabug's millions of records, I'd add partitioning by date."

---

#### Q: What is an index? Types? When NOT to use indexes?

**Answer:**

**What is an Index?**
- Data structure (usually B-tree) that speeds up lookups
- Like a book's index - find content without reading every page
- Trades storage space for query speed

**Types of Indexes:**

**1. B-tree Index (default, most common)**
```sql
CREATE INDEX idx_messages_chat ON messages(chat_id);

-- Good for:
-- - Equality: WHERE chat_id = 123
-- - Range: WHERE created_at > '2025-01-01'
-- - Sorting: ORDER BY created_at
```

**2. Hash Index**
```sql
CREATE INDEX idx_apps_token ON chat_applications USING HASH (token);

-- Good for: Exact equality only
-- WHERE token = 'abc123'

-- Bad for: Ranges, sorting
-- WHERE token > 'aaa'  (won't use index)
```

**3. GiST/GIN (Full-text search, arrays)**
```sql
-- Full-text search
CREATE INDEX idx_messages_body ON messages USING GIN (to_tsvector('english', body));

-- Search
WHERE to_tsvector('english', body) @@ to_tsquery('error');
```

**4. Unique Index**
```sql
-- My chat app uses these
CREATE UNIQUE INDEX idx_chats_app_number ON chats(chat_application_id, number);

-- Enforces uniqueness + speeds up lookups
```

**5. Partial Index**
```sql
-- Index only recent messages (smaller, faster)
CREATE INDEX idx_recent_msgs ON messages(created_at)
WHERE created_at > NOW() - INTERVAL '30 days';
```

**6. Composite Index**
```sql
-- Multiple columns
CREATE INDEX idx_msgs_chat_created ON messages(chat_id, created_at DESC);

-- Column order matters!
-- Can use for:
-- WHERE chat_id = 123
-- WHERE chat_id = 123 AND created_at > '2025-01-01'
-- WHERE chat_id = 123 ORDER BY created_at DESC

-- Cannot use for:
-- WHERE created_at > '2025-01-01'  (second column only)
```

**7. Covering Index (Include columns)**
```sql
CREATE INDEX idx_msgs_covering ON messages(chat_id) INCLUDE (body, created_at);

-- Query can be satisfied entirely from index (index-only scan)
SELECT body, created_at FROM messages WHERE chat_id = 123;
```

**When NOT to Use Indexes:**

**1. Small Tables (< 1000 rows)**
```sql
-- Sequential scan is faster than index scan for small tables
SELECT * FROM chat_applications;  -- Only 100 apps, no index needed
```

**2. High Cardinality on Frequently Updated Columns**
```sql
-- BAD - index slows down writes
CREATE INDEX idx_messages_updated ON messages(updated_at);

-- Every message update requires index update
-- If updated_at changes on every write, index is expensive
```

**3. Low Selectivity Columns**
```sql
-- BAD - Boolean columns with even distribution
CREATE INDEX idx_bugs_resolved ON bugs(is_resolved);

-- If 50% true, 50% false, index doesn't help
-- Database still scans half the table
```

**4. Columns Not Used in WHERE/JOIN/ORDER BY**
```sql
-- BAD - body is only in SELECT, not WHERE
CREATE INDEX idx_messages_body ON messages(body);

-- Unless using full-text search, this is useless
```

**5. Write-Heavy Tables**
```sql
-- Indexes slow down writes
-- Every INSERT/UPDATE requires index update
-- If 90% writes, 10% reads, minimize indexes
```

**Index Maintenance:**
```sql
-- Check index usage
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0  -- Never used!
ORDER BY schemaname, tablename;

-- Drop unused indexes
DROP INDEX idx_unused;

-- Rebuild fragmented indexes
REINDEX INDEX idx_messages_chat;
```

**Connection to my project:**
"My chat app has B-tree indexes on all foreign keys and unique composite indexes on (chat_application_id, number) and (chat_id, number). These enforce uniqueness and speed up nested resource lookups."

---

### NoSQL

#### Q: When would you choose MongoDB/Elasticsearch over PostgreSQL?

**Answer:**

**PostgreSQL (my chat app uses MySQL, similar):**

**Use When:**
- ✅ Need ACID transactions
- ✅ Complex relationships (many JOINs)
- ✅ Data integrity is critical
- ✅ Schema is well-defined and stable

**Example: User accounts, billing, financial data**

**MongoDB:**

**Use When:**
- ✅ Schema is flexible/evolving
- ✅ Need horizontal scaling (sharding)
- ✅ Document-oriented data (nested objects)
- ✅ High write throughput

**Example for Instabug - Bug events:**
```javascript
// MongoDB document - flexible schema
{
  _id: ObjectId("..."),
  app_id: "abc123",
  timestamp: ISODate("2025-01-17"),
  type: "crash",

  // Nested objects (no JOINs)
  user: {
    id: "user123",
    email: "user@example.com",
    device: {
      model: "iPhone 15",
      os: "iOS 18.2"
    }
  },

  // Variable fields based on bug type
  crash: {
    exception: "NullPointerException",
    stack_trace: ["line1", "line2"],
    threads: [...]
  },

  // Can add fields without migration
  custom_data: {
    feature_flag_xyz: true
  }
}

// Query
db.bugs.find({
  "user.device.model": "iPhone 15",
  timestamp: { $gte: ISODate("2025-01-01") }
})
```

**Pros:**
- No schema migration for new fields
- Natural nesting (no JOINs)
- Horizontal scaling built-in

**Cons:**
- No transactions across documents
- Can have data duplication

**Elasticsearch:**

**Use When:**
- ✅ Need full-text search
- ✅ Log/event aggregation
- ✅ Real-time analytics
- ✅ Fuzzy matching, relevance scoring

**Example for Instabug - Log search:**
```json
// Elasticsearch document
{
  "bug_id": "123",
  "timestamp": "2025-01-17T10:30:00Z",
  "log_message": "Failed to connect to database: timeout after 30s",
  "level": "ERROR",
  "app_name": "MyApp",
  "user_id": "user123"
}

// Full-text search with relevance scoring
POST /logs/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "log_message": "database timeout" } },
        { "range": { "timestamp": { "gte": "now-7d" } } }
      ],
      "filter": [
        { "term": { "app_name": "MyApp" } }
      ]
    }
  },
  "aggs": {
    "errors_over_time": {
      "date_histogram": {
        "field": "timestamp",
        "interval": "hour"
      }
    }
  }
}
```

**Pros:**
- Fast full-text search (inverted index)
- Real-time aggregations
- Horizontal scaling

**Cons:**
- Eventually consistent
- Not for transactional data
- Higher resource usage

**Decision Matrix for Instabug:**

| Data Type | Storage | Why |
|-----------|---------|-----|
| User accounts, subscriptions | PostgreSQL | ACID, transactions, billing integrity |
| Bug event stream | MongoDB | Flexible schema, high writes, document-oriented |
| Log messages, stack traces | Elasticsearch | Full-text search, aggregations |
| Session replays (videos) | S3 | Blob storage |
| Real-time metrics | Redis | In-memory, fast counters |

**Hybrid Approach:**
```
Write Path:
Bug Event → MongoDB (primary storage) → Elasticsearch (search index)

Read Path:
- List bugs: MongoDB (structured queries)
- Search logs: Elasticsearch (full-text)
- Show bug: MongoDB → S3 (fetch attachments)
```

**Connection to my project:**
"My chat app uses MySQL (relational) for structured data and Elasticsearch for message search. For Instabug's flexible bug events, MongoDB would be better - no schema migrations for custom fields."

---

#### Q: How would you model a log storage system?

**Answer:**

**Requirements:**
- 100M+ logs per day
- Retention: 30 days hot, 1 year cold
- Query patterns: filter by time, app, level, search text
- Write-heavy (99% writes, 1% reads)

**Architecture:**

```
Log Sources (apps, services)
    │
    ├─> Log Forwarder (Fluentd/Logstash)
    │      ↓
    ├─> Kafka (buffer, replay capability)
    │      ↓
    ├─> Stream Processor (enrich, parse)
    │      ↓
    ├─> Storage Layer (Tiered)
    │      ├─> Hot: Elasticsearch (last 30 days)
    │      ├─> Warm: S3 (Parquet format, 31-90 days)
    │      └─> Cold: S3 Glacier (> 90 days)
    │
    └─> Query Layer
           ├─> Kibana (hot data)
           └─> Athena (warm/cold data)
```

**Data Model:**

**Elasticsearch (Hot Storage):**
```json
{
  // Index pattern: logs-2025-01-17 (daily indices)
  "_index": "logs-2025-01-17",
  "_id": "unique-log-id",
  "_source": {
    "@timestamp": "2025-01-17T10:30:00Z",
    "level": "ERROR",
    "message": "Database connection timeout after 30s",
    "logger": "com.instabug.api.DatabaseService",

    // Structured fields (for filtering)
    "app": {
      "name": "MyApp",
      "version": "1.2.3",
      "environment": "production"
    },

    "user": {
      "id": "user123",
      "email": "user@example.com"
    },

    "request": {
      "method": "POST",
      "path": "/api/bugs",
      "duration_ms": 250
    },

    // Stack trace (full-text searchable)
    "stack_trace": "NullPointerException at ...",

    // Custom fields
    "labels": {
      "team": "backend",
      "severity": "high"
    }
  }
}

// Index settings
PUT /logs-2025-01-17
{
  "settings": {
    "number_of_shards": 5,
    "number_of_replicas": 1,
    "refresh_interval": "30s",  // Don't refresh on every write

    // Index lifecycle management
    "index.lifecycle.name": "logs-policy",
    "index.lifecycle.rollover_alias": "logs"
  },
  "mappings": {
    "properties": {
      "@timestamp": { "type": "date" },
      "level": { "type": "keyword" },
      "message": { "type": "text" },
      "app.name": { "type": "keyword" },
      "request.duration_ms": { "type": "long" }
    }
  }
}
```

**Index Lifecycle Management:**
```json
// Hot → Warm → Cold → Delete
PUT /_ilm/policy/logs-policy
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_age": "1d",
            "max_size": "50gb"
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "shrink": { "number_of_shards": 1 },
          "forcemerge": { "max_num_segments": 1 }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "freeze": {}
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

**S3 Archive (Warm/Cold Storage):**
```
s3://logs-archive/
  ├── year=2025/
  │   ├── month=01/
  │   │   ├── day=17/
  │   │   │   ├── hour=10/
  │   │   │   │   └── logs.parquet.gz
```

**Parquet Schema:**
```python
# Columnar format - efficient for analytics
import pyarrow.parquet as pq

schema = pa.schema([
    ('timestamp', pa.timestamp('ms')),
    ('level', pa.string()),
    ('message', pa.string()),
    ('app_name', pa.string()),
    ('user_id', pa.string()),
    ('duration_ms', pa.int64())
])

# Write to S3
pq.write_table(table, 's3://logs-archive/2025/01/17/10/logs.parquet')

# Query with Athena
CREATE EXTERNAL TABLE logs (
  timestamp TIMESTAMP,
  level STRING,
  message STRING,
  app_name STRING
)
STORED AS PARQUET
LOCATION 's3://logs-archive/'
PARTITIONED BY (year INT, month INT, day INT);

-- Query
SELECT app_name, COUNT(*)
FROM logs
WHERE year=2025 AND month=1 AND day=17
  AND level='ERROR'
GROUP BY app_name;
```

**Ingestion Pipeline:**

```ruby
# Kafka Consumer → Elasticsearch
class LogConsumer
  def consume
    kafka.each_message(batch_size: 1000) do |batch|
      bulk_body = []

      batch.each do |message|
        log = JSON.parse(message.value)

        # Index pattern: logs-YYYY-MM-DD
        index = "logs-#{Date.today.strftime('%Y-%m-%d')}"

        bulk_body << { index: { _index: index, _id: log['id'] } }
        bulk_body << log
      end

      # Bulk insert (much faster than one-by-one)
      elasticsearch.bulk(body: bulk_body)
    end
  end
end
```

**Query Optimization:**

```json
// Use filters (cached) instead of queries
POST /logs-*/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "app.name": "MyApp" } },
        { "range": { "@timestamp": { "gte": "now-1h" } } }
      ],
      "must": [
        { "match": { "message": "error" } }
      ]
    }
  },
  "size": 100,
  "sort": [{ "@timestamp": "desc" }]
}
```

**Cost Optimization:**

| Storage Tier | Retention | Cost/GB/Month | Use Case |
|--------------|-----------|---------------|----------|
| Elasticsearch | 7 days | $0.10 | Real-time search |
| S3 Standard | 30 days | $0.023 | Recent queries |
| S3 Glacier | 1 year | $0.004 | Compliance, rare access |

**Connection to my project:**
"My chat app stores messages in MySQL (structured) and indexes in Elasticsearch (search). For logs, time-series partitioning and tiered storage (hot/warm/cold) would be key additions."

---

(Continuing next sections due to length - let me know if you want me to continue with the remaining 7 sections!)

Would you like me to continue with:
3. Practical Backend Coding (Live Coding)
4. Concurrency & Performance
5. Microservices & Architecture
6. DevOps Knowledge
7. Monitoring, Logging, and Observability
8. Backend Language Knowledge
9. Culture Fit (Technical Judgment)

---

## 3. Practical Backend Coding

### Common Coding Problems

#### Q: Implement a rate limiter

**Answer:**

**Token Bucket Algorithm:**

```ruby
class RateLimiter
  def initialize(redis = REDIS)
    @redis = redis
  end

  # Returns true if request is allowed, false otherwise
  def allow?(key, max_requests: 100, window_seconds: 60)
    current_time = Time.now.to_i
    window_key = "rate_limit:#{key}:#{current_time / window_seconds}"

    count = @redis.incr(window_key)

    # Set expiry on first request in window
    @redis.expire(window_key, window_seconds) if count == 1

    count <= max_requests
  end

  # Returns remaining quota
  def remaining(key, max_requests: 100, window_seconds: 60)
    current_time = Time.now.to_i
    window_key = "rate_limit:#{key}:#{current_time / window_seconds}"

    count = @redis.get(window_key).to_i
    [max_requests - count, 0].max
  end
end

# Usage
limiter = RateLimiter.new
api_key = request.headers['X-API-Key']

unless limiter.allow?(api_key, max_requests: 1000, window_seconds: 60)
  render json: {
    error: 'Rate limit exceeded',
    retry_after: 60 - (Time.now.to_i % 60)
  }, status: :too_many_requests
end
```

**Sliding Window Rate Limiter (More Accurate):**

```ruby
class SlidingWindowRateLimiter
  def allow?(key, max_requests: 100, window_seconds: 60)
    now = Time.now.to_f
    window_start = now - window_seconds

    # Use sorted set with timestamps as scores
    @redis.zremrangebyscore("rate:#{key}", 0, window_start)
    count = @redis.zcard("rate:#{key}")

    if count < max_requests
      @redis.zadd("rate:#{key}", now, "#{now}-#{rand(1000)}")
      @redis.expire("rate:#{key}", window_seconds)
      true
    else
      false
    end
  end
end
```

---

#### Q: Implement an LRU cache

**Answer:**

```ruby
class LRUCache
  def initialize(capacity)
    @capacity = capacity
    @cache = {}  # Hash for O(1) lookup
    @order = []  # Array to track access order (most recent at end)
  end

  def get(key)
    return nil unless @cache.key?(key)

    # Move to end (most recently used)
    @order.delete(key)
    @order.push(key)

    @cache[key]
  end

  def put(key, value)
    if @cache.key?(key)
      # Update existing
      @cache[key] = value
      @order.delete(key)
      @order.push(key)
    else
      # Add new
      if @cache.size >= @capacity
        # Evict least recently used (first in @order)
        lru_key = @order.shift
        @cache.delete(lru_key)
      end

      @cache[key] = value
      @order.push(key)
    end
  end
end

# Usage
cache = LRUCache.new(3)
cache.put(1, 'a')
cache.put(2, 'b')
cache.put(3, 'c')
cache.get(1)       # Returns 'a', moves 1 to end
cache.put(4, 'd')  # Evicts 2 (least recently used)
cache.get(2)       # Returns nil (evicted)
```

**Optimized with Doubly Linked List (O(1) for all operations):**

```ruby
class Node
  attr_accessor :key, :value, :prev, :next

  def initialize(key, value)
    @key = key
    @value = value
    @prev = nil
    @next = nil
  end
end

class LRUCache
  def initialize(capacity)
    @capacity = capacity
    @cache = {}
    @head = Node.new(nil, nil)  # Dummy head
    @tail = Node.new(nil, nil)  # Dummy tail
    @head.next = @tail
    @tail.prev = @head
  end

  def get(key)
    return nil unless @cache.key?(key)

    node = @cache[key]
    move_to_front(node)
    node.value
  end

  def put(key, value)
    if @cache.key?(key)
      node = @cache[key]
      node.value = value
      move_to_front(node)
    else
      if @cache.size >= @capacity
        # Remove LRU (node before tail)
        lru = @tail.prev
        remove_node(lru)
        @cache.delete(lru.key)
      end

      node = Node.new(key, value)
      @cache[key] = node
      add_to_front(node)
    end
  end

  private

  def remove_node(node)
    node.prev.next = node.next
    node.next.prev = node.prev
  end

  def add_to_front(node)
    node.next = @head.next
    node.prev = @head
    @head.next.prev = node
    @head.next = node
  end

  def move_to_front(node)
    remove_node(node)
    add_to_front(node)
  end
end
```

---

#### Q: Parse logs & compute stats

**Answer:**

```ruby
# Given a stream of log lines, compute:
# 1. Total requests per HTTP status code
# 2. Average response time
# 3. Top 5 slowest endpoints

class LogParser
  def initialize
    @status_counts = Hash.new(0)
    @response_times = []
    @endpoint_times = Hash.new { |h, k| h[k] = [] }
  end

  def parse_line(line)
    # Example log format:
    # 2025-01-17 10:30:00 GET /api/bugs 200 125ms
    match = line.match(/(\S+) (\S+) (\S+) (\d+) (\d+)ms/)
    return unless match

    timestamp, method, path, status, duration = match.captures
    status = status.to_i
    duration = duration.to_i

    # Track stats
    @status_counts[status] += 1
    @response_times << duration
    @endpoint_times["#{method} #{path}"] << duration
  end

  def stats
    {
      total_requests: @response_times.size,
      status_distribution: @status_counts,
      avg_response_time: @response_times.sum / @response_times.size.to_f,
      p50_response_time: percentile(@response_times, 50),
      p95_response_time: percentile(@response_times, 95),
      p99_response_time: percentile(@response_times, 99),
      slowest_endpoints: slowest_endpoints(5)
    }
  end

  private

  def percentile(array, pct)
    sorted = array.sort
    index = (pct / 100.0 * sorted.size).ceil - 1
    sorted[index]
  end

  def slowest_endpoints(n)
    @endpoint_times.map do |endpoint, times|
      {
        endpoint: endpoint,
        avg_time: times.sum / times.size.to_f,
        max_time: times.max,
        count: times.size
      }
    end.sort_by { |e| -e[:avg_time] }.take(n)
  end
end

# Usage
parser = LogParser.new

File.foreach('access.log') do |line|
  parser.parse_line(line)
end

puts parser.stats
# => {
#   total_requests: 10000,
#   status_distribution: { 200 => 9500, 404 => 300, 500 => 200 },
#   avg_response_time: 125.5,
#   p95_response_time: 250,
#   slowest_endpoints: [...]
# }
```

---

#### Q: Compute unique users per minute efficiently

**Answer:**

**Using HyperLogLog (Approximate, Memory Efficient):**

```ruby
# Stream of events: { timestamp, user_id }
# Compute unique users per minute

class UniqueUserCounter
  def initialize
    @redis = Redis.new
  end

  def add_event(timestamp, user_id)
    # Round to minute
    minute = Time.at(timestamp).strftime('%Y-%m-%d %H:%M')
    key = "unique_users:#{minute}"

    # HyperLogLog - probabilistic counting (0.81% error rate)
    @redis.pfadd(key, user_id)
    @redis.expire(key, 86400)  # Keep for 24 hours
  end

  def count_unique(minute)
    key = "unique_users:#{minute}"
    @redis.pfcount(key)
  end

  # Count unique across multiple minutes
  def count_unique_range(start_minute, end_minute)
    keys = []
    current = Time.parse(start_minute)
    end_time = Time.parse(end_minute)

    while current <= end_time
      keys << "unique_users:#{current.strftime('%Y-%m-%d %H:%M')}"
      current += 60
    end

    @redis.pfcount(*keys)  # HyperLogLog union
  end
end

# Usage
counter = UniqueUserCounter.new

# Process event stream
events.each do |event|
  counter.add_event(event[:timestamp], event[:user_id])
end

# Query
puts counter.count_unique('2025-01-17 10:30')  # ~50,000 users
puts counter.count_unique_range('2025-01-17 10:00', '2025-01-17 11:00')  # ~500,000 users

# Memory usage: ~12KB per minute (vs 1MB+ for exact set)
```

**Exact Counting (Higher Memory):**

```ruby
class ExactUniqueCounter
  def initialize
    @windows = Hash.new { |h, k| h[k] = Set.new }
  end

  def add_event(timestamp, user_id)
    minute = Time.at(timestamp).strftime('%Y-%m-%d %H:%M')
    @windows[minute].add(user_id)
  end

  def count_unique(minute)
    @windows[minute].size
  end
end
```

---

#### Q: Implement a retry mechanism with exponential backoff

**Answer:**

```ruby
class Retrier
  def self.with_retry(max_attempts: 3, base_delay: 1, max_delay: 60, exceptions: [StandardError])
    attempts = 0

    begin
      attempts += 1
      yield
    rescue *exceptions => e
      if attempts < max_attempts
        # Exponential backoff: 1s, 2s, 4s, 8s...
        delay = [base_delay * (2 ** (attempts - 1)), max_delay].min

        # Add jitter to prevent thundering herd
        jitter = rand(0..delay * 0.1)
        sleep(delay + jitter)

        retry
      else
        # Max retries exceeded
        raise
      end
    end
  end
end

# Usage
Retrier.with_retry(max_attempts: 5) do
  response = HTTP.get('https://api.example.com/data')
  raise 'API error' unless response.status == 200
  response.body
end

# More advanced - with circuit breaker
class ResilientHTTP
  def initialize
    @circuit_breaker = CircuitBreaker.new
  end

  def get(url)
    Retrier.with_retry(max_attempts: 3, exceptions: [Net::OpenTimeout, Net::ReadTimeout]) do
      @circuit_breaker.call do
        HTTP.timeout(5).get(url)
      end
    end
  end
end
```

---

## 4. Concurrency & Performance

#### Q: Difference between threads vs async vs multiprocessing

**Answer:**

**1. Threads (Shared Memory):**

```ruby
# Ruby threads share memory but GIL limits parallelism
threads = []

5.times do
  threads << Thread.new do
    puts "Thread #{Thread.current.object_id} processing"
    sleep 1
  end
end

threads.each(&:join)  # Wait for all threads
```

**Pros:**
- ✅ Lightweight (share memory)
- ✅ Good for I/O-bound tasks (HTTP requests, DB queries)

**Cons:**
- ❌ GIL in Ruby/Python (only one thread runs at a time)
- ❌ Not good for CPU-bound tasks

**2. Async (Event Loop):**

```ruby
# Ruby Async gem
require 'async'

Async do
  tasks = 10.times.map do |i|
    Async do
      response = HTTP.get("https://api.example.com/user/#{i}")
      puts "Got user #{i}"
    end
  end

  tasks.each(&:wait)
end
```

**Pros:**
- ✅ Very lightweight (single thread)
- ✅ Excellent for I/O-bound tasks
- ✅ High concurrency (1000+ connections)

**Cons:**
- ❌ Single-threaded (no CPU parallelism)
- ❌ Callback hell (can be mitigated with async/await)

**3. Multiprocessing (Separate Memory):**

```ruby
# Fork child processes
pids = []

5.times do
  pids << fork do
    puts "Process #{Process.pid} processing"
    # CPU-intensive work
    result = calculate_fibonacci(40)
    puts result
  end
end

pids.each { |pid| Process.wait(pid) }
```

**Pros:**
- ✅ True parallelism (multiple CPU cores)
- ✅ No GIL limitations
- ✅ Good for CPU-bound tasks

**Cons:**
- ❌ Heavy (separate memory, IPC overhead)
- ❌ Slower to create processes

**Decision Matrix:**

| Task Type | Best Choice | Example |
|-----------|-------------|---------|
| **I/O-bound** (network, disk) | Async or Threads | HTTP requests, DB queries |
| **CPU-bound** (computation) | Multiprocessing | Image processing, encryption |
| **Mixed** | Thread pool + process pool | Web server (Puma uses both) |

**Real-World Example (Puma Web Server):**

```ruby
# puma.rb config
workers 4           # 4 processes (multiprocessing)
threads 5, 5        # 5 threads per process (threading)

# Total concurrency: 4 processes × 5 threads = 20 concurrent requests
```

---

#### Q: How do you prevent race conditions?

**Answer:**

**1. Atomic Operations (Preferred):**

```ruby
# BAD - Race condition
count = REDIS.get('counter').to_i
count += 1
REDIS.set('counter', count)
# Problem: Two threads can read same value, both increment, last write wins

# GOOD - Atomic operation
REDIS.incr('counter')
# Redis INCR is atomic - no race condition possible
```

**My chat app uses this for sequential numbering:**
```ruby
# app/services/sequential_number_service.rb
def self.next_message_number(chat_id)
  REDIS.incr("chat:#{chat_id}:message_counter")  # Atomic!
end
```

**2. Database Locks:**

```ruby
# Pessimistic locking
ActiveRecord::Base.transaction do
  chat = Chat.lock.find(chat_id)  # SELECT ... FOR UPDATE
  chat.messages_count += 1
  chat.save!
end

# Optimistic locking
class Chat < ApplicationRecord
  # Migration: add_column :chats, :lock_version, :integer, default: 0

  def increment_count
    self.messages_count += 1
    save!  # Raises ActiveRecord::StaleObjectError if version changed
  end
end
```

**3. Mutexes (In-Process):**

```ruby
class ThreadSafeCounter
  def initialize
    @count = 0
    @mutex = Mutex.new
  end

  def increment
    @mutex.synchronize do
      @count += 1
    end
  end

  def value
    @mutex.synchronize { @count }
  end
end
```

**4. Database Unique Constraints:**

```ruby
# My chat app's safety net
# db/migrate/xxx_create_messages.rb
create_table :messages do |t|
  t.bigint :chat_id
  t.integer :number
end

add_index :messages, [:chat_id, :number], unique: true

# If somehow Redis gives duplicate number, database catches it
begin
  Message.create!(chat_id: 1, number: 5, body: "Hello")
rescue ActiveRecord::RecordNotUnique
  # Retry with new number
end
```

**5. Idempotency Keys:**

```ruby
# For distributed systems
def create_bug_report
  idempotency_key = request.headers['Idempotency-Key']

  # Check if already processed
  cached = REDIS.get("idempotency:#{idempotency_key}")
  return JSON.parse(cached) if cached

  # Process
  result = BugReport.create!(params)

  # Cache result
  REDIS.setex("idempotency:#{idempotency_key}", 86400, result.to_json)

  result
end
```

---

#### Q: What is a mutex, semaphore, and lock-free concurrency?

**Answer:**

**1. Mutex (Mutual Exclusion):**

```ruby
# Only one thread can hold the lock at a time
mutex = Mutex.new
shared_resource = []

threads = 10.times.map do
  Thread.new do
    mutex.synchronize do
      # Critical section - only one thread at a time
      shared_resource << Thread.current.object_id
      sleep 0.1
    end
  end
end

threads.each(&:join)
```

**2. Semaphore (Counting Lock):**

```ruby
# Allow N threads simultaneously
require 'thread'

semaphore = Mutex.new
available = ConditionVariable.new
count = 3  # Max 3 concurrent

def acquire(semaphore, available, count)
  semaphore.synchronize do
    while count.zero?
      available.wait(semaphore)
    end
    count -= 1
  end
end

def release(semaphore, available, count)
  semaphore.synchronize do
    count += 1
    available.signal
  end
end

# Usage: Connection pool (max 3 connections)
threads = 10.times.map do
  Thread.new do
    acquire(semaphore, available, count)
    # Use connection
    sleep 1
    release(semaphore, available, count)
  end
end
```

**3. Lock-Free Concurrency:**

```ruby
# Compare-And-Swap (CAS) - atomic operation
class LockFreeCounter
  def initialize
    @count = Concurrent::AtomicFixnum.new(0)
  end

  def increment
    loop do
      current = @count.value
      new_value = current + 1

      # Atomically: if @count still equals current, set to new_value
      break if @count.compare_and_set(current, new_value)

      # If failed (another thread changed it), retry
    end
  end

  def value
    @count.value
  end
end

# No locks needed - uses CPU-level atomic instructions
```

**When to Use:**

| Primitive | Use Case | Example |
|-----------|----------|---------|
| **Mutex** | Protect critical section | Updating shared data structure |
| **Semaphore** | Limit concurrent access | Connection pool (max 10 connections) |
| **Lock-free** | High-performance counters | Request counting, metrics |

---

#### Q: Explain thread pools and when to tune max workers

**Answer:**

**Thread Pool:**

```ruby
# Puma config
workers 4           # 4 processes (fork)
threads 5, 5        # Min 5, max 5 threads per process

# Total concurrency: 4 × 5 = 20 concurrent requests
```

**How It Works:**
```
Request Queue: [R1, R2, R3, R4, R5, R6, ...]
                   ↓    ↓    ↓    ↓    ↓
Thread Pool:    [T1] [T2] [T3] [T4] [T5]
                 ↓    ↓    ↓    ↓    ↓
                Processing requests
```

**Tuning Guidelines:**

**1. I/O-Bound (Database, HTTP, Disk):**

```ruby
# More threads = more concurrent I/O
# Formula: threads = (core_count * 2) + disk_count

# Example: 4 cores + 1 disk
# threads = (4 * 2) + 1 = 9

threads 9, 9

# Can go higher (20-50) if heavy I/O wait
```

**2. CPU-Bound (Computation, Encryption):**

```ruby
# More threads = worse (context switching overhead)
# Formula: threads = core_count

# Example: 4 cores
threads 4, 4

# Use processes for parallelism, not threads
workers 4
```

**3. Mixed Workload:**

```ruby
# Balance threads and processes
workers ENV.fetch("WEB_CONCURRENCY") { 2 }
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count
```

**Monitoring to Tune:**

```ruby
# Track metrics
- Thread pool utilization (busy_threads / total_threads)
- Queue depth (waiting requests)
- Response time (p95, p99)
- CPU usage
- Memory usage

# If utilization > 80% → Increase threads/workers
# If CPU > 80% → Don't add more threads (add processes or servers)
# If memory > 80% → Reduce workers
```

**Real-World Example:**

```ruby
# config/puma.rb
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

port ENV.fetch("PORT") { 3000 }

environment ENV.fetch("RAILS_ENV") { "development" }

workers ENV.fetch("WEB_CONCURRENCY") { 2 }

preload_app!

on_worker_boot do
  # Reconnect to database in each worker
  ActiveRecord::Base.establish_connection
end
```

---

#### Q: How do you handle CPU-bound vs IO-bound tasks?

**Answer:**

**CPU-Bound Tasks (Computation-heavy):**

```ruby
# Example: Image processing, encryption, compression

# BAD - Blocks web server
class ImagesController < ApplicationController
  def resize
    image = params[:image]
    resized = ImageProcessing.resize(image, width: 800)  # CPU-intensive!
    send_data resized
  end
end

# GOOD - Offload to background job
class ImagesController < ApplicationController
  def resize
    job_id = ImageResizeJob.perform_async(params[:image].path, 800)
    render json: { job_id: job_id, status: 'processing' }, status: :accepted
  end
end

# Use separate worker pool
class ImageResizeJob < ApplicationJob
  queue_as :cpu_intensive

  def perform(image_path, width)
    # Runs in dedicated worker process
    ImageProcessing.resize(File.read(image_path), width: width)
  end
end

# sidekiq.yml - Separate queues
:queues:
  - [default, 2]        # I/O tasks
  - [cpu_intensive, 1]  # CPU tasks (fewer workers)

# Run on different servers
# Server 1: CPU workers (high CPU, low RAM)
# Server 2: I/O workers (low CPU, high RAM)
```

**I/O-Bound Tasks (Network, Database):**

```ruby
# Example: HTTP requests, database queries

# Use threads (Ruby GIL doesn't block I/O)
class BugReportsController < ApplicationController
  def create
    # I/O operations: Redis, MySQL, Kafka
    number = REDIS.incr("chat:#{chat_id}:counter")  # I/O
    BugReport.create!(...)                           # I/O
    KafkaProducer.send(...)                          # I/O

    render json: { number: number }
  end
end

# Puma config - More threads for I/O
workers 2
threads 20, 20  # High thread count OK for I/O
```

**Hybrid Approach:**

```ruby
# Instabug's potential architecture
class BugEventProcessor
  def process(event)
    # I/O: Store raw event
    store_to_s3(event)  # I/O-bound

    # CPU: Parse stack trace
    parsed = parse_stack_trace(event[:stack_trace])  # CPU-bound

    # I/O: Index to Elasticsearch
    index_to_elasticsearch(parsed)  # I/O-bound
  end
end

# Split into multiple jobs
class ProcessBugEventJob < ApplicationJob
  queue_as :default  # I/O queue

  def perform(event)
    store_to_s3(event)

    # Enqueue CPU-intensive task to different queue
    ParseStackTraceJob.perform_async(event[:id])

    index_to_elasticsearch(event)
  end
end

class ParseStackTraceJob < ApplicationJob
  queue_as :cpu_intensive

  def perform(event_id)
    event = S3.get_object(...)
    parsed = parse_stack_trace(event[:stack_trace])
    event.update!(parsed_data: parsed)
  end
end
```

---

(Continuing with sections 5-9 in next message due to length...)


## 5. Microservices & Architecture

#### Q: How do you break a monolith into microservices?

**Answer:**

**Step 1: Identify Bounded Contexts (Domain-Driven Design):**

```
Monolith (Instabug):
├── User Management
├── Bug Reporting  
├── Crash Analytics
├── Session Replay
├── Notifications
└── Billing

Microservices:
1. Auth Service (user management, API keys)
2. Ingestion Service (receive bug reports)
3. Storage Service (persist to S3/DB)
4. Processing Service (parse, group, ML)
5. Notification Service (email, Slack, webhooks)
6. Analytics Service (aggregations, dashboards)
7. Billing Service (subscriptions, usage tracking)
```

**Step 2: Strangler Fig Pattern (Gradual Migration):**

```
Client → Monolith → Database
           ↓
     (Extract service gradually)
           ↓
Client → API Gateway
           ├→ Monolith (legacy features)
           └→ Notification Service (new service)
```

**Step 3: Extract Service:**

```ruby
# Before (Monolith)
class BugReport
  after_create :send_notifications

  def send_notifications
    send_email
    send_slack
    trigger_webhooks
  end
end

# After (Microservice Pattern)
class BugReport
  after_create :publish_event

  def publish_event
    EventBus.publish('bug.created', {
      bug_id: id,
      app_id: app_id,
      severity: severity
    })
  end
end

# Notification Service (separate app)
class BugCreatedConsumer
  def consume(event)
    bug = fetch_bug_details(event[:bug_id])

    # Send notifications
    EmailService.send(bug)
    SlackService.send(bug)
    WebhookService.trigger(bug)
  end
end
```

**Step 4: Database Per Service:**

```
Monolith Database:
├── users
├── bug_reports
├── notifications
└── billing

Split:
Auth Service → users (PostgreSQL)
Ingestion Service → events (Kafka)
Storage Service → bug_reports (MongoDB)
Notification Service → notification_queue (Redis)
Billing Service → subscriptions (PostgreSQL)
```

**Communication Patterns:**

**1. Synchronous (REST/gRPC):**
```ruby
# Auth Service API
class AuthService
  def validate_api_key(api_key)
    HTTP.get("http://auth-service/validate?key=#{api_key}")
  end
end
```

**2. Asynchronous (Message Queue):**
```ruby
# Event-driven
EventBus.publish('bug.created', data)
# → Notification Service consumes
# → Analytics Service consumes
# → Storage Service consumes
```

**3. Data Replication:**
```ruby
# Keep copy of needed data to avoid cross-service calls
# Ingestion Service has cached copy of app metadata
class IngestionService
  def process_bug(data)
    app = @local_cache.get(data[:app_id])  # Cached from Auth Service
    # Don't call Auth Service on every request
  end
end
```

**Challenges & Solutions:**

| Challenge | Solution |
|-----------|----------|
| **Distributed Transactions** | Saga pattern, eventual consistency |
| **Network Latency** | Circuit breakers, timeouts, retries |
| **Data Consistency** | Event sourcing, CQRS |
| **Service Discovery** | Kubernetes, Consul, service mesh |
| **Monitoring** | Distributed tracing (OpenTelemetry) |

---

#### Q: How do services communicate? (REST, gRPC, message queues)

**Answer:**

**1. REST (HTTP/JSON):**

```ruby
# Notification Service calls User Service
class NotificationService
  def send_email(bug_id)
    # Get user details
    user = HTTP.get("http://user-service/users/#{user_id}").parse

    # Send email
    Mailer.send(to: user['email'], subject: "New bug ##{bug_id}")
  end
end
```

**Pros:**
- ✅ Simple, well-understood
- ✅ Language-agnostic
- ✅ Human-readable (debugging)

**Cons:**
- ❌ Slower (JSON serialization, HTTP overhead)
- ❌ No type safety
- ❌ Verbose

**2. gRPC (Protobuf):**

```protobuf
// user_service.proto
service UserService {
  rpc GetUser(GetUserRequest) returns (UserResponse);
}

message GetUserRequest {
  string user_id = 1;
}

message UserResponse {
  string user_id = 1;
  string email = 2;
  string name = 3;
}
```

```ruby
# Client
user_service = UserService::Stub.new('user-service:50051')
response = user_service.get_user(GetUserRequest.new(user_id: '123'))
puts response.email
```

**Pros:**
- ✅ Fast (binary protocol, HTTP/2)
- ✅ Type-safe (generated code from .proto)
- ✅ Streaming support

**Cons:**
- ❌ Not human-readable
- ❌ More complex setup
- ❌ Firewall issues (HTTP/2)

**3. Message Queue (Async):**

```ruby
# Producer
EventBus.publish('user.created', {
  user_id: '123',
  email: 'user@example.com',
  created_at: Time.now
})

# Consumer 1 (Notification Service)
class UserCreatedConsumer
  def consume(event)
    send_welcome_email(event[:email])
  end
end

# Consumer 2 (Analytics Service)
class UserCreatedAnalytics
  def consume(event)
    track_new_user(event[:user_id])
  end
end
```

**Pros:**
- ✅ Decoupling (producer doesn't know consumers)
- ✅ Scalable (multiple consumers)
- ✅ Resilient (queue buffers failures)

**Cons:**
- ❌ Eventual consistency
- ❌ More complex debugging
- ❌ No immediate response

**Decision Matrix:**

| Use Case | Best Choice |
|----------|-------------|
| **Read user profile** | REST (simple, synchronous) |
| **Validate API key** | gRPC (fast, frequent calls) |
| **Bug created event** | Message Queue (multiple consumers) |
| **Send notification** | Message Queue (async, not critical path) |
| **Process payment** | REST with retries (need synchronous confirmation) |

**My Chat App Example:**
```ruby
# My Go service calls Rails Sidekiq via Redis (message queue pattern)
# go-service/queue/sidekiq.go → Redis → Rails Sidekiq workers
```

---

#### Q: How do you detect and avoid cascading failures?

**Answer:**

**Problem:**
```
Service A → Service B (down) → Service C
              ↓
       A waits forever
       A's threads exhausted
       A can't serve other requests
       A goes down
       All services depending on A go down
       CASCADE!
```

**Solution 1: Timeouts:**

```ruby
# Set aggressive timeouts
HTTP.timeout(connect: 1, read: 5).get('http://service-b/data')
```

**Solution 2: Circuit Breaker:**

```ruby
class CircuitBreaker
  STATES = [:closed, :open, :half_open]

  def initialize(failure_threshold: 5, timeout: 60)
    @failure_threshold = failure_threshold
    @timeout = timeout
    @failures = 0
    @state = :closed
    @opened_at = nil
  end

  def call
    case @state
    when :open
      # Circuit open - fail fast
      if Time.now - @opened_at > @timeout
        # Try half-open (allow one request through)
        @state = :half_open
      else
        raise CircuitOpenError, 'Circuit breaker is open'
      end
    end

    begin
      result = yield
      reset_failures  # Success
      result
    rescue => e
      record_failure
      raise
    end
  end

  private

  def record_failure
    @failures += 1
    if @failures >= @failure_threshold
      @state = :open
      @opened_at = Time.now
    end
  end

  def reset_failures
    @failures = 0
    @state = :closed
  end
end

# Usage
breaker = CircuitBreaker.new
begin
  breaker.call { HTTP.get('http://flaky-service/data') }
rescue CircuitOpenError
  # Return cached data or error
  cached_data
end
```

**Solution 3: Bulkheads (Isolate Resources):**

```ruby
# Separate thread pools per service
class ServiceClients
  def initialize
    @user_service_pool = ConnectionPool.new(size: 5) { HTTP }
    @bug_service_pool = ConnectionPool.new(size: 10) { HTTP }
  end

  def get_user(id)
    @user_service_pool.with do |http|
      http.get("http://user-service/users/#{id}")
    end
  end

  def get_bug(id)
    @bug_service_pool.with do |http|
      http.get("http://bug-service/bugs/#{id}")
    end
  end
end

# If bug-service is slow, it only exhausts its pool (10 connections)
# user-service still works with its own pool (5 connections)
```

**Solution 4: Graceful Degradation:**

```ruby
class BugDetailsService
  def get_bug_with_user(bug_id)
    bug = BugRepository.find(bug_id)

    begin
      # Try to enrich with user data
      user = UserService.get_user(bug.user_id)
      bug.user = user
    rescue ServiceError
      # User service down - continue without user data
      bug.user = nil
    end

    bug
  end
end
```

**Solution 5: Rate Limiting:**

```ruby
# Limit requests to protect downstream service
class ApiGateway
  def call_service_b
    unless rate_limiter.allow?('service_b', limit: 1000)
      # Don't overwhelm service B
      render json: { error: 'Service temporarily unavailable' }, status: 503
    end

    ServiceB.call
  end
end
```

**Solution 6: Health Checks & Load Balancer:**

```yaml
# Kubernetes - remove unhealthy pods
livenessProbe:
  httpGet:
    path: /health
    port: 3000
  initialDelaySeconds: 10
  periodSeconds: 5

readinessProbe:
  httpGet:
    path: /ready
    port: 3000
  periodSeconds: 5
```

**Monitoring:**

```ruby
# Track circuit breaker state
Metrics.gauge('circuit_breaker.state', breaker.open? ? 1 : 0)
Metrics.gauge('service_b.failures', breaker.failures)

# Alert on too many open circuits
if open_circuits_count > 3
  alert('Multiple circuits open - cascading failure detected!')
end
```

---

## 6. DevOps Knowledge

#### Q: Docker basics—image layers, Dockerfile best practices

**Answer:**

**Image Layers:**

```dockerfile
# Each instruction creates a layer
FROM ruby:3.3-alpine         # Layer 1 (base image)
RUN apk add --no-cache mysql # Layer 2 (dependencies)
WORKDIR /app                 # Layer 3 (metadata only)
COPY Gemfile .               # Layer 4 (gemfile)
RUN bundle install           # Layer 5 (gems)
COPY . .                     # Layer 6 (app code)
CMD ["rails", "server"]      # Layer 7 (metadata only)
```

**Layers are cached:**
```
Build 1: Layers 1-7 built
Build 2: Code change → Only Layer 6-7 rebuilt (Layers 1-5 cached)
```

**Best Practices:**

**1. Order matters (most stable → least stable):**

```dockerfile
# BAD - Code changes invalidate all layers
FROM ruby:3.3
COPY . /app          # Layer 1 - changes often
RUN bundle install   # Layer 2 - invalidated every code change!

# GOOD - Dependencies cached separately
FROM ruby:3.3
COPY Gemfile Gemfile.lock /app/  # Layer 1 - changes rarely
RUN bundle install                # Layer 2 - cached unless Gemfile changes
COPY . /app                       # Layer 3 - changes often, doesn't affect layer 2
```

**2. Minimize layers (combine RUN commands):**

```dockerfile
# BAD - 3 layers
RUN apk update
RUN apk add mysql-dev
RUN apk add build-base

# GOOD - 1 layer
RUN apk update && \
    apk add --no-cache mysql-dev build-base && \
    rm -rf /var/cache/apk/*
```

**3. Use .dockerignore:**

```
# .dockerignore
node_modules/
tmp/
log/
.git/
*.log

# Prevents copying unnecessary files → smaller image
```

**4. Multi-stage builds (smaller final image):**

```dockerfile
# Build stage
FROM ruby:3.3 AS builder
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

# Runtime stage
FROM ruby:3.3-alpine
WORKDIR /app

# Copy only gems, not build tools
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY . .

CMD ["rails", "server"]
```

**5. Use specific versions (reproducible builds):**

```dockerfile
# BAD - version can change
FROM ruby:3.3

# GOOD - pinned version
FROM ruby:3.3.0-alpine3.19
```

**6. Run as non-root user (security):**

```dockerfile
FROM ruby:3.3-alpine

# Create app user
RUN addgroup -g 1000 app && \
    adduser -D -u 1000 -G app app

# Set ownership
WORKDIR /app
COPY --chown=app:app . .

# Switch to non-root user
USER app

CMD ["rails", "server"]
```

**My Chat App Dockerfile:**
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

---

#### Q: Kubernetes basics—deployments, autoscaling, health checks

**Answer:**

**1. Deployment (Manages Pods):**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rails-api
spec:
  replicas: 3  # 3 pods running
  selector:
    matchLabels:
      app: rails-api

  template:  # Pod template
    metadata:
      labels:
        app: rails-api
    spec:
      containers:
      - name: rails
        image: myapp/rails:v1.2.3
        ports:
        - containerPort: 3000

        # Resource limits
        resources:
          requests:
            cpu: 100m      # 0.1 CPU core
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 1Gi

        # Environment variables
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
```

**2. Service (Load Balancer):**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: rails-api-service
spec:
  type: LoadBalancer
  selector:
    app: rails-api
  ports:
  - port: 80
    targetPort: 3000  # Pod port
```

**3. Horizontal Pod Autoscaler (HPA):**

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: rails-api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: rails-api

  minReplicas: 3
  maxReplicas: 50

  metrics:
  # Scale based on CPU
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70  # Scale when avg CPU > 70%

  # Scale based on custom metric
  - type: Pods
    pods:
      metric:
        name: requests_per_second
      target:
        type: AverageValue
        averageValue: "1000"  # Scale when > 1k req/sec per pod
```

**4. Health Checks:**

```yaml
spec:
  containers:
  - name: rails
    image: myapp/rails

    # Liveness probe (restart if fails)
    livenessProbe:
      httpGet:
        path: /health
        port: 3000
      initialDelaySeconds: 30  # Wait 30s after start
      periodSeconds: 10        # Check every 10s
      timeoutSeconds: 5
      failureThreshold: 3      # Restart after 3 failures

    # Readiness probe (remove from load balancer if fails)
    readinessProbe:
      httpGet:
        path: /ready
        port: 3000
      initialDelaySeconds: 10
      periodSeconds: 5
      failureThreshold: 2
```

**Rails Health Endpoints:**

```ruby
# config/routes.rb
get '/health', to: 'health#index'    # Liveness
get '/ready', to: 'health#ready'     # Readiness

# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def index
    # Basic health check
    render json: { status: 'ok' }, status: :ok
  end

  def ready
    # Check if ready to serve traffic
    # (database connected, migrations run, etc.)
    if database_connected? && redis_connected?
      render json: { status: 'ready' }, status: :ok
    else
      render json: { status: 'not ready' }, status: :service_unavailable
    end
  end
end
```

**Scaling Behavior:**

```
Initial: 3 pods
│
├─> Traffic increases → CPU 80%
├─> HPA adds 3 more pods (double)
├─> Now 6 pods → CPU drops to 40%
│
├─> Traffic keeps increasing → CPU 70% again
├─> HPA adds 6 more pods
├─> Now 12 pods
│
└─> Traffic decreases → CPU 30%
    └─> HPA waits 5 minutes (stabilization)
        └─> Scales down to 6 pods
```

---

## 7. Monitoring, Logging, and Observability

#### Q: Difference between logs, metrics, and traces

**Answer:**

**1. Logs (Events):**

```ruby
# Structured logging
logger.info('Request completed', {
  method: 'POST',
  path: '/api/bugs',
  status: 201,
  duration_ms: 125,
  user_id: 'user123'
})

# Output: [2025-01-17 10:30:00] INFO Request completed method=POST path=/api/bugs status=201 duration_ms=125 user_id=user123
```

**Use for:**
- Debugging specific issues
- Audit trails
- Error investigation

**2. Metrics (Numbers):**

```ruby
# Counter (always increasing)
Metrics.increment('api.requests.total', tags: { endpoint: '/api/bugs', status: 201 })

# Gauge (can go up/down)
Metrics.gauge('database.connections.active', 15)

# Histogram (distribution)
Metrics.histogram('api.response_time', 125, tags: { endpoint: '/api/bugs' })
```

**Use for:**
- Dashboards
- Alerts (CPU > 80%)
- Trends over time

**3. Traces (Request flow):**

```ruby
# Distributed tracing
OpenTelemetry.tracer.in_span('process_bug') do |span|
  span.set_attribute('bug.id', bug_id)

  # Nested span
  OpenTelemetry.tracer.in_span('validate_bug') do
    validate(bug)
  end

  OpenTelemetry.tracer.in_span('store_bug') do
    store(bug)
  end
end

# Trace ID: abc123
# ├─ process_bug (200ms)
#    ├─ validate_bug (50ms)
#    └─ store_bug (150ms)
#       ├─ database_query (100ms)
#       └─ elasticsearch_index (50ms)
```

**Use for:**
- Finding bottlenecks
- Understanding request flow across services
- Debugging latency

**Comparison:**

| Aspect | Logs | Metrics | Traces |
|--------|------|---------|--------|
| **Format** | Text/JSON | Numbers | Spans with timing |
| **Volume** | High | Low | Medium |
| **Query** | "Show me errors with 'timeout'" | "What's avg response time?" | "Why was request XYZ slow?" |
| **Retention** | 30 days | 1 year+ | 7 days |
| **Tools** | ELK, Splunk | Prometheus, DataDog | Jaeger, Zipkin |

---

#### Q: What are SLOs, SLIs, SLAs?

**Answer:**

**SLI (Service Level Indicator) - Measurement:**

```ruby
# Availability SLI
successful_requests = 990
total_requests = 1000
availability = (successful_requests / total_requests.to_f) * 100
# => 99.0%

# Latency SLI
p95_response_time = 250  # ms
# => 95% of requests complete in < 250ms
```

**SLO (Service Level Objective) - Target:**

```
Availability SLO: 99.9% uptime
Latency SLO: p95 < 200ms
Error Rate SLO: < 0.1% errors
```

**SLA (Service Level Agreement) - Contract:**

```
SLA:
- If availability < 99.9% in a month → 10% credit
- If availability < 99.0% in a month → 25% credit
- Measured by successful API responses (2xx, 3xx)
```

**Real Example for Instabug:**

```ruby
# SLI: Measure
class SLITracker
  def track_request(duration_ms, status)
    # Availability
    Metrics.increment('sli.requests.total')
    Metrics.increment('sli.requests.successful') if status < 500

    # Latency
    Metrics.histogram('sli.latency', duration_ms)

    # Error rate
    Metrics.increment('sli.errors') if status >= 500
  end

  def calculate_sli(window: 30.days)
    total = Metrics.query('sli.requests.total', window)
    successful = Metrics.query('sli.requests.successful', window)

    {
      availability: (successful / total.to_f) * 100,
      p95_latency: Metrics.percentile('sli.latency', 95, window),
      error_rate: ((total - successful) / total.to_f) * 100
    }
  end
end

# SLO: Define targets
SLOS = {
  availability: 99.9,  # %
  p95_latency: 200,    # ms
  error_rate: 0.1      # %
}

# Alert if SLI < SLO
if sli[:availability] < SLOS[:availability]
  alert('Availability SLO violated!')
end
```

**Error Budget:**

```ruby
# If SLO is 99.9%, we can be down 0.1% of the time
uptime_target = 0.999
downtime_allowed = 1 - uptime_target  # 0.001 = 0.1%

# In 30 days
seconds_in_30_days = 30 * 24 * 60 * 60  # 2,592,000
error_budget_seconds = seconds_in_30_days * downtime_allowed  # 2,592 seconds = 43.2 minutes

# Track error budget
remaining_budget = error_budget_seconds - actual_downtime
if remaining_budget < 0
  # Violated SLO - slow down feature releases, focus on reliability
end
```

---

## 8. Backend Language Knowledge

#### Q: Memory leaks—how to debug?

**Answer:**

**Ruby Memory Leak Detection:**

```ruby
# 1. Track memory usage over time
class MemoryProfiler
  def self.track
    before = memory_usage
    yield
    after = memory_usage

    puts "Memory delta: #{after - before} MB"
  end

  def self.memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i / 1024.0  # MB
  end
end

# Usage
MemoryProfiler.track do
  10_000.times { process_request }
end

# 2. Find objects not being garbage collected
require 'objspace'

before = ObjectSpace.count_objects
10_000.times { create_bug_report }
after = ObjectSpace.count_objects

diff = after.transform_values.with_index do |count, i|
  count - before.values[i]
end

puts diff
# => { T_STRING: 50000, T_ARRAY: 10000, ... }
# Suspect: Too many strings/arrays created and not freed
```

**Common Memory Leaks in Ruby:**

**1. Global Variables:**

```ruby
# BAD - Leak
$cache = {}
def process(data)
  $cache[data[:id]] = data  # Never freed!
end

# GOOD - Use LRU cache with size limit
@cache = LRUCache.new(1000)
```

**2. Circular References (rare in Ruby due to GC):**

```ruby
# Can cause issues with C extensions
class Node
  attr_accessor :parent, :children

  def initialize
    @children = []
  end
end

parent = Node.new
child = Node.new
child.parent = parent
parent.children << child
# Circular reference - Ruby GC handles this, but be careful
```

**3. Not Closing Resources:**

```ruby
# BAD - File handle leak
def process_log
  file = File.open('log.txt')
  # If exception occurs, file not closed
  process(file.read)
end

# GOOD - Ensure cleanup
def process_log
  File.open('log.txt') do |file|
    process(file.read)
  end  # Automatically closed
end
```

**4. Memoization Gone Wrong:**

```ruby
# BAD - Memoizes forever
class BugReport
  def parsed_stack_trace
    @parsed ||= parse_stack_trace(@stack_trace)  # Cached per instance
  end
end

# If you keep creating BugReport instances and never free them, leak!

# GOOD - Clear cache periodically
class BugReport
  def parsed_stack_trace
    @parsed ||= parse_stack_trace(@stack_trace)
  end

  def clear_cache
    @parsed = nil
  end
end
```

**Debugging Tools:**

```ruby
# memory_profiler gem
require 'memory_profiler'

report = MemoryProfiler.report do
  10_000.times { process_request }
end

report.pretty_print
# Shows:
# - Total allocated objects
# - Retained objects (not freed)
# - Objects by class
# - Stack traces of allocations
```

---

## 9. Culture Fit (Technical Judgment)

#### Q: Describe a time you handled a production incident

**Answer:**

**STAR Method (Situation, Task, Action, Result):**

**Situation:**
"At my previous job, we had a production incident where our API response times spiked from 50ms to 5 seconds at 2 AM. Customers couldn't submit bug reports."

**Task:**
"As the on-call engineer, I needed to quickly identify the root cause and restore service."

**Action:**
1. **Triage (5 min):**
   - Checked dashboard: p95 latency 5000ms (normally 50ms)
   - Checked error logs: No errors, just slow
   - Checked database: CPU 20%, not the bottleneck
   - Checked Redis: 100% CPU usage!

2. **Root Cause (10 min):**
   - Ran `redis-cli SLOWLOG GET 10`
   - Found: Repeated `KEYS *` command (O(N) operation!)
   - Traced to new feature: "List all active sessions"
   - Developer used `REDIS.keys('session:*')` in production

3. **Immediate Fix (5 min):**
   - Deployed hotfix: Changed `KEYS` to `SCAN` (non-blocking)
   - Latency dropped to 50ms immediately

4. **Post-Incident:**
   - Added Redis slow log monitoring
   - Created coding guideline: Never use `KEYS` in production
   - Added pre-merge check in CI: grep for `redis.keys`

**Result:**
- Downtime: 20 minutes total
- Root cause: Inefficient Redis query
- Prevention: Monitoring + automation + guidelines
- Learning: Shared incident post-mortem with team

**Key Takeaways:**
- Stay calm, follow runbook
- Check metrics first (dashboard > logs)
- Fix fast, root cause later
- Document and prevent recurrence

---

#### Q: How do you design for failure?

**Answer:**

**1. Assume Everything Fails:**

```ruby
# External API will fail
def fetch_user_data(id)
  Retrier.with_retry(max_attempts: 3) do
    response = HTTP.timeout(5).get("https://api.example.com/users/#{id}")

    if response.status == 200
      response.parse
    else
      raise APIError
    end
  end
rescue => e
  # Return cached data if available
  cache.get("user:#{id}") || default_user_data
end
```

**2. Fail Fast:**

```ruby
# Don't wait forever
HTTP.timeout(connect: 1, read: 5).get(url)

# Not this:
HTTP.get(url)  # Default timeout: 60s!
```

**3. Graceful Degradation:**

```ruby
# Non-critical features can fail
def show_bug(id)
  bug = BugRepository.find(id)

  begin
    bug.user = UserService.get_user(bug.user_id)  # Nice-to-have
  rescue ServiceError
    bug.user = nil  # Continue without user data
  end

  bug
end
```

**4. Circuit Breakers:**

```ruby
# Don't retry if service is down
breaker = CircuitBreaker.new
breaker.call { SlackService.notify(bug) }
```

**5. Bulkheads (Isolate Failures):**

```ruby
# Separate thread pools
@critical_pool = ConnectionPool.new(size: 20)
@optional_pool = ConnectionPool.new(size: 5)

# If optional service is slow, doesn't affect critical
```

**6. Health Checks:**

```ruby
# Let load balancer remove unhealthy instances
get '/health', to: 'health#index'
```

**7. Chaos Engineering:**

```ruby
# Intentionally inject failures (staging)
if ENV['CHAOS_MONKEY'] == 'true'
  raise RandomError if rand < 0.1  # 10% failure rate
end
```

---

#### Q: How do you review pull requests?

**Answer:**

**My PR Review Checklist:**

**1. Functionality:**
- ✅ Does it solve the problem?
- ✅ Are edge cases handled?
- ✅ Are error cases handled?

**2. Code Quality:**
- ✅ Is it readable? (Clear variable names, no magic numbers)
- ✅ Is it DRY? (No code duplication)
- ✅ Is it SOLID? (Single responsibility, etc.)

**3. Performance:**
- ✅ Any N+1 queries?
- ✅ Are database indexes needed?
- ✅ Is pagination used for large datasets?

**4. Security:**
- ✅ SQL injection risk?
- ✅ XSS risk?
- ✅ Authentication/authorization checked?
- ✅ Secrets in code? (Should be in env vars)

**5. Tests:**
- ✅ Are there tests?
- ✅ Do tests cover edge cases?
- ✅ Are tests readable?

**6. Documentation:**
- ✅ Are complex parts commented?
- ✅ Is API documentation updated?
- ✅ Is README updated if needed?

**Example PR Comment:**

```
Great work on the bug grouping feature! A few suggestions:

**Performance:**
Line 42: This query will cause N+1 problem when loading bug reports.
```ruby
# Current
bugs.each { |bug| bug.user.email }

# Suggested
bugs.includes(:user).each { |bug| bug.user.email }
```

**Security:**
Line 67: User input not sanitized, potential XSS risk.
```ruby
# Current
render html: params[:message]

# Suggested
render html: sanitize(params[:message])
```

**Testing:**
Missing test case for empty stack trace. Can you add:
```ruby
it 'handles empty stack trace' do
  bug = Bug.new(stack_trace: '')
  expect(bug.group_id).to be_nil
end
```

Otherwise looks good! Approving once these are addressed.
```

---

## Summary

**Key Takeaways:**

1. **Design for Scale**: Use async processing, caching, partitioning
2. **Design for Failure**: Timeouts, retries, circuit breakers
3. **Observability**: Logs, metrics, traces - know what's happening
4. **Security**: Validate inputs, don't trust clients
5. **Performance**: Profile first, optimize bottlenecks
6. **Simplicity**: Simple > complex, complex > complicated

**How These Connect to My Chat App:**

- **Async Processing**: My message creation uses Sidekiq (same pattern at scale)
- **Race Conditions**: Redis INCR for sequential numbers (production-ready)
- **Error Handling**: Database constraints + job retries (defense in depth)
- **Microservices**: Go + Rails share infrastructure (polyglot pattern)
- **Observability**: Health checks, structured logs (foundation for scale)

**For Instabug Interview:**

- Explain *why*, not just *what*
- Show trade-offs considered
- Relate to real-world scale (millions of events)
- Demonstrate production thinking (monitoring, errors, edge cases)
- Be honest about what you don't know, but show learning approach

Good luck! 🚀

