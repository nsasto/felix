# S-0062: Run Artifact Sync - End-to-End Testing

**Priority:** High  
**Tags:** Testing, Integration, QA

## Description

As a Felix developer, I need comprehensive end-to-end tests for run artifact syncing so that we can verify the complete flow from CLI agent through outbox queue to backend storage with proper idempotency, failure handling, and performance characteristics.

## Dependencies

- S-0061 (CLI Sync Plugin) - requires working CLI sync implementation
- S-0060 (Backend Sync Endpoints) - requires server endpoints
- S-0059 (Storage Abstraction Layer) - requires filesystem storage

## Acceptance Criteria

### Test Environment Setup

- [ ] Test database created (felix_test or separate schema)
- [ ] Test backend configured with STORAGE_TYPE=filesystem
- [ ] Test storage path uses temp directory
- [ ] Environment variables for test configuration documented
- [ ] Cleanup script removes test data after tests

### Happy Path Test

- [ ] Test script created at `.felix/tests/test-sync-happy-path.ps1`
- [ ] Script enables sync via environment variable
- [ ] Script runs felix agent on test requirement
- [ ] Verifies outbox directory empty after completion
- [ ] Queries database for run record
- [ ] Verifies run has correct requirement_id, status, duration
- [ ] Counts run_files records matches expected artifacts
- [ ] Checks storage directory contains artifact files
- [ ] Downloads artifact via API endpoint
- [ ] Compares downloaded content to original file
- [ ] Test completes in under 60 seconds

### Idempotency Test

- [ ] Test script created at `.felix/tests/test-sync-idempotency.ps1`
- [ ] Runs same requirement twice consecutively
- [ ] Verifies second run creates new run record
- [ ] Checks artifact uploads show "skipped" status for unchanged files
- [ ] Queries run_files updated_at timestamps
- [ ] Unchanged files have earlier updated_at than changed files
- [ ] Storage contains only one copy of each unchanged file (by SHA256)
- [ ] Database sha256 hashes match filesystem file hashes

### Network Failure Test

- [ ] Test script created at `.felix/tests/test-sync-network-failure.ps1`
- [ ] Stops backend server before test
- [ ] Runs felix agent with backend unavailable
- [ ] Verifies outbox contains queued .jsonl files
- [ ] Counts outbox files (should have 3+: register, create run, finish, batch upload)
- [ ] Restarts backend server
- [ ] Triggers outbox flush by running another requirement
- [ ] Verifies original outbox files cleared
- [ ] Verifies both runs appear in database
- [ ] Verifies both runs have artifacts in storage

### Large File Test

- [ ] Test script creates 5MB output.log file
- [ ] Uploads via UploadRunFolder method
- [ ] Verifies upload succeeds without timeout
- [ ] Downloads file via API
- [ ] Compares SHA256 hash of downloaded vs original
- [ ] Verifies upload completes in under 30 seconds
- [ ] No memory issues or process crashes

### Concurrent Upload Test

- [ ] Test runs 3 agents in parallel on different requirements
- [ ] Each agent uploads artifacts simultaneously
- [ ] No database deadlocks occur
- [ ] No storage write conflicts occur
- [ ] All 3 runs complete successfully
- [ ] Database contains all 3 run records
- [ ] Storage contains artifacts for all 3 runs
- [ ] No artifact corruption or cross-contamination

### Performance Benchmark Test

- [ ] Test script runs 100 sequential requirement executions
- [ ] Measures total time and per-run average
- [ ] Sync overhead is less than 10% of total run time
- [ ] Database grows linearly with run count
- [ ] Storage size grows linearly with artifact count
- [ ] No memory leaks detected (PowerShell memory stable)
- [ ] Backend memory stable under load

### Batch vs Individual Comparison

- [ ] Test measures time for individual file uploads (old approach simulation)
- [ ] Test measures time for batch upload (current implementation)
- [ ] Batch upload is at least 70% faster than individual
- [ ] HTTP request count reduced by ~90% with batch approach
- [ ] Logs show single POST request instead of multiple PUTs

### Error Recovery Test

- [ ] Test injects corrupt JSON in outbox file
- [ ] Verifies agent continues without crash
- [ ] Corrupt file skipped with warning log
- [ ] Subsequent valid files processed successfully
- [ ] Test injects invalid file path in batch upload
- [ ] Verifies agent handles missing file gracefully
- [ ] Upload continues with remaining valid files

### Data Integrity Test

- [ ] Test verifies SHA256 hashes match between source and storage
- [ ] Test checks database foreign key constraints enforced
- [ ] Test verifies run events ordered by timestamp
- [ ] Test checks artifact metadata matches file properties
- [ ] No orphaned records in run_files without corresponding runs
- [ ] No orphaned files in storage without run_files records

## Validation Criteria

- [ ] Manual run - `.\scripts\test-sync-happy-path.ps1` exits with code 0
- [ ] Manual run - `.\scripts\test-sync-idempotency.ps1` shows "skipped" in output
- [ ] Manual run - `.\scripts\test-sync-network-failure.ps1` demonstrates retry behavior
- [ ] Manual verification - check `.felix\outbox\` is empty after successful sync
- [ ] Manual verification - `ls storage\runs\` shows organized directory structure

## Technical Notes

**Architecture:** End-to-end tests exercise full stack from CLI through database to storage. Tests use temporary directories and test database to avoid polluting production data.

**Isolation:** Each test restores clean state before running. Use separate test database or dedicated schema. Cleanup scripts remove test data after completion.

**Performance:** Benchmark tests establish baseline for regression detection. Track metrics over time to detect performance degradation.

**Don't assume not implemented:** Check for existing test scripts in scripts/ directory. May have partial test coverage or different test organization.

## Non-Goals

- Load testing with thousands of concurrent agents
- Stress testing to find system limits
- Security penetration testing
- Performance optimization (establish baseline only)
- Frontend testing (covered in Phase 6)
