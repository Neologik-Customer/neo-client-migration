# Migrate-NeologikEnvironment.ps1: Technical Breakdown

## Overview

This document is for approvers of the migration script, `Migrate-NeologikEnvironment.ps1`. An approver is a person who reviews a script before an administrator runs the script.

This document lists each sign-in, each permission, each write to the directory, each write to Azure and each file. This document also lists what the migration script never does. [MIGRATION-SCRIPT-GUIDE.md](MIGRATION-SCRIPT-GUIDE.md) describes each step for the administrator who runs the script.

### What the migration script does

The migration script moves one existing Neologik Platform environment to version 5 of the Neologik Platform. A Global Administrator who also holds Owner on the subscription runs the migration script twice.

| Run | Writes |
|---|---|
| The pre migration script | Creates a directory object or a role assignment that is absent. Removes nothing |
| The post migration script | Removes the access that the deployment identity does not need. Creates a role assignment that is absent first |

### What the deployment identity holds after the post migration script

| Subject | Position |
|---|---|
| Resource group | Seven roles: Contributor, Key Vault Certificates Officer, Key Vault Secrets Officer, Storage Blob Data Contributor, Azure Kubernetes Service RBAC Cluster Admin, Monitoring Contributor and Role Based Access Control Administrator |
| Subscription | Three roles: Reader, Cost Management Contributor, and Role Based Access Control Administrator limited by a condition to assigning three roles, Reader, AppGw for Containers Configuration Manager and Cost Management Reader. These roles change no Azure resource other than cost configuration, support requests and assignments of the three assignable roles |
| Resources in the resource group | Two roles, each granted by the deployment. Cognitive Services Content Understanding Contributor on the Content Understanding account. Storage Blob Data Contributor on the container `function-package`. That container holds the package of the function that starts and stops the cluster |
| Microsoft Graph | Two application permissions: `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` |
| Microsoft Entra ID | No directory role and no group membership |

The post migration script also narrows the script runner identity, the managed identity `neologik-script-runner-service-connection-<short name>` that the deployment runs its scripts with, when the command names the identity with `-ScriptRunnerObjectId`. After the post migration script that identity holds Reader, Key Vault Secrets Officer and Azure Bot Service Contributor Role on the resource group, and no role on the subscription.

### What else stands as the onboarding kit leaves it

After the post migration script the environment stands where an environment onboarded with the current onboarding kit stands. The migration script confirms each item below in both runs, the Admin User Group in the post migration script only, and adds what is absent.

| Subject | Position |
|---|---|
| The Admin User Group | Thirteen roles on the resource group and no role on the subscription: Contributor, Azure Kubernetes Service Cluster Admin Role, Azure Kubernetes Service RBAC Cluster Admin, Key Vault Administrator, Key Vault Secrets Officer, Key Vault Certificates Officer, Storage Blob Data Owner, Storage Blob Data Contributor, Storage Table Data Contributor, Cognitive Services Data Reader, Cognitive Services OpenAI Contributor, Search Index Data Reader and Azure AI Developer. The post migration script removes every other role of the group in the subscription once the group holds all thirteen. A role of the group outside the subscription is listed and kept |
| The SQL managed identity | The directory role Directory Readers, which the SQL server uses to look up Microsoft Entra accounts and groups at sign-in |
| The subscription | Every resource provider and preview feature of `resource-providers.txt` registered |
| The Key Vault | Azure role-based access control |
| The deployment storage account `stneodeploy...` | Shared key access off, public blob access off, minimum TLS version 1.2, the containers `certificate`, `json` and `logs` |

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
| `GroupMember.ReadWrite.All` | The pre migration script and the post migration script | The pre migration script adds members to the security groups. The post migration script removes the deployment identity from groups |
| `Group.ReadWrite.All` | The pre migration script | A security group that is absent, and the rename of the user group of the Neologik Admin Tool |
| `User.Invite.All` | The pre migration script | The invitation of a Neologik support account that is not yet a guest |
| `AgentIdentityBlueprintPrincipal.ReadWrite.All` | The pre migration script | The owner of a service principal of the agent identity blueprint that has none |
| `RoleManagement.ReadWrite.Directory` | Every run | The directory role Directory Readers of the SQL managed identity, when absent. The post migration script also removes directory roles from the deployment identity |

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
| Command-line parameters | The version of the onboarding kit that the migration brings the environment to (`-KitVersion`, required). The tenant, the deployment identity, the solution name and the short name, the Platform Sign-in application, the SharePoint application, each agent registration, the three groups, the subscription and the resource group. The environment name and the name of the directory managed identity. The name of the SQL managed identity (`-SqlIdentityName`, required) and the name of the Key Vault (`-KeyVaultName`, required). The switches `-LaterRun`, `-Verify` and `-UseAzureCliToken`. The storage account for the upload |
| `resource-providers.txt` | The resource providers and preview features that the Neologik Platform requires, the list of the onboarding kit. The migration package carries the file beside the migration script |
| `-ConfigurationFile` | The configuration file that the onboarding wrote. The command from Neologik gives each value as a parameter, so the command needs no configuration file |
| `NeologikGuestUsers.txt` | The Neologik support accounts that the pre migration script confirms as guests of the tenant. The file is beside the script, or `-GuestUsersFile` names the file |

