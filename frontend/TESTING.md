# Frontend API Integration Testing Guide

This guide will help you verify that the frontend is working correctly with the Chat System APIs.

## Prerequisites

Before testing, ensure all services are running:

### 1. Start Rails API (Port 3000)
```bash
cd ../backend
rails server -p 3000
```

### 2. Start Go Service (Port 8080)
```bash
cd ../go-service
go run main.go
```

### 3. Start Frontend (Port 5173)
```bash
cd Frontend
npm install  # First time only
npm run dev
```

The frontend will be available at: **http://localhost:5173**

---

## Manual Testing Checklist

### Test 1: Create Chat Application (Rails)

**Steps:**
1. Open http://localhost:5173
2. Ensure "Rails" service is selected (top right toggle)
3. In the "Chat Applications" card, enter a name (e.g., "Test App 1")
4. Click "Create" button or press Enter

**Expected Result:**
- ✅ Success toast appears: "Application created via RAILS"
- ✅ New application appears in the list with a token
- ✅ Shows "0 chats" badge
- ✅ Performance chart updates with API call timing

**Error Cases to Test:**
- Empty name → Should show validation error: "name: can't be blank"

---

### Test 2: Select and Create Chat (Rails)

**Steps:**
1. Click on the application card you just created
2. The "Chats" section should now show "Create New Chat" button
3. Click "Create New Chat"

**Expected Result:**
- ✅ Success toast: "Chat #1 created via RAILS"
- ✅ Chat appears in list showing "Chat #1" with "0 messages"
- ✅ Application badge updates to "1 chats"

**Repeat to create Chat #2:**
- Should create "Chat #2" with incremented number

---

### Test 3: Send Messages (Rails)

**Steps:**
1. Click on "Chat #1" in the list
2. The "Messages" section should now be active
3. Type a message (e.g., "Hello World") in the input
4. Click "Send" or press Enter

**Expected Result:**
- ✅ Success toast: "Message sent via RAILS"
- ✅ Message appears in the message list with "#1" number
- ✅ Chat badge updates to "1 messages"
- ✅ Message input clears

**Send more messages:**
- "This is the second message"
- "Testing message number three"

All should appear with incremented numbers.

**Error Cases to Test:**
- Empty message → Should show validation error: "body: can't be blank"

---

### Test 4: Search Messages (Rails)

**Steps:**
1. With Chat #1 selected and multiple messages visible
2. Type "second" in the search box

**Expected Result:**
- ✅ Only messages containing "second" are displayed
- ✅ Other messages are filtered out
- ✅ No error messages

**Clear search:**
- Delete search text → All messages should reappear

**Search with no results:**
- Search for "xyz123" → Should show "No messages found"

---

### Test 5: Switch to Go Service (High Performance)

**IMPORTANT NOTE:**
- Go service ONLY supports **write operations** (creating chats and messages)
- ALL **read operations** (listing, searching) ALWAYS use Rails
- The service toggle ONLY affects chat creation and message creation

**Steps:**
1. Click the service toggle in the top right
2. Switch from "Rails" to "Go"
3. Select an existing application (one you created earlier)
4. Create a new chat

**Expected Result:**
- ✅ Success toast: "Chat #X created via GO"
- ✅ Chat appears in list immediately (list fetched from Rails)
- ✅ Performance chart shows Go response times (should be faster)
- ✅ Application badge updates correctly

**Create message via Go:**
1. Select the chat you just created
2. Send a message: "Message from Go service"

**Expected Result:**
- ✅ Success toast: "Message sent via GO"
- ✅ Message appears instantly (list fetched from Rails)
- ✅ Performance chart shows Go timing (~5ms vs Rails ~50ms)

**Verify Read Operations Use Rails:**
- While Go service is selected, notice that:
  - Application list still loads (from Rails)
  - Chat list still loads (from Rails)
  - Message list still loads (from Rails)
  - Search still works (via Rails)
- Only CREATE operations use Go when selected

---

### Test 6: Performance Comparison

**Steps:**
1. Switch to Rails service
2. Create 5 chats and note response times
3. Send 5 messages in one of the chats
4. Note the average response time in the chart
5. Switch to Go service
6. Create 5 more chats using Go service
7. Send 5 messages in one of the chats
8. Compare timings in the performance chart

