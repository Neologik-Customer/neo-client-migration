# Migrate-NeologikEnvironment.ps1: Technical Breakdown

## Overview

This document is for approvers of the migration script, `Migrate-NeologikEnvironment.ps1`. An approver is a person who reviews a script before an administrator runs the script.

This document lists each sign-in, each permission, each write to the directory, each write to Azure and each file. This document also lists what the migration script never does. [MIGRATION-SCRIPT-GUIDE.md](MIGRATION-SCRIPT-GUIDE.md) describes each step for the administrator who runs the script.

### What the migration script does

The migration script moves one existing Neologik Platform environment to version 5 of the Neologik Platform. A Global Administrator who also holds Owner or User Access Administrator on the subscription runs the migration script twice.

| Run | Writes |
|---|---|
| The first run | Creates a directory object or a role assignment that is absent. Removes nothing |
| The later run | Removes the access that the deployment identity no longer needs. Creates a role assignment that is absent first |

### What the deployment identity holds after the later run

| Subject | Position |
|---|---|
| Resource group | Seven roles: Contributor, Key Vault Certificates Officer, Key Vault Secrets Officer, Storage Blob Data Contributor, Azure Kubernetes Service RBAC Cluster Admin, Monitoring Contributor and Role Based Access Control Administrator |
| Subscription | Three roles: Reader, Cost Management Contributor, and Role Based Access Control Administrator limited by a condition to assigning three roles, Reader, AppGw for Containers Configuration Manager and Cost Management Reader. None of the three allows a change to an Azure resource |
| A resource in the resource group | Cognitive Services Content Understanding Contributor on the Content Understanding account, granted by the deployment |
| Microsoft Graph | Two application permissions: `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` |
| Microsoft Entra ID | No directory role and no group membership |

## Contents

