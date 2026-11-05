#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Tests of Migrate-NeologikEnvironment.ps1 (project#3192).

    Every external call is replaced: Microsoft Graph (the SDK cmdlets and the
    raw request seam), Azure (Az.Accounts / Az.Resources), the Azure CLI,
    module installation and the console. An in-memory tenant
    model answers the script's reads and records every write, so a run can
    be asserted to change exactly what a real run would change - and, on a
    compliant tenant, nothing at all.

    Run: pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI"
#>

Describe 'Migrate-NeologikEnvironment.ps1' {

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Migrate-NeologikEnvironment.ps1'

    # ----- stubs for every external command the script calls -----------------
    # (a command must exist before Pester can mock it, and the Graph and Az
    # cmdlets would need real modules.)
    function Connect-MgGraph { [CmdletBinding()] param($AccessToken, $TenantId, $Scopes, [switch]$UseDeviceCode, [switch]$NoWelcome) }
    function Get-MgContext { [CmdletBinding()] param() }
    function Invoke-MgGraphRequest { [CmdletBinding()] param($Method, $Uri, $Body, $Headers, $ContentType, [switch]$SkipHttpErrorCheck, $StatusCodeVariable, $ResponseHeadersVariable) }
    function Get-MgServicePrincipal { [CmdletBinding()] param($Filter, [switch]$All) }
    function Get-MgServicePrincipalAppRoleAssignment { [CmdletBinding()] param($ServicePrincipalId, [switch]$All) }
    function New-MgServicePrincipalAppRoleAssignment { [CmdletBinding()] param($ServicePrincipalId, $PrincipalId, $ResourceId, $AppRoleId) }
    function Remove-MgServicePrincipalAppRoleAssignment { [CmdletBinding()] param($ServicePrincipalId, $AppRoleAssignmentId) }
    function Get-MgGroupAppRoleAssignment { [CmdletBinding()] param($GroupId, [switch]$All) }
    function New-MgGroupAppRoleAssignment { [CmdletBinding()] param($GroupId, $PrincipalId, $ResourceId, $AppRoleId) }
    function Get-MgGroup { [CmdletBinding()] param($GroupId) }
    function Get-MgGroupMember { [CmdletBinding()] param($GroupId, [switch]$All) }
    function Get-MgServicePrincipalMemberOf { [CmdletBinding()] param($ServicePrincipalId, [switch]$All) }
    function Get-MgServicePrincipalOauth2PermissionGrant { [CmdletBinding()] param($ServicePrincipalId, [switch]$All) }
    function Get-MgDirectoryRole { [CmdletBinding()] param([switch]$All, $Filter) }
    function Get-MgDirectoryRoleMember { [CmdletBinding()] param($DirectoryRoleId, [switch]$All) }
    function Remove-MgDirectoryRoleMemberDirectoryObjectByRef { [CmdletBinding()] param($DirectoryRoleId, $DirectoryObjectId) }
    function Remove-MgGroupMemberByRef { [CmdletBinding()] param($GroupId, $DirectoryObjectId) }
    function Get-AzSqlServer { [CmdletBinding()] param($ResourceGroupName) }
    function Get-AzSqlServerActiveDirectoryAdministrator { [CmdletBinding()] param($ResourceGroupName, $ServerName) }
    function Connect-AzAccount { [CmdletBinding()] param($Tenant, $Subscription, $UseDeviceAuthentication, $ClaimsChallenge, $AccessToken, $AccountId, $MicrosoftGraphAccessToken) }
    function Get-AzContext { [CmdletBinding()] param() }
    function Disable-AzContextAutosave { [CmdletBinding()] param($Scope) }
    function Clear-AzContext { [CmdletBinding()] param($Scope, [switch]$Force) }
    function Get-AzResourceGroup { [CmdletBinding()] param($Name) }
    function Invoke-AzRestMethod { [CmdletBinding()] param($Method, $Path, $Uri, $Payload) }
    function Update-AzTag { [CmdletBinding()] param($ResourceId, $Tag, $Operation) }
    function Get-AzRoleAssignment { [CmdletBinding()] param($ObjectId, $RoleDefinitionName, $Scope) }
    function New-AzRoleAssignment { [CmdletBinding()] param($ObjectId, $RoleDefinitionName, $RoleDefinitionId, $Scope, $Condition, $ConditionVersion) }
    function Set-AzRoleAssignment { [CmdletBinding()] param($InputObject, [switch]$PassThru) }
    function Remove-AzRoleAssignment { [CmdletBinding()] param($ObjectId, $RoleDefinitionName, $Scope) }
    # Az.Storage, for the upload of the files of the run (project#3171).
    function Get-AzStorageAccount { [CmdletBinding()] param($ResourceGroupName, $Name) }
    function New-AzStorageContext { [CmdletBinding()] param($StorageAccountName, [switch]$UseConnectedAccount) }
    function Get-AzStorageContainer { [CmdletBinding()] param($Name, $Context) }
    function New-AzStorageContainer { [CmdletBinding()] param($Name, $Context, $Permission) }
    function Set-AzStorageBlobContent { [CmdletBinding()] param($File, $Container, $Blob, $Context, [switch]$Force) }

    # The script under test: dot-sourced, so its functions are defined here
    # and its guarded main entry does not run. The kit version comes from the
    # command (-KitVersion); the fixtures use one value throughout.
    . $script:ScriptPath
    $script:KitVersion = 'v5.0.15'

    # ----- fixed identifiers ------------------------------------------------------
    $script:Ids = @{
        Tenant           = '11111111-1111-1111-1111-111111111111'
        OtherTenant      = '99999999-9999-9999-9999-999999999999'
        Subscription     = '22222222-2222-2222-2222-222222222222'
        DeployAppId      = '33333333-3333-3333-3333-333333333333'
        DeploySpId       = '33333333-aaaa-3333-3333-333333333333'
        ScriptRunnerId   = '33333333-bbbb-3333-3333-333333333333'
        GraphSpId        = '00000003-aaaa-0000-c000-000000000000'
        SignInAppId      = '44444444-4444-4444-4444-444444444444'
        SignInSpId       = '44444444-aaaa-4444-4444-444444444444'
        Group            = '55555555-5555-5555-5555-555555555555'
        AdminGroup       = '55555555-aaaa-5555-5555-555555555555'
        Me               = '66666666-6666-6666-6666-666666666666'
        BlueprintAppObj  = '77777777-7777-7777-7777-777777777777'
        BlueprintAppId   = '77777777-aaaa-7777-7777-777777777777'
        BlueprintSpId    = '77777777-bbbb-7777-7777-777777777777'
        AgentIdentityApp = '88888888-8888-8888-8888-888888888888'
        AgentIdentitySp  = '88888888-aaaa-8888-8888-888888888888'
        AgentUser        = '88888888-bbbb-8888-8888-888888888888'
        AppIdentityApp   = '88888888-cccc-8888-8888-888888888888'
        AppIdentitySp    = '88888888-dddd-8888-8888-888888888888'
        AppUser          = '88888888-eeee-8888-8888-888888888888'
        ComponentSpId    = 'aaaaaaaa-1111-aaaa-aaaa-aaaaaaaaaaaa'
        SharePointSpId   = 'bbbbbbbb-1111-bbbb-bbbb-bbbbbbbbbbbb'
        SharePointAppId  = 'bbbbbbbb-2222-bbbb-bbbb-bbbbbbbbbbbb'
        SharePoint2SpId  = 'bbbbbbbb-3333-bbbb-bbbb-bbbbbbbbbbbb'
        SharePoint2AppId = 'bbbbbbbb-4444-bbbb-bbbb-bbbbbbbbbbbb'
        EarlierSpId      = 'bbbbbbbb-5555-bbbb-bbbb-bbbbbbbbbbbb'
        EarlierAppId     = 'bbbbbbbb-6666-bbbb-bbbb-bbbbbbbbbbbb'
        AppAdminRole     = 'cccccccc-1111-cccc-cccc-cccccccccccc'
        AgentIdAdminRole = 'cccccccc-2222-cccc-cccc-cccccccccccc'
        DevTeamGroup     = '55555555-bbbb-5555-5555-555555555555'
        UserGroup        = '55555555-cccc-5555-5555-555555555555'
        NceAdminsGroup   = '55555555-dddd-5555-5555-555555555555'
        GuestUser        = '66666666-aaaa-6666-6666-666666666666'
        MailboxAppId     = 'dddddddd-1111-dddd-dddd-dddddddddddd'
        MailboxObjectId  = 'dddddddd-2222-dddd-dddd-dddddddddddd'
        LegacyAppId      = 'eeeeeeee-1111-eeee-eeee-eeeeeeeeeeee'
        LegacyObjectId   = 'eeeeeeee-2222-eeee-eeee-eeeeeeeeeeee'
        SignInAppObj     = 'aaaaaaaa-5555-aaaa-aaaa-aaaaaaaaaaaa'
        DeployAppObj     = '33333333-cccc-3333-3333-333333333333'
        DirectorySpId    = 'dddddddd-3333-dddd-dddd-dddddddddddd'
        DirectoryAppId   = 'dddddddd-4444-dddd-dddd-dddddddddddd'
        SqlSpId          = 'dddddddd-5555-dddd-dddd-dddddddddddd'
        SqlAppId         = 'dddddddd-6666-dddd-dddd-dddddddddddd'
    }
    $script:DirectoryIdentityName = 'neologik-directory-managed-identity-abcprd01'
    $script:SqlIdentityName = 'neologik-sql-managed-identity-abcprd01'
    $script:KeyVaultName = 'kvabcprd01'
    $script:DirectoryReadersTemplateId = '88d8e3e3-8f55-4a1e-953a-9b9898b8876b'
    $script:DirectoryReadersRoleId = 'cccccccc-3333-cccc-cccc-cccccccccccc'
    $script:EnvironmentName = 'abcprd'
    $script:DeploymentCredentialName = "github-deployments-$script:EnvironmentName"
    $script:ShortName = 'abcprd01'
    $script:SolutionName = 'neo-abcprd-uks-01'
    $script:RgName = 'rg-neo-abcprd-uks-01'
    $script:RgScope = "/subscriptions/$($script:Ids.Subscription)/resourceGroups/$script:RgName"
    $script:SubScope = "/subscriptions/$($script:Ids.Subscription)"
    $script:AppRoleIds = @{}
    foreach ($roleName in @('Application.ReadWrite.OwnedBy', 'AgentIdentityBlueprint.AddRemoveCreds.All', 'Application.Read.All',
            'AgentIdentityBlueprint.Create', 'AgentIdentityBlueprint.UpdateAuthProperties.All', 'AgentIdentityBlueprintPrincipal.Create',
            'AgentIdentity.Create.All', 'AgentIdUser.ReadWrite.All', 'Group.Create', 'AgentIdUser.ReadWrite.IdentityParentedBy',
            'Sites.Selected', 'Sites.FullControl.All', 'User.Read.All')) {
        $script:AppRoleIds[$roleName] = [guid]::NewGuid().ToString()
    }

    # ----- in-memory tenant ---------------------------------------------------------
    function New-FakeSp {
        param([string]$Id, [string]$AppId, [string]$DisplayName)
        return @{ id = $Id; appId = $AppId; displayName = $DisplayName; owners = @(); appRoleAssignments = @(); grants = @() }
    }

    function New-FakeApp {
        param([string]$Id, [string]$AppId, [string]$DisplayName)
        return @{ id = $Id; appId = $AppId; displayName = $DisplayName; owners = @(); sponsors = @(); credentials = @(); uniqueName = ''; passwordCredentials = @() }
    }

    function Add-FakeAppRole {
        param([string]$SpId, [string]$RoleName)
        $sp = Get-FakeSp -Id $SpId
        $sp.appRoleAssignments += @{ Id = [guid]::NewGuid().ToString(); AppRoleId = $script:AppRoleIds[$RoleName]; ResourceId = $script:Ids.GraphSpId; PrincipalId = $SpId }
    }

    function Get-FakeSp {
        param([string]$Id)
        return @($script:Tenant.ServicePrincipals | Where-Object { $_.id -eq $Id }) | Select-Object -First 1
    }

    function Get-FakeApp {
        param([string]$Id)
        return @($script:Tenant.Apps | Where-Object { $_.id -eq $Id }) | Select-Object -First 1
    }

    function Add-Write {
        param([string]$Description)
        $script:Writes += $Description
    }

    function New-EmptyTenant {
        # The directory as it is before anything Neologik exists, apart from
        # the deployment identity, the Graph service principal, the sign-in
        # application and the NCE user group.
        $t = @{
            Me                    = $script:Ids.Me
            Apps                  = @()
            ServicePrincipals     = @()
            Groups                = @()
            # The accounts the script looks up by mail address (the Neologik guests).
            Users                 = @()
            DirectoryRoles        = @()
            AzRoleAssignments     = @()
            StaleAzRoleAssignments = @()
            StaleAzRoleReads      = 0
            # how many reads after a removal still show the removed assignment
            StaleAzRoleReadsAfterRemoval = 0
            PageSize              = 0
            PrincipalCreateDelays = 0
            GrantRefusals         = @()
            SqlServers            = @()
            # the resource group's tags (the kit version tag lives here).
            ResourceGroupTags     = @{}
            # the directory managed identity on the resource group, when the identity exists.
            DirectoryIdentity     = $null
            # the status with which Azure refuses the creation of the managed identity.
            DirectoryIdentityCreateStatus = 0
            # the SQL managed identity on the resource group, when the identity exists (project#3848).
            SqlIdentity           = $null
            # the registration state of each resource provider and preview feature; an entry
            # absent from the table reads Registered. SlowRegistration keeps a submitted
            # registration at Registering.
            ProviderStates        = @{}
            FeatureStates         = @{}
            SlowRegistration      = $false
            # the Key Vault's access model and the deployment storage account's settings, as
            # the onboarding kit leaves them.
            KeyVaultRbac          = $true
            StorageSettings       = @{ allowSharedKeyAccess = $false; allowBlobPublicAccess = $false; minimumTlsVersion = 'TLS1_2' }
            # The checks of step 5a, compliant: the Flex Consumption plan in the region, vCPU room
            # for the cluster, every classic model already on the Foundry account.
            Quota                 = @{
                FlexRegions  = @('Sweden Central', 'UK South')
                ComputeUsage = @(@{ Name = 'StandardDasv7Family'; Current = 18; Limit = 350 }, @{ Name = 'cores'; Current = 18; Limit = 50 })
                Skus         = @(@{ Name = 'standard_d2as_v7'; Family = 'StandardDasv7Family'; Vcpus = 2 })
                Clusters     = @(@{ Id = "/subscriptions/$($script:Ids.Subscription)/resourceGroups/$script:RgName/providers/Microsoft.ContainerService/managedClusters/aks$script:ShortName"; Name = "aks$script:ShortName"; Pools = @(@{ Name = 'systempool'; VmSize = 'standard_d2as_v7'; Count = 2; MaxCount = 8 }, @{ Name = 'userpool1'; VmSize = 'standard_d2as_v7'; Count = 2; MaxCount = 8 }) })
                AiAccounts   = @(
                    @{ Id = "/subscriptions/$($script:Ids.Subscription)/resourceGroups/$script:RgName/providers/Microsoft.CognitiveServices/accounts/oai-$script:ShortName"; Name = "oai-$script:ShortName"; Kind = 'OpenAI'; Deployments = @(@{ Model = 'gpt-5.4-mini'; Sku = 'GlobalStandard'; Capacity = 1000 }, @{ Model = 'text-embedding-3-large'; Sku = 'Standard'; Capacity = 150 }) },
                    @{ Id = "/subscriptions/$($script:Ids.Subscription)/resourceGroups/$script:RgName/providers/Microsoft.CognitiveServices/accounts/ais-$script:ShortName"; Name = "ais-$script:ShortName"; Kind = 'AIServices'; Deployments = @(@{ Model = 'gpt-5.4-mini'; Sku = 'GlobalStandard'; Capacity = 1000 }, @{ Model = 'text-embedding-3-large'; Sku = 'Standard'; Capacity = 150 }) }
                )
                ModelUsage   = @(@{ Name = 'OpenAI.GlobalStandard.gpt-5.4-mini'; Current = 2000; Limit = 3000 }, @{ Name = 'OpenAI.Standard.text-embedding-3-large'; Current = 300; Limit = 350 })
            }
            # The signed-in administrator: a
            # Global Administrator who owns the subscription.
            MeDirectoryRoles      = @(@{ id = 'role-ga'; displayName = 'Global Administrator'; roleTemplateId = '62e90394-69f5-4237-9190-012177145e10' })
        }
        # Held at the root scope, which every subscription-scoped read inherits.
        $t.AzRoleAssignments += @{ ObjectId = $script:Ids.Me; RoleDefinitionName = 'Owner'; Scope = '/' }
        $t.ServicePrincipals += New-FakeSp -Id $script:Ids.GraphSpId -AppId '00000003-0000-0000-c000-000000000000' -DisplayName 'Microsoft Graph'
        $t.ServicePrincipals += New-FakeSp -Id $script:Ids.DeploySpId -AppId $script:Ids.DeployAppId -DisplayName "Neologik GitHub Service Connection - $script:ShortName"
        $t.ServicePrincipals += New-FakeSp -Id $script:Ids.SignInSpId -AppId $script:Ids.SignInAppId -DisplayName "Neologik Platform Sign-in - $script:ShortName"
        # the sign-in app registration as the onboarding
        # created it - owned by the administrator and the deployment
        # identity, carrying the uniqueName the deployment finds it by.
        $signInApp = New-FakeApp -Id $script:Ids.SignInAppObj -AppId $script:Ids.SignInAppId -DisplayName "Neologik Platform Sign-in - $script:ShortName"
        $signInApp.owners = @($script:Ids.Me, $script:Ids.DeploySpId)
        $signInApp.uniqueName = "sp-admin-$script:SolutionName"
        $t.Apps += $signInApp
        $signInSp = @($t.ServicePrincipals | Where-Object { $_.id -eq $script:Ids.SignInSpId })[0]
        $signInSp.owners = @($script:Ids.Me, $script:Ids.DeploySpId)
        # the application registration of the deployment identity. The onboarding names no owner.
        $t.Apps += New-FakeApp -Id $script:Ids.DeployAppObj -AppId $script:Ids.DeployAppId -DisplayName "GitHub Service Connection - $script:ShortName"
        $t.Groups += @{ id = $script:Ids.Group; displayName = "Neologik NCE User Group - $script:ShortName"; members = @(@{ id = $script:Ids.Me }); appRoleAssignments = @() }
        # the Admin User Group (human administrators) and the
        # environment's SQL server, whose Entra administrator is the group
        # until the platform infrastructure deployment declares the
        # deployment identity.
        $t.Groups += @{ id = $script:Ids.AdminGroup; displayName = "Neologik Admin User Group - $script:ShortName"; members = @(@{ id = $script:Ids.Me }); appRoleAssignments = @() }
        # the onboarding gave the Admin User Group its thirteen roles on the resource group (project#3848).
        foreach ($roleName in $script:AdminGroupRequiredRgRoles) {
            $t.AzRoleAssignments += @{ ObjectId = $script:Ids.AdminGroup; RoleDefinitionName = $roleName; Scope = $script:RgScope }
        }
        # the onboarding created the SQL managed identity and gave the identity Directory Readers (project#3848).
        $t.SqlIdentity = @{ principalId = $script:Ids.SqlSpId; clientId = $script:Ids.SqlAppId }
        $t.ServicePrincipals += New-FakeSp -Id $script:Ids.SqlSpId -AppId $script:Ids.SqlAppId -DisplayName $script:SqlIdentityName
        $t.DirectoryRoles += @{ Id = $script:DirectoryReadersRoleId; RoleTemplateId = $script:DirectoryReadersTemplateId; DisplayName = 'Directory Readers'; members = @($script:Ids.SqlSpId) }
        $t.SqlServers += @{ ServerName = "sql-main-$script:ShortName"; AdminObjectId = $script:Ids.AdminGroup; AdminDisplayName = 'SQL Administrators' }
        return $t
    }

    function Set-LegacyAdminGroupState {
        # The Admin User Group as a v4 onboarding left it (cclprd, 5 November 2026): three
        # roles on the subscription, ten of the thirteen roles on the resource group with
        # Contributor held through the subscription, four extra roles on the resource group
        # and one role on a storage account below the group.
        $t = $script:Tenant
        $t.AzRoleAssignments = @($t.AzRoleAssignments | Where-Object { $_.ObjectId -ne $script:Ids.AdminGroup })
        foreach ($roleName in @('Contributor', 'Cost Management Contributor', 'Monitoring Contributor')) {
            $t.AzRoleAssignments += @{ ObjectId = $script:Ids.AdminGroup; RoleDefinitionName = $roleName; Scope = $script:SubScope }
        }
        foreach ($roleName in @('Azure Kubernetes Service RBAC Cluster Admin', 'Key Vault Administrator', 'Key Vault Secrets Officer', 'Storage Blob Data Owner',
                'Storage Blob Data Contributor', 'Storage Table Data Contributor', 'Cognitive Services Data Reader', 'Cognitive Services OpenAI Contributor',
                'Search Index Data Reader', 'Azure AI Developer', 'AzureML Data Scientist', 'Cognitive Services Contributor', 'Cosmos DB Account Reader Role', 'Search Service Contributor')) {
            $t.AzRoleAssignments += @{ ObjectId = $script:Ids.AdminGroup; RoleDefinitionName = $roleName; Scope = $script:RgScope }
        }
        $t.AzRoleAssignments += @{ ObjectId = $script:Ids.AdminGroup; RoleDefinitionName = 'Storage Blob Data Reader'; Scope = "$script:RgScope/providers/Microsoft.Storage/storageAccounts/stfilesabcprd01" }
    }

    function Get-AdminGroupRoles {
        param([string]$Scope)
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.ObjectId -eq $script:Ids.AdminGroup -and $_.Scope -eq $Scope } |
            ForEach-Object { $_.RoleDefinitionName } | Sort-Object)
    }

    function Add-CompliantDirectoryState {
        # Everything the pre migration script verifies in the directory (steps 1 to 3),
        # already in place.
        $t = $script:Tenant
        $app = New-FakeApp -Id $script:Ids.BlueprintAppObj -AppId $script:Ids.BlueprintAppId -DisplayName "Neologik Agent Blueprint - default - $script:ShortName"
        $app.owners = @($script:Ids.Me, $script:Ids.DeploySpId)
        $app.sponsors = @($script:Ids.Me)
        $app.credentials = @('github-oidc-neo-infrastructure', 'github-oidc-neo-bot-service', 'github-oidc-neo-env-config')
        $t.Apps += $app
        $principal = New-FakeSp -Id $script:Ids.BlueprintSpId -AppId $script:Ids.BlueprintAppId -DisplayName $app.displayName
        $principal.owners = @($script:Ids.Me, $script:Ids.DeploySpId)
        $t.ServicePrincipals += $principal
        Add-FakeAppRole -SpId $script:Ids.BlueprintSpId -RoleName 'AgentIdUser.ReadWrite.IdentityParentedBy'
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'Application.ReadWrite.OwnedBy'
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'AgentIdentityBlueprint.AddRemoveCreds.All'
        (Get-FakeApp -Id $script:Ids.DeployAppObj).credentials = @($script:DeploymentCredentialName)
        $group = @($t.Groups | Where-Object { $_.id -eq $script:Ids.Group })[0]
        $group.appRoleAssignments = @(@{ Id = [guid]::NewGuid().ToString(); ResourceId = $script:Ids.SignInSpId; AppRoleId = '00000000-0000-0000-0000-000000000000' })
        # The security groups of version 5 (project#3127): the user group under its
        # version 5 name, the two groups the onboarding script creates, the Neologik
        # guest and the administrator as members of all four, the NCE Admins group
        # assigned to the sign-in application.
        $group.displayName = "Neologik NCE Contributors - $script:ShortName"
        $group.members = @(@{ id = $script:Ids.Me }, @{ id = $script:Ids.GuestUser })
        $adminGroup = Get-FakeGroup -Id $script:Ids.AdminGroup
        $adminGroup.members = @(@{ id = $script:Ids.Me }, @{ id = $script:Ids.GuestUser })
        $t.Groups += @{ id = $script:Ids.UserGroup; displayName = "Neologik User Group - $script:ShortName"; members = @(@{ id = $script:Ids.Me }, @{ id = $script:Ids.GuestUser }); appRoleAssignments = @() }
        $t.Groups += @{ id = $script:Ids.NceAdminsGroup; displayName = "Neologik NCE Admins - $script:ShortName"; members = @(@{ id = $script:Ids.Me }, @{ id = $script:Ids.GuestUser })
            appRoleAssignments = @(@{ Id = [guid]::NewGuid().ToString(); ResourceId = $script:Ids.SignInSpId; AppRoleId = '00000000-0000-0000-0000-000000000000' }) }
        $t.Users += @{ id = $script:Ids.GuestUser; mail = 'support@neologik.ai'; userPrincipalName = 'support_neologik.ai#EXT#@contoso.onmicrosoft.com'; displayName = 'Neologik Support'; userType = 'Guest' }
        $signIn = Get-FakeSp -Id $script:Ids.SignInSpId
        $signIn.grants = @(@{ id = 'grant-signin'; clientId = $script:Ids.SignInSpId; consentType = 'AllPrincipals'; principalId = $null; resourceId = $script:Ids.GraphSpId; scope = 'User.Read openid profile' })
    }

    function Add-SharePointApp {
        param([switch]$WithConsent, [switch]$Second)
        $t = $script:Tenant
        $sp = New-FakeSp -Id $script:Ids.SharePointSpId -AppId $script:Ids.SharePointAppId -DisplayName "Neologik SharePoint Access - $script:ShortName"
        $t.ServicePrincipals += $sp
        if ($WithConsent) { Add-FakeAppRole -SpId $script:Ids.SharePointSpId -RoleName 'Sites.Selected' }
        if ($Second) {
            $t.ServicePrincipals += New-FakeSp -Id $script:Ids.SharePoint2SpId -AppId $script:Ids.SharePoint2AppId -DisplayName 'Neologik SharePoint Access - other01'
        }
    }

    function Add-EarlierSharePointApp {
        # A hand-made SharePoint application. The customer gave the consent to this
        # application before the deployment created the SharePoint application of
        # the environment.
        param([string]$RoleName = 'Sites.Selected')
        $script:Tenant.ServicePrincipals += New-FakeSp -Id $script:Ids.EarlierSpId -AppId $script:Ids.EarlierAppId -DisplayName 'Neologik SharePoint API Access'
        Add-FakeAppRole -SpId $script:Ids.EarlierSpId -RoleName $RoleName
    }

    function Add-CompliantAzureState {
        # The narrow Azure role set and the retained subscription roles in
        # place, the Application Administrator role held by nobody (step 4).
        $t = $script:Tenant
        foreach ($roleName in $script:RequiredRgRoles) {
            $t.AzRoleAssignments += @{ ObjectId = $script:Ids.DeploySpId; RoleDefinitionName = $roleName; Scope = $script:RgScope }
        }
        foreach ($roleName in $script:RequiredSubRoles) {
            $t.AzRoleAssignments += @{ ObjectId = $script:Ids.DeploySpId; RoleDefinitionName = $roleName; Scope = $script:SubScope }
        }
        $t.AzRoleAssignments += @{ ObjectId = $script:Ids.DeploySpId; RoleDefinitionName = $script:LimitedSubRole; Scope = $script:SubScope; Condition = $script:LimitedSubRoleCondition; ConditionVersion = $script:LimitedSubRoleConditionVersion }
        $t.DirectoryRoles += @{ Id = $script:Ids.AppAdminRole; RoleTemplateId = $script:AppAdminRoleTemplateId; members = @() }
        # an environment kept with this kit carries its version tag.
        $t.ResourceGroupTags = @{ NeologikOnboardingKit = $script:KitVersion }
        Add-CompliantDirectoryIdentity
    }

    function Add-CompliantDirectoryIdentity {
        # The directory managed identity of step 5b, with the permission.
        $t = $script:Tenant
        $t.DirectoryIdentity = @{ principalId = $script:Ids.DirectorySpId; clientId = $script:Ids.DirectoryAppId }
        $t.ServicePrincipals += New-FakeSp -Id $script:Ids.DirectorySpId -AppId $script:Ids.DirectoryAppId -DisplayName $script:DirectoryIdentityName
        Add-FakeAppRole -SpId $script:Ids.DirectorySpId -RoleName 'Application.ReadWrite.OwnedBy'
    }

    function Add-LegacyAzureState {
        # The wide access of an environment onboarded before version 5:
        # Contributor and User Access Administrator on the subscription, and
        # the Application Administrator directory role.
        $t = $script:Tenant
        foreach ($roleName in @('Contributor', 'User Access Administrator')) {
            $t.AzRoleAssignments += @{ ObjectId = $script:Ids.DeploySpId; RoleDefinitionName = $roleName; Scope = $script:SubScope }
        }
        $t.DirectoryRoles += @{ Id = $script:Ids.AppAdminRole; RoleTemplateId = $script:AppAdminRoleTemplateId; members = @($script:Ids.DeploySpId) }
        # a pre-v5 onboarding added the deployment identity to
        # the Admin User Group (its only SQL access while the group is the
        # server administrator).
        Add-AdminGroupMembership
    }

    function Add-LegacyScriptRunnerState {
        # The script runner identity as an onboarding before kit version 5.0.3 left it:
        # Contributor on the subscription and on the resource group, beside the two
        # roles it keeps on the resource group, and no Reader (project#2970).
        $t = $script:Tenant
        $t.AzRoleAssignments += @{ ObjectId = $script:Ids.ScriptRunnerId; RoleDefinitionName = 'Contributor'; Scope = $script:SubScope }
        foreach ($roleName in @('Contributor', 'Key Vault Secrets Officer', 'Azure Bot Service Contributor Role')) {
            $t.AzRoleAssignments += @{ ObjectId = $script:Ids.ScriptRunnerId; RoleDefinitionName = $roleName; Scope = $script:RgScope }
        }
    }

    function Get-ScriptRunnerRoles {
        param([string]$Scope)
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.ObjectId -eq $script:Ids.ScriptRunnerId -and $_.Scope -eq $Scope } |
            ForEach-Object { $_.RoleDefinitionName } | Sort-Object)
    }

    function Add-UndeclaredState {
        # what the audit found beyond the declared set - the
        # evals self-grants at resource-group scope, a subscription-scope
        # leftover, an undeclared resource-scoped role, the declared
        # resource-scoped Content Understanding role (kept), the declared
        # role on the container function-package (kept), the same role on
        # another container, a directory role other than Application
        # Administrator, and a group other than the Admin User Group.
        $t = $script:Tenant
        foreach ($roleName in @('Azure AI Developer', 'Foundry User', 'Reader', 'Search Index Data Reader')) {
            $t.AzRoleAssignments += @{ ObjectId = $script:Ids.DeploySpId; RoleDefinitionName = $roleName; Scope = $script:RgScope }
        }
        $t.AzRoleAssignments += @{ ObjectId = $script:Ids.DeploySpId; RoleDefinitionName = 'Key Vault Secrets Officer'; Scope = $script:SubScope }
        $t.AzRoleAssignments += @{ ObjectId = $script:Ids.DeploySpId; RoleDefinitionName = 'Search Index Data Reader'; Scope = "$script:RgScope/providers/Microsoft.Search/searchServices/srch-$script:ShortName" }
        $t.AzRoleAssignments += @{ ObjectId = $script:Ids.DeploySpId; RoleDefinitionName = 'Cognitive Services Content Understanding Contributor'; Scope = "$script:RgScope/providers/Microsoft.CognitiveServices/accounts/ais-cu-$script:ShortName" }
        $t.AzRoleAssignments += @{ ObjectId = $script:Ids.DeploySpId; RoleDefinitionName = 'Storage Blob Data Contributor'; Scope = "$script:RgScope/providers/Microsoft.Storage/storageAccounts/stfn$script:ShortName/blobServices/default/containers/function-package" }
        $t.AzRoleAssignments += @{ ObjectId = $script:Ids.DeploySpId; RoleDefinitionName = 'Storage Blob Data Contributor'; Scope = "$script:RgScope/providers/Microsoft.Storage/storageAccounts/stfn$script:ShortName/blobServices/default/containers/uploads" }
        $t.DirectoryRoles += @{ Id = $script:Ids.AgentIdAdminRole; RoleTemplateId = 'db506228-d27e-4b7d-95e5-295956d6615f'; DisplayName = 'Agent ID Administrator'; members = @($script:Ids.DeploySpId) }
        $t.Groups += @{ id = $script:Ids.DevTeamGroup; displayName = 'Neologik Dev Team'; members = @(@{ id = $script:Ids.DeploySpId }, @{ id = $script:Ids.Me }); appRoleAssignments = @() }
    }

    function Get-FakeGroup {
        param([string]$Id)
        return @($script:Tenant.Groups | Where-Object { $_.id -eq $Id }) | Select-Object -First 1
    }

    function Add-AdminGroupMembership {
        $group = Get-FakeGroup -Id $script:Ids.AdminGroup
        if (@($group.members | Where-Object { $_.id -eq $script:Ids.DeploySpId }).Count -eq 0) {
            $group.members += @{ id = $script:Ids.DeploySpId }
        }
    }

    function Set-SqlAdministrator {
        # The platform infrastructure deployment's effect: the server's Entra
        # administrator becomes the given object (every server unless named).
        param([string]$ObjectId, [string]$ServerName)
        foreach ($server in $script:Tenant.SqlServers) {
            if ($ServerName -and $server.ServerName -ne $ServerName) { continue }
            $server.AdminObjectId = $ObjectId
            $server.AdminDisplayName = if ($ObjectId -eq $script:Ids.DeploySpId) { "Neologik GitHub Service Connection - $script:ShortName" } else { 'SQL Administrators' }
        }
    }

    function Add-CompliantPreWindowState {
        # Everything the pre migration script verifies, in the directory and in Azure,
        # already in place: the run changes nothing.
        Add-CompliantDirectoryState
        Add-CompliantAzureState
    }

    # ----- Graph request router -------------------------------------------------------
    function Get-QueryValue {
        param([string]$Query, [string]$Name)
        $decoded = [uri]::UnescapeDataString($Query)
        foreach ($part in ($decoded.TrimStart('?') -split '&')) {
            $kv = $part -split '=', 2
            if ($kv[0] -eq $Name -and $kv.Count -eq 2) { return $kv[1] }
        }
        return $null
    }

    function Remove-FakeRefusal {
        # Consumes ONE queued refusal for a scope string (each entry refuses once).
        param([string]$Scope)
        $list = [System.Collections.ArrayList]@($script:Tenant.GrantRefusals)
        $index = $list.IndexOf($Scope)
        if ($index -ge 0) { $list.RemoveAt($index) }
        $script:Tenant.GrantRefusals = @($list)
    }

    function ConvertTo-FakePage {
        # Slices a collection into pages when PageSize is set.
        param([object[]]$Items, [string]$Uri, [string]$Query)
        $pageSize = [int]$script:Tenant.PageSize
        $skip = 0
        $token = Get-QueryValue -Query $Query -Name '$skiptoken'
        if ($token) { $skip = [int]$token }
        if ($pageSize -le 0 -or $Items.Count -le $pageSize) {
            if ($skip -gt 0) { return @{ value = @($Items | Select-Object -Skip $skip) } }
            return @{ value = @($Items) }
        }
        $page = @($Items | Select-Object -Skip $skip -First $pageSize)
        $result = @{ value = $page }
        if ($skip + $pageSize -lt $Items.Count) {
            $base = $Uri -replace '&\$skiptoken=\d+', ''
            $result['@odata.nextLink'] = "$base&`$skiptoken=$($skip + $pageSize)"
        }
        return $result
    }

    function Invoke-FakeGraph {
        param([string]$Method, [string]$Uri, $Body)
        $t = $script:Tenant
        $parsed = [uri]$Uri
        $path = $parsed.AbsolutePath -replace '^/(v1\.0|beta)', ''
        $query = $parsed.Query
        $script:GraphCalls += "$Method $path"
        # Fault injection: the first matching fault with attempts left answers.
        foreach ($fault in @($script:Faults)) {
            if ($fault.Remaining -gt 0 -and "$Method $path" -match $fault.Match) {
                $fault.Remaining--
                $headers = if ($fault.ContainsKey('Headers')) { $fault.Headers } else { @{} }
                return @{ StatusCode = $fault.Status; Headers = $headers; Body = @{ error = @{ code = $fault.Code; message = $fault.Message } } }
            }
        }
        $json = $null
        if ($Body) { $json = $Body | ConvertFrom-Json -AsHashtable }
        switch -Regex ($path) {
            '^/directoryObjects/([^/]+)$' {
                # Any object of the directory by id: a user, a group or a service principal.
                $id = $Matches[1]
                $known = @($t.ServicePrincipals | ForEach-Object { $_.id }) + @($t.Groups | ForEach-Object { $_.id }) + @($t.Users | ForEach-Object { $_.id }) + @($t.Me)
                if ($known -contains $id) { return @{ StatusCode = 200; Headers = @{}; Body = @{ id = $id } } }
                return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } }
            }
            '^/me$' { return @{ StatusCode = 200; Headers = @{}; Body = @{ id = $t.Me; userPrincipalName = 'admin@contoso.com'; displayName = 'Contoso Administrator' } } }
            '^/me/memberOf/microsoft\.graph\.directoryRole$' {
                return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items @($t.MeDirectoryRoles) -Uri $Uri -Query $query) }
            }
            '^/directoryRoles$' {
                # The directory role objects of the tenant (project#3848): a role is activated from
                # its template with POST, and read back by template with a filter.
                if ($Method -eq 'POST') {
                    $role = @{ Id = [guid]::NewGuid().ToString(); RoleTemplateId = [string]$json.roleTemplateId; DisplayName = 'Directory Readers'; members = @() }
                    $t.DirectoryRoles += $role
                    Add-Write "POST directory role $($json.roleTemplateId)"
                    return @{ StatusCode = 201; Headers = @{}; Body = @{ id = $role.Id; roleTemplateId = $role.RoleTemplateId; displayName = $role.DisplayName } }
                }
                $filter = Get-QueryValue -Query $query -Name '$filter'
                $roles = @($t.DirectoryRoles)
                if ($filter -match "^roleTemplateId eq '(.+)'$") { $template = $Matches[1]; $roles = @($t.DirectoryRoles | Where-Object { $_.RoleTemplateId -eq $template }) }
                $items = @($roles | ForEach-Object { @{ id = $_.Id; roleTemplateId = $_.RoleTemplateId; displayName = [string](Get-NeologikProperty $_ 'DisplayName' '') } })
                return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $items -Uri $Uri -Query $query) }
            }
            '^/directoryRoles/([^/]+)/members/\$ref$' {
                $role = @($t.DirectoryRoles | Where-Object { $_.Id -eq $Matches[1] }) | Select-Object -First 1
                if (-not $role) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                $memberId = ($json['@odata.id'] -split '/')[-1]
                if ($role.members -contains $memberId) { return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = 'One or more added object references already exist' } } } }
                $role.members += $memberId
                Add-Write "POST directory role member $($role.Id) $memberId"
                return @{ StatusCode = 204; Headers = @{}; Body = $null }
            }
            '^/applications$' {
                $filter = Get-QueryValue -Query $query -Name '$filter'
                $items = @()
                if ($filter -match "displayName eq '(.+)'$") {
                    $name = $Matches[1] -replace "''", "'"
                    $items = @($t.Apps | Where-Object { $_.displayName -eq $name } | ForEach-Object { @{ id = $_.id; appId = $_.appId; displayName = $_.displayName; uniqueName = $_.uniqueName; passwordCredentials = @($_.passwordCredentials) } })
                }
                elseif ($filter -match "^appId eq '(.+)'$") {
                    $appId = $Matches[1]
                    $items = @($t.Apps | Where-Object { $_.appId -eq $appId } | ForEach-Object { @{ id = $_.id; appId = $_.appId; displayName = $_.displayName; uniqueName = $_.uniqueName; passwordCredentials = @($_.passwordCredentials) } })
                }
                elseif ($filter -match "^startswith\(displayName,'(.+)'\)$") {
                    $prefix = $Matches[1] -replace "''", "'"
                    $items = @($t.Apps | Where-Object { $_.displayName.StartsWith($prefix) } | ForEach-Object { @{ id = $_.id; appId = $_.appId; displayName = $_.displayName } })
                }
                return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $items -Uri $Uri -Query $query) }
            }
            '^/applications/microsoft\.graph\.agentIdentityBlueprint$' {
                Add-Write "POST blueprint $($json.displayName)"
                $app = New-FakeApp -Id ([guid]::NewGuid().ToString()) -AppId ([guid]::NewGuid().ToString()) -DisplayName $json.displayName
                $app.owners = @($t.Me)
                foreach ($bind in @($json['owners@odata.bind'])) { $app.owners += ($bind -split '/')[-1] }
                # Microsoft Graph refuses a blueprint with no sponsor.
                if (@($json['sponsors@odata.bind']).Count -eq 0) { return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = 'A sponsor is required' } } } }
                foreach ($bind in @($json['sponsors@odata.bind'])) { $app.sponsors += ($bind -split '/')[-1] }
                $t.Apps += $app
                return @{ StatusCode = 201; Headers = @{}; Body = @{ id = $app.id; appId = $app.appId; displayName = $app.displayName } }
            }
            '^/applications/([^/]+)$' {
                $app = Get-FakeApp -Id $Matches[1]
                if (-not $app) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                if ($Method -eq 'PATCH') {
                    Add-Write "PATCH application $($app.displayName) uniqueName=$($json.uniqueName)"
                    $app.uniqueName = [string]$json.uniqueName
                    return @{ StatusCode = 204; Headers = @{}; Body = $null }
                }
                return @{ StatusCode = 200; Headers = @{}; Body = @{ id = $app.id; appId = $app.appId; displayName = $app.displayName; uniqueName = $app.uniqueName; passwordCredentials = @($app.passwordCredentials) } }
            }
            '^/applications/([^/]+)/microsoft\.graph\.agentIdentityBlueprint/sponsors$' {
                $app = Get-FakeApp -Id $Matches[1]
                if (-not $app) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                $items = @($app.sponsors | ForEach-Object { @{ id = $_; displayName = $(if ($_ -eq $t.Me) { 'Contoso Administrator' } else { '' }) } })
                return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $items -Uri $Uri -Query $query) }
            }
            '^/applications/([^/]+)/microsoft\.graph\.agentIdentityBlueprint/sponsors/\$ref$' {
                $app = Get-FakeApp -Id $Matches[1]
                if (-not $app) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                $sponsor = ($json['@odata.id'] -split '/')[-1]
                Add-Write "POST blueprint sponsor $sponsor"
                $app.sponsors += $sponsor
                return @{ StatusCode = 204; Headers = @{}; Body = $null }
            }
            '^/applications/([^/]+)/owners$' {
                $app = Get-FakeApp -Id $Matches[1]
                if (-not $app) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                $items = @($app.owners | ForEach-Object { @{ id = $_ } })
                return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $items -Uri $Uri -Query $query) }
            }
            '^/applications/([^/]+)/owners/\$ref$' {
                $app = Get-FakeApp -Id $Matches[1]
                if (-not $app) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                $owner = ($json['@odata.id'] -split '/')[-1]
                if ($app.owners -contains $owner) { return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = 'One or more added object references already exist' } } } }
                Add-Write "POST app owner $owner"
                $app.owners += $owner
                return @{ StatusCode = 204; Headers = @{}; Body = $null }
            }
            '^/applications/([^/]+)/federatedIdentityCredentials$' {
                $app = Get-FakeApp -Id $Matches[1]
                if (-not $app) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                if ($Method -eq 'GET') {
                    $items = @($app.credentials | ForEach-Object { @{ name = $_ } })
                    return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $items -Uri $Uri -Query $query) }
                }
                if ($app.credentials -contains $json.name) { return @{ StatusCode = 409; Headers = @{}; Body = @{ error = @{ code = 'Request_MultipleObjectsWithSameKeyValue'; message = 'FederatedIdentityCredential with name already exists.' } } } }
                Add-Write "POST credential $($json.name)"
                $app.credentials += $json.name
                return @{ StatusCode = 201; Headers = @{}; Body = @{ id = [guid]::NewGuid().ToString(); name = $json.name } }
            }
            '^/servicePrincipals/(?!microsoft\.graph)([^/]+)$' {
                $sp = Get-FakeSp -Id $Matches[1]
                if (-not $sp) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                return @{ StatusCode = 200; Headers = @{}; Body = @{ id = $sp.id; appId = $sp.appId; displayName = $sp.displayName } }
            }
            '^/servicePrincipals$' {
                $filter = Get-QueryValue -Query $query -Name '$filter'
                $items = @()
                if ($filter -match "^appId eq '(.+)'$") {
                    $appId = $Matches[1]
                    $items = @($t.ServicePrincipals | Where-Object { $_.appId -eq $appId })
                }
                elseif ($filter -match "^displayName eq '(.+)'$") {
                    $name = $Matches[1] -replace "''", "'"
                    $items = @($t.ServicePrincipals | Where-Object { $_.displayName -eq $name })
                }
                elseif ($filter -match "^startswith\(displayName,'(.+)'\)$") {
                    $prefix = $Matches[1] -replace "''", "'"
                    $items = @($t.ServicePrincipals | Where-Object { $_.displayName.StartsWith($prefix) })
                }
                $projected = @($items | ForEach-Object { @{ id = $_.id; appId = $_.appId; displayName = $_.displayName } })
                return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $projected -Uri $Uri -Query $query) }
            }
            '^/servicePrincipals/microsoft\.graph\.agentIdentityBlueprintPrincipal$' {
                $app = @($t.Apps | Where-Object { $_.appId -eq $json.appId }) | Select-Object -First 1
                if (-not $app) { return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = 'The appId does not exist' } } } }
                if ($t.PrincipalCreateDelays -gt 0) {
                    $t.PrincipalCreateDelays--
                    return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = 'The application must exist in the local tenant' } } }
                }
                Add-Write "POST blueprint principal $($json.appId)"
                $sp = New-FakeSp -Id ([guid]::NewGuid().ToString()) -AppId $json.appId -DisplayName $app.displayName
                # Microsoft Graph gives a new blueprint service principal no owner, apart from
                # each owner bound in the request.
                $sp.owners = @(@($json['owners@odata.bind']) | Where-Object { $_ } | ForEach-Object { ([string]$_ -split '/')[-1] })
                $t.ServicePrincipals += $sp
                return @{ StatusCode = 201; Headers = @{}; Body = @{ id = $sp.id; appId = $sp.appId } }
            }
            '^/servicePrincipals/([^/]+)/owners$' {
                $sp = Get-FakeSp -Id $Matches[1]
                if (-not $sp) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                $items = @($sp.owners | ForEach-Object { @{ id = $_ } })
                return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $items -Uri $Uri -Query $query) }
            }
            '^/servicePrincipals/([^/]+)/owners/\$ref$' {
                $sp = Get-FakeSp -Id $Matches[1]
                if (-not $sp) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                $owner = ($json['@odata.id'] -split '/')[-1]
                if ($sp.owners -contains $owner) { return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = 'One or more added object references already exist' } } } }
                Add-Write "POST sp owner $owner"
                $sp.owners += $owner
                return @{ StatusCode = 204; Headers = @{}; Body = $null }
            }
            '^/groups$' {
                if ($Method -eq 'POST') {
                    Add-Write "POST group $($json.displayName)"
                    $group = @{ id = [guid]::NewGuid().ToString(); displayName = [string]$json.displayName; description = [string]$json.description; members = @(); appRoleAssignments = @() }
                    $t.Groups += $group
                    return @{ StatusCode = 201; Headers = @{}; Body = @{ id = $group.id; displayName = $group.displayName } }
                }
                $filter = Get-QueryValue -Query $query -Name '$filter'
                $items = @()
                if ($filter -match "^displayName eq '(.+)'$") {
                    $name = $Matches[1] -replace "''", "'"
                    $items = @($t.Groups | Where-Object { $_.displayName -eq $name } | ForEach-Object { @{ id = $_.id; displayName = $_.displayName } })
                }
                return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $items -Uri $Uri -Query $query) }
            }
            '^/groups/([^/]+)$' {
                $group = Get-FakeGroup -Id $Matches[1]
                if (-not $group) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                if ($Method -eq 'PATCH') {
                    Add-Write "PATCH group $($group.displayName) displayName=$($json.displayName)"
                    $group.displayName = [string]$json.displayName
                    return @{ StatusCode = 204; Headers = @{}; Body = $null }
                }
                return @{ StatusCode = 200; Headers = @{}; Body = @{ id = $group.id; displayName = $group.displayName } }
            }
            '^/groups/([^/]+)/members$' {
                $group = Get-FakeGroup -Id $Matches[1]
                if (-not $group) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                $items = @($group.members | ForEach-Object { @{ id = $_.id } })
                return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $items -Uri $Uri -Query $query) }
            }
            '^/groups/([^/]+)/members/\$ref$' {
                $group = Get-FakeGroup -Id $Matches[1]
                if (-not $group) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                $memberId = ($json['@odata.id'] -split '/')[-1]
                if (@($group.members | Where-Object { $_.id -eq $memberId }).Count -gt 0) { return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = 'One or more added object references already exist' } } } }
                Add-Write "POST group member $($group.displayName) $memberId"
                $group.members += @{ id = $memberId }
                return @{ StatusCode = 204; Headers = @{}; Body = $null }
            }
            '^/users$' {
                $filter = Get-QueryValue -Query $query -Name '$filter'
                $items = @()
                if ($filter -match "^mail eq '(.+)' or userPrincipalName eq '(.+)'$") {
                    $address = $Matches[1] -replace "''", "'"
                    $items = @($t.Users | Where-Object { $_.mail -eq $address -or $_.userPrincipalName -eq $address } |
                        ForEach-Object { @{ id = $_.id; displayName = $_.displayName; userPrincipalName = $_.userPrincipalName; userType = $_.userType } })
                }
                return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $items -Uri $Uri -Query $query) }
            }
            '^/invitations$' {
                $email = [string]$json.invitedUserEmailAddress
                Add-Write "POST invitation $email"
                $user = @{ id = [guid]::NewGuid().ToString(); mail = $email; userPrincipalName = (($email -replace '@', '_') + '#EXT#@contoso.onmicrosoft.com'); displayName = $email; userType = 'Guest' }
                $t.Users += $user
                return @{ StatusCode = 201; Headers = @{}; Body = @{ id = [guid]::NewGuid().ToString(); invitedUser = @{ id = $user.id }; status = 'PendingAcceptance' } }
            }
            '^/oauth2PermissionGrants$' {
                if ($Method -eq 'GET') {
                    $filter = Get-QueryValue -Query $query -Name '$filter'
                    $items = @()
                    if ($filter -match "clientId eq '([^']+)' and principalId eq '([^']+)' and resourceId eq '([^']+)'") {
                        $clientId = $Matches[1]; $principalId = $Matches[2]; $resourceId = $Matches[3]
                        $sp = Get-FakeSp -Id $clientId
                        if ($sp) { $items = @($sp.grants | Where-Object { $_.principalId -eq $principalId -and $_.resourceId -eq $resourceId }) }
                    }
                    return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $items -Uri $Uri -Query $query) }
                }
                if ($t.GrantRefusals -contains $json.scope) {
                    Remove-FakeRefusal -Scope $json.scope
                    return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = "Invalid value specified for property 'scope'" } } }
                }
                $sp = Get-FakeSp -Id $json.clientId
                $grant = @{ id = [guid]::NewGuid().ToString(); clientId = $json.clientId; principalId = $json.principalId; resourceId = $json.resourceId; consentType = $json.consentType; scope = $json.scope }
                $sp.grants += $grant
                Add-Write "POST grant $($json.clientId) $($json.scope)"
                return @{ StatusCode = 201; Headers = @{}; Body = $grant }
            }
            '^/oauth2PermissionGrants/([^/]+)$' {
                $grantId = $Matches[1]
                if ($t.GrantRefusals -contains $json.scope) {
                    Remove-FakeRefusal -Scope $json.scope
                    return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = "Invalid value specified for property 'scope'" } } }
                }
                foreach ($sp in $t.ServicePrincipals) {
                    foreach ($grant in $sp.grants) {
                        if ($grant.id -eq $grantId) {
                            $grant.scope = $json.scope
                            Add-Write "PATCH grant $grantId $($json.scope)"
                            return @{ StatusCode = 204; Headers = @{}; Body = $null }
                        }
                    }
                }
                return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'grant not found' } } }
            }
        }
        return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = "no route for $Method $path" } } }
    }

    function ConvertTo-SpObject {
        param($Sp)
        $appRoles = @()
        if ($Sp.id -eq $script:Ids.GraphSpId) {
            $appRoles = @($script:AppRoleIds.Keys | ForEach-Object { [pscustomobject]@{ Id = $script:AppRoleIds[$_]; Value = $_ } })
        }
        return [pscustomobject]@{ Id = $Sp.id; AppId = $Sp.appId; DisplayName = $Sp.displayName; AppRoles = $appRoles }
    }

    function New-NotFoundException {
        param([string]$Message = 'Request_ResourceNotFound: Resource does not exist')
        return [System.Net.Http.HttpRequestException]::new($Message, $null, [System.Net.HttpStatusCode]::NotFound)
    }

    function New-ForbiddenException {
        return [System.Net.Http.HttpRequestException]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.', $null, [System.Net.HttpStatusCode]::Forbidden)
    }

    # ----- fixtures ---------------------------------------------------------------------
    function New-ConfigFile {
        param([string]$Path = (Join-Path $TestDrive 'config.json'), [hashtable]$Overrides = @{}, [string[]]$Remove = @())
        $config = [ordered]@{
            OrganizationName  = 'Contoso Ltd'
            TenantId          = $script:Ids.Tenant
            SubscriptionId    = $script:Ids.Subscription
            ResourceGroupName = $script:RgName
            SolutionShortName = $script:ShortName
            SolutionName      = $script:SolutionName
            AppRegistration   = @{ Name = 'Neologik GitHub Service Connection'; ClientId = $script:Ids.DeployAppId }
            NceAuthApp        = @{ ClientId = $script:Ids.SignInAppId }
            SecurityGroups    = @(
                @{ Name = "Neologik NCE User Group - $script:ShortName"; Id = $script:Ids.Group },
                @{ Name = "Neologik Admin User Group - $script:ShortName"; Id = $script:Ids.AdminGroup }
            )
        }
        foreach ($key in $Overrides.Keys) { $config[$key] = $Overrides[$key] }
        foreach ($key in $Remove) { $config.Remove($key) }
        $config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
        return $Path
    }

    function Get-SummaryResult {
        param([string]$Item)
        $row = @($script:Summary | Where-Object { $_.Item -eq $Item }) | Select-Object -First 1
        if ($row) { return $row.Result }
        return $null
    }

    function Invoke-Run {
        # Runs the main entry and returns its single output (the exit code). The kit
        # version is on every command from Neologik, so the fixture adds it unless the
        # test gives one.
        param([hashtable]$Parameters)
        if (-not $Parameters.ContainsKey('KitVersion')) { $Parameters = $Parameters + @{ KitVersion = $script:KitVersion } }
        if (-not $Parameters.ContainsKey('DirectoryIdentityName')) { $Parameters = $Parameters + @{ DirectoryIdentityName = $script:DirectoryIdentityName } }
        if (-not $Parameters.ContainsKey('EnvironmentName')) { $Parameters = $Parameters + @{ EnvironmentName = $script:EnvironmentName } }
        if (-not $Parameters.ContainsKey('SqlIdentityName')) { $Parameters = $Parameters + @{ SqlIdentityName = $script:SqlIdentityName } }
        if (-not $Parameters.ContainsKey('KeyVaultName')) { $Parameters = $Parameters + @{ KeyVaultName = $script:KeyVaultName } }
        $output = @(Invoke-NeologikEnvironmentMigration @Parameters)
        $output.Count | Should -Be 1 -Because 'the main entry must emit exactly one object: the exit code'
        $output[0] | Should -BeOfType [int]
        return [int]$output[0]
    }

    # ----- default mocks: a healthy machine, tenant answers from the model -------------
    Mock Write-Host { param($Object) $script:Console += [string]$Object }
    Mock Start-Sleep { param($Seconds) $script:Sleeps += [int]$Seconds }
    Mock Get-NeologikAvailableModuleVersion { param($Name) @([version]'2.38.0') }
    Mock Get-NeologikLoadedModuleVersion { $null }
    Mock Install-NeologikModule { param($Name) $script:Installs += $Name }
    Mock Import-NeologikModule { param($Name, $RequiredVersion) $script:Imports += "$Name $RequiredVersion" }
    Mock Test-NeologikCommand { $true }
    Mock Invoke-NeologikAzureCli { @{ ExitCode = 0; Output = @('eyJ0b2tlbg') } }
    # every endpoint answers, and the script's own device code
    # completes on the first poll (the identity platform is never contacted).
    Mock Test-NeologikEndpoint { $true }
    Mock Invoke-NeologikTokenRequest {
        param($Uri, $Body)
        $script:TokenRequests += @{ Uri = $Uri; Body = $Body }
        if ($Uri -match '/devicecode$') {
            return @{ StatusCode = 200; Body = @{ device_code = 'dc-1'; user_code = 'ABCD-EFGH'; verification_uri = 'https://microsoft.com/devicelogin'; expires_in = 900; interval = 5 } }
        }
        return @{ StatusCode = 200; Body = @{ access_token = 'eyJ0b2tlbg'; refresh_token = 'rt-1' } }
    }
    # The browser sign-in: by default no browser opens, so a run falls back to the
    # device code above. The context 'Browser sign-in' opens the browser.
    Mock Start-NeologikLoopbackListener {
        [pscustomobject]@{ Port = 50999 } | Add-Member -MemberType ScriptMethod -Name Stop -Value { } -PassThru
    }
    Mock Open-NeologikBrowser { param($Uri) $script:BrowserUris += $Uri; $script:BrowserOpens }
    Mock Test-NeologikDesktop { $script:Desktop }
    Mock Get-NeologikSummaryDirectory { @($script:SummaryDirs) }
    Mock Get-NeologikGuestUsersFileDefault { $script:GuestFile }
    # The storage account of the environment (project#3171): the first
    # $script:UploadRefusals uploads are refused as a missing data role is.
    Mock Get-AzStorageAccount { @($script:StorageAccounts | ForEach-Object { @{ StorageAccountName = $_ } }) }
    Mock New-AzStorageContext { param($StorageAccountName) if ($script:UnreachableAccounts -contains $StorageAccountName) { throw "Name or service not known: $StorageAccountName.blob.core.windows.net" }; @{ StorageAccountName = $StorageAccountName } }
    Mock Get-AzStorageContainer { param($Name) if ($script:StorageContainers -contains $Name) { @{ Name = $Name } } else { $null } }
    Mock New-AzStorageContainer { param($Name) $script:StorageContainers += $Name; Add-Write "NEW container $Name" }
    Mock Set-AzStorageBlobContent {
        param($File, $Container, $Blob)
        if ($script:UploadRefusals -gt 0) { $script:UploadRefusals--; throw 'AuthorizationPermissionMismatch: This request is not authorized to perform this operation using this permission.' }
        $script:Uploads += "$Container/$Blob"
    }
    # The blob service, for the upload with the token for Azure Storage: the same containers,
    # refusals and unreachable accounts as the Az.Storage mocks above.
    Mock Invoke-NeologikBlobRequest {
        param($Method, $Uri, $Token, $InFile)
        $script:BlobRequests += @{ Method = $Method; Uri = $Uri; Token = $Token; InFile = $InFile }
        if ($Uri -notmatch '^https://([^.]+)\.blob\.core\.windows\.net/([^/?]+)(?:/([^?]+))?(\?restype=container)?$') { throw "unexpected blob uri $Uri" }
        $account = $Matches[1]; $container = $Matches[2]; $blob = $Matches[3]
        if ($script:UnreachableAccounts -contains $account) { throw "Name or service not known: $account.blob.core.windows.net" }
        if ($Uri -like '*restype=container') {
            if ($Method -eq 'GET') { if ($script:StorageContainers -contains $container) { return 200 } else { return 404 } }
            $script:StorageContainers += $container
            Add-Write "NEW container $container"
            return 201
        }
        if ($script:UploadRefusals -gt 0) { $script:UploadRefusals--; return 403 }
        $script:Uploads += "$container/$blob"
        return 201
    }
    Mock Invoke-NeologikGraphRaw { param($Method, $Uri, $Body) Invoke-FakeGraph -Method $Method -Uri $Uri -Body $Body }
    Mock Connect-MgGraph { $script:Connected = $true }
    Mock Get-MgContext { [pscustomobject]@{ TenantId = $script:ContextTenant; Account = 'admin@contoso.com'; Scopes = @($script:ContextScopes) } }
    Mock Get-MgServicePrincipal {
        param($Filter)
        if ($Filter -match "appId eq '([^']+)'") {
            $appId = $Matches[1]
            $sp = @($script:Tenant.ServicePrincipals | Where-Object { $_.appId -eq $appId }) | Select-Object -First 1
            if ($sp) { ConvertTo-SpObject -Sp $sp }
        }
    }
    Mock Get-MgServicePrincipalAppRoleAssignment {
        param($ServicePrincipalId)
        $sp = Get-FakeSp -Id $ServicePrincipalId
        if (-not $sp) { throw (New-NotFoundException) }
        @($sp.appRoleAssignments | ForEach-Object { [pscustomobject]$_ })
    }
    Mock New-MgServicePrincipalAppRoleAssignment {
        param($ServicePrincipalId, $PrincipalId, $ResourceId, $AppRoleId)
        $sp = Get-FakeSp -Id $ServicePrincipalId
        $sp.appRoleAssignments += @{ Id = [guid]::NewGuid().ToString(); AppRoleId = $AppRoleId; ResourceId = $ResourceId; PrincipalId = $PrincipalId }
        Add-Write "NEW approle $ServicePrincipalId $AppRoleId"
    }
    Mock Remove-MgServicePrincipalAppRoleAssignment {
        param($ServicePrincipalId, $AppRoleAssignmentId)
        $sp = Get-FakeSp -Id $ServicePrincipalId
        $sp.appRoleAssignments = @($sp.appRoleAssignments | Where-Object { $_.Id -ne $AppRoleAssignmentId })
        Add-Write "REMOVE approle $ServicePrincipalId $AppRoleAssignmentId"
    }
    Mock Get-MgGroupAppRoleAssignment {
        param($GroupId)
        $group = @($script:Tenant.Groups | Where-Object { $_.id -eq $GroupId }) | Select-Object -First 1
        if (-not $group) { throw (New-NotFoundException) }
        @($group.appRoleAssignments | ForEach-Object { [pscustomobject]$_ })
    }
    Mock New-MgGroupAppRoleAssignment {
        param($GroupId, $PrincipalId, $ResourceId, $AppRoleId)
        $group = @($script:Tenant.Groups | Where-Object { $_.id -eq $GroupId }) | Select-Object -First 1
        $group.appRoleAssignments += @{ Id = [guid]::NewGuid().ToString(); ResourceId = $ResourceId; AppRoleId = $AppRoleId }
        Add-Write "NEW group assignment $GroupId $ResourceId"
    }
    Mock Get-MgGroup {
        param($GroupId)
        $group = @($script:Tenant.Groups | Where-Object { $_.id -eq $GroupId }) | Select-Object -First 1
        if (-not $group) { throw (New-NotFoundException) }
        [pscustomobject]@{ Id = $group.id; DisplayName = $group.displayName }
    }
    Mock Get-MgGroupMember {
        param($GroupId)
        $group = @($script:Tenant.Groups | Where-Object { $_.id -eq $GroupId }) | Select-Object -First 1
        if (-not $group) { throw (New-NotFoundException) }
        @($group.members | ForEach-Object { [pscustomobject]@{ Id = $_.id } })
    }
    Mock Get-MgServicePrincipalOauth2PermissionGrant {
        param($ServicePrincipalId)
        $sp = Get-FakeSp -Id $ServicePrincipalId
        if (-not $sp) { throw (New-NotFoundException) }
        @($sp.grants | ForEach-Object { [pscustomobject]@{ Id = $_.id; ConsentType = $_.consentType; Scope = $_.scope; ResourceId = $_.resourceId } })
    }
    # Graph's directoryRoles/{id}/members omits service principals (verified on
    # the dev tenant 2026-09-08): the script never reads a role's
    # member list, and these two throw so any return to that read fails a test.
    Mock Get-MgDirectoryRole { throw 'Get-MgDirectoryRole is not used: read the identity''s memberOf list' }
    Mock Get-MgDirectoryRoleMember { throw 'Get-MgDirectoryRoleMember omits service principals: read the identity''s memberOf list' }
    Mock Get-MgServicePrincipalMemberOf {
        param($ServicePrincipalId)
        $groups = @($script:Tenant.Groups | Where-Object { @($_.members | Where-Object { $_.id -eq $ServicePrincipalId }).Count -gt 0 } |
            ForEach-Object { [pscustomobject]@{ Id = $_.id; AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.group'; displayName = $_.displayName } } })
        $roles = @($script:Tenant.DirectoryRoles | Where-Object { @($_.members | Where-Object { $_ -eq $ServicePrincipalId }).Count -gt 0 } |
            ForEach-Object { [pscustomobject]@{ Id = $_.Id; AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.directoryRole'; displayName = [string](Get-NeologikProperty $_ 'DisplayName' ''); roleTemplateId = $_.RoleTemplateId } } })
        @($groups + $roles)
    }
    Mock Remove-MgDirectoryRoleMemberDirectoryObjectByRef {
        param($DirectoryRoleId, $DirectoryObjectId)
        $role = @($script:Tenant.DirectoryRoles | Where-Object { $_.Id -eq $DirectoryRoleId }) | Select-Object -First 1
        $role.members = @($role.members | Where-Object { $_ -ne $DirectoryObjectId })
        Add-Write "REMOVE directory role member $DirectoryObjectId"
    }
    Mock Remove-MgGroupMemberByRef {
        param($GroupId, $DirectoryObjectId)
        $group = @($script:Tenant.Groups | Where-Object { $_.id -eq $GroupId }) | Select-Object -First 1
        if (-not $group) { throw (New-NotFoundException) }
        $group.members = @($group.members | Where-Object { $_.id -ne $DirectoryObjectId })
        Add-Write "REMOVE group member $DirectoryObjectId"
    }
    Mock Get-AzSqlServer {
        param($ResourceGroupName)
        @($script:Tenant.SqlServers | ForEach-Object { [pscustomobject]@{ ServerName = $_.ServerName; ResourceGroupName = $ResourceGroupName } })
    }
    Mock Get-AzSqlServerActiveDirectoryAdministrator {
        param($ResourceGroupName, $ServerName)
        $server = @($script:Tenant.SqlServers | Where-Object { $_.ServerName -eq $ServerName }) | Select-Object -First 1
        if (-not $server) { throw (New-NotFoundException) }
        [pscustomobject]@{ ObjectId = $server.AdminObjectId; DisplayName = $server.AdminDisplayName; ResourceGroupName = $ResourceGroupName; ServerName = $ServerName }
    }
    Mock Connect-AzAccount { $script:AzConnected = $true }
    Mock Disable-AzContextAutosave { $script:AzIsolated = @($script:AzIsolated) + 'autosave off' }
    Mock Clear-AzContext { $script:AzIsolated = @($script:AzIsolated) + 'cleared' }
    Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = $script:AzContextSubscription } } }
    Mock Get-AzResourceGroup {
        param($Name)
        [pscustomobject]@{ ResourceGroupName = $Name; ResourceId = $script:RgScope; Location = 'uksouth'; Tags = $script:Tenant.ResourceGroupTags }
    }
    # Azure Resource Manager reads of the quota step (5a): routed by path to the quota fixture.
    Mock Invoke-AzRestMethod {
        param($Method, $Path, $Payload)
        if ($Path -match 'Microsoft\.ManagedIdentity/userAssignedIdentities/([^/?]+)' -and $Matches[1] -eq $script:SqlIdentityName) {
            # The SQL managed identity of the kit standard (project#3848): read, never written.
            if (-not $script:Tenant.SqlIdentity) { return [pscustomobject]@{ StatusCode = 404; Content = '{"error":{"code":"ResourceNotFound","message":"absent"}}' } }
            return [pscustomobject]@{ StatusCode = 200; Content = (@{ name = $script:SqlIdentityName; properties = $script:Tenant.SqlIdentity } | ConvertTo-Json -Depth 5) }
        }
        if ($Path -match '^/subscriptions/[^/]+/providers/Microsoft\.Features/providers/([^/]+)/features/([^/?]+)(/register)?\?api-version=') {
            $key = "$($Matches[1])/$($Matches[2])"
            if ($Method -eq 'POST') {
                Add-Write "REGISTER feature $key"
                $script:Tenant.FeatureStates[$key] = $(if ($script:Tenant.SlowRegistration) { 'Registering' } else { 'Registered' })
                return [pscustomobject]@{ StatusCode = 200; Content = '{}' }
            }
            $featureState = if ($script:Tenant.FeatureStates.ContainsKey($key)) { $script:Tenant.FeatureStates[$key] } else { 'Registered' }
            return [pscustomobject]@{ StatusCode = 200; Content = (@{ name = $key; properties = @{ state = $featureState } } | ConvertTo-Json -Depth 5) }
        }
        if ($Path -match '^/subscriptions/[^/]+/providers/([^/?]+)(/register)?\?api-version=') {
            $namespace = $Matches[1]
            if ($Method -eq 'POST') {
                Add-Write "REGISTER provider $namespace"
                $script:Tenant.ProviderStates[$namespace] = $(if ($script:Tenant.SlowRegistration) { 'Registering' } else { 'Registered' })
                return [pscustomobject]@{ StatusCode = 200; Content = '{}' }
            }
            $providerState = if ($script:Tenant.ProviderStates.ContainsKey($namespace)) { $script:Tenant.ProviderStates[$namespace] } else { 'Registered' }
            return [pscustomobject]@{ StatusCode = 200; Content = (@{ namespace = $namespace; registrationState = $providerState } | ConvertTo-Json -Depth 5) }
        }
        if ($Path -match 'Microsoft\.KeyVault/vaults/([^/?]+)\?api-version=') {
            $vaultName = $Matches[1]
            if ($vaultName -ne $script:KeyVaultName) { return [pscustomobject]@{ StatusCode = 404; Content = '{"error":{"code":"ResourceNotFound","message":"absent"}}' } }
            if ($Method -eq 'PATCH') {
                $script:Tenant.KeyVaultRbac = [bool](($Payload | ConvertFrom-Json).properties.enableRbacAuthorization)
                Add-Write "PATCH vault $vaultName enableRbacAuthorization=$($script:Tenant.KeyVaultRbac)"
            }
            return [pscustomobject]@{ StatusCode = 200; Content = (@{ name = $vaultName; properties = @{ enableRbacAuthorization = $script:Tenant.KeyVaultRbac } } | ConvertTo-Json -Depth 5) }
        }
        if ($Path -match 'Microsoft\.Storage/storageAccounts/([^/?]+)/blobServices/default/containers/([^/?]+)\?api-version=') {
            $containerName = $Matches[2]
            if ($Method -eq 'PUT') {
                $script:StorageContainers += $containerName
                Add-Write "PUT container $containerName"
                return [pscustomobject]@{ StatusCode = 201; Content = (@{ name = $containerName } | ConvertTo-Json) }
            }
            if ($script:StorageContainers -contains $containerName) { return [pscustomobject]@{ StatusCode = 200; Content = (@{ name = $containerName } | ConvertTo-Json) } }
            return [pscustomobject]@{ StatusCode = 404; Content = '{"error":{"code":"ContainerNotFound","message":"absent"}}' }
        }
        if ($Path -match 'Microsoft\.Storage/storageAccounts/([^/?]+)\?api-version=') {
            $accountName = $Matches[1]
            if ($accountName -eq 'stneodeploymissing01') { return [pscustomobject]@{ StatusCode = 404; Content = '{"error":{"code":"ResourceNotFound","message":"absent"}}' } }
            if ($Method -eq 'PATCH') {
                $changes = ($Payload | ConvertFrom-Json).properties
                $changed = @()
                foreach ($property in @($changes.PSObject.Properties | Sort-Object Name)) { $script:Tenant.StorageSettings[$property.Name] = $property.Value; $changed += "$($property.Name)=$($property.Value)" }
                Add-Write "PATCH storage $accountName $($changed -join ' ')"
            }
            return [pscustomobject]@{ StatusCode = 200; Content = (@{ name = $accountName; properties = $script:Tenant.StorageSettings } | ConvertTo-Json -Depth 5) }
        }
        if ($Path -match 'Microsoft\.ManagedIdentity/userAssignedIdentities/([^/?]+)') {
            $identityName = $Matches[1]
            if ($Method -eq 'PUT') {
                if ($script:Tenant.DirectoryIdentityCreateStatus) { return [pscustomobject]@{ StatusCode = $script:Tenant.DirectoryIdentityCreateStatus; Content = '{"error":{"code":"AuthorizationFailed","message":"refused"}}' } }
                Add-Write "PUT managed identity $identityName"
                $script:DirectoryIdentityPayload = $Payload
                $script:Tenant.DirectoryIdentity = @{ principalId = $script:Ids.DirectorySpId; clientId = $script:Ids.DirectoryAppId }
                $script:Tenant.ServicePrincipals += New-FakeSp -Id $script:Ids.DirectorySpId -AppId $script:Ids.DirectoryAppId -DisplayName $identityName
            }
            elseif (-not $script:Tenant.DirectoryIdentity) { return [pscustomobject]@{ StatusCode = 404; Content = '{"error":{"code":"ResourceNotFound","message":"absent"}}' } }
            return [pscustomobject]@{ StatusCode = 200; Content = (@{ name = $identityName; properties = $script:Tenant.DirectoryIdentity } | ConvertTo-Json -Depth 5) }
        }
        $script:ArmReads += $Path
        $q = $script:Tenant.Quota
        $body = $null
        if ($Path -match 'Microsoft\.Web/geoRegions\?') { $body = @{ value = @($q.FlexRegions | ForEach-Object { @{ name = $_; properties = @{ name = $_; displayName = $_ } } }) } }
        elseif ($Path -match "resourceType eq 'Microsoft\.ContainerService/managedClusters'") { $body = @{ value = @($q.Clusters | ForEach-Object { @{ id = $_.Id; name = $_.Name } }) } }
        elseif ($Path -match '/agentPools\?') { $cluster = @($q.Clusters | Where-Object { $Path -like "$($_.Id)/*" })[0]; $body = @{ value = @($cluster.Pools | ForEach-Object { @{ name = $_.Name; properties = @{ vmSize = $_.VmSize; count = $_.Count; maxCount = $_.MaxCount } } }) } }
        elseif ($Path -match 'Microsoft\.Compute/locations/[^/]+/usages') { $body = @{ value = @($q.ComputeUsage | ForEach-Object { @{ name = @{ value = $_.Name; localizedValue = $_.Name }; currentValue = $_.Current; limit = $_.Limit } }) } }
        elseif ($Path -match 'Microsoft\.Compute/skus') { $body = @{ value = @($q.Skus | ForEach-Object { @{ resourceType = 'virtualMachines'; name = $_.Name; family = $_.Family; capabilities = @(@{ name = 'vCPUs'; value = [string]$_.Vcpus }) } }) } }
        elseif ($Path -match "resourceType eq 'Microsoft\.CognitiveServices/accounts'") { $body = @{ value = @($q.AiAccounts | ForEach-Object { @{ id = $_.Id; name = $_.Name } }) } }
        elseif ($Path -match 'Microsoft\.CognitiveServices/accounts/[^/]+/deployments\?') { $account = @($q.AiAccounts | Where-Object { $Path -like "$($_.Id)/deployments*" })[0]; $body = @{ value = @($account.Deployments | ForEach-Object { @{ name = $_.Model; properties = @{ model = @{ name = $_.Model; version = '1' } }; sku = @{ name = $_.Sku; capacity = $_.Capacity } } }) } }
        elseif ($Path -match 'Microsoft\.CognitiveServices/accounts/[^/?]+\?api-version') { $account = @($q.AiAccounts | Where-Object { $Path -like "$($_.Id)?*" })[0]; $body = @{ id = $account.Id; name = $account.Name; kind = $account.Kind; location = 'uksouth' } }
        elseif ($Path -match 'Microsoft\.CognitiveServices/locations/[^/]+/usages') { $body = @{ value = @($q.ModelUsage | ForEach-Object { @{ name = @{ value = $_.Name; localizedValue = $_.Name }; currentValue = $_.Current; limit = $_.Limit; unit = 'Count' } }) } }
        else { return [pscustomobject]@{ StatusCode = 404; Content = '{"error":{"code":"NotFound","message":"no fixture for ' + $Path + '"}}' } }
        [pscustomobject]@{ StatusCode = 200; Content = ($body | ConvertTo-Json -Depth 10) }
    }
    Mock Update-AzTag {
        param($ResourceId, $Tag, $Operation)
        foreach ($key in @($Tag.Keys)) { $script:Tenant.ResourceGroupTags[$key] = $Tag[$key] }
        Add-Write "SET tag $(@($Tag.Keys) -join ',') $ResourceId"
    }
    Mock Get-AzRoleAssignment {
        param($ObjectId, $RoleDefinitionName, $Scope)
        # Azure returns the assignment at the scope and every inherited one above it.
        # Without -ObjectId it returns every principal's assignments. An assignment
        # whose principal is gone from the directory reads ObjectType Unknown, as Azure
        # reports it; every other reads ServicePrincipal.
        $visible = @($script:Tenant.AzRoleAssignments)
        if ([int]$script:Tenant.StaleAzRoleReads -gt 0) {
            $script:Tenant.StaleAzRoleReads--
            $visible += @($script:Tenant.StaleAzRoleAssignments)
        }
        @($visible | Where-Object {
                ((-not $ObjectId) -or $_.ObjectId -eq $ObjectId) -and
                ((-not $RoleDefinitionName) -or $_.RoleDefinitionName -eq $RoleDefinitionName) -and
                ((-not $Scope) -or $Scope.StartsWith($_.Scope, [System.StringComparison]::OrdinalIgnoreCase))
            } | ForEach-Object {
                $entry = @{} + $_
                if (-not $entry.ContainsKey('ObjectType')) { $entry.ObjectType = 'ServicePrincipal' }
                [pscustomobject]$entry
            })
    }
    Mock New-AzRoleAssignment {
        param($ObjectId, $RoleDefinitionName, $RoleDefinitionId, $Scope, $Condition, $ConditionVersion)
        if (-not $RoleDefinitionName -and $RoleDefinitionId -eq 'f58310d9-a9f6-439a-9e8d-f62e7b41a168') { $RoleDefinitionName = 'Role Based Access Control Administrator' }
        $entry = @{ ObjectId = $ObjectId; RoleDefinitionName = $RoleDefinitionName; Scope = $Scope }
        $suffix = ''
        if ($Condition) { $entry.Condition = $Condition; $entry.ConditionVersion = $ConditionVersion; $suffix = ' limited' }
        $script:Tenant.AzRoleAssignments += $entry
        Add-Write "NEW az role $RoleDefinitionName $Scope$suffix"
    }
    Mock Set-AzRoleAssignment {
        param($InputObject)
        foreach ($entry in $script:Tenant.AzRoleAssignments) {
            if ($entry.ObjectId -eq $InputObject.ObjectId -and $entry.RoleDefinitionName -eq $InputObject.RoleDefinitionName -and $entry.Scope -eq $InputObject.Scope) {
                $entry.Condition = $InputObject.Condition
                $entry.ConditionVersion = $InputObject.ConditionVersion
            }
        }
        Add-Write "LIMIT az role $($InputObject.RoleDefinitionName) $($InputObject.Scope)"
    }
    Mock Remove-AzRoleAssignment {
        param($ObjectId, $RoleDefinitionName, $Scope)
        # Azure answers reads with a removed assignment for a while: the model keeps the
        # removed entries in StaleAzRoleAssignments, and Get-AzRoleAssignment returns them
        # for StaleAzRoleReads more reads.
        $script:Tenant.StaleAzRoleAssignments += @($script:Tenant.AzRoleAssignments | Where-Object {
                $_.ObjectId -eq $ObjectId -and $_.RoleDefinitionName -eq $RoleDefinitionName -and $_.Scope -eq $Scope })
        $script:Tenant.AzRoleAssignments = @($script:Tenant.AzRoleAssignments | Where-Object {
                -not ($_.ObjectId -eq $ObjectId -and $_.RoleDefinitionName -eq $RoleDefinitionName -and $_.Scope -eq $Scope) })
        $script:Tenant.StaleAzRoleReads = [int]$script:Tenant.StaleAzRoleReadsAfterRemoval
        Add-Write "REMOVE az role $RoleDefinitionName $Scope"
    }
}

BeforeEach {
    $script:Tenant = New-EmptyTenant
    $script:Writes = @()
    $script:GraphCalls = @()
    $script:Faults = @()
    $script:Console = @()
    $script:Sleeps = @()
    $script:Installs = @()
    $script:Imports = @()
    $script:TokenRequests = @()
    $script:BrowserUris = @()
    $script:BrowserOpens = $false
    $script:Desktop = $false
    $script:Connected = $false
    $script:AzConnected = $false
    $script:ContextTenant = $script:Ids.Tenant
    $script:ContextScopes = @()
    $script:AzContextSubscription = $script:Ids.Subscription
    $script:KitVersion = 'v5.0.15'
    $script:SummaryDirs = @((Join-Path $TestDrive 'summary'))
    $script:StorageContainers = @()
    $script:StorageAccounts = @()
    $script:UnreachableAccounts = @()
    $script:Uploads = @()
    $script:UploadRefusals = 0
    $script:BlobRequests = @()
    $script:ArmReads = @()
    # NeologikGuestUsers.txt as the onboarding kit ships it: one Neologik support account.
    $script:GuestFile = Join-Path $TestDrive 'NeologikGuestUsers.txt'
    Set-Content -LiteralPath $script:GuestFile -Value "# Neologik support accounts`nsupport@neologik.ai`n" -Encoding UTF8
    if (Test-Path (Join-Path $TestDrive 'summary')) { Remove-Item -Path (Join-Path $TestDrive 'summary') -Recurse -Force }
    New-Item -ItemType Directory -Path (Join-Path $TestDrive 'summary') -Force | Out-Null
}

Context 'Helpers' {
    It 'reads properties safely from objects, hashtables and null' {
        Get-NeologikProperty ([pscustomobject]@{ a = 1 }) 'a' | Should -Be 1
        Get-NeologikProperty ([pscustomobject]@{ a = 1 }) 'missing' 'dflt' | Should -Be 'dflt'
        Get-NeologikProperty @{ value = @(1, 2) } 'value' | Should -HaveCount 2
        Get-NeologikProperty @{ a = 1 } 'value' | Should -BeNullOrEmpty
        Get-NeologikProperty $null 'a' 'dflt' | Should -Be 'dflt'
    }

    It 'validates GUIDs' {
        Test-NeologikGuid $script:Ids.Tenant | Should -BeTrue
        Test-NeologikGuid 'not-a-guid' | Should -BeFalse
        Test-NeologikGuid "x' or 1 eq 1" | Should -BeFalse
        Test-NeologikGuid '' | Should -BeFalse
    }

    It 'produces a one-line error text without tokens or stack traces' {
        try { throw "line one`nline two Bearer abc.def-ghi rest" } catch { $record = $_ }
        $text = Get-NeologikErrorText $record
        $text | Should -Not -Match 'abc\.def'
        $text | Should -Match 'bearer <token>'
        $text | Should -Not -Match "`n"
        Get-NeologikErrorText $null | Should -Be 'unknown error'
    }

    It 'derives the HTTP status from typed exceptions and from Graph error text' {
        try { throw (New-ForbiddenException) } catch { $forbidden = $_ }
        Get-NeologikHttpStatus $forbidden | Should -Be 403
        Test-NeologikPrivilegeError $forbidden | Should -BeTrue
        try { throw (New-NotFoundException) } catch { $notFound = $_ }
        Get-NeologikHttpStatus $notFound | Should -Be 404
        try { throw 'Request_ResourceNotFound: Resource does not exist' } catch { $textual = $_ }
        Get-NeologikHttpStatus $textual | Should -Be 404
        try { throw 'something else' } catch { $unknown = $_ }
        Get-NeologikHttpStatus $unknown | Should -Be 0
    }

    It 'honours Retry-After and caps the retry delay' {
        Get-NeologikRetryDelay -Headers @{ 'Retry-After' = @('7') } -Attempt 1 | Should -Be 7
        Get-NeologikRetryDelay -Headers @{ 'Retry-After' = @('600') } -Attempt 1 | Should -Be 60
        Get-NeologikRetryDelay -Headers @{} -Attempt 2 | Should -Be 4
        Get-NeologikRetryDelay -Headers $null -Attempt 10 | Should -Be 60
    }

    It 'refuses PowerShell below 7.4 with an ACTION REQUIRED message' {
        Test-NeologikPowerShellVersion -Version ([version]'5.1.22621') | Should -BeFalse
        ($script:Console -join "`n") | Should -Match 'ACTION REQUIRED'
        ($script:Console -join "`n") | Should -Match 'PowerShell 7.4 or later'
        Test-NeologikPowerShellVersion -Version ([version]'7.4.0') | Should -BeTrue
    }
}

Context 'Input validation (nothing is contacted when an input is wrong)' {
    It 'fails cleanly when neither a configuration file nor the ids are given' {
        $code = Invoke-Run @{ }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The command does not give TenantId'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'reports a missing configuration file' {
        $code = Invoke-Run @{ ConfigurationFile = (Join-Path $TestDrive 'nope.json') }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The configuration file does not exist'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'reports a malformed configuration file' {
        $path = Join-Path $TestDrive 'bad.json'
        Set-Content -LiteralPath $path -Value '{ not json'
        $code = Invoke-Run @{ ConfigurationFile = $path }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'not valid JSON'
    }

    It 'reports an empty configuration file' {
        $path = Join-Path $TestDrive 'empty.json'
        Set-Content -LiteralPath $path -Value '   '
        $code = Invoke-Run @{ ConfigurationFile = $path }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'is empty'
    }

    It 'reports a configuration file that is not the onboarding export' {
        $path = Join-Path $TestDrive 'array.json'
        Set-Content -LiteralPath $path -Value '[{"IdentityAppId": "x"}]'
        $code = Invoke-Run @{ ConfigurationFile = $path }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'not the file that the onboarding script wrote'
    }

    It 'rejects ids that are not GUIDs before they reach a filter' {
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = "abc' or displayName eq 'x" }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'DeploySpClientId must be a GUID'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'rejects a UserGroupId that is not a GUID before contacting anything (project#3787)' {
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UserGroupId = 'not-a-guid' }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'UserGroupId must be a GUID'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'refuses one group id under UserGroupId and NceUserGroupId before contacting anything (project#3787)' {
        # One group under two parameters would be renamed back and forth on every run.
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UserGroupId = $script:Ids.Group; NceUserGroupId = $script:Ids.Group }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'UserGroupId and NceUserGroupId name the same group'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'refuses a run without -KitVersion, or with a value that is not a version, before contacting anything' {
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); KitVersion = '' }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The command does not give KitVersion'
        @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_PreWindow_*.json') | Should -HaveCount 1
        $script:Console = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); KitVersion = '5.0.15' }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'KitVersion must be a version in the form vX.Y.P'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'requires the subscription and resource group for the pre migration script' {
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'pre migration script needs SubscriptionId'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'tolerates a configuration file without AppRegistration or SecurityGroups when the ids are explicit' {
        Add-CompliantPreWindowState
        $cfg = New-ConfigFile -Remove @('AppRegistration', 'SecurityGroups', 'NceAuthApp')
        $code = Invoke-Run @{ ConfigurationFile = $cfg; DeploySpClientId = $script:Ids.DeployAppId; SignInAppClientId = $script:Ids.SignInAppId }
        # Step 2 finds the groups by their version 5 names (project#3127), so the
        # assignment runs without a group id on the command.
        $code | Should -Be 0
        Get-SummaryResult 'User group assignment' | Should -Be 'Already assigned'
        Get-SummaryResult 'Agent identity blueprint' | Should -Be 'Present'
    }

}

