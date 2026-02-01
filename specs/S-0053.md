# S-0053: Production Testing and Validation

**Phase:** 4 (Production Hardening)  
**Effort:** 8-10 hours  
**Priority:** Critical  
**Dependencies:** S-0052

---

## Narrative

This specification covers comprehensive testing of the production deployment to ensure all features work correctly, security is enforced, performance meets requirements, and the system handles edge cases gracefully. This is the final validation before declaring the migration complete.

---

## Acceptance Criteria

### Functional Testing

- [ ] User signup and authentication
- [ ] Agent registration
- [ ] Run creation and control
- [ ] Console streaming
- [ ] Organization switching
- [ ] Real-time updates

### Security Testing

- [ ] RLS isolation between users
- [ ] JWT token validation
- [ ] Unauthorized access blocked
- [ ] Personal org auto-creation

### Performance Testing

- [ ] Real-time latency < 500ms
- [ ] API response time < 200ms (p95)
- [ ] Load test: 10 concurrent agents
- [ ] Database query performance

### Failover Testing

- [ ] Agent disconnection handling
- [ ] WebSocket reconnection
- [ ] Database connection recovery
- [ ] Network interruption recovery

---

## Technical Notes

### Test Suite Structure

```
tests/
├── e2e/
│   ├── test_signup_flow.py
│   ├── test_agent_registration.py
│   ├── test_run_creation.py
│   └── test_realtime_updates.py
├── security/
│   ├── test_rls_isolation.py
│   ├── test_jwt_validation.py
│   └── test_unauthorized_access.py
├── performance/
│   ├── test_api_latency.py
│   ├── test_realtime_latency.py
│   └── test_concurrent_agents.py
└── failover/
    ├── test_websocket_reconnect.py
    └── test_db_recovery.py
```

### Functional Test Cases

**Test 1: User Signup and Personal Org Creation**

```python
async def test_signup_creates_personal_org():
    # Sign up new user
    response = await supabase.auth.sign_up({
        "email": "test@example.com",
        "password": "SecurePass123!@#"
    })
    user_id = response.user.id

    # Verify personal org created
    orgs = await supabase.from_('organizations').select('*').eq('owner_id', user_id)
    assert len(orgs) == 1
    assert orgs[0]['metadata']['personal'] == True

    # Verify user is owner
    members = await supabase.from_('organization_members').select('*').eq('user_id', user_id)
    assert members[0]['role'] == 'owner'
```

**Test 2: Agent Registration**

```python
async def test_agent_registration():
    # Register agent
    response = await api_client.post('/api/agents/register', json={
        "agent_id": "test-agent-1",
        "name": "Test Agent",
        "type": "ralph"
    }, headers={"Authorization": f"Bearer {jwt_token}"})

    assert response.status_code == 201
    agent = response.json()
    assert agent['name'] == 'Test Agent'
    assert agent['status'] == 'idle'
```

**Test 3: Run Creation and Control**

```python
async def test_run_lifecycle():
    # Connect agent to control WebSocket
    ws = await connect_control_websocket(agent_id, jwt_token)

    # Create run
    response = await api_client.post('/api/agents/runs', json={
        "agent_id": agent_id
    }, headers={"Authorization": f"Bearer {jwt_token}"})

    assert response.status_code == 201
    run = response.json()

    # Verify agent receives START command
    message = await ws.recv()
    assert message['type'] == 'command'
    assert message['command'] == 'START'

    # Agent sends status update
    await ws.send(json.dumps({
        "type": "status",
        "status": "running",
        "run_id": run['id']
    }))

    # Verify run status updated in database
    run_updated = await api_client.get(f'/api/agents/runs/{run["id"]}', headers={"Authorization": f"Bearer {jwt_token}"})
    assert run_updated.json()['status'] == 'running'
```

**Test 4: Real-time Updates**

```python
async def test_realtime_updates():
    # Subscribe to agents table
    events = []
    def on_insert(payload):
        events.append(('INSERT', payload))

    supabase.channel('test-channel').on('postgres_changes', {
        'event': 'INSERT',
        'schema': 'public',
        'table': 'agents'
    }, on_insert).subscribe()

    # Insert agent via API
    await api_client.post('/api/agents/register', json={
        "agent_id": "realtime-test-agent",
        "name": "Realtime Test"
    }, headers={"Authorization": f"Bearer {jwt_token}"})

    # Wait for realtime event
    await asyncio.sleep(1)

    # Verify event received
    assert len(events) == 1
    assert events[0][0] == 'INSERT'
    assert events[0][1]['new']['name'] == 'Realtime Test'
```

### Security Test Cases

**Test 5: RLS Isolation**

```python
async def test_rls_isolation():
    # User 1 creates agent
    agent1 = await api_client.post('/api/agents/register', json={
        "agent_id": "user1-agent",
        "name": "User 1 Agent"
    }, headers={"Authorization": f"Bearer {user1_token}"})

    # User 2 tries to list agents
    response = await api_client.get('/api/agents', headers={"Authorization": f"Bearer {user2_token}"})
    agents = response.json()['agents']

    # User 2 should NOT see User 1's agent
    assert not any(a['id'] == 'user1-agent' for a in agents)
```

**Test 6: JWT Validation**

```python
async def test_jwt_validation():
    # Request without token
    response = await api_client.get('/api/agents')
    assert response.status_code == 401

    # Request with invalid token
    response = await api_client.get('/api/agents', headers={"Authorization": "Bearer invalid-token"})
    assert response.status_code == 401

    # Request with expired token
    expired_token = generate_expired_token()
    response = await api_client.get('/api/agents', headers={"Authorization": f"Bearer {expired_token}"})
    assert response.status_code == 401
```

