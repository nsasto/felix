"""
Tests for the Storage Abstraction Layer (S-0059)

Tests for:
- base.py - ArtifactStorage abstract base class
- filesystem.py - FilesystemStorage implementation
- supabase.py - SupabaseStorage stub
- factory.py - Storage factory and singleton
"""
import pytest
from pathlib import Path
import sys
import os
import json

# Ensure imports work from tests directory
sys.path.insert(0, str(Path(__file__).parent.parent))

from artifact_storage.base import ArtifactStorage
from artifact_storage.filesystem import FilesystemStorage
from artifact_storage.supabase import SupabaseStorage
from artifact_storage.factory import get_storage, get_artifact_storage, reset_storage_singleton


@pytest.fixture
def temp_storage(tmp_path):
    """Create a FilesystemStorage instance using a temporary directory."""
    storage = FilesystemStorage(base_path=str(tmp_path))
    return storage


@pytest.fixture(autouse=True)
def reset_singleton():
    """Reset the singleton storage instance before each test."""
    reset_storage_singleton()
    yield
    reset_storage_singleton()


class TestFilesystemStorage:
    """Tests for FilesystemStorage implementation"""

    @pytest.mark.asyncio
    async def test_put_and_get(self, temp_storage):
        """Upload content and download it back, verify match"""
        key = "test-run/file.txt"
        content = b"Hello, World!"
        content_type = "text/plain"
        
        await temp_storage.put(key, content, content_type)
        result = await temp_storage.get(key)
        
        assert result == content

    @pytest.mark.asyncio
    async def test_put_creates_subdirectories(self, temp_storage):
        """Put creates nested subdirectories as needed"""
        key = "level1/level2/level3/file.txt"
        content = b"Nested content"
        
        await temp_storage.put(key, content, "text/plain")
        result = await temp_storage.get(key)
        
        assert result == content

    @pytest.mark.asyncio
    async def test_put_writes_metadata_sidecar(self, temp_storage):
        """Put writes .meta.json sidecar with content_type and metadata"""
        key = "test-run/data.json"
        content = b'{"key": "value"}'
        content_type = "application/json"
        metadata = {"custom_field": "custom_value"}
        
        await temp_storage.put(key, content, content_type, metadata)
        
        # Verify metadata sidecar exists and contains expected data
        meta = await temp_storage.get_metadata(key)
        assert meta is not None
        assert meta["content_type"] == content_type
        assert meta["size"] == len(content)
        assert meta["custom_field"] == "custom_value"

    @pytest.mark.asyncio
    async def test_exists(self, temp_storage):
        """Exists returns True for existing keys, False otherwise"""
        key = "test-run/exists.txt"
        
        # Before put
        assert await temp_storage.exists(key) is False
        
        # After put
        await temp_storage.put(key, b"content", "text/plain")
        assert await temp_storage.exists(key) is True

    @pytest.mark.asyncio
    async def test_list_keys(self, temp_storage):
        """List keys returns all files under prefix, excluding .meta.json"""
        # Create multiple files
        await temp_storage.put("run1/file1.txt", b"1", "text/plain")
        await temp_storage.put("run1/file2.txt", b"2", "text/plain")
        await temp_storage.put("run2/file1.txt", b"3", "text/plain")
        
        # List all keys
        all_keys = await temp_storage.list_keys()
        assert len(all_keys) == 3
        assert "run1/file1.txt" in all_keys
        assert "run1/file2.txt" in all_keys
        assert "run2/file1.txt" in all_keys
        
        # List with prefix
        run1_keys = await temp_storage.list_keys("run1")
        assert len(run1_keys) == 2
        assert "run1/file1.txt" in run1_keys
        assert "run1/file2.txt" in run1_keys

    @pytest.mark.asyncio
    async def test_list_keys_excludes_meta_json(self, temp_storage):
        """List keys does not include .meta.json sidecar files"""
        await temp_storage.put("run1/file.txt", b"content", "text/plain")
        
        keys = await temp_storage.list_keys()
        
        # Should only contain the main file, not the .meta.json
        assert len(keys) == 1
        assert "run1/file.txt" in keys
        assert not any(".meta.json" in k for k in keys)

    @pytest.mark.asyncio
    async def test_delete(self, temp_storage):
        """Delete removes file and metadata sidecar"""
        key = "test-run/to-delete.txt"
        
        # Create file
        await temp_storage.put(key, b"delete me", "text/plain")
        assert await temp_storage.exists(key) is True
        
        # Delete file
        await temp_storage.delete(key)
        assert await temp_storage.exists(key) is False
        
        # Metadata sidecar should also be gone
        meta = await temp_storage.get_metadata(key)
        assert meta is None

    @pytest.mark.asyncio
    async def test_get_metadata(self, temp_storage):
        """Get metadata returns dictionary from .meta.json"""
        key = "test-run/with-meta.txt"
        metadata = {"author": "test", "version": "1.0"}
        
        await temp_storage.put(key, b"content", "text/plain", metadata)
        
        result = await temp_storage.get_metadata(key)
        
        assert result is not None
        assert result["content_type"] == "text/plain"
        assert result["author"] == "test"
        assert result["version"] == "1.0"

    @pytest.mark.asyncio
    async def test_get_metadata_returns_none_for_missing(self, temp_storage):
        """Get metadata returns None when .meta.json doesn't exist"""
        # File doesn't exist
        meta = await temp_storage.get_metadata("nonexistent/file.txt")
        assert meta is None

    @pytest.mark.asyncio
    async def test_directory_traversal_prevention(self, temp_storage):
        """Directory traversal attempts are sanitized"""
        # Attempt directory traversal
        key = "../../../etc/passwd"
        content = b"malicious content"
        
        await temp_storage.put(key, content, "text/plain")
        
        # The file should be created within base_path, not outside
        # The key should be sanitized to "etc/passwd"
        result = await temp_storage.get("etc/passwd")
        assert result == content
        
        # Original traversal path should also work (gets sanitized)
        result2 = await temp_storage.get(key)
        assert result2 == content

    @pytest.mark.asyncio
    async def test_directory_traversal_with_backslashes(self, temp_storage):
        """Directory traversal with backslashes is sanitized"""
        key = "..\\..\\etc\\passwd"
        content = b"test content"
        
        await temp_storage.put(key, content, "text/plain")
        
        # Should be sanitized
        result = await temp_storage.get("etc/passwd")
        assert result == content

    @pytest.mark.asyncio
    async def test_get_nonexistent_raises(self, temp_storage):
        """Get raises FileNotFoundError for nonexistent keys"""
        with pytest.raises(FileNotFoundError):
            await temp_storage.get("does/not/exist.txt")

    @pytest.mark.asyncio
    async def test_delete_nonexistent_raises(self, temp_storage):
        """Delete raises FileNotFoundError for nonexistent keys"""
        with pytest.raises(FileNotFoundError):
            await temp_storage.delete("does/not/exist.txt")

    def test_constructor_creates_base_directory(self, tmp_path):
        """Constructor creates base directory if it doesn't exist"""
        base_path = tmp_path / "new" / "directory"
        assert not base_path.exists()
        
        FilesystemStorage(base_path=str(base_path))
        
        assert base_path.exists()


