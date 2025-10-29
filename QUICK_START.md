# Quick Start Guide

## 🚀 Start the System (3 Steps)

```bash
# 1. Start all services
docker-compose up

# 2. Wait 10 seconds for initialization

# 3. Verify it's running
curl http://localhost:3000/api/v1/chat_applications
```

That's it! The system is ready.

---

## 📝 Quick Demo

```bash
# Create an application
curl -X POST http://localhost:3000/api/v1/chat_applications \
  -H "Content-Type: application/json" \
  -d '{"chat_application": {"name": "My App"}}'

# Save the token from response
TOKEN="<paste-token-here>"

# Create a chat (Rails - standard)
curl -X POST http://localhost:3000/api/v1/chat_applications/$TOKEN/chats

# Create a chat (Go - faster!)
curl -X POST http://localhost:8080/api/v1/chat_applications/$TOKEN/chats

# Create a message
curl -X POST http://localhost:3000/api/v1/chat_applications/$TOKEN/chats/1/messages \
  -H "Content-Type: application/json" \
  -d '{"message": {"body": "Hello World!"}}'

# Search messages
curl "http://localhost:3000/api/v1/chat_applications/$TOKEN/chats/1/messages/search?q=Hello"
```

---

## ✅ Run Tests

```bash
# RSpec tests
docker-compose exec web bundle exec rspec

# End-to-end requirements test
bash test_requirements.sh
```

---

## 📊 Check Status

```bash
# View all containers
docker-compose ps

# View Rails logs
docker logs chat_system_web

# View Go service logs
docker logs chat_system_go

# View Sidekiq logs
docker logs chat_system_sidekiq
```

---

## 🛑 Stop the System

```bash
docker-compose down
```

---

## 📖 Full Documentation

- **README.md** - Complete setup guide
- **API_EXAMPLES.md** - All API endpoints with examples
- **SUBMISSION_CHECKLIST.md** - Requirements compliance
- **FINAL_SUBMISSION_SUMMARY.md** - Detailed summary

---

## 🎯 API Endpoints

**Base URLs:**
- Rails: `http://localhost:3000/api/v1`
- Go: `http://localhost:8080/api/v1` (chat/message creation only)

**Main Endpoints:**
```
POST   /chat_applications                                    Create app
GET    /chat_applications                                    List apps
GET    /chat_applications/:token                             Get app
PUT    /chat_applications/:token                             Update app

POST   /chat_applications/:token/chats                       Create chat
GET    /chat_applications/:token/chats                       List chats
GET    /chat_applications/:token/chats/:number               Get chat

POST   /chat_applications/:token/chats/:number/messages      Create message
GET    /chat_applications/:token/chats/:number/messages      List messages
GET    /chat_applications/:token/chats/:number/messages/:number  Get message
GET    /chat_applications/:token/chats/:number/messages/search?q=query  Search
```

---

## ⚡ Performance Tip

Use the Go service (port 8080) for chat and message creation - it's **10x faster**!

```bash
# Slow (~50ms)
curl -X POST http://localhost:3000/api/v1/chat_applications/$TOKEN/chats

# Fast (~5ms)
curl -X POST http://localhost:8080/api/v1/chat_applications/$TOKEN/chats
```

Both produce identical results.

---

## 🔍 Troubleshooting

**Problem:** Services not starting
```bash
# Solution: Check if ports are available
docker-compose down
docker-compose up
```

**Problem:** Tests failing
```bash
# Solution: Restart services
docker-compose restart
docker-compose exec web bundle exec rspec
```

**Problem:** Elasticsearch not responding
```bash
# Solution: Wait a bit longer (Elasticsearch takes ~30 seconds)
docker logs chat_system_elasticsearch
```

---

## ✨ System Requirements Met

✅ Docker containerization (`docker-compose up`)
✅ Chat applications with tokens
✅ Sequential numbering (race-safe)
✅ Elasticsearch search
✅ Count columns with async updates
✅ Queuing system (Sidekiq)
✅ Database indices
✅ RESTful API
✅ Ruby on Rails 8.1
✅ MySQL datastore
✅ Redis integration
✅ **BONUS:** Go microservice

**All tests passing:** 69 examples, 0 failures ✅

---

## 📧 Need Help?

1. Check the logs: `docker-compose logs -f`
2. Review the full README.md
3. Check FINAL_SUBMISSION_SUMMARY.md for detailed info
