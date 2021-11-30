
Function Out-Log {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$vmname,
        [Parameter(Mandatory=$false)]
        [string]$LineValue,
        [Parameter(Mandatory=$false)]
        [string]$color ='white'
    )
    $Date = (Get-Date -Format "MM_dd_yyyy").ToString()
    $Folder = "c:\temp\$Date" + "_VmwareMigrationLogs"
    If (!(Test-Path $Folder)){new-item $Folder -itemType Directory}
    $Logfile = "$Folder\$vmname.log"
    Add-Content -Path $Logfile -Value $LineValue
    Write-Host $LineValue -ForegroundColor $color 
} 

function ConnnectVcenter{
  #If(!(Get-InstalledModule -Name VMware.VimAutomation.Cis.Core -ErrorAction SilentlyContinue)){
  #   [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  #   Install-Module VMware.PowerCLI -Scope AllUsers  -Force}
  # If(!((get-PowerCLIConfiguration).DefaultVIServerMode -eq 'Multiple' )){Set-PowerCLIConfiguration -DefaultVIServerMode multiple -Scope Session -Confirm:$false}
  Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | Out-Null
  Set-PowerCLIConfiguration -DefaultVIServerMode multiple -Scope Session -Confirm:$false | Out-Null
  $TrainingVCenter = "trmvwap001.us.grainger.com"
  $LFVCenter = "lfmvmwap001.resource.grainger.com"
  $PRMVCenter = "prmvmwap001.resource.grainger.com"
  $File1 = "$ENV:temp\254234234wfafaeraefgategaeedsdfsdfsdfsdfwersfj456e5.txt" 
  $file2 = "$ENV:temp\254253345436ghty45234234wfafaerfsdfsdfwersfj456e5sd.txt"
  if ((!(Test-Path $file1)) -or (!(Test-Path $file2))){
     $cred =  Get-Credential      
     $GetSecureString = $cred.GetNetworkCredential() | Select-Object -Property domain, username| Format-Table -HideTableHeaders -Autosize |Out-String 
     $secureStringText1 = $GetSecureString.trim().Replace(' ', '\') | ConvertTo-SecureString -AsPlainText -Force 
     $secureStringText1 | ConvertFrom-SecureString | Out-File $file1
     $secureStringText2 = $cred.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force 
     $secureStringText2 | ConvertFrom-SecureString | Out-File $file2
  }
  $getfile1 = Get-Content $file1
  $getsec = $getfile1 | ConvertTo-SecureString 
  $BSTR =[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($getsec)
  $Plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
  $ID2 = Get-Content $file2
  $secure = $ID2 | ConvertTo-SecureString 
  $credObject = New-Object System.Management.Automation.PSCredential -ArgumentList $Plain, $secure
  Connect-VIServer -Server $TrainingVCenter -Credential $credObject -ErrorAction SilentlyContinue | Out-Null
  Connect-VIServer -Server $LFVCenter -Credential $credObject -ErrorAction SilentlyContinue   | Out-Null 
  Connect-VIServer -Server $PRMVCenter -Credential $credObject -ErrorAction SilentlyContinue  | Out-Null
  return $cred
}

function Wait-VMTask{
    Param(
      [Parameter(Mandatory=$true)]
      [string]$VCserver,
      [Parameter(Mandatory=$true)]
      [string]$status_to_check,
      [Parameter(Mandatory=$true)]
      [string]$vmName,
      [Parameter(Mandatory=$false)]
      [int] $RetrycountMax=600,
      [Parameter(Mandatory=$false)]
      [int] $sleepseconds=10
    )
    $Date = (Get-Date -Format "MM/dd/yyyy HH:mm:ss").ToString()  
    $Retrycount = 0    
    do{ 
        $task = get-task -Server $VCserver | Where-Object {$_.name -eq $status_to_check -and $_.ExtensionData.Info.EntityName -eq $vmName} | Select-Object -Last 1
        if (($task).state -eq 'Running' -and $Retrycount -lt $RetrycountMax){
          $Retrycount++ 
          $RtrStr = $Retrycount | Out-String
          write-host "$Date $VM $task is running waiting count = $RtrStr" -ForegroundColor "yellow"
          Start-Sleep -Seconds $sleepseconds
        }
    }until ((($task).state -eq 'Success') -or ($Retrycount -eq $RetrycountMax) -or ($task).state -eq 'Error')
    
    If (($task).state -eq 'Success'){
     out-log $vm "$Date $vm $task completed successfully" "green"
     return 'success'
    }else{
     out-log $vm "$Date $vm $task FAILED to complete successfully FAILURE!!!!!" "red"
     return 'Failure'
    }
}

function Wait-VMPower{
  Param(
    [Parameter(Mandatory=$true)]
    [string]$vmName,
    [Parameter(Mandatory=$true)]
    [string] $PowerstateVar,
    [Parameter(Mandatory=$false)]
    [int] $RetrycountMax=60,
    [Parameter(Mandatory=$false)]
    [int] $sleepseconds=1
  )
  $Date = (Get-Date -Format "MM/dd/yyyy HH:mm:ss").ToString()  
  $Retrycount = 0    
  do{ 
      $vm = get-vm $VmName
      $powerstate = $vm.PowerState
      if ((!($powerstate -eq $PowerstateVar)) -and ($Retrycount -lt $RetrycountMax)){
        $Retrycount++
        write-host "$VM $powerstate is powering $PowerstateVar waiting count = $Retrycount" -ForegroundColor "yellow"
        Start-Sleep -Seconds $sleepseconds
      }
  }until (($powerstate -eq $PowerstateVar) -or ($Retrycount -eq $RetrycountMax))
  
  If ($powerstate -eq $PowerstateVar){
   out-log $vm "$Date $vm $PowerstateVar" "green"
   return 'Success'
  }else{
   out-log $vm "$Date $vm $PowerstateVar FAILED!!!!  Please Finish Hardware Update Manually." "red"
   return 'Failure'
  }
}

function PingVM {
  param (
    [Parameter(Mandatory=$true)]
    [string]$IP
  )
  $ipv4 = "^([1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){3}$"
  If ($IP -match $ipv4){ 
    $Timeout = 100
    $Retrycount = 0
    $RetrycountMax = 20

    do{ 
      $Ping = New-Object System.Net.NetworkInformation.Ping
      $Response = $Ping.Send($IP,$Timeout)
      $Response.Status
      $Retrycount ++
      write-host "ping try number $Retrycount"
    }until (($Response.Status -eq 'success') -or ($Retrycount -eq $RetrycountMax))
    
    If ($Response.Status -eq 'success'){
      out-log $vm "$Date $vm Ping $IP was SUCCESSFUL" "green"
      return 'Success'
    }
      
    If ($Retrycount -eq $RetrycountMax){
      out-log $vm "$Date $vm $IP did not respond to ping FAILURE!!!!!!" "red"
      return 'Failure'
    }
  }else {
    out-log $vm "$Date $vm $IP is not valid IPv4" "yellow"
  }
}