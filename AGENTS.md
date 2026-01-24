# Agents - How to Operate This Repository

This file tells Felix **how to run the system**.

## Install Dependencies

### Backend

```bash
cd app/backend
python -m pip install -r requirements.txt
```

### Frontend

```bash
cd app/frontend
npm install
```

## Run Tests

```bash
# To be added when tests are implemented
```

## Build the Project

```bash
# Backend builds are not needed (Python)
# Frontend build:
cd app/frontend
npm run build
```

## Start the Application

### Development Mode

**Backend (FastAPI):**

```bash
cd app/backend
python main.py
# Runs on http://localhost:8080
# API docs at http://localhost:8080/docs
```

**Frontend (React):**

```bash
cd app/frontend
npm run dev
# Runs on http://localhost:3000
```

### Production Mode

```bash
# To be added when production setup is ready
```

## Repository Conventions

- Keep this file operational only
- No planning or status updates
- No long explanations
- If it wouldn't help a new engineer run the repo, it doesn't belong here
