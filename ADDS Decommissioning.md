# AD DS Decommissioning Runbook (Hybrid → Cloud-only) — Checklist

> Assumption: 2 DCs (AD DS + DNS), one hosts Entra Connect sync. End goal: retire on‑prem AD DS/DCs and stop directory sync so objects become cloud‑only.

---

## Phase 0 — Discovery + Decision Gates (Before any change)

- [ ] Confirm target state (cloud-only identities vs retain any on-prem identity services)
- [ ] Confirm there are **no remaining dependencies** on AD DS (apps, file shares, Wi‑Fi/RADIUS, VPN, LDAP/Kerberos, NAS, printers, SQL logins)
- [ ] Confirm DNS plan (what will provide internal DNS after DC removal)
- [ ] Confirm break-glass access in Entra (at least 2 emergency accounts, tested)
- [ ] Confirm rollback plan and maintenance window(s)

---

## Phase 1 — Prepare AD DS for Retirement

### 1.1 Validate DC health (must be clean before demotion)

- [ ] Verify replication health and DC status (errors resolved)
- [ ] Ensure both DCs are online and stable

### 1.2 FSMO roles (ensure you know where they are before you start)

- [ ] Record current FSMO role holders  
  Learn: https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/view-transfer-fsmo-roles
- [ ] If needed, transfer FSMO roles to the intended “last DC” (or planned holder)  
  Learn: https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/manage-fsmo-roles

### 1.3 DNS readiness

- [ ] Inventory DNS zones hosted on DCs (AD-integrated + any non-AD zones)
- [ ] Identify forwarders / conditional forwarders needed post-DC
- [ ] Decide replacement internal DNS service (router/firewall, Windows DNS non-DC, etc.)
- [ ] Update DHCP option 006 (DNS servers) plan for cutover

---

## Phase 2 — Make Cloud the Authority (Stop DirSync) — Cutover Prereqs

### 2.1 Confirm cloud object management approach

- [ ] Confirm how users will be created post-cutover (cloud-only creation process)
- [ ] Confirm how groups will be managed post-cutover (cloud-only; plan for mixed-origin groups)
- [ ] Confirm any attributes currently managed on-prem that must be moved to cloud processes

### 2.2 Turn off directory synchronization (Tenant change)

- [ ] Schedule a change window (this is the “point of no return” for hybrid identity)
- [ ] Turn off directory synchronization so synced users/groups become cloud-only  
  Learn: https://learn.microsoft.com/en-us/microsoft-365/enterprise/turn-off-directory-synchronization?view=o365-worldwide
- [ ] Validate in tenant that DirSync is disabled and objects are manageable in Entra/M365 admin

### 2.3 Decommission the sync server component

- [ ] Identify whether sync is **Entra Connect Sync** (classic) or **Cloud Sync**
- [ ] Stop sync processes/services (per tenant plan) and remove/uninstall the sync tooling (server-side)
- [ ] Confirm no further sync cycles occur and no unexpected object changes appear in cloud

---

## Phase 3 — Demote Domain Controllers (On-Prem Retirement)

> Recommended order (typical): demote the **non-critical/secondary DC first**, leave the best-known/healthiest DC as the last one until final.

### 3.1 Demote the first DC

- [ ] Ensure it is **not** holding critical FSMO roles (or transfer them off first)
- [ ] Demote the DC using Server Manager / AD DS role removal  
  Learn: https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/demoting-domain-controllers-and-domains--level-200-
- [ ] Validate:
  - [ ] Clients are no longer using it for DNS
  - [ ] No authentication issues appear

### 3.2 Demote the last DC

- [ ] Confirm again: no remaining AD DS dependencies
- [ ] Confirm DNS cutover is complete (clients no longer point at DC DNS)
- [ ] Demote final DC  
  Learn: https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/demoting-domain-controllers-and-domains--level-200-

---

## Phase 4 — Post-Demotion Cleanup

### 4.1 AD metadata cleanup (only if demotion was not clean)

- [ ] If a DC was removed unexpectedly / demotion failed, perform metadata cleanup  
  Learn: https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/ad-ds-metadata-cleanup

### 4.2 DNS cleanup

- [ ] Remove stale DNS records for DCs
- [ ] Remove old forwarders/conditional forwarders no longer needed
- [ ] Confirm internal name resolution works for business services

### 4.3 Documentation + final validation

- [ ] Confirm user lifecycle is fully cloud-only (create/modify/disable works as required)
- [ ] Confirm group management is cloud-only and consistent
- [ ] Confirm device auth works for all endpoints (Intune/Autopilot devices)
- [ ] Confirm access to any on-prem resources still required (if any remain)
- [ ] Update runbooks/diagrams and record final state

---

## Phase 5 — Decommission Servers (Optional)

- [ ] If DC VMs are no longer required: remove from monitoring/backup
- [ ] Archive logs/config exports if required by policy
- [ ] Deallocate/delete VMs (or repurpose after hardening and role removal)

---

## Evidence Pack (Suggested artefacts to capture)

- [ ] Screenshot/export: current DirSync state before + after disabling  
  Learn: https://learn.microsoft.com/en-us/microsoft-365/enterprise/turn-off-directory-synchronization?view=o365-worldwide
- [ ] Record FSMO role holders before changes  
  Learn: https://learn.microsoft.com/en-us/troubleshoot/windows-server/active-directory/view-transfer-fsmo-roles
- [ ] Change record: DC demotion completion proof  
  Learn: https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/demoting-domain-controllers-and-domains--level-200-
- [ ] If used: metadata cleanup completion notes  
  Learn: https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/ad-ds-metadata-cleanup
