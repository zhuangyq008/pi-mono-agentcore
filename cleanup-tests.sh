#!/bin/bash
# Cleanup script for test artifacts

echo "=========================================="
echo "Cleaning up test artifacts"
echo "=========================================="

# Kill any lingering test servers
echo "Checking for test servers..."
TEST_SERVERS=$(ps aux | grep "node dist/index.js" | grep -v grep | awk '{print $2}')
if [ ! -z "$TEST_SERVERS" ]; then
    echo "Killing test servers: $TEST_SERVERS"
    kill $TEST_SERVERS 2>/dev/null || true
else
    echo "No test servers running"
fi

# Remove test workspaces
echo "Removing test workspaces..."
rm -rf /tmp/test-workspace-* 2>/dev/null || true
echo "Removed test workspace directories"

# Remove test logs
echo "Removing test logs..."
rm -f /tmp/server-test*.log 2>/dev/null || true
echo "Removed test logs"

# Clean up /tmp/workspace if it was created by tests
if [ -d "/tmp/workspace" ]; then
    echo "Cleaning /tmp/workspace..."
    rm -rf /tmp/workspace/.session/* 2>/dev/null || true
    echo "Cleaned /tmp/workspace/.session"
fi

echo ""
echo "=========================================="
echo "Cleanup complete"
echo "=========================================="