The migration script checks each input before the first sign-in: each id is a GUID, the kit version is a version in the form `vX.Y.P`, and each file exists and parses. A wrong input stops the run before the migration script contacts anything.

## Steps in order

| Step | Run | What happens |
|---|---|---|
| Checks | Pre and post migration scripts | Each Microsoft address answers. The PowerShell modules load. The sign-in to Microsoft Graph. The Global Administrator check. The read of the deployment identity and of the service principal of Microsoft Graph |
| 1 | Pre migration script | The agent identity blueprint, its service principal, the owners, the sponsor, the permission of the service principal, the three federated credentials. The two Microsoft Graph application permissions of the deployment identity |
| 2 | Pre migration script | The four security groups, the Neologik guest users and the memberships |
| 3 | Pre migration script | The assignment of the two role groups to the Platform Sign-in application |
| 4 | Pre migration script | The administrator consent of the Platform Sign-in application (read only). The SharePoint consent. The ownership and the unique names of the application registrations that the command names |
| 5 | Pre migration script | The sign-in to Azure. The ten Azure roles of the deployment identity. The tag `NeologikOnboardingKit` on the resource group |
| 5a | Pre migration script | The Azure checks that the migration needs, in the region of the environment. The step checks that the region has the Flex Consumption plan. The step compares the vCPUs of the node pool family and of the region with the growth of the cluster. The step reads the regional Azure OpenAI quota of each model that the Foundry account lacks. Read only |
| 5c | Pre and post migration scripts | The directory role Directory Readers of the SQL managed identity. The resource providers and preview features of `resource-providers.txt`. Azure role-based access control on the Key Vault. The settings and the containers of the deployment storage account |
| 6 | Post migration script | The two Microsoft Graph application permissions, then the removal of seven other Microsoft Graph application permissions. The sign-in to Azure. The ten Azure roles. The removal of Contributor and User Access Administrator on the subscription. The removal of the directory role Application Administrator and of the membership of the Admin User Group. The removal of every other Azure role, directory role and group membership. The removal of every role assignment on the resource group whose identity is gone from Microsoft Entra ID. When the command names the script runner identity with `-ScriptRunnerObjectId`, Reader and Key Vault Secrets Officer on the resource group for that identity. Then the removal of Contributor on the subscription and on the resource group from that identity. The thirteen roles of the Admin User Group on the resource group, then the removal of every other role of the group in the subscription. The tag `NeologikOnboardingKit` |
| 4c and 5b | Pre and post migration scripts | The federated credential of the deployment identity. The directory managed identity, the Microsoft Graph application permission of the managed identity and the owners. The tag `NeologikOnboardingKit` waits for both, for the items of step 5c and, in the post migration script, for the roles of the Admin User Group |
| Close | Pre and post migration scripts | The snapshot file, the summary table and the summary file, the upload, the list of files |

## Directory writes

Each write happens only when the read before the write shows the object or the value absent. Each write is one Microsoft Graph request or one Microsoft Graph PowerShell command.