Context 'Modules and sign-in' {
    It 'installs a missing Graph module before importing one consistent version' {
        Add-CompliantPreWindowState
        Mock Get-NeologikAvailableModuleVersion {
            param($Name)
            if ($Name -eq 'Microsoft.Graph.Groups' -and $script:Installs -notcontains $Name) { return @() }
            @([version]'2.38.0', [version]'2.20.0')
        }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Installs | Should -Contain 'Microsoft.Graph.Groups'
        $script:Imports | Should -Contain 'Microsoft.Graph.Applications 2.38.0'
        $script:Imports | Should -Contain 'Microsoft.Graph.Groups 2.38.0'
    }

    It 'imports the highest version every Graph module has in common' {
        Add-CompliantPreWindowState
        Mock Get-NeologikAvailableModuleVersion {
            param($Name)
            if ($Name -eq 'Microsoft.Graph.Authentication') { return @([version]'2.40.0', [version]'2.38.0') }
            @([version]'2.38.0')
        }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Imports | Should -Contain 'Microsoft.Graph.Authentication 2.38.0'
        $script:Imports | Should -Not -Contain 'Microsoft.Graph.Authentication 2.40.0'
    }

    It 'pins to the Graph version already loaded in the session' {
        Add-CompliantPreWindowState
        Mock Get-NeologikLoadedModuleVersion { param($Name) if ($Name -eq 'Microsoft.Graph.Authentication') { [version]'2.30.0' } }
        Mock Get-NeologikAvailableModuleVersion { @([version]'2.38.0', [version]'2.30.0') }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Imports | Should -Contain 'Microsoft.Graph.Groups 2.30.0'
    }

    It 'stops with ACTION REQUIRED when a module cannot be installed' {
        Mock Get-NeologikAvailableModuleVersion { @() }
        Mock Install-NeologikModule { throw 'No match was found for the specified search criteria' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'ACTION REQUIRED'
        ($script:Console -join "`n") | Should -Match 'Install-Module Microsoft.Graph.Authentication'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'stops with ACTION REQUIRED when the Graph sign-in fails' {
        Mock Connect-MgGraph { throw 'Device code authentication timed out' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The sign-in to Microsoft Graph did not complete'
        Should -Invoke Get-MgServicePrincipal -Times 0
    }

    It 'stops when the session landed in a different tenant' {
        $script:ContextTenant = $script:Ids.OtherTenant
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The sign-in is for tenant'
        Should -Invoke Get-MgServicePrincipal -Times 0
    }

    It 'adds the directory role scope in both runs and the group scopes to the run that needs them' {
        Add-CompliantPreWindowState
        $graphScopes = {
            $request = @($script:TokenRequests | Where-Object { $_.Uri -match '/devicecode$' -and $_.Body.client_id -eq '14d82eec-204b-4c2f-b7e8-296a70dab67e' }) | Select-Object -Last 1
            @($request.Body.scope -split ' ')
        }
        $null = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        (& $graphScopes) | Should -Contain 'RoleManagement.ReadWrite.Directory'
        (& $graphScopes) | Should -Contain 'GroupMember.ReadWrite.All'
        (& $graphScopes) | Should -Not -Contain 'Group.ReadWrite.All'
        # The grants are the work of Grant-NeologikAgentAccess.ps1 (project#3192): no run requests the grant write scope.
        (& $graphScopes) | Should -Not -Contain 'DelegatedPermissionGrant.ReadWrite.All'
        $script:TokenRequests = @()
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        # Both runs assign the directory role of the SQL managed identity (project#3848).
        (& $graphScopes) | Should -Contain 'RoleManagement.ReadWrite.Directory'
        (& $graphScopes) | Should -Not -Contain 'DelegatedPermissionGrant.ReadWrite.All'
    }

    It 'requests the read scopes the verification steps need' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $graphRequest = @($script:TokenRequests | Where-Object { $_.Uri -match '/devicecode$' }) | Select-Object -First 1
        $scopes = @($graphRequest.Body.scope -split ' ')
        $scopes | Should -Contain 'Directory.Read.All'
        $scopes | Should -Contain 'User.Read'
        $scopes | Should -Contain 'AppRoleAssignment.ReadWrite.All'
        # Both runs assign the directory role Directory Readers to the SQL managed identity (project#3848).
        $scopes | Should -Contain 'RoleManagement.ReadWrite.Directory'
        $scopes | Should -Contain 'GroupMember.ReadWrite.All'
        $scopes | Should -Contain 'AgentIdentityBlueprintPrincipal.ReadWrite.All'
        $scopes | Should -Not -Contain 'DelegatedPermissionGrant.ReadWrite.All'
        $scopes | Should -Contain 'offline_access'
        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $AccessToken -is [securestring] -and -not $UseDeviceCode }
    }

    It 'warns when the session lacks a requested permission' {
        Add-CompliantPreWindowState
        $script:ContextScopes = @('Application.ReadWrite.All')
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        ($script:Console -join "`n") | Should -Match 'lacks the permission'
    }

    It 'uses the Azure CLI token when asked and never prints it' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UseAzureCliToken = $true }
        $code | Should -Be 0
        # Twice: once for the Microsoft Graph session, once for the Azure session.
        Should -Invoke Invoke-NeologikAzureCli -Times 2 -Exactly -ParameterFilter { ($Arguments -join ' ') -match "get-access-token --resource-type ms-graph --tenant $($script:Ids.Tenant)" }
        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $AccessToken -is [securestring] -and -not $UseDeviceCode }
        ($script:Console -join "`n") | Should -Not -Match 'eyJ0b2tlbg'
    }

    It 'signs in to Azure with the Azure CLI token as well when asked' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UseAzureCliToken = $true }
        $code | Should -Be 0
        Should -Invoke Invoke-NeologikAzureCli -Times 1 -ParameterFilter { ($Arguments -join ' ') -match "get-access-token --resource https://management.azure.com/ --subscription $($script:Ids.Subscription)" }
        Should -Invoke Connect-AzAccount -Times 1 -ParameterFilter { $AccessToken -eq 'eyJ0b2tlbg' -and $AccountId -and -not $UseDeviceAuthentication }
        # The Azure session also receives the Microsoft Graph token of the Azure CLI, for the role assignment commands.
        Should -Invoke Connect-AzAccount -Times 1 -ParameterFilter { $MicrosoftGraphAccessToken -eq 'eyJ0b2tlbg' }
        ($script:Console -join "`n") | Should -Not -Match 'device code'
        Get-SummaryResult 'Resource group role: Contributor' | Should -Be 'Already assigned'
    }

    It 'reports ACTION REQUIRED and skips the reduction when the Azure CLI has no token for the subscription' {
        Add-CompliantPreWindowState
        Mock Invoke-NeologikAzureCli { param($Arguments) if (($Arguments -join ' ') -match 'management\.azure\.com') { @{ ExitCode = 1; Output = @() } } else { @{ ExitCode = 0; Output = @('eyJ0b2tlbg') } } }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UseAzureCliToken = $true }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The Azure CLI gave no token for subscription'
        Get-SummaryResult 'Resource group role: Contributor' | Should -Be 'SKIPPED: the sign-in to Azure failed'
        Should -Invoke Connect-AzAccount -Times 0
    }

    It 'stops with ACTION REQUIRED when the Azure CLI is absent or not signed in' {
        Mock Test-NeologikCommand { $false }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UseAzureCliToken = $true }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The Azure CLI is not installed'
        Mock Test-NeologikCommand { $true }
        Mock Invoke-NeologikAzureCli { @{ ExitCode = 1; Output = @() } }
        $script:Console = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UseAzureCliToken = $true }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'az login --tenant'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'stops with a clear message when the deployment identity does not exist' {
        $script:Tenant.ServicePrincipals = @($script:Tenant.ServicePrincipals | Where-Object { $_.id -ne $script:Ids.DeploySpId })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Deployment identity' | Should -Be 'MISSING: the tenant holds no service principal with this client id'
        ($script:Console -join "`n") | Should -Match 'ACTION REQUIRED'
        $script:Writes | Should -HaveCount 0
    }

    It 'reports a Graph read failure on the deployment identity without a stack trace' {
        Mock Get-MgServicePrincipal { throw (New-ForbiddenException) }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Deployment identity') | Should -Match '^FAILED: '
    }
}

