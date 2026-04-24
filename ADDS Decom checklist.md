# AD DS Decommissioning Plan + Checklist (Hybrid → Cloud-only)

**Target state:** Full cloud (Entra ID only), remove both on-prem DCs (Server 2016), no on-prem Exchange, no AD-integrated apps/LDAP/Kerberos dependencies, endpoints managed by Intune/Autopilot.  
**Target completion:** By end of Q4 / June 2026 (per client timeline).  
**Primary success criteria:** “Decommission both DCs and operate fully in cloud with no loss of service.” (Sign-off: John Lightbody)

---

## Phase 0 — Confirm Unknowns + Close Gaps (Mandatory before any cutover)

### 0.1 Identity + Directory sync facts (close “unknowns”)
- [ ] Confirm **sync product**: Entra Connect Sync vs Cloud Sync (questionnaire says “Yes” but not which)  
- [ ] Confirm **authentication method** definitively (PHS vs PTA) (they “think PHS”)  
- [ ] Confirm **what is writeback-enabled** (questionnaire says “Yes” but details unclear)
- [ ] Identify any **service accounts / non-human identities** (questionnaire: “Possibly”)
- [ ] Identify the **authoritative identity decision** post-project:
  - [ ] Users created directly in Entra ID (cloud-only)
  - [ ] Groups managed directly in Entra/M365 (cloud-only)

### 0.2 Security guardrails (reduce risk of “loss of access to O365”)
- [ ] Confirm **2 break-glass Entra accounts** exist and are tested (questionnaire left blank)
- [ ] Implement **baseline Conditional Access** (currently “No”) appropriate to tenant (at minimum: require MFA for admins; block legacy auth)  
  (If you want, I can add a recommended minimal CA checklist.)
- [ ] Confirm MFA enforcement approach (they said “via O365 Entra”)—document how

### 0.3 Endpoint join state (must be confirmed because “possibly domain-joined/hybrid-joined”)
- [ ] Inventory devices: Azure AD joined vs Hybrid Azure AD joined vs Domain joined
- [ ] Confirm there are **no domain-joined servers** (questionnaire: “No”) and validate

### 0.4 AD DS health + roles
- [ ] Record FSMO role holders and plan role transfers if needed  
  Learn: https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/manage-fsmo-roles :contentReference[oaicite:1]{index=1}
- [ ] Confirm AD functional level (currently “Unknown”) and document
- [ ] Confirm DC demotion prerequisites are met (replication healthy, no errors)

---

## Phase 1 — Design (Decommission Runbook + Go/No-Go)

### 1.1 Produce and agree the change plan
- [ ] Define change windows (client says “can be arranged”)
- [ ] Define rollback stance: “Only if loss is experienced” (document what “acceptable loss” means)
- [ ] Define comms plan + who is on the bridge during changes
- [ ] Define verification tests (see Phase 4 verification checklist)

### 1.2 DNS plan (DCs not only DNS; Route53 noted)
- [ ] Confirm current client DNS settings (DHCP + static)
- [ ] Confirm what resolves internal names today and after DC removal
- [ ] Confirm no internal AD-integrated zones are required post-removal

---

## Phase 2 — Directory Sync Retirement (Recommended order: uninstall sync client first, then disable DirSync)

> Microsoft guidance warns that disabling DirSync before removing the sync client can leave optional features appearing enabled; recommended approach is to uninstall the sync client first, then disable directory synchronization. :contentReference[oaicite:2]{index=2}

### 2.1 Pre-cutover checks (must pass)
- [ ] Confirm break-glass admin access works
- [ ] Confirm tenant admin access and roles required are available
- [ ] Confirm no active dependency on password writeback is required post-cutover (they currently have password writeback enabled)
- [ ] Snapshot/backup the sync server (if separate) / DC VM that hosts sync (questionnaire: “hosting company snapshot and vault standard”)

### 2.2 Uninstall / remove Entra Connect (or Cloud Sync) on the sync server
- [ ] Identify the sync server (questionnaire: one DC “doing sync”)
- [ ] If **Entra Connect Sync**: Uninstall Microsoft Entra Connect from the server  
  Learn: https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-uninstall :contentReference[oaicite:3]{index=3}
- [ ] If **Cloud Sync**: remove/disable provisioning agents and configuration (document exact approach used)

