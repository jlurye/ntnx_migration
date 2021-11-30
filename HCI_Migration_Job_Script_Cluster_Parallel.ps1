

$PWSH7 = (test-path 'C:\Program Files\PowerShell\')
If (!($PWSH7)){
  Write-Host "This Script requires Powershell 7!!!!  Please wait wait while we download and install.   If UAC is installed please click yes to install!!!!" 
  $url = 'https://github.com/PowerShell/PowerShell/releases/download/v7.1.2/PowerShell-7.1.2-win-x64.msi'
  $msiFile = "$env:temp\PowerShell-7.1.2-win-x64.msi"
  $start_time = Get-Date

  $wc = New-Object System.Net.WebClient
  $wc.DownloadFile($url, $msiFile)

  $arglist = '/qb! ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1'
  Start-Process msiexec.exe -Wait -ArgumentList "/i  $msiFile  $arglist"
}



$Date = (Get-Date -Format "MM_dd_yyyy").ToString()
$Folder = "$Env:temp\$Date" + "_VmwareMigrationLogs"
$MaxJobs = "2"

$ClusterGroups = Import-CSV "$PSScriptRoot\test_migration.csv" | Group-Object clusters

$scriptpath = $PSScriptRoot
if (!($env:ScriptPath)){setx ScriptPath $PSScriptRoot /m}


$ClusterGroups | ForEach-Object -parallel {

  $cluster = $_.name
  write-host "Cluster = $Cluster"
  $Date = (Get-Date -Format "MM_dd_yyyy").ToString()
  $Folder = "C:\temp\$Date" + "_VmwareMigrationLogs" + "\$vmname"
  If (!(Test-Path $Folder)){new-item $Folder -itemType Directory}

  $CSV = "$env:ScriptPath\test_migration.csv"

  Import-csv $Csv | Where-Object {$_.clusters -match "$cluster"  }  | ForEach-Object -parallel {
    $vmname = $_.vmnames
    $cluster = $_.clusters
    $Date = (Get-Date -Format "MM_dd_yyyy").ToString()
    $Folder = "C:\temp\$Date" + "_VmwareMigrationLogs\$vmname"      
    write-host "VMname is $vmname"
    $FullMigration = $True
    write-host $VMName $Cluster
    New-Item "$Folder" -ItemType Directory -Force 

    Powershell -noprofile -executionpolicy bypass -file "$env:ScriptPath\HWreport.ps1" "$vmname"
    Powershell -noprofile -executionpolicy bypass -file "$env:ScriptPath\migration-script.ps1" "$vmname" "$cluster" "$FullMigration"
    Powershell -noprofile -executionpolicy bypass -file "$env:ScriptPath\HWreport.ps1" "$vmname"  
  }-ThrottleLimit $using:MaxJobs

} 
 