Context 'Sign-in and preflight' {
    It 'prints the sign-in address and code itself, waits, and signs in to Graph and Azure with the tokens' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $console = $script:Console -join "`n"
        $console | Should -Match 'https://microsoft.com/devicelogin'
        $console | Should -Match 'Enter the code: ABCD-EFGH'
        $console | Should -Match 'valid for 15 minutes'
        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $AccessToken -is [securestring] }
        Should -Invoke Connect-AzAccount -Times 1 -ParameterFilter { $AccessToken -eq 'eyJ0b2tlbg' -and -not $UseDeviceAuthentication }
        $azureRequest = @($script:TokenRequests | Where-Object { $_.Uri -match '/devicecode$' -and $_.Body.client_id -eq '1950a258-227b-4e31-a9cf-717495945fc2' }) | Select-Object -First 1
        $azureRequest.Body.scope | Should -Match 'https://management.azure.com/.default'
        $azureRequest.Body.claims | Should -Match '"p1"'
        # The Azure session also receives a Microsoft Graph token from the same sign-in, through
        # the refresh token, so the role assignment commands of Az can resolve each principal.
        $refresh = @($script:TokenRequests | Where-Object { $_.Uri -match '/token$' -and $_.Body.grant_type -eq 'refresh_token' }) | Select-Object -First 1
        $refresh | Should -Not -BeNullOrEmpty
        $refresh.Body.client_id | Should -Be '1950a258-227b-4e31-a9cf-717495945fc2'
        $refresh.Body.refresh_token | Should -Be 'rt-1'
        $refresh.Body.scope | Should -Match 'https://graph.microsoft.com/.default'
        Should -Invoke Connect-AzAccount -Times 1 -ParameterFilter { $MicrosoftGraphAccessToken -eq 'eyJ0b2tlbg' }
        $console | Should -Not -Match 'eyJ0b2tlbg'
        $console | Should -Match 'The sign-in also gave the token for Microsoft Graph'
    }

    It 'gives the run an Az context store of its own before the sign-in, so a saved sign-in takes no part' {
        Add-CompliantPreWindowState
        $script:AzIsolated = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        # Autosave off for this process, then the process copy cleared, both before Connect-AzAccount.
        Should -Invoke Disable-AzContextAutosave -Times 1 -Exactly -ParameterFilter { $Scope -eq 'Process' }
        Should -Invoke Clear-AzContext -Times 1 -Exactly -ParameterFilter { $Scope -eq 'Process' -and $Force }
        $script:AzIsolated | Should -Be @('autosave off', 'cleared')
        ($script:Console -join "`n") | Should -Match 'The run uses an Az session of its own'
        Should -Invoke Connect-AzAccount -Times 1
    }

    It 'keeps waiting while the sign-in is pending, reports every 30 seconds and gives up when the code expires' {
        Add-CompliantPreWindowState
        Mock Invoke-NeologikTokenRequest {
            param($Uri, $Body)
            $script:TokenRequests += @{ Uri = $Uri; Body = $Body }
            if ($Uri -match '/devicecode$') {
                return @{ StatusCode = 200; Body = @{ device_code = 'dc-1'; user_code = 'WXYZ-1234'; verification_uri = 'https://microsoft.com/devicelogin'; expires_in = 120; interval = 10 } }
            }
            return @{ StatusCode = 400; Body = @{ error = 'authorization_pending'; error_description = 'AADSTS70016: Pending end-user authorization.' } }
        }
        Mock Test-NeologikCommand { $false }
        Mock Connect-MgGraph { throw 'Device code authentication timed out' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        $console = $script:Console -join "`n"
        $console | Should -Match 'The script still waits for the sign-in to Microsoft Graph\. Code WXYZ-1234'
        $console | Should -Match 'code expired after 2 minutes'
        # Bounded: polled at once and after each of the twelve 10-second waits, never more.
        @($script:TokenRequests | Where-Object { $_.Uri -match '/token$' }).Count | Should -Be 13
        ($script:Sleeps | Measure-Object -Sum).Sum | Should -Be 120
        $console | Should -Match 'The sign-in to Microsoft Graph did not complete\. The script tried four methods'
        Should -Invoke Get-MgServicePrincipal -Times 0
    }

    It 'falls back to the Azure CLI session when the device code is declined, then to the Graph PowerShell prompt' {
        Add-CompliantPreWindowState
        Mock Invoke-NeologikTokenRequest {
            param($Uri, $Body)
            if ($Uri -match '/devicecode$') {
                return @{ StatusCode = 200; Body = @{ device_code = 'dc-1'; user_code = 'ABCD-EFGH'; verification_uri = 'https://microsoft.com/devicelogin'; expires_in = 900; interval = 5 } }
            }
            return @{ StatusCode = 400; Body = @{ error = 'authorization_declined'; error_description = 'AADSTS70020: The end user declined.' } }
        }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $console = $script:Console -join "`n"
        $console | Should -Match 'The sign-in to Microsoft Graph did not complete\. AADSTS70020'
        $console | Should -Match 'The script now tries the Azure CLI session of this workstation'
        Should -Invoke Invoke-NeologikAzureCli -Times 1 -ParameterFilter { ($Arguments -join ' ') -match 'ms-graph' }
        Should -Invoke Invoke-NeologikAzureCli -Times 1 -ParameterFilter { ($Arguments -join ' ') -match 'management\.azure\.com' }
        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $AccessToken -is [securestring] }

        # No CLI either: the Graph PowerShell device-code prompt is the last method.
        Mock Test-NeologikCommand { $false }
        $script:Console = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $UseDeviceCode }
        Should -Invoke Connect-AzAccount -Times 1 -ParameterFilter { $UseDeviceAuthentication }
        ($script:Console -join "`n") | Should -Match 'The script now tries the device code prompt of Microsoft Graph PowerShell'
    }

    It 'stops before the sign-in with ACTION REQUIRED when an endpoint is not reachable' {
        Add-CompliantPreWindowState
        Mock Test-NeologikEndpoint { param($Uri) $Uri -notmatch 'graph\.microsoft\.com' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        $console = $script:Console -join "`n"
        $console | Should -Match 'ACTION REQUIRED'
        $console | Should -Match 'cannot reach:'
        $console | Should -Match 'Microsoft Graph: https://graph.microsoft.com/'
        Should -Invoke Invoke-NeologikTokenRequest -Times 0
        Should -Invoke Connect-MgGraph -Times 0
        $script:Writes | Should -HaveCount 0
    }

    It 'stops a real run when the signed-in account is not an active Global Administrator, and only warns in verify-only' {
        Add-CompliantPreWindowState
        $script:Tenant.MeDirectoryRoles = @(@{ id = 'role-ua'; displayName = 'User Administrator'; roleTemplateId = 'fe930be7-5e62-47db-91af-98c3a49a38b1' })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        $console = $script:Console -join "`n"
        $console | Should -Match 'admin@contoso.com does not hold an active Global Administrator role'
        $console | Should -Match 'Privileged Identity Management'
        Should -Invoke Get-MgServicePrincipal -Times 0
        $script:Writes | Should -HaveCount 0

        $script:Console = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 0
        ($script:Console -join "`n") | Should -Match 'The run with -Verify continues'
    }

    It 'stops the permission reduction when the signed-in account holds neither Owner nor User Access Administrator' {
        Add-CompliantPreWindowState
        $script:Tenant.AzRoleAssignments = @($script:Tenant.AzRoleAssignments | Where-Object { $_.ObjectId -ne $script:Ids.Me })
        $script:Tenant.AzRoleAssignments += @{ ObjectId = $script:Ids.Me; RoleDefinitionName = 'Reader'; Scope = "/subscriptions/$($script:Ids.Subscription)" }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        $console = $script:Console -join "`n"
        $console | Should -Match 'holds neither Owner nor User Access Administrator'
        $console | Should -Match 'Access control \(IAM\)'
        Get-SummaryResult 'Resource group role: Contributor' | Should -Be 'SKIPPED: the sign-in to Azure failed'
        Should -Invoke New-AzRoleAssignment -Times 0
        Should -Invoke Remove-AzRoleAssignment -Times 0

        $script:Console = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 0
        ($script:Console -join "`n") | Should -Match 'The run with -Verify continues\. Azure refuses each role assignment'
    }

    It 'accepts User Access Administrator inherited from above the subscription' {
        Add-CompliantPreWindowState
        $script:Tenant.AzRoleAssignments = @($script:Tenant.AzRoleAssignments | Where-Object { $_.ObjectId -ne $script:Ids.Me })
        $script:Tenant.AzRoleAssignments += @{ ObjectId = $script:Ids.Me; RoleDefinitionName = 'User Access Administrator'; Scope = '/' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        ($script:Console -join "`n") | Should -Match 'holds User Access Administrator on the subscription'
    }
}

Context 'Browser sign-in' {
    BeforeAll {
        # An access token that names the account admin@contoso.com. The script reads the
        # claims and never checks the signature.
        $claims = ConvertTo-NeologikBase64Url ([System.Text.Encoding]::UTF8.GetBytes('{"upn":"admin@contoso.com"}'))
        $script:AdminJwt = "eyJhbGciOiJub25lIn0.$claims.sig"
        function Get-BrowserQuery {
            # The parameters of the sign-in address that the script opened, by position.
            param([int]$Index)
            ConvertFrom-NeologikQueryString ($script:BrowserUris[$Index].Split('?', 2)[1])
        }
    }

    BeforeEach {
        $script:BrowserOpens = $true
        # The browser returns the code with the state of the address that the script opened.
        Mock Wait-NeologikLoopbackRequest {
            param($Listener, $TimeoutSeconds, $Label)
            $query = Get-BrowserQuery -Index ($script:BrowserUris.Count - 1)
            @{ code = "code-$Label"; state = $query.state }
        }
        Mock Invoke-NeologikTokenRequest {
            param($Uri, $Body)
            $script:TokenRequests += @{ Uri = $Uri; Body = $Body }
            if ($Uri -match '/devicecode$') {
                return @{ StatusCode = 200; Body = @{ device_code = 'dc-1'; user_code = 'ABCD-EFGH'; verification_uri = 'https://microsoft.com/devicelogin'; expires_in = 900; interval = 5 } }
            }
            return @{ StatusCode = 200; Body = @{ access_token = $script:AdminJwt; refresh_token = 'rt-1' } }
        }
    }

    It 'signs in to Graph and Azure in the browser first and asks for no device code' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        @($script:TokenRequests | Where-Object { $_.Uri -match '/devicecode$' }).Count | Should -Be 0
        $script:BrowserUris | Should -HaveCount 2

        $graphUri = $script:BrowserUris[0]
        $graphUri | Should -Match "^https://login\.microsoftonline\.com/$($script:Ids.Tenant)/oauth2/v2\.0/authorize\?"
        $graphQuery = Get-BrowserQuery -Index 0
        $graphQuery.client_id | Should -Be '14d82eec-204b-4c2f-b7e8-296a70dab67e'
        $graphQuery.redirect_uri | Should -Be 'http://localhost:50999/'
        $graphQuery.code_challenge_method | Should -Be 'S256'
        $graphQuery.prompt | Should -Be 'select_account'
        @($graphQuery.scope -split ' ') | Should -Contain 'Directory.Read.All'
        $graphToken = @($script:TokenRequests | Where-Object { $_.Body.client_id -eq '14d82eec-204b-4c2f-b7e8-296a70dab67e' }) | Select-Object -First 1
        $graphToken.Uri | Should -Match '/token$'
        $graphToken.Body.grant_type | Should -Be 'authorization_code'
        $graphToken.Body.code | Should -Be 'code-Microsoft Graph'
        $graphToken.Body.redirect_uri | Should -Be 'http://localhost:50999/'
        # The proof key: the challenge in the address is the hash of the verifier in the token request.
        $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::ASCII.GetBytes($graphToken.Body.code_verifier))
        $graphQuery.code_challenge | Should -Be (ConvertTo-NeologikBase64Url $hash)

        # Azure asks for the claim that a role assignment needs and names the account of the
        # Graph sign-in, so the browser does not ask again.
        $azureQuery = Get-BrowserQuery -Index 1
        $azureQuery.client_id | Should -Be '1950a258-227b-4e31-a9cf-717495945fc2'
        $azureQuery.claims | Should -Match '"p1"'
        $azureQuery.login_hint | Should -Be 'admin@contoso.com'
        $azureQuery.ContainsKey('prompt') | Should -BeFalse
        $azureQuery.state | Should -Not -Be $graphQuery.state

        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $AccessToken -is [securestring] -and -not $UseDeviceCode }
        Should -Invoke Connect-AzAccount -Times 1 -ParameterFilter { $AccessToken -eq $script:AdminJwt -and $AccountId -eq 'admin@contoso.com' -and -not $UseDeviceAuthentication }
        $console = $script:Console -join "`n"
        $console | Should -Match 'opens the sign-in page in the browser of this computer'
        $console | Should -Not -Match 'Enter the code'
        $console | Should -Not -Match ([regex]::Escape($script:AdminJwt))
    }

    It 'falls back to the device code when the browser sign-in does not complete in time' {
        Add-CompliantPreWindowState
        Mock Wait-NeologikLoopbackRequest { $null }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $console = $script:Console -join "`n"
        $console | Should -Match 'The sign-in to Microsoft Graph in the browser did not complete within 5 minutes'
        $console | Should -Match 'Enter the code: ABCD-EFGH'
        @($script:TokenRequests | Where-Object { $_.Uri -match '/devicecode$' }).Count | Should -Be 2
    }

    It 'falls back to the device code when no browser opens' {
        Add-CompliantPreWindowState
        $script:BrowserOpens = $false
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        ($script:Console -join "`n") | Should -Match 'The sign-in to Microsoft Graph in the browser did not start\. The script tries a device code'
        Should -Invoke Wait-NeologikLoopbackRequest -Times 0
    }

    It 'names a Conditional Access refusal in the browser and falls back to the device code' {
        Add-CompliantPreWindowState
        Mock Wait-NeologikLoopbackRequest {
            $query = Get-BrowserQuery -Index ($script:BrowserUris.Count - 1)
            @{ error = 'access_denied'; error_description = 'AADSTS53003: Access has been blocked by Conditional Access policies.'; state = $query.state }
        }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        ($script:Console -join "`n") | Should -Match 'A Conditional Access policy of the tenant refused the sign-in to Microsoft Graph with the browser\. AADSTS53003'
        @($script:TokenRequests | Where-Object { $_.Body.grant_type -eq 'authorization_code' }).Count | Should -Be 0
        @($script:TokenRequests | Where-Object { $_.Uri -match '/devicecode$' }).Count | Should -Be 2
    }

    It 'ignores an answer whose state this run did not request' {
        Add-CompliantPreWindowState
        Mock Wait-NeologikLoopbackRequest { @{ code = 'code-other'; state = 'another-state' } }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        ($script:Console -join "`n") | Should -Match 'returned an answer that this run did not request'
        @($script:TokenRequests | Where-Object { $_.Body.grant_type -eq 'authorization_code' }).Count | Should -Be 0
    }

    It 'names a Conditional Access refusal of the device code and tries the next method at once' {
        Add-CompliantPreWindowState
        $script:BrowserOpens = $false
        Mock Invoke-NeologikTokenRequest {
            param($Uri, $Body)
            if ($Uri -match '/devicecode$') {
                return @{ StatusCode = 200; Body = @{ device_code = 'dc-1'; user_code = 'ABCD-EFGH'; verification_uri = 'https://microsoft.com/devicelogin'; expires_in = 900; interval = 5 } }
            }
            return @{ StatusCode = 400; Body = @{ error = 'invalid_grant'; error_codes = @(53003); error_description = 'AADSTS53003: Access has been blocked by Conditional Access policies.' } }
        }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $console = $script:Console -join "`n"
        $console | Should -Match 'A Conditional Access policy of the tenant refused the sign-in to Microsoft Graph with a device code'
        $console | Should -Match 'The script now tries the Azure CLI session of this workstation'
        ($script:Sleeps | Measure-Object -Sum).Sum | Should -Be 0
    }
}

