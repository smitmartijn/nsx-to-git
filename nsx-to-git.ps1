# NSX Config to Git
#
# This script uses cmdlets from PowerNSX to gather configuration from NSX,
# dump that into XML files (formatted as the NSX API output) and commit those
# XML files to a git repository.
#
# When using this in a scheduled task, the Git repository will build up a handy
# history of configuration changes within NSX.
#
# Martijn Smit
# msmit@vmware.com
# Version 1.0


#Requires -Version 3.0
#Requires -Modules PowerNSX


param (
    [Parameter (Mandatory=$false)]
        # PowerNSX Connection object
        [pscustomobject]$Connection = $DefaultNsxConnection,
    [Parameter (Mandatory=$true)]
        # Path to Git binary
        [string]$GitBinary = "/usr/bin/git",
    [Parameter (Mandatory=$false)]
        $GitRepoPath = "$($PSScriptRoot)/output"
)


if ((-not $Connection) -and (-not $Connection.ViConnection.IsConnected)) {
    throw "No valid NSX Connection found. Connect to NSX and vCenter using Connect-NsxServer first. You can specify a non-default PowerNSX connection using the -Connection parameter."
}

Set-StrictMode -Off

# Check if the git command exists
if(!(Test-Path $GitBinary))
{
    throw "$($GitBinary) does not exist!"
}

# Create output directory if it does not exist yet

if(!(Test-Path $GitRepoPath))
{
    $output = New-Item -ItemType Directory -Force -Path $GitRepoPath 2>&1
}

# Check if the output directory is a git repository
$GitCheck = & "$($GitBinary)" -C "$($GitRepoPath)" status 2>&1

# Fail if it is not a git repo
if($GitCheck -like "*Not a git repository*") 
{
    Write-Host -ForegroundColor red "Your local Git repository is not yet initialised!"
    Write-Host "Please configure the directory 'output/' to be a Git repository. "
    Write-Host "You have 2 options: use a remote repository or keep it local. Remote is the norm."
    Write-Host "To initialise a remote repository, do the following:`n"
    Write-Host " cd output && "
    Write-Host " git init && "
    Write-Host " git remote add origin https://url.to.your.git/repo.git &&"
    Write-Host " echo '# NSX Configuration' > README.md && "
    Write-Host " git add README.md && "
    Write-Host " git commit -a -m 'Initial commit' && "
    Write-Host " git push -u origin master"
    Write-Host "`nThen run this script again."
    Exit
}

# Export Files
$LogicalSwitches_ExportFile = "$GitRepoPath\LogicalSwitches.xml"
$LogicalRouters_ExportFile = "$GitRepoPath\LogicalRouters.xml"
$Edges_ExportFile = "$GitRepoPath\Edges.xml"
$TransportZones_ExportFile = "$GitRepoPath\Transport_Zones.xml"

$Controllers_ExportFile = "$GitRepoPath\Controllers.xml"
$NSXManagerConfig_ExportFile = "$GitRepoPath\NSX_Manager.xml"

$SpoofGuardPolicies_ExportFile = "$GitRepoPath\SpoofGuard_Policies.xml"
$SpoofGuardNics_ExportFile = "$GitRepoPath\SpoofGuard_Nics.xml"

$IpSets_ExportFile = "$GitRepoPath\IpSets.xml"
$Services_ExportFile = "$GitRepoPath\Services.xml"
$ServiceGroups_ExportFile = "$GitRepoPath\Service_Groups.xml"

$SecurityGroups_ExportFile = "$GitRepoPath\Security_Groups.xml"
$SecurityTags_ExportFile = "$GitRepoPath\Security_Tags.xml"
$SecurityPolicies_ExportFile = "$GitRepoPath\Security_Policies.xml"

$FirewallRules_ExportFile = "$GitRepoPath\Firewall_Rules.xml"
$FirewallSections_ExportFile = "$GitRepoPath\Firewall_Sections.xml"
$FirewallSaved_ExportFile = "$GitRepoPath\Firewall_Saved_Log.xml"

