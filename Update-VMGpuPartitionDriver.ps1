<# 
If you are opening this file in Powershell ISE you should modify the params section like so...
Remember: GPU Name must match the name of the GPU you assigned when creating the VM...

Param (
[string]$VMName = "NameofyourVM",
[string]$GPUName = "NameofyourGPU",
[string]$BitLockerKey = "XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX",
[string]$Hostname = $ENV:Computername
)

#>

Param (
    [string]$VMName,
    [string]$GPUName,
    [string]$BitLockerKey,
    [string]$Hostname = $ENV:Computername
)

$ErrorActionPreference = "Stop"

Import-Module $PSSCriptRoot\Add-VMGpuPartitionAdapterFiles.psm1

$VM = Get-VM -VMName $VMName
$VHD = Get-VHD -VMId $VM.VMId

If ($VM.state -eq "Running") {
    [bool]$state_was_running = $True
}

if ($VM.state -ne "Off") {
    "Attemping to shutdown VM..."
    Stop-VM -Name $VMName -Force
    $VHD = Get-VHD -VMId $VM.VMId
} 

While ($VM.State -ne "Off") {
    Start-Sleep -s 3
    "Waiting for VM to shutdown - make sure there are no unsaved documents..."
}

if ($VHD.Attached -eq $False) {
    "Mounting Drive..."
    $DriveLetter = (Mount-VHD -Path $VHD.Path -PassThru | Get-Disk | Get-Partition | Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object DriveLetter)
}
else {
    $DriveLetter = ($VHD | Get-Disk | Get-Partition | Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object DriveLetter)
    "Using already mounted drive ${DriveLetter}"
}

$BitLockerStatus = Get-BitLockerVolume $DriveLetter
if ($BitLockerStatus.LockStatus) {
    if ([string]::IsNullOrWhiteSpace($BitLockerKey)) {
        $BitLockerKey = Read-Host "Enter BitLocker Key for drive ${DriveLetter}"
    }
    Unlock-BitLocker -MountPoint $DriveLetter -RecoveryPassword $BitLockerKey
}

"Copying GPU Files - this could take a while..."
Add-VMGPUPartitionAdapterFiles -hostname $Hostname -DriveLetter $DriveLetter -GPUName $GPUName

"Dismounting Drive..."
Dismount-VHD -Path $VHD.Path

If ($state_was_running) {
    "Previous State was running so starting VM..."
    Start-VM $VMName
}

"Done..."