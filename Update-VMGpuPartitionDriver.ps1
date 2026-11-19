<# 
If you are opening this file in Powershell ISE you should modify the params section like so...
Remember: GPU Name must match the name of the GPU you assigned when creating the VM...

Param (
[string]$VMName = "NameofyourVM",
[string]$GPUName = "NameofyourGPU",
[string]$Hostname = $ENV:Computername
)

#>

Param (
[string]$VMName,
[string]$GPUName,
[string]$Hostname = $ENV:Computername
)

Import-Module $PSSCriptRoot\Add-VMGpuPartitionAdapterFiles.psm1

$VM = Get-VM -VMName $VMName
$VHD = Get-VHD -VMId $VM.VMId

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

"Mounting Drive..."
    $mnt = Mount-VHD -Path $VHD.Path -PassThru
    Start-Sleep -Seconds 3
    $disk = $mnt | Get-Disk
    if ($disk.IsOffline) { Set-Disk -Number $disk.Number -IsOffline $false }
    $part = $disk | Get-Partition | Sort-Object Size -Descending | Select-Object -First 1
    if ($part.DriveLetter -notmatch '^[A-Z]$') {
        $part | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 3
        $part = $disk | Get-Partition | Sort-Object Size -Descending | Select-Object -First 1
    }
    $DriveLetter = "$($part.DriveLetter):"

"Copying GPU Files - this could take a while..."
Add-VMGPUPartitionAdapterFiles -hostname $Hostname -DriveLetter $DriveLetter -GPUName $GPUName

"Dismounting Drive..."
Dismount-VHD -Path $VHD.Path

If ($state_was_running){
    "Previous State was running so starting VM..."
    Start-VM $VMName
    }

"Done..."
