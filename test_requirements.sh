#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Base URLs
RAILS_URL="http://localhost:3000/api/v1"
GO_URL="http://localhost:8080/api/v1"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  CHAT SYSTEM REQUIREMENTS TEST SUITE${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Helper function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${YELLOW}TEST $TOTAL_TESTS:${NC} $test_name"

    result=$(eval "$test_command" 2>&1)

    if echo "$result" | grep -q "$expected_result"; then
        echo -e "${GREEN}✓ PASSED${NC}\n"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo -e "Expected: $expected_result"
        echo -e "Got: $result\n"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Helper function to extract JSON value
extract_json() {
    echo "$1" | grep -o "\"$2\":\"[^\"]*\"" | cut -d'"' -f4
}

extract_json_number() {
    echo "$1" | grep -o "\"$2\":[0-9]*" | cut -d':' -f2
}

echo -e "${BLUE}=== REQUIREMENT 1: Docker Compose Stack ===${NC}\n"

run_test "Docker Compose - All services running" \
    "docker-compose ps | grep -c 'Up'" \
    "6"

run_test "Rails API - Health check" \
    "curl -s http://localhost:3000/health | grep -o 'ok'" \
    "ok"

run_test "Go Service - Health check" \
    "curl -s http://localhost:8080/health | grep -o 'healthy'" \
    "healthy"

run_test "MySQL - Container running" \
    "docker ps | grep -c chat_system_mysql" \
    "1"

run_test "Redis - Container running" \
    "docker ps | grep -c chat_system_redis" \
    "1"

run_test "Elasticsearch - Container running" \
    "docker ps | grep -c chat_system_elasticsearch" \
    "1"

run_test "Sidekiq - Container running" \
    "docker ps | grep -c chat_system_sidekiq" \
    "1"

echo -e "${BLUE}=== REQUIREMENT 2: Chat Applications ===${NC}\n"

# Create a chat application
APP_RESPONSE=$(curl -s -X POST $RAILS_URL/chat_applications \
    -H "Content-Type: application/json" \
    -d '{"chat_application": {"name": "Test App"}}')

TOKEN=$(extract_json "$APP_RESPONSE" "token")
APP_NAME=$(extract_json "$APP_RESPONSE" "name")

run_test "Create chat application - Returns token" \
    "echo '$TOKEN' | wc -c" \
    "32"

run_test "Create chat application - Returns name" \
    "echo '$APP_NAME'" \
    "Test App"

run_test "Create chat application - chats_count is 0" \
    "echo '$APP_RESPONSE' | grep -o '\"chats_count\":0'" \
    "chats_count\":0"

run_test "Get chat application by token" \
    "curl -s $RAILS_URL/chat_applications/$TOKEN | grep -o '\"token\":\"$TOKEN\"'" \
    "token\":\"$TOKEN"

run_test "List all chat applications" \
    "curl -s $RAILS_URL/chat_applications | grep -c '\"token\"'" \
    "1"

run_test "Update chat application" \
    "curl -s -X PUT $RAILS_URL/chat_applications/$TOKEN -H 'Content-Type: application/json' -d '{\"chat_application\": {\"name\": \"Updated App\"}}' | grep -o '\"name\":\"Updated App\"'" \
    "name\":\"Updated App"

echo -e "${BLUE}=== REQUIREMENT 3: Chats with Sequential Numbering ===${NC}\n"

# Create first chat via Rails
CHAT1_RESPONSE=$(curl -s -X POST $RAILS_URL/chat_applications/$TOKEN/chats)
CHAT1_NUMBER=$(extract_json_number "$CHAT1_RESPONSE" "number")

run_test "Create chat (Rails) - Returns number 1" \
    "echo '$CHAT1_NUMBER'" \
    "1"

run_test "Create chat (Rails) - messages_count is 0" \
    "echo '$CHAT1_RESPONSE' | grep -o '\"messages_count\":0'" \
    "messages_count\":0"

# Create second chat via Go service
CHAT2_RESPONSE=$(curl -s -X POST $GO_URL/chat_applications/$TOKEN/chats)
CHAT2_NUMBER=$(extract_json_number "$CHAT2_RESPONSE" "number")

run_test "Create chat (Go) - Returns number 2" \
    "echo '$CHAT2_NUMBER'" \
    "2"

# Create third chat via Rails
CHAT3_RESPONSE=$(curl -s -X POST $RAILS_URL/chat_applications/$TOKEN/chats)
CHAT3_NUMBER=$(extract_json_number "$CHAT3_RESPONSE" "number")

run_test "Create chat (Rails) - Returns number 3" \
    "echo '$CHAT3_NUMBER'" \
    "3"

# Wait for async processing
echo -e "${YELLOW}Waiting 5 seconds for Sidekiq to process jobs...${NC}"
sleep 5

run_test "Get all chats for application" \
    "curl -s $RAILS_URL/chat_applications/$TOKEN/chats | grep -c '\"number\"'" \
    "3"

run_test "Get specific chat by number" \
    "curl -s $RAILS_URL/chat_applications/$TOKEN/chats/1 | grep -o '\"number\":1'" \
    "number\":1"

echo -e "${BLUE}=== REQUIREMENT 4: Messages with Sequential Numbering ===${NC}\n"

# Create first message via Rails
MSG1_RESPONSE=$(curl -s -X POST $RAILS_URL/chat_applications/$TOKEN/chats/1/messages \
    -H "Content-Type: application/json" \
    -d '{"message": {"body": "Hello world from Rails"}}')
MSG1_NUMBER=$(extract_json_number "$MSG1_RESPONSE" "number")

run_test "Create message (Rails) - Returns number 1" \
    "echo '$MSG1_NUMBER'" \
    "1"

# Create second message via Go service
MSG2_RESPONSE=$(curl -s -X POST $GO_URL/chat_applications/$TOKEN/chats/1/messages \
    -H "Content-Type: application/json" \
    -d '{"message": {"body": "Hello world from Go service"}}')
MSG2_NUMBER=$(extract_json_number "$MSG2_RESPONSE" "number")

run_test "Create message (Go) - Returns number 2" \
    "echo '$MSG2_NUMBER'" \
    "2"

# Create third message
MSG3_RESPONSE=$(curl -s -X POST $RAILS_URL/chat_applications/$TOKEN/chats/1/messages \
    -H "Content-Type: application/json" \
    -d '{"message": {"body": "Testing message numbering"}}')
MSG3_NUMBER=$(extract_json_number "$MSG3_RESPONSE" "number")

run_test "Create message (Rails) - Returns number 3" \
    "echo '$MSG3_NUMBER'" \
    "3"

# Wait for async processing
echo -e "${YELLOW}Waiting 5 seconds for Sidekiq to process jobs...${NC}"
sleep 5

run_test "Get all messages for chat" \
    "curl -s $RAILS_URL/chat_applications/$TOKEN/chats/1/messages | grep -c '\"number\"'" \
    "3"

run_test "Get specific message by number" \
    "curl -s $RAILS_URL/chat_applications/$TOKEN/chats/1/messages/1 | grep -o '\"number\":1'" \
    "number\":1"

echo -e "${BLUE}=== REQUIREMENT 5: No IDs Exposed to Client ===${NC}\n"

run_test "Chat application response - No ID field" \
    "curl -s $RAILS_URL/chat_applications/$TOKEN | grep -c '\"id\"'" \
    "0"

run_test "Chats response - No ID field" \
    "curl -s $RAILS_URL/chat_applications/$TOKEN/chats | grep -c '\"id\"'" \
    "0"

run_test "Messages response - No ID field" \
    "curl -s $RAILS_URL/chat_applications/$TOKEN/chats/1/messages | grep -c '\"id\"'" \
    "0"

echo -e "${BLUE}=== REQUIREMENT 6: Elasticsearch Search ===${NC}\n"

# Wait for Elasticsearch indexing
echo -e "${YELLOW}Waiting 3 seconds for Elasticsearch indexing...${NC}"
sleep 3

run_test "Search messages - 'Hello' finds results" \
    "curl -s '$RAILS_URL/chat_applications/$TOKEN/chats/1/messages/search?q=Hello' | grep -c '\"body\"'" \
    "2"

run_test "Search messages - 'Rails' finds specific message" \
    "curl -s '$RAILS_URL/chat_applications/$TOKEN/chats/1/messages/search?q=Rails' | grep -o 'Hello world from Rails'" \
    "Hello world from Rails"

run_test "Search messages - 'Go service' finds specific message" \
    "curl -s '$RAILS_URL/chat_applications/$TOKEN/chats/1/messages/search?q=Go+service' | grep -o 'Hello world from Go service'" \
    "Hello world from Go service"

run_test "Search messages - 'testing' finds message" \
    "curl -s '$RAILS_URL/chat_applications/$TOKEN/chats/1/messages/search?q=testing' | grep -o 'Testing message numbering'" \
    "Testing message numbering"

run_test "Search messages - 'nonexistent' finds nothing" \
    "curl -s '$RAILS_URL/chat_applications/$TOKEN/chats/1/messages/search?q=nonexistent' | grep -c '\\[\\]'" \
    "1"

echo -e "${BLUE}=== REQUIREMENT 7: Count Columns (chats_count, messages_count) ===${NC}\n"

# Wait for count update jobs
echo -e "${YELLOW}Waiting 5 seconds for count update jobs...${NC}"
sleep 5

run_test "Application chats_count updated" \
    "curl -s $RAILS_URL/chat_applications/$TOKEN | grep -o '\"chats_count\":[0-9]*' | cut -d':' -f2" \
    "3"

run_test "Chat messages_count updated" \
    "curl -s $RAILS_URL/chat_applications/$TOKEN/chats/1 | grep -o '\"messages_count\":[0-9]*' | cut -d':' -f2" \
    "3"

echo -e "${BLUE}=== REQUIREMENT 8: Race Condition Handling ===${NC}\n"

# Create new app for concurrent test
CONCURRENT_APP=$(curl -s -X POST $RAILS_URL/chat_applications \
    -H "Content-Type: application/json" \
    -d '{"chat_application": {"name": "Concurrent Test"}}')
CONCURRENT_TOKEN=$(extract_json "$CONCURRENT_APP" "token")

echo -e "${YELLOW}Creating 10 chats concurrently via Rails...${NC}"
for i in {1..10}; do
    curl -s -X POST $RAILS_URL/chat_applications/$CONCURRENT_TOKEN/chats > /dev/null 2>&1 &
done
wait

echo -e "${YELLOW}Creating 10 more chats concurrently via Go...${NC}"
for i in {1..10}; do
    curl -s -X POST $GO_URL/chat_applications/$CONCURRENT_TOKEN/chats > /dev/null 2>&1 &
done
wait

# Wait for processing
echo -e "${YELLOW}Waiting 8 seconds for async processing...${NC}"
sleep 8

CHATS_CREATED=$(curl -s $RAILS_URL/chat_applications/$CONCURRENT_TOKEN/chats | grep -o '\"number\"' | wc -l)

run_test "Concurrent chat creation - All 20 chats created" \
    "echo '$CHATS_CREATED'" \
    "20"

run_test "Concurrent chat creation - No duplicate numbers" \
    "curl -s $RAILS_URL/chat_applications/$CONCURRENT_TOKEN/chats | grep -o '\"number\":[0-9]*' | sort | uniq -d | wc -l" \
    "0"

# Test concurrent messages
echo -e "${YELLOW}Creating 15 messages concurrently...${NC}"
for i in {1..15}; do
    curl -s -X POST $RAILS_URL/chat_applications/$CONCURRENT_TOKEN/chats/1/messages \
        -H "Content-Type: application/json" \
        -d "{\"message\": {\"body\": \"Concurrent message $i\"}}" > /dev/null 2>&1 &
done
wait

# Wait for processing
echo -e "${YELLOW}Waiting 8 seconds for async processing...${NC}"
sleep 8

MESSAGES_CREATED=$(curl -s $RAILS_URL/chat_applications/$CONCURRENT_TOKEN/chats/1/messages | grep -o '\"number\"' | wc -l)

run_test "Concurrent message creation - All 15 messages created" \
    "echo '$MESSAGES_CREATED'" \
    "15"

run_test "Concurrent message creation - No duplicate numbers" \
    "curl -s $RAILS_URL/chat_applications/$CONCURRENT_TOKEN/chats/1/messages | grep -o '\"number\":[0-9]*' | sort | uniq -d | wc -l" \
    "0"

echo -e "${BLUE}=== REQUIREMENT 9: Async Processing (Queuing System) ===${NC}\n"

run_test "Sidekiq is processing jobs" \
    "docker logs chat_system_sidekiq 2>&1 | grep -c 'INFO: done'" \
    "10"

run_test "CreateChatJob exists and runs" \
    "docker logs chat_system_sidekiq 2>&1 | grep -c 'CreateChatJob'" \
    "10"

run_test "CreateMessageJob exists and runs" \
    "docker logs chat_system_sidekiq 2>&1 | grep -c 'CreateMessageJob'" \
    "5"

echo -e "${BLUE}=== REQUIREMENT 10: Database Indices ===${NC}\n"

# Check indices via Rails console
run_test "Chat applications - token index exists" \
    "docker exec chat_system_web bundle exec rails runner 'puts ActiveRecord::Base.connection.indexes(:chat_applications).map(&:columns).include?([\"token\"])' 2>/dev/null" \
    "true"

run_test "Chats - composite index exists" \
    "docker exec chat_system_web bundle exec rails runner 'puts ActiveRecord::Base.connection.indexes(:chats).any? { |i| i.columns.sort == [\"chat_application_id\", \"number\"].sort }' 2>/dev/null" \
    "true"

run_test "Messages - composite index exists" \
    "docker exec chat_system_web bundle exec rails runner 'puts ActiveRecord::Base.connection.indexes(:messages).any? { |i| i.columns.sort == [\"chat_id\", \"number\"].sort }' 2>/dev/null" \
    "true"

echo -e "${BLUE}=== REQUIREMENT 11: RESTful Endpoints ===${NC}\n"

run_test "RESTful - GET /chat_applications" \
    "curl -s -o /dev/null -w '%{http_code}' $RAILS_URL/chat_applications" \
    "200"

run_test "RESTful - POST /chat_applications" \
    "curl -s -o /dev/null -w '%{http_code}' -X POST $RAILS_URL/chat_applications -H 'Content-Type: application/json' -d '{\"chat_application\": {\"name\": \"REST Test\"}}'" \
    "201"

run_test "RESTful - GET /chat_applications/:token" \
    "curl -s -o /dev/null -w '%{http_code}' $RAILS_URL/chat_applications/$TOKEN" \
    "200"

run_test "RESTful - PUT /chat_applications/:token" \
    "curl -s -o /dev/null -w '%{http_code}' -X PUT $RAILS_URL/chat_applications/$TOKEN -H 'Content-Type: application/json' -d '{\"chat_application\": {\"name\": \"REST Updated\"}}'" \
    "200"

run_test "RESTful - GET /chat_applications/:token/chats" \
    "curl -s -o /dev/null -w '%{http_code}' $RAILS_URL/chat_applications/$TOKEN/chats" \
    "200"

run_test "RESTful - POST /chat_applications/:token/chats" \
    "curl -s -o /dev/null -w '%{http_code}' -X POST $RAILS_URL/chat_applications/$TOKEN/chats" \
    "201"

run_test "RESTful - GET /chat_applications/:token/chats/:number" \
    "curl -s -o /dev/null -w '%{http_code}' $RAILS_URL/chat_applications/$TOKEN/chats/1" \
    "200"

run_test "RESTful - GET /chat_applications/:token/chats/:number/messages" \
    "curl -s -o /dev/null -w '%{http_code}' $RAILS_URL/chat_applications/$TOKEN/chats/1/messages" \
    "200"

run_test "RESTful - POST /chat_applications/:token/chats/:number/messages" \
    "curl -s -o /dev/null -w '%{http_code}' -X POST $RAILS_URL/chat_applications/$TOKEN/chats/1/messages -H 'Content-Type: application/json' -d '{\"message\": {\"body\": \"REST test\"}}'" \
    "201"

run_test "RESTful - GET /chat_applications/:token/chats/:number/messages/:number" \
    "curl -s -o /dev/null -w '%{http_code}' $RAILS_URL/chat_applications/$TOKEN/chats/1/messages/1" \
    "200"

run_test "RESTful - GET /chat_applications/:token/chats/:number/messages/search" \
    "curl -s -o /dev/null -w '%{http_code}' '$RAILS_URL/chat_applications/$TOKEN/chats/1/messages/search?q=test'" \
    "200"

echo -e "${BLUE}=== BONUS: Go Service Implementation ===${NC}\n"

run_test "Go service - Endpoint exists" \
    "curl -s -o /dev/null -w '%{http_code}' $GO_URL/chat_applications/$TOKEN/chats" \
    "404"

run_test "Go service - Creates chats successfully" \
    "curl -s -X POST $GO_URL/chat_applications/$TOKEN/chats | grep -c '\"number\"'" \
    "1"

run_test "Go service - Creates messages successfully" \
    "curl -s -X POST $GO_URL/chat_applications/$TOKEN/chats/1/messages -H 'Content-Type: application/json' -d '{\"message\": {\"body\": \"Go test\"}}' | grep -c '\"number\"'" \
    "1"

run_test "Go service - Integrates with Sidekiq" \
    "docker logs chat_system_sidekiq 2>&1 | grep -c 'ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper'" \
    "1"

echo -e "${BLUE}=== REQUIREMENT 12: Error Handling ===${NC}\n"

run_test "Error - Invalid token returns 404" \
    "curl -s -o /dev/null -w '%{http_code}' $RAILS_URL/chat_applications/invalid_token" \
    "404"

run_test "Error - Invalid chat number returns 404" \
    "curl -s -o /dev/null -w '%{http_code}' $RAILS_URL/chat_applications/$TOKEN/chats/999" \
    "404"

run_test "Error - Empty message body returns 422" \
    "curl -s -o /dev/null -w '%{http_code}' -X POST $RAILS_URL/chat_applications/$TOKEN/chats/1/messages -H 'Content-Type: application/json' -d '{\"message\": {\"body\": \"\"}}'" \
    "422"

run_test "Error - Empty application name returns 422" \
    "curl -s -o /dev/null -w '%{http_code}' -X POST $RAILS_URL/chat_applications -H 'Content-Type: application/json' -d '{\"chat_application\": {\"name\": \"\"}}'" \
    "422"

echo -e "${BLUE}=== REQUIREMENT 13: Redis Usage ===${NC}\n"

run_test "Redis - Counters are being used" \
    "docker exec chat_system_redis redis-cli KEYS 'chat_app:*' | wc -l" \
    "1"

run_test "Redis - Chat counter increments" \
    "docker exec chat_system_redis redis-cli GET 'chat_app:1:chat_counter' | grep -E '[0-9]+'" \
    "[0-9]"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}           TEST SUMMARY${NC}"
echo -e "${BLUE}========================================${NC}\n"

echo -e "Total Tests:  ${BLUE}$TOTAL_TESTS${NC}"
echo -e "Passed:       ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed:       ${RED}$FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}✓✓✓ ALL REQUIREMENTS MET! ✓✓✓${NC}"
    echo -e "${GREEN}System is ready for submission!${NC}\n"
    exit 0
else
    echo -e "\n${RED}✗✗✗ SOME TESTS FAILED ✗✗✗${NC}"
    echo -e "${RED}Please fix the issues before submission.${NC}\n"
    exit 1
fi
