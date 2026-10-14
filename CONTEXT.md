# Felix Work Model

This context defines the product concepts Felix uses to organize human-defined outcomes and agent-executed work.

## Work hierarchy

**Epic**:
A visual grouping of related features that share a broader product direction or outcome. An epic is for organization and progress views.
_Avoid_: Initiative, project (unless referring to a repository or Felix Cloud project)

**Feature**:
A product capability or outcome, defined through one or more specs. A feature can span multiple deliverables and groups related requirements.
_Avoid_: User story (as a required format)

**Spec**:
A human-defined requirement that describes intended behavior or an outcome, its context, constraints, and acceptance criteria. A feature may contain multiple specs; Felix decomposes a spec into work units for execution.
_Avoid_: Work unit, task, user story

**Work unit**:
A bounded piece of execution work Felix derives from a spec to decide how to build it. Work units belong to the agent's execution plan; they do not replace or redefine the human-authored requirement.
_Avoid_: Spec, requirement

**Acceptance criteria**:
Conditions or evidence that establish whether a spec meets its intended outcome. Feature-level criteria may summarize the overall result across its specs.
_Avoid_: Definition of done (when the specific criteria are meant)

**User story**:
An optional way to express a user need, not Felix's required work unit or authoring format.
_Avoid_: Spec
