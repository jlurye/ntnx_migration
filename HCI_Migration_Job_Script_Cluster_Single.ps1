param (
        [parameter(Mandatory=$false)]
        [string]$Csv
)

. "$PSScriptRoot\functions.ps1"

Set-PowerCLIConfiguration -DefaultVIServerMode multiple -Scope Session -Confirm:$false

If(!(($global:DefaultVIServers).Count -gt 1)){
   ConnnectVcenter
}

$Csv = $csv
$MaxJobs = "2"

if (!($Csv)){$Csv = "$PSScriptRoot\test_migration.csv"}

Import-csv $Csv | ForEach-Object {
     $vmname = $_.vmnames
     $cluster = $_.clusters
     #$FullMigration = $false
     write-host $VMName $Cluster
     $Date = (Get-Date -Format "MM_dd_yyyy").ToString()
     $Folder = "C:\temp\$Date" + "_VmwareMigrationLogs" + "\$vmname"
     If (!(Test-Path $Folder)){new-item $Folder -itemType Directory}
     & "$PSScriptRoot\HWreport.ps1" $vmname
     Start-Job  -Name $vmname -ScriptBlock { 
               param (
                 [parameter(Mandatory=$false)]
                 [string]$vmname,
                 [parameter(Mandatory=$false)]
                 [string]$cluster
                 #[parameter(Mandatory=$false)]
                 #[string]$FullMigration
               )
              & "C:\Workspaces\nutanix_migration\migration-script.ps1" $vmname $cluster  
         } -ArgumentList $vmname, $cluster 
    while (@(Get-Job -State Running).Count -eq $MaxJobs) {
          $now = Get-Date
          foreach ($job in @(Get-Job -State Running)) {
              #write-host (Get-Job -State Running).count
              Receive-Job ($job).ChildJobs 

              if ($now - (Get-Job -Id $job.id).PSBeginTime -gt [TimeSpan]::FromMinutes(3000)) {
               Stop-Job $job
           }
         }
      Start-Sleep -sec 2
      }
     & "$PSScriptRoot\HWreport.ps1" $vmname
 }






