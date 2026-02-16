"""
Storage factory for creating artifact storage instances.

Provides configuration-driven storage backend selection with singleton
caching for efficient resource usage.
"""

import os
from typing import Optional

from .base import ArtifactStorage
from .filesystem import FilesystemStorage
from .supabase import SupabaseStorage


# Module-level cache for singleton storage instance
_storage_instance: Optional[ArtifactStorage] = None


def get_storage(config: Optional[dict] = None) -> ArtifactStorage:
    """
    Create a storage instance based on configuration.
    
    Reads STORAGE_TYPE from environment if not specified in config.
    Supported storage types:
    - "filesystem" (default): Local filesystem storage
    - "supabase": Supabase cloud storage (stub)
    
    Args:
        config: Optional configuration dictionary with keys:
            - storage_type: "filesystem" or "supabase"
            - base_path: Base path for filesystem storage
            - project_url: Supabase project URL
            - api_key: Supabase API key
            - bucket: Supabase bucket name
            
    Returns:
        Configured ArtifactStorage instance
        
    Raises:
        ValueError: If storage_type is not recognized
    """
    config = config or {}
    
    # Get storage type from config or environment (default to "filesystem")
    storage_type = config.get(
        "storage_type",
        os.environ.get("STORAGE_TYPE", "filesystem")
    )
    
    if storage_type == "filesystem":
        base_path = config.get(
            "base_path",
            os.environ.get("STORAGE_BASE_PATH", "storage/runs")
        )
        return FilesystemStorage(base_path=base_path)
    
    elif storage_type == "supabase":
        project_url = config.get(
            "project_url",
            os.environ.get("SUPABASE_URL", "")
        )
        api_key = config.get(
            "api_key",
            os.environ.get("SUPABASE_KEY", "")
        )
        bucket = config.get(
            "bucket",
            os.environ.get("SUPABASE_BUCKET", "artifacts")
        )
        return SupabaseStorage(
            project_url=project_url,
            api_key=api_key,
            bucket=bucket
        )
    
    else:
        raise ValueError(f"Unknown storage type: {storage_type}")


def get_artifact_storage() -> ArtifactStorage:
    """
    Get the singleton artifact storage instance.
    
    Creates a new instance on first call and caches it for subsequent calls.
    This prevents multiple storage instances being created throughout the
    application lifecycle.
    
    Returns:
        Singleton ArtifactStorage instance
    """
    global _storage_instance
    
    if _storage_instance is None:
        _storage_instance = get_storage()
    
    return _storage_instance


def reset_storage_singleton() -> None:
    """
    Reset the singleton storage instance.
    
    Useful for testing to ensure a fresh storage instance is created.
    """
    global _storage_instance
    _storage_instance = None
