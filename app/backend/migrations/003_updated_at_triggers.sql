-- Felix Database Migration 003
-- Adds updated_at trigger for tables with updated_at columns.

-- ====================================================================
-- TRIGGER FUNCTION
-- ====================================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ====================================================================
-- TRIGGERS
-- ====================================================================
DROP TRIGGER IF EXISTS set_updated_at_organizations ON organizations;
CREATE TRIGGER set_updated_at_organizations
BEFORE UPDATE ON organizations
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_projects ON projects;
CREATE TRIGGER set_updated_at_projects
BEFORE UPDATE ON projects
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_requirements ON requirements;
CREATE TRIGGER set_updated_at_requirements
BEFORE UPDATE ON requirements
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_agents ON agents;
CREATE TRIGGER set_updated_at_agents
BEFORE UPDATE ON agents
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_agent_states ON agent_states;
CREATE TRIGGER set_updated_at_agent_states
BEFORE UPDATE ON agent_states
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ====================================================================
-- ROLLBACK
-- ====================================================================
-- DROP TRIGGER IF EXISTS set_updated_at_agent_states ON agent_states;
-- DROP TRIGGER IF EXISTS set_updated_at_agents ON agents;
-- DROP TRIGGER IF EXISTS set_updated_at_requirements ON requirements;
-- DROP TRIGGER IF EXISTS set_updated_at_projects ON projects;
-- DROP TRIGGER IF EXISTS set_updated_at_organizations ON organizations;
-- DROP FUNCTION IF EXISTS set_updated_at();
