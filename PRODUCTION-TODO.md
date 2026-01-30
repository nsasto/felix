# Felix Production Readiness - SaaS Deployment TODO

## Overview

This document outlines the complete production readiness roadmap for Felix as a SaaS solution. The architecture consists of:

- **Frontend (React + Vite)**: Cloud-hosted web application
- **Backend (FastAPI)**: Cloud-hosted API and WebSocket server
- **Tray Manager (.NET WPF)**: Desktop application on developer machines

```mermaid
graph TB
    subgraph "Cloud Infrastructure"
        FE[Frontend<br/>React + Vite]
        BE[Backend<br/>FastAPI]
        DB[(Database<br/>PostgreSQL)]
        CACHE[(Redis Cache)]
        STORAGE[Object Storage<br/>S3/Azure Blob]
    end
    
    subgraph "Developer Machine"
        TRAY[Tray Manager<br/>.NET WPF]
        LOCAL[Local Felix Agent]
        FILES[Project Files]
    end
    
    BROWSER[Web Browser] -->|HTTPS| FE
    FE -->|REST/WebSocket| BE
    BE -->|Auth/Data| DB
    BE -->|Session/Cache| CACHE
    BE -->|Artifacts/Logs| STORAGE
    TRAY -->|WSS + Auth| BE
    TRAY -->|Manages| LOCAL
    LOCAL -->|R/W| FILES
    
    style FE fill:#e1f5ff
    style BE fill:#e1f5ff
    style TRAY fill:#fff4e1
    style LOCAL fill:#fff4e1
```

---

## 1. Authentication & Authorization

### 1.1 User Authentication (Frontend & Backend)

**Priority**: 🔴 CRITICAL

#### Tasks

- [ ] **Implement OAuth 2.0 / OpenID Connect provider integration**
  - Support GitHub, Google, Microsoft authentication
  - Use industry-standard library (e.g., `authlib` for Python)
  - Store JWT tokens securely in backend
  
- [ ] **Backend authentication middleware**
  - Create FastAPI dependency for JWT validation
  - Implement token refresh mechanism
  - Add rate limiting per user (prevent abuse)
  
- [ ] **Frontend authentication flow**
  - Implement login/logout UI
  - Store auth tokens in httpOnly cookies (not localStorage)
  - Add auth context provider in React
  - Implement automatic token refresh
  
- [ ] **Session management**
  - Use Redis for session storage
  - Implement session timeout (configurable, default 24h)
  - Add "remember me" functionality
  
- [ ] **Multi-tenant data isolation**
  - Add `tenant_id` or `user_id` to all database tables
  - Implement row-level security in queries
  - Ensure WebSocket connections filter by user

```mermaid
sequenceDiagram
    participant User
    participant Frontend
    participant Backend
    participant AuthProvider
    participant Database
    
    User->>Frontend: Click Login
    Frontend->>AuthProvider: Redirect to OAuth
    AuthProvider->>Frontend: Return auth code
    Frontend->>Backend: Exchange code for token
    Backend->>AuthProvider: Validate auth code
    AuthProvider->>Backend: User info + token
    Backend->>Database: Create/update user
    Backend->>Frontend: Return JWT + refresh token
    Frontend->>Frontend: Store tokens in httpOnly cookie
```

### 1.2 Tray Application Authentication

**Priority**: 🔴 CRITICAL

#### Tasks

- [ ] **Device registration flow**
  - Generate unique device ID on first launch
  - Implement device approval workflow in web UI
  - Store device certificates/tokens in Windows Credential Manager
  
- [ ] **Device-to-backend authentication**
  - Implement mutual TLS (mTLS) or API key per device
  - Add device fingerprinting (machine name, MAC address hash)
  - Support device revocation from web UI
  
- [ ] **Workspace authorization**
  - Associate devices with specific workspaces/projects
  - Implement project-level access control
  - Allow users to grant/revoke device access to projects
  
- [ ] **Secure credential storage**
  - Use Windows Credential Manager for API keys
  - Encrypt sensitive data at rest
  - Never store credentials in plain text config files