Context 'Browser sign-in: the loopback listener' {
    It 'reads the result of the sign-in from a real loopback request and answers the browser' {
        # The real listener: the default mock replaces the command name, not the function.
        $listener = & (Get-Command -Name Start-NeologikLoopbackListener -CommandType Function)
        $http = [System.Net.Http.HttpClient]::new()
        try {
            $task = $http.GetAsync("http://localhost:$($listener.Port)/?code=abc%2B1&state=xyz")
            $query = Wait-NeologikLoopbackRequest -Listener $listener -TimeoutSeconds 10 -Label 'Test'
            $query.code | Should -Be 'abc+1'
            $query.state | Should -Be 'xyz'
            $response = $task.GetAwaiter().GetResult()
            [int]$response.StatusCode | Should -Be 200
            $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | Should -Match 'The sign-in is complete\. Return to the PowerShell window\.'
        }
        finally {
            $listener.Stop()
            $http.Dispose()
        }
    }

    It 'answers a request with no result with 404 and gives up when the time ends' {
        # The real listener: the default mock replaces the command name, not the function.
        $listener = & (Get-Command -Name Start-NeologikLoopbackListener -CommandType Function)
        $http = [System.Net.Http.HttpClient]::new()
        try {
            $task = $http.GetAsync("http://localhost:$($listener.Port)/favicon.ico")
            $query = Wait-NeologikLoopbackRequest -Listener $listener -TimeoutSeconds 2 -Label 'Test'
            $query | Should -BeNullOrEmpty
            [int]($task.GetAwaiter().GetResult().StatusCode) | Should -Be 404
        }
        finally {
            $listener.Stop()
            $http.Dispose()
        }
    }
}

Context 'Blueprint short name' {
    It 'adopts the one blueprint the deployment identity owns under another short name instead of creating a second one' {
        # An environment whose deployment identity is named with one short name while the
        # agent identity blueprint carries another; the command passes the blueprint's name.
        Add-CompliantPreWindowState
        $deploySp = Get-FakeSp -Id $script:Ids.DeploySpId
        $deploySp.displayName = 'Neologik GitHub Service Connection - x-prd'
        $app = Get-FakeApp -Id $script:Ids.BlueprintAppObj
        $app.displayName = 'Neologik Agent Blueprint - default - xprd01'
        $principal = Get-FakeSp -Id $script:Ids.BlueprintSpId
        $principal.displayName = $app.displayName
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId; SolutionShortName = 'xprd01'; SolutionName = $script:SolutionName; SignInAppClientId = $script:Ids.SignInAppId; NceUserGroupId = $script:Ids.Group; SubscriptionId = $script:Ids.Subscription; ResourceGroupName = $script:RgName }
        $code | Should -Be 0
        Get-SummaryResult 'Agent identity blueprint' | Should -Be 'Present'
        ($script:Console -join "`n") | Should -Match "Name of the agent identity blueprint: 'Neologik Agent Blueprint - default - xprd01'"
        @($script:Writes | Where-Object { $_ -match 'POST blueprint' }) | Should -HaveCount 0

        # A wrong short name given: the owned blueprint is adopted and named, never duplicated.
        $script:Console = @()
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId; SolutionShortName = 'x-prd'; SolutionName = $script:SolutionName; SignInAppClientId = $script:Ids.SignInAppId; NceUserGroupId = $script:Ids.Group; SubscriptionId = $script:Ids.Subscription; ResourceGroupName = $script:RgName }
        $code | Should -Be 0
        Get-SummaryResult 'Agent identity blueprint' | Should -Be "Present: the script uses 'Neologik Agent Blueprint - default - xprd01'"
        ($script:Console -join "`n") | Should -Match 'The script uses ''Neologik Agent Blueprint - default - xprd01'''
        @($script:Writes | Where-Object { $_ -match 'POST blueprint' }) | Should -HaveCount 0
        @($script:Tenant.Apps | Where-Object { $_.displayName -like 'Neologik Agent Blueprint - default - *' }) | Should -HaveCount 1
    }

    It 'stops the blueprint step when the deployment identity owns several blueprints under other short names' {
        Add-CompliantPreWindowState
        $app = Get-FakeApp -Id $script:Ids.BlueprintAppObj
        $app.displayName = 'Neologik Agent Blueprint - default - xprd01'
        $second = New-FakeApp -Id ([guid]::NewGuid().ToString()) -AppId ([guid]::NewGuid().ToString()) -DisplayName 'Neologik Agent Blueprint - default - xprd02'
        $second.owners = @($script:Ids.DeploySpId)
        $script:Tenant.Apps += $second
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile -Overrides @{ SolutionShortName = 'x-prd' }) }
        $code | Should -Be 1
        (Get-SummaryResult 'Agent identity blueprint') | Should -Match '^FAILED: the deployment identity owns several agent identity blueprints: .*xprd01.*xprd02'
        Get-SummaryResult 'Agent identity blueprint service principal' | Should -Be 'SKIPPED: the agent identity blueprint is not available'
        @($script:Writes | Where-Object { $_ -match 'POST blueprint' }) | Should -HaveCount 0
    }

    It 'creates the blueprint under the given short name when the identity owns none, and reports WOULD CREATE in verify-only' {
        Add-CompliantPreWindowState
        $script:Tenant.Apps = @($script:Tenant.Apps | Where-Object { $_.id -ne $script:Ids.BlueprintAppObj })
        $script:Tenant.ServicePrincipals = @($script:Tenant.ServicePrincipals | Where-Object { $_.id -ne $script:Ids.BlueprintSpId })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 1
        Get-SummaryResult 'Agent identity blueprint' | Should -Be "WOULD CREATE: Neologik Agent Blueprint - default - $($script:ShortName)"
        @($script:Writes) | Should -HaveCount 0
    }
}

Context 'The pre migration script on a compliant environment' {
    It 'records the kit version on the resource group once the reduction is complete, and leaves it when in place' {
        Add-CompliantPreWindowState
        $script:Tenant.ResourceGroupTags = @{ Vendor = 'Neologik' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Onboarding kit version tag' | Should -Be "Set: $script:KitVersion"
        @($script:Writes | Where-Object { $_ -like 'SET tag NeologikOnboardingKit*' }) | Should -HaveCount 1
        $script:Tenant.ResourceGroupTags['NeologikOnboardingKit'] | Should -Be $script:KitVersion
        $script:Tenant.ResourceGroupTags['Vendor'] | Should -Be 'Neologik' -Because 'the tag is merged, never replacing the others'
        $script:Writes = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Onboarding kit version tag' | Should -Be "Already set: $script:KitVersion"
        $script:Writes | Should -HaveCount 0
    }

    It 'reports an older kit version tag as a pending change in verify-only' {
        Add-CompliantPreWindowState
        $script:Tenant.ResourceGroupTags = @{ NeologikOnboardingKit = 'v5.0.1' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 1 -Because 'a pending change needs attention'
        Get-SummaryResult 'Onboarding kit version tag' | Should -Match '^WOULD SET'
        $script:Writes | Should -HaveCount 0
        $script:Tenant.ResourceGroupTags['NeologikOnboardingKit'] | Should -Be 'v5.0.1'
    }

    It 'records the kit version that the command names, whatever version the script carries' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); KitVersion = 'v5.0.16' }
        $code | Should -Be 0
        Get-SummaryResult 'Onboarding kit version tag' | Should -Be 'Set: v5.0.16'
        $script:Tenant.ResourceGroupTags['NeologikOnboardingKit'] | Should -Be 'v5.0.16'
        ($script:Console -join "`n") | Should -Match 'Onboarding kit:\s+v5\.0\.16'
    }

    It 'declares the script version the version history opens with' {
        $history = Get-Content -Raw (Join-Path (Split-Path -Parent $script:ScriptPath) 'docs' 'VERSION_HISTORY.md')
        $top = [regex]::Match($history, '(?m)^## Version (\d+\.\d+\.\d+)').Groups[1].Value
        $script:ScriptVersion | Should -Be $top
    }

    It 'is a pure verification pass: exit 0, no writes, every item in place' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        $script:Summary | Should -Not -BeNullOrEmpty
        @($script:Summary | Where-Object { $_.Result -match $script:AttentionPattern }) | Should -HaveCount 0
        Get-SummaryResult 'Agent identity blueprint' | Should -Be 'Present'
        Get-SummaryResult 'Agent identity blueprint owner' | Should -Be 'Already an owner'
        Get-SummaryResult 'Agent identity blueprint sponsor' | Should -Be 'Present: Contoso Administrator'
        Get-SummaryResult 'Agent identity blueprint service principal' | Should -Be 'Present'
        Get-SummaryResult 'Agent identity blueprint service principal owner' | Should -Be 'Already an owner'
        Get-SummaryResult 'Agent identity blueprint service principal permission: AgentIdUser.ReadWrite.IdentityParentedBy' | Should -Be 'Already granted'
        Get-SummaryResult 'Agent identity blueprint credential: github-oidc-neo-env-config' | Should -Be 'Present'
        Get-SummaryResult 'Deployment identity permission: Application.ReadWrite.OwnedBy' | Should -Be 'Already granted'
        Get-SummaryResult 'User group assignment' | Should -Be 'Already assigned'
        Get-SummaryResult 'Administrator consent' | Should -Be 'Present'
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Not needed. No SharePoint application of Neologik holds a SharePoint permission'
        Get-SummaryResult 'Resource group role: Contributor' | Should -Be 'Already assigned'
        Get-SummaryResult 'Subscription role: Cost Management Contributor' | Should -Be 'Already assigned'
        # The pre migration script reports no removal item (project#3170): the removals belong to the post migration script.
        @($script:Summary | Where-Object { $_.Item -match 'to remove|Application Administrator role|Admin User Group membership|^Other ' }) | Should -HaveCount 0
        Should -Invoke Connect-AzAccount -Times 1
        ($script:Console -join "`n") | Should -Match 'pre migration script'
        ($script:Console -join "`n") | Should -Match 'The pre migration script is complete'
    }

    It 'checks the Sites.Selected consent when the configuration file records SharePoint ingestion' {
        Add-CompliantPreWindowState
        Add-SharePointApp -WithConsent
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile -Overrides @{ SharePointIngestion = $true }) }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Present'
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile -Overrides @{ SharePointIngestion = $false }) }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Not needed'
        $script:Writes | Should -HaveCount 0
    }

    It 'writes the JSON summary beside the script with the held roles and every item' {
        Add-CompliantPreWindowState
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_PreWindow_*.json')
        $files | Should -HaveCount 1
        $json = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        $json.tenantId | Should -Be $script:Ids.Tenant
        $json.deploymentIdentity | Should -Be $script:Ids.DeployAppId
        $json.run | Should -Be 'PreWindow'
        $json.verifyOnly | Should -BeFalse
        $json.pendingChangeCount | Should -Be 0
        @($json.deploymentGraphRoles) | Should -Contain 'Application.ReadWrite.OwnedBy'
        @($json.deploymentGraphRoles) | Should -Contain 'AgentIdentityBlueprint.AddRemoveCreds.All'
        @($json.expectedGraphRoles) | Should -HaveCount 2
        @($json.items).Count | Should -Be $script:Summary.Count
        $json.attentionCount | Should -Be 0
        $bytes = [IO.File]::ReadAllBytes($files[0].FullName)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should -BeFalse -Because 'UTF-8 without BOM'
    }

    It 'falls back to the next summary location when the first is not writable' {
        Add-CompliantPreWindowState
        $second = Join-Path $TestDrive 'summary2'
        New-Item -ItemType Directory -Path $second -Force | Out-Null
        $script:SummaryDirs = @((Join-Path $TestDrive 'does-not-exist\nested'), $second)
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        @(Get-ChildItem -Path $second -Filter 'Neologik_EnvironmentMigration_PreWindow_*.json') | Should -HaveCount 1
        @(Get-ChildItem -Path $second -Filter 'Neologik_EnvironmentMigration_Snapshot_Pre_*.json') | Should -HaveCount 1
        ($script:Console -join "`n") | Should -Match 'The script tries the next folder'
    }

    It 'takes the short name from -SolutionShortName when no configuration file is given' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId; SolutionShortName = $script:ShortName; SolutionName = $script:SolutionName; SignInAppClientId = $script:Ids.SignInAppId; NceUserGroupId = $script:Ids.Group; SubscriptionId = $script:Ids.Subscription; ResourceGroupName = $script:RgName }
        $code | Should -Be 0
        Get-SummaryResult 'Agent identity blueprint' | Should -Be 'Present'
        ($script:Console -join "`n") | Should -Match "Short name '$($script:ShortName)' from -SolutionShortName"
        $script:Writes | Should -HaveCount 0
    }

    It 'refuses the pre migration script without a short name rather than guessing it from a display name' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId; SolutionName = $script:SolutionName; SignInAppClientId = $script:Ids.SignInAppId; NceUserGroupId = $script:Ids.Group; SubscriptionId = $script:Ids.Subscription; ResourceGroupName = $script:RgName }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'needs SolutionShortName'
        Should -Invoke Connect-MgGraph -Times 0
        $script:Writes | Should -HaveCount 0
    }

    It 'finds the user group by its version 5 name when the command gives no group id, so the assignment and the consent check run' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId; SolutionShortName = $script:ShortName; SolutionName = $script:SolutionName; SignInAppClientId = $script:Ids.SignInAppId; SubscriptionId = $script:Ids.Subscription; ResourceGroupName = $script:RgName }
        $code | Should -Be 0
        Get-SummaryResult 'User group assignment' | Should -Be 'Already assigned'
        Get-SummaryResult 'Administrator consent' | Should -Be 'Present'
        $script:Writes | Should -HaveCount 0
    }

    It 'skips the group assignment and consent check when no group exists and the command gives no group id' {
        Add-CompliantPreWindowState
        $script:Tenant.Groups = @($script:Tenant.Groups | Where-Object { $_.id -eq $script:Ids.AdminGroup })
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId; SolutionShortName = $script:ShortName; SolutionName = $script:SolutionName; SignInAppClientId = $script:Ids.SignInAppId; SubscriptionId = $script:Ids.Subscription; ResourceGroupName = $script:RgName; Verify = $true }
        $code | Should -Be 1
        Get-SummaryResult 'User group assignment' | Should -Be 'SKIPPED: the command gives no SignInAppClientId or no NceUserGroupId'
        Get-SummaryResult 'Administrator consent' | Should -BeNullOrEmpty
        $script:Writes | Should -HaveCount 0
    }

    It 'refuses the pre migration script without the sign-in app client id or the solution name' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId; SolutionShortName = $script:ShortName; SolutionName = $script:SolutionName; NceUserGroupId = $script:Ids.Group; SubscriptionId = $script:Ids.Subscription; ResourceGroupName = $script:RgName }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'needs SignInAppClientId'
        Should -Invoke Connect-MgGraph -Times 0

        $script:Console = @()
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId; SolutionShortName = $script:ShortName; SignInAppClientId = $script:Ids.SignInAppId; NceUserGroupId = $script:Ids.Group; SubscriptionId = $script:Ids.Subscription; ResourceGroupName = $script:RgName }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'needs SolutionName'
        Should -Invoke Connect-MgGraph -Times 0
        $script:Writes | Should -HaveCount 0
    }

    It 'rejects a bot app client id that is not a GUID' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); BotAppClientIds = @('not-a-guid') }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'BotAppClientIds must be a GUID'
        Should -Invoke Connect-MgGraph -Times 0
    }
}

Context 'The pre migration script on an environment with missing state' {
    It 'in the post migration script grants the retained access and then removes the wider access, in that order' {
        Add-CompliantPreWindowState
        $deploy = Get-FakeSp -Id $script:Ids.DeploySpId
        $deploy.appRoleAssignments = @()
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'Application.Read.All'
        $script:Tenant.AzRoleAssignments = @(@{ ObjectId = $script:Ids.Me; RoleDefinitionName = 'Owner'; Scope = '/' })
        $script:Tenant.DirectoryRoles = @()
        Add-LegacyAzureState
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Deployment identity permission: Application.ReadWrite.OwnedBy' | Should -Be 'Granted'
        Get-SummaryResult 'Deployment identity permission to remove: Application.Read.All' | Should -Be 'Removed'
        Get-SummaryResult 'Resource group role: Contributor' | Should -Be 'Assigned'
        Get-SummaryResult 'Subscription role to remove: User Access Administrator' | Should -Be 'Removed'
        Get-SummaryResult 'Application Administrator role' | Should -Be 'Removed'
        $kinds = @($script:Writes | ForEach-Object {
                if ($_ -like 'NEW approle*') { 'graph-grant' }
                elseif ($_ -like 'REMOVE approle*') { 'graph-remove' }
                elseif ($_ -like 'NEW az role*') { 'az-create' }
                elseif ($_ -like 'REMOVE az role*') { 'az-remove' }
                elseif ($_ -like 'REMOVE directory role member*') { 'role-remove' }
                elseif ($_ -like 'POST directory role*') { 'kit-item' }
                else { $_ } })
        @($kinds | Where-Object { $_ -ne 'kit-item' } | Select-Object -Unique) | Should -Be @('graph-grant', 'graph-remove', 'az-create', 'az-remove', 'role-remove')
        Should -Invoke Connect-AzAccount -Times 1
    }

    It 'creates the blueprint, its principal, ownership, role and credentials, then verifies clean on a second run' {
        Add-CompliantAzureState
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'Application.ReadWrite.OwnedBy'
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'AgentIdentityBlueprint.AddRemoveCreds.All'
        $group = @($script:Tenant.Groups)[0]
        $group.appRoleAssignments = @(@{ Id = 'x'; ResourceId = $script:Ids.SignInSpId; AppRoleId = '00000000-0000-0000-0000-000000000000' })
        (Get-FakeSp -Id $script:Ids.SignInSpId).grants = @(@{ id = 'g'; clientId = $script:Ids.SignInSpId; consentType = 'AllPrincipals'; principalId = $null; resourceId = $script:Ids.GraphSpId; scope = 'User.Read' })
        $script:Tenant.PrincipalCreateDelays = 2
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Agent identity blueprint' | Should -Be 'Created'
        Get-SummaryResult 'Agent identity blueprint owner' | Should -Be 'Already an owner' -Because 'owners@odata.bind set the deployment identity at creation'
        Get-SummaryResult 'Agent identity blueprint sponsor' | Should -Be 'Present: Contoso Administrator' -Because 'sponsors@odata.bind set the signed-in administrator at creation'
        @($script:Writes | Where-Object { $_ -like 'POST blueprint sponsor*' }) | Should -HaveCount 0
        Get-SummaryResult 'Agent identity blueprint service principal' | Should -Be 'Created'
        Get-SummaryResult 'Agent identity blueprint service principal owner' | Should -Be 'Already an owner' -Because 'owners@odata.bind set the deployment identity at creation'
        @($script:Writes | Where-Object { $_ -like 'POST sp owner*' }) | Should -HaveCount 0 -Because 'Microsoft Graph refuses a later owner call without AgentIdentityBlueprintPrincipal.ReadWrite.All'
        $blueprintSp = @($script:Tenant.ServicePrincipals | Where-Object { $_.displayName -like 'Neologik Agent Blueprint*' })[0]
        $blueprintSp.owners | Should -Be @($script:Ids.DeploySpId)
        Get-SummaryResult 'Agent identity blueprint service principal permission: AgentIdUser.ReadWrite.IdentityParentedBy' | Should -Be 'Granted'
        Get-SummaryResult 'Agent identity blueprint credential: github-oidc-neo-infrastructure' | Should -Be 'Added'
        @($script:Writes | Where-Object { $_ -like 'POST credential github-oidc*' }) | Should -HaveCount 3
        @($script:Sleeps | Where-Object { $_ -eq 15 }) | Should -HaveCount 2 -Because 'the principal create is retried while the blueprint replicates'
        $blueprintApp = @($script:Tenant.Apps | Where-Object { $_.displayName -like 'Neologik Agent Blueprint*' })[0]
        $blueprintApp.displayName | Should -Be "Neologik Agent Blueprint - default - $script:ShortName"
        $blueprintApp.owners | Should -Contain $script:Ids.DeploySpId
        $blueprintApp.owners | Should -Contain $script:Ids.Me
        # Second run: nothing left to do.
        $script:Writes = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        Get-SummaryResult 'Agent identity blueprint service principal' | Should -Be 'Present'
    }

    It 'adopts a pipeline-created blueprint the deployment identity does not own yet' {
        Add-CompliantPreWindowState
        $app = Get-FakeApp -Id $script:Ids.BlueprintAppObj
        $app.owners = @($script:Ids.Me)
        $principal = Get-FakeSp -Id $script:Ids.BlueprintSpId
        $principal.owners = @()
        $app.credentials = @('github-oidc-neo-infrastructure')
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Agent identity blueprint owner' | Should -Be 'Added'
        Get-SummaryResult 'Agent identity blueprint service principal owner' | Should -Be 'Added'
        Get-SummaryResult 'Agent identity blueprint credential: github-oidc-neo-infrastructure' | Should -Be 'Present'
        Get-SummaryResult 'Agent identity blueprint credential: github-oidc-neo-bot-service' | Should -Be 'Added'
        $app.owners | Should -Contain $script:Ids.DeploySpId
        $principal.owners | Should -Contain $script:Ids.DeploySpId
        @($script:Writes) | Should -HaveCount 4
    }

    It 'grants the retained Graph roles before removing the retired ones' {
        Add-CompliantPreWindowState
        $deploy = Get-FakeSp -Id $script:Ids.DeploySpId
        $deploy.appRoleAssignments = @()
        foreach ($roleName in @('Application.Read.All', 'AgentIdentity.Create.All', 'Group.Create')) { Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName $roleName }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Deployment identity permission: Application.ReadWrite.OwnedBy' | Should -Be 'Granted'
        Get-SummaryResult 'Deployment identity permission: AgentIdentityBlueprint.AddRemoveCreds.All' | Should -Be 'Granted'
        Get-SummaryResult 'Deployment identity permission to remove: Application.Read.All' | Should -Be 'Removed'
        Get-SummaryResult 'Deployment identity permission to remove: Group.Create' | Should -Be 'Removed'
        Get-SummaryResult 'Deployment identity permission to remove: AgentIdUser.ReadWrite.All' | Should -Be 'Not held'
        $roleWrites = @($script:Writes | Where-Object { $_ -match "approle $($script:Ids.DeploySpId)" })
        $roleWrites | Should -HaveCount 5
        $roleWrites[0] | Should -Match '^NEW'
        $roleWrites[1] | Should -Match '^NEW'
        $roleWrites[2] | Should -Match '^REMOVE'
        $held = @((Get-FakeSp -Id $script:Ids.DeploySpId).appRoleAssignments | ForEach-Object { $_.AppRoleId })
        $held | Should -HaveCount 2
        $held | Should -Contain $script:AppRoleIds['Application.ReadWrite.OwnedBy']
    }

    It 'leaves the retired roles in place when a retained role could not be granted' {
        Add-CompliantPreWindowState
        $deploy = Get-FakeSp -Id $script:Ids.DeploySpId
        $deploy.appRoleAssignments = @()
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'Application.Read.All'
        Mock New-MgServicePrincipalAppRoleAssignment { throw (New-ForbiddenException) }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Deployment identity permission: Application.ReadWrite.OwnedBy') | Should -Match '^FAILED: insufficient privileges'
        Get-SummaryResult 'Deployment identity permission to remove: Application.Read.All' | Should -Be 'SKIPPED: the deployment identity does not hold both permissions that the deployment identity keeps'
        Should -Invoke Remove-MgServicePrincipalAppRoleAssignment -Times 0
        (Get-FakeSp -Id $script:Ids.DeploySpId).appRoleAssignments | Should -HaveCount 1
    }

    It 'reports a Graph role the cloud does not publish without stopping' {
        Add-CompliantPreWindowState
        $script:AppRoleIds.Remove('AgentIdentityBlueprint.AddRemoveCreds.All')
        try {
            $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
            $code | Should -Be 1
            Get-SummaryResult 'Deployment identity permission: AgentIdentityBlueprint.AddRemoveCreds.All' | Should -Be 'NOT FOUND: report to Neologik'
            Get-SummaryResult 'Administrator consent' | Should -Be 'Present'
        }
        finally {
            $script:AppRoleIds['AgentIdentityBlueprint.AddRemoveCreds.All'] = [guid]::NewGuid().ToString()
        }
    }

    It 'assigns the NCE user group to the sign-in application when missing' {
        Add-CompliantPreWindowState
        $group = @($script:Tenant.Groups)[0]
        $group.appRoleAssignments = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'User group assignment' | Should -Be 'Assigned'
        Should -Invoke New-MgGroupAppRoleAssignment -Times 1 -ParameterFilter { $GroupId -eq $script:Ids.Group -and $PrincipalId -eq $script:Ids.Group -and $ResourceId -eq $script:Ids.SignInSpId -and $AppRoleId -eq '00000000-0000-0000-0000-000000000000' }
        $script:Writes | Should -HaveCount 1
    }

    It 'fills the NCE user group when it has no direct members' {
        Add-CompliantPreWindowState
        $group = @($script:Tenant.Groups)[0]
        $group.members = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        # Step 2 adds the guest and the administrator (project#3127); the member
        # count that step 3 reports is then two.
        @($script:Writes | Where-Object { $_ -like "POST group member Neologik NCE Contributors - $script:ShortName *" }) | Should -HaveCount 2
        ($script:Console -join "`n") | Should -Match 'has 2 direct member'
        ($script:Console -join "`n") | Should -Not -Match 'has no members'
    }

    It 'reports a missing group and a missing sign-in application as MISSING, not as a crash' {
        Add-CompliantPreWindowState
        # an id no object in the fake tenant carries
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile -Overrides @{ SecurityGroups = @(@{ Name = "Neologik NCE User Group - $script:ShortName"; Id = '55555555-ffff-5555-5555-555555555555' }) }) }
        $code | Should -Be 1
        Get-SummaryResult 'User group assignment' | Should -Be 'MISSING: the tenant holds no group with this id. Check the value of -NceUserGroupId'
        Get-SummaryResult 'Administrator consent' | Should -Be 'Present'
        $script:Tenant = New-EmptyTenant
        Add-CompliantPreWindowState
        $script:Tenant.ServicePrincipals = @($script:Tenant.ServicePrincipals | Where-Object { $_.id -ne $script:Ids.SignInSpId })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'User group assignment' | Should -Be 'MISSING: the tenant holds no Platform Sign-in application with this client id'
        Get-SummaryResult 'Administrator consent' | Should -Be 'SKIPPED: the tenant holds no Platform Sign-in application with this client id'
    }

    It 'prints the consent URL when tenant-wide admin consent is missing' {
        Add-CompliantPreWindowState
        (Get-FakeSp -Id $script:Ids.SignInSpId).grants = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Administrator consent' | Should -Be 'MISSING: the script printed the consent address'
        ($script:Console -join "`n") | Should -Match "https://login.microsoftonline.com/$($script:Ids.Tenant)/adminconsent\?client_id=$($script:Ids.SignInAppId)"
        $script:Writes | Should -HaveCount 0
    }

    It 'treats a user-level grant as no tenant-wide consent' {
        Add-CompliantPreWindowState
        (Get-FakeSp -Id $script:Ids.SignInSpId).grants = @(@{ id = 'p'; clientId = $script:Ids.SignInSpId; consentType = 'Principal'; principalId = $script:Ids.Me; resourceId = $script:Ids.GraphSpId; scope = 'User.Read' })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Administrator consent' | Should -Be 'MISSING: the script printed the consent address'
    }

    It 'continues past a blueprint failure and records the dependents as skipped' {
        Add-CompliantPreWindowState
        $script:Faults += @{ Match = 'GET /applications$'; Status = 403; Code = 'Authorization_RequestDenied'; Message = 'Insufficient privileges'; Remaining = 1 }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Agent identity blueprint') | Should -Match '^FAILED: insufficient privileges'
        Get-SummaryResult 'Agent identity blueprint service principal' | Should -Be 'SKIPPED: the agent identity blueprint is not available'
        Get-SummaryResult 'Deployment identity permission: Application.ReadWrite.OwnedBy' | Should -Be 'Already granted'
        Get-SummaryResult 'Administrator consent' | Should -Be 'Present'
    }
}

