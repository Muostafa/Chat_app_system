# Quick Start Guide

Get your Chat System frontend running in 3 minutes.

## Prerequisites

- Node.js 18+ installed
- Backend services running:
  - Rails API on port 3000
  - Go Service on port 8080 (optional)

## Step 1: Install Dependencies

```bash
cd Frontend
npm install
```

## Step 2: Configure Environment (Optional)

The default configuration works out of the box. If you need to change API URLs:

```bash
# Edit .env file
VITE_RAILS_API_URL=http://localhost:3000/api/v1
VITE_GO_API_URL=http://localhost:8080/api/v1
```

## Step 3: Start Development Server

```bash
npm run dev
```

The frontend will start on **http://localhost:5173**

## Step 4: Test It Out

1. Open http://localhost:5173 in your browser
2. Create a chat application (enter a name, click "Create")
3. Click on the application to select it
4. Create a chat
5. Click on the chat to select it
6. Send a message
7. Watch the performance chart update!

## What's Next?

- Read [TESTING.md](./TESTING.md) for comprehensive testing guide
- Read [API_INTEGRATION_REPORT.md](./API_INTEGRATION_REPORT.md) for technical details

## Troubleshooting

**Port already in use?**
```bash
# Change port in vite.config.ts line 10
port: 5174  # or any available port
```

**Can't connect to API?**
```bash
# Make sure backend is running
curl http://localhost:3000/api/v1/chat_applications
```

**Need help?**
Check the console (F12) for error messages.

---

That's it! You're ready to go. 🚀