```csharp
// Example: Secure credential storage
using System.Security.Cryptography;
using Windows.Security.Credentials;

public class SecureStorage 
{
    private const string ResourceName = "FelixTrayApp";
    
    public void StoreDeviceToken(string token) 
    {
        var vault = new PasswordVault();
        vault.Add(new PasswordCredential(
            ResourceName, 
            "DeviceToken", 
            token
        ));
    }
    
    public string? GetDeviceToken() 
    {
        try 
        {
            var vault = new PasswordVault();
            var cred = vault.Retrieve(ResourceName, "DeviceToken");
            cred.RetrievePassword();
            return cred.Password;
        } 
        catch { return null; }
    }
}
```

---

## 2. Backend Cloud Readiness

### 2.1 Database Migration

**Priority**: 🔴 CRITICAL

**Current State**: File-based storage (`~/.felix/projects.json`, `~/.felix/agents.json`)

#### Tasks

- [ ] **Replace file storage with PostgreSQL**
  - Design schema for projects, users, agents, runs, requirements
  - Implement database models using SQLAlchemy or similar ORM
  - Add database migrations (Alembic)
  
- [ ] **Multi-tenancy schema**
  ```sql
  CREATE TABLE users (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      email VARCHAR(255) UNIQUE NOT NULL,
      created_at TIMESTAMP DEFAULT NOW(),
      last_login TIMESTAMP
  );
  
  CREATE TABLE projects (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID REFERENCES users(id) ON DELETE CASCADE,
      name VARCHAR(255) NOT NULL,
      path TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(user_id, name)
  );
  
  CREATE TABLE devices (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID REFERENCES users(id) ON DELETE CASCADE,
      device_name VARCHAR(255) NOT NULL,
      device_token TEXT NOT NULL,
      fingerprint TEXT,
      approved BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMP DEFAULT NOW(),
      last_seen TIMESTAMP
  );
  
  CREATE TABLE project_access (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
      device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
      granted_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(project_id, device_id)
  );
  
  CREATE TABLE runs (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
      requirement_id VARCHAR(50),
      started_at TIMESTAMP DEFAULT NOW(),
      completed_at TIMESTAMP,
      status VARCHAR(50),
      artifacts_url TEXT
  );
  ```

- [ ] **Data migration script**
  - Script to import existing `projects.json` → PostgreSQL
  - Preserve project IDs and timestamps
  
- [ ] **Connection pooling**
  - Configure SQLAlchemy connection pool
  - Set appropriate pool size based on expected load
  - Implement connection retry logic

### 2.2 File Storage (Artifacts & Logs)

**Priority**: 🔴 CRITICAL

**Current State**: Local filesystem (`runs/`, `specs/`, project files)

#### Tasks

- [ ] **Object storage integration**
  - Integrate AWS S3, Azure Blob Storage, or Google Cloud Storage
  - Store run artifacts (plans, logs, diffs) in object storage
  - Generate presigned URLs for secure file access
  
- [ ] **Project file synchronization**
  - Implement bidirectional sync between tray app and cloud
  - Use chunked uploads for large files
  - Handle conflict resolution (last-write-wins or version history)
  
- [ ] **Artifact cleanup policy**
  - Implement retention policies (e.g., delete runs > 90 days)
  - Compress old artifacts
  - Archive vs. delete options

```python
# Example: S3 artifact storage
import boto3
from botocore.exceptions import ClientError

class ArtifactStorage:
    def __init__(self, bucket_name: str):
        self.s3 = boto3.client('s3')
        self.bucket = bucket_name
    
    async def upload_run_artifact(
        self, 
        project_id: str, 
        run_id: str, 
        filename: str, 
        content: bytes
    ) -> str:
        key = f"{project_id}/runs/{run_id}/{filename}"
        self.s3.put_object(
            Bucket=self.bucket,
            Key=key,
            Body=content,
            ServerSideEncryption='AES256'
        )
        return key
    
    async def get_presigned_url(self, key: str, expires_in: int = 3600) -> str:
        return self.s3.generate_presigned_url(
            'get_object',
            Params={'Bucket': self.bucket, 'Key': key},
            ExpiresIn=expires_in
        )
```

### 2.3 WebSocket Scalability

**Priority**: 🟡 HIGH

**Current State**: In-memory connection manager, single-process

#### Tasks

- [ ] **Redis-backed WebSocket pub/sub**
  - Use Redis for WebSocket message broadcasting across instances
  - Implement cluster-aware connection manager
  - Support horizontal scaling with load balancer
  
