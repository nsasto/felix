"""
Filesystem implementation of artifact storage.

Stores artifacts on the local filesystem with metadata in .meta.json sidecar files.
Used for local development and small deployments.
"""

import json
import os
from pathlib import Path
from typing import Optional

import aiofiles
import aiofiles.os

from .base import ArtifactStorage


class FilesystemStorage(ArtifactStorage):
    """
    Filesystem-based artifact storage implementation.
    
    Stores files on the local filesystem with metadata stored in
    .meta.json sidecar files alongside each artifact.
    """
    
    def __init__(self, base_path: str = "storage/runs"):
        """
        Initialize filesystem storage.
        
        Args:
            base_path: Base directory for storing artifacts (defaults to "storage/runs")
        """
        self.base_path = Path(base_path)
        # Create base directory if it doesn't exist
        self.base_path.mkdir(parents=True, exist_ok=True)
    
    def _get_path(self, key: str) -> Path:
        """
        Get the filesystem path for a key with directory traversal prevention.
        
        Sanitizes the key to prevent directory traversal attacks by removing
        ".." components and leading slashes.
        
        Args:
            key: The storage key
            
        Returns:
            Safe filesystem path within the base directory
        """
        # Normalize and sanitize the key
        # Split into parts and filter out dangerous components
        parts = key.replace("\\", "/").split("/")
        safe_parts = [
            p for p in parts
            if p and p != ".." and not p.startswith("/")
        ]
        
        # Reconstruct the safe path
        safe_key = "/".join(safe_parts)
        
        # Return absolute path within base directory
        return self.base_path / safe_key
    
    def _get_meta_path(self, file_path: Path) -> Path:
        """
        Get the metadata sidecar path for a file.
        
        Args:
            file_path: The artifact file path
            
        Returns:
            Path to the .meta.json sidecar file
        """
        return file_path.with_suffix(file_path.suffix + ".meta.json")
    
    async def put(
        self,
        key: str,
        content: bytes,
        content_type: str,
        metadata: Optional[dict] = None
    ) -> None:
        """
        Store content at the given key.
        
        Creates subdirectories as needed and stores metadata in a .meta.json
        sidecar file.
        
        Args:
            key: The storage key (e.g., "run-id/file.txt")
            content: The binary content to store
            content_type: MIME type of the content
            metadata: Optional dictionary of metadata
        """
        file_path = self._get_path(key)
        
        # Create parent directories if needed
        await aiofiles.os.makedirs(file_path.parent, exist_ok=True)
        
        # Write the content
        async with aiofiles.open(file_path, "wb") as f:
            await f.write(content)
        
        # Write metadata sidecar
        meta_path = self._get_meta_path(file_path)
        meta_data = {
            "content_type": content_type,
            "size": len(content),
            **(metadata or {})
        }
        async with aiofiles.open(meta_path, "w", encoding="utf-8") as f:
            await f.write(json.dumps(meta_data, indent=2))
    
    async def get(self, key: str) -> bytes:
        """
        Retrieve content from the given key.
        
        Args:
            key: The storage key to retrieve
            
        Returns:
            The binary content stored at the key
            
        Raises:
            FileNotFoundError: If the key does not exist
        """
        file_path = self._get_path(key)
        
        if not file_path.exists():
            raise FileNotFoundError(f"Key not found: {key}")
        
        async with aiofiles.open(file_path, "rb") as f:
            return await f.read()
    
    async def exists(self, key: str) -> bool:
        """
        Check if a key exists in storage.
        
        Args:
            key: The storage key to check
            
        Returns:
            True if the key exists, False otherwise
        """
        file_path = self._get_path(key)
        return file_path.exists()
    
    async def delete(self, key: str) -> None:
        """
        Delete content at the given key.
        
        Also removes the .meta.json sidecar if it exists.
        
        Args:
            key: The storage key to delete
            
        Raises:
            FileNotFoundError: If the key does not exist
        """
        file_path = self._get_path(key)
        
        if not file_path.exists():
            raise FileNotFoundError(f"Key not found: {key}")
        
        # Delete the main file
        await aiofiles.os.remove(file_path)
        
        # Delete metadata sidecar if it exists
        meta_path = self._get_meta_path(file_path)
        if meta_path.exists():
            await aiofiles.os.remove(meta_path)
    
    async def list_keys(self, prefix: str = "") -> list[str]:
        """
        List all keys with the given prefix.
        
        Recursively lists all files under the prefix, excluding .meta.json
        sidecar files.
        
        Args:
            prefix: Optional prefix to filter keys (e.g., "run-id/")
            
        Returns:
            List of keys matching the prefix
        """
        search_path = self._get_path(prefix) if prefix else self.base_path
        
        if not search_path.exists():
            return []
        
        keys = []
        
        # If search_path is a file, return it (if not a .meta.json)
        if search_path.is_file():
            if not str(search_path).endswith(".meta.json"):
                rel_path = search_path.relative_to(self.base_path)
                keys.append(str(rel_path).replace("\\", "/"))
            return keys
        
        # Recursively list files
        for root, _, files in os.walk(search_path):
            for filename in files:
                # Skip .meta.json sidecar files
                if filename.endswith(".meta.json"):
                    continue
                
                file_path = Path(root) / filename
                rel_path = file_path.relative_to(self.base_path)
                keys.append(str(rel_path).replace("\\", "/"))
        
        return sorted(keys)
    
    async def get_metadata(self, key: str) -> Optional[dict]:
        """
        Retrieve metadata for the given key.
        
        Reads the .meta.json sidecar file if it exists.
        
        Args:
            key: The storage key to get metadata for
            
        Returns:
            Dictionary of metadata if available, None otherwise
        """
        file_path = self._get_path(key)
        meta_path = self._get_meta_path(file_path)
        
        if not meta_path.exists():
            return None
        
        async with aiofiles.open(meta_path, "r", encoding="utf-8") as f:
            content = await f.read()
            return json.loads(content)
