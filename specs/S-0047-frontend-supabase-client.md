# S-0047: Frontend Supabase Client and Realtime Hooks

**Phase:** 3 (Realtime Subscriptions)  
**Effort:** 6-8 hours  
**Priority:** High  
## Dependencies

- S-0046

---

## Narrative

This specification covers setting up the Supabase JavaScript client in the frontend and creating React hooks for subscribing to real-time database changes via Supabase Realtime. This provides the foundation for replacing polling with event-driven updates.

---

## Acceptance Criteria

### Install Supabase JS Client

- [ ] Install package: `cd app/frontend && npm install @supabase/supabase-js`

### Supabase Client Configuration

- [ ] Create **app/frontend/src/lib/supabase.ts** with Supabase client instance
- [ ] Configure with SUPABASE_URL and SUPABASE_ANON_KEY from environment variables
- [ ] Create **.env.local** file with Supabase credentials

### Realtime Hook

- [ ] Create **app/frontend/src/hooks/useSupabaseRealtime.ts** with:
  - `useSupabaseRealtime<T>(table, filter, callback)` hook
  - Subscribe to postgres_changes events (INSERT, UPDATE, DELETE)
  - Handle cleanup on unmount
  - TypeScript generics for type safety

### Auth Context

- [ ] Create **app/frontend/src/contexts/AuthContext.tsx** with:
  - Sign up, sign in, sign out functions
  - Current user state
  - Session management
  - Token refresh handling

### Environment Configuration

- [ ] Create **app/frontend/.env.local** with:
  - `VITE_SUPABASE_URL`
  - `VITE_SUPABASE_ANON_KEY`
- [ ] Update **.gitignore** to exclude .env.local

---

## Technical Notes

### Supabase Client (lib/supabase.ts)

```typescript
import { createClient } from "@supabase/supabase-js";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error("Missing Supabase environment variables");
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
  realtime: {
    params: {
      eventsPerSecond: 10,
    },
  },
});
```

### Realtime Hook (hooks/useSupabaseRealtime.ts)

```typescript
import { useEffect } from "react";
import { supabase } from "../lib/supabase";
import {
  RealtimeChannel,
  RealtimePostgresChangesPayload,
} from "@supabase/supabase-js";

type ChangeEvent = "INSERT" | "UPDATE" | "DELETE" | "*";

interface UseRealtimeOptions<T> {
  table: string;
  event?: ChangeEvent;
  filter?: string;
  onInsert?: (payload: T) => void;
  onUpdate?: (payload: { old: T; new: T }) => void;
  onDelete?: (payload: T) => void;
}

export function useSupabaseRealtime<T = any>(options: UseRealtimeOptions<T>) {
  const { table, event = "*", filter, onInsert, onUpdate, onDelete } = options;

  useEffect(() => {
    let channel: RealtimeChannel;

    const subscribe = async () => {
      // Build channel name
      const channelName = `realtime:${table}${filter ? `:${filter}` : ""}`;

      // Create channel
      channel = supabase.channel(channelName);

      // Subscribe to postgres_changes
      channel.on(
        "postgres_changes",
        {
          event,
          schema: "public",
          table,
          filter,
        },
        (payload: RealtimePostgresChangesPayload<T>) => {
          console.log(`[Realtime] ${payload.eventType} on ${table}:`, payload);

          switch (payload.eventType) {
            case "INSERT":
              onInsert?.(payload.new as T);
              break;
            case "UPDATE":
              onUpdate?.({ old: payload.old as T, new: payload.new as T });
              break;
            case "DELETE":
              onDelete?.(payload.old as T);
              break;
          }
        },
      );

      // Subscribe to channel
      await channel.subscribe();
      console.log(`[Realtime] Subscribed to ${channelName}`);
    };

    subscribe();

    // Cleanup on unmount
    return () => {
      if (channel) {
        supabase.removeChannel(channel);
        console.log(`[Realtime] Unsubscribed from ${table}`);
      }
    };
  }, [table, event, filter, onInsert, onUpdate, onDelete]);
}
```

### Auth Context (contexts/AuthContext.tsx)