- [ ] **WebSocket authentication**
  - Validate JWT token on WebSocket handshake
  - Disconnect on token expiry
  - Implement per-user connection limits
  
- [ ] **Sticky sessions or connection state sharing**
  - Configure load balancer for WebSocket sticky sessions
  - OR: Use Redis to store connection state

```python
# Example: Redis-backed WebSocket manager
import aioredis
from fastapi import WebSocket

class ScalableConnectionManager:
    def __init__(self):
        self.redis = aioredis.from_url("redis://localhost")
        self.local_connections: Dict[str, Set[WebSocket]] = {}
    
    async def broadcast(self, project_id: str, message: dict):
        # Publish to Redis for cross-instance delivery
        await self.redis.publish(
            f"project:{project_id}", 
            json.dumps(message)
        )
    
    async def subscribe_to_broadcasts(self):
        pubsub = self.redis.pubsub()
        await pubsub.psubscribe("project:*")
        
        async for message in pubsub.listen():
            if message['type'] == 'pmessage':
                # Forward to local WebSocket connections
                data = json.loads(message['data'])
                await self._send_to_local_connections(data)
```

### 2.4 Environment Configuration

**Priority**: 🟡 HIGH

#### Tasks

- [ ] **Environment-based configuration**
  - Separate configs for dev, staging, production
  - Use environment variables for secrets
  - Implement 12-factor app principles
  
- [ ] **Secret management**
  - Integrate AWS Secrets Manager, Azure Key Vault, or HashiCorp Vault
  - Rotate secrets automatically
  - Never commit secrets to version control
  
- [ ] **CORS configuration**
  - Update CORS to allow production frontend domain
  - Remove localhost origins in production
  - Implement CORS preflight caching

```python
# config.py
import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Database
    database_url: str = os.getenv("DATABASE_URL", "postgresql://...")
    
    # Redis
    redis_url: str = os.getenv("REDIS_URL", "redis://localhost:6379")
    
    # Object Storage
    s3_bucket: str = os.getenv("S3_BUCKET", "felix-artifacts")
    aws_region: str = os.getenv("AWS_REGION", "us-east-1")
    
    # Auth
    jwt_secret: str = os.getenv("JWT_SECRET")
    jwt_algorithm: str = "HS256"
    jwt_expiration_hours: int = 24
    
    # CORS
    allowed_origins: list = os.getenv("ALLOWED_ORIGINS", "").split(",")
    
    # Feature flags
    copilot_enabled: bool = os.getenv("COPILOT_ENABLED", "true").lower() == "true"
    
    class Config:
        env_file = ".env"

settings = Settings()
```

### 2.5 API Security

**Priority**: 🔴 CRITICAL

#### Tasks

- [ ] **Rate limiting**
  - Implement per-user and per-IP rate limits
  - Use Redis for distributed rate limiting
  - Return proper 429 status codes
  
- [ ] **Input validation**
  - Validate all request bodies with Pydantic
  - Sanitize file paths to prevent directory traversal
  - Limit request body sizes
  
