Param(
    [parameter(Mandatory = $true)]
    [string]
    $vCenter,
    [parameter(Mandatory = $true)]
    [string]
    $TargetCluster,
    [parameter(Mandatory = $true)]
    [string]
    $User,    
    [parameter(Mandatory = $true)]
    [string]
    $Password,
    [parameter(Mandatory = $true)]
    [int]
    $MemoryThreshold,
    [parameter(Mandatory = $true)]
    [int]
    $CPUThreshold,
    [parameter(Mandatory = $true)]
    [int]
    $DiffCPUThreshold,
    [parameter(Mandatory = $true)]
    [int]
    $DiffMemoryThreshold,
    [parameter(Mandatory = $true)]
    [int]
    $IterationMax,
    [int]
    $Interval
)

function Get-VMHostLoadPercentage($ClusterHosts) {
    foreach ($objHost in $objHosts) {
        $objHost | Add-Member NoteProperty PercentMemory ($objHost.MemoryUsageMB / $objHost.MemoryTotalMB * 100)
        $objHost | Add-Member NoteProperty PercentCPU ($objHost.CpuUsageMhz / $objHost.CpuTotalMhz * 100)
        $objHost
    }
}

function Get-VMLoadOPercentage($VMs) {
    foreach ($vm in $VMs) {
        try {
            $usedMemory = $vm | Get-Stat -Stat Mem.Usage.Average -Realtime | Measure-Object Value -Average
            $usedCPU = $vm | Get-Stat -Stat CPU.Usage.Average -Realtime | Measure-Object Value -Average
            $vm | Add-Member NoteProperty PercentMemory $usedMemory.Average
            $vm | Add-Member NoteProperty PercentCPU $usedCPU.Average
            $vm
        }
        catch {
            Write-Host -ForegroundColor Yellow "WARNING: Unable to obtain VM information"
        }
    }

}

# vCenter connection

Write-Host -NoNewline "Connecting the vCenter $vCenter... "
try {
    Connect-VIServer $vCenter -User $User -Password $Password | Out-Null
}
catch {
    Write-Host -ForegroundColor Red "Unable to connect to vCenter $vCenter"
    Exit 1
}
Write-Host -ForegroundColor Green "OK"

$iterationCount = 1
$alreadyReallocated = @()


while ($iterationCount -le $IterationMax) {

    $clusterVMHosts = @()
    #Load percentage of each host in the cluster
    $objHosts = Get-Cluster $TargetCluster | Get-VMHost
    $clusterVMHosts = Get-VMHostLoadPercentage -ClusterHosts $objHosts | Where-Object { $_.PowerState -eq "PoweredOn" -and $_.ConnectionState -eq "Connected" }

    # Check if the difference between memory and CPU between the Host with the most load and the one with the least load is greater than a certain percentage (DiffCPUThreshold and DiffMemoryThreshold)
    $pMemoryHost = $clusterVMHosts | Measure-Object -Property PercentMemory -Minimum -Maximum
    $pCPUHost = $clusterVMHosts | Measure-Object -Property PercentCPU -Minimum -Maximum
    if ((($pCPUHost.Maximum - $pCPUHost.Minimum) -lt $DiffCPUThreshold) -and (($pMemoryHost.Maximum - $pMemoryHost.Minimum) -lt $DiffMemoryThreshold)) {
        Write-Host -ForegroundColor Yellow "The load difference is not enough, the script ends."
        break;
    }

    # Hosts, which are candidates to have machines that can be moved, and say the hosts that have more than a certain CPU and/or memory usage
    $reallocableVMHosts = $clusterVMHosts | Where-Object { $_.PercentMemory -GT $MemoryThreshold -Or $_.PercentCPU -GT $CPUThreshold }

    # Machines that are on the previous hosts, and that were not previously moved
    $elegibles = Get-VM | Where-Object { ($_.VMHost -in $reallocableVMHosts -and $_.PowerState -eq "PoweredOn") -and ($_ -notin $alreadyReallocated) }
    if ($elegibles.Count -eq 0) {
        Write-Host -ForegroundColor Yellow "No VMs found to move"
        break;
    }

    # VM with the least load
    $candidate = Get-VMLoadOPercentage -VMs $elegibles | Sort-Object -Descending -Property @{Expression = "PercentMemory"; Descending = $False }, @{Expression = "PercentCPU"; Descending = $False } | Select-Object -First 1

    # Host with the least load
    $targetHost = $clusterVMHosts  | Sort-Object -Descending -Property @{Expression = "PercentCPU"; Descending = $False }, @{Expression = "PercentMemory"; Descending = $False } | Select-Object -First 1

    # Move the VM to the host with the least load

    Write-Host -NoNewline "[$($iterationCount)/$($IterationMax)] Moving $($candidate.Name) to $($targetHost.Name)... "
    try {
        $candidate | Move-VM -destination $targetHost | Out-Null
        Write-Host -ForegroundColor Green "OK"
    }
    catch { 
        Write-Host -ForegroundColor Red "Unable to move VM"
    }
    
    
    $alreadyReallocated += $candidate
    $iterationCount++

    # Wait for the next iteration
    if ($iterationCount -le $IterationMax) {
        Start-Sleep -Seconds $Interval
    }
}
Disconnect-VIServer $vCenter