1. [Sign-ins and permissions](#sign-ins-and-permissions)
2. [Inputs](#inputs)
3. [Steps in order](#steps-in-order)
4. [Directory writes](#directory-writes)
5. [Azure writes](#azure-writes)
6. [Files](#files)
7. [Changes to the workstation](#changes-to-the-workstation)
8. [What the migration script never does](#what-the-migration-script-never-does)
9. [What the log records](#what-the-log-records)
10. [Repeat runs and failure](#repeat-runs-and-failure)

## Sign-ins and permissions

The migration script makes two sign-ins. Both sign-ins use the account of the administrator who runs the migration script. The migration script never signs in as a service principal. The migration script stores no token.

### The sign-in to Microsoft Graph

| Subject | Detail |
|---|---|
| Method | A sign-in in the browser of the workstation, with an authorisation code, a proof key and a listener on the loopback address of the workstation, with the public client id of Microsoft Graph Command Line Tools |
| Second method | A device code that the migration script requests from the Microsoft identity platform. The administrator opens the address, enters the code and signs in |
| Third method | The Azure CLI session of the workstation, when the workstation has one for the tenant |
| Fourth method | The device code prompt of Microsoft Graph PowerShell |
| Check after the sign-in | The session is for the tenant that the command names. The signed-in account holds an active Global Administrator role. A run that writes stops otherwise |

The sign-in requests delegated permissions only. A delegated permission works only while the administrator is signed in, as the administrator.

| Delegated permission | Run | Use |
|---|---|---|
| `Application.ReadWrite.All` | Every run | The application registrations, the owners, the unique names, the federated credentials and the sponsor of the agent identity blueprint |
| `AppRoleAssignment.ReadWrite.All` | Every run | The Microsoft Graph application permissions of the deployment identity and of the service principal of the agent identity blueprint, and the assignment of the security groups to the Platform Sign-in application |
| `Directory.Read.All` | Every run | Reads of service principals, groups and directory roles |
| `User.Read` | Every run | The identity of the signed-in account |
| `DelegatedPermissionGrant.Read.All` | Every run | The read of the consent of the Platform Sign-in application |
| `AgentIdentityBlueprint.Create` | Every run | The agent identity blueprint, when absent |
| `AgentIdentityBlueprint.AddRemoveCreds.All` | Every run | The federated credentials of the agent identity blueprint |
| `AgentIdentityBlueprintPrincipal.Create` | Every run | The service principal of the agent identity blueprint, when absent |
| `GroupMember.ReadWrite.All` | The first run and the later run | The first run adds members to the security groups. The later run removes the deployment identity from groups |
| `Group.ReadWrite.All` | The first run | A security group of version 5 that is absent, and the rename of the user group of the Neologik Context Engine |
| `User.Invite.All` | The first run | The invitation of a Neologik support account that is not yet a guest |
| `AgentIdentityBlueprintPrincipal.ReadWrite.All` | The first run | The owner of a service principal of the agent identity blueprint that has none |
| `RoleManagement.ReadWrite.Directory` | The later run | The removal of directory roles from the deployment identity |

### The sign-in to Azure Resource Manager

| Subject | Detail |
|---|---|
| Method | A sign-in in the browser of the workstation with the public client id of Microsoft Azure PowerShell, naming the account of the Microsoft Graph sign-in. The request carries the multi-factor authentication claim, because Azure requires the claim for a role assignment. The same sign-in gives the Azure session a token for Microsoft Graph, through the refresh token, because the role assignment commands of Az PowerShell read each principal from Microsoft Graph. The session is opened in an Az context store of the run's own, empty, so a sign-in saved on the workstation by an earlier script takes no part. The saved sign-ins are not changed |
| Second method | A device code that the migration script requests, with the same claim. The device code gives the Azure session the token for Microsoft Graph in the same way |
| Third method | The Azure CLI session of the workstation |
| Fourth method | The device code prompt of Az PowerShell |
| Check after the sign-in | The session selected the subscription that the command names. The signed-in account holds Owner or User Access Administrator on the subscription. A run that writes stops otherwise |
| Purpose | The role assignments of the deployment identity, the tag on the resource group, the read of the SQL server administrators, and the upload of the files of the run |
| Upload of the files | A token for Azure Storage from the same sign-in, obtained with its refresh token, or from the Azure CLI with `-UseAzureCliToken`. The files go into the storage account directly, over HTTPS, with the data role Storage Blob Data Contributor of the signed-in administrator |

### The check of the roles

Before the migration script changes anything in the directory, the signed-in account must hold an active Global Administrator role. Before the migration script changes an Azure role, the signed-in account must hold Owner or User Access Administrator on the subscription. A run with `-Verify` warns and continues, and reports each item that the missing role would fail.

## Inputs

| Input | Content |
|---|---|
| Command-line parameters | The version of the onboarding kit that the migration brings the environment to (`-KitVersion`, required). The tenant, the deployment identity, the solution name and the short name, the Platform Sign-in application, the SharePoint application, each agent registration, the two groups, the subscription and the resource group. The switches `-LaterRun`, `-Verify` and `-UseAzureCliToken`. The storage account for the upload |
| `-ConfigurationFile`, optional | The configuration file that the onboarding wrote. The command from Neologik gives each value as a parameter, so the command needs no configuration file |
| `NeologikGuestUsers.txt` | The Neologik support accounts that the first run confirms as guests of the tenant. The file is beside the script, or `-GuestUsersFile` names the file |

The migration script checks each input before the first sign-in: each id is a GUID, the kit version is a version in the form `vX.Y.P`, and each file exists and parses. A wrong input stops the run before the migration script contacts anything.

## Steps in order

| Step | Run | What happens |
|---|---|---|
| Checks | Both | Each Microsoft address answers. The PowerShell modules load. The sign-in to Microsoft Graph. The Global Administrator check. The read of the deployment identity and of the service principal of Microsoft Graph |
| 1 | First | The agent identity blueprint, its service principal, the owners, the sponsor, the permission of the service principal, the three federated credentials. The two Microsoft Graph application permissions of the deployment identity |
| 2 | First | The four security groups, the Neologik guest users and the memberships |
| 3 | First | The assignment of the two role groups to the Platform Sign-in application |
| 4 | First | The administrator consent of the Platform Sign-in application (read only). The SharePoint consent. The ownership and the unique names of the application registrations that the command names |
| 5 | First | The sign-in to Azure. The ten Azure roles of the deployment identity. The tag `NeologikOnboardingKit` on the resource group |
| 5a | First | The Azure quotas that the migration needs, in the region of the environment: App Service Y1 instances, the vCPUs of the node pool family and of the region against the growth of the cluster, and the regional Azure OpenAI quota of each model that the Foundry account lacks. Read only |
| 6 | Later | The two Microsoft Graph application permissions, then the removal of the seven retired ones. The sign-in to Azure. The ten Azure roles. The removal of Contributor and User Access Administrator on the subscription, the directory role Application Administrator, the membership of the Admin User Group, every other Azure role, directory role and group membership. The removal of every role assignment on the resource group whose identity is gone from Microsoft Entra ID. The tag `NeologikOnboardingKit` |
| Close | Both | The snapshot file, the summary table and the summary file, the upload, the list of files |

## Directory writes

Each write happens only when the read before the write shows the object or the value absent. Each write is one Microsoft Graph request or one Microsoft Graph PowerShell command.

| Write | Run | Object |
|---|---|---|
| Create | First | The agent identity blueprint `Neologik Agent Blueprint - default - <short name>`, with the deployment identity as owner and the signed-in administrator as sponsor |
| Create | First | The service principal of the agent identity blueprint, with the deployment identity as owner |
| Add owner | First | The deployment identity, on the agent identity blueprint, its service principal, and each application registration and service principal that the command names |
| Add sponsor | First | The signed-in administrator, on an agent identity blueprint with no sponsor |
| Grant application permission | First and later | `AgentIdUser.ReadWrite.IdentityParentedBy` to the service principal of the agent identity blueprint. `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` to the deployment identity. `Sites.Selected` to the SharePoint application, when an earlier SharePoint application of Neologik holds a SharePoint permission |
| Add federated credential | First | `github-oidc-neo-infrastructure`, `github-oidc-neo-bot-service` and `github-oidc-neo-env-config` on the agent identity blueprint |
| Create group | First | Each of the four security groups of version 5 that is absent |
| Rename group | First | `Neologik NCE User Group - <short name>` to `Neologik NCE Contributors - <short name>`. The group keeps its id and its members |
| Invite guest | First | Each Neologik support account in `NeologikGuestUsers.txt` that is not a guest of the tenant |
| Add member | First | Each guest and the signed-in administrator to each of the four groups |
| Assign group to application | First | The user group and the NCE Admins group to the Platform Sign-in application |
| Set unique name | First | `sp-admin-<solution name>` on the Platform Sign-in application and `sp-neologik-sharepoint-<short name>` on the SharePoint application, when empty |
| Remove application permission | Later | The seven retired Microsoft Graph application permissions from the deployment identity |
| Remove directory role member | Later | The deployment identity from Application Administrator and from every other directory role |
| Remove group member | Later | The deployment identity from the Admin User Group, when every SQL server names the deployment identity as administrator, and from every other group |

The migration script removes no member other than the deployment identity. The migration script deletes no object.

## Azure writes

| Write | Run | Object |
|---|---|---|
| Role assignment | First and later | Each of the seven roles on the resource group and the two roles on the subscription that the deployment identity lacks |
| Role assignment with condition | First and later | Role Based Access Control Administrator on the subscription, limited to assigning Reader, AppGw for Containers Configuration Manager and Cost Management Reader. The later run removes an assignment that lacks the condition, or has the two-role condition, and creates the assignment again with the condition. Azure keeps the condition of an existing assignment on an update |
| Role assignment removal | Later | Contributor and User Access Administrator on the subscription. Every role of the deployment identity in the subscription outside the ten roles and the Content Understanding role on a resource in the resource group |
| Role assignment removal | Later | Every role assignment made on the resource group itself whose identity is gone from Microsoft Entra ID, whatever the role. The migration retires the identities of the previous platform version. Their assignments outlive them. They grant nothing, and the Azure portal shows them as "Identity not found". Azure reports such an identity as Unknown. The migration script then reads the object from Microsoft Entra ID. The assignment is removed only when that read answers that the object is gone. An assignment inherited from the subscription is never read or touched |
| Tag | First and later | `NeologikOnboardingKit` on the resource group, set to the value of `-KitVersion`, merged with the other tags |
| Role assignment | Both | Storage Blob Data Contributor on one storage account to the signed-in administrator, only when the storage account refuses the upload of the files of the run |

The migration script changes no Azure resource other than the tag and the role assignments. The quota step reads the quotas of the subscription (App Service, compute, Azure OpenAI), the node pools of the cluster, the virtual machine sizes of the region and the model deployments of the AI accounts in the resource group, and changes none of them. The migration script reads the Microsoft Entra administrator of each SQL server in the resource group and changes nothing on the server.

## Files

| File | Content | Secret |
|---|---|---|
| `NeologikEnvironmentMigration_<date and time>.log` | Every message of the run, each failed Microsoft Graph request with its status and request id, the summary table | None |
| `Neologik_EnvironmentMigration_<PreWindow or PostWindow>_<date and time>.json` | The versions, the tenant, the deployment identity, the signed-in account, the permissions the deployment identity holds, the two role groups, every item of the summary | None |
| `Neologik_EnvironmentMigration_Snapshot_<Pre or Post>_<date and time>.json` | The state of the application registrations, the security groups, the deployment identity and the resource group tags as the run leaves them | None. Credential kinds and expiry dates only, never a value |

The migration script writes the files to its own folder, else to the current folder, else to the temporary folder. The migration script uploads the files to the storage account of the onboarding, `stneodeploy...`, else to the storage account that `-UploadStorageAccountName` names, with the Azure session of the administrator. A storage account behind a private endpoint cannot be reached, and the files stay on the workstation.

## Changes to the workstation

| Change | Detail |
|---|---|
| PowerShell modules | The migration script installs `Microsoft.Graph.Authentication`, `Microsoft.Graph.Applications`, `Microsoft.Graph.Groups`, `Microsoft.Graph.Identity.DirectoryManagement`, `Az.Accounts`, `Az.Resources`, `Az.Sql` and `Az.Storage` from the PowerShell Gallery, for the user account only, when a module is absent |
| Sessions | The migration script opens a Microsoft Graph session and an Azure session for the run. The migration script stores no token |
| Files | The three files of the run, in the folder of the script |

## What the migration script never does

- The migration script never reads, moves or deletes customer data.
- The migration script never creates a user other than a guest invitation of a Neologik support account, never creates a secret and never reads a secret value.
- The migration script never gives administrator consent.
- The migration script never changes an application registration that the command does not name by client id.
- The migration script never removes a wider role before the deployment identity holds every narrower role.
- The migration script never grants access to an agent or an App. The grants script of the onboarding kit, `Grant-NeologikAgentAccess.ps1`, does that with the files that the Neologik Context Engine exports.
- The migration script never signs in as a service principal and never stores a token.
- With `-Verify`, the migration script writes nothing. Every write passes through one of two functions that refuse the write in a run with `-Verify`.

## What the log records

The log file opens with the version of the migration script and the version of the onboarding kit. The log file records every message of the run, each failed Microsoft Graph request with its method, path, status and request id, and the summary table. The log file never records a token or a request body.

## Repeat runs and failure

The migration script checks each item separately and continues past a failed item. The summary names each failed item with the reason. The exit code is 1 when any item needs attention. A Global Administrator can run the migration script again at any time; a second run on an environment in the expected state changes nothing. The later run removes nothing unless the deployment identity holds the two Microsoft Graph application permissions and the ten Azure roles, so a failed later run leaves the wider access in place.