- [ ] **HTTPS enforcement**
  - Configure SSL/TLS certificates (Let's Encrypt or cloud provider)
  - Redirect HTTP → HTTPS
  - Implement HSTS headers
  
- [ ] **Security headers**
  - Add CSP (Content Security Policy)
  - X-Frame-Options: DENY
  - X-Content-Type-Options: nosniff
  
- [ ] **API versioning**
  - Implement `/api/v1/` prefix
  - Plan for backward compatibility

```python
from fastapi import Request, HTTPException
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)

@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["Content-Security-Policy"] = "default-src 'self'"
    return response

@app.get("/api/v1/projects")
@limiter.limit("100/minute")
async def list_projects(request: Request, user: User = Depends(get_current_user)):
    # ... implementation
```

---

## 3. Frontend Cloud Readiness

### 3.1 Build & Deployment

**Priority**: 🟡 HIGH

#### Tasks

- [ ] **Production build optimization**
  - Configure Vite for production builds
  - Enable code splitting and lazy loading
  - Optimize bundle size (tree shaking, minification)
  - Generate source maps (store securely, don't expose)
  
- [ ] **Environment configuration**
  - Use `.env.production` for production API URLs
  - Remove hardcoded `localhost:8080` references
  - Implement feature flags
  
- [ ] **CDN integration**
  - Host static assets on CDN (CloudFront, Azure CDN)
  - Configure cache headers
  - Implement asset versioning/cache busting
  
- [ ] **Monitoring & error tracking**
  - Integrate Sentry or similar for error tracking
  - Implement analytics (Google Analytics, Mixpanel)
  - Add performance monitoring

```typescript
// src/config.ts
const config = {
  apiUrl: import.meta.env.VITE_API_URL || 'http://localhost:8080',
  wsUrl: import.meta.env.VITE_WS_URL || 'ws://localhost:8080',
  environment: import.meta.env.MODE,
  sentryDsn: import.meta.env.VITE_SENTRY_DSN,
};

export default config;
```

```bash
# .env.production
VITE_API_URL=https://api.felix.example.com
VITE_WS_URL=wss://api.felix.example.com
VITE_SENTRY_DSN=https://...
```

### 3.2 Authentication Integration

**Priority**: 🔴 CRITICAL

#### Tasks

- [ ] **Auth context provider**
  - Create React context for auth state
  - Implement login/logout flows
  - Handle token refresh
  
- [ ] **Protected routes**
  - Wrap routes with auth guard
  - Redirect unauthenticated users to login
  
- [ ] **API client with auth**
  - Add Authorization header to all API requests
  - Handle 401 responses (redirect to login)
  - Implement token refresh interceptor

```typescript
// src/contexts/AuthContext.tsx
import { createContext, useContext, useState, useEffect } from 'react';

interface AuthContextType {
  user: User | null;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  isAuthenticated: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  
  const login = async (email: string, password: string) => {
    const response = await fetch(`${config.apiUrl}/api/v1/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
      credentials: 'include', // Include cookies
    });
    const data = await response.json();
    setUser(data.user);
  };
  
  const logout = async () => {
    await fetch(`${config.apiUrl}/api/v1/auth/logout`, {
      method: 'POST',
      credentials: 'include',
    });
    setUser(null);
  };
  
  return (
    <AuthContext.Provider value={{ user, login, logout, isAuthenticated: !!user }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used within AuthProvider');
  return context;
};
```

---

## 4. Tray Manager Production Enhancements

### 4.1 Secure Communication

**Priority**: 🔴 CRITICAL

#### Tasks

- [ ] **HTTPS/WSS client implementation**
  - Update all HTTP calls to use HTTPS
  - Update WebSocket connections to use WSS (secure WebSocket)
  - Implement certificate validation
  
- [ ] **Device authentication**
  - Generate device ID on first launch
  - Implement device registration API call
  - Store device token in Windows Credential Manager
  - Add token to all API requests
  
- [ ] **Certificate pinning** (optional, high security)
  - Pin production API certificate
  - Prevent MITM attacks

```csharp
// Services/AuthService.cs
using System.Net.Http;
using System.Net.Http.Headers;
using Windows.Security.Credentials;

public class AuthService
{
    private readonly HttpClient _httpClient;
    private const string ApiBaseUrl = "https://api.felix.example.com";
    
    public AuthService()
    {
        _httpClient = new HttpClient();
    }
    
    public async Task<string> RegisterDeviceAsync()
    {
        var deviceId = GetOrCreateDeviceId();
        var deviceName = Environment.MachineName;
        
        var request = new
        {
            device_id = deviceId,
            device_name = deviceName,
            fingerprint = GetDeviceFingerprint()
        };
        
        var response = await _httpClient.PostAsJsonAsync(
            $"{ApiBaseUrl}/api/v1/devices/register", 
            request
        );
        
        response.EnsureSuccessStatusCode();
        var result = await response.Content.ReadFromJsonAsync<DeviceRegistrationResult>();
        
        // Store token securely
        StoreDeviceToken(result.Token);
        
        return result.Token;
    }
    
    public void AddAuthHeader(HttpRequestMessage request)
    {
        var token = GetDeviceToken();
        if (token != null)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }
    }
    
    private string GetDeviceFingerprint()
    {
        // Generate hash of machine-specific identifiers
        var machineId = Environment.MachineName;
        var username = Environment.UserName;
        // Add more unique identifiers (MAC address, CPU ID, etc.)
        
        using var sha = System.Security.Cryptography.SHA256.Create();
        var hash = sha.ComputeHash(System.Text.Encoding.UTF8.GetBytes($"{machineId}:{username}"));
        return Convert.ToBase64String(hash);
    }
}
```

### 4.2 Configuration Management

**Priority**: 🟡 HIGH

#### Tasks

- [ ] **Remote configuration**
  - Fetch API endpoint from cloud (not hardcoded)
  - Support configuration updates without reinstall
  - Implement configuration caching
  
- [ ] **Auto-update mechanism**
  - Implement ClickOnce deployment or Squirrel.Windows
  - Check for updates on startup
  - Download and install updates in background
  
- [ ] **Logging and diagnostics**
  - Implement structured logging (Serilog)
  - Upload crash reports to cloud
  - Add diagnostic info to crash reports

```csharp
// App.xaml.cs - Auto-update check
protected override async void OnStartup(StartupEventArgs e)
{
    base.OnStartup(e);
    
    // Check for updates
    var updateService = new UpdateService();
    if (await updateService.CheckForUpdatesAsync())
    {
        var result = MessageBox.Show(
            "A new version is available. Update now?",
            "Update Available",
            MessageBoxButton.YesNo
        );
        
        if (result == MessageBoxResult.Yes)
        {
            await updateService.DownloadAndInstallAsync();
            Shutdown();
            return;
        }
    }
    
    // Continue normal startup
    var mainWindow = new MainWindow();
    mainWindow.Show();
}
```

### 4.3 User Experience

**Priority**: 🟢 MEDIUM

#### Tasks

- [ ] **Connection status indicator**
  - Show online/offline status in tray icon
  - Display connection errors to user
  - Auto-reconnect on network recovery
  
- [ ] **Device approval workflow**
  - Show "waiting for approval" message
  - Poll for approval status
  - Guide user to web UI for approval
  
- [ ] **Project sync status**
  - Show upload/download progress
  - Display sync errors
  - Allow manual sync trigger

---

## 5. DevOps & Infrastructure

### 5.1 Containerization

**Priority**: 🟡 HIGH

#### Tasks

- [ ] **Backend Dockerfile**
  ```dockerfile
  FROM python:3.11-slim
  
  WORKDIR /app
  
  # Install dependencies
  COPY app/backend/requirements.txt .
  RUN pip install --no-cache-dir -r requirements.txt
  
  # Copy application
  COPY app/backend/ .
  
  # Create non-root user
  RUN useradd -m -u 1000 felix && chown -R felix:felix /app
  USER felix
  
  EXPOSE 8080
  
  CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
  ```

- [ ] **Frontend Dockerfile**
  ```dockerfile
  # Build stage
  FROM node:20-alpine AS builder
  
  WORKDIR /app
  COPY app/frontend/package*.json ./
  RUN npm ci
  
  COPY app/frontend/ .
  RUN npm run build
  
  # Production stage
  FROM nginx:alpine
  
  COPY --from=builder /app/dist /usr/share/nginx/html
  COPY nginx.conf /etc/nginx/nginx.conf
  
  EXPOSE 80
  CMD ["nginx", "-g", "daemon off;"]
  ```

- [ ] **Docker Compose for local development**
  ```yaml
  version: '3.8'
  
  services:
    postgres:
      image: postgres:15
      environment:
        POSTGRES_DB: felix
        POSTGRES_USER: felix
        POSTGRES_PASSWORD: felix_dev
      ports:
        - "5432:5432"
      volumes:
        - postgres_data:/var/lib/postgresql/data
    
    redis:
      image: redis:7-alpine
      ports:
        - "6379:6379"
    
    backend:
      build:
        context: .
        dockerfile: app/backend/Dockerfile
      environment:
        DATABASE_URL: postgresql://felix:felix_dev@postgres:5432/felix
        REDIS_URL: redis://redis:6379
      ports:
        - "8080:8080"
      depends_on:
        - postgres
        - redis
    
    frontend:
      build:
        context: .
        dockerfile: app/frontend/Dockerfile
      ports:
        - "3000:80"
      depends_on:
        - backend
  
  volumes:
    postgres_data:
  ```

### 5.2 CI/CD Pipeline

**Priority**: 🟡 HIGH

#### Tasks

- [ ] **GitHub Actions workflow**
  - Backend tests on PR
  - Frontend tests on PR
  - Tray app build on PR
  - Automated deployment to staging on merge to main
  - Manual approval for production deployment
  
- [ ] **Deployment automation**
  - Deploy backend to Kubernetes/ECS/App Service
  - Deploy frontend to S3 + CloudFront / Azure Static Web Apps
  - Publish tray app to release page
  
- [ ] **Database migration automation**
  - Run Alembic migrations on deployment
  - Implement rollback strategy

```yaml
# .github/workflows/deploy.yml
name: Deploy to Production

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  test-backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - run: pip install -r app/backend/requirements.txt
      - run: pytest app/backend/tests/
  
  test-frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '20'
      - run: npm ci
        working-directory: app/frontend
      - run: npm test
        working-directory: app/frontend
  
  build-tray:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-dotnet@v3
        with:
          dotnet-version: '8.0'
      - run: dotnet build app/tray-manager/FelixTrayApp.csproj -c Release
  
  deploy-backend:
    needs: [test-backend]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - # Build and push Docker image
      - # Deploy to cloud platform
  
  deploy-frontend:
    needs: [test-frontend]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - # Build and upload to CDN
