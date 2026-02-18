"""
Git URL validation for project identity.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Optional, Dict, Any

from databases import Database

from repositories.projects import PostgresProjectRepository


def normalize_git_url(git_url: str) -> str:
    """
    Normalize a git URL for comparison.

    - Converts SSH URLs to HTTPS format
    - Removes .git suffix
    - Removes trailing slashes
    - Lowercases domain and path

    Args:
        git_url: Git repository URL

    Returns:
        Normalized git URL

    Example:
        >>> normalize_git_url("git@github.com:owner/repo.git")
        "https://github.com/owner/repo"
    """
    git_url = git_url.strip().rstrip("/")

    # Remove .git suffix if present
    if git_url.endswith(".git"):
        git_url = git_url[:-4]

    # Convert SSH format (git@github.com:owner/repo) to HTTPS
    ssh_match = re.match(r"git@([^:]+):(.+)", git_url)
    if ssh_match:
        domain, path = ssh_match.groups()
        git_url = f"https://{domain}/{path}"

    # Remove protocol for comparison (case insensitive domain)
    match = re.match(r"(https?|git|ssh)://([^/]+)/(.+)", git_url, re.IGNORECASE)
    if match:
        _, domain, path = match.groups()
        git_url = f"https://{domain.lower()}/{path}"

    return git_url.rstrip("/")


def validate_git_url(git_url: str) -> None:
    """
    Validate that a git repository URL has correct format.

    Args:
        git_url: Git repository URL (https://, git://, or ssh format)

    Raises:
        ValueError: If the URL format is invalid
    """
    if not git_url or not git_url.strip():
        raise ValueError("Git URL is required")

    git_url = git_url.strip()

    # Basic URL format validation
    valid_prefixes = ("https://", "git@", "git://", "ssh://", "http://")
    if not any(git_url.startswith(prefix) for prefix in valid_prefixes):
        raise ValueError(
            "Invalid git repository URL. Must start with https://, git@, git://, ssh://, or http://"
        )

    # Ensure it looks like a valid git URL (has domain and path)
    if git_url.startswith("git@"):
        if ":" not in git_url:
            raise ValueError("SSH git URL must contain ':' separator (git@host:path)")
    else:
        if "/" not in git_url.split("://", 1)[1]:
            raise ValueError("Git URL must contain repository path")


async def get_project_path(
    db: Database,
    project_id: str,
    org_id: Optional[str] = None,
) -> Path:
    """
    Get filesystem path for a project (development mode only).

    In production, projects don't need server-side filesystem access.
    This function exists for local development where backend and projects
    are on the same machine.

    Derives path from project name: C:/dev/{project-name-slug}
    """
    repo = PostgresProjectRepository(db)
    if org_id:
        project = await repo.get_by_id(org_id, project_id)
    else:
        project = await repo.get_by_id_any(project_id)

    if not project:
        raise LookupError(f"Project not found: {project_id}")

    # Derive filesystem path from project name (dev convention)
    project_name = project.get("name", "").lower().replace(" ", "-").replace("_", "-")
    project_path = Path(f"C:/dev/{project_name}")

    if not project_path.exists():
        raise FileNotFoundError(
            f"Project directory not found: {project_path}. "
            f"This endpoint requires server-side filesystem access (development mode only)."
        )

    return project_path
