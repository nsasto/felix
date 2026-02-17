#!/usr/bin/env python3
"""
Generates a Felix Sync API key for CLI agent authentication.

This script creates a secure random API key, stores its SHA256 hash in the
database, and displays the plain-text key ONCE. The plain-text key is never
stored and cannot be recovered.

Usage:
    py -3 scripts/generate-sync-key.py [options]

Options:
    --name NAME         Human-readable name for the key (default: auto-generated)
    --agent-id UUID     Restrict key to specific agent (optional)
    --expires-days N    Key expires after N days (optional, default: no expiration)
    --db-url URL        Database URL (default: from DATABASE_URL env var)
    -h, --help          Show this help message

Exit Codes:
    0 - API key generated successfully
    1 - Error during key generation
    2 - Invalid arguments or missing database configuration

Example:
    py -3 scripts/generate-sync-key.py --name "Production Agent 1" --expires-days 365

Output:
    Felix Sync API Key Generated
    ============================
    Key: fsk_AbCd1234EfGh5678IjKl9012MnOp3456
    Name: Production Agent 1
    Expires: 2027-02-17

    IMPORTANT: Save this key securely. It cannot be retrieved again!
"""

import argparse
import hashlib
import os
import secrets
import string
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

# Ensure we can import from app/backend
script_dir = Path(__file__).resolve().parent
project_root = script_dir.parent
backend_dir = project_root / "app" / "backend"
sys.path.insert(0, str(backend_dir))


def generate_api_key(length: int = 32) -> str:
    """
    Generate a secure random API key with the 'fsk_' prefix.
    
    The key uses a URL-safe alphabet (letters + digits) for ease of use
    in headers and configuration files.
    
    Args:
        length: Length of the random portion (default: 32)
        
    Returns:
        API key in format 'fsk_XXXXXXXXXX...'
    """
    # Use letters and digits for URL-safe key
    alphabet = string.ascii_letters + string.digits
    random_part = ''.join(secrets.choice(alphabet) for _ in range(length))
    return f"fsk_{random_part}"


def hash_api_key(key: str) -> str:
    """
    Hash an API key using SHA256.
    
    Args:
        key: Plain-text API key
        
    Returns:
        Hex-encoded SHA256 hash
    """
    return hashlib.sha256(key.encode('utf-8')).hexdigest()


def get_database_url(db_url_arg: str | None) -> str | None:
    """
    Get the database URL from argument or environment.
    
    Args:
        db_url_arg: Database URL from command-line argument
        
    Returns:
        Database URL or None if not found
    """
    if db_url_arg:
        return db_url_arg
    
    # Try environment variable
    url = os.getenv("DATABASE_URL")
    if url:
        return url
    
    # Try loading from .env file
    env_file = backend_dir / ".env"
    if env_file.exists():
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith("DATABASE_URL="):
                    return line.split("=", 1)[1].strip()
    
    return None


def insert_api_key(
    db_url: str,
    key_hash: str,
    name: str | None,
    agent_id: str | None,
    expires_at: datetime | None,
) -> str:
    """
    Insert API key hash into the database.
    
    Uses psycopg2 for synchronous database access (simpler for CLI script).
    
    Args:
        db_url: PostgreSQL connection URL
        key_hash: SHA256 hash of the API key
        name: Human-readable name for the key
        agent_id: Optional agent ID to restrict key to
        expires_at: Optional expiration datetime
        
    Returns:
        UUID of the created api_key record
        
    Raises:
        Exception: On database error
    """
    try:
        import psycopg2
    except ImportError:
        print("Error: psycopg2 is required. Install with: pip install psycopg2-binary", file=sys.stderr)
        sys.exit(1)
    
    conn = None
    try:
        conn = psycopg2.connect(db_url)
        with conn.cursor() as cur:
            # Verify api_keys table exists
            cur.execute("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables 
                    WHERE table_schema = 'public' 
                    AND table_name = 'api_keys'
                )
            """)
            if not cur.fetchone()[0]:
                print("Error: api_keys table does not exist.", file=sys.stderr)
                print("Please run the migration first:", file=sys.stderr)
                print("  psql -d felix -f app\\backend\\migrations\\016_api_keys.sql", file=sys.stderr)
                sys.exit(1)
            
            # Insert the API key
            cur.execute("""
                INSERT INTO api_keys (key_hash, name, agent_id, expires_at)
                VALUES (%s, %s, %s, %s)
                RETURNING id
            """, (key_hash, name, agent_id, expires_at))
            
            key_id = cur.fetchone()[0]
            conn.commit()
            return str(key_id)
    finally:
        if conn:
            conn.close()


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Generate a Felix Sync API key for CLI agent authentication.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Example:
    py -3 scripts/generate-sync-key.py --name "Production Agent 1" --expires-days 365

The generated key will be shown once. Store it securely - it cannot be retrieved again.
"""
    )
    parser.add_argument(
        "--name",
        help="Human-readable name for the key (default: auto-generated timestamp)",
    )
    parser.add_argument(
        "--agent-id",
        help="Restrict key to specific agent UUID (optional)",
    )
    parser.add_argument(
        "--expires-days",
        type=int,
        help="Key expires after N days (optional, default: no expiration)",
    )
    parser.add_argument(
        "--db-url",
        help="Database URL (default: from DATABASE_URL env var or .env file)",
    )
    
    args = parser.parse_args()
    
    # Get database URL
    db_url = get_database_url(args.db_url)
    if not db_url:
        print("Error: Database URL not found.", file=sys.stderr)
        print("Set DATABASE_URL environment variable or use --db-url option.", file=sys.stderr)
        print("Example: set DATABASE_URL=postgresql://postgres@localhost:5432/felix", file=sys.stderr)
        return 2
    
    # Generate key name if not provided
    name = args.name
    if not name:
        name = f"sync-key-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}"
    
    # Calculate expiration if specified
    expires_at = None
    if args.expires_days:
        expires_at = datetime.now(timezone.utc) + timedelta(days=args.expires_days)
    
    # Generate the API key
    api_key = generate_api_key()
    key_hash = hash_api_key(api_key)
    
    try:
        # Insert into database
        key_id = insert_api_key(
            db_url=db_url,
            key_hash=key_hash,
            name=name,
            agent_id=args.agent_id,
            expires_at=expires_at,
        )
        
        # Display the result
        print()
        print("Felix Sync API Key Generated")
        print("=" * 40)
        print(f"Key:      {api_key}")
        print(f"Name:     {name}")
        print(f"ID:       {key_id}")
        if args.agent_id:
            print(f"Agent:    {args.agent_id}")
        if expires_at:
            print(f"Expires:  {expires_at.strftime('%Y-%m-%d %H:%M:%S UTC')}")
        else:
            print("Expires:  Never")
        print()
        print("=" * 40)
        print("IMPORTANT: Save this key securely!")
        print("It cannot be retrieved again.")
        print()
        print("To use this key, set the environment variable:")
        print(f"  $env:FELIX_SYNC_KEY = \"{api_key}\"")
        print()
        print("Or add to .felix/config.json:")
        print(f'  "sync": {{ "api_key": "{api_key}" }}')
        print()
        
        return 0
        
    except Exception as e:
        print(f"Error inserting API key into database: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