```

### 5.3 Monitoring & Observability

**Priority**: 🟡 HIGH

#### Tasks

- [ ] **Application monitoring**
  - Integrate Datadog, New Relic, or open-source alternatives (Prometheus + Grafana)
  - Track request latency, error rates, throughput
  - Set up alerts for anomalies
  
- [ ] **Logging infrastructure**
  - Centralized logging (CloudWatch, Azure Monitor, ELK stack)
  - Structured JSON logging
  - Log retention policies
  
- [ ] **Health checks**
  - Implement `/health` and `/ready` endpoints
  - Configure load balancer health checks
  - Add database connectivity checks
  
- [ ] **Distributed tracing**
  - Implement OpenTelemetry
  - Trace requests across services
  - Visualize service dependencies

```python
# monitoring.py
from prometheus_client import Counter, Histogram, generate_latest
from fastapi import Request
import time

# Metrics
request_count = Counter(
    'felix_requests_total', 
    'Total requests', 
    ['method', 'endpoint', 'status']
)
request_duration = Histogram(
    'felix_request_duration_seconds',
    'Request duration',
    ['method', 'endpoint']
)

@app.middleware("http")
async def monitor_requests(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    duration = time.time() - start
    
    request_count.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code
    ).inc()
    
    request_duration.labels(
        method=request.method,
        endpoint=request.url.path
    ).observe(duration)
    
    return response

