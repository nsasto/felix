"""
Project helpers for validation and path lookup.
"""

from __future__ import annotations

from pathlib import Path
from typing import Optional, Dict, Any

from databases import Database

from repositories.projects import PostgresProjectRepository


def normalize_project_path(path: str) -> Path:
    return Path(path).resolve()


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
        raise ValueError(
            "Invalid Felix project structure. Missing: "
            f"{missing}"
        )


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