**Expected Result:**
- ✅ Go service shows ~5-10ms response times for creates
- ✅ Rails service shows ~30-50ms response times for creates
- ✅ Chart clearly shows Go is faster for write operations
- ✅ "Go is X% faster" message displays
- ✅ All list/read operations show consistent timing (always Rails)

**Note:** The performance difference is most noticeable under load or when creating many resources quickly.

---

### Test 7: Multiple Applications

**Steps:**
1. Create multiple applications:
   - "Mobile App"
   - "Web App"
   - "Desktop App"
2. Switch between applications
3. Each should show its own chats

**Expected Result:**
- ✅ Each application maintains separate chats
- ✅ Switching applications updates the chat list
- ✅ No data mixing between applications
- ✅ Token copy functionality works (click copy icon)

---

### Test 8: Error Handling

**Test 404 - Invalid Token:**
1. Open browser DevTools (F12)
2. Go to Console tab
3. In browser console, run:
```javascript
fetch('http://localhost:3000/api/v1/chat_applications/invalid_token')
  .then(r => r.json())
  .then(console.log)
```

**Expected Result:**
- ✅ Console shows: `{error: "ChatApplication not found"}`

**Test Invalid Chat Number:**
```javascript
// Replace TOKEN with a real token from your app
fetch('http://localhost:3000/api/v1/chat_applications/TOKEN/chats/999')
  .then(r => r.json())
  .then(console.log)
```

**Expected Result:**
- ✅ Console shows: `{error: "Chat not found"}`

**Test Empty Search Query:**
In the UI, this is handled by the frontend (not sent to API), but you can test manually:
```javascript
// Replace TOKEN with real token
fetch('http://localhost:3000/api/v1/chat_applications/TOKEN/chats/1/messages/search')
  .then(r => r.json())
  .then(console.log)
```

**Expected Result:**
- ✅ Console shows: `{error: "Query parameter required"}`

---

### Test 9: State Persistence

**Steps:**
1. Create an application and several chats
2. Refresh the page (F5)

**Expected Result:**
- ✅ All applications still appear in the list
- ✅ Must re-select an application (selection state is lost - expected)
- ✅ All data is persisted in backend

---

### Test 10: UI Responsiveness

**Steps:**
1. Resize browser window to mobile size (375px width)
2. Test all functionality

**Expected Result:**
- ✅ Layout adapts to mobile (stacks vertically)
- ✅ All features still accessible
- ✅ Scrolling works properly
- ✅ No horizontal scroll

---

## API Endpoint Verification

### Endpoints Currently Implemented:

| Method | Endpoint | Service | Status |
|--------|----------|---------|--------|
| POST | `/chat_applications` | Rails | ✅ Implemented |
| GET | `/chat_applications` | Rails | ✅ Implemented |
| POST | `/chat_applications/:token/chats` | Rails & Go | ✅ Implemented |
| GET | `/chat_applications/:token/chats` | Rails | ✅ Implemented |
| POST | `/chat_applications/:token/chats/:number/messages` | Rails & Go | ✅ Implemented |
| GET | `/chat_applications/:token/chats/:number/messages` | Rails | ✅ Implemented |
| GET | `/chat_applications/:token/chats/:number/messages/search?q=` | Rails | ✅ Implemented |

### Endpoints NOT Implemented (Not Required for Current UI):

| Method | Endpoint | Reason |
|--------|----------|--------|
| GET | `/chat_applications/:token` | UI uses list view, not detail view |
| PATCH | `/chat_applications/:token` | No edit functionality in UI |
| GET | `/chat_applications/:token/chats/:number` | UI uses list view, not detail view |
| GET | `/chat_applications/:token/chats/:number/messages/:number` | UI uses list view, not detail view |

---

## Automated API Testing with cURL

You can verify API integration with these cURL commands:

### Test Create Application:
```bash
curl -X POST http://localhost:3000/api/v1/chat_applications \
  -H "Content-Type: application/json" \
  -d '{"chat_application": {"name": "cURL Test App"}}'
```

Expected: `{"name":"cURL Test App","token":"...","chats_count":0}`