@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type="text/plain")
```

---

## 6. Compliance & Legal

### 6.1 Data Privacy

**Priority**: 🔴 CRITICAL

#### Tasks

- [ ] **GDPR compliance**
  - Implement data export functionality (user can download all their data)
  - Implement right to deletion (delete user and all associated data)
  - Add privacy policy and terms of service
  - Obtain consent for data collection
  
- [ ] **Data encryption**
  - Encrypt sensitive data at rest (database encryption)
  - Encrypt data in transit (TLS 1.3)
  - Encrypt backup files
  
- [ ] **Audit logging**
  - Log all data access and modifications
  - Track who accessed what and when
  - Retain audit logs for compliance period

### 6.2 Licensing & Usage Tracking

**Priority**: 🟢 MEDIUM

#### Tasks

- [ ] **Subscription management**
  - Integrate Stripe or similar payment processor
  - Implement tiered pricing (free, pro, enterprise)
  - Track usage limits (projects, devices, API calls)
  
- [ ] **License enforcement**
  - Validate subscription status on critical operations
  - Gracefully handle expired subscriptions
  - Provide upgrade prompts

---

## 7. Performance & Scalability

### 7.1 Database Optimization

**Priority**: 🟡 HIGH

#### Tasks

- [ ] **Indexing strategy**
  - Add indexes on frequently queried columns (user_id, project_id)
  - Composite indexes for complex queries
  - Regularly analyze query performance
  
- [ ] **Query optimization**
  - Use connection pooling
  - Implement pagination for large result sets
  - Use database views for complex aggregations
  
- [ ] **Caching strategy**
  - Cache frequently accessed data in Redis
  - Implement cache invalidation on updates
  - Set appropriate TTLs

### 7.2 API Performance

**Priority**: 🟡 HIGH

#### Tasks

- [ ] **Response optimization**
  - Implement compression (gzip)
  - Use ETags for conditional requests
  - Implement GraphQL or similar for flexible queries
  
- [ ] **Async processing**
  - Use background tasks for long-running operations
  - Implement job queue (Celery + Redis)
  - Provide job status endpoints

### 7.3 Frontend Performance

**Priority**: 🟢 MEDIUM

#### Tasks

- [ ] **Code splitting**
  - Lazy load routes
  - Split vendor bundles
  - Implement dynamic imports
  
- [ ] **Asset optimization**
  - Optimize images (WebP, compression)
  - Use CSS/JS minification
  - Implement lazy loading for images
  
- [ ] **Caching**
  - Configure service worker for offline support
  - Implement browser caching headers
  - Use CDN caching

---

## 8. Testing & Quality Assurance

### 8.1 Automated Testing

**Priority**: 🟡 HIGH

#### Tasks

- [ ] **Backend tests**
  - Unit tests for all business logic
  - Integration tests for API endpoints
  - E2E tests for critical workflows
  - Target 80%+ code coverage
  
- [ ] **Frontend tests**
  - Unit tests for components
  - Integration tests for user flows
  - Visual regression tests (Percy, Chromatic)
  
- [ ] **Tray app tests**
  - Unit tests for view models
  - Integration tests for API communication
  - UI automation tests

### 8.2 Security Testing

**Priority**: 🔴 CRITICAL

#### Tasks

- [ ] **Penetration testing**
  - Hire security firm or use bug bounty program
  - Test for OWASP Top 10 vulnerabilities
  - Fix all critical and high-severity issues
  
- [ ] **Dependency scanning**
  - Use Dependabot or Snyk
  - Regularly update dependencies
  - Scan for known vulnerabilities
  
- [ ] **Code scanning**
  - Static analysis (Bandit for Python, ESLint for JS)
  - Secret scanning (prevent API keys in code)

---

## 9. Documentation & Support

### 9.1 User Documentation

**Priority**: 🟢 MEDIUM

#### Tasks

- [ ] **Getting started guide**
  - Account registration walkthrough
  - Device setup instructions
  - First project tutorial
  
- [ ] **API documentation**
  - OpenAPI/Swagger documentation
  - SDK/client library examples
  - Rate limits and quotas
  
- [ ] **Troubleshooting guide**
  - Common issues and solutions
  - FAQ section
  - Status page integration

### 9.2 Support Infrastructure

**Priority**: 🟢 MEDIUM

#### Tasks

- [ ] **Support ticketing system**
  - Integrate Zendesk, Intercom, or open-source alternative
  - Implement in-app chat support
  - SLA for response times
  
- [ ] **Community forum**
  - Set up Discord or community platform
  - Encourage user-to-user support
  - Staff moderation

---

## 10. Cost Optimization

### 10.1 Infrastructure Costs

**Priority**: 🟢 MEDIUM

#### Tasks

- [ ] **Right-sizing resources**
  - Monitor actual resource usage
  - Scale down over-provisioned instances
  - Use auto-scaling for variable load
  
- [ ] **Reserved instances**
  - Purchase reserved instances for predictable workloads
  - Use spot instances for non-critical tasks
  
- [ ] **Data transfer optimization**
  - Use CDN to reduce egress costs
  - Compress responses
  - Implement efficient data sync (delta uploads)

### 10.2 Operational Efficiency

**Priority**: 🟢 MEDIUM

#### Tasks

- [ ] **Automated scaling**
  - Configure horizontal pod autoscaling (Kubernetes)
  - Scale based on CPU, memory, and custom metrics
  
- [ ] **Cost monitoring**
  - Set up billing alerts
  - Track cost per customer
  - Identify cost optimization opportunities

---

## Implementation Roadmap

### Phase 1: Core Security & Authentication (Weeks 1-4)
**Critical for launch**

```mermaid
gantt
    title Phase 1: Security & Auth
    dateFormat  YYYY-MM-DD
    
    section Backend
    OAuth integration           :crit, a1, 2026-02-01, 7d
    JWT middleware             :crit, a2, after a1, 5d
    Database setup             :crit, a3, 2026-02-01, 10d
    
    section Frontend
    Auth context               :crit, b1, after a2, 5d
    Login UI                   :crit, b2, after b1, 3d
    
    section Tray
    Device registration        :crit, c1, after a1, 7d
    Secure storage            :crit, c2, after c1, 3d
