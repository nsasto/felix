import React, { useCallback, useEffect, useState } from "react";
import { felixApi, FelixConfig, Project } from "../services/felixApi";
import { AlertTriangle, Copy, Folder, Plus, Search, X } from "lucide-react";
import {
  inviteOrgMember,
  listOrgMembers,
  removeOrgMember,
  resendOrgInvite,
  revokeOrgInvite,
  updateOrgInviteRole,
  updateOrgMemberRole,
} from "../src/api/client";
import type { OrgInvite, OrgMember } from "../src/api/types";
import { Alert, AlertDescription } from "./ui/alert";
import { Badge } from "./ui/badge";
import { Button } from "./ui/button";
import DataSurface from "./DataSurface";
import FilterPopover from "./FilterPopover";
import { Input } from "./ui/input";
import { PageLoading } from "./ui/page-loading";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "./ui/select";
import { Tabs, TabsList, TabsTrigger } from "./ui/tabs";
import { Switch } from "./ui/switch";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "./ui/table";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "./ui/dialog";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "./ui/alert-dialog";

type OrgTab =
  | "members"
  | "projects"
  | "adapters"
  | "agent-templates"
  | "policies"
  | "billing";

const ORG_TABS: Array<{ id: OrgTab; label: string }> = [
  { id: "members", label: "Members and Roles" },
  { id: "projects", label: "Projects" },
  { id: "adapters", label: "Adapters" },
  { id: "agent-templates", label: "Agent Templates" },
  { id: "policies", label: "Policies" },
  { id: "billing", label: "Billing" },
];

type MemberRow = {
  id: string;
  kind: "member" | "invite";
  name: string;
  email: string;
  role: string;
  status: string;
  lastActive: string;
  joinedAt: string;
  userId?: string;
  inviteId?: string;
};

interface OrganizationSettingsScreenProps {
  orgId?: string | null;
  orgSlug?: string | null;
  organizationName?: string | null;
  roleLabel?: string | null;
  onBack: () => void;
}

