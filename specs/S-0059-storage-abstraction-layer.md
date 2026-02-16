# S-0059: Run Artifact Sync - Storage Abstraction Layer

**Priority:** High  
**Tags:** Backend, Storage, Infrastructure

## Description

As a Felix developer, I need an abstraction layer for artifact storage so that the system can store run artifacts on local filesystem initially and migrate to cloud storage (Supabase) in the future without changing backend code.

## Dependencies

- S-0057 (Run Artifact Sync Preparation) - requires backend config with STORAGE_TYPE
- S-0036 (Backend Database Integration Layer) - requires database connection setup

## Acceptance Criteria

### Storage Module Structure

- [ ] Module directory `app/backend/storage/` created
- [ ] `app/backend/storage/__init__.py` exists with module docstring
- [ ] Base interface file `app/backend/storage/base.py` exists
- [ ] Filesystem implementation `app/backend/storage/filesystem.py` exists
- [ ] Supabase stub `app/backend/storage/supabase.py` exists
- [ ] Factory module `app/backend/storage/factory.py` exists

### Base Storage Interface

- [ ] `ArtifactStorage` abstract base class defined
- [ ] Method `put(key, content, content_type, metadata)` declared async
- [ ] Method `get(key)` declared async returning bytes
- [ ] Method `exists(key)` declared async returning bool
- [ ] Method `delete(key)` declared async
- [ ] Method `list_keys(prefix)` declared async returning list
- [ ] Method `get_metadata(key)` declared async returning optional dict

### Filesystem Storage Implementation

- [ ] `FilesystemStorage` class inherits from ArtifactStorage
- [ ] Constructor accepts base_path parameter (defaults to storage/runs)
- [ ] Constructor creates base directory if not exists
- [ ] `_get_path()` helper prevents directory traversal attacks
- [ ] `put()` creates subdirectories as needed
- [ ] `put()` writes content and metadata sidecar (.meta.json)
- [ ] `get()` reads file content asynchronously
- [ ] `get()` raises FileNotFoundError if key doesn't exist
- [ ] `exists()` checks file existence
- [ ] `delete()` removes file and metadata sidecar
- [ ] `list_keys()` recursively lists files under prefix
- [ ] `list_keys()` excludes .meta.json files from results
- [ ] `get_metadata()` reads and parses .meta.json file

### Supabase Storage Stub

- [ ] `SupabaseStorage` class inherits from ArtifactStorage
- [ ] Constructor accepts project_url, api_key, bucket parameters
- [ ] All methods raise NotImplementedError with helpful message
- [ ] Docstring indicates "TODO - use filesystem for now"

### Storage Factory

- [ ] `get_storage()` function reads STORAGE_TYPE from environment
- [ ] Factory returns FilesystemStorage for type='filesystem'
- [ ] Factory returns SupabaseStorage for type='supabase' (will error until implemented)
- [ ] Factory raises ValueError for unknown storage types
- [ ] `get_artifact_storage()` singleton function caches storage instance
- [ ] Singleton prevents multiple storage instances from being created

### Storage Tests

- [ ] Test file `app/backend/tests/test_storage.py` exists
- [ ] Fixture `temp_storage` creates temporary filesystem storage
- [ ] Test `test_put_and_get` verifies basic upload/download
- [ ] Test `test_list_keys` verifies prefix filtering
- [ ] Test `test_delete` verifies file deletion
- [ ] Test `test_get_metadata` verifies metadata sidecar
- [ ] Test `test_directory_traversal_prevention` verifies security
- [ ] All tests pass with pytest

## Validation Criteria

- [ ] `python -c "from app.backend.storage.base import ArtifactStorage; print('OK')"` completes without errors
- [ ] `python -c "from app.backend.storage.filesystem import FilesystemStorage; print('OK')"` imports successfully
- [ ] `python -c "from app.backend.storage.factory import get_artifact_storage; s = get_artifact_storage(); print(type(s).__name__)"` outputs FilesystemStorage
- [ ] `cd app/backend && pytest tests/test_storage.py -v` shows all tests passed
- [ ] Manual test - create test file with storage.put(), verify file exists in storage/runs/

## Technical Notes

**Architecture:** Abstract base class pattern allows swapping storage backends via configuration. Filesystem storage uses metadata sidecars (.meta.json) to track content type and custom metadata without requiring a separate database table.

**Security:** The `_get_path()` helper strips ".." and leading slashes to prevent directory traversal attacks. All user-provided keys are sanitized before filesystem access.

**Async Design:** All storage methods are async to match FastAPI's async patterns and allow future optimization with concurrent operations.

**Don't assume not implemented:** Check if app/backend/storage/ directory already exists from earlier work. May have partial implementations or different interface designs.

## Non-Goals

- Supabase storage implementation (deferred - stub only for now)
- S3 or other cloud storage providers
- Compression or encryption of stored artifacts
- Automatic cleanup of old artifacts
- CDN integration for artifact delivery