```

### Phase 2: Cloud Infrastructure (Weeks 5-8)
**Enable multi-tenant operation**

- Database migration complete
- Object storage for artifacts
- WebSocket scaling with Redis
- HTTPS/WSS enforcement
- Initial monitoring setup

### Phase 3: Production Hardening (Weeks 9-12)
**Make it bulletproof**

- Rate limiting and security headers
- Comprehensive logging
- Auto-update for tray app
- Performance optimization
- Load testing

### Phase 4: Polish & Launch Prep (Weeks 13-16)
**Ready for customers**

- Documentation complete
- Support infrastructure
- Compliance review
- Security audit
- Beta testing program

---

## Critical Dependencies

```mermaid
graph LR
    A[OAuth Integration] --> B[JWT Middleware]
    B --> C[Protected API Endpoints]
    C --> D[Frontend Auth]
    C --> E[Tray Auth]
    
    F[Database Setup] --> G[Multi-tenant Schema]
    G --> C
    
    H[Object Storage] --> I[Artifact Upload]
    I --> C
    
    J[Redis Setup] --> K[WebSocket Scaling]
    J --> L[Rate Limiting]
    J --> M[Session Management]
    
    style A fill:#ff6b6b
    style F fill:#ff6b6b
    style H fill:#ff6b6b
    style J fill:#ff6b6b
