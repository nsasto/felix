# S-0052: Docker Containerization and Deployment

**Phase:** 4 (Production Hardening)  
**Effort:** 8-10 hours  
**Priority:** High  
**Dependencies:** S-0051

---

## Narrative

This specification covers containerizing the backend with Docker, deploying to Railway (backend) and Vercel (frontend), and configuring production environment variables. This enables consistent deployment across environments and simplifies production operations.

---

## Acceptance Criteria

### Backend Dockerfile

- [ ] Create **app/backend/Dockerfile** with:
  - Python 3.11 base image
  - Install dependencies from requirements.txt
  - Copy application code
  - Expose port 8080
  - Run with uvicorn

### Docker Compose (Local Testing)

- [ ] Create **docker-compose.yml** for local testing:
  - Backend service
  - Environment variable configuration
  - Volume mounts for development

### Railway Deployment

- [ ] Deploy backend to Railway:
  - Connect GitHub repository
  - Configure build settings
  - Set environment variables
  - Verify deployment

### Vercel Deployment

- [ ] Deploy frontend to Vercel:
  - Connect GitHub repository
  - Configure build command
  - Set environment variables (Supabase URL, keys)
  - Verify deployment

### Production Environment Configuration

- [ ] Configure production environment variables
- [ ] Update CORS settings for production domains
- [ ] Test end-to-end production deployment

---

## Technical Notes

### Backend Dockerfile (app/backend/Dockerfile)

```dockerfile
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create runs directory
RUN mkdir -p runs

# Expose port
EXPOSE 8080

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PORT=8080

# Run application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

### Docker Compose (docker-compose.yml)

```yaml
version: "3.8"

services:
  backend:
    build:
      context: ./app/backend
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      - DATABASE_URL=${DATABASE_URL}
      - SUPABASE_URL=${SUPABASE_URL}
      - SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
      - SUPABASE_SERVICE_KEY=${SUPABASE_SERVICE_KEY}
      - SUPABASE_JWT_SECRET=${SUPABASE_JWT_SECRET}
      - AUTH_MODE=enabled
      - LOG_LEVEL=INFO
    volumes:
      - ./runs:/app/runs
    restart: unless-stopped
```

### Railway Deployment Steps

1. **Create Railway Project:**
   - Go to https://railway.app
   - Click "New Project" → "Deploy from GitHub repo"
   - Select Felix repository
   - Railway auto-detects Dockerfile

2. **Configure Build Settings:**
   - Root directory: `/`
   - Dockerfile path: `app/backend/Dockerfile`
   - Build command: (auto-detected)

3. **Set Environment Variables:**

   ```
   DATABASE_URL=<supabase-database-url>
   SUPABASE_URL=<supabase-url>
   SUPABASE_ANON_KEY=<supabase-anon-key>
   SUPABASE_SERVICE_KEY=<supabase-service-key>
   SUPABASE_JWT_SECRET=<supabase-jwt-secret>
   AUTH_MODE=enabled
   LOG_LEVEL=INFO
   PORT=8080
   ```

4. **Deploy:**
   - Railway automatically builds and deploys
   - Note assigned URL: `https://felix-backend-production.up.railway.app`

5. **Verify Health:**
   ```bash
   curl https://felix-backend-production.up.railway.app/health
   ```

### Vercel Deployment Steps

1. **Create Vercel Project:**
   - Go to https://vercel.com
   - Click "New Project" → Import from GitHub
   - Select Felix repository
   - Framework preset: Vite

2. **Configure Build Settings:**
   - Root directory: `app/frontend`
   - Build command: `npm run build`
   - Output directory: `dist`
   - Install command: `npm install`

3. **Set Environment Variables:**

   ```
   VITE_SUPABASE_URL=<supabase-url>
   VITE_SUPABASE_ANON_KEY=<supabase-anon-key>
   VITE_API_BASE_URL=https://felix-backend-production.up.railway.app
   ```

4. **Deploy:**
   - Vercel automatically builds and deploys
   - Note assigned URL: `https://felix-dashboard.vercel.app`

5. **Verify Frontend:**
   - Open `https://felix-dashboard.vercel.app` in browser
   - Sign in with test user
   - Verify dashboard loads

