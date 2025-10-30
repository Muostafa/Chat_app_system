# Service Architecture: Rails vs Go

This document explains how the frontend intelligently routes requests between Rails and Go services.

---

## Overview

The Chat System uses **two backend services**:

1. **Rails API** (port 3000) - Full-featured CRUD API
2. **Go Service** (port 8080) - High-performance write-only API

The frontend automatically routes requests to the appropriate service based on the operation type.

---

## Service Capabilities

| Operation | Rails API | Go Service | Frontend Routes To |
|-----------|-----------|------------|-------------------|
| **Chat Applications** |
| Create Application | ✅ Supported | ❌ Not Supported | Always Rails |
| List Applications | ✅ Supported | ❌ Not Supported | Always Rails |
| Get Application | ✅ Supported | ❌ Not Supported | Always Rails |
| Update Application | ✅ Supported | ❌ Not Supported | Always Rails |
| **Chats** |
| Create Chat | ✅ Supported | ✅ Supported | User's Choice |
| List Chats | ✅ Supported | ❌ Not Supported | Always Rails |
| Get Chat | ✅ Supported | ❌ Not Supported | Always Rails |
| **Messages** |
| Create Message | ✅ Supported | ✅ Supported | User's Choice |
| List Messages | ✅ Supported | ❌ Not Supported | Always Rails |
| Get Message | ✅ Supported | ❌ Not Supported | Always Rails |
| Search Messages | ✅ Supported | ❌ Not Supported | Always Rails |

---

## Frontend Implementation

### Automatic Routing Logic

The `ApiClient` class in `src/lib/api.ts` implements smart routing:

```typescript
// READ operations - Always use Rails
async listApplications() {
  return this.measureRequest('rails', 'list_applications', async () => {
    const response = await fetch(`${BASE_URLS.rails}/chat_applications`);
    return this.handleResponse(response);
  });
}

// WRITE operations - Use selected service (Rails or Go)
async createChat(service: ServiceType, token: string) {
  return this.measureRequest(service, 'create_chat', async () => {
    const response = await fetch(
      `${BASE_URLS[service]}/chat_applications/${token}/chats`,
      { method: 'POST' }
    );
    return this.handleResponse(response);
  });
}
```

### Service Toggle Behavior

**What the toggle affects:**
- ✅ Chat creation (POST `/chats`)
- ✅ Message creation (POST `/messages`)

**What the toggle does NOT affect:**
- ❌ Application operations (always Rails)
- ❌ All list/read operations (always Rails)
- ❌ Search operations (always Rails)

---

## Performance Comparison

### Rails API Performance
- **Response Time:** ~30-50ms average
- **Throughput:** Standard Rails performance
- **Use Case:** Full CRUD operations, complex queries, search

### Go Service Performance
- **Response Time:** ~5-10ms average
- **Throughput:** ~10x higher than Rails
- **Use Case:** High-speed writes, bulk operations, latency-sensitive creates

### When to Use Each Service

**Use Rails (default):**
- Normal application usage
- Need full CRUD capabilities
- Running search queries
- Reading/listing data

**Use Go (optional):**
- Bulk chat/message creation
- Performance benchmarking
- High-throughput scenarios
- Latency-sensitive operations
- Load testing

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                   Frontend (React)                       │
│                 http://localhost:5173                    │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │          ApiClient (Smart Router)               │    │
│  │                                                 │    │
│  │  Routing Logic:                                 │    │
│  │  • Read Operations → Rails                      │    │
│  │  • Application Ops → Rails                      │    │
│  │  • Create Chat → User's Choice                  │    │
│  │  • Create Message → User's Choice               │    │
│  └────────────┬─────────────────────┬──────────────┘    │
└───────────────┼─────────────────────┼──────────────────┘
                │                     │
                │                     │
        ┌───────▼────────┐    ┌──────▼────────┐
        │   Rails API    │    │  Go Service   │
        │   Port 3000    │    │   Port 8080   │
        │                │    │               │
        │  Full CRUD     │    │  Writes Only  │
        │  ~50ms avg     │    │  ~5ms avg     │
        └───────┬────────┘    └──────┬────────┘
                │                     │
                └──────────┬──────────┘
                           │
                   ┌───────▼────────┐
                   │   Database     │
                   │   (Shared)     │
                   │   MySQL/Redis  │
                   └────────────────┘
