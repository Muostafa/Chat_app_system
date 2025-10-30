# Performance Chart Update

## Summary

The Performance Comparison chart has been updated to **only compare operations that both Rails and Go services support**, ensuring accurate and meaningful performance metrics.

---

## What Changed

### Before ❌
The chart was comparing ALL operations, including:
- Creating applications (Rails only)
- Listing applications (Rails only)
- Listing chats (Rails only)
- Listing messages (Rails only)
- Searching messages (Rails only)
- Creating chats (both services)
- Creating messages (both services)

**Problem:** This skewed the comparison because Go metrics only existed for 2 operations while Rails had metrics for all operations.

### After ✅
The chart now **only compares** the 2 operations Go actually supports:
- ✅ **Create Chat** (POST `/chats`)
- ✅ **Create Message** (POST `/messages`)

**Result:** Accurate apples-to-apples comparison of write performance.

---

## Implementation Details

### Filtering Logic

**Location:** `src/components/PerformanceChart.tsx:9-15`

```typescript
// Only compare endpoints that Go actually supports
const GO_SUPPORTED_ENDPOINTS = ['create_chat', 'create_message'];

// Filter to only show metrics for operations both services support
const comparableMetrics = metrics.filter(m =>
  GO_SUPPORTED_ENDPOINTS.includes(m.endpoint)
);
```

### Average Calculations

**Before:**
```typescript
// Calculated average across ALL operations
const avgRails = allRailsMetrics.reduce(...) / allRailsMetrics.length;
const avgGo = allGoMetrics.reduce(...) / allGoMetrics.length;
```

**After:**
```typescript
// Calculates average ONLY for comparable operations (create_chat, create_message)
const railsMetrics = comparableMetrics.filter(m => m.service === 'rails');
const goMetrics = comparableMetrics.filter(m => m.service === 'go');

const avgRails = railsMetrics.reduce(...) / railsMetrics.length;
const avgGo = goMetrics.reduce(...) / goMetrics.length;
```

---

## Visual Changes

### Updated Card Description
**Before:**
> Real-time latency comparison between Rails and Go services

**After:**
> Comparing Rails vs Go for write operations (create chat & create message)

### Updated Metric Labels
**Before:**
- "Rails Avg"
- "Go Avg"
- "Improvement"

**After:**
- "Rails Avg (writes)" with operation count
- "Go Avg (writes)" with operation count
- "Go Improvement" with "faster writes" label

### Updated Empty State
**Before:**
> No performance data yet. Start making requests to see comparisons!

**After:**
> No comparable performance data yet.
> Create chats or send messages using both Rails and Go services to see the comparison!

### Chart X-Axis Labels
**Before:** `create_chat`, `create_message`
**After:** `Create Chat`, `Create Message` (formatted for readability)

---

## Display Examples

### Scenario 1: Only Rails Operations
User creates 5 chats using Rails, lists applications, searches messages.

**Chart Shows:**
- Rails metrics: 5 operations (only create operations)
- Go metrics: 0 operations
- Improvement: N/A
- Message: Need both services for comparison

**Why:** List and search operations are excluded from the chart.

### Scenario 2: Mixed Operations
User performs:
- 3x Create Chat via Rails
- 3x Create Chat via Go
- 5x Create Message via Rails
- 5x Create Message via Go
- 10x List Messages (excluded)
- 5x Search Messages (excluded)

**Chart Shows:**
- Rails metrics: 8 operations (3 chats + 5 messages)
- Go metrics: 8 operations (3 chats + 5 messages)
- Improvement: ~90% (Go is ~10x faster)
- Chart: Two lines showing Rails ~50ms, Go ~5ms

**Why:** Only write operations are compared.

### Scenario 3: All Operations
User performs many operations across both services.

**Chart Shows:**
- Rails Avg (writes): 45.2ms (25 operations)
- Go Avg (writes): 4.8ms (25 operations)
- Go Improvement: 89.4% faster writes
- Chart: Clear visual difference between services

---

## Benefits

### 1. Accurate Comparison ✅
- Only compares operations both services can perform
- Eliminates false metrics from Rails-only operations
- Shows true write performance difference

