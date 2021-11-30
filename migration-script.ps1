param (
        [parameter(Mandatory=$true)]
        [string]$vmnames,
        [parameter(Mandatory=$false)]
        [string] $cluster
        #[parameter(Mandatory=$false)]
        #[string] $fullmigration

)  

. "$PSScriptRoot\functions.ps1"

If(!(($global:DefaultVIServers).Count -gt 1)){
    ConnnectVcenter
}

If(test-path $VMNames){
    write-host "$VMNames contains path importing vms"
    $importcsv = import-csv $VMNames
    $VMNames = ($importcsv).vmnames
    $Clusters = ($importcsv).clusters
}

foreach ($VMName in ($VMNames).split(' ')){
    $Date = (Get-Date -Format "MM/dd/yyyy HH:mm:ss").ToString()         
    $vm = get-vm $vmname
    $VCserver = $vm.Uid.Split(":")[0].Split("@")[1] 

    Out-Log $vm "************************************************************************************************************"
    Out-Log $vm "Starting Migration Script`tVM:$vmname`t`t`t`tStart Time:`t$Date"
    Out-Log $vm "************************************************************************************************************`n"

    If ($Clusters){
        $Cluster = ($importcsv | Where-Object {$_.vmnames -eq $vmname}).clusters
    }

    If (!($Cluster)){
        $count=0
        while($count -le 9)
        {
            if($host.UI.RawUI.KeyAvailable) {
                $key = $host.ui.RawUI.ReadKey("NoEcho,IncludeKeyUp")
            if($key.VirtualKeyCode -eq '32') {
                    Write-Host -ForegroundColor Yellow ("Enter Destination Cluster Name")
                    $Cluster= read-host
                    break
            }
            }
            $count++
            Write-Host ("Count Incremented to - {0}" -f $count)
            Write-Host ("Press 'spacebar' to enter cluster or script will fail!!!!!")
            Start-Sleep  1
        }
    }
    if (!($Cluster)){ 
        out-log $vm "$Date No Cluster Specified" "red"
        Start-sleep 20
        [Environment]::Exit(1)
    }
    
    #$destDS = get-cluster $cluster | get-datastore | Where-Object {$_.ExtensionData.Summary.MultipleHostAccess}  |Sort-Object -Property FreespaceGB -Descending:$true |Select-Object -First 1 | Where-Object {$_.name -notlike "NTNX*"}  
    #$destDS = get-cluster $cluster | get-datastore | Where-Object {$_.name -like "LFDRSLAB*"} | Get-Random     
    $destDS = get-cluster $cluster | get-datastore | Where-Object {$_.name -like "$cluster*"}      
    $destHost = Get-Cluster $cluster | get-vmhost | Where-Object{$_.ConnectionState -eq “Connected”}| Get-Random 
    $networkadapters = get-networkadapter $vm 
    $IPs = ($vm).Guest.Nics|ForEach-Object {$_.IPAddress}

    $DestPG=@()          
    foreach($networkadapter in $networkadapters) {
        $sourcenetwork = get-networkadapter $vm -name ($networkadapter).name | Select-Object networkname
        $DestPG += Get-VDPortgroup -Server $VCServer | Where-Object {($_.name -eq $sourcenetwork.networkname+"-NTX")}
        if (!($DestPG)){
        out-log $vm "$vm $networkadapter $sourcenetwork doesnt exist. VM may already be migrated to Nutanix. FAILURE!!!!" "red"
        [Environment]::Exit(1)
        } 
        else {
            out-log $vm  "$vm $networkadapter Destination Port Group $DestPG exists and will continue" "green"
        }
    } 
    
    
    $oldsnapshots=Get-VM $vm | Get-Snapshot | Where-Object {$_.Created -lt (Get-Date).AddDays(-14)}
    If ($oldsnapshots) { $oldsnapshots | remove-snapshot -confirm:$false
        $TaskResult = Wait-VMTask $VCserver 'RemoveSnapshot_Task' $Vm
        Out-Log "old snaphshot have been removed for $vm" 
    }

   
    $drsgroup=(Get-DrsClusterGroup -Type VMGroup | ? {$_.member -contains $vm})
    if ($drsgroup.member.count -gt 1) {Get-DrsClusterGroup $drsgroup | Set-DrsClusterGroup -VM $vm -Remove -Confirm:$false | out-null
    Out-Log "$vm removed from DRS Group $drsgroup"
    }
    if ($drsgroup.member.count -eq 1) {Get-DrsClusterGroup $drsgroup | Remove-DrsClusterGroup -Confirm:$false
    Out-Log "$vm is last VM in DRS group. $drsgroup is now removed"
    } 
    
    Move-VM -VM $vm -Destination $destHost -NetworkAdapter $networkAdapters -Portgroup $DestPG -Datastore $destDS -DiskStorageFormat Thin -InventoryLocation "HCI-Migration" -confirm:$false -RunAsync 
    out-log $vm "$date $vm moving  -Destination $destHost -NetworkAdapter $networkAdapters -Portgroup $DestPG -Datastore $destDS " "yellow"
    $TaskResult = Wait-VMTask $VCserver 'RelocateVM_Task' $Vm
    write-host $TaskResult
     
    If (!($TaskResult -eq 'success')){
        out-log $vm "$date $vm Failed to Migrate within the allowed timframe.  Could be taking to long or an issue.  Check $vm FAILURE!!!!" "red"
        start-sleep 20
        [Environment]::Exit(1)
    }

    $PostVmMove = get-vm $vm
    $postnetwork = get-networkadapter $PostVmMove    
    #$PostPortGroupNames = ($postnetwork | Select-Object networkname).NetworkName
    $PostCluster =  ($PostVmMove | Select-Object -Property Name,@{Name=’Cluster’;Expression={$_.VMHost.Parent}}).Cluster.Name
    $PostHost = ($PostVmMove| Select-Object VMHost).VMHost.Name
    foreach ($networkadapter in $postnetwork) {
        $vm| Get-NetworkAdapter | Where-object {$_.name -eq "$networkadapter"} | Set-NetworkAdapter -StartConnected:$true -Confirm:$false
        Wait-VMTask $VCserver 'ReconfigVM_Task' $Vm
    }

    If (!($PostCluster -eq $cluster)){
        out-log $vm "$Date $vm Current cluster $cluster doesnt match destination cluster $PostCluster!!!!!!!" "red"
        start-sleep 20
        [Environment]::Exit(1)
    }
    else{
        out-log $vm "$Date $vm Current cluster $cluster matches destination cluster $PostCluster" "green"
    }

    If (!($PostHost -eq ($destHost).name)){
        out-log $vm "$Date $vm Current host $PostHost doesnt match destination host $destHost!!!!!" "red"
        start-sleep 20
        [Environment]::Exit(1)
    }
    else{
        out-log $vm "$Date $vm Current host $PostHost matches destination host $destHost" "green"
        
    }

    <#
    If (!($PostPortGroupNames -eq ($DestPG).name)){
        out-log $vm "$Date $vm Current port group $PostPortGroupNames doesnt match destination port group $DestPG!!!!!" "red"
        start-sleep 20
        [Environment]::Exit(1)
    }
    else{
        out-log $vm "$Date $vm Current port group $PostPortGroupNames matches destination port group $DestPG" "green"
    }
    #>

    ForEach ($IP in $IPs){
        $PingReturn = PingVM $IP
        If ($PingReturn -eq 'Failure'){[Environment]::Exit(1) }
    }
}

out-log $vm "$date $vm Migration was SUCESSFUL!!!!!!`n" "green"

<#
If ($FullMigration) {
    out-log $vm "Running updatevm.ps1"
    &   "$PSScriptRoot\UpdateVms.ps1" $vmnames
}
#>
