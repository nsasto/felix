# S-0050: Data Migration Script

**Phase:** 4 (Production Hardening)  
**Effort:** 4-6 hours  
**Priority:** High  
**Dependencies:** S-0049

---

## Narrative

This specification covers creating a Python script that migrates historical data from the file-based system (..felix/\*.json, runs/ directory) to the Supabase database. This is a one-time migration that preserves all historical runs, requirements, and agent configurations.

---

## Acceptance Criteria

### Migration Script

- [ ] Create **scripts/migrate_file_data.py** that:
  - Reads ..felix/requirements.json
  - Reads ..felix/agents.json
  - Scans runs/ directory for historical runs
  - Inserts data into Supabase database
  - Handles errors gracefully (continue on failure)
  - Reports progress and statistics

### Data Mapping

- [ ] Map requirements.json → requirements table
- [ ] Map agents.json → agents table (if not already in DB)
- [ ] Map runs/ directory → runs table + run_artifacts table
- [ ] Preserve timestamps, metadata, relationships

### Validation

- [ ] Verify no duplicate data (check UUIDs before insert)
- [ ] Verify foreign key relationships valid
- [ ] Report skipped/failed records
- [ ] Generate migration summary report

---

## Technical Notes

### Migration Script (scripts/migrate_file_data.py)

