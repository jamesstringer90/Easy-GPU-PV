<# 
If you are opening this file in Powershell ISE you should modify the params section like so...

Param (
    [string]$VMName = "NameofyourVM",
    [int]$GPUResourceAllocationPercentage = 50
)

#>

Param (
    [string]$VMName,
    [int]$GPUResourceAllocationPercentage
)

$VM = Get-VM -VMName $VMName

if (($VMName -AND $GPUResourceAllocationPercentage) -ne [string]$null) {
    If ($VM.state -eq "Running") {
        [bool]$state_was_running = $true
        }
    
    if ($VM.state -ne "Off"){
        "Attemping to shutdown VM..."
        Stop-VM -Name $VMName -Force
        } 
    
    While ($VM.State -ne "Off") {
        Start-Sleep -s 3
        "Waiting for VM to shutdown - make sure there are no unsaved documents..."
        }

    [float]$devider = [math]::round($(100 / $GPUResourceAllocationPercentage), 2)

    Set-VMGpuPartitionAdapter -VMName $VMName -MinPartitionVRAM ([math]::round($(1000000000 / $devider))) -MaxPartitionVRAM ([math]::round($(1000000000 / $devider))) -OptimalPartitionVRAM ([math]::round($(1000000000 / $devider)))
    Set-VMGPUPartitionAdapter -VMName $VMName -MinPartitionEncode ([math]::round($(18446744073709551615 / $devider))) -MaxPartitionEncode ([math]::round($(18446744073709551615 / $devider))) -OptimalPartitionEncode ([math]::round($(18446744073709551615 / $devider)))
    Set-VMGpuPartitionAdapter -VMName $VMName -MinPartitionDecode ([math]::round($(1000000000 / $devider))) -MaxPartitionDecode ([math]::round($(1000000000 / $devider))) -OptimalPartitionDecode ([math]::round($(1000000000 / $devider)))
    Set-VMGpuPartitionAdapter -VMName $VMName -MinPartitionCompute ([math]::round($(1000000000 / $devider))) -MaxPartitionCompute ([math]::round($(1000000000 / $devider))) -OptimalPartitionCompute ([math]::round($(1000000000 / $devider)))

    If ($state_was_running){
        "Previous State was running so starting VM..."
        Start-VM $VMName
        }

    "Done..."
}
