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

"Mounting Drive(s)..."
$DriveLetter = $null
$OSVHDPath = $null
foreach ($v in $VHD) {
    $mounted = Mount-VHD -Path $v.Path -PassThru
    $osVolume = $mounted | Get-Disk | Get-Partition | Get-Volume | Where-Object {$_.DriveLetter -and (Test-Path "$($_.DriveLetter):\Windows\System32\ntoskrnl.exe")}
    if ($osVolume) {
        $DriveLetter = $osVolume.DriveLetter
        $OSVHDPath = $v.Path
        }
    else {
        Dismount-VHD -Path $v.Path
        }
    }

if (-not $DriveLetter) {
    Throw "Could not find the VM's Windows OS volume among its attached VHDs."
    }

"Copying GPU Files - this could take a while..."
Add-VMGPUPartitionAdapterFiles -hostname $Hostname -DriveLetter $DriveLetter -GPUName $GPUName

"Dismounting Drive..."
Dismount-VHD -Path $OSVHDPath

If ($state_was_running){
    "Previous State was running so starting VM..."
    Start-VM $VMName
    }

"Done..."