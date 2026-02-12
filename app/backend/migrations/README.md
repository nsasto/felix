# Database Migrations

This directory contains PostgreSQL database migrations for the Felix application.

## Prerequisites

- PostgreSQL server running on localhost:5432
- `psql` command-line tool available in PATH
- Access to postgres superuser (or equivalent permissions)

## Connection String Format

```
postgresql://postgres@localhost:5432/felix
```

For connecting with psql:

```bash
psql -U postgres -d felix
```

## Naming Convention

Migration files follow this naming pattern:

```
NNN_description.sql
```

Where:

- **NNN** - Three-digit sequence number (001, 002, 003, etc.)
- **description** - Brief snake_case description of the migration

Examples:

- `001_initial_schema.sql`
- `002_add_user_preferences.sql`
- `003_add_run_logs_table.sql`

## How to Run Migrations

### Running a Single Migration

```bash
psql -U postgres -d felix -f app/backend/migrations/001_initial_schema.sql
```

### Running All Migrations (in order)

From the project root:

```bash
for file in app/backend/migrations/*.sql; do
  psql -U postgres -d felix -f "$file"
done
```

On Windows PowerShell:

```powershell
Get-ChildItem app/backend/migrations/*.sql | Sort-Object Name | ForEach-Object {
  psql -U postgres -d felix -f $_.FullName
}
```

### Optional Dev Seed Data

The `001_seed_dev_data.sql` file is for local/dev seeding only. It is skipped by
default in `scripts/setup-db.ps1`. To include it:

```powershell
.\scripts\setup-db.ps1 -Seed
```

## How to Add New Migrations

1. Determine the next sequence number by checking existing migration files
2. Create a new file following the naming convention: `NNN_description.sql`
3. Write your SQL statements (CREATE TABLE, ALTER TABLE, etc.)
4. Make migrations idempotent where possible:
   - Use `CREATE TABLE IF NOT EXISTS` or `DROP TABLE IF EXISTS ... CASCADE`
   - Use `INSERT ... ON CONFLICT DO NOTHING` for seed data
5. Test the migration on a local database before committing
6. Document any rollback steps in comments at the end of the file

## Rollback Strategy

If a migration causes issues:

1. Drop the database and recreate:

   ```bash
   psql -U postgres -c "DROP DATABASE felix;"
   psql -U postgres -c "CREATE DATABASE felix;"
   ```

2. Re-run migrations with fixes

For production environments, always write explicit rollback scripts.

## Current Migrations

| File                   | Description                                                                         | Applied      |
| ---------------------- | ----------------------------------------------------------------------------------- | ------------ |
| 001_initial_schema.sql | Core tables: schema_migrations, organizations, projects, agents, runs, requirements | Auto-tracked |
| 002_enable_pgcrypto_and_status_checks.sql | Enable pgcrypto + align status constraints                             | Auto-tracked |
| 003_updated_at_triggers.sql | Auto-update updated_at columns via triggers                                 | Auto-tracked |
| 004_requirement_dependencies.sql | Join table for requirement dependencies                               | Auto-tracked |
| 005_requirement_content_versions.sql | Requirement content snapshot + version history                      | Auto-tracked |
| 006_add_requirement_code.sql | Add human-readable requirement code                                     | Auto-tracked |

## Dev Seed (Optional)

| File                  | Description                             | Applied              |
| --------------------- | --------------------------------------- | -------------------- |
| 001_seed_dev_data.sql | Development seed data for local testing | Only with `-Seed`    |

## Migration Tracking

The `schema_migrations` table tracks which migrations have been applied:

```sql
SELECT * FROM schema_migrations ORDER BY applied_at;
```

Output:

```
 id |           version            |          applied_at
----+------------------------------+-------------------------------
 1 | 001_initial_schema.sql       | 2026-02-02 10:30:00.123456+00
  2 | 001_seed_dev_data.sql        | 2026-02-02 10:30:01.234567+00  (dev only, when `-Seed` is used)
  3 | 002_enable_pgcrypto_and_status_checks.sql | 2026-02-02 10:30:02.345678+00
  4 | 003_updated_at_triggers.sql  | 2026-02-02 10:30:03.456789+00
  5 | 004_requirement_dependencies.sql | 2026-02-02 10:30:04.567890+00
  6 | 005_requirement_content_versions.sql | 2026-02-02 10:30:05.678901+00
  7 | 006_add_requirement_code.sql | 2026-02-02 10:30:06.789012+00
```

## Quick Setup

Run the automated setup script. The script now accepts `-PgBin` and `-DataDir` parameters
and reads `PG_BIN` / `PGDATA` / `DATABASE_URL` environment variables when present.

Examples (Windows PowerShell):

```powershell
# Use explicit Postgres install location and data directory
.\scripts\setup-db.ps1 -PgBin 'C:\Program Files\PostgreSQL\18\bin' -DataDir 'C:\Program Files\PostgreSQL\18\data'

# Or set environment variables (requires reopening shells to pick up User PATH changes):
setx PG_BIN "C:\Program Files\PostgreSQL\18\bin"
setx PGDATA "C:\Program Files\PostgreSQL\18\data"
.\scripts\setup-db.ps1

# If you already have a DATABASE_URL (e.g. for CI), the script will use it automatically:
$env:DATABASE_URL = 'postgresql://postgres:password@localhost:5432/felix'
.\scripts\setup-db.ps1

# Include dev seed data
.\scripts\setup-db.ps1 -Seed
```

What the script does:

- Create the database if it doesn't exist
- Create the migration tracking table
- Run all pending migrations (seed data optional)

## Requirement Content + Versions (Working Model)

We store spec content separately from the `requirements` table:

- `requirement_content`: current snapshot for fast reads
- `requirement_versions`: append-only history for audit/rollback

Write flow:
1) Insert a new row into `requirement_versions` with `content`, `author_id`, and `source`.
2) Upsert `requirement_content` for the requirement:
   - `content` = latest content
   - `current_version_id` = new version ID
   - `updated_at` = NOW()

Read flow:
- Default reads use `requirement_content` (single row).
- History/rollback uses `requirement_versions` ordered by `created_at DESC`.

## Requirements.json Migration Script

Use the PowerShell helper to migrate `.felix/requirements.json` into the DB:

```powershell
.\scripts\migrate-requirements.ps1 -ProjectId "00000000-0000-0000-0000-000000000001"
```

Dry run (no DB writes):

```powershell
.\scripts\migrate-requirements.ps1 -ProjectId "00000000-0000-0000-0000-000000000001" -DryRun
```

This script:
- Strips `S-XXXX:` from titles
- Writes `code` into `requirements.code`
- Inserts content into `requirement_content` + `requirement_versions`
- Inserts dependency rows into `requirement_dependencies`
- Verify the schema

To force a fresh start (destroys all data):

```powershell
.\scripts\setup-db.ps1 -Force
```