class TestSupabaseStorage:
    """Tests for SupabaseStorage stub"""

    def test_constructor_accepts_parameters(self):
        """Constructor accepts project_url, api_key, and bucket parameters"""
        storage = SupabaseStorage(
            project_url="https://test.supabase.co",
            api_key="xxx",
            bucket="test-bucket"
        )
        
        assert storage.project_url == "https://test.supabase.co"
        assert storage.api_key == "xxx"
        assert storage.bucket == "test-bucket"

    def test_constructor_has_default_bucket(self):
        """Constructor uses 'artifacts' as default bucket"""
        storage = SupabaseStorage(
            project_url="https://test.supabase.co",
            api_key="xxx"
        )
        
        assert storage.bucket == "artifacts"

    @pytest.mark.asyncio
    async def test_put_raises_not_implemented(self):
        """Put raises NotImplementedError"""
        storage = SupabaseStorage(
            project_url="https://test.supabase.co",
            api_key="xxx"
        )
        
        with pytest.raises(NotImplementedError) as exc_info:
            await storage.put("key", b"content", "text/plain")
        
        assert "Supabase storage not yet implemented" in str(exc_info.value)

    @pytest.mark.asyncio
    async def test_get_raises_not_implemented(self):
        """Get raises NotImplementedError"""
        storage = SupabaseStorage(
            project_url="https://test.supabase.co",
            api_key="xxx"
        )
        
        with pytest.raises(NotImplementedError) as exc_info:
            await storage.get("key")
        
        assert "Supabase storage not yet implemented" in str(exc_info.value)

    @pytest.mark.asyncio
    async def test_exists_raises_not_implemented(self):
        """Exists raises NotImplementedError"""
        storage = SupabaseStorage(
            project_url="https://test.supabase.co",
            api_key="xxx"
        )
        
        with pytest.raises(NotImplementedError) as exc_info:
            await storage.exists("key")
        
        assert "Supabase storage not yet implemented" in str(exc_info.value)

    @pytest.mark.asyncio
    async def test_delete_raises_not_implemented(self):
        """Delete raises NotImplementedError"""
        storage = SupabaseStorage(
            project_url="https://test.supabase.co",
            api_key="xxx"
        )
        
        with pytest.raises(NotImplementedError) as exc_info:
            await storage.delete("key")
        
        assert "Supabase storage not yet implemented" in str(exc_info.value)

    @pytest.mark.asyncio
    async def test_list_keys_raises_not_implemented(self):
        """List keys raises NotImplementedError"""
        storage = SupabaseStorage(
            project_url="https://test.supabase.co",
            api_key="xxx"
        )
        
        with pytest.raises(NotImplementedError) as exc_info:
            await storage.list_keys()
        
        assert "Supabase storage not yet implemented" in str(exc_info.value)

    @pytest.mark.asyncio
    async def test_get_metadata_raises_not_implemented(self):
        """Get metadata raises NotImplementedError"""
        storage = SupabaseStorage(
            project_url="https://test.supabase.co",
            api_key="xxx"
        )
        
        with pytest.raises(NotImplementedError) as exc_info:
            await storage.get_metadata("key")
        
        assert "Supabase storage not yet implemented" in str(exc_info.value)