Context 'SharePoint consent and an earlier SharePoint application' {
    It 'grants Sites.Selected to the SharePoint application when an earlier application holds the consent' {
        Add-CompliantPreWindowState
        Add-SharePointApp
        Add-EarlierSharePointApp
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be "Granted to 'Neologik SharePoint Access - $script:ShortName'"
        $script:Writes | Should -HaveCount 1
        $script:Writes[0] | Should -Be "NEW approle $($script:Ids.SharePointSpId) $($script:AppRoleIds['Sites.Selected'])"
        ($script:Console -join "`n") | Should -Match 'A site administrator grants access to each site separately'
        # A second run finds the consent and writes nothing.
        $script:Writes = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Present'
        $script:Writes | Should -HaveCount 0
    }

    It 'grants Sites.Selected only, when the earlier application holds a wider SharePoint permission' {
        Add-CompliantPreWindowState
        Add-SharePointApp
        Add-EarlierSharePointApp -RoleName 'Sites.FullControl.All'
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be "Granted to 'Neologik SharePoint Access - $script:ShortName'"
        $script:Writes | Should -HaveCount 1
        $script:Writes[0] | Should -Be "NEW approle $($script:Ids.SharePointSpId) $($script:AppRoleIds['Sites.Selected'])"
    }

    It 'reports the grant as WOULD GRANT in a run with -Verify and writes nothing' {
        Add-CompliantPreWindowState
        Add-SharePointApp
        Add-EarlierSharePointApp
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 1
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be "WOULD GRANT Sites.Selected to 'Neologik SharePoint Access - $script:ShortName'"
        $script:Writes | Should -HaveCount 0
    }

    It 'asks for a second run when the SharePoint application of the environment does not exist yet' {
        Add-CompliantPreWindowState
        Add-EarlierSharePointApp
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be "MISSING: the SharePoint application of this environment does not exist. The application 'Neologik SharePoint API Access' holds a SharePoint permission. Run the script again after the deployment by Neologik"
        $script:Writes | Should -HaveCount 0
    }

    It 'changes nothing when the SharePoint application already holds the consent' {
        Add-CompliantPreWindowState
        Add-SharePointApp -WithConsent
        Add-EarlierSharePointApp
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Present'
        $script:Writes | Should -HaveCount 0
    }

    It 'grants nothing and prints no consent address when no Neologik application holds a SharePoint permission' {
        Add-CompliantPreWindowState
        Add-SharePointApp
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Not needed. No SharePoint application of Neologik holds a SharePoint permission'
        $script:Writes | Should -HaveCount 0
        ($script:Console -join "`n") | Should -Not -Match 'adminconsent\?client_id='
    }

    It 'does not treat the SharePoint application of another environment as an earlier application' {
        Add-CompliantPreWindowState
        Add-SharePointApp -Second
        Add-FakeAppRole -SpId $script:Ids.SharePoint2SpId -RoleName 'Sites.Selected'
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Not needed. No SharePoint application of Neologik holds a SharePoint permission'
        $script:Writes | Should -HaveCount 0
    }

    It 'finds the SharePoint application by the client id that the command names' {
        Add-CompliantPreWindowState
        $script:Tenant.ServicePrincipals += New-FakeSp -Id $script:Ids.SharePointSpId -AppId $script:Ids.SharePointAppId -DisplayName 'Contoso document access'
        Add-EarlierSharePointApp
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); SharePointAppClientId = $script:Ids.SharePointAppId }
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be "Granted to 'Contoso document access'"
        @($script:Writes | Where-Object { $_ -eq "NEW approle $($script:Ids.SharePointSpId) $($script:AppRoleIds['Sites.Selected'])" }) | Should -HaveCount 1
    }

    It 'reports a refused grant as FAILED and continues' {
        Add-CompliantPreWindowState
        Add-SharePointApp
        Add-EarlierSharePointApp
        Mock New-MgServicePrincipalAppRoleAssignment { throw 'Authorization_RequestDenied: Insufficient privileges to complete the operation.' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'FAILED: insufficient privileges. Sign in as a Global Administrator'
        Get-SummaryResult 'Resource group role: Contributor' | Should -Be 'Already assigned'
    }
}

Context 'Platform app ownership' {
    It 'verifies the sign-in app and reports no SharePoint app and no bots listed on a compliant environment' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult "Registration 'Neologik Platform Sign-in - $script:ShortName' owner" | Should -Be 'Already an owner'
        Get-SummaryResult "Registration 'Neologik Platform Sign-in - $script:ShortName' service principal owner" | Should -Be 'Already an owner'
        Get-SummaryResult "Registration 'Neologik Platform Sign-in - $script:ShortName' unique name" | Should -Be 'Already set'
        Get-SummaryResult "Registration 'Neologik Platform Sign-in - $script:ShortName' client secrets" | Should -Be 'None from another source'
        Get-SummaryResult 'SharePoint application registration' | Should -Match '^Not listed'
        Get-SummaryResult 'Agent registrations' | Should -Match '^None listed'
        $script:Writes | Should -HaveCount 0
    }

    It 'leaves the application registration of the deployment identity out of the review' {
        Add-CompliantPreWindowState
        # In a customer tenant the registration of the deployment identity carries the platform name.
        (Get-FakeApp -Id $script:Ids.DeployAppObj).displayName = "Neologik GitHub Service Connection - $script:ShortName"
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult "Registration not on the list: 'Neologik GitHub Service Connection - $script:ShortName'" | Should -BeNullOrEmpty
        $script:Writes | Should -HaveCount 0
    }

    It 'adopts exactly the listed registrations and only reports the rest' {
        Add-CompliantPreWindowState
        $t = $script:Tenant
        $spAppId = 'b1b1b1b1-0000-4000-8000-000000000001'
        $botAppId = 'b2b2b2b2-0000-4000-8000-000000000002'
        # The sign-in app as an administrator made it by hand: no deployment owner, no uniqueName.
        $signIn = Get-FakeApp -Id $script:Ids.SignInAppObj
        $signIn.owners = @($script:Ids.Me)
        $signIn.uniqueName = ''
        (Get-FakeSp -Id $script:Ids.SignInSpId).owners = @($script:Ids.Me)
        # A hand-made SharePoint app with a customer's own credential beside the deployment's.
        $sp = New-FakeApp -Id 'spapp-obj' -AppId $spAppId -DisplayName "Neologik SharePoint Access - $script:ShortName"
        $sp.owners = @($script:Ids.Me)
        $sp.passwordCredentials = @(@{ displayName = 'sharepoint-access' }, @{ displayName = 'power-automate' })
        $t.Apps += $sp
        $spPrincipal = New-FakeSp -Id 'spsp-obj' -AppId $spAppId -DisplayName $sp.displayName
        $spPrincipal.owners = @($script:Ids.Me)
        $t.ServicePrincipals += $spPrincipal
        # An agent registration named by hand, listed by client id, with a secret
        # the deployment did not create and will remove.
        $bot = New-FakeApp -Id 'bot-obj' -AppId $botAppId -DisplayName 'ABC Chat Agent'
        $bot.owners = @($script:Ids.Me)
        $bot.passwordCredentials = @(@{ displayName = 'manual-secret' })
        $t.Apps += $bot
        $t.ServicePrincipals += (New-FakeSp -Id 'bot-sp' -AppId $botAppId -DisplayName $bot.displayName)
        # Registrations named for the platform but NOT listed: reported, never touched.
        $lookalike = New-FakeApp -Id 'look-obj' -AppId 'c3c3c3c3-0000-4000-8000-000000000003' -DisplayName "Neologik Integration - $script:ShortName"
        $t.Apps += $lookalike
        $t.Apps += (New-FakeApp -Id 'other-obj' -AppId 'c4c4c4c4-0000-4000-8000-000000000004' -DisplayName 'Neologik - ide - otherenv')

        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); SharePointAppClientId = $spAppId; BotAppClientIds = @($botAppId) }
        $code | Should -Be 1 -Because 'the bot app carries a credential the deployment will remove'
        $signIn.owners | Should -Contain $script:Ids.DeploySpId
        (Get-FakeSp -Id $script:Ids.SignInSpId).owners | Should -Contain $script:Ids.DeploySpId
        $signIn.uniqueName | Should -Be "sp-admin-$script:SolutionName"
        $sp.owners | Should -Contain $script:Ids.DeploySpId
        $spPrincipal.owners | Should -Contain $script:Ids.DeploySpId
        $sp.uniqueName | Should -Be "sp-neologik-sharepoint-$script:ShortName"
        $bot.owners | Should -Contain $script:Ids.DeploySpId
        (Get-FakeSp -Id 'bot-sp').owners | Should -Contain $script:Ids.DeploySpId
        $lookalike.owners | Should -HaveCount 0
        (Get-FakeApp -Id 'other-obj').owners | Should -HaveCount 0
        Get-SummaryResult "Registration 'Neologik SharePoint Access - $script:ShortName' client secrets" | Should -Match '^Review: 1 client secret\(s\) that the deployment did not create: power-automate'
        Get-SummaryResult "Registration 'ABC Chat Agent' client secrets" | Should -Match '^PENDING: 1 client secret\(s\) that the deployment did not create: manual-secret'
        Get-SummaryResult "Registration 'ABC Chat Agent' unique name" | Should -Match '^Not required'
        Get-SummaryResult "Registration not on the list: 'Neologik Integration - $script:ShortName'" | Should -Match '^Review: the command does not name c3c3c3c3-0000-4000-8000-000000000003\. The script did not change the application registration'
        Get-SummaryResult "Registration not on the list: 'Neologik - ide - otherenv'" | Should -Match '^Review: '
        Get-SummaryResult 'Agent registrations' | Should -BeNullOrEmpty
        ($script:Console -join "`n") | Should -Match 'removes every client secret of this application registration'
        @($script:Writes | Where-Object { $_ -match 'look-obj|other-obj' }) | Should -HaveCount 0

        # Second run: everything already in place; the secret still needs attention.
        $script:Writes = @()
        $script:Summary = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); SharePointAppClientId = $spAppId; BotAppClientIds = @($botAppId) }
        $code | Should -Be 1
        $script:Writes | Should -HaveCount 0
        Get-SummaryResult "Registration 'Neologik SharePoint Access - $script:ShortName' owner" | Should -Be 'Already an owner'
        Get-SummaryResult "Registration 'Neologik SharePoint Access - $script:ShortName' unique name" | Should -Be 'Already set'
        Get-SummaryResult "Registration 'ABC Chat Agent' owner" | Should -Be 'Already an owner'
    }

    It 'accepts the bot ids as one comma-separated value and fails a listed id that is not in this tenant' {
        Add-CompliantPreWindowState
        $botAppId = 'b2b2b2b2-0000-4000-8000-000000000002'
        $missingId = 'd5d5d5d5-0000-4000-8000-000000000005'
        $bot = New-FakeApp -Id 'bot-obj' -AppId $botAppId -DisplayName 'ABC Chat Agent'
        $bot.owners = @($script:Ids.DeploySpId)
        $script:Tenant.Apps += $bot
        $botSp = New-FakeSp -Id 'bot-sp' -AppId $botAppId -DisplayName $bot.displayName
        $botSp.owners = @($script:Ids.DeploySpId)
        $script:Tenant.ServicePrincipals += $botSp
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); BotAppClientIds = @("$botAppId,$missingId") }
        $code | Should -Be 1
        Get-SummaryResult "Registration 'ABC Chat Agent' owner" | Should -Be 'Already an owner'
        Get-SummaryResult "Agent registration $missingId" | Should -Match '^NOT FOUND: this tenant holds no application registration with this client id'
        @($script:Writes | Where-Object { $_ -notmatch $script:Ids.DirectorySpId }) | Should -HaveCount 0 -Because 'only the directory managed identity becomes an owner'
        $bot.owners | Should -Contain $script:Ids.DirectorySpId
    }

    It 'records the adoption as pending in verify-only and writes nothing' {
        Add-CompliantPreWindowState
        $signIn = Get-FakeApp -Id $script:Ids.SignInAppObj
        $signIn.owners = @($script:Ids.Me)
        $signIn.uniqueName = ''
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 1
        Get-SummaryResult "Registration 'Neologik Platform Sign-in - $script:ShortName' owner" | Should -Be 'WOULD ADD'
        Get-SummaryResult "Registration 'Neologik Platform Sign-in - $script:ShortName' unique name" | Should -Be "WOULD SET sp-admin-$script:SolutionName"
        $script:Writes | Should -HaveCount 0
        $signIn.owners | Should -Not -Contain $script:Ids.DeploySpId
    }

    It 'fails the uniqueName when it differs from the deployment name, and refuses to run without the solution name' {
        Add-CompliantPreWindowState
        $signIn = Get-FakeApp -Id $script:Ids.SignInAppObj
        $signIn.uniqueName = 'sp-admin-something-else'
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult "Registration 'Neologik Platform Sign-in - $script:ShortName' unique name" | Should -Match "^FAILED: the unique name is 'sp-admin-something-else'\. The deployment expects 'sp-admin-$script:SolutionName'"

        $signIn.uniqueName = ''
        $script:Summary = @()
        $script:Console = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile -Remove @('SolutionName')) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'needs SolutionName'
        $signIn.uniqueName | Should -Be ''
    }

    It 'reports a sign-in registration that is not in this tenant' {
        Add-CompliantPreWindowState
        $script:Tenant.Apps = @($script:Tenant.Apps | Where-Object { $_.id -ne $script:Ids.SignInAppObj })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Platform Sign-in application registration' | Should -Match '^NOT FOUND: this tenant holds no application registration with this client id'
    }
}

Context 'Graph resilience' {
    BeforeEach {
        Add-CompliantPreWindowState
    }

    It 'retries throttling with the Retry-After delay and succeeds' {
        $script:Faults += @{ Match = 'GET /applications$'; Status = 429; Code = 'TooManyRequests'; Message = 'throttled'; Remaining = 1; Headers = @{ 'Retry-After' = @('3') } }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Sleeps | Should -Contain 3
        Get-SummaryResult 'Agent identity blueprint' | Should -Be 'Present'
        $script:Writes | Should -HaveCount 0
    }

    It 'retries transient service errors and gives up with a recorded failure' {
        $script:Faults += @{ Match = 'GET /applications/[^/]+/owners$'; Status = 503; Code = 'ServiceUnavailable'; Message = 'try later'; Remaining = 2 }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Agent identity blueprint owner' | Should -Be 'Already an owner'
        @($script:Sleeps) | Should -HaveCount 2
        $script:Tenant = New-EmptyTenant
        Add-CompliantPreWindowState
        $script:Faults = @(@{ Match = 'GET /applications/[^/]+/owners$'; Status = 500; Code = 'InternalServerError'; Message = 'boom'; Remaining = 99 })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Agent identity blueprint owner') | Should -Match '^FAILED: Microsoft Graph GET /v1.0/applications/.+ returned HTTP 500\. InternalServerError: boom'
        Get-SummaryResult 'Agent identity blueprint service principal' | Should -Be 'Present'
        Get-SummaryResult 'Administrator consent' | Should -Be 'Present'
    }

    It 'retries a not-found right after a create (replication delay)' {
        $script:Tenant.Apps = @($script:Tenant.Apps | Where-Object { $_.displayName -notlike 'Neologik Agent Blueprint*' })
        $script:Tenant.ServicePrincipals = @($script:Tenant.ServicePrincipals | Where-Object { $_.id -ne $script:Ids.BlueprintSpId })
        $script:Faults += @{ Match = 'GET /applications/[^/]+/owners$'; Status = 404; Code = 'Request_ResourceNotFound'; Message = 'not replicated'; Remaining = 1 }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Agent identity blueprint' | Should -Be 'Created'
        Get-SummaryResult 'Agent identity blueprint owner' | Should -Be 'Already an owner'
    }

    It 'does not retry a not-found on a plain read' {
        $script:Faults += @{ Match = 'GET /applications/[^/]+/owners$'; Status = 404; Code = 'Request_ResourceNotFound'; Message = 'gone'; Remaining = 1 }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Agent identity blueprint owner') | Should -Match 'HTTP 404'
        @($script:Sleeps) | Should -HaveCount 0
    }

    It 'follows @odata.nextLink so an owner on a later page is seen' {
        $app = Get-FakeApp -Id $script:Ids.BlueprintAppObj
        $principal = Get-FakeSp -Id $script:Ids.BlueprintSpId
        $filler = @(1..5 | ForEach-Object { [guid]::NewGuid().ToString() })
        $app.owners = @($filler) + @($script:Ids.DeploySpId)
        $principal.owners = @($filler) + @($script:Ids.DeploySpId)
        $app.credentials = @(1..7 | ForEach-Object { "other-cred-$_" }) + $app.credentials
        $script:Tenant.PageSize = 2
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Agent identity blueprint owner' | Should -Be 'Already an owner'
        Get-SummaryResult 'Agent identity blueprint service principal owner' | Should -Be 'Already an owner'
        Get-SummaryResult 'Agent identity blueprint credential: github-oidc-neo-env-config' | Should -Be 'Present'
        $script:Writes | Should -HaveCount 0
        @($script:GraphCalls | Where-Object { $_ -match 'GET /applications/[^/]+/owners$' }).Count | Should -BeGreaterThan 1
    }

    It 'treats an "already exists" reply to an owner add as already in place' {
        $app = Get-FakeApp -Id $script:Ids.BlueprintAppObj
        $app.owners = @($script:Ids.Me)
        $script:Faults += @{ Match = 'GET /applications/[^/]+/owners$'; Status = 200; Code = ''; Message = ''; Remaining = 0 }
        Mock Invoke-NeologikGraphRaw {
            param($Method, $Uri, $Body)
            if ($Method -eq 'POST' -and $Uri -match '/owners/\$ref$') {
                return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = 'One or more added object references already exist for the following modified properties' } } }
            }
            Invoke-FakeGraph -Method $Method -Uri $Uri -Body $Body
        }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Agent identity blueprint owner' | Should -Be 'Already an owner'
    }

    It 'never lets an unexpected exception escape: the run is recorded and the summary written' {
        Mock Set-NeologikAgentBlueprint { throw 'something nobody anticipated' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Run' | Should -Be 'FAILED: unexpected error. something nobody anticipated'
        @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_PreWindow_*.json') | Should -HaveCount 1
    }
}

Context 'The post migration script: the script runner identity (step 6i, project#2970)' {
    It 'gives the script runner identity Reader on the resource group, then removes both Contributor roles' {
        Add-CompliantPreWindowState
        Add-LegacyScriptRunnerState
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile); ScriptRunnerObjectId = $script:Ids.ScriptRunnerId }
        $code | Should -Be 0
        $script:Writes | Should -Be @(
            "NEW az role Reader $script:RgScope",
            "REMOVE az role Contributor $script:SubScope",
            "REMOVE az role Contributor $script:RgScope")
        Get-SummaryResult 'Script runner identity resource group role: Reader' | Should -Be 'Assigned'
        Get-SummaryResult 'Script runner identity subscription role to remove: Contributor' | Should -Be 'Removed'
        Get-SummaryResult 'Script runner identity resource group role to remove: Contributor' | Should -Be 'Removed'
        Get-ScriptRunnerRoles $script:SubScope | Should -HaveCount 0
        Get-ScriptRunnerRoles $script:RgScope | Should -Be @('Azure Bot Service Contributor Role', 'Key Vault Secrets Officer', 'Reader')
        # The deployment identity's own roles are untouched by the step.
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.ObjectId -eq $script:Ids.DeploySpId }) | Should -HaveCount 10
    }

    It 'changes nothing for a script runner identity that already holds Reader and no Contributor' {
        Add-CompliantPreWindowState
        foreach ($roleName in @('Reader', 'Key Vault Secrets Officer', 'Azure Bot Service Contributor Role')) {
            $script:Tenant.AzRoleAssignments += @{ ObjectId = $script:Ids.ScriptRunnerId; RoleDefinitionName = $roleName; Scope = $script:RgScope }
        }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile); ScriptRunnerObjectId = $script:Ids.ScriptRunnerId }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        Get-SummaryResult 'Script runner identity resource group role: Reader' | Should -Be 'Already assigned'
        Get-SummaryResult 'Script runner identity subscription role to remove: Contributor' | Should -Be 'Not held'
        Get-SummaryResult 'Script runner identity resource group role to remove: Contributor' | Should -Be 'Not held'
    }

    It 'keeps both Contributor roles when Reader could not be assigned' {
        Add-CompliantPreWindowState
        Add-LegacyScriptRunnerState
        Mock New-AzRoleAssignment { param($ObjectId) if ($ObjectId -eq $script:Ids.ScriptRunnerId) { throw 'AuthorizationFailed: The client does not have authorization' }; Add-Write "NEW az role $RoleDefinitionName $Scope" }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile); ScriptRunnerObjectId = $script:Ids.ScriptRunnerId }
        $code | Should -Be 1
        (Get-SummaryResult 'Script runner identity resource group role: Reader') | Should -Match '^FAILED: insufficient privileges'
        Get-SummaryResult 'Script runner identity subscription role to remove: Contributor' | Should -Be 'SKIPPED: the script runner identity does not hold Reader on the resource group'
        Should -Invoke Remove-AzRoleAssignment -Times 0
        Get-ScriptRunnerRoles $script:SubScope | Should -Be @('Contributor')
    }

    It 'leaves the script runner identity alone when the command does not name it' {
        Add-CompliantPreWindowState
        Add-LegacyScriptRunnerState
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        Get-SummaryResult 'Script runner identity resource group role: Reader' | Should -BeNullOrEmpty
        Get-ScriptRunnerRoles $script:SubScope | Should -Be @('Contributor')
        ($script:Console -join "`n") | Should -Match 'does not name the script runner identity'
    }

    It 'with -Verify reports the three changes as pending and writes nothing' {
        Add-CompliantPreWindowState
        Add-LegacyScriptRunnerState
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile); ScriptRunnerObjectId = $script:Ids.ScriptRunnerId; Verify = $true }
        $script:Writes | Should -HaveCount 0
        Get-SummaryResult 'Script runner identity resource group role: Reader' | Should -Be 'WOULD ASSIGN'
        Get-SummaryResult 'Script runner identity subscription role to remove: Contributor' | Should -Be 'WOULD REMOVE'
        Get-SummaryResult 'Script runner identity resource group role to remove: Contributor' | Should -Be 'WOULD REMOVE'
        Get-ScriptRunnerRoles $script:SubScope | Should -Be @('Contributor')
    }

    It 'skips the script runner rows with the rest when the deployment identity lacks a role' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        Add-LegacyScriptRunnerState
        Mock New-AzRoleAssignment { param($RoleDefinitionName) if ($RoleDefinitionName -eq 'Monitoring Contributor') { throw 'AuthorizationFailed: The client does not have authorization' }; Add-Write "NEW az role $RoleDefinitionName $Scope" }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile); ScriptRunnerObjectId = $script:Ids.ScriptRunnerId }
        $code | Should -Be 1
        Get-SummaryResult 'Script runner identity subscription role to remove: Contributor' | Should -Be 'SKIPPED: the deployment identity does not hold all ten Azure roles'
        Should -Invoke Remove-AzRoleAssignment -Times 0
    }

    It 'refuses a script runner object id that is not a GUID before any sign-in' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile); ScriptRunnerObjectId = 'not-a-guid' }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'ScriptRunnerObjectId must be a GUID'
        Should -Invoke Connect-AzAccount -Times 0
    }
}

