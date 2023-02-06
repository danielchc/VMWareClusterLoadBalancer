# VMWareClusterLoadBalancer

This PowerShell script that can move virtual machines between hosts in an ESXi cluster without the need for a VMware Enterprise license. It simulates the functionality of the **Fully Automated** DRS Automation Level.



### Params:
 - **vCenter**: vSphere Appliance
 - **TargetCluster**: Cluster
 - **MemoryThreshold** and **CPUThreshold**:  Minimum Host Load Percentage to move VMs
 - **DiffMemoryThreshold** and **DiffCPUThreshold**: Minimum difference between the load of the host with the highest load and the one with the least load.
 - **User** and **Password**:  vSphere Appliance credentials
 - **IterationMax**: Maximum number of VMs to move

### Example
``` powershell
 ./VMWareClusterLoadBalancer.ps1 -vCenter vcsa.vsphere.local  -TargetCluster cluster01 -MemoryThreshold 80 -CPUThreshold 80 -DiffCPUThreshold 5 -DiffMemoryThreshold 5 -User administrator@vsphere.local -Password p4ssw0rd  -IterationMax 10
```
