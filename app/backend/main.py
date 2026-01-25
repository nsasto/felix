"""
Felix Backend - FastAPI Server
Provides HTTP API and WebSocket for observing and controlling Felix agents.
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from routers import projects, files, runs

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    print("Felix Backend starting...")
    yield
    # Shutdown
    print("Felix Backend shutting down...")
    
    # Clean up any running agent processes
    running_agents = runs.get_running_agents()
    if running_agents:
        print(f"Terminating {len(running_agents)} running agent(s)...")
        import os
        import signal
        for project_id, info in running_agents.items():
            try:
                os.kill(info.pid, signal.SIGTERM)
                print(f"  Terminated agent for project {project_id} (PID: {info.pid})")
            except (OSError, ProcessLookupError):
                pass  # Process already dead

app = FastAPI(
    title="Felix Backend",
    description="API for Felix - Ralph-style autonomous software delivery",
    version="0.1.0",
    lifespan=lifespan
)

# CORS configuration for frontend (React on port 3000)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(projects.router)
app.include_router(files.router)
app.include_router(runs.router)

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "felix-backend",
        "version": "0.1.0"
    }

@app.get("/")
async def root():
    """Root endpoint with basic info"""
    return {
        "name": "Felix Backend",
        "description": "Ralph-style autonomous software delivery system",
        "docs": "/docs",
        "health": "/health"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8080,
        reload=True,
        log_level="info"
    )
