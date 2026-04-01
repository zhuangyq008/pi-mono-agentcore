#!/bin/bash
# Run all local tests for AWS SA Agent

set -e

echo "=========================================="
echo "AWS SA Agent - Local Test Suite"
echo "=========================================="
echo ""

TESTS=(
    "test-1-server-health.sh"
    "test-2-input-validation.sh"
    "test-3-workspace.sh"
    "test-4-tools-safety.sh"
    "test-5-hooks.sh"
)

PASSED=0
FAILED=0
FAILED_TESTS=()

for test in "${TESTS[@]}"; do
    echo ""
    echo "=========================================="
    echo "Running: $test"
    echo "=========================================="

    if bash "/home/ec2-user/AWS-EXPERT/pi-on-agentcore/$test"; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("$test")
    fi

    echo ""
    sleep 2  # Brief pause between tests
done

echo ""
echo "=========================================="
echo "Test Suite Results"
echo "=========================================="
echo "Total tests: ${#TESTS[@]}"
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo "Failed tests:"
    for failed_test in "${FAILED_TESTS[@]}"; do
        echo "  - $failed_test"
    done
    echo ""
    echo "TEST SUITE: FAILED"
    exit 1
else
    echo ""
    echo "TEST SUITE: PASSED ✓"
    exit 0
fi