const OrganizationSettingsScreen: React.FC<OrganizationSettingsScreenProps> = ({
  orgId,
  organizationName,
  roleLabel,
  onBack,
}) => {
  const [activeTab, setActiveTab] = useState<OrgTab>("projects");
  const [projects, setProjects] = useState<Project[]>([]);
  const [projectsLoading, setProjectsLoading] = useState(false);
  const [projectsError, setProjectsError] = useState<string | null>(null);
  const [projectSearchQuery, setProjectSearchQuery] = useState("");
  const [showRegisterForm, setShowRegisterForm] = useState(false);
  const [registerGitUrl, setRegisterGitUrl] = useState("");
  const [registerName, setRegisterName] = useState("");
  const [isRegistering, setIsRegistering] = useState(false);
  const [registerError, setRegisterError] = useState<string | null>(null);
  const [unregisteringId, setUnregisteringId] = useState<string | null>(null);
  const [showUnregisterConfirm, setShowUnregisterConfirm] = useState<
    string | null
  >(null);
  const [configuringProjectId, setConfiguringProjectId] = useState<
    string | null
  >(null);
  const [configProjectName, setConfigProjectName] = useState("");
  const [configProjectGitUrl, setConfigProjectGitUrl] = useState("");
  const [isSavingConfig, setIsSavingConfig] = useState(false);
  const [orgConfig, setOrgConfig] = useState<FelixConfig | null>(null);
  const [orgConfigOriginal, setOrgConfigOriginal] =
    useState<FelixConfig | null>(null);
  const [orgConfigLoading, setOrgConfigLoading] = useState(false);
  const [orgConfigSaving, setOrgConfigSaving] = useState(false);
  const [orgConfigError, setOrgConfigError] = useState<string | null>(null);
  const [orgValidationErrors, setOrgValidationErrors] = useState<
    Record<string, string>
  >({});
  const [memberSearchQuery, setMemberSearchQuery] = useState("");
  const [memberFilters, setMemberFilters] = useState<
    Record<string, Set<string>>
  >({
    role: new Set(),
    status: new Set(),
  });
  const [orgMembers, setOrgMembers] = useState<OrgMember[]>([]);
  const [orgInvites, setOrgInvites] = useState<OrgInvite[]>([]);
  const [membersLoading, setMembersLoading] = useState(false);
  const [membersError, setMembersError] = useState<string | null>(null);
  const [inviteOpen, setInviteOpen] = useState(false);
  const [inviteEmail, setInviteEmail] = useState("");
  const [inviteRole, setInviteRole] = useState("member");
  const [inviteError, setInviteError] = useState<string | null>(null);
  const [inviteSubmitting, setInviteSubmitting] = useState(false);
  const [manageMember, setManageMember] = useState<MemberRow | null>(null);
  const [manageRole, setManageRole] = useState("member");
  const [manageSaving, setManageSaving] = useState(false);
  const [manageError, setManageError] = useState<string | null>(null);
  const [resendInviting, setResendInviting] = useState(false);
  const [confirmRemoveOpen, setConfirmRemoveOpen] = useState(false);
  const [pendingRemove, setPendingRemove] = useState<MemberRow | null>(null);

  const fetchProjects = useCallback(async () => {
    if (!orgId) {
      setProjectsError("Organization not selected.");
      setProjectsLoading(false);
      return;
    }
    setProjectsLoading(true);
    setProjectsError(null);
    try {
      const list = await Promise.race([
        felixApi.listProjects(),
        new Promise<Project[]>((_, reject) =>
          setTimeout(
            () => reject(new Error("Project request timed out")),
            12000,
          ),
        ),
      ]);
      setProjects(list);
    } catch (err) {
      setProjectsError(
        err instanceof Error ? err.message : "Failed to load projects",
      );
    } finally {
      setProjectsLoading(false);
    }
  }, [orgId]);

  useEffect(() => {
    if (activeTab === "projects") {
      fetchProjects();
    }
  }, [activeTab, fetchProjects]);

  const fetchOrgMembers = useCallback(async () => {
    if (!orgId) {
      setMembersError("Organization not selected.");
      setMembersLoading(false);
      return;
    }
    setMembersLoading(true);
    setMembersError(null);
    try {
      const result = await listOrgMembers(orgId);
      setOrgMembers(result.members);
      setOrgInvites(result.invites);
    } catch (err) {
      setMembersError(
        err instanceof Error ? err.message : "Failed to load members",
      );
    } finally {
      setMembersLoading(false);
    }
  }, [orgId]);

  useEffect(() => {
    if (activeTab === "members") {
      fetchOrgMembers();
    }
  }, [activeTab, fetchOrgMembers]);

  const fetchOrgConfig = useCallback(async () => {
    setOrgConfigLoading(true);
    setOrgConfigError(null);
    try {
      const result = await felixApi.getOrgConfig();
      setOrgConfig(result.config);
      setOrgConfigOriginal(result.config);
    } catch (err) {
      setOrgConfigError(
        err instanceof Error ? err.message : "Failed to load org settings",
      );
    } finally {
      setOrgConfigLoading(false);
    }
  }, []);

  useEffect(() => {
    if (activeTab === "policies") {
      fetchOrgConfig();
    }
  }, [activeTab, fetchOrgConfig]);

  const handleOrgExecutorChange = (
    field: keyof FelixConfig["executor"],
    value: any,
  ) => {
    if (!orgConfig) return;
    const updated = {
      ...orgConfig,
      executor: {
        ...orgConfig.executor,
        [field]: value,
      },
    };
    setOrgConfig(updated);
    setOrgValidationErrors(validateOrgConfig(updated));
  };

  const handleOrgBackpressureChange = (
    field: keyof FelixConfig["backpressure"],
    value: any,
  ) => {
    if (!orgConfig) return;
    const updated = {
      ...orgConfig,
      backpressure: {
        ...orgConfig.backpressure,
        [field]: value,
      },
    };
    setOrgConfig(updated);
    setOrgValidationErrors(validateOrgConfig(updated));
  };

  const validateOrgConfig = (config: FelixConfig): Record<string, string> => {
    const errors: Record<string, string> = {};
    if (
      !Number.isInteger(config.executor.max_iterations) ||
      config.executor.max_iterations <= 0
    ) {
      errors.max_iterations = "Must be a positive integer";
    }
    if (!["planning", "building"].includes(config.executor.default_mode)) {
      errors.default_mode = 'Must be "planning" or "building"';
    }
    if (config.backpressure.max_retries !== undefined) {
      if (
        !Number.isInteger(config.backpressure.max_retries) ||
        config.backpressure.max_retries < 0
      ) {
        errors.max_retries = "Must be a non-negative integer";
      }
    }
    return errors;
  };

  const saveOrgConfig = async () => {
    if (!orgConfig) return;
    const errors = validateOrgConfig(orgConfig);
    if (Object.keys(errors).length > 0) {
      setOrgValidationErrors(errors);
      return;
    }
    setOrgConfigSaving(true);
    setOrgConfigError(null);
    try {
      const result = await felixApi.updateOrgConfig(orgConfig);
      setOrgConfig(result.config);
      setOrgConfigOriginal(result.config);
      setOrgValidationErrors({});
    } catch (err) {
      setOrgConfigError(
        err instanceof Error ? err.message : "Failed to save org settings",
      );
    } finally {
      setOrgConfigSaving(false);
    }
  };

  const renderMembersTab = () => {
    const formatLabel = (value: string) =>
      value
        .replace(/[_-]+/g, " ")
        .split(" ")
        .filter(Boolean)
        .map((segment) => segment[0].toUpperCase() + segment.slice(1))
        .join(" ");

    const parseNameFromEmail = (email: string) => {
      const handle = email.split("@")[0] || "New member";
      return handle
        .split(/[._-]+/)
        .filter(Boolean)
        .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
        .join(" ");
    };

    const rows: MemberRow[] = [
      ...orgMembers.map((member) => ({
        id: `member-${member.user_id}`,
        kind: "member",
        name:
          member.display_name ||
          member.full_name ||
          member.email ||
          member.user_id ||
          "Member",
        email: member.email || member.user_id || "",
        role: formatLabel(member.role),
        status: "Active",
        lastActive: member.updated_at
          ? new Date(member.updated_at).toLocaleDateString()
          : "N/A",
        joinedAt: member.created_at,
        userId: member.user_id,
      })),
      ...orgInvites.map((invite) => ({
        id: `invite-${invite.id}`,
        kind: "invite",
        name: parseNameFromEmail(invite.email),
        email: invite.email,
        role: formatLabel(invite.role),
        status: formatLabel(invite.status || "invited"),
        lastActive: "Awaiting",
        joinedAt: invite.created_at,
        inviteId: invite.id,
      })),
    ];

    const filteredMembers = rows.filter((member) => {
      const query = memberSearchQuery.trim().toLowerCase();
      const matchesQuery =
        !query ||
        member.name.toLowerCase().includes(query) ||
        member.email.toLowerCase().includes(query);
      const matchesRole =
        memberFilters.role.size === 0 ||
        memberFilters.role.has(member.role.toLowerCase());
      const matchesStatus =
        memberFilters.status.size === 0 ||
        memberFilters.status.has(member.status.toLowerCase());
      return matchesQuery && matchesRole && matchesStatus;
    });

    const roleOptions = Array.from(
      new Set(rows.map((member) => member.role.toLowerCase())),
    );
    const statusOptions = Array.from(
      new Set(rows.map((member) => member.status.toLowerCase())),
    );

    const statusVariant = (
      status: string,
    ): React.ComponentProps<typeof Badge>["variant"] => {
      switch (status.toLowerCase()) {
        case "active":
          return "success";
        case "invited":
        case "pending":
          return "warning";
        default:
          return "default";
      }
    };

    const handleInviteSubmit = async () => {
      if (!orgId) {
        setInviteError("Organization not selected.");
        return;
      }
      const trimmedEmail = inviteEmail.trim().toLowerCase();
      if (!trimmedEmail) {
        setInviteError("Email is required.");
        return;
      }
      if (!/^[^@]+@[^@]+\.[^@]+$/.test(trimmedEmail)) {
        setInviteError("Enter a valid email address.");
        return;
      }
      if (rows.some((member) => member.email.toLowerCase() === trimmedEmail)) {
        setInviteError("This email is already listed.");
        return;
      }
      setInviteSubmitting(true);
      setInviteError(null);
      try {
        await inviteOrgMember(orgId, {
          email: trimmedEmail,
          role: inviteRole,
        });
        await fetchOrgMembers();
        setInviteEmail("");
        setInviteRole("member");
        setInviteOpen(false);
      } catch (err) {
        setInviteError(
          err instanceof Error ? err.message : "Failed to send invite",
        );
      } finally {
        setInviteSubmitting(false);
      }
    };

    const openManageMember = (member: MemberRow) => {
      setManageMember(member);
      setManageRole(member.role.toLowerCase());
      setManageError(null);
    };

    const handleManageSave = async () => {
      if (!manageMember || !orgId) return;
      setManageSaving(true);
      setManageError(null);
      try {
        const updatedRole = manageRole;
        if (manageMember.kind === "invite") {
          await updateOrgInviteRole(orgId, manageMember.inviteId!, updatedRole);
        } else {
          await updateOrgMemberRole(orgId, manageMember.userId!, updatedRole);
        }
        await fetchOrgMembers();
        setManageMember(null);
      } catch (err) {
        setManageError(
          err instanceof Error ? err.message : "Failed to update role",
        );
      } finally {
        setManageSaving(false);
      }
    };

    const handleRemoveMember = async () => {
      if (!pendingRemove || !orgId) return;
      try {
        if (pendingRemove.kind === "invite") {
          await revokeOrgInvite(orgId, pendingRemove.inviteId!);
        } else {
          await removeOrgMember(orgId, pendingRemove.userId!);
        }
        await fetchOrgMembers();
      } catch (err) {
        setMembersError(
          err instanceof Error ? err.message : "Failed to remove member",
        );
      } finally {
        setPendingRemove(null);
        setConfirmRemoveOpen(false);
        setManageMember(null);
      }
    };

    const handleResendInvite = async () => {
      if (!manageMember || manageMember.kind !== "invite" || !orgId) return;
      setResendInviting(true);
      setManageError(null);
      try {
        await resendOrgInvite(orgId, manageMember.inviteId!);
        await fetchOrgMembers();
      } catch (err) {
        setManageError(
          err instanceof Error ? err.message : "Failed to resend invite",
        );
      } finally {
        setResendInviting(false);
      }
    };

    if (membersLoading) {
      return (
        <div className="flex justify-center py-8">
          <PageLoading
            message="Loading members..."
            size="md"
            fullPage={false}
          />
        </div>
      );
    }

    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between mb-2">
          <div>
            <h3 className="text-lg font-semibold">Members and Roles</h3>
            <p className="text-xs theme-text-muted mt-1">
              Manage organization access and role assignments.
            </p>
          </div>
          <Button
            size="sm"
            className="uppercase"
            onClick={() => setInviteOpen(true)}
          >
            <Plus className="w-4 h-4" />
            Invite Member
          </Button>
        </div>
        {membersError && (
          <Alert className="border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
            <AlertDescription className="text-xs">
              {membersError}
            </AlertDescription>
          </Alert>
        )}
        <DataSurface
          className="pt-0 -mx-6"
          search={
            <div className="relative w-full max-w-sm">
              <Input
                type="text"
                placeholder="Search members by name or email..."
                value={memberSearchQuery}
                onChange={(e) => setMemberSearchQuery(e.target.value)}
                className="h-9 pl-9 text-sm"
              />
              <Search className="w-4 h-4 theme-text-muted absolute left-3 top-1/2 -translate-y-1/2" />
            </div>
          }
          filters={
            <FilterPopover
              groups={[
                {
                  key: "role",
                  label: "Role",
                  options: roleOptions.map((role) => ({
                    label: formatLabel(role),
                    value: role,
                  })),
                },
                {
                  key: "status",
                  label: "Status",
                  options: statusOptions.map((status) => ({
                    label: formatLabel(status),
                    value: status,
                  })),
                },
              ]}
              value={memberFilters}
              onChange={setMemberFilters}
              label="Filter members"
            />
          }
          footer={
            <div className="flex items-center justify-between">
              <div>
                <h4 className="text-sm font-semibold theme-text-secondary">
                  Members summary
                </h4>
                <p className="text-[11px] theme-text-muted mt-1">
                  {rows.length} total, {orgMembers.length} active.
                </p>
              </div>
              <Badge variant="default">Org Scope</Badge>
            </div>
          }
        >
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Member</TableHead>
                <TableHead>Role</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Last Active</TableHead>
                <TableHead>Joined</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {filteredMembers.map((member) => (
                <TableRow key={member.id}>
                  <TableCell>
                    <div className="flex items-center gap-3">
                      <div className="w-9 h-9 rounded-full bg-[var(--bg-surface-200)] flex items-center justify-center text-[11px] font-bold text-[var(--text-muted)]">
                        {member.name
                          .split(" ")
                          .map((part) => part[0])
                          .slice(0, 2)
                          .join("")}
                      </div>
                      <div>
                        <p className="text-sm font-semibold theme-text-secondary">
                          {member.name}
                        </p>
                        <p className="text-[11px] theme-text-muted">
                          {member.email || "N/A"}
                        </p>
                      </div>
                    </div>
                  </TableCell>
                  <TableCell>
                    <span className="text-xs font-semibold theme-text-secondary">
                      {member.role}
                    </span>
                  </TableCell>
                  <TableCell>
                    <Badge variant={statusVariant(member.status)}>
                      {member.status}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    <span className="text-xs theme-text-muted">
                      {member.lastActive}
                    </span>
                  </TableCell>
                  <TableCell>
                    <span className="text-xs theme-text-muted">
                      {new Date(member.joinedAt).toLocaleDateString()}
                    </span>
                  </TableCell>
                  <TableCell className="text-right">
                    <Button
                      variant="ghost"
                      size="sm"
                      className="text-[10px] font-bold"
                      onClick={() => openManageMember(member)}
                    >
                      Manage
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
              {filteredMembers.length === 0 && (
                <TableRow>
                  <TableCell colSpan={6}>
                    <div className="py-6 text-center text-xs theme-text-muted">
                      No members match the current filters.
                    </div>
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </DataSurface>

        <Dialog open={inviteOpen} onOpenChange={setInviteOpen}>
          <DialogContent>
            <DialogHeader>
              <div>
                <DialogTitle>Invite Member</DialogTitle>
                <DialogDescription>
                  Send an invitation to join this organization.
                </DialogDescription>
              </div>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => setInviteOpen(false)}
              >
                <X className="w-4 h-4" />
              </Button>
            </DialogHeader>
            <div className="px-4 py-4 space-y-4">
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Email Address
                </label>
                <Input
                  type="email"
                  placeholder="member@company.com"
                  value={inviteEmail}
                  onChange={(e) => {
                    setInviteEmail(e.target.value);
                    if (inviteError) {
                      setInviteError(null);
                    }
                  }}
                />
              </div>
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Role
                </label>
                <Select value={inviteRole} onValueChange={setInviteRole}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="owner">Owner</SelectItem>
                    <SelectItem value="admin">Admin</SelectItem>
                    <SelectItem value="member">Member</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              {inviteError && (
                <Alert className="border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
                  <AlertDescription className="text-xs">
                    {inviteError}
                  </AlertDescription>
                </Alert>
              )}
            </div>
            <DialogFooter>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setInviteOpen(false)}
              >
                Cancel
              </Button>
              <Button
                size="sm"
                className="uppercase"
                onClick={handleInviteSubmit}
                disabled={inviteSubmitting}
              >
                {inviteSubmitting ? "Sending..." : "Send Invite"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>

        <Dialog
          open={!!manageMember}
          onOpenChange={(open) => {
            if (!open) setManageMember(null);
          }}
        >
          <DialogContent>
            <DialogHeader>
              <div>
                <DialogTitle>
                  {manageMember?.kind === "invite"
                    ? "Manage Invite"
                    : "Manage Member"}
                </DialogTitle>
                <DialogDescription>
                  Adjust access level and manage membership.
                </DialogDescription>
              </div>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => setManageMember(null)}
              >
                <X className="w-4 h-4" />
              </Button>
            </DialogHeader>
            {manageMember && (
              <div className="px-4 py-4 space-y-4">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-[var(--bg-surface-200)] flex items-center justify-center text-[11px] font-bold text-[var(--text-muted)]">
                    {manageMember.name
                      .split(" ")
                      .map((part) => part[0])
                      .slice(0, 2)
                      .join("")}
                  </div>
                  <div>
                    <p className="text-sm font-semibold theme-text-secondary">
                      {manageMember.name}
                    </p>
                    <p className="text-[11px] theme-text-muted">
                      {manageMember.email || "N/A"}
                    </p>
                  </div>
                </div>
                <div>
                  <label className="block text-xs font-bold theme-text-tertiary mb-2">
                    Role
                  </label>
                  <Select value={manageRole} onValueChange={setManageRole}>
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="owner">Owner</SelectItem>
                      <SelectItem value="admin">Admin</SelectItem>
                      <SelectItem value="member">Member</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                {manageMember.kind === "invite" && (
                  <div className="flex items-center justify-between rounded-lg border border-[var(--border-muted)] p-3 text-xs">
                    <span className="theme-text-muted">
                      Invitation pending. Last sent{" "}
                      {new Date(manageMember.joinedAt).toLocaleDateString()}.
                    </span>
                    <Button
                      variant="ghost"
                      size="sm"
                      className="text-[10px] font-bold"
                      onClick={handleResendInvite}
                      disabled={resendInviting}
                    >
                      {resendInviting ? "Resending..." : "Resend"}
                    </Button>
                  </div>
                )}
                {manageError && (
                  <Alert className="border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
                    <AlertDescription className="text-xs">
                      {manageError}
                    </AlertDescription>
                  </Alert>
                )}
              </div>
            )}
            <DialogFooter className="justify-between">
              <Button
                variant="destructive"
                size="sm"
                className="bg-[var(--destructive-500)]/10 text-[var(--destructive-500)] hover:bg-[var(--destructive-500)]/20"
                onClick={() => {
                  if (!manageMember) return;
                  setPendingRemove(manageMember);
                  setConfirmRemoveOpen(true);
                }}
              >
                {manageMember?.kind === "invite"
                  ? "Revoke Invite"
                  : "Remove Member"}
              </Button>
              <div className="flex items-center gap-3">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setManageMember(null)}
                >
                  Cancel
                </Button>
                <Button
                  size="sm"
                  className="uppercase"
                  onClick={handleManageSave}
                  disabled={manageSaving}
                >
                  {manageSaving ? "Saving..." : "Save Changes"}
                </Button>
              </div>
            </DialogFooter>
          </DialogContent>
        </Dialog>

        <AlertDialog
          open={confirmRemoveOpen}
          onOpenChange={setConfirmRemoveOpen}
        >
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>
                {pendingRemove?.kind === "invite"
                  ? "Revoke Invite"
                  : "Remove Member"}
              </AlertDialogTitle>
              <AlertDialogDescription>
                {pendingRemove?.kind === "invite"
                  ? "This invitation will be revoked immediately."
                  : "This member will lose access to the organization immediately."}
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel asChild>
                <Button variant="ghost" size="sm">
                  Cancel
                </Button>
              </AlertDialogCancel>
              <AlertDialogAction asChild>
                <Button
                  size="sm"
                  className="bg-[var(--destructive-500)] text-white hover:bg-[var(--destructive-600)]"
                  onClick={handleRemoveMember}
                >
                  {pendingRemove?.kind === "invite" ? "Revoke" : "Remove"}
                </Button>
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </div>
    );
  };

  const renderProjectsTab = () => {
    const filteredProjects = projects.filter((project) => {
      if (!projectSearchQuery.trim()) return true;
      const query = projectSearchQuery.toLowerCase();
      return (
        (project.name || project.id).toLowerCase().includes(query) ||
        project.git_url.toLowerCase().includes(query) ||
        project.id.toLowerCase().includes(query)
      );
    });

    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h3 className="text-lg font-semibold">Projects</h3>
            <p className="text-xs theme-text-muted mt-1">
              Manage registered Felix projects
            </p>
          </div>
          <Button
            onClick={() => setShowRegisterForm(true)}
            size="sm"
            className="uppercase"
          >
            <Plus className="w-4 h-4" />
            Register New Project
          </Button>
        </div>

        <div className="relative">
          <Input
            type="text"
            placeholder="Search projects by name or path..."
            value={projectSearchQuery}
            onChange={(e) => setProjectSearchQuery(e.target.value)}
            className="h-11 pl-10"
          />
          <Search className="w-4 h-4 theme-text-muted absolute left-4 top-1/2 -translate-y-1/2" />
        </div>

        {showRegisterForm && (
          <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-bold theme-text-secondary">
                Register New Project
              </h4>
              <Button
                onClick={() => {
                  setShowRegisterForm(false);
                  setRegisterGitUrl("");
                  setRegisterName("");
                  setRegisterError(null);
                }}
                variant="ghost"
                size="icon"
                className="h-8 w-8"
              >
                <X className="w-4 h-4" />
              </Button>
            </div>
            <div className="space-y-4">
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Git Repository URL *
                </label>
                <Input
                  type="text"
                  placeholder="https://github.com/username/repo.git"
                  value={registerGitUrl}
                  onChange={(e) => setRegisterGitUrl(e.target.value)}
                  className="font-mono"
                />
                <p className="mt-1.5 text-[10px] theme-text-muted">
                  Git repository URL for project identity and authentication
                  <br />
                  Example: https://github.com/username/projectname.git
                </p>
              </div>
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Project Name (optional)
                </label>
                <Input
                  type="text"
                  placeholder="My Project"
                  value={registerName}
                  onChange={(e) => setRegisterName(e.target.value)}
                />
              </div>
              {registerError && (
                <Alert className="border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
                  <AlertDescription className="text-[var(--destructive-500)] text-xs">
                    {registerError}
                  </AlertDescription>
                </Alert>
              )}
              <div className="flex justify-end gap-3 pt-2">
                <Button
                  onClick={() => {
                    setShowRegisterForm(false);
                    setRegisterGitUrl("");
                    setRegisterName("");
                    setRegisterError(null);
                  }}
                  variant="ghost"
                  size="sm"
                  className="uppercase"
                >
                  Cancel
                </Button>
                <Button
                  onClick={async () => {
                    if (!registerGitUrl.trim()) return;
                    setIsRegistering(true);
                    setRegisterError(null);
                    try {
                      await felixApi.registerProject({
                        git_url: registerGitUrl.trim(),
                        name: registerName.trim() || undefined,
                      });
                      setShowRegisterForm(false);
                      setRegisterGitUrl("");
                      setRegisterName("");
                      fetchProjects();
                    } catch (err) {
                      setRegisterError(
                        err instanceof Error
                          ? err.message
                          : "Failed to register project",
                      );
                    } finally {
                      setIsRegistering(false);
                    }
                  }}
                  disabled={!registerGitUrl.trim() || isRegistering}
                  size="sm"
                  className="uppercase"
                >
                  {isRegistering ? (
                    <>
                      <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                      Registering...
                    </>
                  ) : (
                    "Register Project"
                  )}
                </Button>
              </div>
            </div>
          </div>
        )}

        {projectsLoading && (
          <div className="flex flex-col items-center justify-center py-12">
            <PageLoading message="Loading projects..." fullPage={false} />
          </div>
        )}

        {projectsError && !projectsLoading && (
          <Alert className="border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
            <AlertDescription className="flex items-start gap-3 text-[var(--destructive-500)]">
              <AlertTriangle className="w-4 h-4 mt-0.5 flex-shrink-0" />
              <div>
                <p className="text-xs">{projectsError}</p>
                <Button
                  onClick={fetchProjects}
                  variant="ghost"
                  size="sm"
                  className="mt-2 text-[10px] text-[var(--destructive-500)]"
                >
                  Try again
                </Button>
              </div>
            </AlertDescription>
          </Alert>
        )}

        {!projectsLoading &&
          !projectsError &&
          filteredProjects.length === 0 && (
            <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-8 text-center">
              <div className="w-12 h-12 theme-bg-surface rounded-xl flex items-center justify-center mx-auto mb-4">
                <Folder className="w-6 h-6 theme-text-muted" />
              </div>
              <h4 className="text-sm font-bold theme-text-tertiary mb-2">
                No Projects Registered
              </h4>
              <p className="text-xs theme-text-muted max-w-sm mx-auto">
                Register a Felix project to get started. Projects must have
                specs/ and felix/ directories.
              </p>
            </div>
          )}

        {!projectsLoading && !projectsError && filteredProjects.length > 0 && (
          <div className="space-y-3">
            {filteredProjects
              .sort(
                (a, b) =>
                  new Date(b.registered_at).getTime() -
                  new Date(a.registered_at).getTime(),
              )
              .map((project) => (
                <div
                  key={project.id}
                  className="theme-bg-elevated border rounded-xl p-5 transition-all border-[var(--border-default)] hover:border-[var(--border-muted)]"
                >
                  <div className="flex items-start justify-between gap-4">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <h4 className="text-sm font-bold theme-text-secondary truncate">
                          {project.name || project.id}
                        </h4>
                      </div>
                      <div className="flex items-center gap-2">
                        <code className="text-[11px] font-mono theme-text-muted truncate block">
                          {project.git_url}
                        </code>
                        <Button
                          onClick={() =>
                            navigator.clipboard.writeText(project.git_url)
                          }
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7"
                          title="Copy git URL"
                        >
                          <Copy className="w-3.5 h-3.5" />
                        </Button>
                      </div>
                      <p className="text-[10px] theme-text-muted mt-2">
                        Registered{" "}
                        {new Date(project.registered_at).toLocaleDateString()}
                      </p>
                    </div>
                    <div className="flex items-center gap-2 flex-shrink-0">
                      <Button
                        onClick={() => {
                          // TODO: Open project action - requires callback from parent
                        }}
                        variant="secondary"
                        size="sm"
                        className="text-[10px] font-bold"
                      >
                        Open
                      </Button>
                      <Button
                        onClick={() => {
                          setConfiguringProjectId(project.id);
                          setConfigProjectName(project.name || "");
                          setConfigProjectGitUrl(project.git_url || "");
                        }}
                        variant="secondary"
                        size="sm"
                        className="text-[10px] font-bold"
                      >
                        Configure
                      </Button>
                      <Button
                        onClick={() => setShowUnregisterConfirm(project.id)}
                        variant="destructive"
                        size="sm"
                        className="text-[10px] font-bold bg-[var(--destructive-500)]/10 text-[var(--destructive-500)] hover:bg-[var(--destructive-500)]/20"
                      >
                        Unregister
                      </Button>
                    </div>
                  </div>

                  {configuringProjectId === project.id && (
                    <div className="mt-4 pt-4 border-t border-[var(--border-default)]">
                      <div className="space-y-4">
                        <div>
                          <label className="block text-xs font-bold theme-text-tertiary mb-2">
                            Project Name
                          </label>
                          <Input
                            type="text"
                            value={configProjectName}
                            onChange={(e) =>
                              setConfigProjectName(e.target.value)
                            }
                            placeholder="My Project"
                          />
                          <p className="mt-1.5 text-[10px] theme-text-muted">
                            Display name for this project
                          </p>
                        </div>
                        <div>
                          <label className="block text-xs font-bold theme-text-tertiary mb-2">
                            Git Repository URL *
                          </label>
                          <Input
                            type="text"
                            value={configProjectGitUrl}
                            onChange={(e) =>
                              setConfigProjectGitUrl(e.target.value)
                            }
                            placeholder="https://github.com/username/repo.git"
                            className="font-mono"
                          />
                          <p className="mt-1.5 text-[10px] theme-text-muted">
                            Git repository URL for project identity
                          </p>
                        </div>
                        <div className="flex justify-end gap-3">
                          <Button
                            onClick={() => {
                              setConfiguringProjectId(null);
                              setConfigProjectName("");
                              setConfigProjectGitUrl("");
                            }}
                            variant="ghost"
                            size="sm"
                            className="uppercase"
                          >
                            Cancel
                          </Button>
                          <Button
                            onClick={async () => {
                              setIsSavingConfig(true);
                              try {
                                const gitUrlChanged =
                                  configProjectGitUrl.trim() !==
                                  project.git_url;
                                await felixApi.updateProject(project.id, {
                                  name: configProjectName.trim() || undefined,
                                  git_url: gitUrlChanged
                                    ? configProjectGitUrl.trim() || null
                                    : undefined,
                                });
                                setConfiguringProjectId(null);
                                setConfigProjectName("");
                                setConfigProjectGitUrl("");
                                fetchProjects();
                              } catch (err) {
                                setProjectsError(
                                  err instanceof Error
                                    ? err.message
                                    : "Failed to save project configuration",
                                );
                              } finally {
                                setIsSavingConfig(false);
                              }
                            }}
                            disabled={isSavingConfig}
                            size="sm"
                            className="uppercase"
                          >
                            {isSavingConfig ? (
                              <>
                                <div className="w-3 h-3 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                                Saving...
                              </>
                            ) : (
                              "Save"
                            )}
                          </Button>
                        </div>
                      </div>
                    </div>
                  )}

                  {showUnregisterConfirm === project.id && (
                    <div className="mt-4 pt-4 border-t border-[var(--border-default)]">
                      <div className="flex items-center justify-between">
                        <p className="text-xs text-[var(--status-warning)]">
                          Remove this project from Felix? Files will remain on
                          disk.
                        </p>
                        <div className="flex items-center gap-2">
                          <Button
                            onClick={() => setShowUnregisterConfirm(null)}
                            variant="ghost"
                            size="sm"
                            className="text-[10px] font-bold"
                          >
                            Cancel
                          </Button>
                          <Button
                            onClick={async () => {
                              setUnregisteringId(project.id);
                              try {
                                await felixApi.unregisterProject(project.id);
                                setShowUnregisterConfirm(null);
                                fetchProjects();
                              } catch (err) {
                                setProjectsError(
                                  err instanceof Error
                                    ? err.message
                                    : "Failed to unregister project",
                                );
                              } finally {
                                setUnregisteringId(null);
                              }
                            }}
                            disabled={unregisteringId === project.id}
                            variant="destructive"
                            size="sm"
                            className="text-[10px] font-bold bg-[var(--destructive-500)]/10 text-[var(--destructive-500)] hover:bg-[var(--destructive-500)]/20"
                          >
                            {unregisteringId === project.id ? (
                              <>
                                <div className="w-3 h-3 border-2 border-[var(--status-error)]/30 border-t-[var(--status-error)] rounded-full animate-spin" />
                                Removing...
                              </>
                            ) : (
                              "Confirm Unregister"
                            )}
                          </Button>
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              ))}
          </div>
        )}
      </div>
    );
  };

  const renderPlaceholder = (title: string) => (
    <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-6">
      <h3 className="text-lg font-semibold">{title}</h3>
      <p className="mt-2 text-xs theme-text-muted">
        This section is ready for organization-level configuration.
      </p>
    </div>
  );

  const renderActiveTab = () => {
    if (activeTab === "projects") {
      return renderProjectsTab();
    }
    if (activeTab === "members") {
      return renderMembersTab();
    }
    if (activeTab === "policies") {
      const hasChanges =
        orgConfig &&
        orgConfigOriginal &&
        JSON.stringify(orgConfig) !== JSON.stringify(orgConfigOriginal);
      const hasValidationErrors = Object.keys(orgValidationErrors).length > 0;

      if (orgConfigLoading) {
        return (
          <div className="flex justify-center py-8">
            <PageLoading
              message="Loading org policies..."
              size="md"
              fullPage={false}
            />
          </div>
        );
      }

      if (!orgConfig) {
        return renderPlaceholder("Policies");
      }

      return (
        <div className="space-y-6">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-lg font-semibold">Policies</h3>
              <p className="text-xs theme-text-muted mt-1">
                Organization defaults for execution behavior.
              </p>
              <span className="inline-flex mt-2 text-[9px] font-bold px-2 py-1 rounded-full border border-[var(--border-muted)] text-[var(--text-muted)] uppercase tracking-[0.18em]">
                Org Scope
              </span>
              {hasChanges && (
                <div className="mt-2 flex items-center gap-2 text-[11px] text-[var(--status-warning)]">
                  <div className="w-1.5 h-1.5 rounded-full bg-[var(--status-warning)] animate-pulse" />
                  <span className="font-mono uppercase">Unsaved changes</span>
                </div>
              )}
            </div>
            <div className="flex items-center gap-2">
              <Button
                onClick={() => {
                  if (orgConfigOriginal) {
                    setOrgConfig(orgConfigOriginal);
                    setOrgValidationErrors({});
                  }
                }}
                variant="ghost"
                size="sm"
                className="text-[10px] font-bold"
                disabled={!hasChanges}
              >
                Reset to Defaults
              </Button>
              <Button
                onClick={saveOrgConfig}
                disabled={!hasChanges || orgConfigSaving || hasValidationErrors}
                size="sm"
                className="text-[10px] font-bold uppercase"
              >
                {orgConfigSaving ? "Saving..." : "Save Defaults"}
              </Button>
            </div>
          </div>

          {orgConfigError && (
            <Alert className="border-[var(--destructive-500)]/30 bg-[var(--destructive-500)]/10 text-[var(--destructive-500)]">
              <AlertDescription className="text-xs text-[var(--destructive-500)]">
                {orgConfigError}
              </AlertDescription>
            </Alert>
          )}

          <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
            <h4 className="text-sm font-bold theme-text-secondary mb-4">
              Executor Defaults
            </h4>
            <div className="space-y-4">
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Max Iterations
                </label>
                <Input
                  type="number"
                  min="1"
                  value={orgConfig.executor.max_iterations}
                  onChange={(e) =>
                    handleOrgExecutorChange(
                      "max_iterations",
                      parseInt(e.target.value) || 0,
                    )
                  }
                  className={
                    orgValidationErrors.max_iterations
                      ? "border-[var(--destructive-500)]/50 focus-visible:ring-[var(--destructive-500)]"
                      : ""
                  }
                />
                {orgValidationErrors.max_iterations && (
                  <p className="mt-1.5 text-[10px] text-[var(--destructive-500)]">
                    {orgValidationErrors.max_iterations}
                  </p>
                )}
              </div>
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Default Mode
                </label>
                <Select
                  value={orgConfig.executor.default_mode}
                  onValueChange={(value) =>
                    handleOrgExecutorChange("default_mode", value)
                  }
                >
                  <SelectTrigger
                    aria-label="Default Mode"
                    className={
                      orgValidationErrors.default_mode
                        ? "border-[var(--destructive-500)]/50 focus-visible:ring-[var(--destructive-500)]"
                        : ""
                    }
                  >
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="planning">Planning</SelectItem>
                    <SelectItem value="building">Building</SelectItem>
                  </SelectContent>
                </Select>
                {orgValidationErrors.default_mode && (
                  <p className="mt-1.5 text-[10px] text-[var(--destructive-500)]">
                    {orgValidationErrors.default_mode}
                  </p>
                )}
              </div>
              <div className="flex items-center justify-between">
                <div>
                  <label className="block text-xs font-bold theme-text-tertiary">
                    Auto Transition
                  </label>
                  <p className="text-[10px] theme-text-muted mt-1">
                    Switch from planning to building automatically
                  </p>
                </div>
                <Switch
                  checked={orgConfig.executor.auto_transition}
                  onCheckedChange={(checked) =>
                    handleOrgExecutorChange("auto_transition", checked)
                  }
                />
              </div>
            </div>
          </div>

          <div className="theme-bg-elevated border border-[var(--border-default)] rounded-xl p-5">
            <h4 className="text-sm font-bold theme-text-secondary mb-4">
              Backpressure Defaults
            </h4>
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <label className="block text-xs font-bold theme-text-tertiary">
                    Enable Backpressure
                  </label>
                  <p className="text-[10px] theme-text-muted mt-1">
                    Run validation between iterations
                  </p>
                </div>
                <Switch
                  checked={orgConfig.backpressure.enabled}
                  onCheckedChange={(checked) =>
                    handleOrgBackpressureChange("enabled", checked)
                  }
                />
              </div>
              <div>
                <label className="block text-xs font-bold theme-text-tertiary mb-2">
                  Max Retries
                </label>
                <Input
                  type="number"
                  min="0"
                  value={(orgConfig.backpressure as any).max_retries || 0}
                  onChange={(e) =>
                    handleOrgBackpressureChange(
                      "max_retries",
                      parseInt(e.target.value) || 0,
                    )
                  }
                  className={
                    orgValidationErrors.max_retries
                      ? "border-[var(--destructive-500)]/50 focus-visible:ring-[var(--destructive-500)]"
                      : ""
                  }
                />
                {orgValidationErrors.max_retries && (
                  <p className="mt-1.5 text-[10px] text-[var(--destructive-500)]">
                    {orgValidationErrors.max_retries}
                  </p>
                )}
              </div>
            </div>
          </div>
        </div>
      );
    }
    const tab = ORG_TABS.find((entry) => entry.id === activeTab);
    return renderPlaceholder(tab?.label || "Settings");
  };

  return (
    <div className="flex-1 flex flex-col theme-bg-base overflow-hidden">
      <div className="bg-[var(--bg-base)] px-6 pt-8 pb-2">
        <div className="max-w-5xl mx-auto">
          <div className="flex items-start justify-between gap-6">
            <div>
              <h1 className="text-2xl font-semibold theme-text-primary">
                Organization Settings
              </h1>
              <p className="mt-2 text-xs theme-text-muted">
                {organizationName || "Organization"}
              </p>
              {roleLabel && (
                <span className="inline-flex mt-2 text-[10px] font-bold px-2 py-1 rounded-full border border-[var(--border-muted)] text-[var(--text-muted)]">
                  {roleLabel}
                </span>
              )}
            </div>
            <Button onClick={onBack} variant="ghost" size="sm">
              Back to Projects
            </Button>
          </div>
          <div className="mt-6 border-b border-[var(--border-default)]">
            <Tabs
              value={activeTab}
              onValueChange={(value) => setActiveTab(value as OrgTab)}
            >
              <TabsList
                variant="line"
                className="w-full justify-start gap-6 overflow-x-auto overflow-y-hidden whitespace-nowrap"
              >
                {ORG_TABS.map((tab) => (
                  <TabsTrigger
                    key={tab.id}
                    value={tab.id}
                    variant="line"
                    className="text-sm font-medium whitespace-nowrap"
                  >
                    {tab.label}
                  </TabsTrigger>
                ))}
              </TabsList>
            </Tabs>
          </div>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto custom-scrollbar p-8 theme-bg-base">
        <div className="max-w-5xl mx-auto">{renderActiveTab()}</div>
      </div>
    </div>
  );
};

export default OrganizationSettingsScreen;
