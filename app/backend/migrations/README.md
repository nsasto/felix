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
| 001_seed_dev_data.sql  | Development seed data for local testing                                             | Auto-tracked |

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
  2 | 001_seed_dev_data.sql        | 2026-02-02 10:30:01.234567+00
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
```

What the script does:

- Create the database if it doesn't exist
- Create the migration tracking table
- Run all pending migrations
- Verify the schema

To force a fresh start (destroys all data):

```powershell
.\scripts\setup-db.ps1 -Force
```