### Update Backend CORS Settings

```python
# app/backend/main.py

from fastapi.middleware.cors import CORSMiddleware

# Production CORS configuration
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "http://localhost:3000").split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"]
)
```

**Railway Environment Variable:**

```
ALLOWED_ORIGINS=https://felix-dashboard.vercel.app,http://localhost:3000
```

### Frontend API Base URL

Update **app/frontend/src/api/client.ts**:

```typescript
const API_BASE =
  import.meta.env.VITE_API_BASE_URL || "http://localhost:8080/api";
```

---

## Dependencies

**Depends On:**

- S-0051: Monitoring, Logging, and Health Checks

**Blocks:**

- S-0053: Production Testing and Validation

---

## Validation Criteria

### Docker Build Test

```bash
# Build Docker image
cd app/backend
docker build -t felix-backend .

# Run locally
docker run -p 8080:8080 \
  -e DATABASE_URL=<supabase-url> \
  -e SUPABASE_URL=<supabase-url> \
  -e SUPABASE_ANON_KEY=<anon-key> \
  -e SUPABASE_SERVICE_KEY=<service-key> \
  -e SUPABASE_JWT_SECRET=<jwt-secret> \
  -e AUTH_MODE=enabled \
  felix-backend

# Test health endpoint
curl http://localhost:8080/health
```

Expected: Health check returns healthy status

### Docker Compose Test

```bash
# Start with docker-compose
docker-compose up

# Test health endpoint
curl http://localhost:8080/health

# Stop
docker-compose down
```

### Railway Deployment Verification

- [ ] Backend deployed successfully
- [ ] No build errors in Railway logs
- [ ] Health endpoint accessible: `curl https://<railway-url>/health`
- [ ] API docs accessible: `https://<railway-url>/docs`
- [ ] Logs show structured JSON output
- [ ] Database connection successful

### Vercel Deployment Verification

- [ ] Frontend deployed successfully
- [ ] No build errors in Vercel logs
- [ ] Frontend loads: Open `https://<vercel-url>` in browser
- [ ] Sign in works
- [ ] Dashboard loads agents and runs
- [ ] Console streaming works
- [ ] Organization switcher works

### CORS Verification

```bash
# Test CORS from frontend domain
curl -X OPTIONS https://<railway-url>/api/agents \
  -H "Origin: https://<vercel-url>" \
  -H "Access-Control-Request-Method: GET" \
  -v
```

Expected: Response includes `Access-Control-Allow-Origin: https://<vercel-url>`

### End-to-End Production Test

1. **Sign Up:**
   - Go to `https://<vercel-url>`
   - Sign up with new email
   - Verify personal org created

2. **Register Agent:**
   - Run `felix-agent.ps1` locally with production backend URL
   - Verify agent appears in dashboard

3. **Create Run:**
   - Click "Start Run" in dashboard
   - Verify run starts
   - Verify console logs stream

4. **Multi-Tab Sync:**
   - Open dashboard in 2 tabs
   - Start run in Tab 1
   - Verify Tab 2 updates automatically

---

## Rollback Strategy

If deployment fails:

1. **Railway:** Revert to previous deployment in Railway dashboard
2. **Vercel:** Revert to previous deployment in Vercel dashboard
3. Debug issues locally with Docker
4. Re-deploy after fixing

**Backup Strategy:**

- Railway keeps deployment history (easy rollback)
- Vercel keeps deployment history (easy rollback)
- Git tags mark production releases

---

## Notes

- Railway provides free tier (500 hours/month, sufficient for development)
- Vercel provides free tier for personal projects
- Docker image size: ~300MB (Python 3.11 + dependencies)
- Backend cold start: ~2-3 seconds on Railway
- Frontend build time: ~1-2 minutes on Vercel
- Supabase free tier includes 500MB database, 2GB bandwidth
- Production environment uses AUTH_MODE=enabled (JWT validation)
- CORS must allow Vercel domain for API calls
- Railway auto-deploys on git push to main branch
- Vercel auto-deploys on git push to main branch
- Consider custom domains in future (felix.yourdomain.com)
- Monitor Railway logs for errors: Railway dashboard → Logs
- Monitor Vercel logs for build issues: Vercel dashboard → Deployments