```python
#!/usr/bin/env python3
"""
Migrate file-based data to Supabase database.

Usage:
    python scripts/migrate_file_data.py

Requires:
    - .env file with DATABASE_URL and Supabase credentials
    - ..felix/requirements.json
    - ..felix/agents.json (optional)
    - runs/ directory with historical runs
"""

import os
import json
import asyncio
from pathlib import Path
from datetime import datetime
from databases import Database
from dotenv import load_dotenv

load_dotenv('app/backend/.env')

DATABASE_URL = os.getenv('DATABASE_URL')
DEV_PROJECT_ID = os.getenv('DEV_PROJECT_ID', '00000000-0000-0000-0000-000000000001')
DEV_ORG_ID = os.getenv('DEV_ORG_ID', '00000000-0000-0000-0000-000000000001')

db = Database(DATABASE_URL)

class MigrationStats:
    def __init__(self):
        self.requirements_inserted = 0
        self.requirements_skipped = 0
        self.agents_inserted = 0
        self.agents_skipped = 0
        self.runs_inserted = 0
        self.runs_skipped = 0
        self.artifacts_inserted = 0
        self.errors = []

stats = MigrationStats()

async def migrate_requirements():
    """Migrate requirements from ..felix/requirements.json"""
    print("📋 Migrating requirements...")

    req_file = Path('..felix/requirements.json')
    if not req_file.exists():
        print("  ⚠️  requirements.json not found, skipping")
        return

    with open(req_file) as f:
        requirements = json.load(f)

    for req in requirements:
        try:
            # Check if requirement already exists
            existing = await db.fetch_one(
                "SELECT id FROM requirements WHERE id = :id",
                {"id": req['id']}
            )

            if existing:
                print(f"  ⏭️  Requirement {req['id']} already exists, skipping")
                stats.requirements_skipped += 1
                continue

            # Insert requirement
            await db.execute("""
                INSERT INTO requirements (id, project_id, title, spec_path, status, priority, metadata, created_at, updated_at)
                VALUES (:id, :project_id, :title, :spec_path, :status, :priority, :metadata, :created_at, :updated_at)
            """, {
                "id": req['id'],
                "project_id": DEV_PROJECT_ID,
                "title": req['title'],
                "spec_path": req['spec_path'],
                "status": req.get('status', 'planned'),
                "priority": req.get('priority', 'medium'),
                "metadata": json.dumps(req.get('metadata', {})),
                "created_at": req.get('created_at', datetime.utcnow().isoformat()),
                "updated_at": req.get('updated_at', datetime.utcnow().isoformat())
            })

            print(f"  ✅ Migrated requirement: {req['title']}")
            stats.requirements_inserted += 1

        except Exception as e:
            print(f"  ❌ Failed to migrate requirement {req.get('id')}: {e}")
            stats.errors.append(f"Requirement {req.get('id')}: {e}")

async def migrate_agents():
    """Migrate agents from ..felix/agents.json"""
    print("\n🤖 Migrating agents...")

    agents_file = Path('..felix/agents.json')
    if not agents_file.exists():
        print("  ⚠️  agents.json not found, skipping")
        return

    with open(agents_file) as f:
        agents = json.load(f)

    for agent_id, agent_data in agents.items():
        try:
            # Check if agent already exists
            existing = await db.fetch_one(
                "SELECT id FROM agents WHERE id = :id",
                {"id": agent_id}
            )

            if existing:
                print(f"  ⏭️  Agent {agent_id} already exists, skipping")
                stats.agents_skipped += 1
                continue

            # Insert agent
            await db.execute("""
                INSERT INTO agents (id, project_id, name, type, status, metadata, created_at, updated_at)
                VALUES (:id, :project_id, :name, :type, :status, :metadata, :created_at, :updated_at)
            """, {
                "id": agent_id,
                "project_id": DEV_PROJECT_ID,
                "name": agent_data.get('name', agent_id),
                "type": agent_data.get('type', 'ralph'),
                "status": agent_data.get('status', 'idle'),
                "metadata": json.dumps(agent_data.get('metadata', {})),
                "created_at": agent_data.get('created_at', datetime.utcnow().isoformat()),
                "updated_at": agent_data.get('updated_at', datetime.utcnow().isoformat())
            })

            print(f"  ✅ Migrated agent: {agent_data.get('name', agent_id)}")
            stats.agents_inserted += 1

        except Exception as e:
            print(f"  ❌ Failed to migrate agent {agent_id}: {e}")
            stats.errors.append(f"Agent {agent_id}: {e}")

async def migrate_runs():
    """Migrate runs from runs/ directory"""
    print("\n🏃 Migrating runs...")

    runs_dir = Path('runs')
    if not runs_dir.exists():
        print("  ⚠️  runs/ directory not found, skipping")
        return

    # Scan for run directories (timestamp format: YYYY-MM-DDTHH-MM-SS)
    run_dirs = [d for d in runs_dir.iterdir() if d.is_dir()]
    print(f"  Found {len(run_dirs)} run directories")

    for run_dir in run_dirs:
        try:
            # Extract timestamp from directory name
            run_timestamp = run_dir.name  # e.g., "2026-01-26T15-42-19"

            # Generate UUID for run (use hash of timestamp for consistency)
            import uuid
            run_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, run_timestamp))

            # Check if run already exists
            existing = await db.fetch_one(
                "SELECT id FROM runs WHERE id = :id",
                {"id": run_id}
            )

            if existing:
                stats.runs_skipped += 1
                continue

            # Read run metadata if available
            metadata_file = run_dir / 'metadata.json'
            metadata = {}
            if metadata_file.exists():
                with open(metadata_file) as f:
                    metadata = json.load(f)

            # Determine agent_id (default to 'legacy-agent' if unknown)
            agent_id = metadata.get('agent_id', 'legacy-agent')

            # Ensure legacy agent exists
            if agent_id == 'legacy-agent':
                await db.execute("""
                    INSERT INTO agents (id, project_id, name, type, status, metadata)
                    VALUES (:id, :project_id, :name, :type, :status, :metadata)
                    ON CONFLICT (id) DO NOTHING
                """, {
                    "id": 'legacy-agent',
                    "project_id": DEV_PROJECT_ID,
                    "name": 'Legacy Agent (Migrated)',
                    "type": 'ralph',
                    "status": 'idle',
                    "metadata": json.dumps({"migrated": True})
                })

            # Insert run
            await db.execute("""
                INSERT INTO runs (id, project_id, agent_id, status, started_at, completed_at, metadata)
                VALUES (:id, :project_id, :agent_id, :status, :started_at, :completed_at, :metadata)
            """, {
                "id": run_id,
                "project_id": DEV_PROJECT_ID,
                "agent_id": agent_id,
                "status": metadata.get('status', 'completed'),
                "started_at": metadata.get('started_at', run_timestamp.replace('T', ' ').replace('-', ':')),
                "completed_at": metadata.get('completed_at'),
                "metadata": json.dumps(metadata)
            })

            # Migrate artifacts (output.log, etc.)
            log_file = run_dir / 'output.log'
            if log_file.exists():
                await db.execute("""
                    INSERT INTO run_artifacts (run_id, artifact_type, file_path, metadata)
                    VALUES (:run_id, :artifact_type, :file_path, :metadata)
                """, {
                    "run_id": run_id,
                    "artifact_type": "log",
                    "file_path": str(log_file),
                    "metadata": json.dumps({"size": log_file.stat().st_size})
                })
                stats.artifacts_inserted += 1

            print(f"  ✅ Migrated run: {run_dir.name}")
            stats.runs_inserted += 1

        except Exception as e:
            print(f"  ❌ Failed to migrate run {run_dir.name}: {e}")
            stats.errors.append(f"Run {run_dir.name}: {e}")

async def print_summary():
    """Print migration summary"""
    print("\n" + "=" * 60)
    print("📊 Migration Summary")
    print("=" * 60)
    print(f"Requirements: {stats.requirements_inserted} inserted, {stats.requirements_skipped} skipped")
    print(f"Agents:       {stats.agents_inserted} inserted, {stats.agents_skipped} skipped")
    print(f"Runs:         {stats.runs_inserted} inserted, {stats.runs_skipped} skipped")
    print(f"Artifacts:    {stats.artifacts_inserted} inserted")
    print(f"Errors:       {len(stats.errors)}")

    if stats.errors:
        print("\n❌ Errors:")
        for error in stats.errors[:10]:  # Show first 10 errors
            print(f"  - {error}")
        if len(stats.errors) > 10:
            print(f"  ... and {len(stats.errors) - 10} more")

    print("\n✅ Migration complete!")

async def main():
    print("🚀 Starting file data migration to Supabase...\n")

    await db.connect()

    try:
        await migrate_requirements()
        await migrate_agents()
        await migrate_runs()
    finally:
        await db.disconnect()

    await print_summary()

if __name__ == '__main__':
    asyncio.run(main())
```

