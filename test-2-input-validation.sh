#!/bin/bash
# Test 2: Input Validation

set -e

TEST_PORT=9877
TEST_WORKSPACE="/tmp/test-workspace-$(date +%s)"
TEST_SKILLS_DIR="/home/ec2-user/AWS-EXPERT/pi-on-agentcore/skills"

echo "=================================================="
echo "Test 2: Input Validation"
echo "=================================================="

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    if [ ! -z "$SERVER_PID" ]; then
        kill $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
    fi
    rm -rf "$TEST_WORKSPACE"
}
trap cleanup EXIT

# Create workspace
mkdir -p "$TEST_WORKSPACE"

# Start server
echo "Starting server on port $TEST_PORT..."
cd /home/ec2-user/AWS-EXPERT/pi-on-agentcore
PORT=$TEST_PORT SKILLS_DIR="$TEST_SKILLS_DIR" WORKSPACE_PATH="$TEST_WORKSPACE" node dist/index.js > /tmp/server-test-2.log 2>&1 &
SERVER_PID=$!

# Wait for server to start
echo "Waiting for server to start..."
for i in {1..30}; do
    if curl -s http://localhost:$TEST_PORT/ping > /dev/null 2>&1; then
        break
    fi
    if [ $i -eq 30 ]; then
        echo "FAILED: Server did not start"
        exit 1
    fi
    sleep 1
done

echo "Server started. Testing input validation..."
echo ""

# Test 1: Empty body
echo "Test 2.1: POST /invocations with empty body"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:$TEST_PORT/invocations -H "Content-Type: application/json" -d '{}')
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

echo "HTTP Status: $HTTP_CODE"
echo "Response Body: $BODY"

if [ "$HTTP_CODE" = "400" ] || [ "$HTTP_CODE" = "422" ]; then
    echo "PASSED: Got expected error status"
else
    echo "FAILED: Expected 400 or 422, got $HTTP_CODE"
    exit 1
fi
echo ""

# Test 2: Empty prompt
echo "Test 2.2: POST /invocations with empty prompt"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:$TEST_PORT/invocations -H "Content-Type: application/json" -d '{"prompt":""}')
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

echo "HTTP Status: $HTTP_CODE"
echo "Response Body: $BODY"

if [ "$HTTP_CODE" = "400" ] || [ "$HTTP_CODE" = "422" ]; then
    echo "PASSED: Got expected error status"
else
    echo "FAILED: Expected 400 or 422, got $HTTP_CODE"
    exit 1
fi
echo ""

# Test 3: Invalid prompt type (number instead of string)
echo "Test 2.3: POST /invocations with invalid prompt type (number)"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:$TEST_PORT/invocations -H "Content-Type: application/json" -d '{"prompt":123}')
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

echo "HTTP Status: $HTTP_CODE"
echo "Response Body: $BODY"

if [ "$HTTP_CODE" = "400" ] || [ "$HTTP_CODE" = "422" ]; then
    echo "PASSED: Got expected error status"
else
    echo "FAILED: Expected 400 or 422, got $HTTP_CODE"
    exit 1
fi
echo ""

# Test 4: Completely malformed JSON
echo "Test 2.4: POST /invocations with malformed JSON"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST http://localhost:$TEST_PORT/invocations -H "Content-Type: application/json" -d '{bad json')
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

echo "HTTP Status: $HTTP_CODE"
echo "Response Body: $BODY"

if [ "$HTTP_CODE" = "400" ]; then
    echo "PASSED: Got expected error status"
else
    echo "FAILED: Expected 400, got $HTTP_CODE"
    exit 1
fi
echo ""

echo "=================================================="
echo "Test 2: PASSED (All validation tests passed)"
echo "=================================================="
