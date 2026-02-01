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

| File | Description |
|------|-------------|
| 001_initial_schema.sql | Core tables: organizations, projects, agents, runs, requirements |
| 001_seed_dev_data.sql | Development seed data for local testing |
