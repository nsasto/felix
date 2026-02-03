# Spec Creation Rules

1. **Header Metadata**
   - Start each spec with `# S-NNNN: <Title>` where `S-NNNN` is incremented sequentially.
   - Follow immediately with `## Narrative` describing stakeholder goals or motivations.

2. **Acceptance & Validation Criteria**
   - Include `## Acceptance Criteria` with Markdown checkboxes detailing expected behavior.
   - When applicable, add `## Validation Criteria` (or equivalent) listing concrete commands/observables required for verification.
   - **CRITICAL - Backtick Usage**: Only use backticks for complete, executable commands that can be run in a terminal:
     - ✅ CORRECT: `curl http://localhost:8080/api/agents` (full executable command)
     - ✅ CORRECT: `python -m pytest tests/` (full executable command)
     - ❌ WRONG: Check `..felix/agents.json` file (file path - will be executed as command)
     - ❌ WRONG: Verify `config.json` updated (partial text - will be executed)
     - ✅ CORRECT: Check ..felix/agents.json file (no backticks for file paths)
     - ✅ CORRECT: Manual verification - verify config.json updated (no backticks)
   - If a validation step cannot be automated with a single shell command, mark it as "Manual verification" without backticks.

3. **Technical Guidance**
   - Provide sections such as `## Technical Notes`, `## Solution`, or `## Technical Details` to capture implementation direction, architecture constraints, or workflow expectations. Do NOT Instruct the developers how to implement.

4. **Problem/Context & Non-Goals**
   - As needed, include `## Problem`, `## Solution`, `## Non-Goals`, or `## Dependencies` to clarify motivations, scope boundaries, and required prerequisites.

5. **Artifacts & Infrastructure**
   - Reference relevant files, scripts, or runtime artifacts (e.g., `felix-agent.ps1`, `scripts/validate-requirement.py`, `runs/` artifacts) and describe their expected semantics or placement.

6. **Status Tracking & Observability**
   - Describe how `..felix/requirements.json` should be updated and how UI/agent indicators (status badges, plan markers, timestamps) should reflect spec state.

These rules ensure all specs share a consistent structure for planning, validation, and observability.

---

## Example Spec Layout

```markdown
# S-0042: User Authentication System

## Narrative

As a platform operator, I need users to authenticate securely so that we can protect sensitive data and provide personalized experiences while maintaining compliance with security standards.

## Acceptance Criteria

### Authentication Flow

- [ ] User can register with email and password
- [ ] Password requirements enforced (min 12 chars, special chars, numbers)
- [ ] User can log in with valid credentials
- [ ] Failed login attempts are rate-limited (max 5 per minute)
- [ ] User sessions expire after 24 hours of inactivity

### Security

- [ ] Passwords are hashed using bcrypt with salt
- [ ] JWT tokens are signed and validated
- [ ] Refresh tokens stored securely with expiration
- [ ] HTTPS enforced for all auth endpoints

### API Endpoints

- [ ] POST /api/auth/register returns 201 on success
- [ ] POST /api/auth/login returns JWT token
- [ ] POST /api/auth/refresh validates and issues new token
- [ ] POST /api/auth/logout invalidates session

## Technical Notes

**Architecture:** Token-based authentication using JWT with refresh token rotation. Backend validates all requests via middleware that checks token signature and expiration.

**Storage:** User credentials in PostgreSQL users table. Refresh tokens in separate auth_tokens table with foreign key to users.

**Don't assume not implemented:** Check existing auth middleware and user models before implementing. May have partial implementation from earlier work.

## Dependencies

- S-0002 (Backend API Server) - requires FastAPI server running
- S-0015 (Database Schema) - requires users table structure

## Non-Goals

- OAuth/social login (separate requirement)
- Two-factor authentication (future enhancement)
- Password reset via email (separate requirement)
```


