"""
Project helpers for validation and path lookup.
"""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Optional, Dict, Any

from databases import Database

from repositories.projects import PostgresProjectRepository


def normalize_project_path(path: str) -> Path:
    return Path(path).resolve()


def validate_git_repo(git_repo: str) -> None:
    """
    Validate that a git repository URL is accessible.

    Args:
        git_repo: Git repository URL (https://, git://, or ssh format)

    Raises:
        ValueError: If the URL format is invalid or repo is not accessible
    """
    if not git_repo or not git_repo.strip():
        return  # Allow empty/None values

    git_repo = git_repo.strip()

    # Basic URL format validation
    valid_prefixes = ("https://", "git@", "git://", "ssh://", "http://")
    if not any(git_repo.startswith(prefix) for prefix in valid_prefixes):
        raise ValueError(
            "Invalid git repository URL. Must start with https://, git@, git://, ssh://, or http://"
        )

    # Check if git is available
    try:
        result = subprocess.run(
            ["git", "--version"], capture_output=True, text=True, timeout=5
        )
        if result.returncode != 0:
            raise ValueError("Git is not installed or not available")
    except (subprocess.TimeoutExpired, FileNotFoundError):
        raise ValueError("Git is not installed or not available on this system")

    # Validate repository is accessible with git ls-remote
    try:
        result = subprocess.run(
            ["git", "ls-remote", "--heads", git_repo],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            error_msg = result.stderr.strip() if result.stderr else "Unknown error"
            raise ValueError(f"Cannot access git repository: {error_msg}")
    except subprocess.TimeoutExpired:
        raise ValueError("Git repository validation timed out. Please check the URL.")
    except Exception as e:
        raise ValueError(f"Failed to validate git repository: {str(e)}")


def validate_project_structure(project_path: Path) -> None:
    if not project_path.exists():
        raise ValueError(f"Project path does not exist: {project_path}")

    if not project_path.is_dir():
        raise ValueError(f"Project path is not a directory: {project_path}")

    felix_dir = project_path / ".felix"
    specs_dir = project_path / "specs"
    missing = []
    if not felix_dir.exists():
        missing.append(".felix/")
    if not specs_dir.exists():
        missing.append("specs/")
    if missing:
        raise ValueError("Invalid Felix project structure. Missing: " f"{missing}")


async def fetch_project_row(
    db: Database,
    project_id: str,
    org_id: Optional[str] = None,
) -> Optional[Dict[str, Any]]:
    repo = PostgresProjectRepository(db)
    if org_id:
        return await repo.get_by_id(org_id, project_id)
    return await repo.get_by_id_any(project_id)


def ensure_project_path_exists(path: str) -> Path:
    project_path = Path(path)
    if not project_path.exists():
        raise FileNotFoundError(f"Project directory no longer exists: {path}")
    return project_path


async def get_project_path(
    db: Database,
    project_id: str,
    org_id: Optional[str] = None,
) -> Path:
    project = await fetch_project_row(db, project_id, org_id)
    if not project:
        raise LookupError(f"Project not found: {project_id}")
    project_path = project.get("path")
    if not project_path:
        raise FileNotFoundError(f"Project path not set: {project_id}")
    return ensure_project_path_exists(project_path)
