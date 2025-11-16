# Interview Cheat Sheet - Quick Reference

## 30-Second Elevator Pitch
"Production-ready chat system with **polyglot microservices** (Rails + Go), **async processing** with Sidekiq, **full-text search** with Elasticsearch, and **race condition handling** using Redis atomic operations. Demonstrates distributed systems patterns at scale."

---

## Architecture Quick Facts

| Component | Technology | Port | Purpose |
|-----------|-----------|------|---------|
| Rails API | Ruby 8.1 | 3000 | Full CRUD, business logic |
| Go Service | Go 1.21 | 8080 | High-performance writes (10x faster) |
| Database | MySQL 8.0 | 3306 | ACID persistent storage |
| Cache/Counters | Redis 7 | 6379 | Atomic operations, job queue |
| Search | Elasticsearch 7.17 | 9200 | Full-text message search |
| Workers | Sidekiq | - | 5 async workers |
| Frontend | React + TypeScript | 80 | Interactive UI, performance tracking |

---

## Key Design Patterns

### 1. Sequential Numbering
```ruby
# Redis INCR = atomic operation (no race conditions)
number = redis.incr("chat_app:#{id}:chat_counter")

# DB unique constraint = safety net
add_index :chats, [:chat_application_id, :number], unique: true
```

### 2. Async Processing Flow
```
Request → Validate → Redis INCR → Enqueue Job → Return Response (<5ms)
                                        ↓
                        Background: MySQL + Elasticsearch (slow)
```

### 3. Go-Rails Integration
```
Go → Enqueue ActiveJob JSON → Redis Queue → Sidekiq Worker (Rails)
```

---

## Response Times

| Operation | Rails | Go | Improvement |
|-----------|-------|-----|-------------|
| Create Message | ~50ms | ~5ms | **10x** |
| Throughput | ~200/s | ~2000/s | **10x** |

---

## Data Model

```
ChatApplication (token: unique)
  └── has_many :chats (number: sequential per app)
       └── has_many :messages (number: sequential per chat)
            └── indexed in Elasticsearch (body field)
```

---

## Critical Interview Questions & Answers

### Q: "How do you prevent duplicate numbers under concurrency?"
**A:** "Redis INCR is atomic - single point of serialization. DB unique constraint catches edge cases. Sidekiq retries on conflicts."

### Q: "What if Redis goes down?"
**A:** "Writes fail (need Redis for numbers), reads still work. Production: Redis Sentinel for auto-failover. AOF persistence prevents data loss."

### Q: "Why async processing?"
**A:** "API responds before DB write = <5ms response time. Trade-off: eventual consistency (acceptable per requirements)."

### Q: "What if Elasticsearch fails?"
**A:** "Job logs error, doesn't fail. Message still in MySQL. Later: run ReindexMessagesJob to bulk reindex. Search is nice-to-have, not critical."

### Q: "Why both Rails and Go?"
**A:** "Right tool for the job. Rails = complex logic, integrations. Go = high-throughput writes. Real-world pattern (Twitter, Uber do this)."

### Q: "How do you scale to 1M messages/sec?"
**A:** "Horizontal scaling: 100+ API instances, 1000+ Sidekiq workers. Shard Redis (hash slots) and MySQL (by application_id). Consider Kafka + Cassandra."

---

## Code Locations

| Concept | File |
|---------|------|
| Sequential numbering | `app/services/sequential_number_service.rb` |
| Message creation (Rails) | `app/controllers/api/v1/messages_controller.rb` |
| Message creation (Go) | `go-service/handlers/message_handler.go` |
| Async jobs | `app/jobs/create_message_job.rb` |
| Elasticsearch model | `app/models/message.rb` |
| Go-Sidekiq integration | `go-service/queue/sidekiq.go` |
| Frontend API client | `frontend/src/lib/api.ts` |

---

## Demo Commands

### Start System
```bash
docker-compose up
```

### Create Application
```bash
curl -X POST http://localhost:3000/api/v1/applications \
  -H "Content-Type: application/json" \
  -d '{"name":"Demo App"}'
```

### Watch Redis Activity
```bash
docker exec -it chat_app_system-redis-1 redis-cli monitor
```

### Watch Sidekiq Jobs
```bash
docker-compose logs -f sidekiq
```