### 2. Clear Messaging ✅
- Description explicitly states "write operations"
- Labels clarify this is about create operations
- Empty state guides users on what to do

### 3. User Understanding ✅
- Users understand they're comparing write performance
- No confusion about why Go seems "missing" from reads
- Operation count shows how many data points

### 4. Meaningful Metrics ✅
- Improvement percentage reflects actual write speed
- Averages are apples-to-apples comparison
- Chart visualizes the real performance difference

---

## Testing the Update

### Test 1: Create Data with Rails Only

**Steps:**
1. Toggle to Rails service
2. Create 5 chats
3. Send 10 messages
4. Check performance chart

**Expected:**
- Chart shows "Rails Avg (writes): Xms (15 operations)"
- Chart shows "Go Avg (writes): N/A (0 operations)"
- Chart shows "Go Improvement: N/A"
- Chart displays only Rails data points

### Test 2: Create Data with Both Services

**Steps:**
1. Toggle to Rails, create 3 chats, send 5 messages
2. Toggle to Go, create 3 chats, send 5 messages
3. Check performance chart

**Expected:**
- Chart shows both Rails and Go averages
- Clear performance difference visible
- Improvement percentage calculated
- Both lines appear on chart

### Test 3: Mixed Operations

**Steps:**
1. Create applications (Rails only)
2. Create chats (using Go)
3. List applications (Rails only - should not affect chart)
4. Send messages (using Rails)
5. Search messages (Rails only - should not affect chart)
6. Check performance chart

**Expected:**
- Chart only shows metrics from create chat and create message
- List and search operations don't appear in averages
- Operation counts match only create operations

---

## Technical Details

### Data Flow

```
User Action
    ↓
API Call (create_chat or create_message)
    ↓
measureRequest() wraps call with timing
    ↓
Metric stored: { endpoint, service, duration, timestamp }
    ↓
useStore.metrics[] (last 50 metrics)
    ↓
PerformanceChart component
    ↓
Filter: comparableMetrics = metrics where endpoint in ['create_chat', 'create_message']
    ↓
Group by endpoint and service
    ↓
Calculate averages for Rails vs Go
    ↓
Display chart with filtered data
```

### Key Constants

```typescript
// Only these endpoints appear in performance comparison
const GO_SUPPORTED_ENDPOINTS = ['create_chat', 'create_message'];
```

To add more comparable endpoints in the future:
```typescript
const GO_SUPPORTED_ENDPOINTS = [
  'create_chat',
  'create_message',
  'new_endpoint_name'  // Add here
];
```

---

## Future Enhancements

### 1. Endpoint-Specific Comparison
Show separate averages for chats vs messages:
```
Create Chat:  Rails 48ms | Go 5ms (90% faster)
Create Message: Rails 52ms | Go 6ms (88% faster)
```

### 2. Time-Series View
Show performance over time with timestamps:
```
Last 10 minutes: Go 91% faster
Last hour: Go 89% faster
Last day: Go 90% faster
```

### 3. Percentile Metrics
Show p50, p95, p99 latencies:
```
Rails: p50=45ms, p95=75ms, p99=120ms
Go:    p50=5ms,  p95=8ms,  p99=15ms
```

### 4. Export Data
Allow users to export metrics as CSV:
```
timestamp,endpoint,service,duration_ms
2025-10-30T10:30:00,create_chat,rails,48
2025-10-30T10:30:05,create_chat,go,5
```

---

## Summary

The PerformanceChart component has been updated to provide **accurate, meaningful performance comparisons** by:

✅ Filtering to only Go-supported operations (create chat, create message)
✅ Calculating averages only on comparable data
✅ Updating labels to clarify "write operations"
✅ Showing operation counts for transparency
✅ Providing clear empty state messaging

This ensures users see the true performance benefit of the Go service for write operations, without confusion from Rails-only features.

---

**Last Updated:** 2025-10-30
**Component:** `src/components/PerformanceChart.tsx`
**Lines Modified:** 9-15, 17-24, 27-45, 56-68, 71-108