Context 'The post migration script: permission reduction (step 6)' {
    It 'on an already-hardened environment creates only the Cost Management Contributor grant' {
        Add-CompliantPreWindowState
        $script:Tenant.AzRoleAssignments = @($script:Tenant.AzRoleAssignments | Where-Object { $_.RoleDefinitionName -ne 'Cost Management Contributor' })
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 1
        $script:Writes[0] | Should -Be "NEW az role Cost Management Contributor $script:SubScope"
        Get-SummaryResult 'Resource group role: Contributor' | Should -Be 'Already assigned'
        Get-SummaryResult 'Subscription role: Reader' | Should -Be 'Already assigned'
        Get-SummaryResult 'Subscription role: Cost Management Contributor' | Should -Be 'Assigned'
        Get-SummaryResult 'Subscription role to remove: Contributor' | Should -Be 'Not held'
        Get-SummaryResult 'Application Administrator role' | Should -Be 'Not held'
        Should -Invoke Connect-AzAccount -Times 1 -ParameterFilter { $Tenant -eq $script:Ids.Tenant -and $Subscription -eq $script:Ids.Subscription -and $AccessToken -eq 'eyJ0b2tlbg' }
        # Second run: pure verification.
        $script:Writes = @()
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
    }

    It 'on a legacy environment applies the narrow set before removing the broad grants' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $news = @($script:Writes | Where-Object { $_ -like 'NEW az role*' })
        $removes = @($script:Writes | Where-Object { $_ -like 'REMOVE*' })
        $news | Should -HaveCount 10
        $removes | Should -HaveCount 3
        [array]::IndexOf($script:Writes, $removes[0]) | Should -BeGreaterThan ([array]::IndexOf($script:Writes, $news[-1]))
        Get-SummaryResult 'Subscription role to remove: Contributor' | Should -Be 'Removed'
        Get-SummaryResult 'Subscription role to remove: User Access Administrator' | Should -Be 'Removed'
        Get-SummaryResult 'Application Administrator role' | Should -Be 'Removed'
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.Scope -eq $script:SubScope }).RoleDefinitionName | Should -Be @('Reader', 'Cost Management Contributor', 'Role Based Access Control Administrator')
        @($script:Tenant.DirectoryRoles | Where-Object { $_.Id -eq $script:Ids.AppAdminRole })[0].members | Should -HaveCount 0
    }

    It 'does not mistake an inherited subscription role for the resource-group assignment' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Resource group role: Contributor' | Should -Be 'Assigned'
        # The Admin User Group holds Contributor on the resource group too (the onboarding kit's set): count the deployment identity's own assignment.
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.ObjectId -eq $script:Ids.DeploySpId -and $_.RoleDefinitionName -eq 'Contributor' -and $_.Scope -eq $script:RgScope }) | Should -HaveCount 1
    }

    It 'leaves the broad grants in place when a narrow role could not be applied, after the directory checks ran' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        Mock New-AzRoleAssignment { param($RoleDefinitionName) if ($RoleDefinitionName -eq 'Monitoring Contributor') { throw 'AuthorizationFailed: The client does not have authorization to perform action' }; $script:Tenant.AzRoleAssignments += @{ ObjectId = $ObjectId; RoleDefinitionName = $RoleDefinitionName; Scope = $Scope }; Add-Write "NEW az role $RoleDefinitionName $Scope" }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Resource group role: Monitoring Contributor') | Should -Match '^FAILED: insufficient privileges'
        Get-SummaryResult 'Subscription role to remove: Contributor' | Should -Be 'SKIPPED: the deployment identity does not hold all ten Azure roles'
        Get-SummaryResult 'Application Administrator role' | Should -Be 'SKIPPED: the deployment identity does not hold all ten Azure roles'
        Should -Invoke Remove-AzRoleAssignment -Times 0
        Should -Invoke Remove-MgDirectoryRoleMemberDirectoryObjectByRef -Times 0
        @($script:Tenant.DirectoryRoles | Where-Object { $_.Id -eq $script:Ids.AppAdminRole })[0].members | Should -Contain $script:Ids.DeploySpId
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.Scope -eq $script:SubScope -and $_.RoleDefinitionName -eq 'Contributor' }) | Should -HaveCount 1
        Get-SummaryResult 'Deployment identity permission to remove: Group.Create' | Should -Be 'Not held'
    }

    It 'treats a RoleAssignmentExists race as already in place' {
        Add-CompliantPreWindowState
        $script:Tenant.AzRoleAssignments = @($script:Tenant.AzRoleAssignments | Where-Object { $_.RoleDefinitionName -ne 'Reader' })
        Mock New-AzRoleAssignment { throw 'RoleAssignmentExists: The role assignment already exists.' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Subscription role: Reader' | Should -Be 'Already assigned'
    }

    It 'assigns the limited Role Based Access Control Administrator on the subscription with its condition' {
        Add-CompliantPreWindowState
        $script:Tenant.AzRoleAssignments = @($script:Tenant.AzRoleAssignments | Where-Object { -not ($_.RoleDefinitionName -eq $script:LimitedSubRole -and $_.Scope -eq $script:SubScope) })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Subscription role: Role Based Access Control Administrator (limited)' | Should -Be 'Assigned'
        $limited = @($script:Tenant.AzRoleAssignments | Where-Object { $_.RoleDefinitionName -eq $script:LimitedSubRole -and $_.Scope -eq $script:SubScope })
        $limited | Should -HaveCount 1
        $limited[0].Condition | Should -Match 'acdd72a7-3385-48ef-bd42-f606fba81ae7, fbc52c3f-28ad-4303-a892-8a056630b8f1'
        $limited[0].Condition | Should -Match "ActionMatches\{'Microsoft.Authorization/roleAssignments/write'\}"
        $limited[0].Condition | Should -Match "ActionMatches\{'Microsoft.Authorization/roleAssignments/delete'\}"
        $limited[0].ConditionVersion | Should -Be '2.0'
        @($script:Writes | Where-Object { $_ -like 'NEW az role Role Based Access Control Administrator * limited' }) | Should -HaveCount 1
        Should -Invoke Set-AzRoleAssignment -Times 0
    }

    It 'keeps a limited assignment that already carries the condition' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Subscription role: Role Based Access Control Administrator (limited)' | Should -Be 'Already assigned'
        @($script:Writes | Where-Object { $_ -like '*az role*' }) | Should -HaveCount 0
    }

    It 'reports a Role Based Access Control Administrator held without the limit, and the post migration script applies the limit' {
        Add-CompliantPreWindowState
        foreach ($entry in $script:Tenant.AzRoleAssignments) {
            if ($entry.RoleDefinitionName -eq $script:LimitedSubRole -and $entry.Scope -eq $script:SubScope) { $entry.Remove('Condition'); $entry.Remove('ConditionVersion') }
        }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Subscription role: Role Based Access Control Administrator (limited)' | Should -Be 'Already assigned without the limit. The post migration script applies the limit'
        Should -Invoke Set-AzRoleAssignment -Times 0
        Should -Invoke New-AzRoleAssignment -Times 0
        $script:Writes = @()
        $script:Summary = @()
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Subscription role: Role Based Access Control Administrator (limited)' | Should -Be 'Limit applied'
        # Azure keeps the condition of an assignment on an update, so the post migration script removes
        # the assignment and creates it again with the limit; it never updates in place.
        Should -Invoke Set-AzRoleAssignment -Times 0
        Should -Invoke Remove-AzRoleAssignment -Times 1
        @($script:Writes | Where-Object { $_ -like 'REMOVE az role Role Based Access Control Administrator *' }) | Should -HaveCount 1
        @($script:Writes | Where-Object { $_ -like 'NEW az role Role Based Access Control Administrator * limited' }) | Should -HaveCount 1
        $limited = @($script:Tenant.AzRoleAssignments | Where-Object { $_.RoleDefinitionName -eq $script:LimitedSubRole -and $_.Scope -eq $script:SubScope })
        $limited | Should -HaveCount 1
        $limited[0].Condition | Should -Be $script:LimitedSubRoleCondition
        $limited[0].Condition | Should -Match 'fbc52c3f-28ad-4303-a892-8a056630b8f1'
    }

    It 'in the post migration script replaces a limited assignment that carries the two-role condition with the three-role condition' {
        Add-CompliantPreWindowState
        $twoRole = $script:LimitedSubRoleCondition -replace ', 72fafb9e-0641-4937-9268-a91bfd8191a3', ''
        $twoRole | Should -Not -Be $script:LimitedSubRoleCondition
        foreach ($entry in $script:Tenant.AzRoleAssignments) {
            if ($entry.RoleDefinitionName -eq $script:LimitedSubRole -and $entry.Scope -eq $script:SubScope) { $entry.Condition = $twoRole }
        }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Subscription role: Role Based Access Control Administrator (limited)' | Should -Be 'Limit applied'
        Should -Invoke Set-AzRoleAssignment -Times 0
        @($script:Writes | Where-Object { $_ -like 'REMOVE az role Role Based Access Control Administrator *' }) | Should -HaveCount 1
        @($script:Writes | Where-Object { $_ -like 'NEW az role Role Based Access Control Administrator * limited' }) | Should -HaveCount 1
        $limited = @($script:Tenant.AzRoleAssignments | Where-Object { $_.RoleDefinitionName -eq $script:LimitedSubRole -and $_.Scope -eq $script:SubScope })
        $limited | Should -HaveCount 1
        $limited[0].Condition | Should -Be $script:LimitedSubRoleCondition
    }

    It 'in the post migration script waits until Azure no longer shows the removed assignment before creating the limited one' {
        Add-CompliantPreWindowState
        foreach ($entry in $script:Tenant.AzRoleAssignments) {
            if ($entry.RoleDefinitionName -eq $script:LimitedSubRole -and $entry.Scope -eq $script:SubScope) { $entry.Remove('Condition'); $entry.Remove('ConditionVersion') }
        }
        $script:Tenant.StaleAzRoleReadsAfterRemoval = 3
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Subscription role: Role Based Access Control Administrator (limited)' | Should -Be 'Limit applied'
        @($script:Sleeps | Where-Object { $_ -eq 5 }) | Should -HaveCount 3
        $script:Tenant.StaleAzRoleReads | Should -Be 0
        @($script:Writes | Where-Object { $_ -like 'REMOVE az role Role Based Access Control Administrator *' }) | Should -HaveCount 1
        @($script:Writes | Where-Object { $_ -like 'NEW az role Role Based Access Control Administrator * limited' }) | Should -HaveCount 1
        $limited = @($script:Tenant.AzRoleAssignments | Where-Object { $_.RoleDefinitionName -eq $script:LimitedSubRole -and $_.Scope -eq $script:SubScope })
        $limited | Should -HaveCount 1
        $limited[0].Condition | Should -Be $script:LimitedSubRoleCondition
    }

    It 'in the post migration script tries the create again when Azure answers "already exists" for the removed assignment' {
        Add-CompliantPreWindowState
        foreach ($entry in $script:Tenant.AzRoleAssignments) {
            if ($entry.RoleDefinitionName -eq $script:LimitedSubRole -and $entry.Scope -eq $script:SubScope) { $entry.Remove('Condition'); $entry.Remove('ConditionVersion') }
        }
        $script:CreateRefusals = 2
        Mock New-AzRoleAssignment {
            param($ObjectId, $RoleDefinitionName, $RoleDefinitionId, $Scope, $Condition, $ConditionVersion)
            if ($script:CreateRefusals -gt 0) { $script:CreateRefusals--; throw 'RoleAssignmentExists: The role assignment already exists.' }
            $script:Tenant.AzRoleAssignments += @{ ObjectId = $ObjectId; RoleDefinitionName = $script:LimitedSubRole; Scope = $Scope; Condition = $Condition; ConditionVersion = $ConditionVersion }
            Add-Write "NEW az role $($script:LimitedSubRole) $Scope limited"
        }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Subscription role: Role Based Access Control Administrator (limited)' | Should -Be 'Limit applied'
        $script:CreateRefusals | Should -Be 0
        @($script:Sleeps | Where-Object { $_ -eq 10 }) | Should -HaveCount 2
        @($script:Writes | Where-Object { $_ -like 'NEW az role Role Based Access Control Administrator * limited' }) | Should -HaveCount 1
        $limited = @($script:Tenant.AzRoleAssignments | Where-Object { $_.RoleDefinitionName -eq $script:LimitedSubRole -and $_.Scope -eq $script:SubScope })
        $limited | Should -HaveCount 1
        $limited[0].Condition | Should -Be $script:LimitedSubRoleCondition
    }

    It 'in the post migration script with -Verify reports the limit as a pending change and removes nothing' {
        Add-CompliantPreWindowState
        foreach ($entry in $script:Tenant.AzRoleAssignments) {
            if ($entry.RoleDefinitionName -eq $script:LimitedSubRole -and $entry.Scope -eq $script:SubScope) { $entry.Remove('Condition'); $entry.Remove('ConditionVersion') }
        }
        $null = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile); Verify = $true }
        Get-SummaryResult 'Subscription role: Role Based Access Control Administrator (limited)' | Should -Be 'WOULD APPLY THE LIMIT'
        Should -Invoke Remove-AzRoleAssignment -Times 0
        Should -Invoke New-AzRoleAssignment -Times 0
        Should -Invoke Set-AzRoleAssignment -Times 0
    }

    It 'with -Verify reports the limited role as WOULD ASSIGN and writes nothing' {
        Add-CompliantPreWindowState
        $script:Tenant.AzRoleAssignments = @($script:Tenant.AzRoleAssignments | Where-Object { -not ($_.RoleDefinitionName -eq $script:LimitedSubRole -and $_.Scope -eq $script:SubScope) })
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); Verify = $true }
        Get-SummaryResult 'Subscription role: Role Based Access Control Administrator (limited)' | Should -Be 'WOULD ASSIGN'
        Should -Invoke New-AzRoleAssignment -Times 0
        Should -Invoke Set-AzRoleAssignment -Times 0
    }

    It 'stops with ACTION REQUIRED when the Azure sign-in fails, touching nothing' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        Mock Connect-AzAccount { throw 'Device code expired' }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'Owner or User Access Administrator on subscription'
        Get-SummaryResult 'Resource group role: Contributor' | Should -Be 'SKIPPED: the sign-in to Azure failed'
        Get-SummaryResult 'Application Administrator role' | Should -Be 'SKIPPED: the script did not confirm the Azure roles of the deployment identity'
        $script:Writes | Should -HaveCount 0
    }

    It 'stops when the Azure session selected another subscription' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        $script:AzContextSubscription = [guid]::NewGuid().ToString()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'selected subscription'
        $script:Writes | Should -HaveCount 0
    }

    It 'installs the Az modules when absent' {
        Add-CompliantPreWindowState
        Mock Get-NeologikAvailableModuleVersion { param($Name) if ($Name -like 'Az.*' -and $script:Installs -notcontains $Name) { @() } else { @([version]'5.5.0') } }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Installs | Should -Contain 'Az.Accounts'
        $script:Installs | Should -Contain 'Az.Resources'
    }

    It 'reports the directory role removal as failed when Graph refuses it' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        Mock Remove-MgDirectoryRoleMemberDirectoryObjectByRef { throw (New-ForbiddenException) }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Application Administrator role') | Should -Match '^FAILED: insufficient privileges'
        Get-SummaryResult 'Subscription role to remove: Contributor' | Should -Be 'Removed'
    }

    It 'reports the Application Administrator check as failed when the memberOf read fails, never as not held' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        Mock Get-MgServicePrincipalMemberOf { throw (New-ForbiddenException) }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Application Administrator role') | Should -Match '^FAILED'
        @($script:Tenant.DirectoryRoles | Where-Object { $_.Id -eq $script:Ids.AppAdminRole })[0].members | Should -Contain $script:Ids.DeploySpId
    }

    It 'finds the directory roles through the identity''s memberOf list, never through a role''s member list' {
        # The member list of a directory role omits service principals, so a role
        # the identity holds would read as not held through it.
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        Add-UndeclaredState
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Application Administrator role' | Should -Be 'Removed'
        Get-SummaryResult 'Other directory role: Agent ID Administrator' | Should -Be 'Removed'
        Should -Invoke Get-MgDirectoryRole -Times 0
        Should -Invoke Get-MgDirectoryRoleMember -Times 0
        @($script:Tenant.DirectoryRoles | Where-Object { $_.Id -eq $script:Ids.AppAdminRole })[0].members | Should -HaveCount 0
        @($script:Tenant.DirectoryRoles | Where-Object { $_.Id -eq $script:Ids.AgentIdAdminRole })[0].members | Should -HaveCount 0
    }

    It 'accepts explicit parameters instead of a configuration file' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId; SolutionShortName = $script:ShortName; SolutionName = $script:SolutionName; SignInAppClientId = $script:Ids.SignInAppId; NceUserGroupId = $script:Ids.Group; SubscriptionId = $script:Ids.Subscription; ResourceGroupName = $script:RgName }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
    }
}

Context 'Blueprint sponsor' {
    It 'adds the signed-in administrator when the blueprint has no sponsor, and writes nothing more on the next run' {
        Add-CompliantPreWindowState
        (Get-FakeApp -Id $script:Ids.BlueprintAppObj).sponsors = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Agent identity blueprint sponsor' | Should -Be 'Added: Contoso Administrator'
        @($script:Writes) | Should -Be @("POST blueprint sponsor $($script:Ids.Me)")
        (Get-FakeApp -Id $script:Ids.BlueprintAppObj).sponsors | Should -Be @($script:Ids.Me)
        $script:Writes = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        Get-SummaryResult 'Agent identity blueprint sponsor' | Should -Be 'Present: Contoso Administrator'
    }

    It 'reports WOULD ADD in a run with -Verify and writes nothing' {
        Add-CompliantPreWindowState
        (Get-FakeApp -Id $script:Ids.BlueprintAppObj).sponsors = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 1
        Get-SummaryResult 'Agent identity blueprint sponsor' | Should -Be 'WOULD ADD: the signed-in administrator'
        $script:Writes | Should -HaveCount 0
    }

    It 'names a sponsor that another administrator set, by id when the directory gives no name, and changes nothing' {
        Add-CompliantPreWindowState
        (Get-FakeApp -Id $script:Ids.BlueprintAppObj).sponsors = @('99999999-9999-9999-9999-999999999999')
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Agent identity blueprint sponsor' | Should -Be 'Present: 99999999-9999-9999-9999-999999999999'
        $script:Writes | Should -HaveCount 0
    }
}

Context 'Verify-only run (-Verify)' {
    It 'reports every pending change on a legacy environment, writes nothing and exits 1' {
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'Application.Read.All'
        Add-LegacyAzureState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 1
        $script:Writes | Should -HaveCount 0
        @($script:Tenant.Apps | Where-Object { $_.displayName -like 'Neologik Agent Blueprint*' }) | Should -HaveCount 0
        (Get-SummaryResult 'Agent identity blueprint') | Should -BeLike 'WOULD CREATE*'
        Get-SummaryResult 'Agent identity blueprint service principal' | Should -Be 'WOULD CREATE'
        Get-SummaryResult 'Agent identity blueprint service principal owner' | Should -Be 'WOULD ADD at creation'
        Get-SummaryResult 'Agent identity blueprint sponsor' | Should -Be 'WOULD SET at creation: the signed-in administrator'
        Get-SummaryResult 'Agent identity blueprint credential: github-oidc-neo-infrastructure' | Should -Be 'WOULD ADD'
        Get-SummaryResult 'Deployment identity permission: Application.ReadWrite.OwnedBy' | Should -Be 'WOULD GRANT'
        Get-SummaryResult 'Deployment identity permission to remove: Application.Read.All' | Should -BeNullOrEmpty -Because 'the pre migration script removes nothing (project#3170)'
        Get-SummaryResult 'User group assignment' | Should -Be 'WOULD ASSIGN'
        Get-SummaryResult 'Administrator consent' | Should -Be 'MISSING: the script printed the consent address'
        Get-SummaryResult 'Resource group role: Contributor' | Should -Be 'WOULD ASSIGN'
        Get-SummaryResult 'Subscription role: Cost Management Contributor' | Should -Be 'WOULD ASSIGN'
        Get-SummaryResult 'Subscription role to remove: Contributor' | Should -BeNullOrEmpty
        Get-SummaryResult 'Application Administrator role' | Should -BeNullOrEmpty
        @($script:Summary | Where-Object { $_.Result -match '^(FAILED|SKIPPED)' }) | Should -HaveCount 0
        ($script:Console -join "`n") | Should -Match 'with -Verify'
        ($script:Console -join "`n") | Should -Match 'The script wrote nothing'
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_PreWindow_*.json')
        $files | Should -HaveCount 1
        $json = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        $json.verifyOnly | Should -BeTrue
        $json.pendingChangeCount | Should -BeGreaterThan 10
        (Get-FakeSp -Id $script:Ids.DeploySpId).appRoleAssignments | Should -HaveCount 1
        @($script:Tenant.DirectoryRoles | Where-Object { $_.Id -eq $script:Ids.AppAdminRole })[0].members | Should -Contain $script:Ids.DeploySpId
        Should -Invoke Connect-MgGraph -Times 1
        Should -Invoke Connect-AzAccount -Times 1
    }

    It 'is a clean pass on a compliant environment: exit 0, nothing pending' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        ($script:Console -join "`n") | Should -Match 'would change nothing'
    }

    It 'reports every pending removal of the post migration script on a legacy environment, writes nothing and exits 1' {
        Add-CompliantDirectoryState
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'Application.Read.All'
        Add-LegacyAzureState
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 1
        $script:Writes | Should -HaveCount 0
        Get-SummaryResult 'Deployment identity permission to remove: Application.Read.All' | Should -Be 'WOULD REMOVE'
        Get-SummaryResult 'Resource group role: Contributor' | Should -Be 'WOULD ASSIGN'
        Get-SummaryResult 'Subscription role to remove: Contributor' | Should -Be 'WOULD REMOVE'
        Get-SummaryResult 'Application Administrator role' | Should -Be 'WOULD REMOVE'
        Get-SummaryResult 'Agent identity blueprint' | Should -BeNullOrEmpty -Because 'the post migration script makes none of the checks of the pre migration script'
        ($script:Console -join "`n") | Should -Match 'post migration script with -Verify'
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_PostWindow_*.json')
        $files | Should -HaveCount 1
        (Get-FakeSp -Id $script:Ids.DeploySpId).appRoleAssignments | Should -HaveCount 3
        @($script:Tenant.DirectoryRoles | Where-Object { $_.Id -eq $script:Ids.AppAdminRole })[0].members | Should -Contain $script:Ids.DeploySpId
    }

    It 'the write seams refuse every write in a verify-only run, whatever the caller does' {
        $script:State = @{ Verify = $true }
        { Invoke-NeologikGraph -Method POST -Uri "$script:GraphV1/oauth2PermissionGrants" -Body '{}' } | Should -Throw -ExpectedMessage '*The run with -Verify refused the write*'
        { Invoke-NeologikWrite -Command 'New-AzRoleAssignment' -Parameters @{ ObjectId = 'x'; RoleDefinitionName = 'Reader'; Scope = '/subscriptions/x' } } | Should -Throw -ExpectedMessage '*The run with -Verify refused the write*'
        $script:GraphCalls | Should -HaveCount 0
        $script:Writes | Should -HaveCount 0
        Should -Invoke New-AzRoleAssignment -Times 0
        # A read passes.
        $null = Invoke-NeologikGraph -Method GET -Uri "$script:GraphV1/me"
        $script:GraphCalls | Should -Contain 'GET /me'
        # Without -Verify the seam performs the write.
        $script:State = @{ Verify = $false }
        Invoke-NeologikWrite -Command 'New-AzRoleAssignment' -Parameters @{ ObjectId = 'x'; RoleDefinitionName = 'Reader'; Scope = '/subscriptions/x' }
        $script:Writes | Should -HaveCount 1
    }
}

Context 'Parameter surface' {
    It 'has no -Phase parameter and no grants file parameter: -LaterRun selects the run' {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors) | Should -HaveCount 0
        $names = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
        $names | Should -Not -Contain 'Phase'
        $names | Should -Contain 'Verify'
        $names | Should -Contain 'KitVersion'
        $names | Should -Contain 'LaterRun'
        $names | Should -Contain 'UserGroupId'
        # The grants are the work of Grant-NeologikAgentAccess.ps1 in the onboarding kit (project#3192).
        $names | Should -Not -Contain 'AgentGrantsFile'
        $names | Should -Not -Contain 'MailboxGrantsFile'
        $names | Should -Not -Contain 'RemoveLegacyGrantAppIds'
        { Invoke-NeologikEnvironmentMigration -ConfigurationFile (New-ConfigFile) -Phase 'PostWindow' } | Should -Throw -ExpectedMessage "*'Phase'*"
        Should -Invoke Connect-MgGraph -Times 0
    }
}

Context 'Summary and exit code' {
    It 'flags FAILED, UNKNOWN, MISSING, SKIPPED, PENDING, NOT FOUND and WOULD as attention' {
        foreach ($result in @('FAILED - x', 'UNKNOWN - x', 'MISSING - x', 'SKIPPED - x', 'PENDING - x', 'NOT FOUND - x', 'WOULD GRANT', 'WOULD REMOVE: 2 role assignment(s)')) {
            $result | Should -Match $script:AttentionPattern
        }
        foreach ($result in @('Present', 'Created', 'Already granted', 'Granted: User.Read', 'Removed', 'Not held', 'Not present', 'Not needed', 'Updated: a b',
                'Not checked. The post migration script with -AgentGrantsFile makes the check', 'Kept. An email channel still uses the identity')) {
            $result | Should -Not -Match $script:AttentionPattern
        }
    }

    It 'keeps going and writes the summary file when the summary roles cannot be read' {
        Add-CompliantPreWindowState
        Mock Get-NeologikHeldGraphRole { throw 'read failed' }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        ($script:Console -join "`n") | Should -Match 'could not read the permissions of the deployment identity for the summary'
        @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_PostWindow_*.json') | Should -HaveCount 1
    }
}

Context 'The pre migration script: security groups, guests and memberships (step 2, project#3127)' {
    BeforeAll {
        function Set-LegacyGroupState {
            # The directory of an environment set up before version 5, with everything else
            # compliant: the user group under its old name, no User Group, no NCE Admins
            # group, no Neologik guest, the administrator a member of the two old groups.
            $t = $script:Tenant
            $t.Groups = @($t.Groups | Where-Object { $_.id -notin @($script:Ids.UserGroup, $script:Ids.NceAdminsGroup) })
            $group = Get-FakeGroup -Id $script:Ids.Group
            $group.displayName = "Neologik NCE User Group - $script:ShortName"
            $group.members = @(@{ id = $script:Ids.Me })
            (Get-FakeGroup -Id $script:Ids.AdminGroup).members = @(@{ id = $script:Ids.Me })
            $t.Users = @()
        }
    }

    It 'creates the two missing groups, renames the user group, invites the guest and fills the memberships, then changes nothing on the next run' {
        Add-CompliantPreWindowState
        Set-LegacyGroupState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -Contain "POST group Neologik User Group - $script:ShortName"
        $script:Writes | Should -Contain "POST group Neologik NCE Admins - $script:ShortName"
        $script:Writes | Should -Contain "PATCH group Neologik NCE User Group - $script:ShortName displayName=Neologik NCE Contributors - $script:ShortName"
        $script:Writes | Should -Contain 'POST invitation support@neologik.ai'
        # The guest joins four groups; the administrator joins the two new ones.
        @($script:Writes | Where-Object { $_ -like 'POST group member *' }) | Should -HaveCount 6
        @($script:Writes | Where-Object { $_ -like "POST group member * $($script:Ids.Me)" }) | Should -HaveCount 2
        $admins = @($script:Tenant.Groups | Where-Object { $_.displayName -eq "Neologik NCE Admins - $script:ShortName" })
        $admins | Should -HaveCount 1
        $script:Writes | Should -Contain "NEW group assignment $($admins[0].id) $($script:Ids.SignInSpId)"
        (Get-SummaryResult 'Security groups') | Should -Be "Present: 1. Created: Neologik User Group - $script:ShortName, Neologik NCE Admins - $script:ShortName. Renamed: Neologik NCE Contributors - $script:ShortName"
        (Get-SummaryResult 'Neologik guest users') | Should -Be 'Invited: support@neologik.ai'
        (Get-SummaryResult 'Group memberships') | Should -BeLike 'Present: 2. Added: *'
        (Get-SummaryResult 'Signed-in administrator membership') | Should -Be 'Present in every group (4)'
        (Get-SummaryResult 'NCE Admins group') | Should -Be "Present, id $($admins[0].id). Neologik records this id for the environment"
        Get-SummaryResult 'User group assignment' | Should -Be 'Already assigned'
        Get-SummaryResult 'Admin group assignment' | Should -Be 'Assigned'
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_PreWindow_*.json')
        $json = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        $json.nceAdminsGroupId | Should -Be $admins[0].id
        $json.nceContributorsGroupId | Should -Be $script:Ids.Group

        $script:Writes = @()
        $script:Summary = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        (Get-SummaryResult 'Security groups') | Should -Be 'Present: 4'
        (Get-SummaryResult 'Neologik guest users') | Should -Be 'Present: 1'
        (Get-SummaryResult 'Group memberships') | Should -Be 'Present: 8'
    }

    It 'reports every pending change with -Verify and writes nothing' {
        Add-CompliantPreWindowState
        Set-LegacyGroupState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 1
        $script:Writes | Should -HaveCount 0
        (Get-SummaryResult 'Security groups') | Should -Be "Present: 1. Renamed: WOULD RENAME 'Neologik NCE User Group - $script:ShortName'. WOULD CREATE: Neologik User Group - $script:ShortName, Neologik NCE Admins - $script:ShortName"
        (Get-SummaryResult 'Neologik guest users') | Should -Be 'WOULD INVITE: support@neologik.ai'
        (Get-SummaryResult 'NCE Admins group') | Should -Be 'WOULD CREATE'
        @($script:Tenant.Groups) | Should -HaveCount 2
        # The closing count takes every item that reports a change, the step 2 items included,
        # where the word WOULD sits inside the line.
        $reporting = @($script:Summary | Where-Object { $_.Result -match '\bWOULD ' })
        @($reporting | ForEach-Object { $_.Item }) | Should -Be @('Security groups', 'NCE Admins group', 'Neologik guest users')
        ($script:Console -join "`n") | Should -Match 'would change 3 item\(s\)'
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_PreWindow_*.json')
        $json = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        $json.pendingChangeCount | Should -Be $reporting.Count
    }

    It 'adds the signed-in administrator who is also a listed guest once, and reports no failure' {
        Add-CompliantPreWindowState
        Set-LegacyGroupState
        # The rare case: the administrator who runs the script is a Neologik guest on the list.
        $script:Tenant.Users += @{ id = $script:Ids.Me; mail = 'admin@neologik.ai'; userPrincipalName = 'admin_neologik.ai#EXT#@contoso.onmicrosoft.com'; displayName = 'Admin'; userType = 'Guest' }
        $file = Join-Path $TestDrive 'guests-with-admin.txt'
        Set-Content -LiteralPath $file -Value "support@neologik.ai`nadmin@neologik.ai`n" -Encoding UTF8
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); GuestUsersFile = $file }
        $code | Should -Be 0
        # The administrator joins the two new groups once each; the other guest joins all four.
        @($script:Writes | Where-Object { $_ -like "POST group member * $($script:Ids.Me)" }) | Should -HaveCount 2
        @($script:Writes | Where-Object { $_ -like 'POST group member *' }) | Should -HaveCount 6
        (Get-SummaryResult 'Neologik guest users') | Should -Be 'Present: 1. Invited: support@neologik.ai'
        (Get-SummaryResult 'Group memberships') | Should -Not -Match 'FAILED'
        (Get-SummaryResult 'Group memberships') | Should -Match 'signed-in administrator to Neologik NCE Admins'
        (Get-SummaryResult 'Signed-in administrator membership') | Should -Be 'Present in every group (4)'
    }

    It 'finds the user group by its version 5 name when the command gives no group id' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile -Remove @('SecurityGroups')) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        Get-SummaryResult 'User group assignment' | Should -Be 'Already assigned'
        Get-SummaryResult 'Admin group assignment' | Should -Be 'Already assigned'
    }

    It 'finds the user group by the id in the command, gives the group the version 5 name and creates no second group (project#3787)' {
        # An environment set up before version 5 can hold the user group under an older
        # Neologik name, as sasdev holds 'Neologik User Group Neologik - sas-dev'.
        Add-CompliantPreWindowState
        (Get-FakeGroup -Id $script:Ids.UserGroup).displayName = 'Neologik User Group Neologik - x-dev'
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UserGroupId = $script:Ids.UserGroup }
        $code | Should -Be 0
        $script:Writes | Should -Contain "PATCH group Neologik User Group Neologik - x-dev displayName=Neologik User Group - $script:ShortName"
        $script:Writes | Should -Not -Contain "POST group Neologik User Group - $script:ShortName"
        @($script:Tenant.Groups | Where-Object { $_.displayName -like 'Neologik User Group*' }) | Should -HaveCount 1
        (Get-SummaryResult 'Security groups') | Should -Be "Present: 3. Renamed: Neologik User Group - $script:ShortName"
        ($script:Console -join "`n") | Should -Match ('Neologik User Group:\s+' + [regex]::Escape($script:Ids.UserGroup))
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_PreWindow_*.json')
        $json = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        $json.userGroupId | Should -Be $script:Ids.UserGroup
        $snapshots = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_Snapshot_Pre_*.json')
        $snapshot = Get-Content -LiteralPath $snapshots[0].FullName -Raw | ConvertFrom-Json
        @($snapshot.groups | Where-Object { $_.id -eq $script:Ids.UserGroup }) | Should -HaveCount 1

        $script:Writes = @()
        $script:Summary = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UserGroupId = $script:Ids.UserGroup }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        (Get-SummaryResult 'Security groups') | Should -Be 'Present: 4'
    }

    It 'reports the rename of the user group with -Verify and writes nothing (project#3787)' {
        Add-CompliantPreWindowState
        (Get-FakeGroup -Id $script:Ids.UserGroup).displayName = 'Neologik User Group Neologik - x-dev'
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UserGroupId = $script:Ids.UserGroup; Verify = $true }
        $code | Should -Be 1
        $script:Writes | Should -HaveCount 0
        (Get-SummaryResult 'Security groups') | Should -Be "Present: 3. Renamed: WOULD RENAME 'Neologik User Group Neologik - x-dev'"
    }

    It 'takes the id of the user group from the configuration file (project#3787)' {
        Add-CompliantPreWindowState
        (Get-FakeGroup -Id $script:Ids.UserGroup).displayName = 'Neologik User Group Neologik - x-dev'
        $securityGroups = @(
            @{ Name = 'Neologik User Group Neologik - x-dev'; Id = $script:Ids.UserGroup },
            @{ Name = "Neologik NCE User Group - $script:ShortName"; Id = $script:Ids.Group },
            @{ Name = "Neologik Admin User Group - $script:ShortName"; Id = $script:Ids.AdminGroup })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile -Overrides @{ SecurityGroups = $securityGroups }) }
        $code | Should -Be 0
        $script:Writes | Should -Contain "PATCH group Neologik User Group Neologik - x-dev displayName=Neologik User Group - $script:ShortName"
        $script:Writes | Should -Not -Contain "POST group Neologik User Group - $script:ShortName"
    }

    It 'leaves a user group with a name of the organisation''s own as it is and uses the Neologik User Group (project#3787)' {
        # The group of an earlier channel can be a group of the organisation's own, such
        # as All Staff. No Neologik guest may join that group.
        Add-CompliantPreWindowState
        $allStaff = Get-FakeGroup -Id $script:Ids.UserGroup
        $allStaff.displayName = 'All Staff'
        $allStaff.members = @(@{ id = $script:Ids.Me })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UserGroupId = $script:Ids.UserGroup }
        $code | Should -Be 0
        $allStaff.displayName | Should -Be 'All Staff'
        @($allStaff.members) | Should -HaveCount 1
        @($script:Writes | Where-Object { $_ -like 'PATCH group All Staff*' -or $_ -like 'POST group member All Staff *' }) | Should -HaveCount 0
        $script:Writes | Should -Contain "POST group Neologik User Group - $script:ShortName"
        (Get-SummaryResult 'Security groups') | Should -Be "Present: 3. Created: Neologik User Group - $script:ShortName. Not used, a name of the organisation's own: 'All Staff'"
        $created = @($script:Tenant.Groups | Where-Object { $_.displayName -eq "Neologik User Group - $script:ShortName" })
        $created | Should -HaveCount 1
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_PreWindow_*.json')
        $json = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        $json.userGroupId | Should -Be $created[0].id
    }

    It 'keeps the name of an Admin User Group that the command names by id when the name is not a Neologik name (project#3787)' {
        Add-CompliantPreWindowState
        (Get-FakeGroup -Id $script:Ids.AdminGroup).displayName = 'IT Administrators'
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AdminGroupId = $script:Ids.AdminGroup }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        (Get-FakeGroup -Id $script:Ids.AdminGroup).displayName | Should -Be 'IT Administrators'
        (Get-SummaryResult 'Security groups') | Should -Be "Present: 3. Kept the name: 'IT Administrators'"
    }

    It 'records the user group found by name in the summary file when the command gives no id (project#3787)' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_PreWindow_*.json')
        $json = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        $json.userGroupId | Should -Be $script:Ids.UserGroup
    }

    It 'reports the guest users file as skipped when the file is not beside the script' {
        Add-CompliantPreWindowState
        Mock Get-NeologikGuestUsersFileDefault { Join-Path $TestDrive 'not-there.txt' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Neologik guest users') | Should -BeLike 'SKIPPED: the guest users file is not found*'
        # The administrator's memberships are still confirmed.
        (Get-SummaryResult 'Signed-in administrator membership') | Should -Be 'Present in every group (4)'
        $script:Writes | Should -HaveCount 0
    }

    It 'refuses a -GuestUsersFile that does not exist before contacting anything' {
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); GuestUsersFile = (Join-Path $TestDrive 'nowhere.txt') }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The guest users file is not found'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'takes the guest list from -GuestUsersFile and ignores a comment line' {
        Add-CompliantPreWindowState
        $file = Join-Path $TestDrive 'guests.txt'
        Set-Content -LiteralPath $file -Value "# two accounts`nsupport@neologik.ai`n`nsecond@neologik.ai`n" -Encoding UTF8
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); GuestUsersFile = $file }
        $code | Should -Be 0
        $script:Writes | Should -Contain 'POST invitation second@neologik.ai'
        @($script:Writes | Where-Object { $_ -like 'POST group member *' }) | Should -HaveCount 4
        (Get-SummaryResult 'Neologik guest users') | Should -Be 'Present: 1. Invited: second@neologik.ai'
    }

    It 'requests the group and invitation scopes for the pre migration script' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $request = @($script:TokenRequests | Where-Object { $_.Uri -match '/devicecode$' }) | Select-Object -First 1
        @($request.Body.scope -split ' ') | Should -Contain 'Group.ReadWrite.All'
        @($request.Body.scope -split ' ') | Should -Contain 'User.Invite.All'
    }
}

