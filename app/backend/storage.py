"""
Felix Backend - Project Storage
Manages ~/.felix/projects.json for registered projects.
"""
import json
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Optional, List
from models import Project, ProjectsStore, ProjectDetails


def get_felix_home() -> Path:
    """Get ~/.felix directory, creating if needed"""
    felix_home = Path.home() / ".felix"
    felix_home.mkdir(exist_ok=True)
    return felix_home


def get_projects_file() -> Path:
    """Get path to projects.json"""
    return get_felix_home() / "projects.json"


def generate_project_id(path: str) -> str:
    """Generate deterministic ID from path"""
    # Use MD5 hash of normalized path for short, consistent ID
    normalized = str(Path(path).resolve()).lower()
    return hashlib.md5(normalized.encode()).hexdigest()[:12]


def load_projects() -> ProjectsStore:
    """Load projects from storage"""
    projects_file = get_projects_file()
    if projects_file.exists():
        try:
            data = json.loads(projects_file.read_text())
            return ProjectsStore(**data)
        except (json.JSONDecodeError, ValueError):
            # Corrupted file, return empty
            return ProjectsStore()
    return ProjectsStore()


def save_projects(store: ProjectsStore):
    """Save projects to storage"""
    store.updated_at = datetime.now()
    projects_file = get_projects_file()
    projects_file.write_text(store.model_dump_json(indent=2))


def register_project(path: str, name: Optional[str] = None) -> Project:
    """Register a new project or update existing"""
    project_path = Path(path).resolve()
    
    if not project_path.exists():
        raise ValueError(f"Project path does not exist: {path}")
    
    if not project_path.is_dir():
        raise ValueError(f"Project path is not a directory: {path}")
    
    # Check for Felix structure
    felix_dir = project_path / "felix"
    specs_dir = project_path / "specs"
    
    if not felix_dir.exists() or not specs_dir.exists():
        raise ValueError(
            f"Invalid Felix project structure. "
            f"Missing: {[d for d in ['felix/', 'specs/'] if not (project_path / d.rstrip('/')).exists()]}"
        )
    
    project_id = generate_project_id(str(project_path))
    project_name = name or project_path.name
    
    store = load_projects()
    
    # Check if already registered
    existing_idx = None
    for i, p in enumerate(store.projects):
        if p.id == project_id:
            existing_idx = i
            break
    
    project = Project(
        id=project_id,
        path=str(project_path),
        name=project_name,
        registered_at=datetime.now()
    )
    
    if existing_idx is not None:
        store.projects[existing_idx] = project
    else:
        store.projects.append(project)
    
    save_projects(store)
    return project


def get_all_projects() -> List[Project]:
    """Get all registered projects"""
    return load_projects().projects


def get_project_by_id(project_id: str) -> Optional[Project]:
    """Get a project by ID"""
    store = load_projects()
    for project in store.projects:
        if project.id == project_id:
            return project
    return None


def get_project_details(project_id: str) -> Optional[ProjectDetails]:
    """Get project with runtime details"""
    project = get_project_by_id(project_id)
    if not project:
        return None
    
    project_path = Path(project.path)
    
    # Check for Felix artifacts
    specs_dir = project_path / "specs"
    
    spec_count = 0
    if specs_dir.exists():
        spec_count = len(list(specs_dir.glob("*.md")))
    
    # S-0032: File operations removed - no longer read state.json or requirements.json
    # has_requirements and status will be database-driven in Phase 0
    
    return ProjectDetails(
        id=project.id,
        path=project.path,
        name=project.name,
        registered_at=project.registered_at,
        has_specs=specs_dir.exists(),
        has_requirements=False,  # Stubbed: will be database-driven
        spec_count=spec_count,
        status=None  # Stubbed: will be database-driven
    )


def unregister_project(project_id: str) -> bool:
    """Remove a project from registry"""
    store = load_projects()
    original_count = len(store.projects)
    store.projects = [p for p in store.projects if p.id != project_id]
    
    if len(store.projects) < original_count:
        save_projects(store)
        return True
    return False


def update_project(project_id: str, name: Optional[str] = None, path: Optional[str] = None) -> Optional[Project]:
    """Update a project's metadata"""
    store = load_projects()
    
    for i, project in enumerate(store.projects):
        if project.id == project_id:
            new_path = project.path
            new_id = project.id
            
            # If path is being updated, validate it
            if path is not None and path.strip():
                project_path = Path(path).resolve()
                
                if not project_path.exists():
                    raise ValueError(f"Project path does not exist: {path}")
                
                if not project_path.is_dir():
                    raise ValueError(f"Project path is not a directory: {path}")
                
                # Check for Felix structure
                felix_dir = project_path / "felix"
                specs_dir = project_path / "specs"
                
                if not felix_dir.exists() or not specs_dir.exists():
                    raise ValueError(
                        f"Invalid Felix project structure. "
                        f"Missing: {[d for d in ['felix/', 'specs/'] if not (project_path / d.rstrip('/')).exists()]}"
                    )
                
                new_path = str(project_path)
                new_id = generate_project_id(new_path)
                
                # Check if new path is already registered by another project
                for p in store.projects:
                    if p.id == new_id and p.id != project_id:
                        raise ValueError(f"Path is already registered as another project: {path}")
            
            # Update name if provided
            new_name = project.name
            if name is not None:
                new_name = name if name.strip() else None
            
            store.projects[i] = Project(
                id=new_id,
                path=new_path,
                name=new_name,
                registered_at=project.registered_at
            )
            save_projects(store)
            return store.projects[i]
    
    return None
