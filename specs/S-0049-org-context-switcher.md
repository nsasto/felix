# S-0049: Organization Context and Switcher

**Phase:** 3 (Realtime Subscriptions)  
**Effort:** 6-8 hours  
**Priority:** Medium  
**Dependencies:** S-0047

---

## Narrative

This specification covers implementing organization context management and a UI component for switching between organizations. Users can be members of multiple organizations (personal + teams), and this feature allows them to switch between different organizational contexts, with each context showing only that organization's projects and data.

---

## Acceptance Criteria

### Organization Context

- [ ] Create **app/frontend/src/contexts/OrganizationContext.tsx** with:
  - Load all organizations user is a member of
  - Track currently selected organization
  - `switchOrganization(orgId)` function
  - Persist selection to localStorage
  - Subscribe to organization_members changes

### Organization Switcher Component

- [ ] Create **app/frontend/src/components/OrganizationSwitcher.tsx** with:
  - Dropdown showing all user's organizations
  - Current organization displayed prominently
  - Click to switch organizations
  - Show personal org with special icon/badge

### Integrate into App

- [ ] Wrap App component with OrganizationProvider
- [ ] Add OrganizationSwitcher to main navigation/header
  - Update AgentDashboard to use current organization's project

---

## Technical Notes

### Organization Context (contexts/OrganizationContext.tsx)

```typescript
import React, { createContext, useContext, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from './AuthContext';

interface Organization {
  id: string;
  name: string;
  slug: string;
  owner_id: string;
  metadata: Record<string, any>;
  created_at: string;
  updated_at: string;
  role?: string; // User's role in this org
}

interface OrganizationContextType {
  organizations: Organization[];
  currentOrg: Organization | null;
  loading: boolean;
  switchOrganization: (orgId: string) => void;
  refreshOrganizations: () => Promise<void>;
}

const OrganizationContext = createContext<OrganizationContextType | undefined>(undefined);

export function OrganizationProvider({ children }: { children: React.ReactNode }) {
  const { user } = useAuth();
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [currentOrg, setCurrentOrg] = useState<Organization | null>(null);
  const [loading, setLoading] = useState(true);

  // Load user's organizations
  const loadOrganizations = async () => {
    if (!user) {
      setOrganizations([]);
      setCurrentOrg(null);
      setLoading(false);
      return;
    }

    try {
      // Query organization_members to find user's orgs
      const { data: memberships, error } = await supabase
        .from('organization_members')
        .select('org_id, role, organization:organizations(*)')
        .eq('user_id', user.id);

      if (error) throw error;

      const orgs = memberships?.map(m => ({
        ...m.organization,
        role: m.role
      })) || [];

      setOrganizations(orgs);

      // Set current org from localStorage or default to first org
      const savedOrgId = localStorage.getItem('currentOrgId');
      const current = orgs.find(o => o.id === savedOrgId) || orgs[0] || null;
      setCurrentOrg(current);

      setLoading(false);
    } catch (err) {
      console.error('Failed to load organizations:', err);
      setLoading(false);
    }
  };

  useEffect(() => {
    loadOrganizations();
  }, [user]);

  // Subscribe to organization_members changes
  useEffect(() => {
    if (!user) return;

    const channel = supabase
      .channel('org_membership_changes')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'organization_members',
          filter: `user_id=eq.${user.id}`
        },
        () => {
          // Refresh organizations when membership changes
          loadOrganizations();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [user]);

  const switchOrganization = (orgId: string) => {
    const org = organizations.find(o => o.id === orgId);
    if (org) {
      setCurrentOrg(org);
      localStorage.setItem('currentOrgId', orgId);
    }
  };

  return (
    <OrganizationContext.Provider
      value={{
        organizations,
        currentOrg,
        loading,
        switchOrganization,
        refreshOrganizations: loadOrganizations
      }}
    >
      {children}
    </OrganizationContext.Provider>
  );
}

export function useOrganization() {
  const context = useContext(OrganizationContext);
  if (context === undefined) {
    throw new Error('useOrganization must be used within an OrganizationProvider');
  }
  return context;
}
```

### Organization Switcher Component (components/OrganizationSwitcher.tsx)

```typescript
import React, { useState } from 'react';
import { useOrganization } from '../contexts/OrganizationContext';

export default function OrganizationSwitcher() {
  const { organizations, currentOrg, switchOrganization } = useOrganization();
  const [isOpen, setIsOpen] = useState(false);

  if (!currentOrg) {
    return <div>No organization selected</div>;
  }

  const isPersonalOrg = currentOrg.metadata?.personal === true;

  return (
    <div className="org-switcher">
      <button
        className="org-switcher-button"
        onClick={() => setIsOpen(!isOpen)}
      >
        <span className="org-name">
          {isPersonalOrg && '👤 '}
          {currentOrg.name}
        </span>
        <span className="dropdown-arrow">▼</span>
      </button>

      {isOpen && (
        <div className="org-dropdown">
          {organizations.map(org => (
            <div
              key={org.id}
              className={`org-option ${org.id === currentOrg.id ? 'active' : ''}`}
              onClick={() => {
                switchOrganization(org.id);
                setIsOpen(false);
              }}
            >
              <span className="org-name">
                {org.metadata?.personal && '👤 '}
                {org.name}
              </span>
              <span className="org-role">{org.role}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
```