Context 'The post migration script: Admin User Group membership' {
    BeforeEach {
        Add-CompliantDirectoryState
        Add-CompliantAzureState
    }

    It 'reports the membership as not held on a compliant environment' {
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Admin User Group membership' | Should -Be 'Not held'
        Should -Invoke Remove-MgGroupMemberByRef -Times 0
    }

    It 'keeps the membership while a SQL server still names the group as its administrator' {
        Add-AdminGroupMembership
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Admin User Group membership' | Should -Match '^HELD\. The script keeps the membership until each SQL server names the deployment identity'
        Should -Invoke Remove-MgGroupMemberByRef -Times 0
        @((Get-FakeGroup -Id $script:Ids.AdminGroup).members | ForEach-Object { $_.id }) | Should -Contain $script:Ids.DeploySpId
        ($script:Console -join "`n") | Should -Match 'The deployment by Neologik sets the administrator'
    }

    It 'removes the membership once every SQL server names the deployment identity as its administrator' {
        Add-AdminGroupMembership
        Set-SqlAdministrator -ObjectId $script:Ids.DeploySpId
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Admin User Group membership' | Should -Be 'Removed'
        Should -Invoke Remove-MgGroupMemberByRef -Times 1
        @((Get-FakeGroup -Id $script:Ids.AdminGroup).members | ForEach-Object { $_.id }) | Should -Not -Contain $script:Ids.DeploySpId
        $script:Writes | Should -Contain "REMOVE group member $($script:Ids.DeploySpId)"
        # the other members of the group are untouched
        @((Get-FakeGroup -Id $script:Ids.AdminGroup).members | ForEach-Object { $_.id }) | Should -Contain $script:Ids.Me
    }

    It 'finds the membership in the identity''s memberOf list when the group''s member list leaves out the identity' {
        # Graph's groups/{id}/members returned the users of the Admin User Group and
        # left out the deployment identity on a customer tenant (verified 2026-11-05).
        # The fake member list does the same, so a return to that read fails here.
        Mock Get-MgGroupMember {
            param($GroupId)
            $group = @($script:Tenant.Groups | Where-Object { $_.id -eq $GroupId }) | Select-Object -First 1
            @($group.members | Where-Object { $_.id -ne $script:Ids.DeploySpId } | ForEach-Object { [pscustomobject]@{ Id = $_.id } })
        }
        Add-AdminGroupMembership
        Set-SqlAdministrator -ObjectId $script:Ids.DeploySpId
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Admin User Group membership' | Should -Be 'Removed'
        @((Get-FakeGroup -Id $script:Ids.AdminGroup).members | ForEach-Object { $_.id }) | Should -Not -Contain $script:Ids.DeploySpId
        # The post migration script prints the title of each step without a step number.
        ($script:Console -join "`n") | Should -Not -Match 'Step \d+[a-z]? of \d+'
    }

    It 'keeps the membership when one of two servers still names the group' {
        Add-AdminGroupMembership
        $script:Tenant.SqlServers += @{ ServerName = 'sql-custom-01'; AdminObjectId = $script:Ids.AdminGroup; AdminDisplayName = 'SQL Administrators' }
        Set-SqlAdministrator -ObjectId $script:Ids.DeploySpId -ServerName "sql-main-$script:ShortName"
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Admin User Group membership' | Should -Match '^HELD'
        Should -Invoke Remove-MgGroupMemberByRef -Times 0
    }

    It 'keeps the membership when the resource group has no SQL server yet' {
        Add-AdminGroupMembership
        $script:Tenant.SqlServers = @()
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        Get-SummaryResult 'Admin User Group membership' | Should -Match '^HELD'
        Should -Invoke Remove-MgGroupMemberByRef -Times 0
    }

    It 'records the removal as a pending change in a verify-only run and writes nothing' {
        Add-AdminGroupMembership
        Set-SqlAdministrator -ObjectId $script:Ids.DeploySpId
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 1
        Get-SummaryResult 'Admin User Group membership' | Should -Be 'WOULD REMOVE'
        Should -Invoke Remove-MgGroupMemberByRef -Times 0
        $script:Writes | Should -HaveCount 0
    }

    It 'finds the Admin User Group by its name when the command gives no AdminGroupId' {
        $cfg = New-ConfigFile -Overrides @{ SecurityGroups = @(@{ Name = "Neologik NCE User Group - $script:ShortName"; Id = $script:Ids.Group }) }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = $cfg }
        $code | Should -Be 0
        # Step 2 names the group (project#3127), so the membership check runs.
        Get-SummaryResult 'Admin User Group membership' | Should -Be 'Not held'
        Should -Invoke Remove-MgGroupMemberByRef -Times 0
    }

    It 'reports not checked, without needing attention, when no Admin User Group exists and the command gives no AdminGroupId' {
        $cfg = New-ConfigFile -Overrides @{ SecurityGroups = @(@{ Name = "Neologik NCE User Group - $script:ShortName"; Id = $script:Ids.Group }) }
        $script:Tenant.Groups = @($script:Tenant.Groups | Where-Object { $_.id -ne $script:Ids.AdminGroup })
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = $cfg; Verify = $true }
        Get-SummaryResult 'Admin User Group membership' | Should -Be 'Not checked. The command gives no AdminGroupId'
        Should -Invoke Remove-MgGroupMemberByRef -Times 0
    }

    It 'takes the Admin User Group id as an explicit parameter' {
        Add-AdminGroupMembership
        Set-SqlAdministrator -ObjectId $script:Ids.DeploySpId
        $cfg = New-ConfigFile -Overrides @{ SecurityGroups = @(@{ Name = "Neologik NCE User Group - $script:ShortName"; Id = $script:Ids.Group }) }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = $cfg; AdminGroupId = $script:Ids.AdminGroup }
        $code | Should -Be 0
        Get-SummaryResult 'Admin User Group membership' | Should -Be 'Removed'
    }

    It 'imports the Az modules at their own versions, never a common pin' {
        Mock Get-NeologikAvailableModuleVersion { param($Name) switch -Wildcard ($Name) { 'Az.Accounts' { @([version]'5.5.3') } 'Az.Resources' { @([version]'10.0.0') } 'Az.Sql' { @([version]'7.1.0') } default { @([version]'2.38.0') } } }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        # Az.Storage is imported for the upload of the files of the run (project#3171).
        @($script:Imports | Where-Object { $_ -like 'Az.*' }) | Should -Be @('Az.Accounts ', 'Az.Resources ', 'Az.Sql ', 'Az.Storage ')
        Get-SummaryResult 'Resource group role: Contributor' | Should -Be 'Already assigned'
        Get-SummaryResult 'Admin User Group membership' | Should -Be 'Not held'
    }

    It 'requests the group-member and directory role scopes for the post migration script' {
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $request = @($script:TokenRequests | Where-Object { $_.Uri -match '/devicecode$' }) | Select-Object -First 1
        @($request.Body.scope -split ' ') | Should -Contain 'GroupMember.ReadWrite.All'
        @($request.Body.scope -split ' ') | Should -Contain 'RoleManagement.ReadWrite.Directory'
    }

    It 'reports a refused removal without touching anything else' {
        Add-AdminGroupMembership
        Set-SqlAdministrator -ObjectId $script:Ids.DeploySpId
        Mock Remove-MgGroupMemberByRef { throw (New-ForbiddenException) }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Admin User Group membership') | Should -Match '^FAILED: insufficient privileges'
        @((Get-FakeGroup -Id $script:Ids.AdminGroup).members | ForEach-Object { $_.id }) | Should -Contain $script:Ids.DeploySpId
    }
}

Context 'The post migration script: declared set or nothing' {
    BeforeEach {
        Add-CompliantDirectoryState
        Add-CompliantAzureState
    }

    It 'reports nothing undeclared on a compliant environment' {
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Other Azure roles' | Should -Be 'None'
        Get-SummaryResult 'Other directory roles' | Should -Be 'None'
        Get-SummaryResult 'Other group memberships' | Should -Be 'None'
        Should -Invoke Remove-AzRoleAssignment -Times 0
        Should -Invoke Remove-MgGroupMemberByRef -Times 0
    }

    It 'removes every undeclared Azure role, directory role and group membership and keeps the declared set' {
        Add-UndeclaredState
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        foreach ($item in @('Other Azure role: Azure AI Developer on resource group', 'Other Azure role: Foundry User on resource group',
                'Other Azure role: Reader on resource group', 'Other Azure role: Search Index Data Reader on resource group',
                'Other Azure role: Key Vault Secrets Officer on subscription', "Other Azure role: Search Index Data Reader on srch-$script:ShortName",
                'Other Azure role: Storage Blob Data Contributor on uploads',
                'Other directory role: Agent ID Administrator', 'Other group membership: Neologik Dev Team')) {
            Get-SummaryResult $item | Should -Be 'Removed' -Because "$item must go"
        }
        Get-SummaryResult 'Other Azure role: Cognitive Services Content Understanding Contributor on ais-cu-abcprd01' | Should -BeNullOrEmpty -Because 'the Content Understanding role is declared at resource scope'
        Get-SummaryResult 'Other Azure role: Storage Blob Data Contributor on function-package' | Should -BeNullOrEmpty -Because 'the role on the container function-package is declared'
        $left = @($script:Tenant.AzRoleAssignments | Where-Object { $_.ObjectId -eq $script:Ids.DeploySpId })
        @($left | Where-Object { $_.RoleDefinitionName -eq 'Cognitive Services Content Understanding Contributor' }) | Should -HaveCount 1
        @($left | Where-Object { $_.Scope -like '*/containers/function-package' }).RoleDefinitionName | Should -Be 'Storage Blob Data Contributor'
        @($left | Where-Object { $_.Scope -like '*/containers/uploads' }) | Should -HaveCount 0
        @($left | Where-Object { $_.RoleDefinitionName -in @('Azure AI Developer', 'Foundry User') }) | Should -HaveCount 0
        @($left | Where-Object { $_.Scope -eq $script:SubScope }).RoleDefinitionName | Sort-Object | Should -Be @('Cost Management Contributor', 'Reader', 'Role Based Access Control Administrator')
        @($left | Where-Object { $_.Scope -eq $script:RgScope }).RoleDefinitionName | Sort-Object | Should -Be @($script:RequiredRgRoles | Sort-Object)
        @($script:Tenant.DirectoryRoles | Where-Object { $_.Id -eq $script:Ids.AgentIdAdminRole })[0].members | Should -HaveCount 0
        @((Get-FakeGroup -Id $script:Ids.DevTeamGroup).members | ForEach-Object { $_.id }) | Should -Not -Contain $script:Ids.DeploySpId
        @((Get-FakeGroup -Id $script:Ids.DevTeamGroup).members | ForEach-Object { $_.id }) | Should -Contain $script:Ids.Me
    }

    It 'reports every undeclared item as a pending removal in a verify-only run and writes nothing' {
        Add-UndeclaredState
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 1
        Get-SummaryResult 'Other Azure role: Foundry User on resource group' | Should -Be 'WOULD REMOVE'
        Get-SummaryResult 'Other Azure role: Storage Blob Data Contributor on function-package' | Should -BeNullOrEmpty -Because 'the role on the container function-package is declared'
        Get-SummaryResult 'Other directory role: Agent ID Administrator' | Should -Be 'WOULD REMOVE'
        Get-SummaryResult 'Other group membership: Neologik Dev Team' | Should -Be 'WOULD REMOVE'
        $script:Writes | Should -HaveCount 0
    }

    It 'keeps the role that the infrastructure deployment grants on the container function-package' {
        $script:Tenant.AzRoleAssignments += @{ ObjectId = $script:Ids.DeploySpId; RoleDefinitionName = 'Storage Blob Data Contributor'; Scope = "$script:RgScope/providers/Microsoft.Storage/storageAccounts/stfn$script:ShortName/blobServices/default/containers/function-package" }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 0
        Get-SummaryResult 'Other Azure roles' | Should -Be 'None'
        $script:Writes | Should -HaveCount 0
    }

    It 'leaves everything undeclared in place while the narrow set is incomplete' {
        Add-UndeclaredState
        Mock New-AzRoleAssignment { param($RoleDefinitionName) if ($RoleDefinitionName -eq 'Monitoring Contributor') { throw 'AuthorizationFailed: The client does not have authorization to perform action' }; $script:Tenant.AzRoleAssignments += @{ ObjectId = $ObjectId; RoleDefinitionName = $RoleDefinitionName; Scope = $Scope }; Add-Write "NEW az role $RoleDefinitionName $Scope" }
        $script:Tenant.AzRoleAssignments = @($script:Tenant.AzRoleAssignments | Where-Object { $_.RoleDefinitionName -ne 'Monitoring Contributor' })
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Other Azure roles' | Should -Be 'SKIPPED: the deployment identity does not hold all ten Azure roles'
        Get-SummaryResult 'Other directory roles' | Should -Be 'SKIPPED: the deployment identity does not hold all ten Azure roles'
        Get-SummaryResult 'Other group memberships' | Should -Be 'SKIPPED: the deployment identity does not hold all ten Azure roles'
        Should -Invoke Remove-AzRoleAssignment -Times 0
        Should -Invoke Remove-MgGroupMemberByRef -Times 0
        @((Get-FakeGroup -Id $script:Ids.DevTeamGroup).members | ForEach-Object { $_.id }) | Should -Contain $script:Ids.DeploySpId
    }

    It 'reports a refused group removal and continues' {
        Add-UndeclaredState
        Mock Remove-MgGroupMemberByRef { throw (New-ForbiddenException) }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Other group memberships') | Should -Match '^FAILED: insufficient privileges'
        Get-SummaryResult 'Other directory role: Agent ID Administrator' | Should -Be 'Removed'
    }
}

Context 'The pre migration script removes nothing (project#3170)' {
    It 'keeps every wider grant on a legacy environment and assigns the ten roles' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        Add-UndeclaredState
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'Application.Read.All'
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        @($script:Writes | Where-Object { $_ -like 'REMOVE*' }) | Should -HaveCount 0
        @($script:Writes | Where-Object { $_ -like 'NEW az role*' }) | Should -HaveCount 10
        @($script:Summary | Where-Object { $_.Item -match 'to remove|Application Administrator role|Admin User Group membership|^Other ' }) | Should -HaveCount 0
        @($script:Tenant.DirectoryRoles | Where-Object { $_.Id -eq $script:Ids.AppAdminRole })[0].members | Should -Contain $script:Ids.DeploySpId
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.Scope -eq $script:SubScope -and $_.RoleDefinitionName -eq 'Contributor' }) | Should -HaveCount 1
        @((Get-FakeSp -Id $script:Ids.DeploySpId).appRoleAssignments | ForEach-Object { $_.AppRoleId }) | Should -Contain $script:AppRoleIds['Application.Read.All']
        @((Get-FakeGroup -Id $script:Ids.DevTeamGroup).members | ForEach-Object { $_.id }) | Should -Contain $script:Ids.DeploySpId
        Get-SummaryResult 'Onboarding kit version tag' | Should -Be "Set: $script:KitVersion"
        ($script:Console -join "`n") | Should -Match 'The pre migration script removes nothing'
        Should -Invoke Remove-AzRoleAssignment -Times 0
        Should -Invoke Remove-MgDirectoryRoleMemberDirectoryObjectByRef -Times 0
        Should -Invoke Remove-MgServicePrincipalAppRoleAssignment -Times 0
        Should -Invoke Remove-MgGroupMemberByRef -Times 0
    }

    It 'then the post migration script removes exactly that wider access' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'Application.Read.All'
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $script:Writes = @()
        $script:Summary = @()
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Deployment identity permission to remove: Application.Read.All' | Should -Be 'Removed'
        Get-SummaryResult 'Subscription role to remove: Contributor' | Should -Be 'Removed'
        Get-SummaryResult 'Application Administrator role' | Should -Be 'Removed'
        Get-SummaryResult 'Admin User Group membership' | Should -Match '^HELD'
        Get-SummaryResult 'Onboarding kit version tag' | Should -Be "Already set: $script:KitVersion"
        @($script:Writes | Where-Object { $_ -like 'NEW az role*' }) | Should -HaveCount 0
        ($script:Console -join "`n") | Should -Match 'The post migration script is complete'
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_PostWindow_*.json')
        $files | Should -HaveCount 1
    }

    It 'in the post migration script removes the role assignments on the resource group whose identity no longer exists, and only those' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        $gone = [guid]::NewGuid().ToString()
        $goneAtSubscription = [guid]::NewGuid().ToString()
        # An assignment whose identity Azure cannot resolve but the directory still holds:
        # the Dev Team group's id stands in for such an identity.
        $unresolvedButPresent = $script:Ids.DevTeamGroup
        $script:Tenant.Groups += @{ id = $script:Ids.DevTeamGroup; displayName = 'Neologik Dev Team'; members = @(); appRoleAssignments = @() }
        $script:Tenant.AzRoleAssignments += @{ ObjectId = $gone; ObjectType = 'Unknown'; RoleDefinitionName = 'Contributor'; Scope = $script:RgScope }
        $script:Tenant.AzRoleAssignments += @{ ObjectId = $gone; ObjectType = 'Unknown'; RoleDefinitionName = 'Key Vault Secrets User'; Scope = $script:RgScope }
        $script:Tenant.AzRoleAssignments += @{ ObjectId = $goneAtSubscription; ObjectType = 'Unknown'; RoleDefinitionName = 'Reader'; Scope = $script:SubScope }
        $script:Tenant.AzRoleAssignments += @{ ObjectId = $unresolvedButPresent; ObjectType = 'Unknown'; RoleDefinitionName = 'Reader'; Scope = $script:RgScope }
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        # The pre migration script removes nothing.
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.ObjectId -eq $gone }) | Should -HaveCount 2
        $script:Writes = @()
        $script:Summary = @()
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult "Orphaned role assignment: Contributor for identity $gone" | Should -Be 'Removed'
        Get-SummaryResult "Orphaned role assignment: Key Vault Secrets User for identity $gone" | Should -Be 'Removed'
        Get-SummaryResult "Orphaned role assignment: Reader for identity $unresolvedButPresent" | Should -Match '^Review'
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.ObjectId -eq $gone }) | Should -HaveCount 0
        # Inherited from the subscription: never touched by the post migration script's resource-group sweep.
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.ObjectId -eq $goneAtSubscription }) | Should -HaveCount 1
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.ObjectId -eq $unresolvedButPresent }) | Should -HaveCount 1
        Get-SummaryResult 'Onboarding kit version tag' | Should -Be "Already set: $script:KitVersion"
    }

    It 'reports the orphaned role assignments as pending in a run with -Verify and removes nothing' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        $gone = [guid]::NewGuid().ToString()
        $script:Tenant.AzRoleAssignments += @{ ObjectId = $gone; ObjectType = 'Unknown'; RoleDefinitionName = 'Contributor'; Scope = $script:RgScope }
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $null = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $script:Writes = @()
        $script:Tenant.AzRoleAssignments += @{ ObjectId = $gone; ObjectType = 'Unknown'; RoleDefinitionName = 'Contributor'; Scope = $script:RgScope }
        $code = Invoke-Run @{ LaterRun = $true; Verify = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        @($script:Writes | Where-Object { $_ -like 'REMOVE az role*' }) | Should -HaveCount 0
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.ObjectId -eq $gone }) | Should -HaveCount 1
    }

    It 'needs SubscriptionId and ResourceGroupName for the post migration script with -LaterRun' {
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile -Remove @('SubscriptionId')) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The post migration script with -LaterRun needs SubscriptionId'
        Should -Invoke Connect-MgGraph -Times 0
    }

}

Context 'Log file and summary file on every exit (project#3170)' {
    It 'writes the log file and the summary file when an input is wrong, before contacting anything' {
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile -Remove @('TenantId')) }
        $code | Should -Be 1
        Should -Invoke Connect-MgGraph -Times 0
        $logs = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'NeologikEnvironmentMigration_*.log')
        $logs | Should -HaveCount 1
        $log = Get-Content -LiteralPath $logs[0].FullName -Raw
        $log | Should -Match "onboarding kit $([regex]::Escape($script:KitVersion))"
        $log | Should -Match '\[Error\] .*TenantId'
        $log | Should -Match '\[ActionRequired\]'
        $log | Should -Match '\[Summary\] Run: FAILED: an input is wrong'
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_*.json')
        $files | Should -HaveCount 1
        $json = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        $json.exitReason | Should -Match '^an input is wrong'
        $json.logFile | Should -Be $logs[0].FullName
        $json.kitVersion | Should -Be $script:KitVersion
        $json.attentionCount | Should -Be 1
    }

    It 'writes the summary file and the log file when the sign-in to Microsoft Graph fails' {
        Mock Connect-MgGraph { throw 'AADSTS50076: multi-factor authentication is required' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_PreWindow_*.json')
        $files | Should -HaveCount 1
        $json = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        $json.exitReason | Should -Match 'sign-in to Microsoft Graph did not complete'
        $log = Get-Content -LiteralPath $json.logFile -Raw
        $log | Should -Match 'AADSTS50076'
        $log | Should -Match 'Neologik environment migration: pre migration script'
    }

    It 'records a failed Microsoft Graph request with its status and request id in the log file' {
        Add-CompliantPreWindowState
        $script:Faults += @{ Match = 'GET /applications$'; Status = 403; Code = 'Authorization_RequestDenied'; Message = 'Insufficient privileges'; Remaining = 1; Headers = @{ 'request-id' = @('req-0001') } }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        $logs = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'NeologikEnvironmentMigration_*.log')
        $logs | Should -HaveCount 1
        $log = Get-Content -LiteralPath $logs[0].FullName -Raw
        $log | Should -Match '\[Graph\] GET .*/applications.* returned HTTP 403\. request-id req-0001\. .*Authorization_RequestDenied: Insufficient privileges'
        $log | Should -Match 'The agent identity blueprint'
        $log | Should -Match 'SUMMARY'
        $log | Should -Match '\[Summary\] Agent identity blueprint: FAILED'
    }

    It 'continues without a log file when no folder accepts one' {
        Mock Get-NeologikSummaryDirectory { @((Join-Path $TestDrive 'does-not-exist')) }
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1 -Because 'the snapshot file could not be written either, which needs attention'
        ($script:Console -join "`n") | Should -Match 'could not create the log file'
        ($script:Console -join "`n") | Should -Match 'could not write the summary file to any folder'
        Get-SummaryResult 'Snapshot file' | Should -Match '^SKIPPED'
    }
}

Context 'Step 5a: the Azure quotas that the migration needs' {
    It 'reports the Flex Consumption plan, the vCPU room and no model to move when everything is in place' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Region: Flex Consumption plan' | Should -Be 'Present: uksouth'
        # Each pool may add 6 nodes plus 1 for the upgrade: (6 + 1) * 2 vCPUs * 2 pools = 28.
        Get-SummaryResult 'Quota: vCPUs of StandardDasv7Family' | Should -Be 'Present: 18 of 350 used in uksouth. The cluster may need 28 more'
        Get-SummaryResult 'Quota: vCPUs of the region' | Should -Be 'Present: 18 of 50 used in uksouth. The cluster may need 28 more'
        Get-SummaryResult 'Model deployments on Foundry' | Should -Match '^Present: gpt-5.4-mini \(GlobalStandard 1000\), text-embedding-3-large \(Standard 150\)$'
        Get-SummaryResult 'Model deployments to move to Foundry' | Should -Be 'None'
        # Reads only: the Flex Consumption regions, the cluster, its pools, the compute usage, the sizes, the accounts, their deployments.
        @($script:ArmReads | Where-Object { $_ -match 'Microsoft\.Web/geoRegions\?' }) | Should -HaveCount 1
        @($script:ArmReads | Where-Object { $_ -match 'Microsoft\.Quota/quotas' }) | Should -HaveCount 0
        @($script:ArmReads | Where-Object { $_ -match '/agentPools\?' }) | Should -HaveCount 1
        Should -Invoke Invoke-AzRestMethod -Times 0 -ParameterFilter { $Method -ne 'GET' }
        ($script:Console -join "`n") | Should -Match 'The Azure quotas that the migration needs'
        # The run prints the title of each step without a step number.
        ($script:Console -join "`n") | Should -Not -Match 'Step \d+[a-z]? of \d+'
    }

    It 'reports SHORT and needs attention when the region has no Flex Consumption plan' {
        Add-CompliantPreWindowState
        $script:Tenant.Quota.FlexRegions = @('Sweden Central')
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Region: Flex Consumption plan' | Should -Be 'SHORT: uksouth has no Flex Consumption plan. The start and stop schedule of the cluster runs as a Function App on that plan. Tell Neologik to run the cluster without the schedule'
        ($script:Console -join "`n") | Should -Match 'Region: Flex Consumption plan: not available in uksouth\. The start and stop schedule of the cluster needs the plan'
    }

    It 'reports SHORT when the cluster growth does not fit the regional vCPU quota' {
        Add-CompliantPreWindowState
        $script:Tenant.Quota.ComputeUsage = @(@{ Name = 'StandardDasv7Family'; Current = 18; Limit = 350 }, @{ Name = 'cores'; Current = 30; Limit = 50 })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Quota: vCPUs of the region' | Should -Be 'SHORT: 30 of 50 used in uksouth. The cluster may need 28 more and 20 are free. Ask Microsoft for the quota before the migration'
        Get-SummaryResult 'Quota: vCPUs of StandardDasv7Family' | Should -Match '^Present'
    }

    It 'names each model the Foundry account lacks and whether its regional quota fits the move' {
        Add-CompliantPreWindowState
        $script:Tenant.Quota.AiAccounts[1].Deployments = @(@{ Model = 'gpt-5.4'; Sku = 'GlobalStandard'; Capacity = 100 })
        $script:Tenant.Quota.ModelUsage = @(@{ Name = 'OpenAI.GlobalStandard.gpt-5.4-mini'; Current = 2500; Limit = 3000 }, @{ Name = 'OpenAI.Standard.text-embedding-3-large'; Current = 150; Limit = 350 })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Model deployments on Foundry' | Should -Be 'Present: gpt-5.4 (GlobalStandard 100)'
        Get-SummaryResult 'Model to move to Foundry: gpt-5.4-mini (GlobalStandard 1000)' | Should -Match "^SHORT: 500 of 3000 free in uksouth and the deployment needs 1000\. Remove the deployment on oai-$script:ShortName first"
        Get-SummaryResult 'Model to move to Foundry: text-embedding-3-large (Standard 150)' | Should -Be 'Fits: 200 of 350 free in uksouth'
    }

    It 'reports Review and continues when Azure refuses a quota read' {
        Add-CompliantPreWindowState
        Mock Invoke-AzRestMethod { param($Method, $Path) if ($Path -match "userAssignedIdentities/$script:SqlIdentityName") { return [pscustomobject]@{ StatusCode = 200; Content = (@{ properties = $script:Tenant.SqlIdentity } | ConvertTo-Json -Depth 5) } }; if ($Path -match 'userAssignedIdentities') { return [pscustomobject]@{ StatusCode = 200; Content = (@{ properties = $script:Tenant.DirectoryIdentity } | ConvertTo-Json -Depth 5) } }; if ($Path -match 'Microsoft\.Web/geoRegions\?') { return [pscustomobject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"The client does not have authorization"}}' } }; if ($Path -match '/providers/Microsoft\.Features/') { return [pscustomobject]@{ StatusCode = 200; Content = '{"properties":{"state":"Registered"}}' } }; if ($Path -match '^/subscriptions/[^/]+/providers/[^/?]+\?api-version=') { return [pscustomobject]@{ StatusCode = 200; Content = '{"registrationState":"Registered"}' } }; if ($Path -match 'Microsoft\.KeyVault/vaults/') { return [pscustomobject]@{ StatusCode = 200; Content = '{"properties":{"enableRbacAuthorization":true}}' } }; [pscustomobject]@{ StatusCode = 200; Content = '{"value":[]}' } }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Region: Flex Consumption plan' | Should -Match '^Review: the regions could not be read\. .*HTTP 403\. The client does not have authorization'
        Get-SummaryResult 'Quota: vCPUs' | Should -Be 'Review: the resource group holds no Kubernetes cluster'
        Get-SummaryResult 'Model deployments on Foundry' | Should -Match '^Review: the resource group holds no Foundry account'
    }

    It 'checks no quota in the post migration script' {
        Add-CompliantPreWindowState
        $null = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        # The kit standard reads the managed identities, the providers, the Key Vault and the storage account in both runs (project#3848); the quota paths stay out of the post run.
        Should -Invoke Invoke-AzRestMethod -Times 0 -ParameterFilter { $Path -notmatch 'userAssignedIdentities|/providers/Microsoft\.Features/|^/subscriptions/[^/]+/providers/[^/?]+\?api-version=|Microsoft\.KeyVault/vaults|Microsoft\.Storage/storageAccounts' }
    }
}