| Write | Run | Object |
|---|---|---|
| Create | Pre migration script | The agent identity blueprint `Neologik Agent Blueprint - default - <short name>`, with the deployment identity as owner and the signed-in administrator as sponsor |
| Create | Pre migration script | The service principal of the agent identity blueprint, with the deployment identity as owner |
| Add owner | Pre migration script | The deployment identity, on the agent identity blueprint, its service principal, and each application registration and service principal that the command names |
| Add sponsor | Pre migration script | The signed-in administrator, on an agent identity blueprint with no sponsor |
| Grant application permission | Pre and post migration scripts | `AgentIdUser.ReadWrite.IdentityParentedBy` to the service principal of the agent identity blueprint. `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` to the deployment identity. `Sites.Selected` to the SharePoint application, when another SharePoint application of Neologik holds a SharePoint permission |
| Add federated credential | Pre migration script | `github-oidc-neo-infrastructure`, `github-oidc-neo-bot-service` and `github-oidc-neo-env-config` on the agent identity blueprint |
| Add federated credential | Pre and post migration scripts | `github-deployments-<environment name>` on the application registration of the deployment identity. The credential accepts only a run of the Neologik deployment organisation that names this environment. The credential adds no permission |
| Grant application permission | Pre and post migration scripts | `Application.ReadWrite.OwnedBy` to the directory managed identity |
| Add owner | Pre and post migration scripts | The directory managed identity, on each agent registration that the command names and on the service principal of each |
| Add directory role member | Pre and post migration scripts | The SQL managed identity to the directory role Directory Readers. When the tenant has never used the role, the migration script activates the role object from its template first |
| Create group | Pre migration script | Each of the four security groups that is absent |
| Rename group | Pre migration script | `Neologik NCE User Group - <short name>` to `Neologik NCE Contributors - <short name>`. A group that the command names by id, `-UserGroupId`, `-NceUserGroupId` or `-AdminGroupId`, from another name that begins `Neologik` to the name of step 2. The group keeps its id and its members. A group with a name of the organisation's own keeps the name. A user group with a name of the organisation's own is not used, and step 2 finds or creates the user group by name |
| Invite guest | Pre migration script | Each Neologik support account in `NeologikGuestUsers.txt` that is not a guest of the tenant |
| Add member | Pre migration script | Each guest and the signed-in administrator to each of the four groups |
| Assign group to application | Pre migration script | The user group and the NCE Admins group to the Platform Sign-in application |
| Set unique name | Pre migration script | `sp-admin-<solution name>` on the Platform Sign-in application and `sp-neologik-sharepoint-<short name>` on the SharePoint application, when empty |
| Remove application permission | Post migration script | Seven Microsoft Graph application permissions that the deployment identity does not need |
| Remove directory role member | Post migration script | The deployment identity from Application Administrator and from every other directory role |
| Remove group member | Post migration script | The deployment identity from the Admin User Group, when every SQL server names the deployment identity as administrator, and from every other group |

The migration script removes no member other than the deployment identity. The migration script deletes no object. The migration script adds no member other than the Neologik guest users, the signed-in administrator and the SQL managed identity.

## Azure writes

| Write | Run | Object |
|---|---|---|
| Role assignment | Pre and post migration scripts | Each of the seven roles on the resource group and the two roles on the subscription that the deployment identity lacks |
| Role assignment with condition | Pre and post migration scripts | Role Based Access Control Administrator on the subscription. The condition limits the role to assigning Reader, AppGw for Containers Configuration Manager and Cost Management Reader. The post migration script removes an assignment that lacks the condition or has a different condition. The post migration script then creates the assignment again with the condition. Azure keeps the condition of an existing assignment on an update |
| Role assignment removal | Post migration script | Contributor and User Access Administrator on the subscription. Every role of the deployment identity in the subscription outside the ten roles and the Content Understanding role on a resource in the resource group |
| Role assignment | Post migration script | Reader and Key Vault Secrets Officer on the resource group to the script runner identity, the managed identity `neologik-script-runner-service-connection-<short name>` that the deployment runs its scripts with, when the command names the identity with `-ScriptRunnerObjectId` and the identity lacks a role |
| Role assignment removal | Post migration script | Contributor on the subscription and Contributor on the resource group from the script runner identity, only after the identity holds Reader and Key Vault Secrets Officer on the resource group. The identity keeps Azure Bot Service Contributor Role on the resource group. Without `-ScriptRunnerObjectId` the migration script changes no role of the identity |
| Role assignment | Post migration script | Each of the thirteen roles of the Admin User Group on the resource group that the group lacks, when the command names the group with `-AdminGroupId` |
| Role assignment removal | Post migration script | Every role of the Admin User Group in the subscription outside the thirteen roles, on the subscription, on the resource group and below, only after the group holds all thirteen roles on the resource group. A role of the group outside the subscription is listed and kept |
| Resource provider registration | Pre and post migration scripts | Each resource provider and preview feature of `resource-providers.txt` that is not registered on the subscription. The migration script waits for the registrations for ten minutes at most |
| Key Vault setting | Pre and post migration scripts | Azure role-based access control on the Key Vault that `-KeyVaultName` names, when the setting is off |
| Storage account settings | Pre and post migration scripts | On the deployment storage account `stneodeploy...`: shared key access off, public blob access off and minimum TLS version 1.2, each when the setting differs. The containers `certificate`, `json` and `logs`, each when absent |
| Role assignment removal | Post migration script | Every role assignment made on the resource group itself whose identity is gone from Microsoft Entra ID, whatever the role. Such a role assignment grants nothing, and the Azure portal shows the role assignment as "Identity not found". Azure reports such an identity as Unknown. The migration script then reads the object from Microsoft Entra ID. The assignment is removed only when that read answers that the object is gone. An assignment inherited from the subscription is never read or touched |
| Create managed identity | Pre and post migration scripts | The directory managed identity, with the name that `-DirectoryIdentityName` gives, in the location of the resource group and with the tags of the resource group. The managed identity holds no Azure role. Nothing can sign in as the managed identity until a deployment by Neologik adds the sign-in credential |
| Tag | Pre and post migration scripts | `NeologikOnboardingKit` on the resource group, set to the value of `-KitVersion`, merged with the other tags, when the federated credential and the directory managed identity are complete |
| Role assignment | Pre and post migration scripts | Storage Blob Data Contributor on one storage account to the signed-in administrator, only when the storage account refuses the upload of the files of the run |

