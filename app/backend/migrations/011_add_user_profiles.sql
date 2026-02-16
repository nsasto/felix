-- Felix Database Migration 011
-- Add user_profiles table for personal settings and avatar storage.

CREATE TABLE IF NOT EXISTS user_profiles (
    user_id TEXT PRIMARY KEY,
    email TEXT,
    display_name TEXT,
    full_name TEXT,
    title TEXT,
    bio TEXT,
    phone TEXT,
    location TEXT,
    website TEXT,
    avatar_bytes BYTEA,
    avatar_content_type TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Updated at trigger
DROP TRIGGER IF EXISTS set_updated_at_user_profiles ON user_profiles;
CREATE TRIGGER set_updated_at_user_profiles
BEFORE UPDATE ON user_profiles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ROLLBACK (manual)
-- DROP TRIGGER IF EXISTS set_updated_at_user_profiles ON user_profiles;
-- DROP TABLE IF EXISTS user_profiles;
