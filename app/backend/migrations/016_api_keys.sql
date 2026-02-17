-- Felix Database Migration 016
-- API Keys for Sync Authentication
-- 
-- Creates the api_keys table for authenticating CLI sync operations.
-- API keys are stored as SHA256 hashes for security.
--
-- Related specs:
-- - S-0064: Run Artifact Sync - Production Readiness
--
-- IDEMPOTENCY: This migration uses CREATE TABLE IF NOT EXISTS
-- so it can be run multiple times safely.

-- ============================================================================
-- API KEYS TABLE
-- ============================================================================
-- Stores API keys for sync endpoint authentication.
-- Keys are hashed using SHA256 and stored as hex strings.
-- Each key can optionally be tied to a specific agent_id for scoped access.

CREATE TABLE IF NOT EXISTS api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Key hash (SHA256 of the plain text key, stored as hex)
    -- The plain text key is only shown once at generation time
    key_hash TEXT NOT NULL UNIQUE,
    
    -- Optional: restrict key to specific agent
    -- NULL means the key can be used by any agent
    agent_id UUID REFERENCES agents(id) ON DELETE CASCADE,
    
    -- Optional: human-readable name/description for the key
    name TEXT,
    
    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,  -- NULL means never expires
    last_used_at TIMESTAMPTZ,
    
    -- Optional: track who created the key (user_id from auth)
    created_by TEXT
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Primary lookup by key_hash (for authentication)
-- Already has UNIQUE constraint which creates an index

-- Lookup by agent_id (to list keys for an agent)
CREATE INDEX IF NOT EXISTS idx_api_keys_agent_id ON api_keys(agent_id);

-- Filter by expiration (to find expired keys for cleanup)
CREATE INDEX IF NOT EXISTS idx_api_keys_expires_at ON api_keys(expires_at) 
    WHERE expires_at IS NOT NULL;

-- Partial index for active (non-expired) keys
CREATE INDEX IF NOT EXISTS idx_api_keys_active ON api_keys(key_hash) 
    WHERE expires_at IS NULL OR expires_at > NOW();

-- ============================================================================
-- API KEY USAGE LOG TABLE
-- ============================================================================
-- Audit trail for API key usage (optional, for security auditing)

CREATE TABLE IF NOT EXISTS api_key_usage_log (
    id BIGSERIAL PRIMARY KEY,
    key_id UUID NOT NULL REFERENCES api_keys(id) ON DELETE CASCADE,
    used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    endpoint TEXT NOT NULL,
    agent_id TEXT,  -- The agent_id from the request (may differ from key's agent_id)
    ip_address TEXT,
    user_agent TEXT,
    success BOOLEAN NOT NULL DEFAULT TRUE
);

-- Index for querying usage by key
CREATE INDEX IF NOT EXISTS idx_api_key_usage_log_key_id 
    ON api_key_usage_log(key_id, used_at DESC);

-- Index for querying usage by time (for cleanup/reporting)
CREATE INDEX IF NOT EXISTS idx_api_key_usage_log_used_at 
    ON api_key_usage_log(used_at DESC);

-- Partial index for failed attempts (security monitoring)
CREATE INDEX IF NOT EXISTS idx_api_key_usage_log_failed 
    ON api_key_usage_log(used_at DESC) 
    WHERE success = FALSE;

-- ============================================================================
-- COMPLETION
-- ============================================================================

SELECT 'Migration 016: API keys schema applied' AS status;

-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- To rollback this migration, run the following commands in order:
--
-- -- Drop usage log table first (depends on api_keys)
-- DROP TABLE IF EXISTS api_key_usage_log CASCADE;
--
-- -- Drop indexes (will be dropped with table, but explicit for clarity)
-- DROP INDEX IF EXISTS idx_api_keys_agent_id;
-- DROP INDEX IF EXISTS idx_api_keys_expires_at;
-- DROP INDEX IF EXISTS idx_api_keys_active;
--
-- -- Drop main table
-- DROP TABLE IF EXISTS api_keys CASCADE;