### Search Messages
```bash
curl "http://localhost:3000/api/v1/applications/{TOKEN}/chats/1/messages/search?query=hello"
```

---

## Trade-offs Made

| Decision | Pro | Con | Justification |
|----------|-----|-----|---------------|
| Async processing | Fast response | Eventual consistency | Requirements allow lag |
| Redis INCR | Atomic, fast | Single point of failure | Use Sentinel in prod |
| Cached counters | O(1) reads | 1-hour lag | Requirements allow lag |
| Elasticsearch | Great search | Ops complexity | Search is core feature |
| Go + Rails | Performance + productivity | Two codebases | Educational + realistic |

---

## Production Improvements

**Would add:**
- Authentication (JWT)
- Rate limiting
- Pagination
- WebSockets (real-time)
- Monitoring (Prometheus)
- Redis Sentinel (HA)
- MySQL replication
- API documentation (Swagger)
- Increased test coverage
- Database partitioning

---

## Technical Highlights to Mention

1. **Race condition handling** - Redis INCR + DB constraints
2. **Polyglot architecture** - Go speaks ActiveJob to Rails Sidekiq
3. **Eventual consistency** - CAP theorem applied (chose AP)
4. **Elasticsearch resilience** - Graceful degradation on failures
5. **Performance visualization** - Frontend tracks & charts metrics
6. **Docker orchestration** - 7 services with health checks
7. **Production patterns** - Tokens, API versioning, structured logging

---

## Common Mistakes to Avoid

- ❌ Don't say "I just used a library"
  - ✅ Say "I chose Redis INCR because it's atomic, unlike DB sequences which have table-level locks"

- ❌ Don't claim it's perfect
  - ✅ Say "For a demo it's solid, but production needs authentication, monitoring, and HA"

- ❌ Don't just explain what the code does
  - ✅ Explain **why** you made each decision and what alternatives you considered

- ❌ Don't get defensive about limitations
  - ✅ Say "Great question! Here's how I'd improve that..."

---

## Opening Statement Template

"I built a **chat application system** that demonstrates **distributed systems patterns**. The core challenge was **sequential numbering under high concurrency** - solved using **Redis INCR** for atomic operations.

I implemented **two backends** - Rails for full CRUD and Go for high-performance writes - both sharing the same infrastructure. The system uses **async processing** with Sidekiq for sub-5ms responses and **Elasticsearch** for full-text search.

The React frontend lets you **toggle between services** and see the **10x performance difference** in real-time. Everything runs in **Docker Compose** with proper health checks.

I'm excited to walk you through the architecture and discuss design trade-offs!"

---

## Closing Statement Template

"Working on this project taught me about:
- **Distributed systems complexity** - sequential numbering is hard under concurrency
- **Async processing trade-offs** - speed vs. consistency
- **Polyglot architecture** - when to use multiple languages

If I rebuilt it, I'd add **WebSockets for real-time updates**, **authentication with JWTs**, and **comprehensive monitoring**. But I'm proud of how the core architecture handles race conditions, graceful degradation, and performance optimization.

I'd love to discuss how these patterns apply to **Instabug's** challenges with error reporting at scale!"

---

## Body Language Tips

- ✅ Smile when discussing complex problems you solved
- ✅ Use hands to draw architecture in the air
- ✅ Make eye contact when explaining trade-offs
- ✅ Show enthusiasm when demoing the frontend
- ✅ Pause for questions - don't monologue
- ✅ Write on whiteboard if available (diagrams help!)

---

## If They Ask: "Walk me through your code"

**Order:**
1. Show `docker-compose.yml` - "7 services working together"
2. Show request flow diagram - "Let's follow a message creation"
3. Show `messages_controller.rb` - "API gets request, gets number, enqueues job"
4. Show `sequential_number_service.rb` - "Redis INCR is the magic"
5. Show `create_message_job.rb` - "Background persistence + Elasticsearch"
6. Show `message.rb` - "Model with Elasticsearch integration"
7. Demo frontend - "Visual proof of performance difference"
8. Ask: "Want to see the Go implementation comparison?"

---

**Remember:** You're not just explaining code, you're telling the story of solving a **distributed systems problem** with **production-ready patterns**. Show your thought process, not just the result!

Good luck! 🚀
