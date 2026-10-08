# Migrate-NeologikEnvironment.ps1: What the Script Does

## Overview

`Migrate-NeologikEnvironment.ps1` is the migration script. A Global Administrator runs the migration script, signed in with the account of the Global Administrator. Neologik asks for a run on two occasions.

| Run | When Neologik asks for the run | What the migration script does |
|---|---|---|
| The first run | Before an existing environment moves to version 5 of the Neologik Platform | Confirms the directory objects that the Neologik Platform uses, and the roles and permissions that the deployment identity needs. Removes nothing |
| The later run | After Neologik has deployed and proven the environment | Reduces the access of the deployment identity to the roles that the deployment identity needs |

The first run removes nothing. The deployment identity keeps the access it holds today until the later run. Between the two runs, Neologik can put right a failed first run or a failed deployment with that access. Neologik then needs no further request to you.

Neologik sends the complete command, with every value filled in. You supply the sign-in.

The migration script reads the current state before each change. The migration script changes only what differs from the expected state. A Global Administrator can run the migration script again at any time. With `-Verify` the migration script reports each change that a run would make, and writes nothing.

The grants for agents and Apps that work unattended in Microsoft 365 are not part of the migration script. A Global Administrator applies them with the grants script of the onboarding kit, `Grant-NeologikAgentAccess.ps1`, and the files that the Neologik Context Engine exports.

## Contents