class TestStorageFactory:
    """Tests for storage factory"""

    def test_factory_default_filesystem(self, tmp_path, monkeypatch):
        """Factory returns FilesystemStorage by default"""
        # Ensure STORAGE_TYPE is not set
        monkeypatch.delenv("STORAGE_TYPE", raising=False)
        monkeypatch.setenv("STORAGE_BASE_PATH", str(tmp_path))
        
        storage = get_storage()
        
        assert isinstance(storage, FilesystemStorage)

    def test_factory_explicit_filesystem(self, tmp_path):
        """Factory returns FilesystemStorage when type='filesystem'"""
        storage = get_storage({
            "storage_type": "filesystem",
            "base_path": str(tmp_path)
        })
        
        assert isinstance(storage, FilesystemStorage)

    def test_factory_supabase_type(self):
        """Factory returns SupabaseStorage when type='supabase'"""
        storage = get_storage({
            "storage_type": "supabase",
            "project_url": "https://test.supabase.co",
            "api_key": "xxx"
        })
        
        assert isinstance(storage, SupabaseStorage)

    def test_factory_invalid_type_raises(self):
        """Factory raises ValueError for unknown storage types"""
        with pytest.raises(ValueError) as exc_info:
            get_storage({"storage_type": "unknown"})
        
        assert "Unknown storage type" in str(exc_info.value)

    def test_factory_reads_env_storage_type(self, tmp_path, monkeypatch):
        """Factory reads STORAGE_TYPE from environment"""
        monkeypatch.setenv("STORAGE_TYPE", "filesystem")
        monkeypatch.setenv("STORAGE_BASE_PATH", str(tmp_path))
        
        storage = get_storage()
        
        assert isinstance(storage, FilesystemStorage)

    def test_singleton_returns_same_instance(self, tmp_path, monkeypatch):
        """get_artifact_storage returns the same instance on repeated calls"""
        monkeypatch.delenv("STORAGE_TYPE", raising=False)
        monkeypatch.setenv("STORAGE_BASE_PATH", str(tmp_path))
        
        storage1 = get_artifact_storage()
        storage2 = get_artifact_storage()
        
        assert storage1 is storage2

    def test_singleton_reset(self, tmp_path, monkeypatch):
        """reset_storage_singleton clears the cached instance"""
        monkeypatch.delenv("STORAGE_TYPE", raising=False)
        monkeypatch.setenv("STORAGE_BASE_PATH", str(tmp_path))
        
        storage1 = get_artifact_storage()
        reset_storage_singleton()
        storage2 = get_artifact_storage()
        
        # Should be different instances after reset
        assert storage1 is not storage2


class TestArtifactStorageABC:
    """Tests for ArtifactStorage abstract base class"""

    def test_cannot_instantiate_abc(self):
        """Cannot directly instantiate ArtifactStorage"""
        with pytest.raises(TypeError):
            ArtifactStorage()

    def test_filesystemstorage_is_subclass(self):
        """FilesystemStorage is a subclass of ArtifactStorage"""
        assert issubclass(FilesystemStorage, ArtifactStorage)

    def test_supabasestorage_is_subclass(self):
        """SupabaseStorage is a subclass of ArtifactStorage"""
        assert issubclass(SupabaseStorage, ArtifactStorage)