The migration script changes no Azure resource other than the directory managed identity, the tag, the role assignments, the registration of resource providers, the access model of the Key Vault and the settings and containers of the deployment storage account. The quota step reads the quotas of the subscription (App Service, compute, Azure OpenAI), the node pools of the cluster, the virtual machine sizes of the region and the model deployments of the AI accounts in the resource group, and changes none of them. The migration script reads the Microsoft Entra administrator of each SQL server in the resource group and changes nothing on the server.

## Files

| File | Content | Secret |
|---|---|---|
| `NeologikEnvironmentMigration_<date and time>.log` | Every message of the run, each failed Microsoft Graph request with its status and request id, the summary table | None |
| `Neologik_EnvironmentMigration_<PreWindow or PostWindow>_<date and time>.json` | The versions, the tenant, the deployment identity, the signed-in account, the permissions the deployment identity holds, the user group and the two role groups, every item of the summary | None |
| `Neologik_EnvironmentMigration_Snapshot_<Pre or Post>_<date and time>.json` | The state of the application registrations, the security groups, the deployment identity and the resource group tags as the run leaves them | None. Credential kinds and expiry dates only, never a value |

The migration script writes the files to its own folder, else to the current folder, else to the temporary folder. The migration script uploads the files to the storage account of the onboarding, `stneodeploy...`, else to the storage account that `-UploadStorageAccountName` names, with the Azure session of the administrator. A storage account behind a private endpoint cannot be reached, and the files stay on the workstation.

## Changes to the workstation

| Change | Detail |
|---|---|
| PowerShell modules | The migration script installs `Microsoft.Graph.Authentication`, `Microsoft.Graph.Applications`, `Microsoft.Graph.Groups`, `Microsoft.Graph.Identity.DirectoryManagement`, `Az.Accounts`, `Az.Resources`, `Az.Sql` and `Az.Storage` from the PowerShell Gallery, for the user account only, when a module is absent |
| Sessions | The migration script opens a Microsoft Graph session and an Azure session for the run. The migration script stores no token |
| Files | The three files of the run, in the folder of the script. The migration script reads `NeologikGuestUsers.txt` and `resource-providers.txt` from that folder |

## What the migration script never does

- The migration script never reads, moves or deletes customer data.
- The migration script never creates a user other than a guest invitation of a Neologik support account, never creates a secret and never reads a secret value.
- The migration script never gives administrator consent.
- The migration script never changes an application registration that the command does not name by client id.
- The migration script never removes a wider role before the deployment identity holds every narrower role.
- The migration script never grants access to an agent or an App. The grants script of the onboarding kit, `Grant-NeologikAgentAccess.ps1`, does that with the agent grants file and the mailbox grants file.
- The migration script never signs in as a service principal and never stores a token.
- With `-Verify`, the migration script writes nothing. Every write passes through one of two functions that refuse the write in a run with `-Verify`.

## What the log records

The log file opens with the version of the migration script and the version of the onboarding kit. The log file records every message of the run, each failed Microsoft Graph request with its method, path, status and request id, and the summary table. The log file never records a token or a request body.

## Repeat runs and failure

The migration script checks each item separately and continues past a failed item. The summary names each failed item with the reason. The exit code is 1 when any item needs attention. A Global Administrator can run the migration script again at any time; a second run on an environment in the expected state changes nothing. The post migration script removes nothing unless the deployment identity holds the two Microsoft Graph application permissions and the ten Azure roles, so a failed post migration script leaves the wider access in place.
