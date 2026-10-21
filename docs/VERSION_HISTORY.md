# Version History

## Overview

This document lists the versions of the Neologik migration package. For each version, this document states what changed for you.

| Subject | Detail |
|---|---|
| Version of the migration script | `Migrate-NeologikEnvironment.ps1` reports the version at the top of each run and in each file the run writes |
| Version of the onboarding kit | The command from Neologik names the version of the onboarding kit that the migration brings your environment to, with `-KitVersion`. The migration script records that version on your resource group, in the tag `NeologikOnboardingKit`. The Neologik Platform reads the tag before an upgrade |
| Before version 1.0.0 | The migration script was part of the onboarding kit, under the name `Update-NeologikEnvironmentAccess.ps1`, up to onboarding kit version 5.0.14. [VERSION_HISTORY.md](https://github.com/Neologik-Customer/neo-client-onboarding/blob/main/docs/VERSION_HISTORY.md) of the onboarding kit lists those versions |

## Contents

1. [Scripts in this version](#scripts-in-this-version)
2. [Version 1.1.2](#version-112)
3. [Version 1.1.1](#version-111)
4. [Version 1.1.0](#version-110)
5. [Version 1.0.4](#version-104)
6. [Version 1.0.3](#version-103)
7. [Version 1.0.2](#version-102)
8. [Version 1.0.1](#version-101)
9. [Version 1.0.0](#version-100)

## Scripts in this version

| Script | Version of the script | Purpose |
|---|---|---|
| `Migrate-NeologikEnvironment.ps1` | 1.1.2 | Moves an existing environment to version 5 of the Neologik Platform: confirms the access that the deployment identity needs in the pre migration script, and reduces the access in the post migration script |

## Version 1.1.2

**Date**: 2026-10-20

This version applies to an environment on Neologik Platform version 5.0 or version 5.1.

| Item | Change |
|---|---|
| `Migrate-NeologikEnvironment.ps1` | Wording only. The two runs of the migration script have fixed names: the pre migration script, the run before the migration window, and the post migration script, the run after Neologik has proven the environment, selected with `-LaterRun`. The messages, the summary and the help of the script use the two names. The parameter `-LaterRun`, the file names `PreWindow` and `PostWindow` and the code are unchanged |
| `MIGRATION-SCRIPT-GUIDE.md`, `MIGRATION-SCRIPT-TECHNICAL-BREAKDOWN.md`, `README.md` | The documents use the two names |

## Version 1.1.1

**Date**: 2026-10-20

This version applies to an environment on Neologik Platform version 5.0 or version 5.1.

| Item | Change |
|---|---|
| `Migrate-NeologikEnvironment.ps1` | New step 6i of the post migration script. The post migration script gives the script runner identity, the managed identity `neologik-script-runner-service-connection-<short name>` that the deployment runs its scripts with, the role Reader on the resource group. Then the post migration script removes Contributor on the subscription and Contributor on the resource group from that identity. An onboarding before onboarding kit version 5.0.3 gave the identity Contributor instead of Reader. The post migration script removes nothing from the identity until the identity holds Reader. The command from Neologik names the identity with the new parameter `-ScriptRunnerObjectId`. Without the parameter the post migration script leaves the roles of the identity |
| `Migrate-NeologikEnvironment.ps1` | A run with `-Verify` reports the three changes of step 6i as `WOULD ASSIGN` and `WOULD REMOVE` and writes nothing |
| `MIGRATION-SCRIPT-GUIDE.md`, `MIGRATION-SCRIPT-TECHNICAL-BREAKDOWN.md` | Step 6i described |

## Version 1.1.0

**Date**: 2026-10-20

This version applies to an environment on Neologik Platform version 5.0 or version 5.1.

| Item | Change |
|---|---|
| `Migrate-NeologikEnvironment.ps1` | The migration script signs in to Microsoft Graph and to Azure in the browser of the workstation first. A device code is the second method. Before this version, a device code was the first method. An organisation that blocks the device code with a Conditional Access policy could not complete the sign-in |
| `Migrate-NeologikEnvironment.ps1` | When a Conditional Access policy refuses a sign-in, the migration script says so and tries the next method at once |
| `Migrate-NeologikEnvironment.ps1` | Step 5 and step 6 apply a three-role condition to the limited Role Based Access Control Administrator on the subscription: Reader, AppGw for Containers Configuration Manager and Cost Management Reader. The deployment assigns Cost Management Reader on the resource group that Azure Kubernetes Service creates for the nodes of the cluster to the identity of the configuration API of the Neologik Platform, which reads the daily cost of the nodes for the return on investment report. An assignment with the old condition receives the new condition in the post migration script |
| `MIGRATION-SCRIPT-GUIDE.md` | The document describes the browser sign-in, the device code as the second method and the three roles the limited administrator may assign. The sign-in step says to choose the account that holds Owner or User Access Administrator on the subscription as well as Global Administrator |
| `Migrate-NeologikEnvironment.ps1` | New step 6h of the post migration script. The migration script removes every role assignment on the resource group whose identity is gone from Microsoft Entra ID. The migration retires the identities of the previous platform version. Their role assignments outlive them. They grant nothing, and the Azure portal shows them as "Identity not found". The migration script confirms with Microsoft Entra ID that the identity is gone before it removes an assignment. An assignment whose identity still exists is kept and reads `Review` in the summary. An assignment inherited from the subscription is never touched. The tag of the onboarding kit is now step 6i |
| `MIGRATION-SCRIPT-GUIDE.md`, `MIGRATION-SCRIPT-TECHNICAL-BREAKDOWN.md` | Step 6h described |
| `Migrate-NeologikEnvironment.ps1` | The post migration script now replaces a Role Based Access Control Administrator assignment on the subscription that lacks the three-role limit. The post migration script removes the assignment and creates the assignment again with the limit. Before this change, the post migration script updated the assignment, and Azure kept the earlier two-role limit. The deployment identity then could not assign Cost Management Reader |
| `MIGRATION-SCRIPT-GUIDE.md`, `MIGRATION-SCRIPT-TECHNICAL-BREAKDOWN.md` | Step 6 and the Azure writes table describe the removal and the new assignment |

## Version 1.0.4

**Date**: 2026-10-08

| Item | Change |
|---|---|
| `Migrate-NeologikEnvironment.ps1` | New step 5a of the pre migration script: the Azure quotas that the migration needs, read with the Azure session and changed never. The App Service Y1 instance quota for the start and stop schedule of the cluster, the vCPU quota of the node pool family and of the region against the growth of the cluster, and the regional Azure OpenAI quota of each model that the Foundry account lacks. A quota that is short reads `SHORT` in the summary and needs attention; a refused read reads `Review` and the run continues |
| `MIGRATION-SCRIPT-GUIDE.md`, `MIGRATION-SCRIPT-TECHNICAL-BREAKDOWN.md` | Step 5a described |

## Version 1.0.3

**Date**: 2026-10-08

| Item | Change |
|---|---|
| `Migrate-NeologikEnvironment.ps1` | The upload of the files of the run uses a token for Azure Storage from the same sign-in as the Azure session, and puts the files into the storage account directly. Before this version, the upload asked the Azure session for that token, which a session opened from the sign-in of the script does not hold, and the upload failed with `failed to retrieve access token for resource 'StorageOAuthEndpointResourceId'`. The administrator then sent the files by hand. The sign-in with the device code of Az PowerShell is unchanged |

## Version 1.0.2

**Date**: 2026-10-08

| Item | Change |
|---|---|
| `Migrate-NeologikEnvironment.ps1` | The run opens its Azure session in a context store of its own, empty, so a sign-in saved on the workstation by an earlier script takes no part. Before this version, Az PowerShell could use such a saved sign-in in place of the tokens of the run, and every Azure call then failed with `User interaction is required`. The saved sign-ins on the workstation are not changed. The log says when the sign-in also gave the token for Microsoft Graph |

## Version 1.0.1

**Date**: 2026-10-08

| Item | Change |
|---|---|
| `Migrate-NeologikEnvironment.ps1` | The Azure session receives a token for Microsoft Graph as well as the token for Azure Resource Manager, from the same sign-in. Before this version, every read and every write of an Azure role failed after the device code sign-in with `Authentication failed against resource MicrosoftGraphEndpointResourceId`, because the Azure session could not obtain that token itself. The administrator signs in once, as before |
| Documents | The preparation steps of `README.md` name the inner folder of a zip downloaded from GitHub, lift the execution policy for the window with `Bypass` in place of `RemoteSigned`, and say what to do when Group Policy enforces the policy |

## Version 1.0.0

**Date**: 2026-10-08

| Item | Change |
|---|---|
| `Migrate-NeologikEnvironment.ps1` | New script. The script is the migration half of `Update-NeologikEnvironmentAccess.ps1` of onboarding kit version 5.0.14: the pre migration script and the post migration script, with the snapshot files, the log file, the summary file and the upload. The grants for agents and Apps that work unattended are not part of the script. `Grant-NeologikAgentAccess.ps1` of the onboarding kit applies them |
| `Migrate-NeologikEnvironment.ps1` | New parameter `-KitVersion`, required. The command from Neologik gives the version of the onboarding kit that the migration brings the environment to. The script records that version on the resource group, in the tag `NeologikOnboardingKit` |
| `Migrate-NeologikEnvironment.ps1` | The post migration script is the permission reduction only, step 6. The command selects the post migration script with `-LaterRun` |
| `Migrate-NeologikEnvironment.ps1` | The files of a run are named `NeologikEnvironmentMigration_<date and time>.log`, `Neologik_EnvironmentMigration_<PreWindow or PostWindow>_<date and time>.json` and `Neologik_EnvironmentMigration_Snapshot_<Pre or Post>_<date and time>.json`. Each file names the version of the script and the version of the onboarding kit |
| `Migrate-NeologikEnvironment.ps1` | The sign-in to Microsoft Graph no longer requests `DelegatedPermissionGrant.ReadWrite.All` in any run. The grants script of the onboarding kit requests the permission |
| `MIGRATION-SCRIPT-GUIDE.md` | New document. What the migration script checks and changes, for the administrator who runs the script |
| `MIGRATION-SCRIPT-TECHNICAL-BREAKDOWN.md` | New document. Each sign-in, each permission, each write and each file, for approvers |
| `NeologikGuestUsers.txt` | One Neologik support account that no longer works for Neologik is removed from the list |
