"""
Felix - Artifact Templates and Scaffolding CLI

A command-line tool for initializing and managing Felix-enabled projects.

Commands:
  - felix init: Initialize Felix in an existing project
  - felix spec create <name>: Create a new specification
  - felix validate: Validate Felix project health
"""

__version__ = "0.1.0"

from . import cli

__all__ = ["cli", "__version__"]
