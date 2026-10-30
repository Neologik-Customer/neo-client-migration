# Neologik Migration Package

## Overview

The Neologik migration package is the set of files in this folder. A Global Administrator uses the migration package to move one existing Neologik Platform environment to version 5 of the Neologik Platform. Neologik sends the migration package to a customer whose environment is to migrate, with the complete command for each run.

This document has two readers.

| Reader | Where to read |
|---|---|
| Administrators | [Before you start](#before-you-start) and the sections that follow |
| Approvers | [MIGRATION-SCRIPT-TECHNICAL-BREAKDOWN.md](docs/MIGRATION-SCRIPT-TECHNICAL-BREAKDOWN.md) |

## Contents

1. [Terms used in the migration package](#terms-used-in-the-migration-package)
2. [What the migration package contains](#what-the-migration-package-contains)
3. [The two runs](#the-two-runs)
4. [Before you start](#before-you-start)
5. [Run the migration script](#run-the-migration-script)
6. [After the migration](#after-the-migration)
7. [Help](#help)

## Terms used in the migration package

| Term | Meaning |
|---|---|
| Neologik Context Engine | The administration web application of the Neologik Platform. The web application shows the name **Neologik Admin Tool** on screen. Platform operators configure agents and Apps there |
| Deployment identity | The service principal that Neologik signs in with to deploy the Neologik Platform into your resource group |
| Migration script | `Migrate-NeologikEnvironment.ps1` |
| Onboarding kit | The set of scripts and documents that Neologik gives a new customer. The onboarding kit holds the grants script, `Grant-NeologikAgentAccess.ps1`, which this migration package does not hold |
| Short name | The organisation code, the environment type and the environment index, joined together. An example is `abcprd01` |
| Platform Sign-in application | The application registration that signs your users in to the Neologik Context Engine and to Apps |
| Agent identity blueprint | The Microsoft Entra Agent ID object that is the parent of each agent identity and each agent user account |

## What the migration package contains

| File | Purpose |
|---|---|
| `Migrate-NeologikEnvironment.ps1` | The migration script. A Global Administrator runs the migration script twice: the pre migration script before the migration, the post migration script after Neologik has proven the environment |
| `NeologikGuestUsers.txt` | The list of Neologik support accounts. The pre migration script confirms that each account is a guest of your tenant |
| [README.md](README.md) | This document. The place to start |
| [docs/MIGRATION-SCRIPT-GUIDE.md](docs/MIGRATION-SCRIPT-GUIDE.md) | What the migration script checks and changes, run by run |
| [docs/MIGRATION-SCRIPT-TECHNICAL-BREAKDOWN.md](docs/MIGRATION-SCRIPT-TECHNICAL-BREAKDOWN.md) | For Approvers. Each sign-in, each permission, each write and each file |
| `LICENSE` | The licence for the migration package |

## The two runs

| Run | When Neologik asks for the run | What the migration script does |
|---|---|---|
| The pre migration script | Before the environment moves to version 5 of the Neologik Platform | Confirms the directory objects that the Neologik Platform uses, and the roles and permissions that the deployment identity needs. Removes nothing |
| The post migration script | After Neologik has deployed and proven the environment | Reduces the access of the deployment identity to the roles that the deployment identity needs |

The pre migration script removes nothing. The deployment identity keeps the access it holds today until the post migration script. Between the two runs, Neologik can put right a failed pre migration script or a failed deployment with that access.

The grants for agents and Apps that work unattended in Microsoft 365 are not part of the migration script. When an agent or an App of the migrated environment is to work unattended, a Global Administrator runs the grants script of the onboarding kit, `Grant-NeologikAgentAccess.ps1`, with the agent grants file and the mailbox grants file.

## Before you start

| Requirement | Detail |
|---|---|
| PowerShell | PowerShell 7.4 or later. Windows PowerShell 5.1 cannot run the migration script |
| Workstation | A desktop and a browser, for the sign-in |
| Microsoft Entra role | **Global Administrator** in your tenant |
| Azure role | **Owner** or **User Access Administrator** on the subscription of the environment. The migration script assigns and, in the post migration script, removes Azure roles |
| The command from Neologik | The command names your tenant, your subscription, your resource group, the application registrations of the environment and the version of the onboarding kit that the migration brings your environment to |

The migration script installs the PowerShell modules that the run needs, for your user account, when the modules are missing.

## Run the migration script

1. Extract the migration package to a folder, for example `C:\Neologik`. A zip downloaded from GitHub extracts to a folder inside the folder you choose, named `neo-client-migration-main`. The script is in that inner folder. Keep the files together: the pre migration script reads `NeologikGuestUsers.txt` from the folder of the migration script.
2. Open PowerShell 7 and go to the folder that holds the script, for example `cd C:\Neologik\neo-client-migration-main`.
3. Allow the script to run in this session:

```powershell
Get-ChildItem .\*.ps1 | Unblock-File
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

The first command removes the mark that Windows puts on a downloaded file. Without it, PowerShell refuses the script with the words `not digitally signed`. The second command lifts the execution policy for the current PowerShell window only. If PowerShell still refuses a script with the words `not digitally signed`, the execution policy is set by Group Policy, which the command above cannot change. Run `Get-ExecutionPolicy -List`: a value other than `Undefined` on the `MachinePolicy` or `UserPolicy` row confirms it. An administrator of that policy allows `RemoteSigned` for the workstation, or you run the scripts from a workstation without the policy.

4. Paste the command from Neologik and press Enter.
5. The migration script opens the sign-in page in your browser. Sign in as a Global Administrator who also holds Owner or User Access Administrator on the subscription. The migration script then signs in to Azure with the same account. When the browser sign-in does not complete, the migration script prints a web address and a code to enter in a browser on any device.
6. Read the summary table on screen and the list `FILES TO SEND TO NEOLOGIK` under it. Send the files to Neologik, unless the list says that the run uploaded them.

To see what a run would change, add `-Verify` to the end of the command. The migration script reports each pending change as `WOULD` and writes nothing.

[MIGRATION-SCRIPT-GUIDE.md](docs/MIGRATION-SCRIPT-GUIDE.md) describes each step of each run.

## After the migration

Neologik tells you when the environment is proven. Neologik then sends the command of the post migration script. After the post migration script, the deployment identity holds the access that [MIGRATION-SCRIPT-GUIDE.md](docs/MIGRATION-SCRIPT-GUIDE.md) lists and nothing else.

The migration package has no further use after the post migration script. The onboarding kit holds every script that a migrated environment needs later.

## Help

Email support@neologik.ai with the files that the list at the end of the run names. Give the name of your organisation and the host name of the environment.