### Performance Test Cases

**Test 7: API Latency**

```python
async def test_api_latency():
    latencies = []

    for _ in range(100):
        start = time.time()
        response = await api_client.get('/api/agents', headers={"Authorization": f"Bearer {jwt_token}"})
        latency = (time.time() - start) * 1000
        latencies.append(latency)

    p95 = sorted(latencies)[95]
    assert p95 < 200, f"P95 latency {p95}ms exceeds 200ms threshold"
```

**Test 8: Realtime Latency**

```python
async def test_realtime_latency():
    latencies = []

    for _ in range(50):
        # Record timestamp before insert
        start = time.time()

        # Insert agent
        await api_client.post('/api/agents/register', json={
            "agent_id": f"latency-test-{_}",
            "name": "Latency Test"
        }, headers={"Authorization": f"Bearer {jwt_token}"})

        # Wait for realtime event
        event = await wait_for_realtime_event()

        # Calculate latency
        latency = (time.time() - start) * 1000
        latencies.append(latency)

    avg_latency = sum(latencies) / len(latencies)
    assert avg_latency < 500, f"Average realtime latency {avg_latency}ms exceeds 500ms threshold"
```

**Test 9: Concurrent Agents**

```python
async def test_concurrent_agents():
    # Start 10 agents concurrently
    agents = []
    for i in range(10):
        agent_id = f"concurrent-agent-{i}"
        agents.append(agent_id)

        # Register agent
        await api_client.post('/api/agents/register', json={
            "agent_id": agent_id,
            "name": f"Concurrent Agent {i}"
        }, headers={"Authorization": f"Bearer {jwt_token}"})

        # Connect to control WebSocket
        ws = await connect_control_websocket(agent_id, jwt_token)

    # Verify all agents connected
    response = await api_client.get('/api/agents', headers={"Authorization": f"Bearer {jwt_token}"})
    assert len(response.json()['agents']) >= 10

    # Create runs for all agents concurrently
    tasks = [
        api_client.post('/api/agents/runs', json={"agent_id": agent_id}, headers={"Authorization": f"Bearer {jwt_token}"})
        for agent_id in agents
    ]
    responses = await asyncio.gather(*tasks)

    # Verify all runs created
    assert all(r.status_code == 201 for r in responses)
```

### Failover Test Cases

**Test 10: WebSocket Reconnection**

```python
async def test_websocket_reconnection():
    # Connect agent
    ws = await connect_control_websocket(agent_id, jwt_token)

    # Simulate disconnection
    await ws.close()

    # Reconnect
    ws = await connect_control_websocket(agent_id, jwt_token)

    # Verify agent can still receive commands
    await api_client.post('/api/agents/runs', json={"agent_id": agent_id}, headers={"Authorization": f"Bearer {jwt_token}"})
    message = await ws.recv()
    assert message['type'] == 'command'
```

---

## Dependencies

**Depends On:**

- S-0052: Docker Containerization and Deployment

**Blocks:** None (Final spec)

---

## Validation Criteria

### Test Execution

```bash
# Run all tests
pytest tests/ -v

# Run specific test suites
pytest tests/e2e/ -v
pytest tests/security/ -v
pytest tests/performance/ -v
pytest tests/failover/ -v
```

Expected: All tests pass (0 failures)

### Production Smoke Test Checklist

- [ ] **Signup:** Create new user account
- [ ] **Login:** Sign in with credentials
- [ ] **Personal Org:** Verify personal org auto-created
- [ ] **Agent Registration:** Register agent via API
- [ ] **Run Creation:** Start run from dashboard
- [ ] **Console Streaming:** View live console output
- [ ] **Real-time Updates:** Verify instant dashboard updates (no refresh)
- [ ] **Multi-Tab Sync:** Open 2 tabs, verify both update
- [ ] **Organization Switch:** Create team org, switch between orgs
- [ ] **RLS Isolation:** Create second user, verify data isolation

### Performance Benchmarks

- [ ] **API Latency:** P95 < 200ms
- [ ] **Realtime Latency:** Average < 500ms
- [ ] **Dashboard Load Time:** < 2 seconds
- [ ] **Console Streaming:** No dropped messages
- [ ] **Concurrent Agents:** 10 agents running simultaneously

### Security Checklist

- [ ] **No Token = 401:** API requests without JWT return 401
- [ ] **Invalid Token = 401:** Malformed/expired tokens rejected
- [ ] **RLS Working:** Users can't see other users' data
- [ ] **Personal Org Secured:** Users can't delete personal orgs
- [ ] **CORS Configured:** Only allowed origins can access API

---

## Rollback Strategy

If critical issues found:

1. Mark spec as blocked in requirements.json
2. Roll back to previous deployment
3. Fix issues in development
4. Re-test and re-deploy

---

## Success Metrics

**Quantitative:**

- 100% of test cases passing
- API latency < 200ms (p95)
- Realtime latency < 500ms (average)
- 0 security vulnerabilities
- 10+ concurrent agents supported

**Qualitative:**

- Dashboard loads quickly and responsively
- Real-time updates feel instant
- Console streaming is smooth
- Multi-tenant isolation is transparent
- Overall system feels production-ready

---

## Notes

- This is the final validation before declaring migration complete
- All previous phases (0-3) must be complete and working
- Tests should be automated and repeatable
- Performance benchmarks should be monitored over time
- Security testing should be ongoing (not just Phase 4)
- Load testing can reveal database indexing issues
- Consider setting up continuous testing pipeline
- Document any known issues or limitations
- Celebrate successful migration! 🎉🚀