### Test Create Chat (replace TOKEN):
```bash
TOKEN="your-token-here"
curl -X POST http://localhost:3000/api/v1/chat_applications/$TOKEN/chats \
  -H "Content-Type: application/json"
```

Expected: `{"number":1,"messages_count":0}`

### Test Create Message:
```bash
TOKEN="your-token-here"
curl -X POST http://localhost:3000/api/v1/chat_applications/$TOKEN/chats/1/messages \
  -H "Content-Type: application/json" \
  -d '{"message": {"body": "Test message from cURL"}}'
```

Expected: `{"number":1}`

### Test Search:
```bash
TOKEN="your-token-here"
curl "http://localhost:3000/api/v1/chat_applications/$TOKEN/chats/1/messages/search?q=test"
```

Expected: Array of messages containing "test"

---

## Known Issues & Limitations

### Fixed Issues:
- ✅ Port conflict between Vite (was 8080) and Go service → Fixed to port 5173
- ✅ Generic error messages → Now shows specific validation errors
- ✅ Hardcoded API URLs → Now uses environment variables

### Current Limitations:
1. **No pagination** - Large message lists may be slow
2. **No real-time updates** - Must manually refresh to see changes from other users
3. **No request retry** - Failed requests don't automatically retry
4. **Selection state lost on refresh** - Must re-select application after page reload
5. **Go service limited** - Only supports create operations, not reads

---

## Troubleshooting

### Issue: "Failed to fetch" error

**Possible Causes:**
- Backend not running
- Wrong port configuration
- CORS issue

**Solution:**
```bash
# Check if Rails is running
curl http://localhost:3000/api/v1/chat_applications

# Check if Go is running
curl http://localhost:8080/health

# If not, start the services
```

### Issue: Empty application list

**Cause:** No applications created yet

**Solution:** Create a new application using the form

### Issue: "ChatApplication not found" error

**Cause:** Invalid token or application was deleted

**Solution:**
- Verify token is correct
- Create a new application
- Check backend database

### Issue: Performance chart not updating

**Cause:** React Query caching

**Solution:**
- Wait a few seconds
- Perform another API operation
- Hard refresh (Ctrl+Shift+R)

### Issue: Port 5173 already in use

**Solution:**
```bash
# Find process using port 5173
netstat -ano | findstr :5173  # Windows
lsof -i :5173                 # Mac/Linux

# Kill the process or change port in vite.config.ts
```

---

## Success Criteria

Your frontend is working correctly if:

- ✅ All 10 manual tests pass
- ✅ No console errors in browser DevTools
- ✅ Performance chart shows metrics for both Rails and Go
- ✅ Toast notifications appear for all actions
- ✅ Validation errors display properly
- ✅ Search functionality filters messages correctly
- ✅ Both Rails and Go services create data successfully
- ✅ UI is responsive on mobile and desktop

---

## Environment Variables

The frontend uses these environment variables (see `.env` file):

```env
VITE_RAILS_API_URL=http://localhost:3000/api/v1
VITE_GO_API_URL=http://localhost:8080/api/v1
```

To change API URLs:
1. Edit `.env` file
2. Restart the dev server (`npm run dev`)

For production:
1. Create `.env.production` file
2. Set production URLs
3. Build: `npm run build`

---

## Additional Notes

### Data Flow:
1. User action → Component
2. Component → React Query mutation/query
3. React Query → API Client (`src/lib/api.ts`)
4. API Client → Backend (Rails or Go)
5. Backend → Response
6. API Client → Performance tracking
7. React Query → Cache update
8. Component → UI update

### Performance Metrics:
- All API calls are timed using `performance.now()`
- Metrics stored in Zustand store (last 50 calls)
- Chart displays both Rails and Go timings
- Comparison shows percentage improvement

### Error Handling:
- Network errors → React Query error state
- HTTP errors → Parsed and displayed as toast
- Validation errors (422) → Field-specific messages
- 404/400 errors → API error message displayed

---

## Contact & Support

If you encounter issues not covered in this guide:

1. Check browser console for errors
2. Check backend logs
3. Verify all services are running
4. Check network tab in DevTools
5. Verify environment variables are loaded

---

**Last Updated:** 2025-10-30
**Frontend Version:** 0.0.0
**Node Version Required:** 18+
**Package Manager:** npm or bun