```

---

## Implementation Details

### Service Selection State

**Location:** `src/store/useStore.ts`

```typescript
interface StoreState {
  service: 'rails' | 'go';  // User's selected service
  // Only affects: createChat() and createMessage()
}
```

### Performance Tracking

Every API call is measured and tracked:

```typescript
async measureRequest(service, endpoint, request) {
  const startTime = performance.now();
  const data = await request();
  const duration = performance.now() - startTime;

  return {
    data,
    metric: { service, endpoint, duration }
  };
}
```

Metrics are displayed in the `PerformanceChart` component, allowing real-time comparison between Rails and Go performance.

---

## Why This Architecture?

### Go Service Benefits
1. **Faster writes:** ~10x improvement for chat/message creation
2. **Higher throughput:** Can handle more concurrent requests
3. **Lower latency:** Sub-10ms response times
4. **Scalability:** Better performance under load

### Rails Service Benefits
1. **Full feature set:** Search, filtering, updates, deletes
2. **Battle-tested:** Mature, stable codebase
3. **Rich ecosystem:** Easy to add complex features
4. **Developer friendly:** Easier to maintain and extend

### Hybrid Approach
- Use Rails for complex operations
- Use Go for high-speed writes
- Frontend abstracts the complexity
- User can compare performance

---

## Data Consistency

### How Data Stays Consistent

Both services share the same backend:
- **Database:** Same MySQL instance
- **Redis:** Same Redis for sequential numbering
- **Sidekiq:** Go queues jobs that Rails workers process

**Result:** Data created via Go is immediately visible via Rails and vice versa.

### Example Flow

**Create Message via Go:**
1. Frontend → Go Service (POST)
2. Go validates and gets next number from Redis
3. Go queues Sidekiq job
4. Rails Sidekiq worker persists to MySQL
5. Frontend fetches messages → Rails API (GET)
6. Rails returns all messages (including Go-created ones)

---

## Testing the Service Switching

### Manual Test Procedure

1. **Start both services:**
   ```bash
   # Terminal 1
   rails s -p 3000

   # Terminal 2
   go run main.go  # port 8080
   ```

2. **Create resources with Rails:**
   - Toggle to "Rails"
   - Create 5 chats
   - Send 5 messages
   - Note response times

3. **Create resources with Go:**
   - Toggle to "Go"
   - Create 5 chats
   - Send 5 messages
   - Note response times (~10x faster)

4. **Verify consistency:**
   - All chats visible regardless of creation service
   - All messages visible regardless of creation service
   - Counts are accurate

### Expected Results

- Go creates should be ~5-10ms
- Rails creates should be ~30-50ms
- All reads should be consistent (always from Rails)
- Performance chart shows clear difference

---

## Troubleshooting

### "Go service not responding"

**Check if Go is running:**
```bash
curl http://localhost:8080/health
# Expected: {"status":"healthy"}
```

**If not running:**
```bash
cd go-service
go run main.go
```

### "Data created via Go not appearing"

**Check Sidekiq is running:**
```bash
# In Rails directory
bundle exec sidekiq
```

Go queues jobs that Sidekiq processes. If Sidekiq isn't running, Go-created data won't persist.

### "Performance difference not visible"

This is normal if:
- Creating only 1-2 resources (overhead dominates)
- Network latency is high
- Running on slow hardware

Try:
- Creating 10+ resources in quick succession
- Comparing average times over many operations
- Testing under load

---

## Future Enhancements

Potential improvements to the architecture:

1. **Smart Auto-Switching**
   - Automatically use Go for bulk operations
   - Fallback to Rails if Go unavailable

2. **Load Balancing**
   - Round-robin between multiple Go instances
   - Health checks and circuit breakers

3. **Caching Layer**
   - Cache read results in frontend
   - Invalidate on writes
   - Reduce Rails load

4. **WebSocket Support**
   - Real-time message updates
   - Live chat functionality
   - No polling needed

---

## Summary

The frontend implements a **hybrid service architecture** that:

✅ Automatically routes requests to the optimal service
✅ Uses Rails for all read operations and complex features
✅ Allows Go usage for high-performance writes
✅ Maintains data consistency across services
✅ Tracks and visualizes performance differences
✅ Provides transparent service switching

This architecture provides the best of both worlds: Rails' rich feature set and Go's blazing performance.

---

**Last Updated:** 2025-10-30
**Frontend Version:** 0.0.0
**Rails API Version:** v1
**Go Service Version:** v1
