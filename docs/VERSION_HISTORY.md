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
2. [Version 1.0.3](#version-103)
3. [Version 1.0.2](#version-102)
4. [Version 1.0.1](#version-101)
5. [Version 1.0.0](#version-100)

## Scripts in this version

| Script | Version of the script | Purpose |
|---|---|---|
| `Migrate-NeologikEnvironment.ps1` | 1.0.3 | Moves an existing environment to version 5 of the Neologik Platform: confirms the access that the deployment identity needs in the first run, and reduces the access in the later run |

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
| `Migrate-NeologikEnvironment.ps1` | New script. The script is the migration half of `Update-NeologikEnvironmentAccess.ps1` of onboarding kit version 5.0.14: the first run and the later run, with the snapshot files, the log file, the summary file and the upload. The grants for agents and Apps that work unattended are not part of the script. `Grant-NeologikAgentAccess.ps1` of the onboarding kit applies them |
| `Migrate-NeologikEnvironment.ps1` | New parameter `-KitVersion`, required. The command from Neologik gives the version of the onboarding kit that the migration brings the environment to. The script records that version on the resource group, in the tag `NeologikOnboardingKit` |
| `Migrate-NeologikEnvironment.ps1` | The later run is the permission reduction only, step 6. The command selects the later run with `-LaterRun` |
| `Migrate-NeologikEnvironment.ps1` | The files of a run are named `NeologikEnvironmentMigration_<date and time>.log`, `Neologik_EnvironmentMigration_<PreWindow or PostWindow>_<date and time>.json` and `Neologik_EnvironmentMigration_Snapshot_<Pre or Post>_<date and time>.json`. Each file names the version of the script and the version of the onboarding kit |
| `Migrate-NeologikEnvironment.ps1` | The sign-in to Microsoft Graph no longer requests `DelegatedPermissionGrant.ReadWrite.All` in any run. The grants script of the onboarding kit requests the permission |
| `MIGRATION-SCRIPT-GUIDE.md` | New document. What the migration script checks and changes, for the administrator who runs the script |
| `MIGRATION-SCRIPT-TECHNICAL-BREAKDOWN.md` | New document. Each sign-in, each permission, each write and each file, for approvers |
| `NeologikGuestUsers.txt` | One Neologik support account that no longer works for Neologik is removed from the list |