### Update App.tsx

```typescript
import { AuthProvider } from './contexts/AuthContext';
import { OrganizationProvider } from './contexts/OrganizationContext';
import OrganizationSwitcher from './components/OrganizationSwitcher';
import AgentDashboard from './components/AgentDashboard';

export default function App() {
  return (
    <AuthProvider>
      <OrganizationProvider>
        <div className="app">
          <header>
            <h1>Felix Dashboard</h1>
            <OrganizationSwitcher />
          </header>
          <main>
            <AgentDashboard />
          </main>
        </div>
      </OrganizationProvider>
    </AuthProvider>
  );
}
```

### Update AgentDashboard to Use Current Org

```typescript
import { useOrganization } from '../contexts/OrganizationContext';

export default function AgentDashboard() {
  const { currentOrg } = useOrganization();

  if (!currentOrg) {
    return <div>No organization selected</div>;
  }

  // Get first project for current org (temporary - Phase 4 will add project selection)
  const [projectId, setProjectId] = useState<string | null>(null);

  useEffect(() => {
    const loadProject = async () => {
      const { data } = await supabase
        .from('projects')
        .select('id')
        .eq('org_id', currentOrg.id)
        .limit(1)
        .single();

      setProjectId(data?.id || null);
    };

    loadProject();
  }, [currentOrg]);

  if (!projectId) {
    return <div>No projects in this organization</div>;
  }

  const { agents, runs, loading, error } = useProjectState(projectId);

  // ... rest of component
}
```

---

## Dependencies

**Depends On:**

- S-0047: Frontend Supabase Client and Realtime Hooks

**Blocks:**

- S-0050: Data Migration Script (Phase 4)

---

## Validation Criteria

### File Creation

- [ ] File exists: **app/frontend/src/contexts/OrganizationContext.tsx**
- [ ] File exists: **app/frontend/src/components/OrganizationSwitcher.tsx**
- [ ] App.tsx updated with OrganizationProvider

### Build Verification

- [ ] Frontend builds: `cd app/frontend && npm run build` (exit code 0)
- [ ] No TypeScript errors: `npx tsc --noEmit`

### Organization Loading Test

- [ ] Sign in with test user
- [ ] Verify OrganizationSwitcher displays personal org
- [ ] Check localStorage: `localStorage.getItem('currentOrgId')` (should be personal org ID)
- [ ] Console shows loaded organizations

### Organization Switching Test

**Setup:**

1. Create second organization via Supabase Table Editor:

```sql
INSERT INTO organizations (name, slug, owner_id, metadata)
VALUES ('Team Org', 'team-org', '<user-id>', '{"personal": false}');

INSERT INTO organization_members (org_id, user_id, role)
VALUES ('<team-org-id>', '<user-id>', 'member');
```

2. Refresh frontend
3. Verify OrganizationSwitcher shows 2 orgs (personal + team)
4. Click team org → verify switch
5. Verify AgentDashboard updates to show team org's data
6. localStorage updated with new org ID
7. Refresh page → verify team org still selected

### Personal Org Badge Test

- [ ] Personal org shows 👤 icon in switcher
- [ ] Team org has no icon
- [ ] Role badge shows correctly (owner, admin, member)

### Real-Time Membership Test

**Tab 1 (User A):**

1. Sign in as User A
2. Create team org, invite User B via Table Editor

**Tab 2 (User B):**

1. Sign in as User B
2. Verify new org appears in switcher automatically (no refresh)
3. Real-time subscription detected membership change

---

## Rollback Strategy

If organization context causes issues:

1. Remove OrganizationProvider from App.tsx
2. Hardcode organization in AgentDashboard
3. Hide OrganizationSwitcher
4. Debug context implementation

---

## Notes

- localStorage persists organization selection across sessions
- Personal orgs are auto-created on signup (S-0046 trigger)
- Users can be members of multiple orgs (personal + teams)
- RLS policies isolate data by organization (S-0044)
- Real-time subscriptions keep org list up-to-date
- Switching org triggers AgentDashboard re-render with new project
- Phase 4 will add project selection within organization
- For now, AgentDashboard shows first project in current org
- Organization metadata.personal flag identifies personal orgs
- Dropdown closes after selection for better UX
- Active org highlighted in dropdown