```typescript
import React, { createContext, useContext, useEffect, useState } from 'react';
import { User, Session, AuthError } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';

interface AuthContextType {
  user: User | null;
  session: Session | null;
  loading: boolean;
  signUp: (email: string, password: string) => Promise<{ error?: AuthError }>;
  signIn: (email: string, password: string) => Promise<{ error?: AuthError }>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Get initial session
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      setUser(session?.user ?? null);
      setLoading(false);
    });

    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        setSession(session);
        setUser(session?.user ?? null);
      }
    );

    return () => subscription.unsubscribe();
  }, []);

  const signUp = async (email: string, password: string) => {
    const { error } = await supabase.auth.signUp({ email, password });
    return { error };
  };

  const signIn = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    return { error };
  };

  const signOut = async () => {
    await supabase.auth.signOut();
  };

  return (
    <AuthContext.Provider value={{ user, session, loading, signUp, signIn, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
```

### Environment File (.env.local)

```bash
VITE_SUPABASE_URL=https://xxxxxxxx.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

---

## Dependencies

**Depends On:**

- S-0046: Personal Organization Auto-Creation (Phase 2 complete)

**Blocks:**

- S-0048: Project State Management with Realtime

---

## Validation Criteria

### Installation Verification

- [ ] Package installed: `ls app/frontend/node_modules/@supabase/supabase-js`
- [ ] File exists: **app/frontend/src/lib/supabase.ts**
- [ ] File exists: **app/frontend/src/hooks/useSupabaseRealtime.ts**
- [ ] File exists: **app/frontend/src/contexts/AuthContext.tsx**
- [ ] File exists: **app/frontend/.env.local**
- [ ] .env.local added to .gitignore

### Build Verification

- [ ] Frontend builds: `cd app/frontend && npm run build` (exit code 0)
- [ ] No TypeScript errors: `npx tsc --noEmit`

### Supabase Client Test

```typescript
// Test in browser console after starting frontend
import { supabase } from "./lib/supabase";

// Check client initialization
console.log(supabase);

// Test database query
const { data, error } = await supabase.from("organizations").select("*");
console.log("Organizations:", data);
```

### Auth Context Test

```typescript
// Add temporary test component in App.tsx
import { useAuth } from './contexts/AuthContext';

function AuthTest() {
  const { user, signIn, signOut } = useAuth();

  return (
    <div>
      <p>User: {user?.email || 'Not logged in'}</p>
      {!user && (
        <button onClick={() => signIn('test@example.com', 'password')}>
          Sign In
        </button>
      )}
      {user && <button onClick={signOut}>Sign Out</button>}
    </div>
  );
}
```

### Realtime Hook Test

```typescript
// Add temporary test component
import { useSupabaseRealtime } from './hooks/useSupabaseRealtime';

function RealtimeTest() {
  useSupabaseRealtime({
    table: 'agents',
    onInsert: (agent) => console.log('New agent:', agent),
    onUpdate: ({ old, new: updated }) => console.log('Updated agent:', old, updated),
    onDelete: (agent) => console.log('Deleted agent:', agent)
  });

  return <div>Check console for realtime events</div>;
}
```

- [ ] Start frontend
- [ ] Open browser console
- [ ] In another tab, insert agent via Supabase Table Editor
- [ ] Verify console logs show INSERT event
- [ ] Update agent → verify UPDATE event
- [ ] Delete agent → verify DELETE event

### Authentication Flow Test

- [ ] Start frontend
- [ ] Sign in with test user
- [ ] Verify token stored in localStorage (Application → LocalStorage → supabase.auth.token)
- [ ] Refresh page → verify still signed in
- [ ] Sign out → verify token cleared

---

## Rollback Strategy

If Supabase client causes issues:

1. Uninstall package: `npm uninstall @supabase/supabase-js`
2. Delete lib/supabase.ts, hooks/useSupabaseRealtime.ts, contexts/AuthContext.tsx
3. Remove from App.tsx
4. Continue using API client from Phase 1

---

## Notes

- @supabase/supabase-js provides client for Auth, Database, Realtime, and Storage
- Anon key is safe to expose in frontend - RLS policies enforce security
- Realtime uses WebSocket under the hood (managed by Supabase)
- useSupabaseRealtime hook is generic - reusable across all tables
- Auth context manages session, auto-refreshes tokens, persists to localStorage
- Vite uses import.meta.env for environment variables (not process.env)
- .env.local is loaded automatically by Vite (no extra config needed)
- Realtime events are instant (sub-500ms latency typical)
- Personal organization is auto-created on signup (S-0046 trigger)
- Phase 3 (S-0048) will use these hooks to replace polling in dashboard

