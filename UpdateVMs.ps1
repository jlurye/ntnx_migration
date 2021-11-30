param (
        [parameter(Mandatory=$true)]
        [string]$vmname
)

. "$PSScriptRoot\functions.ps1"

If(!(($global:DefaultVIServers).Count -gt 1)){
    ConnnectVcenter
}

$Date = (Get-Date -Format "MM/dd/yyyy HH:mm:ss").ToString()  
$vm = get-vm $vmname
$VCserver = $vm.Uid.Split(":")[0].Split("@")[1]
$ToolsVersionStatus=$vm.Guest.ExtensionData.ToolsVersionStatus
$networkadapters = get-networkadapter $vm 
$IPs = ($vm).Guest.Nics|ForEach-Object {$_.IPAddress}
$HardwareVersion = $vm.HardwareVersion

Out-Log $vm "************************************************************************************************************" "green"
Out-Log $vm "Starting Update VM Script`tVM:$vmname`t`t`t`tStart Time:`t$Date"
Out-Log $vm "************************************************************************************************************`n" "green"

out-log $vm "$Date $vm taking Snapshot before Tools and Hardware update." "yellow"
New-Snapshot -VM $vm -Name "Before_VM_Update" -Description "Snapshot taken before Tools and Hardware was updated" -Confirm:$false -RunAsync
Wait-VMTask $VCserver "CreateSnapshot_Task" $vm

If ((get-vm $Vm).PowerState -eq 'PoweredOff'){
  out-log $vm "$Date $vm PoweredOff. Waiting for PowerOn" "yellow"
  Start-VM -VM $vm -Confirm:$false -RunAsync
  Wait-VMPower $vm 'PoweredOn'
}

out-log $vmname "$Date $vm Tools Status: $ToolsVersionStatus" "yellow"

If ($ToolsVersionStatus -eq 'guestToolsNeedUpgrade'){
  out-log $vm "$Date $vm Upgrading Tools" "yellow"
 Update-Tools -NoReboot -VM $vm -Verbose -RunAsync
 $ResultUpGradeTools = Wait-VMTask $VCserver "UpgradeTools_Task" $VM 
  If (!($ResultUpGradeTools -eq 'success')){
    Start-sleep 20 
    [Environment]::Exit(1)
  } 
  out-log $vm "$Date $vm tools=$ToolsRunningStatus upgraded SUCESSFUL!!!!" "green"
}

$Retrycount = 0
$RetrycountMax=30 
 
do{ 
  $vm = get-vm $vmname
  $ToolsRunningStatus=$vm.Guest.ExtensionData.ToolsRunningStatus
    if (($ToolsRunningStatus -eq 'toolsNotRunning') -and ($Retrycount -lt $RetrycountMax)){
      $Retrycount++
      Start-Sleep -Seconds 10
    }
}until (($ToolsRunningStatus -eq 'guestToolsRunning') -or ($Retrycount -eq $RetrycountMax))

IF((get-vm $vm).Guest.ExtensionData.ToolsVersionStatus -eq 'guestToolsNeedUpgrade'){
  out-log $vm "$Date $vm VMWare Tools Not UPGRADED  Failed!!!!" "red"
  [Environment]::Exit(1)
  Start-Sleep -Seconds 20
}

Shutdown-VMGuest -VM $vm -Confirm:$false | Out-Null
out-log $vm "$Date $vm shutting down VM" "yellow"
$ResultVMShutDown = Wait-VMPower $vm 'PoweredOff'
If (!($ResultVMShutDown -eq 'success')){
   out-log $vm "$Date $vm not shut down properly FAILED!!!!" "red"
   [Environment]::Exit(1)
   Start-Sleep -Seconds 20
} 
  
out-log $vm "$Date $vm HardwareVersion = $HardwareVersion" "yellow"
$power = (get-vm $vm).powerState
out-log $vm "$Date $vm powerstate = $power" "yellow"
If (((get-vm $vm).powerState -eq  "PoweredOff") -and ($HardwareVersion -lt 'vmx-14')){  
  out-log $vm "$Date $vm  HardwareVersion = $HardwareVersion and will be upgraded" "yellow"
  $vm.ExtensionData.UpgradeVM('vmx-14')
  Wait-VMTask $VCserver "UpgradeVM_Task" $VM 
  $vm = get-vm $vmname 
  $HardwareVersion = $vm.HardwareVersion
  out-log $vm "$Date $vm  HardwareVersion = $HardwareVersion upgraded SUCESSFUL!!!!" "yellow"
  $networkadapters = get-networkadapter $vm
  foreach ($networkadapter in $networkadapters) {
    $vm| Get-NetworkAdapter | Where-object {$_.name -eq "$networkadapter"} | Set-NetworkAdapter -StartConnected:$true -Confirm:$false
  }
}

IF(!((get-vm $vm).HardwareVersion -ge 'vmx-14')){
  out-log $vm "$Date $vm $HardwareVersion Not UPGRADED" "red"
  [Environment]::Exit(1)
}

Start-VM -VM $vm -Confirm:$false -RunAsync
$ResultVMPowerOn = Wait-VMPower $vm 'PoweredOn'
If (!($ResultVMPowerOn -eq 'success')){
   out-log $vm "$Date $vm did not power on properly FAILED!!!!" "red"
   [Environment]::Exit(1)
   Start-Sleep -Seconds 20
} 

$Retrycount = 0  
$RetrycountMax = 30  
do{ 
  $vm = get-vm $vmname
  $IPs = ($vm).Guest.Nics|ForEach-Object {$_.IPAddress}
  if ((!($IPs)) -and ($Retrycount -lt $RetrycountMax)){
      $Retrycount++
      write-host "$VM waiting powering on count = $Retrycount" -ForegroundColor "yellow"
      Start-Sleep -Seconds 5
    }
}until (($IPs) -or ($Retrycount -eq $RetrycountMax))

If ($IPs){
  out-log $vm "$Date $vm Powered On" "green"
}else{
  out-log $vm "$Date $vm Power back on successfully" "red"
  Start-Sleep 20
  [Environment]::Exit(1)
}

ForEach ($IP in $IPs){
  $PingReturn = PingVM $IP
  If ($PingReturn -eq 'Failure'){
    Start-sleep 20 
    [Environment]::Exit(1)
  }
}

out-log $vm "$Date $vm updated Successfully!!!!!" "green"
 