---

## Dependencies

**Depends On:**

- S-0049: Organization Context and Switcher (Phase 3 complete)

**Blocks:**

- S-0051: Monitoring, Logging, and Health Checks

---

## Validation Criteria

### Script Execution

```bash
python scripts/migrate_file_data.py
```

Expected output:

```
🚀 Starting file data migration to Supabase...

📋 Migrating requirements...
  ✅ Migrated requirement: Implement WebSocket Support
  ✅ Migrated requirement: Add Database Integration
  ... (30 requirements)

🤖 Migrating agents...
  ✅ Migrated agent: ralph-agent-1
  ⏭️  Agent ralph-agent-2 already exists, skipping

🏃 Migrating runs...
  Found 147 run directories
  ✅ Migrated run: 2026-01-26T15-42-19
  ... (147 runs)

============================================================
📊 Migration Summary
============================================================
Requirements: 30 inserted, 0 skipped
Agents:       1 inserted, 1 skipped
Runs:         147 inserted, 0 skipped
Artifacts:    147 inserted
Errors:       0

✅ Migration complete!
```

### Data Verification

```sql
-- Verify migrated data in Supabase
SELECT COUNT(*) FROM requirements;  -- Should match ..felix/requirements.json count
SELECT COUNT(*) FROM agents;        -- Should match ..felix/agents.json count
SELECT COUNT(*) FROM runs;          -- Should match runs/ directory count
SELECT COUNT(*) FROM run_artifacts; -- Should match log files count
```

### Idempotency Test

```bash
# Run migration twice
python scripts/migrate_file_data.py
python scripts/migrate_file_data.py
```

Expected: Second run skips all records (no duplicates created)

---

## Rollback Strategy

If migration corrupts data:

1. Truncate tables: `TRUNCATE requirements, agents, runs, run_artifacts CASCADE;`
2. Re-apply seed data: `psql ... -f migrations/001_seed_dev_data.sql`
3. Fix migration script
4. Re-run migration

**Backup Before Migration:**

```bash
pg_dump -U postgres -d felix > backup_before_migration_$(date +%Y%m%d).sql
```

---

## Notes

- Migration script is idempotent (safe to run multiple times)
- Historical runs/ directories remain intact (not deleted)
- Legacy agent created automatically for runs without agent_id
- UUIDs for runs generated deterministically from timestamp
- Large runs/ directories may take several minutes to migrate
- Progress is reported real-time during migration
- Errors don't stop migration (best-effort approach)
- After migration, ..felix/\*.json files can be archived (not deleted yet)
- Run script during low-traffic period
- Total migration time: ~1-5 minutes for typical dataset (< 1000 runs)



