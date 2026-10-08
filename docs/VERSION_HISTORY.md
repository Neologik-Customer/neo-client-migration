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
2. [Version 1.0.0](#version-100)

## Scripts in this version

| Script | Version of the script | Purpose |
|---|---|---|
| `Migrate-NeologikEnvironment.ps1` | 1.0.0 | Moves an existing environment to version 5 of the Neologik Platform: confirms the access that the deployment identity needs in the first run, and reduces the access in the later run |

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