Context 'Steps 4c and 5b: the federated credential and the directory managed identity' {
    It 'creates the managed identity, grants the permission, adds the owners and adds the credential on a run that finds none' {
        Add-CompliantPreWindowState
        $script:Tenant.DirectoryIdentity = $null
        $script:Tenant.ServicePrincipals = @($script:Tenant.ServicePrincipals | Where-Object { $_.id -ne $script:Ids.DirectorySpId })
        (Get-FakeApp -Id $script:Ids.DeployAppObj).credentials = @()
        $botAppId = 'f0000000-0000-0000-0000-000000000001'
        $botApp = New-FakeApp -Id 'f0000000-0000-0000-0000-000000000002' -AppId $botAppId -DisplayName 'Bot registration'
        $botApp.owners = @($script:Ids.DeploySpId)
        $script:Tenant.Apps += $botApp
        $botSp = New-FakeSp -Id 'f0000000-0000-0000-0000-000000000003' -AppId $botAppId -DisplayName 'Bot registration'
        $botSp.owners = @($script:Ids.DeploySpId)
        $script:Tenant.ServicePrincipals += $botSp

        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); BotAppClientIds = @($botAppId) }

        $code | Should -Be 0
        Get-SummaryResult 'Directory managed identity' | Should -Be "Created: $script:DirectoryIdentityName"
        Get-SummaryResult 'Directory managed identity permission: Application.ReadWrite.OwnedBy' | Should -Be 'Granted'
        Get-SummaryResult "Deployment identity credential: $script:DeploymentCredentialName" | Should -Be 'Added'
        (Get-FakeApp -Id $botApp.id).owners | Should -Contain $script:Ids.DirectorySpId
        (Get-FakeSp -Id $botSp.id).owners | Should -Contain $script:Ids.DirectorySpId
        (Get-FakeApp -Id $script:Ids.DeployAppObj).credentials | Should -Contain $script:DeploymentCredentialName
        (Get-FakeSp -Id $script:Ids.DirectorySpId).appRoleAssignments.AppRoleId | Should -Contain $script:AppRoleIds['Application.ReadWrite.OwnedBy']
    }

    It 'grants the managed identity no Azure role' {
        Add-CompliantPreWindowState
        $script:Tenant.DirectoryIdentity = $null
        $script:Tenant.ServicePrincipals = @($script:Tenant.ServicePrincipals | Where-Object { $_.id -ne $script:Ids.DirectorySpId })
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.ObjectId -eq $script:Ids.DirectorySpId }) | Should -HaveCount 0
    }

    It 'creates the managed identity in the location of the resource group with the tags of the resource group, leaving out the kit version tag' {
        Add-CompliantPreWindowState
        $script:Tenant.DirectoryIdentity = $null
        $script:Tenant.ServicePrincipals = @($script:Tenant.ServicePrincipals | Where-Object { $_.id -ne $script:Ids.DirectorySpId })
        $script:Tenant.ResourceGroupTags = @{ NeologikOnboardingKit = $script:KitVersion; CostCentre = '42' }
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $payload = $script:DirectoryIdentityPayload | ConvertFrom-Json -AsHashtable
        $payload.location | Should -Be 'uksouth'
        $payload.tags.CostCentre | Should -Be '42'
        $payload.tags.ContainsKey('NeologikOnboardingKit') | Should -BeFalse
    }

    It 'changes nothing on a second run' {
        Add-CompliantPreWindowState
        $script:Writes = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Directory managed identity' | Should -Be "Present: $script:DirectoryIdentityName"
        Get-SummaryResult "Deployment identity credential: $script:DeploymentCredentialName" | Should -Be 'Present'
        $script:Writes | Should -HaveCount 0
    }

    It 'accepts only a run that names the environment, on either subject format, from the Neologik organisation' {
        Add-CompliantPreWindowState
        (Get-FakeApp -Id $script:Ids.DeployAppObj).credentials = @()
        Mock Invoke-NeologikGraphRaw -ParameterFilter { $Method -eq 'POST' -and $Uri -match '/federatedIdentityCredentials$' } {
            param($Method, $Uri, $Body)
            $script:CredentialBody = $Body | ConvertFrom-Json -AsHashtable
            return @{ StatusCode = 201; Headers = @{}; Body = @{ name = 'x' } }
        }
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $script:CredentialBody.claimsMatchingExpression.value | Should -Be "claims['sub'] matches 'repo:Neologik-AI*:environment:$script:EnvironmentName' and claims['repository_owner_id'] eq '109681438'"
        $script:CredentialBody.issuer | Should -Be 'https://token.actions.githubusercontent.com'
    }

    It 'reports each change and writes nothing with -Verify' {
        Add-CompliantPreWindowState
        $script:Tenant.DirectoryIdentity = $null
        (Get-FakeApp -Id $script:Ids.DeployAppObj).credentials = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 1
        Get-SummaryResult 'Directory managed identity' | Should -Match '^WOULD CREATE'
        Get-SummaryResult "Deployment identity credential: $script:DeploymentCredentialName" | Should -Match '^WOULD ADD'
        $script:Writes | Should -HaveCount 0
    }

    It 'records no kit version tag, and needs attention, when the managed identity cannot be created' {
        Add-CompliantPreWindowState
        $script:Tenant.DirectoryIdentity = $null
        $script:Tenant.DirectoryIdentityCreateStatus = 403
        $script:Tenant.ResourceGroupTags = @{}
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Directory managed identity' | Should -Match 'FAILED: The signed-in account cannot create a managed identity.*Owner'
        Get-SummaryResult 'Onboarding kit version tag' | Should -Match '^SKIPPED'
        $script:Tenant.ResourceGroupTags.ContainsKey('NeologikOnboardingKit') | Should -BeFalse
    }

    It 'makes both items in the post migration script, for a customer who has only that run left' {
        Add-CompliantPreWindowState
        $script:Tenant.DirectoryIdentity = $null
        $script:Tenant.ServicePrincipals = @($script:Tenant.ServicePrincipals | Where-Object { $_.id -ne $script:Ids.DirectorySpId })
        (Get-FakeApp -Id $script:Ids.DeployAppObj).credentials = @()
        $script:Tenant.ResourceGroupTags = @{}
        $null = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        Get-SummaryResult 'Directory managed identity' | Should -Be "Created: $script:DirectoryIdentityName"
        Get-SummaryResult 'Directory managed identity permission: Application.ReadWrite.OwnedBy' | Should -Be 'Granted'
        Get-SummaryResult "Deployment identity credential: $script:DeploymentCredentialName" | Should -Be 'Added'
        Get-SummaryResult 'Onboarding kit version tag' | Should -Be "Set: $script:KitVersion"
    }

    It 'leaves the roles of the managed identity alone in the post migration script' {
        Add-CompliantPreWindowState
        $script:Tenant.AzRoleAssignments += @{ ObjectId = $script:Ids.DirectorySpId; RoleDefinitionName = 'Reader'; Scope = $script:RgScope }
        $null = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.ObjectId -eq $script:Ids.DirectorySpId }) | Should -HaveCount 1
    }

    It 'refuses a command without each new value, and contacts nothing' {
        $code = Invoke-NeologikEnvironmentMigration -KitVersion $script:KitVersion -ConfigurationFile (New-ConfigFile) -EnvironmentName $script:EnvironmentName
        @($code)[-1] | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'does not give DirectoryIdentityName'
        $script:Console = @()
        $code = Invoke-NeologikEnvironmentMigration -KitVersion $script:KitVersion -ConfigurationFile (New-ConfigFile) -DirectoryIdentityName $script:DirectoryIdentityName
        @($code)[-1] | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'does not give EnvironmentName'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'refuses a malformed value' {
        $code = Invoke-NeologikEnvironmentMigration -KitVersion $script:KitVersion -ConfigurationFile (New-ConfigFile) -DirectoryIdentityName 'bad name' -EnvironmentName $script:EnvironmentName
        @($code)[-1] | Should -Be 1
        $script:Console = @()
        $code = Invoke-NeologikEnvironmentMigration -KitVersion $script:KitVersion -ConfigurationFile (New-ConfigFile) -DirectoryIdentityName $script:DirectoryIdentityName -EnvironmentName "abc'prd"
        @($code)[-1] | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'EnvironmentName must be'
        Should -Invoke Connect-MgGraph -Times 0
    }
}

Context 'Snapshot, upload and the file list (project#3171)' {
    BeforeAll {
        function Get-SnapshotFile {
            param([string]$Label)
            $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter "Neologik_EnvironmentMigration_Snapshot_${Label}_*.json")
            $files | Should -HaveCount 1
            return (Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json)
        }
    }

    It 'the pre migration script writes the Pre snapshot and lists the three files' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Snapshot file' | Should -BeLike 'Written: Neologik_EnvironmentMigration_Snapshot_Pre_*'
        $snapshot = Get-SnapshotFile -Label 'Pre'
        $snapshot.label | Should -Be 'Pre'
        $snapshot.run | Should -Be 'PreWindow'
        $snapshot.kitVersion | Should -Be $script:KitVersion
        $snapshot.scriptVersion | Should -Be $script:ScriptVersion
        $snapshot.deploymentIdentity.graphRoles | Should -Contain 'Application.ReadWrite.OwnedBy'
        @($snapshot.deploymentIdentity.azureRoleAssignments | Where-Object { $_.role -eq 'Reader' }) | Should -HaveCount 1
        $signIn = @($snapshot.applications | Where-Object { $_.appId -eq $script:Ids.SignInAppId })
        $signIn | Should -HaveCount 1
        $signIn[0].present | Should -BeTrue
        $signIn[0].servicePrincipal.present | Should -BeTrue
        @($snapshot.groups).Count | Should -BeGreaterOrEqual 3
        @($snapshot.groups | Where-Object { $_.id -eq $script:Ids.AdminGroup })[0].memberCount | Should -Be 2
        @($snapshot.summaryItems).Count | Should -BeGreaterThan 10
        ($snapshot | ConvertTo-Json -Depth 8) | Should -Not -Match 'secretText'
        $text = $script:Console -join "`n"
        $text | Should -Match 'FILES TO SEND TO NEOLOGIK'
        $text | Should -Match 'NeologikEnvironmentMigration_\d+_\d+\.log'
        $text | Should -Match 'Neologik_EnvironmentMigration_PreWindow_'
        $text | Should -Match 'Neologik_EnvironmentMigration_Snapshot_Pre_'
        $script:Uploads | Should -HaveCount 0
    }

    It 'the post migration script writes the Post snapshot' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $snapshot = Get-SnapshotFile -Label 'Post'
        $snapshot.run | Should -Be 'PostWindow'
        @($snapshot.azure.sqlServers).Count | Should -BeGreaterOrEqual 1
    }

    It 'uploads the three files to the storage account and lists the blobs' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UploadStorageAccountName = 'sttemplateabcprd01' }
        $code | Should -Be 0
        $script:Uploads | Should -HaveCount 3
        $script:Uploads | Should -Contain ('onboarding-access/' + (Split-Path -Leaf (Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_Snapshot_Pre_*.json')[0].FullName))
        $script:Writes | Should -Contain 'NEW container onboarding-access'
        @($script:Writes | Where-Object { $_ -like 'NEW az role Storage Blob Data Contributor*' }) | Should -HaveCount 0
        $text = $script:Console -join "`n"
        $text | Should -Match 'Uploaded to the storage account'
        $text | Should -Match 'sttemplateabcprd01/onboarding-access/NeologikEnvironmentMigration_'
    }

    It 'uploads with a token for Azure Storage from the same sign-in, so the session opened from access tokens needs none of its own' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UploadStorageAccountName = 'sttemplateabcprd01' }
        $code | Should -Be 0
        # One refresh token exchange for the storage scope, with the client of the Azure sign-in.
        $refresh = @($script:TokenRequests | Where-Object { $_.Uri -match '/token$' -and $_.Body.grant_type -eq 'refresh_token' -and $_.Body.scope -match 'storage\.azure\.com' })
        $refresh | Should -HaveCount 1
        $refresh[0].Body.client_id | Should -Be '1950a258-227b-4e31-a9cf-717495945fc2'
        $refresh[0].Body.refresh_token | Should -Be 'rt-1'
        # Three blobs put with that token, the container created first; Az.Storage not used.
        @($script:BlobRequests | Where-Object { $_.Method -eq 'PUT' -and $_.Uri -notlike '*restype=container' -and $_.InFile }) | Should -HaveCount 3
        @($script:BlobRequests | Where-Object { $_.Token -ne 'eyJ0b2tlbg' }) | Should -HaveCount 0
        $script:Uploads | Should -HaveCount 3
        Should -Invoke New-AzStorageContext -Times 0
        Should -Invoke Set-AzStorageBlobContent -Times 0
        ($script:Console -join "`n") | Should -Match 'The sign-in also gave the token for Azure Storage'
        ($script:Console -join "`n") | Should -Not -Match 'eyJ0b2tlbg'
    }

    It 'assigns Storage Blob Data Contributor to the administrator and retries when the upload is refused' {
        Add-CompliantPreWindowState
        $script:UploadRefusals = 1
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UploadStorageAccountName = 'sttemplateabcprd01' }
        $code | Should -Be 0
        $script:Uploads | Should -HaveCount 3
        $role = @($script:Writes | Where-Object { $_ -like 'NEW az role Storage Blob Data Contributor*' })
        $role | Should -HaveCount 1
        $role[0] | Should -Be "NEW az role Storage Blob Data Contributor /subscriptions/$($script:Ids.Subscription)/resourceGroups/$script:RgName/providers/Microsoft.Storage/storageAccounts/sttemplateabcprd01"
        $script:Sleeps | Should -Contain 20
        ($script:Console -join "`n") | Should -Match 'assigns Storage Blob Data Contributor'
    }

    It 'uploads to the storage account of the onboarding first, into its logs and json containers' {
        Add-CompliantPreWindowState
        $cfg = New-ConfigFile -Overrides @{ StorageAccount = @{ Name = 'stneodeployabcprduks01'; JsonContainerName = 'json'; LogsContainerName = 'logs' } }
        $code = Invoke-Run @{ ConfigurationFile = $cfg; UploadStorageAccountName = 'sttemplateabcprd01' }
        $code | Should -Be 0
        $script:Uploads | Should -HaveCount 3
        @($script:Uploads | Where-Object { $_ -like 'logs/NeologikEnvironmentMigration_*.log' }) | Should -HaveCount 1
        @($script:Uploads | Where-Object { $_ -like 'json/Neologik_EnvironmentMigration_*.json' }) | Should -HaveCount 2
        ($script:Console -join "`n") | Should -Match 'stneodeployabcprduks01 \(onboarding\)'
        ($script:Console -join "`n") | Should -Not -Match 'sttemplateabcprd01 \(named\)'
        Should -Invoke Get-AzStorageAccount -Times 0 -Because 'the configuration file names the storage account'
    }

    It 'finds the storage account of the onboarding in the resource group when the command gives no configuration file' {
        Add-CompliantPreWindowState
        $script:StorageAccounts = @('stfilesneoabcprd01', 'stneodeployabcprduks01', 'sttemplateabcprd01')
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId; SolutionShortName = $script:ShortName; SolutionName = $script:SolutionName; SignInAppClientId = $script:Ids.SignInAppId; NceUserGroupId = $script:Ids.Group; SubscriptionId = $script:Ids.Subscription; ResourceGroupName = $script:RgName; UploadStorageAccountName = 'sttemplateabcprd01' }
        $code | Should -Be 0
        $script:Uploads | Should -HaveCount 3
        ($script:Console -join "`n") | Should -Match 'stneodeployabcprduks01 \(onboarding\)'
        @($script:Uploads | Where-Object { $_ -like 'json/*' }) | Should -HaveCount 2
    }

    It 'falls back to the named storage account when the storage account of the onboarding cannot be reached' {
        Add-CompliantPreWindowState
        $script:StorageAccounts = @('stneodeployabcprduks01')
        $script:UnreachableAccounts = @('stneodeployabcprduks01')
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UploadStorageAccountName = 'sttemplateabcprd01' }
        $code | Should -Be 0
        $script:Uploads | Should -HaveCount 3
        @($script:Uploads | Where-Object { $_ -like 'onboarding-access/*' }) | Should -HaveCount 3
        $text = $script:Console -join "`n"
        $text | Should -Match 'could not upload the files to stneodeployabcprduks01'
        $text | Should -Match 'sttemplateabcprd01 \(named\)'
    }

    It 'leaves the files listed when the storage account cannot be reached, without changing the exit code' {
        Add-CompliantPreWindowState
        # The blob service of the storage account does not answer, as behind a private endpoint.
        $script:UnreachableAccounts = @('sttemplateabcprd01')
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UploadStorageAccountName = 'sttemplateabcprd01' }
        $code | Should -Be 0
        $script:Uploads | Should -HaveCount 0
        $text = $script:Console -join "`n"
        $text | Should -Match 'could not upload the files to sttemplateabcprd01'
        $text | Should -Match 'private endpoint'
        $text | Should -Match 'FILES TO SEND TO NEOLOGIK'
        $text | Should -Not -Match 'Uploaded to the storage account'
    }

    It 'does not upload in a verify-only run' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UploadStorageAccountName = 'sttemplateabcprd01'; Verify = $true }
        $code | Should -Be 0
        $script:Uploads | Should -HaveCount 0
        ($script:Console -join "`n") | Should -Match '-Verify: the script does not upload'
    }

    It 'refuses a storage account name that is not one, before contacting anything' {
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UploadStorageAccountName = 'Not A Storage Account' }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'UploadStorageAccountName must be the name of a storage account'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'lists the log file and the summary file after an early exit' {
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile -Remove @('TenantId')) }
        $code | Should -Be 1
        $text = $script:Console -join "`n"
        $text | Should -Match 'FILES TO SEND TO NEOLOGIK'
        $text | Should -Match 'NeologikEnvironmentMigration_\d+_\d+\.log'
        $text | Should -Match 'Neologik_EnvironmentMigration_PreWindow_'
        $text | Should -Not -Match 'Snapshot_'
    }
}


Context 'Helpers: a Microsoft Graph PowerShell dictionary (project#3847)' {
    It 'reads a generic dictionary, such as AdditionalProperties of a Microsoft Graph PowerShell object' {
        $extra = [System.Collections.Generic.Dictionary[string, object]]::new()
        $extra['@odata.type'] = '#microsoft.graph.directoryRole'
        $extra['displayName'] = 'Directory Readers'
        Get-NeologikProperty $extra '@odata.type' | Should -Be '#microsoft.graph.directoryRole'
        Get-NeologikProperty $extra 'missing' 'dflt' | Should -Be 'dflt'
        Test-NeologikProperty $extra 'displayName' | Should -BeTrue
        Test-NeologikProperty $extra 'missing' | Should -BeFalse
    }

    It 'records the memberships in the snapshot instead of an error' {
        Add-CompliantPreWindowState
        Add-AdminGroupMembership
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentMigration_Snapshot_Pre_*.json')
        $snapshot = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        $snapshot.deploymentIdentity.memberOf | Should -Not -BeNullOrEmpty
        ($snapshot.deploymentIdentity.memberOf | ConvertTo-Json) | Should -Not -Match 'Cannot find an overload'
        @($snapshot.deploymentIdentity.memberOf | Where-Object { $_.displayName -like 'Neologik Admin User Group*' }) | Should -HaveCount 1
    }
}

Context 'The kit standard in both runs: the SQL managed identity, the providers, the Key Vault and the storage account (project#3848)' {
    It 'changes nothing on an environment that already stands as the onboarding kit leaves it' {
        Add-CompliantPreWindowState
        $script:StorageAccounts = @('stneodeployabcprduks01')
        $script:StorageContainers = @('certificate', 'json', 'logs')
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        Get-SummaryResult 'SQL managed identity' | Should -Be "Present: $script:SqlIdentityName"
        Get-SummaryResult 'SQL managed identity directory role: Directory Readers' | Should -Be 'Already held'
        Get-SummaryResult 'Resource providers and preview features' | Should -Match '^Already registered: 34 resource providers and 2 preview features$'
        Get-SummaryResult 'Key Vault access model: Azure role-based access control' | Should -Be 'Already on'
        Get-SummaryResult 'Deployment storage account stneodeployabcprduks01 shared key access: off' | Should -Be 'Already set'
        Get-SummaryResult 'Deployment storage account stneodeployabcprduks01 minimum TLS version: 1.2' | Should -Be 'Already set'
        Get-SummaryResult 'Deployment storage account stneodeployabcprduks01 container: logs' | Should -Be 'Present'
        Get-SummaryResult 'Onboarding kit version tag' | Should -Be "Already set: $script:KitVersion"
    }

    It 'assigns Directory Readers to the SQL managed identity, activating the role when the tenant has never used it' {
        Add-CompliantPreWindowState
        $script:Tenant.DirectoryRoles = @($script:Tenant.DirectoryRoles | Where-Object { $_.RoleTemplateId -ne $script:DirectoryReadersTemplateId })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -Contain "POST directory role $script:DirectoryReadersTemplateId"
        @($script:Writes | Where-Object { $_ -like "POST directory role member * $($script:Ids.SqlSpId)" }) | Should -HaveCount 1
        Get-SummaryResult 'SQL managed identity directory role: Directory Readers' | Should -Be 'Assigned'
        $role = @($script:Tenant.DirectoryRoles | Where-Object { $_.RoleTemplateId -eq $script:DirectoryReadersTemplateId })[0]
        $role.members | Should -Contain $script:Ids.SqlSpId
    }

    It 'assigns the role to an existing role object without activating the role again' {
        Add-CompliantPreWindowState
        $role = @($script:Tenant.DirectoryRoles | Where-Object { $_.RoleTemplateId -eq $script:DirectoryReadersTemplateId })[0]
        $role.members = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        @($script:Writes | Where-Object { $_ -like 'POST directory role 8*' }) | Should -HaveCount 0
        $script:Writes | Should -Contain "POST directory role member $script:DirectoryReadersRoleId $($script:Ids.SqlSpId)"
    }

    It 'reports a missing SQL managed identity and holds the kit version tag' {
        Add-CompliantPreWindowState
        $script:Tenant.SqlIdentity = $null
        $script:Tenant.ResourceGroupTags = @{ NeologikOnboardingKit = 'v5.0.10' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'SQL managed identity') | Should -Match '^MISSING: the managed identity'
        (Get-SummaryResult 'Onboarding kit version tag') | Should -Match '^SKIPPED'
        $script:Tenant.ResourceGroupTags['NeologikOnboardingKit'] | Should -Be 'v5.0.10'
    }

    It 'registers the resource providers and preview features that the subscription lacks and waits for them' {
        Add-CompliantPreWindowState
        $script:Tenant.ProviderStates['Microsoft.VideoIndexer'] = 'NotRegistered'
        $script:Tenant.ProviderStates['Microsoft.ServiceNetworking'] = 'NotRegistered'
        $script:Tenant.FeatureStates['Microsoft.ContainerService/AzureLinuxCVMPreview'] = 'NotRegistered'
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -Contain 'REGISTER provider Microsoft.VideoIndexer'
        $script:Writes | Should -Contain 'REGISTER provider Microsoft.ServiceNetworking'
        $script:Writes | Should -Contain 'REGISTER feature Microsoft.ContainerService/AzureLinuxCVMPreview'
        Get-SummaryResult 'Resource provider: Microsoft.VideoIndexer' | Should -Be 'Registered'
        Get-SummaryResult 'Preview feature: Microsoft.ContainerService/AzureLinuxCVMPreview' | Should -Be 'Registered'
        Get-SummaryResult 'Resource provider: Microsoft.Storage' | Should -BeNullOrEmpty
        # The script waited for the registrations, reading the state between the reads.
        @($script:Sleeps | Where-Object { $_ -eq $script:ProviderPollSeconds }).Count | Should -BeGreaterOrEqual 1
    }

    It 'reports a registration that Azure has not finished as pending and holds the kit version tag' {
        Add-CompliantPreWindowState
        $script:Tenant.ProviderStates['Microsoft.VideoIndexer'] = 'NotRegistered'
        $script:Tenant.SlowRegistration = $true
        $script:Tenant.ResourceGroupTags = @{ NeologikOnboardingKit = 'v5.0.10' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Resource provider: Microsoft.VideoIndexer') | Should -Match '^PENDING: the registration is in progress'
        @($script:Sleeps | Where-Object { $_ -eq $script:ProviderPollSeconds }).Count | Should -Be $script:ProviderRegistrationPolls
        (Get-SummaryResult 'Onboarding kit version tag') | Should -Match '^SKIPPED'
    }

    It 'turns on Azure role-based access control on a Key Vault that uses access policies' {
        Add-CompliantPreWindowState
        $script:Tenant.KeyVaultRbac = $false
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -Contain "PATCH vault $script:KeyVaultName enableRbacAuthorization=True"
        Get-SummaryResult 'Key Vault access model: Azure role-based access control' | Should -Be 'Set'
        $script:Tenant.KeyVaultRbac | Should -BeTrue
    }

    It 'brings the deployment storage account to the settings and containers of the onboarding kit' {
        Add-CompliantPreWindowState
        $script:StorageAccounts = @('stneodeployabcprduks01')
        $script:StorageContainers = @('certificate')
        $script:Tenant.StorageSettings = @{ allowSharedKeyAccess = $true; allowBlobPublicAccess = $false; minimumTlsVersion = 'TLS1_0' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -Contain 'PATCH storage stneodeployabcprduks01 allowSharedKeyAccess=False minimumTlsVersion=TLS1_2'
        $script:Writes | Should -Contain 'PUT container json'
        $script:Writes | Should -Contain 'PUT container logs'
        $script:Writes | Should -Not -Contain 'PUT container certificate'
        Get-SummaryResult 'Deployment storage account stneodeployabcprduks01 shared key access: off' | Should -Be 'Set'
        Get-SummaryResult 'Deployment storage account stneodeployabcprduks01 public blob access: off' | Should -Be 'Already set'
        Get-SummaryResult 'Deployment storage account stneodeployabcprduks01 minimum TLS version: 1.2' | Should -Be 'Set'
        Get-SummaryResult 'Deployment storage account stneodeployabcprduks01 container: json' | Should -Be 'Created'
        Get-SummaryResult 'Deployment storage account stneodeployabcprduks01 container: certificate' | Should -Be 'Present'
        $script:Tenant.StorageSettings.minimumTlsVersion | Should -Be 'TLS1_2'
    }

    It 'checks no storage account when the resource group holds no deployment storage account' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Deployment storage account' | Should -Match '^Not checked: no storage account named stneodeploy'
    }

    It 'with -Verify reports every pending item of the kit standard and writes nothing' {
        Add-CompliantPreWindowState
        $script:Tenant.SqlIdentity = @{ principalId = $script:Ids.SqlSpId; clientId = $script:Ids.SqlAppId }
        $role = @($script:Tenant.DirectoryRoles | Where-Object { $_.RoleTemplateId -eq $script:DirectoryReadersTemplateId })[0]
        $role.members = @()
        $script:Tenant.ProviderStates['Microsoft.VideoIndexer'] = 'NotRegistered'
        $script:Tenant.KeyVaultRbac = $false
        $script:StorageAccounts = @('stneodeployabcprduks01')
        $script:Tenant.StorageSettings = @{ allowSharedKeyAccess = $true; allowBlobPublicAccess = $true; minimumTlsVersion = 'TLS1_2' }
        $script:Tenant.ResourceGroupTags = @{ NeologikOnboardingKit = 'v5.0.10' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 1
        $script:Writes | Should -HaveCount 0
        Get-SummaryResult 'SQL managed identity directory role: Directory Readers' | Should -Be 'WOULD ASSIGN'
        Get-SummaryResult 'Resource provider: Microsoft.VideoIndexer' | Should -Be 'WOULD REGISTER'
        Get-SummaryResult 'Key Vault access model: Azure role-based access control' | Should -Be 'WOULD SET'
        Get-SummaryResult 'Deployment storage account stneodeployabcprduks01 shared key access: off' | Should -Be 'WOULD SET'
        Get-SummaryResult 'Deployment storage account stneodeployabcprduks01 container: json' | Should -Be 'WOULD CREATE'
        (Get-SummaryResult 'Onboarding kit version tag') | Should -Match '^WOULD SET'
    }

    It 'the post migration script confirms the same items' {
        Add-CompliantPreWindowState
        $script:Tenant.ProviderStates['Microsoft.VideoIndexer'] = 'NotRegistered'
        $role = @($script:Tenant.DirectoryRoles | Where-Object { $_.RoleTemplateId -eq $script:DirectoryReadersTemplateId })[0]
        $role.members = @()
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -Contain 'REGISTER provider Microsoft.VideoIndexer'
        Get-SummaryResult 'SQL managed identity directory role: Directory Readers' | Should -Be 'Assigned'
        Get-SummaryResult 'Resource provider: Microsoft.VideoIndexer' | Should -Be 'Registered'
        Get-SummaryResult 'Key Vault access model: Azure role-based access control' | Should -Be 'Already on'
    }

    It 'skips the items of the kit standard with the rest when the sign-in to Azure fails' {
        Add-CompliantPreWindowState
        Mock Connect-AzAccount { throw 'AADSTS50076: multi-factor authentication required' }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'SQL managed identity') | Should -Match '^SKIPPED'
        (Get-SummaryResult 'Resource providers and preview features') | Should -Match '^SKIPPED'
        (Get-SummaryResult 'Admin User Group other roles') | Should -Match '^SKIPPED'
    }

    It 'refuses a command without the SQL managed identity name or the Key Vault name before any sign-in' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); SqlIdentityName = '' }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The command does not give SqlIdentityName'
        Should -Invoke Connect-MgGraph -Times 0
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); KeyVaultName = 'Not A Vault' }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'KeyVaultName must be the name of a Key Vault'
        Should -Invoke Connect-MgGraph -Times 0
    }

}

Context 'The post migration script: the Admin User Group roles (step 6j, project#3848)' {
    It 'brings the Admin User Group to the thirteen roles of the onboarding kit and removes the rest in the subscription' {
        Add-CompliantPreWindowState
        Set-LegacyAdminGroupState
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -Contain "NEW az role Contributor $script:RgScope"
        $script:Writes | Should -Contain "NEW az role Azure Kubernetes Service Cluster Admin Role $script:RgScope"
        $script:Writes | Should -Contain "NEW az role Key Vault Certificates Officer $script:RgScope"
        $script:Writes | Should -Contain "REMOVE az role Contributor $script:SubScope"
        $script:Writes | Should -Contain "REMOVE az role Cost Management Contributor $script:SubScope"
        $script:Writes | Should -Contain "REMOVE az role Monitoring Contributor $script:SubScope"
        $script:Writes | Should -Contain "REMOVE az role AzureML Data Scientist $script:RgScope"
        $script:Writes | Should -Contain "REMOVE az role Cosmos DB Account Reader Role $script:RgScope"
        $script:Writes | Should -Contain "REMOVE az role Search Service Contributor $script:RgScope"
        $script:Writes | Should -Contain "REMOVE az role Storage Blob Data Reader $script:RgScope/providers/Microsoft.Storage/storageAccounts/stfilesabcprd01"
        Get-SummaryResult 'Admin User Group resource group role: Contributor' | Should -Be 'Assigned'
        Get-SummaryResult 'Admin User Group resource group role: Key Vault Administrator' | Should -Be 'Already assigned'
        Get-SummaryResult 'Admin User Group other role: Contributor on subscription' | Should -Be 'Removed'
        Get-SummaryResult 'Admin User Group other role: Storage Blob Data Reader on stfilesabcprd01' | Should -Be 'Removed'
        Get-AdminGroupRoles $script:SubScope | Should -HaveCount 0
        Get-AdminGroupRoles $script:RgScope | Should -Be @($script:AdminGroupRequiredRgRoles | Sort-Object)
        # The deployment identity's own roles are untouched by the step.
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.ObjectId -eq $script:Ids.DeploySpId }) | Should -HaveCount 10
    }

    It 'changes nothing for an Admin User Group that already holds exactly the thirteen roles' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        Get-SummaryResult 'Admin User Group resource group role: Azure AI Developer' | Should -Be 'Already assigned'
        Get-SummaryResult 'Admin User Group other roles' | Should -Be 'None'
    }

    It 'lists a role outside the subscription for review and removes nothing there' {
        Add-CompliantPreWindowState
        $script:Tenant.AzRoleAssignments += @{ ObjectId = $script:Ids.AdminGroup; RoleDefinitionName = 'Reader'; Scope = '/subscriptions/99999999-0000-0000-0000-000000000000' }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        (Get-SummaryResult 'Admin User Group role outside the subscription: Reader on subscription') | Should -Match '^Review'
        Get-SummaryResult 'Admin User Group other roles' | Should -Be 'None'
    }

    It 'removes no role when one of the thirteen roles could not be assigned' {
        Add-CompliantPreWindowState
        Set-LegacyAdminGroupState
        Mock New-AzRoleAssignment { param($ObjectId, $RoleDefinitionName, $Scope) if ($ObjectId -eq $script:Ids.AdminGroup -and $RoleDefinitionName -eq 'Key Vault Certificates Officer') { throw 'AuthorizationFailed: The client does not have authorization' }; $script:Tenant.AzRoleAssignments += @{ ObjectId = $ObjectId; RoleDefinitionName = $RoleDefinitionName; Scope = $Scope }; Add-Write "NEW az role $RoleDefinitionName $Scope" }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Admin User Group resource group role: Key Vault Certificates Officer') | Should -Match '^FAILED: insufficient privileges'
        Get-SummaryResult 'Admin User Group other roles' | Should -Be 'SKIPPED: the Admin User Group does not hold all thirteen roles on the resource group'
        Get-AdminGroupRoles $script:SubScope | Should -Be @('Contributor', 'Cost Management Contributor', 'Monitoring Contributor')
        (Get-SummaryResult 'Onboarding kit version tag') | Should -Match '^SKIPPED'
    }

    It 'with -Verify reports the additions and the removals as pending and writes nothing' {
        Add-CompliantPreWindowState
        Set-LegacyAdminGroupState
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 1
        $script:Writes | Should -HaveCount 0
        Get-SummaryResult 'Admin User Group resource group role: Contributor' | Should -Be 'WOULD ASSIGN'
        Get-SummaryResult 'Admin User Group other role: Contributor on subscription' | Should -Be 'WOULD REMOVE'
        Get-SummaryResult 'Admin User Group other role: AzureML Data Scientist on resource group' | Should -Be 'WOULD REMOVE'
    }

    It 'skips the Admin User Group rows with the rest when the deployment identity lacks a role' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        Set-LegacyAdminGroupState
        Mock New-AzRoleAssignment { param($RoleDefinitionName) if ($RoleDefinitionName -eq 'Monitoring Contributor') { throw 'AuthorizationFailed: The client does not have authorization' }; Add-Write "NEW az role $RoleDefinitionName $Scope" }
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Admin User Group other roles' | Should -Be 'SKIPPED: the deployment identity does not hold all ten Azure roles'
        Get-AdminGroupRoles $script:SubScope | Should -Be @('Contributor', 'Cost Management Contributor', 'Monitoring Contributor')
    }

    It 'confirms Key Vault Secrets Officer for the script runner identity beside Reader' {
        Add-CompliantPreWindowState
        Add-LegacyScriptRunnerState
        $script:Tenant.AzRoleAssignments = @($script:Tenant.AzRoleAssignments | Where-Object { -not ($_.ObjectId -eq $script:Ids.ScriptRunnerId -and $_.RoleDefinitionName -eq 'Key Vault Secrets Officer') })
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile); ScriptRunnerObjectId = $script:Ids.ScriptRunnerId }
        $code | Should -Be 0
        $script:Writes | Should -Contain "NEW az role Key Vault Secrets Officer $script:RgScope"
        Get-SummaryResult 'Script runner identity resource group role: Key Vault Secrets Officer' | Should -Be 'Assigned'
        Get-ScriptRunnerRoles $script:RgScope | Should -Be @('Azure Bot Service Contributor Role', 'Key Vault Secrets Officer', 'Reader')
    }

    It 'leaves the Admin User Group alone when neither the command nor the directory names the group' {
        Add-CompliantPreWindowState
        Set-LegacyAdminGroupState
        # The post migration script finds the group by its standard name when the command gives no id (step 6d); a group with a name of the customer's own is not found.
        $adminGroup = @($script:Tenant.Groups | Where-Object { $_.id -eq $script:Ids.AdminGroup })[0]
        $adminGroup.displayName = 'Platform Administrators'
        $code = Invoke-Run @{ LaterRun = $true; ConfigurationFile = (New-ConfigFile -Overrides @{ SecurityGroups = @(@{ Name = "Neologik NCE User Group - $script:ShortName"; Id = $script:Ids.Group }) }) }
        @($script:Writes | Where-Object { $_ -like "* $script:SubScope" -and $_ -like 'REMOVE*Monitoring Contributor*' }) | Should -HaveCount 0
        Get-SummaryResult 'Admin User Group roles' | Should -Be 'Not checked: the command does not name the Admin User Group'
        Get-AdminGroupRoles $script:SubScope | Should -Be @('Contributor', 'Cost Management Contributor', 'Monitoring Contributor')
    }
}

}