### 2.3 Disable directory synchronization in Microsoft 365 tenant
- [ ] Turn off directory synchronization in the tenant (this converts synced users/groups to cloud-only management)  
  Learn: https://learn.microsoft.com/en-us/microsoft-365/enterprise/turn-off-directory-synchronization?view=o365-worldwide :contentReference[oaicite:4]{index=4}
- [ ] Validate in Entra/M365 admin center:
  - [ ] Synced objects become editable as expected
  - [ ] Group management behaves as intended
  - [ ] No unexpected reappearance of deleted objects (indicates sync still running somewhere)

### 2.4 Decommission writeback settings (if still configured)
- [ ] If password writeback was enabled, disable on-prem integration settings that are no longer relevant  
  Learn (concept): https://learn.microsoft.com/en-us/entra/identity/authentication/concept-sspr-writeback :contentReference[oaicite:5]{index=5}

---

## Phase 3 — AD DS / DC Decommission (Demote both DCs)

> DC OS: Windows Server 2016 Datacenter (supported by the demotion guidance). :contentReference[oaicite:6]{index=6}

### 3.1 Pre-demotion checks (must pass)
- [ ] Confirm no domain-joined servers exist (validate)
- [ ] Confirm no apps/services authenticate against AD DS (questionnaire indicates none)
- [ ] Confirm clients are not using DCs as primary DNS (or have alternate resolvers in place)
- [ ] Confirm FSMO roles plan (where they will go during demotion sequence)

### 3.2 Demote DC #1 (non-sync DC first, if possible)
- [ ] Ensure DC #1 is not holding critical FSMO roles (transfer if required)
- [ ] Demote DC using Server Manager/PowerShell  
  Learn: https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/demoting-domain-controllers-and-domains--level-200- :contentReference[oaicite:7]{index=7}
- [ ] Post-demotion validation:
  - [ ] Authentication still works (cloud sign-in / device sign-in)
  - [ ] DNS resolution stable
  - [ ] No service outages reported

### 3.3 Demote DC #2 (final DC)
- [ ] Final dependency check (repeat Phase 3.1 quickly)
- [ ] Demote final DC  
  Learn: https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/demoting-domain-controllers-and-domains--level-200- :contentReference[oaicite:8]{index=8}

### 3.4 If demotion fails / forced removal required (fallback)
- [ ] Perform AD DS metadata cleanup (only if needed)  
  Learn: https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/ad-ds-metadata-cleanup :contentReference[oaicite:9]{index=9}

---

## Phase 4 — Post-Change Verification (What to test, and when)

### 4.1 Immediate smoke tests (during the change window)
- [ ] Admins can sign into Microsoft 365 admin center
- [ ] Admins can sign into Entra admin center
- [ ] Test user can:
  - [ ] Sign into M365 (web)
  - [ ] Sign into device (Autopilot/Azure AD joined scenario)
  - [ ] Reset password (SSPR) and sign in again (if SSPR is used)
- [ ] Create a new user **cloud-only** and assign a licence; verify sign-in
- [ ] Create/modify a group in Entra/M365; verify membership + mail delivery if relevant

### 4.2 24–72 hour stabilisation checks
- [ ] Confirm no sync-related errors (because sync tooling is removed)
- [ ] Confirm support desk processes for joiner/mover/leaver are updated and working
- [ ] Confirm no residual references to AD DS in tooling/monitoring
- [ ] Confirm backups/monitoring updated to remove DC-specific items

---

## Phase 5 — Decommission Infrastructure (After stabilisation)

- [ ] Remove DC VMs from backup schedules (if retained)
- [ ] Remove DC VMs from monitoring/alerting
- [ ] Archive configuration/evidence pack for audit
- [ ] Deallocate/delete VMs (or repurpose after hardening)

---

## Evidence Pack (capture for sign-off)
- [ ] Evidence that directory sync is disabled (tenant setting)  
  Learn: https://learn.microsoft.com/en-us/microsoft-365/enterprise/turn-off-directory-synchronization?view=o365-worldwide :contentReference[oaicite:10]{index=10}
- [ ] Evidence of Entra Connect removal (screenshots / add-remove programs / change record)  
  Learn: https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-uninstall :contentReference[oaicite:11]{index=11}
- [ ] DC demotion logs/screenshots for each DC  
  Learn: https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/demoting-domain-controllers-and-domains--level-200- :contentReference[oaicite:12]{index=12}
- [ ] Post-change verification results + sign-off from John Lightbody

---