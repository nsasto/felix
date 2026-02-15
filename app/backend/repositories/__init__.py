"""
Repository interfaces and implementations for database access.
"""

from .agents import (
    IAgentProfileRepository,
    IAgentRepository,
    IMachineRepository,
    PostgresAgentProfileRepository,
    PostgresAgentRepository,
    PostgresMachineRepository,
)
from .requirements import (
    IRequirementRepository,
    IRequirementContentRepository,
    IRequirementDependencyRepository,
    PostgresRequirementRepository,
    PostgresRequirementContentRepository,
    PostgresRequirementDependencyRepository,
)
from .projects import (
    IProjectRepository,
    PostgresProjectRepository,
)
from .settings import (
    ISettingsRepository,
    PostgresSettingsRepository,
)

__all__ = [
    "IAgentProfileRepository",
    "IAgentRepository",
    "IMachineRepository",
    "PostgresAgentProfileRepository",
    "PostgresAgentRepository",
    "PostgresMachineRepository",
    "IRequirementRepository",
    "IRequirementContentRepository",
    "IRequirementDependencyRepository",
    "PostgresRequirementRepository",
    "PostgresRequirementContentRepository",
    "PostgresRequirementDependencyRepository",
    "IProjectRepository",
    "PostgresProjectRepository",
    "ISettingsRepository",
    "PostgresSettingsRepository",
]
