#!/bin/bash
# Test 5: Hooks - Output Redaction

set -e

echo "=================================================="
echo "Test 5: Hooks - Output Redaction"
echo "=================================================="

cd /home/ec2-user/AWS-EXPERT/pi-on-agentcore

# Test hooks for sensitive data redaction
node --input-type=module <<'EOF'
import { createAfterToolCallHook } from './dist/agent/hooks.js';

console.log('\nTest 5.1: Test sensitive data redaction patterns');

// Create the hook
const afterToolCallHook = createAfterToolCallHook({});

// Test cases with sensitive data
const testCases = [
    {
        description: 'AWS Access Key ID (AKIA)',
        input: 'AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE',
        shouldRedact: true
    },
    {
        description: 'AWS Access Key ID (ASIA)',
        input: 'export AWS_ACCESS_KEY_ID=ASIATESTKEYEXAMPLE12',
        shouldRedact: true
    },
    {
        description: 'AWS Secret Access Key',
        input: 'aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        shouldRedact: true
    },
    {
        description: 'RSA Private Key',
        input: '-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA...\n-----END RSA PRIVATE KEY-----',
        shouldRedact: true
    },
    {
        description: 'Generic Private Key',
        input: '-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkq...\n-----END PRIVATE KEY-----',
        shouldRedact: true
    },
    {
        description: 'Password in config',
        input: 'database password=mysecretpassword123',
        shouldRedact: true
    },
    {
        description: 'Secret in config-style',
        input: 'secret: my-secret-value-123',
        shouldRedact: true
    },
    {
        description: 'Normal EC2 output (should NOT redact)',
        input: 'Instance i-1234567890 is running in us-east-1 with type t2.micro',
        shouldRedact: false
    },
    {
        description: 'Normal S3 output (should NOT redact)',
        input: 's3://my-bucket/path/to/file.txt exists and is 1024 bytes',
        shouldRedact: false
    }
];

let passed = 0;
let failed = 0;

for (const test of testCases) {
    console.log(`\nTesting: ${test.description}`);
    console.log(`Input: ${test.input.substring(0, 60)}${test.input.length > 60 ? '...' : ''}`);
    console.log(`Should redact: ${test.shouldRedact}`);

    // Simulate tool call result
    const mockContext = {
        toolCall: { name: 'test-tool', id: 'test-id' },
        args: {},
        result: {
            content: [{ type: 'text', text: test.input }]
        }
    };

    try {
        const hookResult = await afterToolCallHook(mockContext, null);

        if (test.shouldRedact) {
            // Check if hook returned modified content
            if (hookResult && hookResult.content) {
                const redactedText = hookResult.content[0].text;
                if (redactedText.includes('[REDACTED]') && redactedText !== test.input) {
                    console.log('✓ PASSED: Sensitive data redacted');
                    console.log(`Output: ${redactedText.substring(0, 60)}${redactedText.length > 60 ? '...' : ''}`);
                    passed++;
                } else {
                    console.log('✗ FAILED: Sensitive data not redacted properly');
                    console.log(`Output: ${redactedText}`);
                    failed++;
                }
            } else {
                console.log('✗ FAILED: Hook did not return modified content');
                failed++;
            }
        } else {
            // Normal output should not be modified
            if (!hookResult || hookResult === undefined) {
                console.log('✓ PASSED: Normal output unchanged (hook returned undefined)');
                passed++;
            } else if (hookResult.content && hookResult.content[0].text === test.input) {
                console.log('✓ PASSED: Normal output unchanged');
                passed++;
            } else {
                console.log('✗ FAILED: Normal output was modified');
                console.log(`Output: ${hookResult?.content?.[0]?.text || 'undefined'}`);
                failed++;
            }
        }
    } catch (error) {
        console.log('✗ FAILED: Hook threw error');
        console.log('Error:', error.message);
        failed++;
    }
}

console.log('\n==================================================');
console.log(`Results: ${passed} passed, ${failed} failed`);
console.log('==================================================');

if (failed === 0) {
    console.log('Test 5: PASSED (All redaction tests passed)');
    process.exit(0);
} else {
    console.log('Test 5: FAILED (Some redaction tests failed)');
    process.exit(1);
}
EOF
