"""
Storage abstraction layer for artifact storage.

This module provides an abstract interface for storing run artifacts,
with implementations for filesystem (local development) and cloud storage
(Supabase for production).

Usage:
    from artifact_storage import get_artifact_storage, ArtifactStorage
    
    storage = get_artifact_storage()
    await storage.put("run-id/file.txt", b"content", "text/plain")
    content = await storage.get("run-id/file.txt")
"""

from .base import ArtifactStorage
from .filesystem import FilesystemStorage
from .supabase import SupabaseStorage
from .factory import get_storage, get_artifact_storage

__all__ = [
    "ArtifactStorage",
    "FilesystemStorage",
    "SupabaseStorage",
    "get_storage",
    "get_artifact_storage",
]