```

## Success Metrics

Track these metrics to ensure production readiness:

| Metric | Target | Status |
|--------|--------|--------|
| API uptime | > 99.9% | ⏳ Not measured |
| Average response time | < 200ms | ⏳ Not measured |
| Authentication success rate | > 99% | ⏳ Not implemented |
| WebSocket connection stability | < 1% disconnects/hr | ⏳ Not measured |
| Security vulnerabilities | 0 critical, 0 high | ⏳ Not scanned |
| Test coverage | > 80% | ⏳ Needs improvement |
| Documentation completeness | 100% API documented | ⏳ Not started |
| Average support response time | < 24 hours | ⏳ No support system |

---

## Estimated Effort

**Total estimated effort**: 12-16 weeks (3-4 months) with 2-3 full-time engineers

**Breakdown by priority**:
- 🔴 Critical (must-have): 6-8 weeks
- 🟡 High (should-have): 4-5 weeks
- 🟢 Medium (nice-to-have): 2-3 weeks

**Recommended team structure**:
- Backend engineer (authentication, database, infrastructure)
- Frontend engineer (React UI, auth integration)
- DevOps engineer (CI/CD, monitoring, deployment)
- .NET engineer (Tray app enhancements, part-time)

---

## Risk Assessment

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Security breach | 🔴 Critical | 🟡 Medium | Comprehensive security audit, penetration testing |
| Data loss | 🔴 Critical | 🟢 Low | Automated backups, disaster recovery plan |
| Scaling issues | 🟡 High | 🟡 Medium | Load testing, auto-scaling, monitoring |
| Third-party API outages | 🟡 High | 🟡 Medium | Circuit breakers, fallback mechanisms |
| Database migration failures | 🟡 High | 🟢 Low | Thorough testing, rollback plan |
| Cost overruns | 🟢 Medium | 🟡 Medium | Cost monitoring, right-sizing, alerts |

---

## Conclusion

This production readiness plan transforms Felix from a local development tool into a robust, secure, scalable SaaS platform. The priorities are:

1. **Security first**: Authentication, authorization, encryption
2. **Cloud-native**: Stateless backend, distributed architecture
3. **User experience**: Seamless device onboarding, reliable sync
4. **Operational excellence**: Monitoring, logging, incident response

Follow the phased approach to de-risk the migration and ensure each component is production-ready before moving to the next phase.

**Next immediate steps**:
1. Set up development/staging environments matching production architecture
2. Implement OAuth provider integration (GitHub OAuth is fastest to start)
3. Create database schema and migration scripts
4. Update backend to use environment-based configuration
5. Begin security audit of existing codebase

Good luck! 🚀