# Start exporting
Write-Host -ForeGroundColor Green "NSX Config to Git Script"
Write-Host -ForeGroundColor yellow "`nGetting NSX Configuration"

# Backend config
Write-Host "  Getting NSX Controllers"
$Controllers = Get-NsxController -Connection $connection
# Remove last cluster sync to prevent this value being changed every run and causing a commit
$Controllers | Select-Xml -XPath '//*[local-name() = ''lastRefreshedAt'']' | Foreach-Object{$_.Node.RemoveAll()} 

# Topology config
Write-Host "  Getting LogicalSwitches"
$LogicalSwitches = Get-NsxLogicalSwitch -Connection $connection 

Write-Host "  Getting Logical Routers"
$LogicalRouters = Get-NsxLogicalRouter -Connection $connection
# Remove last edge sync to prevent this value being changed every run and causing a commit
$LogicalRouters | Select-Xml -XPath '//*[local-name() = ''statusFromVseUpdatedOn'']' | Foreach-Object{$_.Node.RemoveAll()} 

Write-Host "  Getting Edges"
$Edges = Get-NsxEdge -Connection $connection
# Remove last esg sync to prevent this value being changed every run and causing a commit
$Edges | Select-Xml -XPath '//*[local-name() = ''statusFromVseUpdatedOn'']' | Foreach-Object{$_.Node.RemoveAll()} 

Write-Host "  Getting Transport Zones"
$TransportZones = Get-NsxTransportZone -Connection $connection

# Spoofguard details
Write-Host "  Getting IP and MAC details from Spoofguard"
$SpoofGuardPolicies = Get-NsxSpoofguardPolicy -Connection $connection 

$SpoofGuardNics = @()
foreach($policy in $SpoofGuardPolicies) {
    $SpoofGuardNics += ($policy | Get-NsxSpoofguardNic -Connection $connection)
}

# Firewall config
Write-Host "  Getting configured IP Set objects"
$IPSets = Get-NsxIpSet -Connection $connection

Write-Host "  Getting configured Services"
$Services = Get-NsxService -Connection $connection

Write-Host "  Getting configured Service groups"
$ServiceGroups = Get-NsxServiceGroup -Connection $connection 

Write-Host "  Getting configured Security groups"
$SecurityGroups = Get-NsxSecurityGroup -Connection $connection 

Write-Host "  Getting configured Security tags"
$SecurityTags = Get-NsxSecurityTag -Connection $connection 

Write-Host "  Getting Security Policies"
$SecurityPolicies = Get-NsxSecurityPolicy -Connection $connection 

Write-Host "  Getting configured Distributed Firewall Rules"
$FirewallRules = Get-NsxFirewallRule -Connection $connection

Write-Host "  Getting configured Distributed Firewall Sections"
$FirewallSections = Get-NsxFirewallSection -Connection $connection

Write-Host "  Getting Distributed Firewall saved log"
$FirewallSaved = Get-NsxFirewallSavedConfiguration -Connection $connection

Write-Host "  Getting NSX Manager configuration"
$NSXManagerConfig = @()

# Backup details
$NSXManagerConfig += Get-NsxManagerBackup -Connection $connection
# SSL Certificate
$NSXManagerConfig += Get-NsxManagerCertificate -Connection $connection
# Component summary (services and if they are running)
$NSXManagerConfig += Get-NsxManagerComponentSummary -Connection $connection
# Network config
$NSXManagerConfig += Get-NsxManagerNetwork -Connection $connection
# NSX Manager role (standalone, primary, secondary)
$NSXManagerConfig += Get-NsxManagerRole -Connection $connection
# SSO configuration
$NSXManagerConfig += Get-NsxManagerSsoConfig -Connection $connection

# vCenter configuration
$tmp = Get-NsxManagerVcenterConfig -Connection $connection
# Remove the last vcenter sync time to prevent this value being changed every run and causing a commit
$tmp.vcInventoryLastUpdateTime = ""
$NSXManagerConfig += $tmp

