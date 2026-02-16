"""
Abstract base class for artifact storage.

Defines the interface that all storage backends must implement.
"""

from abc import ABC, abstractmethod
from typing import Optional


class ArtifactStorage(ABC):
    """
    Abstract base class for artifact storage backends.
    
    All storage implementations must inherit from this class and implement
    all abstract methods. The interface supports basic CRUD operations
    plus listing and metadata retrieval for run artifacts.
    """
    
    @abstractmethod
    async def put(
        self,
        key: str,
        content: bytes,
        content_type: str,
        metadata: Optional[dict] = None
    ) -> None:
        """
        Store content at the given key.
        
        Args:
            key: The storage key (e.g., "run-id/file.txt")
            content: The binary content to store
            content_type: MIME type of the content (e.g., "text/plain")
            metadata: Optional dictionary of metadata to store with the file
            
        Raises:
            IOError: If the write operation fails
        """
        pass
    
    @abstractmethod
    async def get(self, key: str) -> bytes:
        """
        Retrieve content from the given key.
        
        Args:
            key: The storage key to retrieve
            
        Returns:
            The binary content stored at the key
            
        Raises:
            FileNotFoundError: If the key does not exist
            IOError: If the read operation fails
        """
        pass
    
    @abstractmethod
    async def exists(self, key: str) -> bool:
        """
        Check if a key exists in storage.
        
        Args:
            key: The storage key to check
            
        Returns:
            True if the key exists, False otherwise
        """
        pass
    
    @abstractmethod
    async def delete(self, key: str) -> None:
        """
        Delete content at the given key.
        
        Args:
            key: The storage key to delete
            
        Raises:
            FileNotFoundError: If the key does not exist
            IOError: If the delete operation fails
        """
        pass
    
    @abstractmethod
    async def list_keys(self, prefix: str = "") -> list[str]:
        """
        List all keys with the given prefix.
        
        Args:
            prefix: Optional prefix to filter keys (e.g., "run-id/")
            
        Returns:
            List of keys matching the prefix
        """
        pass
    
    @abstractmethod
    async def get_metadata(self, key: str) -> Optional[dict]:
        """
        Retrieve metadata for the given key.
        
        Args:
            key: The storage key to get metadata for
            
        Returns:
            Dictionary of metadata if available, None otherwise
        """
        pass