1. [What you need](#what-you-need)
2. [How to run the migration script](#how-to-run-the-migration-script)
3. [The first run](#the-first-run)
4. [The later run](#the-later-run)
5. [What the migration script never does](#what-the-migration-script-never-does)
6. [What the sign-in asks you to approve](#what-the-sign-in-asks-you-to-approve)
7. [What you receive](#what-you-receive)
8. [Questions](#questions)
9. [Help](#help)

## What you need

| Requirement | Reason |
|---|---|
| PowerShell 7.4 or later | The migration script stops on an earlier version |
| A Global Administrator account in your tenant | Only a Global Administrator can grant and remove Microsoft Graph application permissions and directory roles |
| Owner or User Access Administrator on the subscription | The same account changes the Azure role assignments of the deployment identity |
| The command from Neologik | The command names your tenant, your subscription, your resource group, the application registrations of the environment and the version of the onboarding kit that the migration brings your environment to |

The migration script installs the PowerShell modules that the run needs, for your user account, when the modules are missing: the Microsoft Graph modules and the Az modules.

Before the migration script changes anything, the migration script confirms three facts.

1. The workstation can reach each Microsoft address that the migration script uses.
2. The PowerShell modules load.
3. The signed-in account holds an active Global Administrator role.

Each run makes one more check before the run changes an Azure role. The signed-in account must hold Owner or User Access Administrator on the subscription.

## How to run the migration script

1. Place the migration package in a folder on your workstation. The first run reads `NeologikGuestUsers.txt` from the folder of `Migrate-NeologikEnvironment.ps1`.
2. Open PowerShell 7 in that folder.
3. Paste the command from Neologik and press Enter.
4. The migration script prints a web address and a code. Open the web address in a browser on any device, enter the code and sign in as a Global Administrator who also holds Owner or User Access Administrator on the subscription. The account picker may offer another account that is a Global Administrator but holds no role on the subscription, such as a guest account; the Azure steps are skipped for that account and the run must be repeated. The migration script waits for up to 15 minutes.
5. The migration script signs in a second time, to Azure, with a second code. Sign in with the same account.
6. Read the summary table on screen and the list `FILES TO SEND TO NEOLOGIK` under it. Send the files to Neologik, unless the list says that the run uploaded them.

The command names the version of the onboarding kit that the migration brings your environment to, with `-KitVersion`. The migration script records that version on your resource group at the end of each run. The Neologik Platform reads the record before an upgrade.

To see what a run would change, add `-Verify` to the end of the command. The sign-ins are the same. The migration script reports each pending change as `WOULD` and writes nothing.

## The first run

The command selects the first run when the command does not name `-LaterRun`. The first run has five steps. The migration script checks each item of a step separately. When an item fails, the migration script records the item and the reason in the summary and continues. The first run removes nothing.

### Step 1: The agent identity blueprint and the permissions of the deployment identity

| Item | What the migration script checks | When the migration script changes the item |
|---|---|---|
| The agent identity blueprint, `Neologik Agent Blueprint - default - <short name>` | The agent identity blueprint exists | The migration script creates the agent identity blueprint when the agent identity blueprint is absent |
| The service principal of the agent identity blueprint | The service principal exists | The migration script creates the service principal when the service principal is absent |
| Owner | The deployment identity owns the agent identity blueprint and the service principal | The migration script adds the deployment identity as an owner when the deployment identity is not an owner |
| Sponsor | The agent identity blueprint has a sponsor. The sponsor is the person who is accountable for the agents of the environment. The summary names the sponsor | The migration script adds the signed-in Global Administrator as the sponsor when the agent identity blueprint has no sponsor |
| The permission of the service principal | The service principal holds `AgentIdUser.ReadWrite.IdentityParentedBy`. The permission covers only the agent users of this agent identity blueprint | The migration script grants the permission when the permission is absent |
| The federated credentials | The agent identity blueprint holds the three federated credentials through which the Neologik deployment signs in as the agent identity blueprint | The migration script adds a federated credential when the federated credential is absent |
| The permissions that the deployment identity keeps | The deployment identity holds `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` | The migration script grants a permission when the permission is absent. The first run removes no permission. The later run removes the seven permissions listed under step 6 |

The deployment identity can already own one agent identity blueprint with another short name. The migration script then uses that agent identity blueprint and creates no second one. The summary then names the agent identity blueprint that the migration script used.

### Step 2: The security groups, the Neologik guest users and the memberships

Version 5 of the Neologik Platform uses four security groups in your tenant. An environment set up before version 5 has two of them. The migration script completes the set.

| Item | What the migration script checks | When the migration script changes the item |
|---|---|---|
| `Neologik User Group - <short name>` | The group exists | The migration script creates the group when the group is absent |
| `Neologik NCE Contributors - <short name>` | The group exists under this name. The group is the user group of the Neologik Context Engine | The migration script renames `Neologik NCE User Group - <short name>` to this name. The group keeps the id and the members. The migration script creates the group when no group exists under either name |
| `Neologik NCE Admins - <short name>` | The group exists. Members of the group administer the Neologik Context Engine | The migration script creates the group when the group is absent |
| `Neologik Admin User Group - <short name>` | The group exists | The migration script creates the group when the group is absent |
| The Neologik support accounts | Each mail address in `NeologikGuestUsers.txt` is a guest of your tenant | The migration script invites an account that is absent. Microsoft sends the invitation |
| The memberships | Each guest and the signed-in administrator are direct members of every one of the four groups | The migration script adds a membership that is absent. The migration script removes no member |

When the command names a group by id, the id decides, whatever the name of the group. When the command names no id, the migration script finds the group by name.

The summary item `NCE Admins group` states the id of the group. Neologik records the id for the environment, so that members of the group hold the administrator role in the Neologik Context Engine.

When `NeologikGuestUsers.txt` is not beside the migration script, the summary reports the item `Neologik guest users` as `SKIPPED`. Run the migration script from the folder of the migration package, or add `-GuestUsersFile <path>` to the command.

### Step 3: The role groups of the Neologik Context Engine

The Neologik Context Engine reads the groups claim of the sign-in token to authorise a user. The groups claim lists only the security groups that are assigned to the Platform Sign-in application. The migration script assigns the user group that the command names, and the group `Neologik NCE Admins - <short name>`, to the application `Neologik Platform Sign-in - <short name>`, when an assignment is absent.

A user must be a direct member of the security group. A member of a nested group cannot sign in. The migration script reports the number of direct members.

### Step 4: Consent and ownership

| Item | What the migration script checks | When the migration script changes the item |
|---|---|---|
| Administrator consent for the Platform Sign-in application | The consent for the whole tenant exists | Never. When the consent is absent, the migration script prints the consent address. A Global Administrator opens the consent address and gives the consent. Run the migration script again afterwards to confirm the consent |
| Consent for the SharePoint application | The SharePoint application of the environment holds the Microsoft Graph application permission `Sites.Selected` | When an earlier SharePoint application of Neologik in your tenant holds a SharePoint permission. A consent belongs to one application, so the migration script grants `Sites.Selected` to the SharePoint application of the environment. When no application holds a SharePoint permission, the migration script grants nothing. When the configuration file records SharePoint ingestion, the migration script then prints the consent address |
| Ownership of the application registrations | The deployment identity owns each application registration that the command names by client id, and the service principal of each. The command names the Platform Sign-in application, the SharePoint application and the application registration of each agent | The migration script adds the deployment identity as an owner when the deployment identity is not an owner |
| Unique name | The Platform Sign-in application and the SharePoint application hold the unique name by which the deployment finds each application | The migration script sets the unique name when the unique name is empty. The migration script reports another value and changes nothing |
| Client secrets | Each named application registration is read for client secrets that the deployment did not create | Never. The summary lists each such client secret. See below |
| Other application registrations | Every other application registration whose name begins `Neologik` | Never. The summary lists each such application registration as `Review`, so that you and Neologik can confirm that the command missed none |

The deployment replaces the client secrets of the Platform Sign-in application and of the application registration of each agent. When one of these application registrations holds a client secret that the deployment did not create, the summary lists the client secret as `PENDING`. Confirm with Neologik that nothing else uses the client secret before the upgrade.

### Step 5: The Azure roles of the deployment identity

The migration script confirms that the deployment identity holds ten Azure roles. The migration script assigns a role that is absent and removes nothing.

| Scope | Roles |
|---|---|
| Resource group | Contributor<br>Key Vault Certificates Officer<br>Key Vault Secrets Officer<br>Storage Blob Data Contributor<br>Azure Kubernetes Service RBAC Cluster Admin<br>Monitoring Contributor<br>Role Based Access Control Administrator |
| Subscription | Reader<br>Cost Management Contributor<br>Role Based Access Control Administrator, limited to assigning two roles: Reader and AppGw for Containers Configuration Manager |

The deployment runs the ingress controller of a secure environment with Application Gateway for Containers. Microsoft requires the identity of that controller to hold two roles. The first is Reader on the resource group that Azure Kubernetes Service creates for the nodes of the cluster. That resource group is outside the resource group of the environment. The second is AppGw for Containers Configuration Manager on the resource group of the environment. The condition on the role lets the deployment identity assign those two roles and no other role. The deployment identity may already hold Role Based Access Control Administrator on the subscription without the condition. The first run then reports `Already assigned without the limit` and keeps the role, because the first run removes nothing. The later run writes the condition onto that assignment and reports `Limit applied`.

When the deployment identity holds all ten roles, the migration script records the version of the onboarding kit that the command names on the resource group. The record is the tag `NeologikOnboardingKit`. The migration script keeps your other tags and writes the tag only when the value differs. The Neologik Platform reads the tag before an upgrade.

The first run changes nothing on a managed identity, on a security group or on a user. The first run removes no role, no permission and no membership.

### Step 5a: The Azure quotas that the migration needs

The migration script reads three quotas of your subscription, in the region of the environment, and changes nothing. A quota that is short needs attention before the migration, because the quota comes from Microsoft and takes days.

| Quota | Why the migration needs it | What the summary says |
|---|---|---|
| App Service Y1 instances | The schedule that starts and stops the cluster outside working hours runs as a Function App on a consumption plan, one Y1 instance | `Present: <n>`, or `SHORT: 0` with the Azure portal path to request the quota. Without the quota, Neologik runs the cluster without the schedule |
| vCPUs of the node pool family and of the region | The cluster may grow to the maximum node count of each pool, and the upgrade of the cluster adds one node per pool while it runs | `Present` with the use, the limit and the growth the cluster may need, or `SHORT` |
| Azure OpenAI model quota | The Neologik Platform uses the models on the Foundry account. A model deployed only on the classic Azure OpenAI account is deployed on the Foundry account before the migration, within the regional quota of the model | `Model deployments on Foundry` lists what the Foundry account holds. One line per model to move: `Fits`, or `SHORT` with the free quota and the capacity the move needs |

A read that Azure refuses reports `Review` with the reason, and the run continues.

## The later run

The command selects the later run with `-LaterRun`. Neologik asks for the later run once Neologik has deployed and proven the environment. The later run makes none of the checks of the first run.

### Step 6: Permission reduction

The migration script first confirms the two Microsoft Graph application permissions that the deployment identity keeps, and the ten Azure roles of step 5. The migration script assigns a role or grants a permission that is absent. The migration script writes the limit onto a Role Based Access Control Administrator assignment on the subscription that lacks it. The migration script removes the wider access only when the deployment identity holds all of them. When the migration script cannot assign one of the ten roles, the migration script removes nothing. The deployment never loses access part way through the run.

| What the migration script removes | Condition |
|---|---|
| Seven Microsoft Graph application permissions:<br>`Application.Read.All`<br>`AgentIdentityBlueprint.Create`<br>`AgentIdentityBlueprint.UpdateAuthProperties.All`<br>`AgentIdentityBlueprintPrincipal.Create`<br>`AgentIdentity.Create.All`<br>`AgentIdUser.ReadWrite.All`<br>`Group.Create` | The deployment identity holds the permission |
| Contributor and User Access Administrator on the subscription | The deployment identity holds the role |
| The directory role Application Administrator | The deployment identity holds the role |
| The membership of the group `Neologik Admin User Group - <short name>` | The deployment identity is a member, and each SQL server in the resource group names the deployment identity as the Microsoft Entra administrator. Until then the migration script keeps the membership, because the membership is the only access of the deployment identity to SQL. The summary then reads `HELD` |
| Every other Azure role in the subscription | The role is outside the ten roles of step 5. The migration script keeps the role `Cognitive Services Content Understanding Contributor` on a resource in the resource group |
| Every other directory role | The deployment identity holds the role |
| Every other group membership | The deployment identity is a member |

Last, the migration script records the version of the onboarding kit on the resource group, in the tag `NeologikOnboardingKit`.

## What the migration script never does

- The migration script never reads, moves or deletes your data. The migration script reads directory objects and Azure role assignments.
- The migration script never changes an application registration that the command does not name.
- The migration script never creates a user or a secret.
- The migration script never gives administrator consent. The migration script prints the consent address. You decide.
- The migration script never removes a wider role before the deployment identity holds the roles that replace the wider role.
- The migration script never grants access to an agent or an App. The grants script of the onboarding kit does that.
- The migration script never sends anything to Neologik other than the files of the run, to a storage account of your environment. You send the files when the upload does not happen.
- The migration script never stores your sign-in.

## What the sign-in asks you to approve

The migration script signs in to Microsoft Graph with your account. At the first use, Microsoft lists the permissions that the migration script requests. Each permission is a delegated permission. A delegated permission works as you, for the run only. The sign-in grants nothing to an application.

| Permission | Requested in | What the migration script uses the permission for |
|---|---|---|
| `Application.ReadWrite.All` | Every run | To read the application registrations. To add the owner and the unique name. To add the federated credentials of the agent identity blueprint. To read and to add the sponsor of the agent identity blueprint |
| `AppRoleAssignment.ReadWrite.All` | Every run | To grant and remove Microsoft Graph application permissions, and to assign the security groups to the Platform Sign-in application |
| `Directory.Read.All` | Every run | To read the service principals, the groups and the directory roles |
| `User.Read` | Every run | To identify your account |
| `DelegatedPermissionGrant.Read.All` | Every run | To read the consent of the Platform Sign-in application |
| `AgentIdentityBlueprint.Create`<br>`AgentIdentityBlueprint.AddRemoveCreds.All`<br>`AgentIdentityBlueprintPrincipal.Create` | Every run | To create the agent identity blueprint, the service principal and the federated credentials when each is absent |
| `GroupMember.ReadWrite.All` | The first run | To add the Neologik guest users and the signed-in administrator to the security groups |
| `Group.ReadWrite.All` | The first run | To create a security group of version 5 that is absent, and to rename the user group of the Neologik Context Engine |
| `User.Invite.All` | The first run | To invite a Neologik support account that is not yet a guest of your tenant |
| `AgentIdentityBlueprintPrincipal.ReadWrite.All` | The first run | To add the deployment identity as an owner of the service principal of the agent identity blueprint. The migration script adds the owner when that service principal has none |
| `RoleManagement.ReadWrite.Directory` | The later run | To remove directory roles from the deployment identity |
| `GroupMember.ReadWrite.All` | The later run | To remove the deployment identity from groups |

The sign-in to Azure uses the same account and shows no list of permissions.

## What you receive

The migration script prints a summary table. The migration script writes three files in the folder of the migration script.

| File | Name | Content |
|---|---|---|
| The log file | `NeologikEnvironmentMigration_<date and time>.log` | Every message of the run, from the first line. Each failed request to Microsoft Graph, with its status and the request id by which Microsoft can find the request. The summary table |
| The summary file of the first run | `Neologik_EnvironmentMigration_PreWindow_<date and time>.json` | The summary of the run, see below |
| The summary file of the later run | `Neologik_EnvironmentMigration_PostWindow_<date and time>.json` | The summary of the run, see below |
| The snapshot file | `Neologik_EnvironmentMigration_Snapshot_Pre_<date and time>.json` after the first run, `..._Post_...` after the later run | The state that the run leaves. For each application registration: the owners, the unique name, the kinds and expiry dates of credentials, the permissions and the consents. For the deployment identity: the Azure roles and the group memberships. For each security group: the member count. Every item of the summary. No secret value. Neologik compares the Pre and the Post snapshot to confirm that the upgrade changed what the upgrade was meant to change, and nothing else |

The migration script writes the summary file on every exit, a run that stopped before its steps included. The migration script writes to the current folder when the folder of the migration script is not writable. The migration script writes to the temporary folder when the current folder is not writable.

The run ends with the list `FILES TO SEND TO NEOLOGIK`, which names each file with its full path.

The migration script also uploads the three files, with your Azure session. The first choice is the storage account that the onboarding created, named `stneodeploy...`, into the containers `logs` and `json`. When that storage account does not exist or does not take the files, the second choice is the storage account that the command from Neologik names with `-UploadStorageAccountName`, container `onboarding-access`. The storage accounts of the Neologik Platform refuse shared keys, so the upload needs the role Storage Blob Data Contributor. When a storage account refuses the first upload, the migration script assigns that role on the storage account to your account and tries again while the role takes effect. The list at the end names the uploaded files too. A storage account behind a private endpoint cannot be reached from your workstation. The files then stay on your workstation, the list says so, and you send the files to Neologik.

The summary file holds these things:

- the version of the migration script and the version of the onboarding kit
- the tenant id
- the client id of the deployment identity
- the signed-in account
- the time of the run
- the Microsoft Graph application permissions that the deployment identity holds
- the ids of the two role groups of the Neologik Context Engine, after the first run
- every item of the summary
- the path of the log file, and the reason when the run stopped before its steps

No file holds a secret.

| Result | Meaning |
|---|---|
| `Present`, `Already granted`, `Already assigned`, `Already an owner`, `Already set`, `None`, `Not held`, `None from another source` | Nothing to change |
| `Created`, `Added`, `Granted`, `Assigned`, `Set`, `Removed`, `Limit applied` | Changed in this run |
| `Review` | Listed for you to read. The migration script changed nothing |
| `Not checked`, `Not needed`, `Not listed`, `Not required`, `HELD` | The item did not apply to this run, or the migration script keeps the item on purpose. The row gives the reason |
| `WOULD` | A change that a run without `-Verify` would make |
| `MISSING`, `SKIPPED`, `NOT FOUND`, `PENDING`, `UNKNOWN`, `FAILED` | Needs attention. The row gives the reason |

| Exit code | Meaning |
|---|---|
| 0 | Every item is in the expected state |
| 1 | An item needs attention. With `-Verify`, a change is pending |

## Questions

**Does the first run give Neologik more access?**

The first run adds only a role or a permission that is absent from the set listed in this document, and removes nothing. The deployment identity keeps the wider access it held before the run until the later run. The later run removes that wider access, so that the deployment identity ends with the access listed in this document and nothing else.

**Why does the first run keep the wider access until the later run?**

Neologik deploys the new version of the environment between the two runs. When a step of the first run or of the deployment fails, Neologik puts the step right. The deployment identity still holds the access for that, so Neologik needs no further request to you. Once the environment is proven, the later run removes the wider access.

**Why does my account need such wide permissions?**

Only a Global Administrator can remove a directory role or grant a Microsoft Graph application permission. The migration script uses your sign-in for the run. The sign-in grants nothing to your account and stores nothing.

**What happens when an item is already in the expected state?**

The migration script reports the item and moves to the next item. A second run on an environment in the expected state changes nothing.

**What happens when an item fails?**

The migration script records the failure with the reason, continues with the other items and ends with exit code 1. Send the files that the list at the end names to Neologik, unless the run uploaded them.

**Why does the summary list application registrations that the migration script did not change?**

The deployment identity manages only the application registrations that the deployment identity owns. The migration script adds the deployment identity as an owner of exactly the application registrations that the command names. The summary lists every other application registration whose name begins `Neologik`, so that you and Neologik can confirm that the command missed none.

## Help

Email support@neologik.ai with the files that the list at the end of the run names. Give the name of your organisation and the host name of the environment.
