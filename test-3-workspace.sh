#!/bin/bash
# Test 3: Workspace Manager

set -e

TEST_WORKSPACE="/tmp/test-workspace-$(date +%s)"

echo "=================================================="
echo "Test 3: Workspace Manager"
echo "=================================================="

cd /home/ec2-user/AWS-EXPERT/pi-on-agentcore

# Cleanup function
cleanup() {
    rm -rf "$TEST_WORKSPACE"
}
trap cleanup EXIT

# Test workspace initialization and basic operations
node --input-type=module <<'EOF'
import { createWorkspaceManager } from './dist/workspace/manager.js';

const workspacePath = process.env.TEST_WORKSPACE;

console.log(`\nTest 3.1: Initialize workspace at ${workspacePath}`);
const workspace = await createWorkspaceManager({ workspacePath });

console.log('Workspace base path:', workspace.basePath);
console.log('Is available:', workspace.isAvailable);
console.log('Session dir:', workspace.sessionDir());

// Test 3.2: Save session history
console.log('\nTest 3.2: Save session history');
const messages = [
    { role: 'user', content: 'Test message 1' },
    { role: 'assistant', content: 'Test response 1' }
];

await workspace.saveSessionHistory(messages);
console.log('History saved');

// Test 3.3: Load session history
console.log('\nTest 3.3: Load session history');
const loaded = await workspace.loadSessionHistory();
console.log('Loaded messages:', JSON.stringify(loaded, null, 2));

if (loaded.length === 2 &&
    loaded[0].role === 'user' &&
    loaded[0].content === 'Test message 1' &&
    loaded[1].role === 'assistant' &&
    loaded[1].content === 'Test response 1') {
    console.log('PASSED: History loaded correctly');
} else {
    console.error('FAILED: History mismatch');
    process.exit(1);
}

// Test 3.4: Save artifact
console.log('\nTest 3.4: Save artifact');
const artifactPath = await workspace.saveArtifact('test-file.txt', 'Test content', 'reports');
console.log('Artifact saved at:', artifactPath);

// Test 3.5: Verify artifact exists
console.log('\nTest 3.5: Verify artifact file');
import { readFile } from 'node:fs/promises';
try {
    const content = await readFile(artifactPath, 'utf-8');
    if (content === 'Test content') {
        console.log('PASSED: Artifact content verified');
    } else {
        console.error('FAILED: Artifact content mismatch');
        process.exit(1);
    }
} catch (error) {
    console.error('FAILED: Could not read artifact:', error.message);
    process.exit(1);
}

console.log('\n==================================================');
console.log('Test 3: PASSED (All workspace tests passed)');
console.log('==================================================');
EOF