# NSX Manager cluster synchronisation status (universal)
$tmp = Get-NsxManagerSyncStatus -Connection $connection
# Remove the last cluster sync time to prevent this value being changed every run and causing a commit
$tmp.lastClusterSyncTime = ""
$NSXManagerConfig += $tmp

# Syslog settings
$NSXManagerConfig += Get-NsxManagerSyslogServer -Connection $connection

# Time config (ntp)
$tmp = Get-NsxManagerTimeSettings -Connection $connection
# Remove the time to prevent this value being changed every run and causing a commit
$tmp.datetime = ""
$NSXManagerConfig += $tmp

# NSX Manager system summary (version, hostname, etc)
$tmp = Get-NsxManagerSystemSummary -Connection $connection
# Remove a couple of ever changing values to prevent this value being changed every run and causing a commit
$tmp.uptime = ""
$tmp.currentSystemDate = ""
$tmp | Select-Xml -XPath '//*[local-name() = ''cpuInfoDto'']' | Foreach-Object{$_.Node.RemoveAll()}
$tmp | Select-Xml -XPath '//*[local-name() = ''memInfoDto'']' | Foreach-Object{$_.Node.RemoveAll()}
$tmp | Select-Xml -XPath '//*[local-name() = ''storageInfoDto'']' | Foreach-Object{$_.Node.RemoveAll()}
$NSXManagerConfig += $tmp


Write-Host  -ForeGroundColor yellow "`nCreating Export XML Files.."

# Export config to their XML files
$NSXManagerConfig | Format-Xml | Out-File $NSXManagerConfig_ExportFile -Encoding ASCII
$Controllers | Format-Xml | Out-File $Controllers_ExportFile -Encoding ASCII

$LogicalSwitches | Format-Xml | Out-File $LogicalSwitches_ExportFile -Encoding ASCII
$LogicalRouters | Format-Xml | Out-File $LogicalRouters_ExportFile -Encoding ASCII
$Edges | Format-Xml | Out-File $Edges_ExportFile -Encoding ASCII
$TransportZones | Format-Xml | Out-File $TransportZones_ExportFile -Encoding ASCII


$Services | Format-Xml | Out-File $Services_ExportFile -Encoding ASCII
$ServiceGroups | Format-Xml | Out-File $ServiceGroups_ExportFile -Encoding ASCII
$IPSets | Format-Xml | Out-File $IpSets_ExportFile -Encoding ASCII

$SecurityTags | Format-Xml | Out-File $SecurityTags_ExportFile -Encoding ASCII
$SecurityGroups | Format-Xml | Out-File $SecurityGroups_ExportFile -Encoding ASCII
$SecurityPolicies | Format-Xml | Out-File $SecurityPolicies_ExportFile -Encoding ASCII

$FirewallRules | Format-Xml | Out-File $FirewallRules_ExportFile -Encoding ASCII
$FirewallSections | Format-Xml | Out-File $FirewallSections_ExportFile -Encoding ASCII
$FirewallSaved | Format-Xml | Out-File $FirewallSaved_ExportFile -Encoding ASCII

$SpoofGuardPolicies | Format-Xml | Out-File $SpoofGuardPolicies_ExportFile -Encoding ASCII
$SpoofGuardNics | Format-Xml | Out-File $SpoofGuardNics_ExportFile -Encoding ASCII

# Commit to git!
Write-Host -ForegroundColor yellow "`nCommitting changes to Git"
# Do an add on *.xml, commit any changes and push it to the origin
$output = & "$($GitBinary)" -C "$($GitRepoPath)" add "$($GitRepoPath)/*.xml" 2>&1
$output = & "$($GitBinary)" -C "$($GitRepoPath)" commit -a -m "Changes (via bot)" 2>&1
$output = & "$($GitBinary)" -C "$($GitRepoPath)" push -u origin master 2>&1
Write-Host $output

Write-Host  -ForeGroundColor Green "`nAll done!"


