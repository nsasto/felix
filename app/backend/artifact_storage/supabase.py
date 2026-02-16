"""
Supabase implementation of artifact storage.

TODO - Supabase implementation deferred, use filesystem for now.

This module provides a stub implementation that raises NotImplementedError
for all methods. When cloud storage is needed, implement the methods using
the Supabase Storage API.
"""

from typing import Optional

from .base import ArtifactStorage


class SupabaseStorage(ArtifactStorage):
    """
    Supabase-based artifact storage implementation (stub).
    
    This is a placeholder for future cloud storage support.
    All methods raise NotImplementedError until implementation is complete.
    """
    
    def __init__(
        self,
        project_url: str,
        api_key: str,
        bucket: str = "artifacts"
    ):
        """
        Initialize Supabase storage.
        
        Args:
            project_url: Supabase project URL (e.g., "https://xxx.supabase.co")
            api_key: Supabase API key
            bucket: Storage bucket name (defaults to "artifacts")
        """
        self.project_url = project_url
        self.api_key = api_key
        self.bucket = bucket
    
    async def put(
        self,
        key: str,
        content: bytes,
        content_type: str,
        metadata: Optional[dict] = None
    ) -> None:
        """
        Store content at the given key.
        
        Raises:
            NotImplementedError: Supabase storage not yet implemented
        """
        raise NotImplementedError(
            "Supabase storage not yet implemented - use filesystem"
        )
    
    async def get(self, key: str) -> bytes:
        """
        Retrieve content from the given key.
        
        Raises:
            NotImplementedError: Supabase storage not yet implemented
        """
        raise NotImplementedError(
            "Supabase storage not yet implemented - use filesystem"
        )
    
    async def exists(self, key: str) -> bool:
        """
        Check if a key exists in storage.
        
        Raises:
            NotImplementedError: Supabase storage not yet implemented
        """
        raise NotImplementedError(
            "Supabase storage not yet implemented - use filesystem"
        )
    
    async def delete(self, key: str) -> None:
        """
        Delete content at the given key.
        
        Raises:
            NotImplementedError: Supabase storage not yet implemented
        """
        raise NotImplementedError(
            "Supabase storage not yet implemented - use filesystem"
        )
    
    async def list_keys(self, prefix: str = "") -> list[str]:
        """
        List all keys with the given prefix.
        
        Raises:
            NotImplementedError: Supabase storage not yet implemented
        """
        raise NotImplementedError(
            "Supabase storage not yet implemented - use filesystem"
        )
    
    async def get_metadata(self, key: str) -> Optional[dict]:
        """
        Retrieve metadata for the given key.
        
        Raises:
            NotImplementedError: Supabase storage not yet implemented
        """
        raise NotImplementedError(
            "Supabase storage not yet implemented - use filesystem"
        )
