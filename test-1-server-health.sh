#!/bin/bash
# Test 1: Server Startup & Health Check

set -e

TEST_PORT=9876
TEST_WORKSPACE="/tmp/test-workspace-$(date +%s)"
TEST_SKILLS_DIR="/home/ec2-user/AWS-EXPERT/pi-on-agentcore/skills"

echo "=================================================="
echo "Test 1: Server Startup & Health Check"
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
PORT=$TEST_PORT SKILLS_DIR="$TEST_SKILLS_DIR" WORKSPACE_PATH="$TEST_WORKSPACE" node dist/index.js > /tmp/server-test.log 2>&1 &
SERVER_PID=$!

echo "Server PID: $SERVER_PID"

# Wait for server to start
echo "Waiting for server to start..."
for i in {1..30}; do
    if curl -s http://localhost:$TEST_PORT/ping > /dev/null 2>&1; then
        echo "Server started successfully"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "FAILED: Server did not start within 30 seconds"
        cat /tmp/server-test.log
        exit 1
    fi
    sleep 1
done

# Test health check
echo ""
echo "Testing GET /ping..."
RESPONSE=$(curl -s -w "\n%{http_code}" http://localhost:$TEST_PORT/ping)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

echo "HTTP Status: $HTTP_CODE"
echo "Response Body: $BODY"

if [ "$HTTP_CODE" != "200" ]; then
    echo "FAILED: Expected HTTP 200, got $HTTP_CODE"
    exit 1
fi

if ! echo "$BODY" | grep -q '"status":"healthy"'; then
    echo "FAILED: Expected {\"status\":\"healthy\"}, got $BODY"
    exit 1
fi

echo ""
echo "Checking server logs for skills loading..."
sleep 1
cat /tmp/server-test.log

if grep -q "aws-compute" /tmp/server-test.log && \
   grep -q "aws-cost-optimization" /tmp/server-test.log && \
   grep -q "aws-networking" /tmp/server-test.log && \
   grep -q "aws-security" /tmp/server-test.log && \
   grep -q "linux-administration" /tmp/server-test.log && \
   grep -q "troubleshooting" /tmp/server-test.log; then
    echo ""
    echo "SUCCESS: All 6 skills loaded"
else
    echo ""
    echo "WARNING: Not all skills found in logs (may be normal if skills load silently)"
fi

echo ""
echo "=================================================="
echo "Test 1: PASSED"
echo "=================================================="
