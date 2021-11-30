param (
    [parameter(Mandatory=$true)]
    [string]$vmnames

)

. "$PSScriptRoot\functions.ps1"
$Date = (Get-Date -Format "MM_dd_yyyy").ToString()
$Folder = "c:\temp\$Date" + "_VmwareMigrationLogs" + "\$vmnames"
If (!(Test-Path $Folder)){new-item $Folder -itemType Directory}

If(!(($global:DefaultVIServers).Count -gt 1)){
    ConnnectVcenter
}

If(test-path $VMNames){
    write-host "$VMNames contains path importing vms"
    $importcsv = import-csv $VMNames
    $VMNames = ($importcsv).vmnames
}

$MyCol = @()
foreach ($VMName in ($VMNames).split(' ')) {
    write-host "vm= $VMName"
    $getVm = Get-VM $VMName
    $vmview = Get-VM $VMName | Get-View
    $vmnetwork = Get-NetworkAdapter -VM $VMname
    $nicmac = ($vmnetwork).MacAddress
    $nictype = ($vmnetwork).Type
    $networkname= ($vmnetwork).NetworkName
    $IPs = $getvm.Guest.Nics |ForEach-Object {$_.IPAddress}
    $ProvisionedSpaceGB=[math]::round(($getvm.ProvisionedSpaceGB),2)
    $UsedSpaceGB=[math]::round(($getvm.UsedSpaceGB),2)
    $VMInfo = "" | Select-Object VMName,NICCount,IPAddress,MacAddress,NICType,NetworkName,Guest,GuestRunningOS,PowerState,`
        ToolsVersion,ToolsVersionStatus,ToolsStatus,ToolsRunningStatus,HWLevel,VMHost,Cluster,ProvisionedSpaceGB,UsedspaceGB
    $VMInfo.VMName = $vmview.Name
    $VMInfo.NICCount = $vmview.Guest.Net.Count
    $VMInfo.IPAddress = [string]$IPs 
    $VMInfo.MacAddress = [String]$nicmac -replace ' ' , "`n" 
    $VMInfo.NICType = [String]$nictype -replace ' ' , "`n"
    $VMInfo.NetworkName = [String]$networkname -replace ' ' , "`n"
    $VMInfo.Guest = $vmview.Guest.Hostname
    $VMInfo.GuestRunningOS = $vmview.Guest.GuestFullname
    $VMInfo.PowerState = $getvm.PowerState
    $VMInfo.ToolsVersion = $vmview.Guest.ToolsVersion
    $VMInfo.ToolsVersionStatus = $vmview.Guest.ToolsVersionStatus
    $VMInfo.ToolsStatus = $vmview.Guest.ToolsStatus
    $VMInfo.ToolsRunningStatus = $vmview.Guest.ToolsRunningStatus
    $VMInfo.HWLevel = $vmview.Config.Version
    $VMInfo.VMHost = ($getvm.VMHost).Name
    $VMInfo.Cluster = ($getvm.VMHost.Parent).Name
    $VMInfo.UsedSpacegb = $UsedspaceGB
    $VMInfo.ProvisionedSpaceGB = $ProvisionedSpaceGB    
    $myCol += $VMInfo
}

$StartEnd = (Get-Date -Format "MM_dd_yyyy_hh-mm-ss").ToString()
$file = $Folder + "\HWreport-" + "$StartEnd" + ".csv"  
$myCol | Export-csv -NoTypeInformation $file

        