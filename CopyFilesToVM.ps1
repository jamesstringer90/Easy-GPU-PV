$params = @{
    VMName = "GPUPV"
    pisoPath = "C:\Program Files\PowerISO\piso.exe"
    SourcePath = "C:\Users\james\Downloads\Win11_English_x64.iso"
    Edition    = 6
    VhdFormat  = "VHDX"
    DiskLayout = "UEFI"
    SizeBytes  = 40GB
    MemoryAmount = 8GB
    CPUCores = 4
    NetworkSwitch = "Default Switch"
    VHDPath = "C:\Users\Public\Documents\Hyper-V\Virtual Hard Disks\"
    UnattendPath = "$PSScriptRoot"+"\autounattend.xml"
    GPUName = "AUTO"
    GPUResourceAllocationPercentage = 50
    Team_ID = ""
    Key = ""
    Username = "GPUVM"
    Password = "CoolestPassword!"
    Autologon = "true"
}

Import-Module $PSSCriptRoot\Add-VMGpuPartitionAdapterFiles.psm1

function Is-Administrator  
{  
    $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent();
    (New-Object Security.Principal.WindowsPrincipal $CurrentUser).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)  
}


Function PowerISO-Mount-ISO {
param (
[string]$SourcePath
)
    #PowerISO command line docs: https://poweriso.com/tutorials/command-line-argus.htm
    #We will use Power ISO exclusively, and we will use only 1 virtual drive (Not strictly necessary, just to keep script simple and fast)
    Start-Process -NoNewWindow -FilePath $params.pisoPath -ArgumentList "unmount all"
    Start-Process -NoNewWindow -FilePath $params.pisoPath -ArgumentList "setvdnum 1"

    $pisoPath=$params.pisoPath
    $listvdOutput = & "$pisoPath" "listvd"
    # Find the first drive that is free (contains "<No media>")
    $freeDrive = $null
    foreach ($line in $listvdOutput) {
        if ($line -match "Drive \[([A-Z]):\] <No media>") {
            $freeDrive = $matches[1]
        }
    }

    if (-not $freeDrive) {
        return
    }

    # Mount the ISO to the free drive
    $mountCommand = & "$pisoPath" mount "$SourcePath" "${freeDrive}:"
    if ($mountCommand -like "*successfully*") {
        Write-Output "${freeDrive}"
    } else {
        Write-Output "Failed to mount the ISO."
    }
}

Function Dismount-ISO {
Start-Process -NoNewWindow -FilePath $params.pisoPath -ArgumentList "unmount all"
}


Function ConcatenateVHDPath {
param(
[string]$VHDPath,
[string]$VMName
)
if ($VHDPath[-1] -eq '\') {
    $VHDPath + $VMName + ".vhdx"
    }
Else {
    $VHDPath + "\" +  $VMName + ".vhdx"
    }
}

Function SmartExit {
param (
[switch]$NoHalt,
[string]$ExitReason
)
if (($host.name -eq 'Windows PowerShell ISE Host') -or ($host.Name -eq 'Visual Studio Code Host')) {
    Write-Host $ExitReason
    Exit
    }
else{
    if ($NoHalt) {
        Write-Host $ExitReason
        Exit
        }
    else {
        Write-Host $ExitReason
        Read-host -Prompt "Press any key to Exit..."
        Exit
        }
    }
}

Function Check-Params {

$ExitReason = @()

if ([ENVIRONMENT]::Is64BitProcess -eq $false) {
    $ExitReason += "You are not using the correct version of Powershell, do not use Powershell(x86)."
    }
if ((Is-Administrator) -eq $false) {
    $ExitReason += "Script not running as Administrator, please run script as Administrator."
    }
if (!(Test-Path $params.VHDPath)) {
    $ExitReason += "VHDPath Directory doesn't exist, please create it before running this script."
    }
if (!(test-path $params.SourcePath)) {
    $ExitReason += "ISO Path Invalid. Please enter a valid ISO Path in the SourcePath section of Params."
    }
else {
    $ISODriveLetter = PowerISO-Mount-ISO -SourcePath $params.SourcePath
    if (!(Test-Path $("$ISODriveLetter"+":\Sources\install.wim"))) {
        $ExitReason += "This ISO is invalid, please check readme for ISO downloading instructions."
        }
    Dismount-ISO
    }
if ($params.Username -eq $params.VMName ) {
    $ExitReason += "Username cannot be the same as VMName."
    }
if (!($params.Username -match "^[a-zA-Z0-9]+$")) {
    $ExitReason += "Username cannot contain special characters."
    }
if (($params.VMName -notmatch "^[a-zA-Z0-9]+$") -or ($params.VMName.Length -gt 15)) {
    $ExitReason += "VMName cannot contain special characters, or be more than 15 characters long"
    }
if (([Environment]::OSVersion.Version.Build -lt 22000) -and ($params.GPUName -ne "AUTO")) {
    $ExitReason += "GPUName must be set to AUTO on Windows 10."
    }
If ($ExitReason.Count -gt 0) {
    Write-Host "Script failed params check due to the following reasons:" -ForegroundColor DarkYellow
    ForEach ($IndividualReason in $ExitReason) {
        Write-Host "ERROR: $IndividualReason" -ForegroundColor RED
        }
    SmartExit
    }
}

Function Setup-Install {
param(
[string]$DriveLetter,
[string]$Team_ID,
[string]$Key
)
    $new = @()

    $content = get-content "$PSScriptRoot\user\psscripts.ini" 

    foreach ($line in $content) {
        if ($line -like "0Parameters="){
            $line = "0Parameters=$Team_ID $Key"
            $new += $line
            }
        Else {
            $new += $line
            }
    }
    Set-Content -Value $new -Path "$PSScriptRoot\user\psscripts.ini"
    if((Test-Path -Path $DriveLetter\Windows\system32\GroupPolicy\User\Scripts\Logon) -eq $true) {} Else {New-Item -Path $DriveLetter\Windows\system32\GroupPolicy\User\Scripts\Logon -ItemType directory | Out-Null}
    if((Test-Path -Path $DriveLetter\Windows\system32\GroupPolicy\User\Scripts\Logoff) -eq $true) {} Else {New-Item -Path $DriveLetter\Windows\system32\GroupPolicy\User\Scripts\Logoff -ItemType directory | Out-Null}
    if((Test-Path -Path $DriveLetter\ProgramData\Easy-GPU-P) -eq $true) {} Else {New-Item -Path $DriveLetter\ProgramData\Easy-GPU-P -ItemType directory | Out-Null}
    Copy-Item -Path $psscriptroot\VMScripts\VBCableInstall.ps1 -Destination $DriveLetter\ProgramData\Easy-GPU-P
    Copy-Item -Path $psscriptroot\gpt.ini -Destination $DriveLetter\Windows\system32\GroupPolicy
    Copy-Item -Path $psscriptroot\User\psscripts.ini -Destination $DriveLetter\Windows\system32\GroupPolicy\User\Scripts
    Copy-Item -Path $psscriptroot\User\Install.ps1 -Destination $DriveLetter\Windows\system32\GroupPolicy\User\Scripts\Logon
}

function Convert-WindowsImage {
    <#
    .NOTES
        Copyright (c) Microsoft Corporation.  All rights reserved.

        Use of this sample source code is subject to the terms of the Microsoft
        license agreement under which you licensed this sample source code. If
        you did not accept the terms of the license agreement, you are not
        authorized to use this sample source code. For the terms of the license,
        please see the license agreement between you and Microsoft or, if applicable,
        see the LICENSE.RTF on your install media or the root of your tools installation.
        THE SAMPLE SOURCE CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

    .SYNOPSIS
        Creates a bootable VHD(X) based on Windows 7 or Windows 8 installation media.

    .DESCRIPTION
        Creates a bootable VHD(X) based on Windows 7 or Windows 8 installation media.

    .PARAMETER SourcePath
        The complete path to the WIM or ISO file that will be converted to a Virtual Hard Disk.
        The ISO file must be valid Windows installation media to be recognized successfully.

    .PARAMETER CacheSource
        If the source WIM/ISO was copied locally, we delete it by default.
        Pass $true to cache the source image from the temp directory.

    .PARAMETER VHDPath
        The name and path of the Virtual Hard Disk to create.
        Omitting this parameter will create the Virtual Hard Disk is the current directory, (or,
        if specified by the -WorkingDirectory parameter, the working directory) and will automatically
        name the file in the following format:

        <build>.<revision>.<architecture>.<branch>.<timestamp>_<skufamily>_<sku>_<language>.<extension>
        i.e.:
        9200.0.amd64fre.winmain_win8rtm.120725-1247_client_professional_en-us.vhd(x)

    .PARAMETER WorkingDirectory
        Specifies the directory where the VHD(X) file should be generated.
        If specified along with -VHDPath, the -WorkingDirectory value is ignored.
        The default value is the current directory ($pwd).

    .PARAMETER TempDirectory
        Specifies the directory where the logs and ISO files should be placed.
        The default value is the temp directory ($env:Temp).

    .PARAMETER SizeBytes
        The size of the Virtual Hard Disk to create.
        For fixed disks, the VHD(X) file will be allocated all of this space immediately.
        For dynamic disks, this will be the maximum size that the VHD(X) can grow to.
        The default value is 40GB.

    .PARAMETER VHDFormat
        Specifies whether to create a VHD or VHDX formatted Virtual Hard Disk.
        The default is AUTO, which will create a VHD if using the BIOS disk layout or
        VHDX if using UEFI or WindowsToGo layouts.

    .PARAMETER DiskLayout
        Specifies whether to build the image for BIOS (MBR), UEFI (GPT), or WindowsToGo (MBR).
        Generation 1 VMs require BIOS (MBR) images.  Generation 2 VMs require UEFI (GPT) images.
        Windows To Go images will boot in UEFI or BIOS but are not technically supported (upgrade
        doesn't work)

    .PARAMETER UnattendPath
        The complete path to an unattend.xml file that can be injected into the VHD(X).

    .PARAMETER Edition
        The name or image index of the image to apply from the WIM.

    .PARAMETER Passthru
        Specifies that the full path to the VHD(X) that is created should be
        returned on the pipeline.

    .PARAMETER BCDBoot
        By default, the version of BCDBOOT.EXE that is present in \Windows\System32
        is used by Convert-WindowsImage.  If you need to specify an alternate version,
        use this parameter to do so.

    .PARAMETER MergeFolder
        Specifies additional MergeFolder path to be added to the root of the VHD(X)

    .PARAMETER BCDinVHD
        Specifies the purpose of the VHD(x). Use NativeBoot to skip cration of BCD store
        inside the VHD(x). Use VirtualMachine (or do not specify this option) to ensure
        the BCD store is created inside the VHD(x).

    .PARAMETER Driver
        Full path to driver(s) (.inf files) to inject to the OS inside the VHD(x).

    .PARAMETER ExpandOnNativeBoot
        Specifies whether to expand the VHD(x) to its maximum suze upon native boot.
        The default is True. Set to False to disable expansion.

    .PARAMETER RemoteDesktopEnable
        Enable Remote Desktop to connect to the OS inside the VHD(x) upon provisioning.
        Does not include Windows Firewall rules (firewall exceptions). The default is False.

    .PARAMETER Feature
        Enables specified Windows Feature(s). Note that you need to specify the Internal names
        understood by DISM and DISM CMDLets (e.g. NetFx3) instead of the "Friendly" names
        from Server Manager CMDLets (e.g. NET-Framework-Core).

    .PARAMETER Package
        Injects specified Windows Package(s). Accepts path to either a directory or individual
        CAB or MSU file.

    .PARAMETER ShowUI
        Specifies that the Graphical User Interface should be displayed.

    .PARAMETER EnableDebugger
        Configures kernel debugging for the VHD(X) being created.
        EnableDebugger takes a single argument which specifies the debugging transport to use.
        Valid transports are: None, Serial, 1394, USB, Network, Local.

        Depending on the type of transport selected, additional configuration parameters will become
        available.

        Serial:
            -ComPort   - The COM port number to use while communicating with the debugger.
                         The default value is 1 (indicating COM1).
            -BaudRate  - The baud rate (in bps) to use while communicating with the debugger.
                         The default value is 115200, valid values are:
                         9600, 19200, 38400, 56700, 115200

        1394:
            -Channel   - The 1394 channel used to communicate with the debugger.
                         The default value is 10.

        USB:
            -Target    - The target name used for USB debugging.
                         The default value is "debugging".

        Network:
            -IPAddress - The IP address of the debugging host computer.
            -Port      - The port on which to connect to the debugging host.
                         The default value is 50000, with a minimum value of 49152.
            -Key       - The key used to encrypt the connection.  Only [0-9] and [a-z] are allowed.
            -nodhcp    - Prevents the use of DHCP to obtain the target IP address.
            -newkey    - Specifies that a new encryption key should be generated for the connection.

    .PARAMETER DismPath
        Full Path to an alternative version of the Dism.exe tool. The default is the current OS version.

    .PARAMETER ApplyEA
        Specifies that any EAs captured in the WIM should be applied to the VHD.
        The default is False.

    .EXAMPLE
        .\Convert-WindowsImage.ps1 -SourcePath D:\foo\install.wim -Edition Professional -WorkingDirectory D:\foo

        This command will create a 40GB dynamically expanding VHD in the D:\foo folder.
        The VHD will be based on the Professional edition from D:\foo\install.wim,
        and will be named automatically.

    .EXAMPLE
        .\Convert-WindowsImage.ps1 -SourcePath D:\foo\Win7SP1.iso -Edition Ultimate -VHDPath D:\foo\Win7_Ultimate_SP1.vhd

        This command will parse the ISO file D:\foo\Win7SP1.iso and try to locate
        \sources\install.wim.  If that file is found, it will be used to create a
        dynamically-expanding 40GB VHD containing the Ultimate SKU, and will be
        named D:\foo\Win7_Ultimate_SP1.vhd

    .EXAMPLE
        .\Convert-WindowsImage.ps1 -SourcePath D:\foo\install.wim -Edition Professional -EnableDebugger Serial -ComPort 2 -BaudRate 38400

        This command will create a VHD from D:\foo\install.wim of the Professional SKU.
        Serial debugging will be enabled in the VHD via COM2 at a baud rate of 38400bps.

    .OUTPUTS
        System.IO.FileInfo
    #>
    [CmdletBinding(DefaultParameterSetName="SRC",
        HelpURI="https://github.com/Microsoft/Virtualization-Documentation/tree/master/hyperv-tools/Convert-WindowsImage")]

    param(
        [Parameter(ParameterSetName="SRC", Mandatory=$true, ValueFromPipeline=$true)]
        [Alias("WIM")]
        [string]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $(Resolve-Path $_) })]
        $SourcePath,

        [Parameter(ParameterSetName="SRC")]
        [Alias("DriveLetter")]
        [string]
        [ValidateNotNullOrEmpty()]
        [string]$ISODriveLetter,

        [Parameter(ParameterSetName="SRC")]
        [Alias("GPU")]
        [string]
        [ValidateNotNullOrEmpty()]
        [string]$GPUName,

        [Parameter(ParameterSetName="SRC")]
        [Alias("TeamID")]
        [string]
        #[ValidateNotNullOrEmpty()]
        [string]$Team_ID,

        [Parameter(ParameterSetName="SRC")]
        [Alias("Teamkey")]
        [string]
        #[ValidateNotNullOrEmpty()]
        [string]$Key,

        [Parameter(ParameterSetName="SRC")]
        [switch]
        $CacheSource = $false,

        [Parameter(ParameterSetName="SRC")]
        [Alias("SKU")]
        [string[]]
        [ValidateNotNullOrEmpty()]
        $Edition,

        [Parameter(ParameterSetName="SRC")]
        [Alias("WorkDir")]
        [string]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $_ })]
        $WorkingDirectory = $pwd,

        [Parameter(ParameterSetName="SRC")]
        [Alias("TempDir")]
        [string]
        [ValidateNotNullOrEmpty()]
        $TempDirectory = $env:Temp,

        [Parameter(ParameterSetName="SRC")]
        [Alias("VHD")]
        [string]
        [ValidateNotNullOrEmpty()]
        $VHDPath,

        [Parameter(ParameterSetName="SRC")]
        [Alias("Size")]
        [UInt64]
        [ValidateNotNullOrEmpty()]
        [ValidateRange(512MB, 64TB)]
        $SizeBytes = 25GB,

        [Parameter(ParameterSetName="SRC")]
        [Alias("Format")]
        [string]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("VHD", "VHDX", "AUTO")]
        $VHDFormat = "AUTO",

        [Parameter(ParameterSetName="SRC")]
        [Alias("MergeFolder")]
        [string]
        [ValidateNotNullOrEmpty()]
        $MergeFolderPath = "",

        [Parameter(ParameterSetName="SRC", Mandatory=$true)]
        [Alias("Layout")]
        [string]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("BIOS", "UEFI", "WindowsToGo")]
        $DiskLayout,

        [Parameter(ParameterSetName="SRC")]
        [string]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("NativeBoot", "VirtualMachine")]
        $BCDinVHD = "VirtualMachine",

        [Parameter(ParameterSetName="SRC")]
        [Parameter(ParameterSetName="UI")]
        [string]
        $BCDBoot = "bcdboot.exe",

        [Parameter(ParameterSetName="SRC")]
        [Parameter(ParameterSetName="UI")]
        [string]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("None", "Serial", "1394", "USB", "Local", "Network")]
        $EnableDebugger = "None",

        [Parameter(ParameterSetName="SRC")]
        [string[]]
        [ValidateNotNullOrEmpty()]
        $Feature,

        [Parameter(ParameterSetName="SRC")]
        [string[]]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $(Resolve-Path $_) })]
        $Driver,

        [Parameter(ParameterSetName="SRC")]
        [string[]]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $(Resolve-Path $_) })]
        $Package,

        [Parameter(ParameterSetName="SRC")]
        [switch]
        $ExpandOnNativeBoot = $true,

        [Parameter(ParameterSetName="SRC")]
        [switch]
        $RemoteDesktopEnable = $false,

        [Parameter(ParameterSetName="SRC")]
        [Alias("Unattend")]
        [string]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $(Resolve-Path $_) })]
        $UnattendPath,

        [Parameter(ParameterSetName="SRC")]
        [Parameter(ParameterSetName="UI")]
        [switch]
        $Passthru,

        [Parameter(ParameterSetName="SRC")]
        [string]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path $(Resolve-Path $_) })]
        $DismPath,

        [Parameter(ParameterSetName="SRC")]
        [switch]
        $ApplyEA = $false,

        [Parameter(ParameterSetName="UI")]
        [switch]
        $ShowUI
    )
    #region Code

    # Begin Dynamic Parameters
    # Create the parameters for the various types of debugging.
    DynamicParam
    {
        #Set-StrictMode -version 3

        # Set up the dynamic parameters.
        # Dynamic parameters are only available if certain conditions are met, so they'll only show up
        # as valid parameters when those conditions apply.  Here, the conditions are based on the value of
        # the EnableDebugger parameter.  Depending on which of a set of values is the specified argument
        # for EnableDebugger, different parameters will light up, as outlined below.

        $parameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

        if (!(Test-Path Variable:Private:EnableDebugger))
        {
            return $parameterDictionary
        }

        switch ($EnableDebugger)
        {
            "Serial"
            {
                #region ComPort

                $ComPortAttr                   = New-Object System.Management.Automation.ParameterAttribute
                $ComPortAttr.ParameterSetName  = "__AllParameterSets"
                $ComPortAttr.Mandatory         = $false

                $ComPortValidator              = New-Object System.Management.Automation.ValidateRangeAttribute(
                                                    1,
                                                    10   # Is that a good maximum?
                                                 )

                $ComPortNotNull                = New-Object System.Management.Automation.ValidateNotNullOrEmptyAttribute

                $ComPortAttrCollection         = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
                $ComPortAttrCollection.Add($ComPortAttr)
                $ComPortAttrCollection.Add($ComPortValidator)
                $ComPortAttrCollection.Add($ComPortNotNull)

                $ComPort                       = New-Object System.Management.Automation.RuntimeDefinedParameter(
                                                    "ComPort",
                                                    [UInt16],
                                                    $ComPortAttrCollection
                                                 )

                # By default, use COM1
                $ComPort.Value                 = 1
                $parameterDictionary.Add("ComPort", $ComPort)
                #endregion ComPort

                #region BaudRate
                $BaudRateAttr                  = New-Object System.Management.Automation.ParameterAttribute
                $BaudRateAttr.ParameterSetName = "__AllParameterSets"
                $BaudRateAttr.Mandatory        = $false

                $BaudRateValidator             = New-Object System.Management.Automation.ValidateSetAttribute(
                                                    9600, 19200,38400, 57600, 115200
                                                 )

                $BaudRateNotNull               = New-Object System.Management.Automation.ValidateNotNullOrEmptyAttribute

                $BaudRateAttrCollection        = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
                $BaudRateAttrCollection.Add($BaudRateAttr)
                $BaudRateAttrCollection.Add($BaudRateValidator)
                $BaudRateAttrCollection.Add($BaudRateNotNull)

                $BaudRate                      = New-Object System.Management.Automation.RuntimeDefinedParameter(
                                                     "BaudRate",
                                                     [UInt32],
                                                     $BaudRateAttrCollection
                                                 )

                # By default, use 115,200.
                $BaudRate.Value                = 115200
                $parameterDictionary.Add("BaudRate", $BaudRate)
                #endregion BaudRate

                break
            }

            "1394"
            {
                $ChannelAttr                   = New-Object System.Management.Automation.ParameterAttribute
                $ChannelAttr.ParameterSetName  = "__AllParameterSets"
                $ChannelAttr.Mandatory         = $false

                $ChannelValidator              = New-Object System.Management.Automation.ValidateRangeAttribute(
                                                    0,
                                                    62
                                                 )

                $ChannelNotNull                = New-Object System.Management.Automation.ValidateNotNullOrEmptyAttribute

                $ChannelAttrCollection         = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
                $ChannelAttrCollection.Add($ChannelAttr)
                $ChannelAttrCollection.Add($ChannelValidator)
                $ChannelAttrCollection.Add($ChannelNotNull)

                $Channel                       = New-Object System.Management.Automation.RuntimeDefinedParameter(
                                                     "Channel",
                                                     [UInt16],
                                                     $ChannelAttrCollection
                                                 )

                # By default, use channel 10
                $Channel.Value                 = 10
                $parameterDictionary.Add("Channel", $Channel)
                break
            }

            "USB"
            {
                $TargetAttr                    = New-Object System.Management.Automation.ParameterAttribute
                $TargetAttr.ParameterSetName   = "__AllParameterSets"
                $TargetAttr.Mandatory          = $false

                $TargetNotNull                 = New-Object System.Management.Automation.ValidateNotNullOrEmptyAttribute

                $TargetAttrCollection          = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
                $TargetAttrCollection.Add($TargetAttr)
                $TargetAttrCollection.Add($TargetNotNull)

                $Target                        = New-Object System.Management.Automation.RuntimeDefinedParameter(
                                                     "Target",
                                                     [string],
                                                     $TargetAttrCollection
                                                 )

                # By default, use target = "debugging"
                $Target.Value                  = "Debugging"
                $parameterDictionary.Add("Target", $Target)
                break
            }

            "Network"
            {
                #region IP
                $IpAttr                        = New-Object System.Management.Automation.ParameterAttribute
                $IpAttr.ParameterSetName       = "__AllParameterSets"
                $IpAttr.Mandatory              = $true

                $IpValidator                   = New-Object System.Management.Automation.ValidatePatternAttribute(
                                                    "\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"
                                                 )
                $IpNotNull                     = New-Object System.Management.Automation.ValidateNotNullOrEmptyAttribute

                $IpAttrCollection              = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
                $IpAttrCollection.Add($IpAttr)
                $IpAttrCollection.Add($IpValidator)
                $IpAttrCollection.Add($IpNotNull)

                $IP                            = New-Object System.Management.Automation.RuntimeDefinedParameter(
                                                     "IPAddress",
                                                     [string],
                                                     $IpAttrCollection
                                                 )

                # There's no good way to set a default value for this.
                $parameterDictionary.Add("IPAddress", $IP)
                #endregion IP

                #region Port
                $PortAttr                      = New-Object System.Management.Automation.ParameterAttribute
                $PortAttr.ParameterSetName     = "__AllParameterSets"
                $PortAttr.Mandatory            = $false

                $PortValidator                 = New-Object System.Management.Automation.ValidateRangeAttribute(
                                                    49152,
                                                    50039
                                                 )

                $PortNotNull                   = New-Object System.Management.Automation.ValidateNotNullOrEmptyAttribute

                $PortAttrCollection            = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
                $PortAttrCollection.Add($PortAttr)
                $PortAttrCollection.Add($PortValidator)
                $PortAttrCollection.Add($PortNotNull)


                $Port                          = New-Object System.Management.Automation.RuntimeDefinedParameter(
                                                     "Port",
                                                     [UInt16],
                                                     $PortAttrCollection
                                                 )

                # By default, use port 50000
                $Port.Value                    = 50000
                $parameterDictionary.Add("Port", $Port)
                #endregion Port

                #region Key
                $KeyAttr                       = New-Object System.Management.Automation.ParameterAttribute
                $KeyAttr.ParameterSetName      = "__AllParameterSets"
                $KeyAttr.Mandatory             = $true

                $KeyValidator                  = New-Object System.Management.Automation.ValidatePatternAttribute(
                                                    "\b([A-Z0-9]+).([A-Z0-9]+).([A-Z0-9]+).([A-Z0-9]+)\b"
                                                 )

                $KeyNotNull                    = New-Object System.Management.Automation.ValidateNotNullOrEmptyAttribute

                $KeyAttrCollection             = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
                $KeyAttrCollection.Add($KeyAttr)
                $KeyAttrCollection.Add($KeyValidator)
                $KeyAttrCollection.Add($KeyNotNull)

                $Key                           = New-Object System.Management.Automation.RuntimeDefinedParameter(
                                                     "Key",
                                                     [string],
                                                     $KeyAttrCollection
                                                 )

                # Don't set a default key.
                $parameterDictionary.Add("Key", $Key)
                #endregion Key

                #region NoDHCP
                $NoDHCPAttr                    = New-Object System.Management.Automation.ParameterAttribute
                $NoDHCPAttr.ParameterSetName   = "__AllParameterSets"
                $NoDHCPAttr.Mandatory          = $false

                $NoDHCPAttrCollection          = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
                $NoDHCPAttrCollection.Add($NoDHCPAttr)

                $NoDHCP                        = New-Object System.Management.Automation.RuntimeDefinedParameter(
                                                     "NoDHCP",
                                                     [switch],
                                                     $NoDHCPAttrCollection
                                                 )

                $parameterDictionary.Add("NoDHCP", $NoDHCP)
                #endregion NoDHCP

                #region NewKey
                $NewKeyAttr                    = New-Object System.Management.Automation.ParameterAttribute
                $NewKeyAttr.ParameterSetName   = "__AllParameterSets"
                $NewKeyAttr.Mandatory          = $false

                $NewKeyAttrCollection          = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
                $NewKeyAttrCollection.Add($NewKeyAttr)

                $NewKey                        = New-Object System.Management.Automation.RuntimeDefinedParameter(
                                                     "NewKey",
                                                     [switch],
                                                     $NewKeyAttrCollection
                                                 )

                # Don't set a default key.
                $parameterDictionary.Add("NewKey", $NewKey)
                #endregion NewKey

                break
            }

            # There's nothing to do for local debugging.
            # Synthetic debugging is not yet implemented.

            default
            {
               break
            }
        }

        return $parameterDictionary
    }

    Begin
    {
        ##########################################################################################
        #                             Constants and Pseudo-Constants
        ##########################################################################################
        $PARTITION_STYLE_MBR    = 0x00000000                                   # The default value
        $PARTITION_STYLE_GPT    = 0x00000001                                   # Just in case...

        # Version information that can be populated by timebuild.
        $ScriptVersion = DATA
        {
    ConvertFrom-StringData -StringData @"
        Major     = 10
        Minor     = 0
        Build     = 14278
        Qfe       = 1000
        Branch    = rs1_es_media
        Timestamp = 160201-1707
        Flavor    = amd64fre
"@
}

        $myVersion              = "$($ScriptVersion.Major).$($ScriptVersion.Minor).$($ScriptVersion.Build).$($ScriptVersion.QFE).$($ScriptVersion.Flavor).$($ScriptVersion.Branch).$($ScriptVersion.Timestamp)"
        $scriptName             = "Convert-WindowsImage"                       # Name of the script, obviously.
        $sessionKey             = [Guid]::NewGuid().ToString()                 # Session key, used for keeping records unique between multiple runs.
        $logFolder              = "$($TempDirectory)\$($scriptName)\$($sessionKey)" # Log folder path.
        $vhdMaxSize             = 2040GB                                       # Maximum size for VHD is ~2040GB.
        $vhdxMaxSize            = 64TB                                         # Maximum size for VHDX is ~64TB.
        $lowestSupportedVersion = New-Object Version "6.1"                     # The lowest supported *image* version; making sure we don't run against Vista/2k8.
        $lowestSupportedBuild   = 9200                                         # The lowest supported *host* build.  Set to Win8 CP.
        $transcripting          = $false

        # Since we use the VHDFormat in output, make it uppercase.
        # We'll make it lowercase again when we use it as a file extension.
        $VHDFormat              = $VHDFormat.ToUpper()
        ##########################################################################################
        #                                      Here Strings
        ##########################################################################################

        # Banner text displayed during each run.
        $header    = @"

Windows(R) Image to Virtual Hard Disk Converter for Windows(R) 10
Copyright (C) Microsoft Corporation.  All rights reserved.
Version $myVersion

"@

        # Text used as the banner in the UI.
        $uiHeader  = @"
You can use the fields below to configure the VHD or VHDX that you want to create!
"@

        #region Helper Functions

        ##########################################################################################
        #                                   Helper Functions
        ##########################################################################################

        <#
            Functions to mount and dismount registry hives.
            These hives will automatically be accessible via the HKLM:\ registry PSDrive.

            It should be noted that I have more confidence in using the RegLoadKey and
            RegUnloadKey Win32 APIs than I do using REG.EXE - it just seems like we should
            do things ourselves if we can, instead of using yet another binary.

            Consider this a TODO for future versions.
        #>
        Function Mount-RegistryHive
        {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
                [System.IO.FileInfo]
                [ValidateNotNullOrEmpty()]
                [ValidateScript({ $_.Exists })]
                $Hive
            )

            $mountKey = [System.Guid]::NewGuid().ToString()
            $regPath  = "REG.EXE"

            if (Test-Path HKLM:\$mountKey)
            {
                throw "The registry path already exists.  I should just regenerate it, but I'm lazy."
            }

            $regArgs = (
                "LOAD",
                "HKLM\$mountKey",
                $Hive.Fullname
            )
            try
            {

                Run-Executable -Executable $regPath -Arguments $regArgs

            }
            catch
            {
                throw
            }

            # Set a global variable containing the name of the mounted registry key
            # so we can unmount it if there's an error.
            $global:mountedHive = $mountKey

            return $mountKey
        }

        ##########################################################################################

        Function Dismount-RegistryHive
        {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
                [string]
                [ValidateNotNullOrEmpty()]
                $HiveMountPoint
            )

            $regPath = "REG.EXE"

            $regArgs = (
                "UNLOAD",
                "HKLM\$($HiveMountPoint)"
            )

            Run-Executable -Executable $regPath -Arguments $regArgs

            $global:mountedHive = $null
        }

        ##########################################################################################

        function
        Test-Admin
        {
            <#
                .SYNOPSIS
                    Short function to determine whether the logged-on user is an administrator.

                .EXAMPLE
                    Do you honestly need one?  There are no parameters!

                .OUTPUTS
                    $true if user is admin.
                    $false if user is not an admin.
            #>
            [CmdletBinding()]
            param()

            $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
            $isAdmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
            Write-W2VTrace "isUserAdmin? $isAdmin"

            return $isAdmin
        }

        ##########################################################################################

        function
        Get-WindowsBuildNumber
        {
            $os = Get-WmiObject -Class Win32_OperatingSystem
            return [int]($os.BuildNumber)
        }

        ##########################################################################################

        function
        Test-WindowsVersion
        {
            $isWin8 = ((Get-WindowsBuildNumber) -ge [int]$lowestSupportedBuild)

            Write-W2VTrace "is Windows 8 or Higher? $isWin8"
            return $isWin8
        }

        ##########################################################################################

        function
        Write-W2VInfo
        {
        # Function to make the Write-Host output a bit prettier.
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [string]
                [ValidateNotNullOrEmpty()]
                $text
            )
            Write-Host "INFO   : $($text)"
        }

        ##########################################################################################

        function
        Write-W2VTrace
        {
        # Function to make the Write-Verbose output... well... exactly the same as it was before.
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [string]
                [ValidateNotNullOrEmpty()]
                $text
            )
            Write-Verbose $text
        }

        ##########################################################################################

        function
        Write-W2VError
        {
        # Function to make the Write-Host (NOT Write-Error) output prettier in the case of an error.
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [string]
                [ValidateNotNullOrEmpty()]
                $text
            )
            Write-Host "ERROR  : $($text)"
        }

        ##########################################################################################

        function
        Write-W2VWarn
        {
        # Function to make the Write-Host (NOT Write-Warning) output prettier.
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
                [string]
                [ValidateNotNullOrEmpty()]
                $text
            )
            Write-Host "WARN   : $($text)" -ForegroundColor (Get-Host).PrivateData.WarningForegroundColor
        }

        ##########################################################################################

        function
        Run-Executable
        {
            <#
                .SYNOPSIS
                    Runs an external executable file, and validates the error level.

                .PARAMETER Executable
                    The path to the executable to run and monitor.

                .PARAMETER Arguments
                    An array of arguments to pass to the executable when it's executed.

                .PARAMETER SuccessfulErrorCode
                    The error code that means the executable ran successfully.
                    The default value is 0.
            #>

            [CmdletBinding()]
            param(
                [Parameter(Mandatory=$true)]
                [string]
                [ValidateNotNullOrEmpty()]
                $Executable,

                [Parameter(Mandatory=$true)]
                [string[]]
                [ValidateNotNullOrEmpty()]
                $Arguments,

                [Parameter()]
                [int]
                [ValidateNotNullOrEmpty()]
                $SuccessfulErrorCode = 0

            )

            Write-W2VTrace "Running $Executable $Arguments"
            $ret = Start-Process           `
                -FilePath $Executable      `
                -ArgumentList $Arguments   `
                -NoNewWindow               `
                -Wait                      `
                -RedirectStandardOutput "$($TempDirectory)\$($scriptName)\$($sessionKey)\$($Executable)-StandardOutput.txt" `
                -RedirectStandardError  "$($TempDirectory)\$($scriptName)\$($sessionKey)\$($Executable)-StandardError.txt"  `
                -Passthru

            Write-W2VTrace "Return code was $($ret.ExitCode)."

            if ($ret.ExitCode -ne $SuccessfulErrorCode)
            {
                throw "$Executable failed with code $($ret.ExitCode)!"
            }
        }

        ##########################################################################################
        Function Test-IsNetworkLocation
        {
            <#
                .SYNOPSIS
                    Determines whether or not a given path is a network location or a local drive.

                .DESCRIPTION
                    Function to determine whether or not a specified path is a local path, a UNC path,
                    or a mapped network drive.

                .PARAMETER Path
                    The path that we need to figure stuff out about,
            #>

            [CmdletBinding()]
            param(
                [Parameter(ValueFromPipeLine = $true)]
                [string]
                [ValidateNotNullOrEmpty()]
                $Path
            )

            $result = $false

            if ([bool]([URI]$Path).IsUNC)
            {
                $result = $true
            }
            else
            {
                $driveInfo = [IO.DriveInfo]((Resolve-Path $Path).Path)

                if ($driveInfo.DriveType -eq "Network")
                {
                    $result = $true
                }
            }

            return $result
        }
        ##########################################################################################

        #endregion Helper Functions
    }

    Process
    {
        Write-Host $header
        
        $disk           = $null
        $openWim        = $null
        $openIso        = $null
        $openImage      = $null
        $vhdFinalName   = $null
        $vhdFinalPath   = $null
        $mountedHive    = $null
        $isoPath        = $null
        $tempSource     = $null

        if (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)
        {
            try
            {
                $hyperVEnabled  = $((Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V).State -eq "Enabled")
            }
            catch
            {
                # WinPE DISM does not support online queries.  This will throw on non-WinPE machines
                $winpeVersion = (Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\WinPE').Version

                Write-W2VInfo "Running WinPE version $winpeVersion"

                $hyperVEnabled = $false
            }
        }
        else
        {
            $hyperVEnabled = $false
        }

        $vhd            = @()

        try
        {
            # Create log folder
            if (Test-Path $logFolder)
            {
                $null = rd $logFolder -Force -Recurse
            }

            $null = md $logFolder -Force

            # Try to start transcripting.  If it's already running, we'll get an exception and swallow it.
            try
            {
                $null = Start-Transcript -Path (Join-Path $logFolder "Convert-WindowsImageTranscript.txt") -Force -ErrorAction SilentlyContinue
                $transcripting = $true
            }
            catch
            {
                Write-W2VWarn "Transcription is already running.  No Convert-WindowsImage-specific transcript will be created."
                $transcripting = $false
            }

            #
            # Add types
            #
            Add-WindowsImageTypes

            # Check to make sure we're running as Admin.
            if (!(Test-Admin))
            {
                throw "Images can only be applied by an administrator.  Please launch PowerShell elevated and run this script again."
            }

            # Check to make sure we're running on Win8.
            if (!(Test-WindowsVersion))
            {
                throw "$scriptName requires Windows 8 Consumer Preview or higher.  Please use WIM2VHD.WSF (http://code.msdn.microsoft.com/wim2vhd) if you need to create VHDs from Windows 7."
            }

            # Resolve the path for the unattend file.
            if (![string]::IsNullOrEmpty($UnattendPath))
            {
                $UnattendPath = (Resolve-Path $UnattendPath).Path
            }

            if ($ShowUI)
            {

                Write-W2VInfo "Launching UI..."
                Add-Type -AssemblyName System.Drawing,System.Windows.Forms

                #region Form Objects
                $frmMain                = New-Object System.Windows.Forms.Form
                $groupBox4              = New-Object System.Windows.Forms.GroupBox
                $btnGo                  = New-Object System.Windows.Forms.Button
                $groupBox3              = New-Object System.Windows.Forms.GroupBox
                $txtVhdName             = New-Object System.Windows.Forms.TextBox
                $label6                 = New-Object System.Windows.Forms.Label
                $btnWrkBrowse           = New-Object System.Windows.Forms.Button
                $cmbVhdSizeUnit         = New-Object System.Windows.Forms.ComboBox
                $numVhdSize             = New-Object System.Windows.Forms.NumericUpDown
                $cmbVhdFormat           = New-Object System.Windows.Forms.ComboBox
                $label5                 = New-Object System.Windows.Forms.Label
                $txtWorkingDirectory    = New-Object System.Windows.Forms.TextBox
                $label4                 = New-Object System.Windows.Forms.Label
                $label3                 = New-Object System.Windows.Forms.Label
                $label2                 = New-Object System.Windows.Forms.Label
                $label7                 = New-Object System.Windows.Forms.Label
                $txtUnattendFile        = New-Object System.Windows.Forms.TextBox
                $btnUnattendBrowse      = New-Object System.Windows.Forms.Button
                $groupBox2              = New-Object System.Windows.Forms.GroupBox
                $cmbSkuList             = New-Object System.Windows.Forms.ComboBox
                $label1                 = New-Object System.Windows.Forms.Label
                $groupBox1              = New-Object System.Windows.Forms.GroupBox
                $txtSourcePath          = New-Object System.Windows.Forms.TextBox
                $btnBrowseWim           = New-Object System.Windows.Forms.Button
                $openFileDialog1        = New-Object System.Windows.Forms.OpenFileDialog
                $openFolderDialog1      = New-Object System.Windows.Forms.FolderBrowserDialog
                $InitialFormWindowState = New-Object System.Windows.Forms.FormWindowState

                #endregion Form Objects

                #region Event scriptblocks.

                $btnGo_OnClick                          = {
                    $frmMain.Close()
                }

                $btnWrkBrowse_OnClick                   = {
                    $openFolderDialog1.RootFolder       = "Desktop"
                    $openFolderDialog1.Description      = "Select the folder you'd like your VHD(X) to be created in."
                    $openFolderDialog1.SelectedPath     = $WorkingDirectory

                    $ret = $openFolderDialog1.ShowDialog()

                    if ($ret -ilike "ok")
                    {
                        $WorkingDirectory = $txtWorkingDirectory = $openFolderDialog1.SelectedPath
                        Write-W2VInfo "Selected Working Directory is $WorkingDirectory..."
                    }
                }

                $btnUnattendBrowse_OnClick              = {
                    $openFileDialog1.InitialDirectory   = $pwd
                    $openFileDialog1.Filter             = "XML files (*.xml)|*.XML|All files (*.*)|*.*"
                    $openFileDialog1.FilterIndex        = 1
                    $openFileDialog1.CheckFileExists    = $true
                    $openFileDialog1.CheckPathExists    = $true
                    $openFileDialog1.FileName           = $null
                    $openFileDialog1.ShowHelp           = $false
                    $openFileDialog1.Title              = "Select an unattend file..."

                    $ret = $openFileDialog1.ShowDialog()

                    if ($ret -ilike "ok")
                    {
                        $UnattendPath = $txtUnattendFile.Text = $openFileDialog1.FileName
                    }
                }

                $btnBrowseWim_OnClick                   = {
                    $openFileDialog1.InitialDirectory   = $pwd
                    $openFileDialog1.Filter             = "All compatible files (*.ISO, *.WIM)|*.ISO;*.WIM|All files (*.*)|*.*"
                    $openFileDialog1.FilterIndex        = 1
                    $openFileDialog1.CheckFileExists    = $true
                    $openFileDialog1.CheckPathExists    = $true
                    $openFileDialog1.FileName           = $null
                    $openFileDialog1.ShowHelp           = $false
                    $openFileDialog1.Title              = "Select a source file..."

                    $ret = $openFileDialog1.ShowDialog()

                    if ($ret -ilike "ok")
                    {

                        if (([IO.FileInfo]$openFileDialog1.FileName).Extension -ilike ".iso")
                        {

                            if (Test-IsNetworkLocation $openFileDialog1.FileName)
                            {
                                Write-W2VInfo "Copying ISO $(Split-Path $openFileDialog1.FileName -Leaf) to temp folder..."
                                Write-W2VWarn "The UI may become non-responsive while this copy takes place..."
                                Copy-Item -Path $openFileDialog1.FileName -Destination $TempDirectory -Force
                                $openFileDialog1.FileName = "$($TempDirectory)\$(Split-Path $openFileDialog1.FileName -Leaf)"
                            }

                            $txtSourcePath.Text = $isoPath = (Resolve-Path $openFileDialog1.FileName).Path
                            Write-W2VInfo "Opening ISO $(Split-Path $isoPath -Leaf)..."

                            $script:SourcePath  = "$($driveLetter):\sources\install.wim"

                            # Check to see if there's a WIM file we can muck about with.
                            Write-W2VInfo "Looking for $($SourcePath)..."
                            if (!(Test-Path $SourcePath))
                            {
                                throw "The specified ISO does not appear to be valid Windows installation media."
                            }
                        }
                        else
                        {
                            $txtSourcePath.Text = $script:SourcePath = $openFileDialog1.FileName
                        }

                        # Check to see if the WIM is local, or on a network location.  If the latter, copy it locally.
                        if (Test-IsNetworkLocation $SourcePath)
                        {
                            Write-W2VInfo "Copying WIM $(Split-Path $SourcePath -Leaf) to temp folder..."
                            Write-W2VWarn "The UI may become non-responsive while this copy takes place..."
                            Copy-Item -Path $SourcePath -Destination $TempDirectory -Force
                            $txtSourcePath.Text = $script:SourcePath = "$($TempDirectory)\$(Split-Path $SourcePath -Leaf)"
                        }

                        $script:SourcePath = (Resolve-Path $SourcePath).Path

                        Write-W2VInfo "Scanning WIM metadata..."

                        $tempOpenWim = $null

                        try
                        {
                            $tempOpenWim   = New-Object WIM2VHD.WimFile $SourcePath

                            # Let's see if we're running against an unstaged build.  If we are, we need to blow up.
                            if ($tempOpenWim.ImageNames.Contains("Windows Longhorn Client") -or
                                $tempOpenWim.ImageNames.Contains("Windows Longhorn Server") -or
                                $tempOpenWim.ImageNames.Contains("Windows Longhorn Server Core"))
                            {
                                [Windows.Forms.MessageBox]::Show(
                                    "Convert-WindowsImage cannot run against unstaged builds. Please try again with a staged build.",
                                    "WIM is incompatible!",
                                    "OK",
                                    "Error"
                                )

                                return
                            }
                            else
                            {
                                $tempOpenWim.Images | %{ $cmbSkuList.Items.Add($_.ImageFlags) }
                                $cmbSkuList.SelectedIndex = 0
                            }

                        }
                        catch
                        {
                            throw "Unable to load WIM metadata!"
                        }
                        finally
                        {
                            $tempOpenWim.Close()
                            Write-W2VTrace "Closing WIM metadata..."
                        }
                    }
                }

                $OnLoadForm_StateCorrection = {

                    # Correct the initial state of the form to prevent the .Net maximized form issue
                    $frmMain.WindowState      = $InitialFormWindowState
                }

                #endregion Event scriptblocks

                # Figure out VHD size and size unit.
                $unit = $null
                switch ([Math]::Round($SizeBytes.ToString().Length / 3))
                {
                    3 { $unit = "MB"; break }
                    4 { $unit = "GB"; break }
                    5 { $unit = "TB"; break }
                    default { $unit = ""; break }
                }

                $quantity = Invoke-Expression -Command "$($SizeBytes) / 1$($unit)"

                #region Form Code
                #region frmMain
                $frmMain.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 579
                $System_Drawing_Size.Width    = 512
                $frmMain.ClientSize           = $System_Drawing_Size
                $frmMain.Font                 = New-Object System.Drawing.Font("Segoe UI",10,0,3,1)
                $frmMain.FormBorderStyle      = 1
                $frmMain.MaximizeBox          = $False
                $frmMain.MinimizeBox          = $False
                $frmMain.Name                 = "frmMain"
                $frmMain.StartPosition        = 1
                $frmMain.Text                 = "Convert-WindowsImage UI"
                #endregion frmMain

                #region groupBox4
                $groupBox4.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 10
                $System_Drawing_Point.Y       = 498
                $groupBox4.Location           = $System_Drawing_Point
                $groupBox4.Name               = "groupBox4"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 69
                $System_Drawing_Size.Width    = 489
                $groupBox4.Size               = $System_Drawing_Size
                $groupBox4.TabIndex           = 8
                $groupBox4.TabStop            = $False
                $groupBox4.Text               = "4. Make the VHD!"

                $frmMain.Controls.Add($groupBox4)
                #endregion groupBox4

                #region btnGo
                $btnGo.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 39
                $System_Drawing_Point.Y       = 24
                $btnGo.Location               = $System_Drawing_Point
                $btnGo.Name                   = "btnGo"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 33
                $System_Drawing_Size.Width    = 415
                $btnGo.Size                   = $System_Drawing_Size
                $btnGo.TabIndex               = 0
                $btnGo.Text                   = "&Make my VHD"
                $btnGo.UseVisualStyleBackColor = $True
                $btnGo.DialogResult           = "OK"
                $btnGo.add_Click($btnGo_OnClick)

                $groupBox4.Controls.Add($btnGo)
                $frmMain.AcceptButton = $btnGo
                #endregion btnGo

                #region groupBox3
                $groupBox3.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 10
                $System_Drawing_Point.Y       = 243
                $groupBox3.Location           = $System_Drawing_Point
                $groupBox3.Name               = "groupBox3"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 245
                $System_Drawing_Size.Width    = 489
                $groupBox3.Size               = $System_Drawing_Size
                $groupBox3.TabIndex           = 7
                $groupBox3.TabStop            = $False
                $groupBox3.Text               = "3. Choose configuration options"

                $frmMain.Controls.Add($groupBox3)
                #endregion groupBox3

                #region txtVhdName
                $txtVhdName.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 25
                $System_Drawing_Point.Y       = 150
                $txtVhdName.Location          = $System_Drawing_Point
                $txtVhdName.Name              = "txtVhdName"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 25
                $System_Drawing_Size.Width    = 418
                $txtVhdName.Size              = $System_Drawing_Size
                $txtVhdName.TabIndex          = 10

                $groupBox3.Controls.Add($txtVhdName)
                #endregion txtVhdName

                #region txtUnattendFile
                $txtUnattendFile.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 25
                $System_Drawing_Point.Y       = 198
                $txtUnattendFile.Location     = $System_Drawing_Point
                $txtUnattendFile.Name         = "txtUnattendFile"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 25
                $System_Drawing_Size.Width    = 418
                $txtUnattendFile.Size         = $System_Drawing_Size
                $txtUnattendFile.TabIndex     = 11

                $groupBox3.Controls.Add($txtUnattendFile)
                #endregion txtUnattendFile

                #region label7
                $label7.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 23
                $System_Drawing_Point.Y       = 180
                $label7.Location              = $System_Drawing_Point
                $label7.Name                  = "label7"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 23
                $System_Drawing_Size.Width    = 175
                $label7.Size                  = $System_Drawing_Size
                $label7.Text                  = "Unattend File (Optional)"

                $groupBox3.Controls.Add($label7)
                #endregion label7

                #region label6
                $label6.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 23
                $System_Drawing_Point.Y       = 132
                $label6.Location              = $System_Drawing_Point
                $label6.Name                  = "label6"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 23
                $System_Drawing_Size.Width    = 175
                $label6.Size                  = $System_Drawing_Size
                $label6.Text                  = "VHD Name (Optional)"

                $groupBox3.Controls.Add($label6)
                #endregion label6

                #region btnUnattendBrowse
                $btnUnattendBrowse.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 449
                $System_Drawing_Point.Y       = 199
                $btnUnattendBrowse.Location   = $System_Drawing_Point
                $btnUnattendBrowse.Name       = "btnUnattendBrowse"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 25
                $System_Drawing_Size.Width    = 27
                $btnUnattendBrowse.Size       = $System_Drawing_Size
                $btnUnattendBrowse.TabIndex   = 9
                $btnUnattendBrowse.Text       = "..."
                $btnUnattendBrowse.UseVisualStyleBackColor = $True
                $btnUnattendBrowse.add_Click($btnUnattendBrowse_OnClick)

                $groupBox3.Controls.Add($btnUnattendBrowse)
                #endregion btnUnattendBrowse

                #region btnWrkBrowse
                $btnWrkBrowse.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 449
                $System_Drawing_Point.Y       = 98
                $btnWrkBrowse.Location        = $System_Drawing_Point
                $btnWrkBrowse.Name            = "btnWrkBrowse"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 25
                $System_Drawing_Size.Width    = 27
                $btnWrkBrowse.Size            = $System_Drawing_Size
                $btnWrkBrowse.TabIndex        = 9
                $btnWrkBrowse.Text            = "..."
                $btnWrkBrowse.UseVisualStyleBackColor = $True
                $btnWrkBrowse.add_Click($btnWrkBrowse_OnClick)

                $groupBox3.Controls.Add($btnWrkBrowse)
                #endregion btnWrkBrowse

                #region cmbVhdSizeUnit
                $cmbVhdSizeUnit.DataBindings.DefaultDataSourceUpdateMode = 0
                $cmbVhdSizeUnit.FormattingEnabled = $True
                $cmbVhdSizeUnit.Items.Add("MB") | Out-Null
                $cmbVhdSizeUnit.Items.Add("GB") | Out-Null
                $cmbVhdSizeUnit.Items.Add("TB") | Out-Null
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 409
                $System_Drawing_Point.Y       = 42
                $cmbVhdSizeUnit.Location      = $System_Drawing_Point
                $cmbVhdSizeUnit.Name          = "cmbVhdSizeUnit"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 25
                $System_Drawing_Size.Width    = 67
                $cmbVhdSizeUnit.Size          = $System_Drawing_Size
                $cmbVhdSizeUnit.TabIndex      = 5
                $cmbVhdSizeUnit.Text          = $unit

                $groupBox3.Controls.Add($cmbVhdSizeUnit)
                #endregion cmbVhdSizeUnit

                #region numVhdSize
                $numVhdSize.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 340
                $System_Drawing_Point.Y       = 42
                $numVhdSize.Location          = $System_Drawing_Point
                $numVhdSize.Name              = "numVhdSize"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 25
                $System_Drawing_Size.Width    = 63
                $numVhdSize.Size              = $System_Drawing_Size
                $numVhdSize.TabIndex          = 4
                $numVhdSize.Value             = $quantity

                $groupBox3.Controls.Add($numVhdSize)
                #endregion numVhdSize

                #region cmbVhdFormat
                $cmbVhdFormat.DataBindings.DefaultDataSourceUpdateMode = 0
                $cmbVhdFormat.FormattingEnabled = $True
                $cmbVhdFormat.Items.Add("VHD")  | Out-Null
                $cmbVhdFormat.Items.Add("VHDX") | Out-Null
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 25
                $System_Drawing_Point.Y       = 42
                $cmbVhdFormat.Location        = $System_Drawing_Point
                $cmbVhdFormat.Name            = "cmbVhdFormat"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 25
                $System_Drawing_Size.Width    = 136
                $cmbVhdFormat.Size            = $System_Drawing_Size
                $cmbVhdFormat.TabIndex        = 0
                $cmbVhdFormat.Text            = $VHDFormat

                $groupBox3.Controls.Add($cmbVhdFormat)
                #endregion cmbVhdFormat

                #region label5
                $label5.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 23
                $System_Drawing_Point.Y       = 76
                $label5.Location              = $System_Drawing_Point
                $label5.Name                  = "label5"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 23
                $System_Drawing_Size.Width    = 264
                $label5.Size                  = $System_Drawing_Size
                $label5.TabIndex              = 8
                $label5.Text                  = "Working Directory"

                $groupBox3.Controls.Add($label5)
                #endregion label5

                #region txtWorkingDirectory
                $txtWorkingDirectory.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 25
                $System_Drawing_Point.Y       = 99
                $txtWorkingDirectory.Location = $System_Drawing_Point
                $txtWorkingDirectory.Name     = "txtWorkingDirectory"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 25
                $System_Drawing_Size.Width    = 418
                $txtWorkingDirectory.Size     = $System_Drawing_Size
                $txtWorkingDirectory.TabIndex = 7
                $txtWorkingDirectory.Text     = $WorkingDirectory

                $groupBox3.Controls.Add($txtWorkingDirectory)
                #endregion txtWorkingDirectory

                #region label4
                $label4.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 340
                $System_Drawing_Point.Y       = 21
                $label4.Location              = $System_Drawing_Point
                $label4.Name                  = "label4"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 27
                $System_Drawing_Size.Width    = 86
                $label4.Size                  = $System_Drawing_Size
                $label4.TabIndex              = 6
                $label4.Text                  = "VHD Size"

                $groupBox3.Controls.Add($label4)
                #endregion label4

                #region label3
                $label3.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 176
                $System_Drawing_Point.Y       = 21
                $label3.Location              = $System_Drawing_Point
                $label3.Name                  = "label3"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 27
                $System_Drawing_Size.Width    = 92
                $label3.Size                  = $System_Drawing_Size
                $label3.TabIndex              = 3
                $label3.Text                  = "VHD Type"

                $groupBox3.Controls.Add($label3)
                #endregion label3

                #region label2
                $label2.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 25
                $System_Drawing_Point.Y       = 21
                $label2.Location              = $System_Drawing_Point
                $label2.Name                  = "label2"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 30
                $System_Drawing_Size.Width    = 118
                $label2.Size                  = $System_Drawing_Size
                $label2.TabIndex              = 1
                $label2.Text                  = "VHD Format"

                $groupBox3.Controls.Add($label2)
                #endregion label2

                #region groupBox2
                $groupBox2.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 10
                $System_Drawing_Point.Y       = 169
                $groupBox2.Location           = $System_Drawing_Point
                $groupBox2.Name               = "groupBox2"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 68
                $System_Drawing_Size.Width    = 490
                $groupBox2.Size               = $System_Drawing_Size
                $groupBox2.TabIndex           = 6
                $groupBox2.TabStop            = $False
                $groupBox2.Text               = "2. Choose a SKU from the list"

                $frmMain.Controls.Add($groupBox2)
                #endregion groupBox2

                #region cmbSkuList
                $cmbSkuList.DataBindings.DefaultDataSourceUpdateMode = 0
                $cmbSkuList.FormattingEnabled = $True
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 25
                $System_Drawing_Point.Y       = 24
                $cmbSkuList.Location          = $System_Drawing_Point
                $cmbSkuList.Name              = "cmbSkuList"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 25
                $System_Drawing_Size.Width    = 452
                $cmbSkuList.Size              = $System_Drawing_Size
                $cmbSkuList.TabIndex          = 2

                $groupBox2.Controls.Add($cmbSkuList)
                #endregion cmbSkuList

                #region label1
                $label1.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 23
                $System_Drawing_Point.Y       = 21
                $label1.Location              = $System_Drawing_Point
                $label1.Name                  = "label1"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 71
                $System_Drawing_Size.Width    = 464
                $label1.Size                  = $System_Drawing_Size
                $label1.TabIndex              = 5
                $label1.Text                  = $uiHeader

                $frmMain.Controls.Add($label1)
                #endregion label1

                #region groupBox1
                $groupBox1.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 10
                $System_Drawing_Point.Y       = 95
                $groupBox1.Location           = $System_Drawing_Point
                $groupBox1.Name               = "groupBox1"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 68
                $System_Drawing_Size.Width    = 490
                $groupBox1.Size               = $System_Drawing_Size
                $groupBox1.TabIndex           = 4
                $groupBox1.TabStop            = $False
                $groupBox1.Text               = "1. Choose a source"

                $frmMain.Controls.Add($groupBox1)
                #endregion groupBox1

                #region txtSourcePath
                $txtSourcePath.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 25
                $System_Drawing_Point.Y       = 24
                $txtSourcePath.Location       = $System_Drawing_Point
                $txtSourcePath.Name           = "txtSourcePath"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 25
                $System_Drawing_Size.Width    = 418
                $txtSourcePath.Size           = $System_Drawing_Size
                $txtSourcePath.TabIndex       = 0

                $groupBox1.Controls.Add($txtSourcePath)
                #endregion txtSourcePath

                #region btnBrowseWim
                $btnBrowseWim.DataBindings.DefaultDataSourceUpdateMode = 0
                $System_Drawing_Point         = New-Object System.Drawing.Point
                $System_Drawing_Point.X       = 449
                $System_Drawing_Point.Y       = 24
                $btnBrowseWim.Location        = $System_Drawing_Point
                $btnBrowseWim.Name            = "btnBrowseWim"
                $System_Drawing_Size          = New-Object System.Drawing.Size
                $System_Drawing_Size.Height   = 25
                $System_Drawing_Size.Width    = 28
                $btnBrowseWim.Size            = $System_Drawing_Size
                $btnBrowseWim.TabIndex        = 1
                $btnBrowseWim.Text            = "..."
                $btnBrowseWim.UseVisualStyleBackColor = $True
                $btnBrowseWim.add_Click($btnBrowseWim_OnClick)

                $groupBox1.Controls.Add($btnBrowseWim)
                #endregion btnBrowseWim

                $openFileDialog1.FileName     = "openFileDialog1"
                $openFileDialog1.ShowHelp     = $True

                #endregion Form Code

                # Save the initial state of the form
                $InitialFormWindowState       = $frmMain.WindowState

                # Init the OnLoad event to correct the initial state of the form
                $frmMain.add_Load($OnLoadForm_StateCorrection)

                # Return the constructed form.
                $ret = $frmMain.ShowDialog()

                if (!($ret -ilike "OK"))
                {
                    throw "Form session has been cancelled."
                }

                if ([string]::IsNullOrEmpty($SourcePath))
                {
                    throw "No source path specified."
                }

                # VHD Format
                $VHDFormat        = $cmbVhdFormat.SelectedItem

                # VHD Size
                $SizeBytes        = Invoke-Expression "$($numVhdSize.Value)$($cmbVhdSizeUnit.SelectedItem)"

                # Working Directory
                $WorkingDirectory = $txtWorkingDirectory.Text

                # VHDPath
                if (![string]::IsNullOrEmpty($txtVhdName.Text))
                {
                    $VHDPath      = "$($WorkingDirectory)\$($txtVhdName.Text)"
                }

                # Edition
                if (![string]::IsNullOrEmpty($cmbSkuList.SelectedItem))
                {
                    $Edition      = $cmbSkuList.SelectedItem
                }

                # Because we used ShowDialog, we need to manually dispose of the form.
                # This probably won't make much of a difference, but let's free up all of the resources we can
                # before we start the conversion process.

                $frmMain.Dispose()
            }

            if ($VHDFormat -ilike "AUTO")
            {
                if ($DiskLayout -eq "BIOS")
                {
                    $VHDFormat = "VHD"
                }
                else
                {
                    $VHDFormat = "VHDX"
                }
            }

            #
            # Choose smallest supported block size for dynamic VHD(X)
            #
            $BlockSizeBytes = 1MB

            # There's a difference between the maximum sizes for VHDs and VHDXs.  Make sure we follow it.
            if ("VHD" -ilike $VHDFormat)
            {
                if ($SizeBytes -gt $vhdMaxSize)
                {
                    Write-W2VWarn "For the VHD file format, the maximum file size is ~2040GB.  We're automatically setting the size to 2040GB for you."
                    $SizeBytes = 2040GB
                }

                $BlockSizeBytes = 512KB
            }

            # Check if -VHDPath and -WorkingDirectory were both specified.
            if ((![String]::IsNullOrEmpty($VHDPath)) -and (![String]::IsNullOrEmpty($WorkingDirectory)))
            {
                if ($WorkingDirectory -ne $pwd)
                {
                    # If the WorkingDirectory is anything besides $pwd, tell people that the WorkingDirectory is being ignored.
                    Write-W2VWarn "Specifying -VHDPath and -WorkingDirectory at the same time is contradictory."
                    Write-W2VWarn "Ignoring the WorkingDirectory specification."
                    $WorkingDirectory = Split-Path $VHDPath -Parent
                }
            }

            if ($VHDPath)
            {
                # Check to see if there's a conflict between the specified file extension and the VHDFormat being used.
                $ext = ([IO.FileInfo]$VHDPath).Extension

                if (!($ext -ilike ".$($VHDFormat)"))
                {
                    throw "There is a mismatch between the VHDPath file extension ($($ext.ToUpper())), and the VHDFormat (.$($VHDFormat)).  Please ensure that these match and try again."
                }
            }

            # Create a temporary name for the VHD(x).  We'll name it properly at the end of the script.
            if ([String]::IsNullOrEmpty($VHDPath))
            {
                $VHDPath      = Join-Path $WorkingDirectory "$($sessionKey).$($VHDFormat.ToLower())"
            }
            else
            {
                # Since we can't do Resolve-Path against a file that doesn't exist, we need to get creative in determining
                # the full path that the user specified (or meant to specify if they gave us a relative path).
                # Check to see if the path has a root specified.  If it doesn't, use the working directory.
                if (![IO.Path]::IsPathRooted($VHDPath))
                {
                    $VHDPath  = Join-Path $WorkingDirectory $VHDPath
                }

                $vhdFinalName = Split-Path $VHDPath -Leaf
                $VHDPath      = Join-Path (Split-Path $VHDPath -Parent) "$($sessionKey).$($VHDFormat.ToLower())"
            }

            Write-W2VTrace "Temporary $VHDFormat path is : $VHDPath"

            # If we're using an ISO, mount it and get the path to the WIM file.
            if (([IO.FileInfo]$SourcePath).Extension -ilike ".ISO")
            {
                # If the ISO isn't local, copy it down so we don't have to worry about resource contention
                # or about network latency.
                if (Test-IsNetworkLocation $SourcePath)
                {
                    Write-W2VError "ISO Path cannot be network location"
                    #Write-W2VInfo "Copying ISO $(Split-Path $SourcePath -Leaf) to temp folder..."
                    #robocopy $(Split-Path $SourcePath -Parent) $TempDirectory $(Split-Path $SourcePath -Leaf) | Out-Null
                    #$SourcePath = "$($TempDirectory)\$(Split-Path $SourcePath -Leaf)"
                    #$tempSource = $SourcePath
                }

                $isoPath = (Resolve-Path $SourcePath).Path

                Write-W2VInfo "Opening ISO $(Split-Path $isoPath -Leaf)..."
                <#
                $openIso     = Mount-DiskImage -ImagePath $isoPath -StorageType ISO -PassThru
                # Refresh the DiskImage object so we can get the real information about it.  I assume this is a bug.
                $openIso     = Get-DiskImage -ImagePath $isoPath
                $driveLetter = ($openIso | Get-Volume).DriveLetter
                #>
                $SourcePath  = "$($DriveLetter):\sources\install.wim"

                # Check to see if there's a WIM file we can muck about with.
                Write-W2VInfo "Looking for $($SourcePath)..."
                if (!(Test-Path $SourcePath))
                {
                    throw "The specified ISO does not appear to be valid Windows installation media."
                }
            }

            # Check to see if the WIM is local, or on a network location.  If the latter, copy it locally.
            if (Test-IsNetworkLocation $SourcePath)
            {
                Write-W2VInfo "Copying WIM $(Split-Path $SourcePath -Leaf) to temp folder..."
                robocopy $(Split-Path $SourcePath -Parent) $TempDirectory $(Split-Path $SourcePath -Leaf) | Out-Null
                $SourcePath = "$($TempDirectory)\$(Split-Path $SourcePath -Leaf)"

                $tempSource = $SourcePath
            }

            $SourcePath  = (Resolve-Path $SourcePath).Path

            ####################################################################################################
            # QUERY WIM INFORMATION AND EXTRACT THE INDEX OF TARGETED IMAGE
            ####################################################################################################

            Write-W2VInfo "Looking for the requested Windows image in the WIM file"
            $WindowsImage = Get-WindowsImage -ImagePath "$($driveLetter):\sources\install.wim"

            if (-not $WindowsImage -or ($WindowsImage -is [System.Array]))
            {
                #
                # WIM may have multiple images.  Filter on Edition (can be index or name) and try to find a unique image
                #
                $EditionIndex = 0;
                if ([Int32]::TryParse($Edition, [ref]$EditionIndex))
                {
                    $WindowsImage = Get-WindowsImage -ImagePath $SourcePath -Index $EditionIndex
                }
                else
                {
                    $WindowsImage = Get-WindowsImage -ImagePath $SourcePath | Where-Object {$_.ImageName -ilike "*$($Edition)"}
                }

                if (-not $WindowsImage)
                {
                    throw "Requested windows Image was not found on the WIM file!"
                }
                if ($WindowsImage -is [System.Array])
                {
                    Write-W2VInfo "WIM file has the following $($WindowsImage.Count) images that match filter *$($Edition)"
                    Get-WindowsImage -ImagePath $SourcePath

                    Write-W2VError "You must specify an Edition or SKU index, since the WIM has more than one image."
                    throw "There are more than one images that match ImageName filter *$($Edition)"
                }
            }

            $ImageIndex = $WindowsImage[0].ImageIndex

            # We're good.  Open the WIM container.
            # NOTE: this is only required because we want to get the XML-based meta-data at the end.  Is there a better way?
            # If we can get this information from DISM cmdlets, we can remove the openWim constructs
            $openWim     = New-Object WIM2VHD.WimFile $SourcePath

            $openImage = $openWim[[Int32]$ImageIndex]

            if ($null -eq $openImage)
            {
                Write-W2VError "The specified edition does not appear to exist in the specified WIM."
                Write-W2VError "Valid edition names are:"
                $openWim.Images | %{ Write-W2VError "  $($_.ImageFlags)" }
                throw
            }

            Write-W2VInfo "Image $($openImage.ImageIndex) selected ($($openImage.ImageFlags))..."

            # Check to make sure that the image we're applying is Windows 7 or greater.
            if ($openImage.ImageVersion -lt $lowestSupportedVersion)
            {
                if ($openImage.ImageVersion -eq "0.0.0.0")
                {
                    Write-W2VWarn "The specified WIM does not encode the Windows version."
                }
                else
                {
                    throw "Convert-WindowsImage only supports Windows 7 and Windows 8 WIM files.  The specified image (version $($openImage.ImageVersion)) does not appear to contain one of those operating systems."
                }
            }

            if ($hyperVEnabled)
            {
                Write-W2VInfo "Creating sparse disk..."
                $newVhd = New-VHD -Path $VHDPath -SizeBytes $SizeBytes -BlockSizeBytes $BlockSizeBytes -Dynamic

                Write-W2VInfo "Mounting $VHDFormat..."
                $disk = $newVhd | Mount-VHD -PassThru | Get-Disk
            }
            else
            {
                <#
                    Create the VHD using the VirtDisk Win32 API.
                    So, why not use the New-VHD cmdlet here?

                    New-VHD depends on the Hyper-V Cmdlets, which aren't installed by default.
                    Installing those cmdlets isn't a big deal, but they depend on the Hyper-V WMI
                    APIs, which in turn depend on Hyper-V.  In order to prevent Convert-WindowsImage
                    from being dependent on Hyper-V (and thus, x64 systems only), we're using the
                    VirtDisk APIs directly.
                #>

                Write-W2VInfo "Creating sparse disk..."
                [WIM2VHD.VirtualHardDisk]::CreateSparseDisk(
                    $VHDFormat,
                    $VHDPath,
                    $SizeBytes,
                    $true
                )

                # Attach the VHD.\
                Write-W2VInfo "Attaching $VHDFormat..."
                $disk = Mount-DiskImage -ImagePath $VHDPath -PassThru | Get-DiskImage | Get-Disk
            }

            switch ($DiskLayout)
            {
                "BIOS"
                {
                    Write-W2VInfo "Initializing disk..."
                    Initialize-Disk -Number $disk.Number -PartitionStyle MBR

                    #
                    # Create the Windows/system partition
                    #
                    Write-W2VInfo "Creating single partition..."
                    $systemPartition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -MbrType IFS -IsActive
                    $windowsPartition = $systemPartition

                    Write-W2VInfo "Formatting windows volume..."
                    $systemVolume = Format-Volume -Partition $systemPartition -FileSystem NTFS -Force -Confirm:$false
                    $windowsVolume = $systemVolume
                }

                "UEFI"
                {
                    Write-W2VInfo "Initializing disk..."
                    Initialize-Disk -Number $disk.Number -PartitionStyle GPT

                    if ((Get-WindowsBuildNumber) -ge 10240)
                    {
                        #
                        # Create the system partition.  Create a data partition so we can format it, then change to ESP
                        #
                        Write-W2VInfo "Creating EFI system partition..."
                        $systemPartition = New-Partition -DiskNumber $disk.Number -Size 200MB -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'

                        Write-W2VInfo "Formatting system volume..."
                        $systemVolume = Format-Volume -Partition $systemPartition -FileSystem FAT32 -Force -Confirm:$false

                        Write-W2VInfo "Setting system partition as ESP..."
                        $systemPartition | Set-Partition -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
                        $systemPartition | Add-PartitionAccessPath -AssignDriveLetter
                    }
                    else
                    {
                        #
                        # Create the system partition
                        #
                        Write-W2VInfo "Creating EFI system partition (ESP)..."
                        $systemPartition = New-Partition -DiskNumber $disk.Number -Size 200MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -AssignDriveLetter

                        Write-W2VInfo "Formatting ESP..."
                        $formatArgs = @(
                            "$($systemPartition.DriveLetter):", # Partition drive letter
                            "/FS:FAT32",                        # File system
                            "/Q",                               # Quick format
                            "/Y"                                # Suppress prompt
                            )

                        Run-Executable -Executable format -Arguments $formatArgs
                    }

                    #
                    # Create the reserved partition
                    #
                    Write-W2VInfo "Creating MSR partition..."
                    $reservedPartition = New-Partition -DiskNumber $disk.Number -Size 128MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'

                    #
                    # Create the Windows partition
                    #
                    Write-W2VInfo "Creating windows partition..."
                    $windowsPartition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'

                    Write-W2VInfo "Formatting windows volume..."
                    $windowsVolume = Format-Volume -Partition $windowsPartition -FileSystem NTFS -Force -Confirm:$false
                }

                "WindowsToGo"
                {
                    Write-W2VInfo "Initializing disk..."
                    Initialize-Disk -Number $disk.Number -PartitionStyle MBR

                    #
                    # Create the system partition
                    #
                    Write-W2VInfo "Creating system partition..."
                    $systemPartition = New-Partition -DiskNumber $disk.Number -Size 350MB -MbrType FAT32 -IsActive

                    Write-W2VInfo "Formatting system volume..."
                    $systemVolume    = Format-Volume -Partition $systemPartition -FileSystem FAT32 -Force -Confirm:$false

                    #
                    # Create the Windows partition
                    #
                    Write-W2VInfo "Creating windows partition..."
                    $windowsPartition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -MbrType IFS

                    Write-W2VInfo "Formatting windows volume..."
                    $windowsVolume    = Format-Volume -Partition $windowsPartition -FileSystem NTFS -Force -Confirm:$false
                }
            }

            #
            # Assign drive letter to Windows partition.  This is required for bcdboot
            #

            $attempts = 1
            $assigned = $false

            do
            {
                $windowsPartition | Add-PartitionAccessPath -AssignDriveLetter
                $windowsPartition = $windowsPartition | Get-Partition
                if($windowsPartition.DriveLetter -ne 0)
                {
                    $assigned = $true
                }
                else
                {
                    #sleep for up to 10 seconds and retry
                    Get-Random -Minimum 1 -Maximum 10 | Start-Sleep

                    $attempts++
                }
            }
            while ($attempts -le 100 -and -not($assigned))

            if (-not($assigned))
            {
                throw "Unable to get Partition after retry"
            }

            $windowsDrive = $(Get-Partition -Volume $windowsVolume).AccessPaths[0].substring(0,2)
            Write-W2VInfo "Windows path ($windowsDrive) has been assigned."
            Write-W2VInfo "Windows path ($windowsDrive) took $attempts attempts to be assigned."

            #
            # Refresh access paths (we have now formatted the volume)
            #
            $systemPartition = $systemPartition | Get-Partition
            $systemDrive = $systemPartition.AccessPaths[0].trimend("\").replace("\?", "??")
            Write-W2VInfo "System volume location: $systemDrive"

            ####################################################################################################
            # APPLY IMAGE FROM WIM TO THE NEW VHD
            ####################################################################################################

            Write-W2VInfo "Applying image to $VHDFormat. This could take a while..."
            if ((Get-Command Expand-WindowsImage -ErrorAction SilentlyContinue) -and ((-not $ApplyEA) -and ([string]::IsNullOrEmpty($DismPath))))
            {
                Expand-WindowsImage -ApplyPath $windowsDrive -ImagePath $SourcePath -Index $ImageIndex -LogPath "$($logFolder)\DismLogs.log" | Out-Null
            }
            else
            {
                if (![string]::IsNullOrEmpty($DismPath))
                {
                    $dismPath = $DismPath
                }
                else
                {
                    $dismPath = $(Join-Path (get-item env:\windir).value "system32\dism.exe")
                }

                $applyImage = "/Apply-Image"
                if ($ApplyEA)
                {
                    $applyImage = $applyImage + " /EA"
                }

                $dismArgs = @("$applyImage /ImageFile:`"$SourcePath`" /Index:$ImageIndex /ApplyDir:$windowsDrive /LogPath:`"$($logFolder)\DismLogs.log`"")
                Write-W2VInfo "Applying image: $dismPath $dismArgs"
                $process  = Start-Process -Passthru -Wait -NoNewWindow -FilePath $dismPath `
                            -ArgumentList $dismArgs `

                if ($process.ExitCode -ne 0)
                {
 	                throw "Image Apply failed! See DismImageApply logs for details"
                }
            }
            Write-W2VInfo "Image was applied successfully. "

            #
            # Here we copy in the unattend file (if specified by the command line)
            #
            if (![string]::IsNullOrEmpty($UnattendPath))
            {
                Write-W2VInfo "Applying unattend file ($(Split-Path $UnattendPath -Leaf))..."
                Copy-Item -Path $UnattendPath -Destination (Join-Path $windowsDrive "unattend.xml") -Force
            }

            if (![string]::IsNullOrEmpty($MergeFolderPath))
            {
                Write-W2VInfo "Applying merge folder ($MergeFolderPath)..."
                Copy-Item -Recurse -Path (Join-Path $MergeFolderPath "*") -Destination $windowsDrive -Force #added to handle merge folders
            }

            if (($openImage.ImageArchitecture -ne "ARM") -and       # No virtualization platform for ARM images
                ($openImage.ImageArchitecture -ne "ARM64") -and     # No virtualization platform for ARM64 images
                ($BCDinVHD -ne "NativeBoot"))                       # User asked for a non-bootable image
            {
                if (Test-Path "$($systemDrive)\boot\bcd")
                {
                    Write-W2VInfo "Image already has BIOS BCD store..."
                }
                elseif (Test-Path "$($systemDrive)\efi\microsoft\boot\bcd")
                {
                    Write-W2VInfo "Image already has EFI BCD store..."
                }
                else
                {
                    Write-W2VInfo "Making image bootable..."
                    $bcdBootArgs = @(
                        "$($windowsDrive)\Windows", # Path to the \Windows on the VHD
                        "/s $systemDrive",          # Specifies the volume letter of the drive to create the \BOOT folder on.
                        "/v"                        # Enabled verbose logging.
                        )

                    switch ($DiskLayout)
                    {
                        "BIOS"
                        {
                            $bcdBootArgs += "/f BIOS"   # Specifies the firmware type of the target system partition
                        }

                        "UEFI"
                        {
                            $bcdBootArgs += "/f UEFI"   # Specifies the firmware type of the target system partition
                        }

                        "WindowsToGo"
                        {
                            # Create entries for both UEFI and BIOS if possible
                            if (Test-Path "$($windowsDrive)\Windows\boot\EFI\bootmgfw.efi")
                            {
                                $bcdBootArgs += "/f ALL"
                            }
                        }
                    }

                    Run-Executable -Executable $BCDBoot -Arguments $bcdBootArgs

                    # The following is added to mitigate the VMM diff disk handling
                    # We're going to change from MBRBootOption to LocateBootOption.

                    if ($DiskLayout -eq "BIOS")
                    {
                        Write-W2VInfo "Fixing the Device ID in the BCD store on $($VHDFormat)..."
                        Run-Executable -Executable "BCDEDIT.EXE" -Arguments (
                            "/store $($systemDrive)\boot\bcd",
                            "/set `{bootmgr`} device locate"
                        )
                        Run-Executable -Executable "BCDEDIT.EXE" -Arguments (
                            "/store $($systemDrive)\boot\bcd",
                            "/set `{default`} device locate"
                        )
                        Run-Executable -Executable "BCDEDIT.EXE" -Arguments (
                            "/store $($systemDrive)\boot\bcd",
                            "/set `{default`} osdevice locate"
                        )
                    }
                }

                Write-W2VInfo "Drive is bootable.  Cleaning up..."

                # Are we turning the debugger on?
                if ($EnableDebugger -inotlike "None")
                {
                    $bcdEditArgs = $null;

                    # Configure the specified debugging transport and other settings.
                    switch ($EnableDebugger)
                    {
                        "Serial"
                        {
                            $bcdEditArgs = @(
                                "/dbgsettings SERIAL",
                                "DEBUGPORT:$($ComPort.Value)",
                                "BAUDRATE:$($BaudRate.Value)"
                                )
                        }

                        "1394"
                        {
                            $bcdEditArgs = @(
                                "/dbgsettings 1394",
                                "CHANNEL:$($Channel.Value)"
                                )
                        }

                        "USB"
                        {
                            $bcdEditArgs = @(
                                "/dbgsettings USB",
                                "TARGETNAME:$($Target.Value)"
                                )
                        }

                        "Local"
                        {
                            $bcdEditArgs = @(
                                "/dbgsettings LOCAL"
                                )
                        }

                        "Network"
                        {
                            $bcdEditArgs = @(
                                "/dbgsettings NET",
                                "HOSTIP:$($IP.Value)",
                                "PORT:$($Port.Value)",
                                "KEY:$($Key.Value)"
                                )
                        }
                    }

                    $bcdStores = @(
                        "$($systemDrive)\boot\bcd",
                        "$($systemDrive)\efi\microsoft\boot\bcd"
                        )

                    foreach ($bcdStore in $bcdStores)
                    {
                        if (Test-Path $bcdStore)
                        {
                            Write-W2VInfo "Turning kernel debugging on in the $($VHDFormat) for $($bcdStore)..."
                            Run-Executable -Executable "BCDEDIT.EXE" -Arguments (
                                "/store $($bcdStore)",
                                "/set `{default`} debug on"
                                )

                            $bcdEditArguments = @("/store $($bcdStore)") + $bcdEditArgs

                            Run-Executable -Executable "BCDEDIT.EXE" -Arguments $bcdEditArguments
                        }
                    }
                }
            }
            else
            {
                # Don't bother to check on debugging.  We can't boot WoA VHDs in VMs, and
                # if we're native booting, the changes need to be made to the BCD store on the
                # physical computer's boot volume.

                Write-W2VInfo "Image applied. It is not bootable."
            }

            if ($RemoteDesktopEnable -or (-not $ExpandOnNativeBoot))
            {
                $hive = Mount-RegistryHive -Hive (Join-Path $windowsDrive "Windows\System32\Config\System")

                if ($RemoteDesktopEnable)
                {
                    Write-W2VInfo -text "Enabling Remote Desktop"
                    Set-ItemProperty -Path "HKLM:\$($hive)\ControlSet001\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
                }

                if (-not $ExpandOnNativeBoot)
                {
                    Write-W2VInfo -text "Disabling automatic $VHDFormat expansion for Native Boot"
                    Set-ItemProperty -Path "HKLM:\$($hive)\ControlSet001\Services\FsDepends\Parameters" -Name "VirtualDiskExpandOnMount" -Value 4
                }

                Dismount-RegistryHive -HiveMountPoint $hive
            }

            if ($Driver)
            {
                Write-W2VInfo -text "Adding Windows Drivers to the Image"
                $Driver | ForEach-Object -Process {
                    Write-W2VInfo -text "Driver path: $PSItem"
                    Add-WindowsDriver -Path $windowsDrive -Recurse -Driver $PSItem -Verbose | Out-Null
                }
            }

            If ($Feature)
            {
                Write-W2VInfo -text "Installing Windows Feature(s) $Feature to the Image"
                $FeatureSourcePath = Join-Path -Path "$($driveLetter):" -ChildPath "sources\sxs"
                Write-W2VInfo -text "From $FeatureSourcePath"
                Enable-WindowsOptionalFeature -FeatureName $Feature -Source $FeatureSourcePath -Path $windowsDrive -All | Out-Null
            }

            if ($Package)
            {
                Write-W2VInfo -text "Adding Windows Packages to the Image"

                $Package | ForEach-Object -Process {
                    Write-W2VInfo -text "Package path: $PSItem"
                    Add-WindowsPackage -Path $windowsDrive -PackagePath $PSItem | Out-Null
                }
            }

            #
            # Remove system partition access path, if necessary
            #

            if (($GPUName)) {
            Add-VMGpuPartitionAdapterFiles -GPUName $GPUName -DriveLetter $windowsDrive
            }

            Write-W2VInfo "Setting up VBCable to install at boot"
            Setup-Install -DriveLetter $WindowsDrive -Team_ID $team_id -Key $key

            if ($DiskLayout -eq "UEFI")
            {
                $systemPartition | Remove-PartitionAccessPath -AccessPath $systemPartition.AccessPaths[0]
            }

            if ([String]::IsNullOrEmpty($vhdFinalName))
            {
                # We need to generate a file name.
                Write-W2VInfo "Generating name for $($VHDFormat)..."
                $hive         = Mount-RegistryHive -Hive (Join-Path $windowsDrive "Windows\System32\Config\Software")

                $buildLabEx   = (Get-ItemProperty "HKLM:\$($hive)\Microsoft\Windows NT\CurrentVersion").BuildLabEx
                $installType  = (Get-ItemProperty "HKLM:\$($hive)\Microsoft\Windows NT\CurrentVersion").InstallationType
                $editionId    = (Get-ItemProperty "HKLM:\$($hive)\Microsoft\Windows NT\CurrentVersion").EditionID
                $skuFamily    = $null

                Dismount-RegistryHive -HiveMountPoint $hive

                # Is this ServerCore?
                # Since we're only doing this string comparison against the InstallType key, we won't get
                # false positives with the Core SKU.
                if ($installType.ToUpper().Contains("CORE"))
                {
                    $editionId += "Core"
                }

                # What type of SKU are we?
                if ($installType.ToUpper().Contains("SERVER"))
                {
                    $skuFamily = "Server"
                }
                elseif ($installType.ToUpper().Contains("CLIENT"))
                {
                    $skuFamily = "Client"
                }
                else
                {
                    $skuFamily = "Unknown"
                }

                #
                # ISSUE - do we want VL here?
                #
                $vhdFinalName = "$($buildLabEx)_$($skuFamily)_$($editionId)_$($openImage.ImageDefaultLanguage).$($VHDFormat.ToLower())"
                Write-W2VTrace "$VHDFormat final name is : $vhdFinalName"
            }

            if ($hyperVEnabled)
            {
                Write-W2VInfo "Dismounting $VHDFormat..."
                Dismount-VHD -Path $VHDPath
            }
            else
            {
                Write-W2VInfo "Closing $VHDFormat..."
                Dismount-DiskImage -ImagePath $VHDPath
            }

            $vhdFinalPath = Join-Path (Split-Path $VHDPath -Parent) $vhdFinalName
            Write-W2VTrace "$VHDFormat final path is : $vhdFinalPath"

            if (Test-Path $vhdFinalPath)
            {
                Write-W2VInfo "Deleting pre-existing $VHDFormat : $(Split-Path $vhdFinalPath -Leaf)..."
                Remove-Item -Path $vhdFinalPath -Force
            }

            Write-W2VTrace -Text "Renaming $VHDFormat at $VHDPath to $vhdFinalName"
            Rename-Item -Path (Resolve-Path $VHDPath).Path -NewName $vhdFinalName -Force
            $vhd += Get-DiskImage -ImagePath $vhdFinalPath

            $vhdFinalName = $null
        }
        catch
        {
            Write-W2VError $_
            Write-W2VInfo "Log folder is $logFolder"
        }
        finally
        {
            # If we still have a WIM image open, close it.
            if ($openWim -ne $null)
            {
                Write-W2VInfo "Closing Windows image..."
                $openWim.Close()
            }

            # If we still have a registry hive mounted, dismount it.
            if ($mountedHive -ne $null)
            {
                Write-W2VInfo "Closing registry hive..."
                Dismount-RegistryHive -HiveMountPoint $mountedHive
            }

            # If VHD is mounted, unmount it
            if (Test-Path $VHDPath)
            {
                if ($hyperVEnabled)
                {
                    if ((Get-VHD -Path $VHDPath).Attached)
                    {
                        Dismount-VHD -Path $VHDPath
                    }
                }
                else
                {
                    Dismount-DiskImage -ImagePath $VHDPath
                }
            }

            # If we still have an ISO open, close it.
            if ($openIso -ne $null)
            {
                Write-W2VInfo "Closing ISO..."
                Dismount-DiskImage $ISOPath
            }

            if (-not $CacheSource)
            {
                if ($tempSource -and (Test-Path $tempSource))
                {
                    Remove-Item -Path $tempSource -Force
                }
            }

            # Close out the transcript and tell the user we're done.
            Dismount-ISO
            Write-W2VInfo "Done."
            if ($transcripting)
            {
                $null = Stop-Transcript
            }
        }
    }

    End
    {
        if ($Passthru)
        {
            return $vhd
        }
    }
    #endregion Code

}

function Add-WindowsImageTypes {
        $code      = @"
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Xml.Linq;
using System.Xml.XPath;
using Microsoft.Win32.SafeHandles;

namespace WIM2VHD
{

/// <summary>
/// P/Invoke methods and associated enums, flags, and structs.
/// </summary>
public class
NativeMethods
{

    #region Delegates and Callbacks
    #region WIMGAPI

    ///<summary>
    ///User-defined function used with the RegisterMessageCallback or UnregisterMessageCallback function.
    ///</summary>
    ///<param name="MessageId">Specifies the message being sent.</param>
    ///<param name="wParam">Specifies additional message information. The contents of this parameter depend on the value of the
    ///MessageId parameter.</param>
    ///<param name="lParam">Specifies additional message information. The contents of this parameter depend on the value of the
    ///MessageId parameter.</param>
    ///<param name="UserData">Specifies the user-defined value passed to RegisterCallback.</param>
    ///<returns>
    ///To indicate success and to enable other subscribers to process the message return WIM_MSG_SUCCESS.
    ///To prevent other subscribers from receiving the message, return WIM_MSG_DONE.
    ///To cancel an image apply or capture, return WIM_MSG_ABORT_IMAGE when handling the WIM_MSG_PROCESS message.
    ///</returns>
    public delegate uint
    WimMessageCallback(
        uint   MessageId,
        IntPtr wParam,
        IntPtr lParam,
        IntPtr UserData
    );

    public static void
    RegisterMessageCallback(
        WimFileHandle hWim,
        WimMessageCallback callback)
        {

        uint _callback = NativeMethods.WimRegisterMessageCallback(hWim, callback, IntPtr.Zero);
        int rc = Marshal.GetLastWin32Error();
        if (0 != rc)
        {
            // Throw an exception if something bad happened on the Win32 end.
            throw
                new InvalidOperationException(
                    string.Format(
                        CultureInfo.CurrentCulture,
                        "Unable to register message callback."
            ));
        }
    }

    public static void
    UnregisterMessageCallback(
        WimFileHandle hWim,
        WimMessageCallback registeredCallback)
        {

        bool status = NativeMethods.WimUnregisterMessageCallback(hWim, registeredCallback);
        int rc = Marshal.GetLastWin32Error();
        if (!status)
        {
            throw
                new InvalidOperationException(
                    string.Format(
                        CultureInfo.CurrentCulture,
                        "Unable to unregister message callback."
            ));
        }
    }

    #endregion WIMGAPI
    #endregion Delegates and Callbacks

    #region Constants

    #region VDiskInterop

    /// <summary>
    /// The default depth in a VHD parent chain that this library will search through.
    /// If you want to go more than one disk deep into the parent chain, provide a different value.
    /// </summary>
    public   const uint  OPEN_VIRTUAL_DISK_RW_DEFAULT_DEPTH   = 0x00000001;

    public   const uint  DEFAULT_BLOCK_SIZE                   = 0x00080000;
    public   const uint  DISK_SECTOR_SIZE                     = 0x00000200;

    internal const uint  ERROR_VIRTDISK_NOT_VIRTUAL_DISK      = 0xC03A0015;
    internal const uint  ERROR_NOT_FOUND                      = 0x00000490;
    internal const uint  ERROR_IO_PENDING                     = 0x000003E5;
    internal const uint  ERROR_INSUFFICIENT_BUFFER            = 0x0000007A;
    internal const uint  ERROR_ERROR_DEV_NOT_EXIST            = 0x00000037;
    internal const uint  ERROR_BAD_COMMAND                    = 0x00000016;
    internal const uint  ERROR_SUCCESS                        = 0x00000000;

    public   const uint  GENERIC_READ                         = 0x80000000;
    public   const uint  GENERIC_WRITE                        = 0x40000000;
    public   const short FILE_ATTRIBUTE_NORMAL                = 0x00000080;
    public   const uint  CREATE_NEW                           = 0x00000001;
    public   const uint  CREATE_ALWAYS                        = 0x00000002;
    public   const uint  OPEN_EXISTING                        = 0x00000003;
    public   const short INVALID_HANDLE_VALUE                 = -1;

    internal static Guid VirtualStorageTypeVendorUnknown      = new Guid("00000000-0000-0000-0000-000000000000");
    internal static Guid VirtualStorageTypeVendorMicrosoft    = new Guid("EC984AEC-A0F9-47e9-901F-71415A66345B");

    #endregion VDiskInterop

    #region WIMGAPI

    public   const uint  WIM_FLAG_VERIFY                      = 0x00000002;
    public   const uint  WIM_FLAG_INDEX                       = 0x00000004;

    public   const uint  WM_APP                               = 0x00008000;

    #endregion WIMGAPI

    #endregion Constants

    #region Enums and Flags

    #region VDiskInterop

    /// <summary>
    /// Indicates the version of the virtual disk to create.
    /// </summary>
    public enum CreateVirtualDiskVersion : int
    {
        VersionUnspecified         = 0x00000000,
        Version1                   = 0x00000001,
        Version2                   = 0x00000002
    }

    public enum OpenVirtualDiskVersion : int
    {
        VersionUnspecified         = 0x00000000,
        Version1                   = 0x00000001,
        Version2                   = 0x00000002
    }

    /// <summary>
    /// Contains the version of the virtual hard disk (VHD) ATTACH_VIRTUAL_DISK_PARAMETERS structure to use in calls to VHD functions.
    /// </summary>
    public enum AttachVirtualDiskVersion : int
    {
        VersionUnspecified         = 0x00000000,
        Version1                   = 0x00000001,
        Version2                   = 0x00000002
    }

    public enum CompactVirtualDiskVersion : int
    {
        VersionUnspecified         = 0x00000000,
        Version1                   = 0x00000001
    }

    /// <summary>
    /// Contains the type and provider (vendor) of the virtual storage device.
    /// </summary>
    public enum VirtualStorageDeviceType : int
    {
        /// <summary>
        /// The storage type is unknown or not valid.
        /// </summary>
        Unknown                    = 0x00000000,
        /// <summary>
        /// For internal use only.  This type is not supported.
        /// </summary>
        ISO                        = 0x00000001,
        /// <summary>
        /// Virtual Hard Disk device type.
        /// </summary>
        VHD                        = 0x00000002,
        /// <summary>
        /// Virtual Hard Disk v2 device type.
        /// </summary>
        VHDX                       = 0x00000003
    }

    /// <summary>
    /// Contains virtual hard disk (VHD) open request flags.
    /// </summary>
    [Flags]
    public enum OpenVirtualDiskFlags
    {
        /// <summary>
        /// No flags. Use system defaults.
        /// </summary>
        None                       = 0x00000000,
        /// <summary>
        /// Open the VHD file (backing store) without opening any differencing-chain parents. Used to correct broken parent links.
        /// </summary>
        NoParents                  = 0x00000001,
        /// <summary>
        /// Reserved.
        /// </summary>
        BlankFile                  = 0x00000002,
        /// <summary>
        /// Reserved.
        /// </summary>
        BootDrive                  = 0x00000004,
    }

    /// <summary>
    /// Contains the bit mask for specifying access rights to a virtual hard disk (VHD).
    /// </summary>
    [Flags]
    public enum VirtualDiskAccessMask
    {
        /// <summary>
        /// Only Version2 of OpenVirtualDisk API accepts this parameter
        /// </summary>
        None                       = 0x00000000,
        /// <summary>
        /// Open the virtual disk for read-only attach access. The caller must have READ access to the virtual disk image file.
        /// </summary>
        /// <remarks>
        /// If used in a request to open a virtual disk that is already open, the other handles must be limited to either
        /// VIRTUAL_DISK_ACCESS_DETACH or VIRTUAL_DISK_ACCESS_GET_INFO access, otherwise the open request with this flag will fail.
        /// </remarks>
        AttachReadOnly             = 0x00010000,
        /// <summary>
        /// Open the virtual disk for read-write attaching access. The caller must have (READ | WRITE) access to the virtual disk image file.
        /// </summary>
        /// <remarks>
        /// If used in a request to open a virtual disk that is already open, the other handles must be limited to either
        /// VIRTUAL_DISK_ACCESS_DETACH or VIRTUAL_DISK_ACCESS_GET_INFO access, otherwise the open request with this flag will fail.
        /// If the virtual disk is part of a differencing chain, the disk for this request cannot be less than the readWriteDepth specified
        /// during the prior open request for that differencing chain.
        /// </remarks>
        AttachReadWrite            = 0x00020000,
        /// <summary>
        /// Open the virtual disk to allow detaching of an attached virtual disk. The caller must have
        /// (FILE_READ_ATTRIBUTES | FILE_READ_DATA) access to the virtual disk image file.
        /// </summary>
        Detach                     = 0x00040000,
        /// <summary>
        /// Information retrieval access to the virtual disk. The caller must have READ access to the virtual disk image file.
        /// </summary>
        GetInfo                    = 0x00080000,
        /// <summary>
        /// Virtual disk creation access.
        /// </summary>
        Create                     = 0x00100000,
        /// <summary>
        /// Open the virtual disk to perform offline meta-operations. The caller must have (READ | WRITE) access to the virtual
        /// disk image file, up to readWriteDepth if working with a differencing chain.
        /// </summary>
        /// <remarks>
        /// If the virtual disk is part of a differencing chain, the backing store (host volume) is opened in RW exclusive mode up to readWriteDepth.
        /// </remarks>
        MetaOperations             = 0x00200000,
        /// <summary>
        /// Reserved.
        /// </summary>
        Read                       = 0x000D0000,
        /// <summary>
        /// Allows unrestricted access to the virtual disk. The caller must have unrestricted access rights to the virtual disk image file.
        /// </summary>
        All                        = 0x003F0000,
        /// <summary>
        /// Reserved.
        /// </summary>
        Writable                   = 0x00320000
    }

    /// <summary>
    /// Contains virtual hard disk (VHD) creation flags.
    /// </summary>
    [Flags]
    public enum CreateVirtualDiskFlags
    {
        /// <summary>
        /// Contains virtual hard disk (VHD) creation flags.
        /// </summary>
        None                       = 0x00000000,
        /// <summary>
        /// Pre-allocate all physical space necessary for the size of the virtual disk.
        /// </summary>
        /// <remarks>
        /// The CREATE_VIRTUAL_DISK_FLAG_FULL_PHYSICAL_ALLOCATION flag is used for the creation of a fixed VHD.
        /// </remarks>
        FullPhysicalAllocation     = 0x00000001
    }

    /// <summary>
    /// Contains virtual disk attach request flags.
    /// </summary>
    [Flags]
    public enum AttachVirtualDiskFlags
    {
        /// <summary>
        /// No flags. Use system defaults.
        /// </summary>
        None                       = 0x00000000,
        /// <summary>
        /// Attach the virtual disk as read-only.
        /// </summary>
        ReadOnly                   = 0x00000001,
        /// <summary>
        /// No drive letters are assigned to the disk's volumes.
        /// </summary>
        /// <remarks>Oddly enough, this doesn't apply to NTFS mount points.</remarks>
        NoDriveLetter              = 0x00000002,
        /// <summary>
        /// Will decouple the virtual disk lifetime from that of the VirtualDiskHandle.
        /// The virtual disk will be attached until the Detach() function is called, even if all open handles to the virtual disk are closed.
        /// </summary>
        PermanentLifetime          = 0x00000004,
        /// <summary>
        /// Reserved.
        /// </summary>
        NoLocalHost                = 0x00000008
    }

    [Flags]
    public enum DetachVirtualDiskFlag
    {
        None                       = 0x00000000
    }

    [Flags]
    public enum CompactVirtualDiskFlags
    {
        None                       = 0x00000000,
        NoZeroScan                 = 0x00000001,
        NoBlockMoves               = 0x00000002
    }

    #endregion VDiskInterop

    #region WIMGAPI

    [FlagsAttribute]
    internal enum
    WimCreateFileDesiredAccess : uint
        {
        WimQuery                   = 0x00000000,
        WimGenericRead             = 0x80000000
    }

    public enum WimMessage : uint
    {
        WIM_MSG                    = WM_APP + 0x1476,
        WIM_MSG_TEXT,
        ///<summary>
        ///Indicates an update in the progress of an image application.
        ///</summary>
        WIM_MSG_PROGRESS,
        ///<summary>
        ///Enables the caller to prevent a file or a directory from being captured or applied.
        ///</summary>
        WIM_MSG_PROCESS,
        ///<summary>
        ///Indicates that volume information is being gathered during an image capture.
        ///</summary>
        WIM_MSG_SCANNING,
        ///<summary>
        ///Indicates the number of files that will be captured or applied.
        ///</summary>
        WIM_MSG_SETRANGE,
        ///<summary>
        ///Indicates the number of files that have been captured or applied.
        ///</summary>
        WIM_MSG_SETPOS,
        ///<summary>
        ///Indicates that a file has been either captured or applied.
        ///</summary>
        WIM_MSG_STEPIT,
        ///<summary>
        ///Enables the caller to prevent a file resource from being compressed during a capture.
        ///</summary>
        WIM_MSG_COMPRESS,
        ///<summary>
        ///Alerts the caller that an error has occurred while capturing or applying an image.
        ///</summary>
        WIM_MSG_ERROR,
        ///<summary>
        ///Enables the caller to align a file resource on a particular alignment boundary.
        ///</summary>
        WIM_MSG_ALIGNMENT,
        WIM_MSG_RETRY,
        ///<summary>
        ///Enables the caller to align a file resource on a particular alignment boundary.
        ///</summary>
        WIM_MSG_SPLIT,
        WIM_MSG_SUCCESS            = 0x00000000,
        WIM_MSG_ABORT_IMAGE        = 0xFFFFFFFF
    }

    internal enum
    WimCreationDisposition : uint
        {
        WimOpenExisting            = 0x00000003,
    }

    internal enum
    WimActionFlags : uint
        {
        WimIgnored                 = 0x00000000
    }

    internal enum
    WimCompressionType : uint
        {
        WimIgnored                 = 0x00000000
    }

    internal enum
    WimCreationResult : uint
        {
        WimCreatedNew              = 0x00000000,
        WimOpenedExisting          = 0x00000001
    }

    #endregion WIMGAPI

    #endregion Enums and Flags

    #region Structs

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CreateVirtualDiskParameters
    {
        /// <summary>
        /// A CREATE_VIRTUAL_DISK_VERSION enumeration that specifies the version of the CREATE_VIRTUAL_DISK_PARAMETERS structure being passed to or from the virtual hard disk (VHD) functions.
        /// </summary>
        public CreateVirtualDiskVersion Version;

        /// <summary>
        /// Unique identifier to assign to the virtual disk object. If this member is set to zero, a unique identifier is created by the system.
        /// </summary>
        public Guid UniqueId;

        /// <summary>
        /// The maximum virtual size of the virtual disk object. Must be a multiple of 512.
        /// If a ParentPath is specified, this value must be zero.
        /// If a SourcePath is specified, this value can be zero to specify the size of the source VHD to be used, otherwise the size specified must be greater than or equal to the size of the source disk.
        /// </summary>
        public ulong MaximumSize;

        /// <summary>
        /// Internal size of the virtual disk object blocks.
        /// The following are predefined block sizes and their behaviors. For a fixed VHD type, this parameter must be zero.
        /// </summary>
        public uint BlockSizeInBytes;

        /// <summary>
        /// Internal size of the virtual disk object sectors. Must be set to 512.
        /// </summary>
        public uint SectorSizeInBytes;

        /// <summary>
        /// Optional path to a parent virtual disk object. Associates the new virtual disk with an existing virtual disk.
        /// If this parameter is not NULL, SourcePath must be NULL.
        /// </summary>
        public string ParentPath;

        /// <summary>
        /// Optional path to pre-populate the new virtual disk object with block data from an existing disk. This path may refer to a VHD or a physical disk.
        /// If this parameter is not NULL, ParentPath must be NULL.
        /// </summary>
        public string SourcePath;

        /// <summary>
        /// Flags for opening the VHD
        /// </summary>
        public OpenVirtualDiskFlags OpenFlags;

        /// <summary>
        /// GetInfoOnly flag for V2 handles
        /// </summary>
        public bool GetInfoOnly;

        /// <summary>
        /// Virtual Storage Type of the parent disk
        /// </summary>
        public VirtualStorageType ParentVirtualStorageType;

        /// <summary>
        /// Virtual Storage Type of the source disk
        /// </summary>
        public VirtualStorageType SourceVirtualStorageType;

        /// <summary>
        /// A GUID to use for fallback resiliency over SMB.
        /// </summary>
        public Guid ResiliencyGuid;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct VirtualStorageType
    {
        public VirtualStorageDeviceType DeviceId;
        public Guid VendorId;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SecurityDescriptor
    {
        public byte revision;
        public byte size;
        public short control;
        public IntPtr owner;
        public IntPtr group;
        public IntPtr sacl;
        public IntPtr dacl;
    }

    #endregion Structs

    #region VirtDisk.DLL P/Invoke

    [DllImport("virtdisk.dll", CharSet = CharSet.Unicode)]
    public static extern uint
    CreateVirtualDisk(
        [In, Out] ref VirtualStorageType VirtualStorageType,
        [In]          string Path,
        [In]          VirtualDiskAccessMask VirtualDiskAccessMask,
        [In, Out] ref SecurityDescriptor SecurityDescriptor,
        [In]          CreateVirtualDiskFlags Flags,
        [In]          uint ProviderSpecificFlags,
        [In, Out] ref CreateVirtualDiskParameters Parameters,
        [In]          IntPtr Overlapped,
        [Out]     out SafeFileHandle Handle);

    #endregion VirtDisk.DLL P/Invoke

    #region Win32 P/Invoke

    [DllImport("advapi32", SetLastError = true)]
    public static extern bool InitializeSecurityDescriptor(
        [Out]     out SecurityDescriptor pSecurityDescriptor,
        [In]          uint dwRevision);

    #endregion Win32 P/Invoke

    #region WIMGAPI P/Invoke

    #region SafeHandle wrappers for WimFileHandle and WimImageHandle

    public sealed class WimFileHandle : SafeHandle
    {

        public WimFileHandle(
            string wimPath)
            : base(IntPtr.Zero, true)
            {

            if (String.IsNullOrEmpty(wimPath))
            {
                throw new ArgumentNullException("wimPath");
            }

            if (!File.Exists(Path.GetFullPath(wimPath)))
            {
                throw new FileNotFoundException((new FileNotFoundException()).Message, wimPath);
            }

            NativeMethods.WimCreationResult creationResult;

            this.handle = NativeMethods.WimCreateFile(
                wimPath,
                NativeMethods.WimCreateFileDesiredAccess.WimGenericRead,
                NativeMethods.WimCreationDisposition.WimOpenExisting,
                NativeMethods.WimActionFlags.WimIgnored,
                NativeMethods.WimCompressionType.WimIgnored,
                out creationResult
            );

            // Check results.
            if (creationResult != NativeMethods.WimCreationResult.WimOpenedExisting)
            {
                throw new Win32Exception();
            }

            if (this.handle == IntPtr.Zero)
            {
                throw new Win32Exception();
            }

            // Set the temporary path.
            NativeMethods.WimSetTemporaryPath(
                this,
                Environment.ExpandEnvironmentVariables("%TEMP%")
            );
        }

        protected override bool ReleaseHandle()
        {
            return NativeMethods.WimCloseHandle(this.handle);
        }

        public override bool IsInvalid
        {
            get { return this.handle == IntPtr.Zero; }
        }
    }

    public sealed class WimImageHandle : SafeHandle
    {
        public WimImageHandle(
            WimFile Container,
            uint ImageIndex)
            : base(IntPtr.Zero, true)
            {

            if (null == Container)
            {
                throw new ArgumentNullException("Container");
            }

            if ((Container.Handle.IsClosed) || (Container.Handle.IsInvalid))
            {
                throw new ArgumentNullException("The handle to the WIM file has already been closed, or is invalid.", "Container");
            }

            if (ImageIndex > Container.ImageCount)
            {
                throw new ArgumentOutOfRangeException("ImageIndex", "The index does not exist in the specified WIM file.");
            }

            this.handle = NativeMethods.WimLoadImage(
                Container.Handle.DangerousGetHandle(),
                ImageIndex);
        }

        protected override bool ReleaseHandle()
        {
            return NativeMethods.WimCloseHandle(this.handle);
        }

        public override bool IsInvalid
        {
            get { return this.handle == IntPtr.Zero; }
        }
    }

    #endregion SafeHandle wrappers for WimFileHandle and WimImageHandle

    [DllImport("Wimgapi.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "WIMCreateFile")]
    internal static extern IntPtr
    WimCreateFile(
        [In, MarshalAs(UnmanagedType.LPWStr)] string WimPath,
        [In]    WimCreateFileDesiredAccess DesiredAccess,
        [In]    WimCreationDisposition CreationDisposition,
        [In]    WimActionFlags FlagsAndAttributes,
        [In]    WimCompressionType CompressionType,
        [Out, Optional] out WimCreationResult CreationResult
    );

    [DllImport("Wimgapi.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "WIMCloseHandle")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool
    WimCloseHandle(
        [In]    IntPtr Handle
    );

    [DllImport("Wimgapi.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "WIMLoadImage")]
    internal static extern IntPtr
    WimLoadImage(
        [In]    IntPtr Handle,
        [In]    uint ImageIndex
    );

    [DllImport("Wimgapi.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "WIMGetImageCount")]
    internal static extern uint
    WimGetImageCount(
        [In]    WimFileHandle Handle
    );

    [DllImport("Wimgapi.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "WIMGetImageInformation")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool
    WimGetImageInformation(
        [In]        SafeHandle Handle,
        [Out]   out StringBuilder ImageInfo,
        [Out]   out uint SizeOfImageInfo
    );

    [DllImport("Wimgapi.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "WIMSetTemporaryPath")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool
    WimSetTemporaryPath(
        [In]    WimFileHandle Handle,
        [In]    string TempPath
    );

    [DllImport("Wimgapi.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "WIMRegisterMessageCallback", CallingConvention = CallingConvention.StdCall)]
    internal static extern uint
    WimRegisterMessageCallback(
        [In, Optional] WimFileHandle      hWim,
        [In]           WimMessageCallback MessageProc,
        [In, Optional] IntPtr             ImageInfo
    );

    [DllImport("Wimgapi.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "WIMUnregisterMessageCallback", CallingConvention = CallingConvention.StdCall)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool
    WimUnregisterMessageCallback(
        [In, Optional] WimFileHandle      hWim,
        [In]           WimMessageCallback MessageProc
    );


    #endregion WIMGAPI P/Invoke
}

#region WIM Interop

public class WimFile
{

    internal XDocument m_xmlInfo;
    internal List<WimImage> m_imageList;

    private static NativeMethods.WimMessageCallback wimMessageCallback;

    #region Events

    /// <summary>
    /// DefaultImageEvent handler
    /// </summary>
    public delegate void DefaultImageEventHandler(object sender, DefaultImageEventArgs e);

    ///<summary>
    ///ProcessFileEvent handler
    ///</summary>
    public delegate void ProcessFileEventHandler(object sender, ProcessFileEventArgs e);

    ///<summary>
    ///Enable the caller to prevent a file resource from being compressed during a capture.
    ///</summary>
    public event ProcessFileEventHandler ProcessFileEvent;

    ///<summary>
    ///Indicate an update in the progress of an image application.
    ///</summary>
    public event DefaultImageEventHandler ProgressEvent;

    ///<summary>
    ///Alert the caller that an error has occurred while capturing or applying an image.
    ///</summary>
    public event DefaultImageEventHandler ErrorEvent;

    ///<summary>
    ///Indicate that a file has been either captured or applied.
    ///</summary>
    public event DefaultImageEventHandler StepItEvent;

    ///<summary>
    ///Indicate the number of files that will be captured or applied.
    ///</summary>
    public event DefaultImageEventHandler SetRangeEvent;

    ///<summary>
    ///Indicate the number of files that have been captured or applied.
    ///</summary>
    public event DefaultImageEventHandler SetPosEvent;

    #endregion Events

    private
    enum
    ImageEventMessage : uint
    {
        ///<summary>
        ///Enables the caller to prevent a file or a directory from being captured or applied.
        ///</summary>
        Progress = NativeMethods.WimMessage.WIM_MSG_PROGRESS,
        ///<summary>
        ///Notification sent to enable the caller to prevent a file or a directory from being captured or applied.
        ///To prevent a file or a directory from being captured or applied, call WindowsImageContainer.SkipFile().
        ///</summary>
        Process = NativeMethods.WimMessage.WIM_MSG_PROCESS,
        ///<summary>
        ///Enables the caller to prevent a file resource from being compressed during a capture.
        ///</summary>
        Compress = NativeMethods.WimMessage.WIM_MSG_COMPRESS,
        ///<summary>
        ///Alerts the caller that an error has occurred while capturing or applying an image.
        ///</summary>
        Error = NativeMethods.WimMessage.WIM_MSG_ERROR,
        ///<summary>
        ///Enables the caller to align a file resource on a particular alignment boundary.
        ///</summary>
        Alignment = NativeMethods.WimMessage.WIM_MSG_ALIGNMENT,
        ///<summary>
        ///Enables the caller to align a file resource on a particular alignment boundary.
        ///</summary>
        Split = NativeMethods.WimMessage.WIM_MSG_SPLIT,
        ///<summary>
        ///Indicates that volume information is being gathered during an image capture.
        ///</summary>
        Scanning = NativeMethods.WimMessage.WIM_MSG_SCANNING,
        ///<summary>
        ///Indicates the number of files that will be captured or applied.
        ///</summary>
        SetRange = NativeMethods.WimMessage.WIM_MSG_SETRANGE,
        ///<summary>
        ///Indicates the number of files that have been captured or applied.
        /// </summary>
        SetPos = NativeMethods.WimMessage.WIM_MSG_SETPOS,
        ///<summary>
        ///Indicates that a file has been either captured or applied.
        ///</summary>
        StepIt = NativeMethods.WimMessage.WIM_MSG_STEPIT,
        ///<summary>
        ///Success.
        ///</summary>
        Success = NativeMethods.WimMessage.WIM_MSG_SUCCESS,
        ///<summary>
        ///Abort.
        ///</summary>
        Abort = NativeMethods.WimMessage.WIM_MSG_ABORT_IMAGE
    }

    ///<summary>
    ///Event callback to the Wimgapi events
    ///</summary>
    private
    uint
    ImageEventMessagePump(
        uint MessageId,
        IntPtr wParam,
        IntPtr lParam,
        IntPtr UserData)
        {

        uint status = (uint) NativeMethods.WimMessage.WIM_MSG_SUCCESS;

        DefaultImageEventArgs eventArgs = new DefaultImageEventArgs(wParam, lParam, UserData);

        switch ((ImageEventMessage)MessageId)
        {

            case ImageEventMessage.Progress:
                ProgressEvent(this, eventArgs);
                break;

            case ImageEventMessage.Process:
                if (null != ProcessFileEvent)
                {
                    string fileToImage = Marshal.PtrToStringUni(wParam);
                    ProcessFileEventArgs fileToProcess = new ProcessFileEventArgs(fileToImage, lParam);
                    ProcessFileEvent(this, fileToProcess);

                    if (fileToProcess.Abort == true)
                    {
                        status = (uint)ImageEventMessage.Abort;
                    }
                }
                break;

            case ImageEventMessage.Error:
                if (null != ErrorEvent)
                {
                    ErrorEvent(this, eventArgs);
                }
                break;

            case ImageEventMessage.SetRange:
                if (null != SetRangeEvent)
                {
                    SetRangeEvent(this, eventArgs);
                }
                break;

            case ImageEventMessage.SetPos:
                if (null != SetPosEvent)
                {
                    SetPosEvent(this, eventArgs);
                }
                break;

            case ImageEventMessage.StepIt:
                if (null != StepItEvent)
                {
                    StepItEvent(this, eventArgs);
                }
                break;

            default:
                break;
        }
        return status;

    }

    /// <summary>
    /// Constructor.
    /// </summary>
    /// <param name="wimPath">Path to the WIM container.</param>
    public
    WimFile(string wimPath)
    {
        if (string.IsNullOrEmpty(wimPath))
        {
            throw new ArgumentNullException("wimPath");
        }

        if (!File.Exists(Path.GetFullPath(wimPath)))
        {
            throw new FileNotFoundException((new FileNotFoundException()).Message, wimPath);
        }

        Handle = new NativeMethods.WimFileHandle(wimPath);

        // Hook up the events before we return.
        //wimMessageCallback = new NativeMethods.WimMessageCallback(ImageEventMessagePump);
        //NativeMethods.RegisterMessageCallback(this.Handle, wimMessageCallback);
    }

    /// <summary>
    /// Closes the WIM file.
    /// </summary>
    public void
    Close()
    {
        foreach (WimImage image in Images)
        {
            image.Close();
        }

        if (null != wimMessageCallback)
        {
            NativeMethods.UnregisterMessageCallback(this.Handle, wimMessageCallback);
            wimMessageCallback = null;
        }

        if ((!Handle.IsClosed) && (!Handle.IsInvalid))
        {
            Handle.Close();
        }
    }

    /// <summary>
    /// Provides a list of WimImage objects, representing the images in the WIM container file.
    /// </summary>
    public List<WimImage>
    Images
    {
        get
        {
            if (null == m_imageList)
            {

                int imageCount = (int)ImageCount;
                m_imageList = new List<WimImage>(imageCount);
                for (int i = 0; i < imageCount; i++)
                {

                    // Load up each image so it's ready for us.
                    m_imageList.Add(
                        new WimImage(this, (uint)i + 1));
                }
            }

            return m_imageList;
        }
    }

    /// <summary>
    /// Provides a list of names of the images in the specified WIM container file.
    /// </summary>
    public List<string>
    ImageNames
    {
        get
        {
            List<string> nameList = new List<string>();
            foreach (WimImage image in Images)
            {
                nameList.Add(image.ImageName);
            }
            return nameList;
        }
    }

    /// <summary>
    /// Indexer for WIM images inside the WIM container, indexed by the image number.
    /// The list of Images is 0-based, but the WIM container is 1-based, so we automatically compensate for that.
    /// this[1] returns the 0th image in the WIM container.
    /// </summary>
    /// <param name="ImageIndex">The 1-based index of the image to retrieve.</param>
    /// <returns>WinImage object.</returns>
    public WimImage
    this[int ImageIndex]
    {
        get { return Images[ImageIndex - 1]; }
    }

    /// <summary>
    /// Indexer for WIM images inside the WIM container, indexed by the image name.
    /// WIMs created by different processes sometimes contain different information - including the name.
    /// Some images have their name stored in the Name field, some in the Flags field, and some in the EditionID field.
    /// We take all of those into account in while searching the WIM.
    /// </summary>
    /// <param name="ImageName"></param>
    /// <returns></returns>
    public WimImage
    this[string ImageName]
    {
        get
        {
            return
                Images.Where(i => (
                    i.ImageName.ToUpper()  == ImageName.ToUpper() ||
                    i.ImageFlags.ToUpper() == ImageName.ToUpper() ))
                .DefaultIfEmpty(null)
                    .FirstOrDefault<WimImage>();
        }
    }

    /// <summary>
    /// Returns the number of images in the WIM container.
    /// </summary>
    internal uint
    ImageCount
    {
        get { return NativeMethods.WimGetImageCount(Handle); }
    }

    /// <summary>
    /// Returns an XDocument representation of the XML metadata for the WIM container and associated images.
    /// </summary>
    internal XDocument
    XmlInfo
    {
        get
        {

            if (null == m_xmlInfo)
            {
                StringBuilder builder;
                uint bytes;
                if (!NativeMethods.WimGetImageInformation(Handle, out builder, out bytes))
                {
                    throw new Win32Exception();
                }

                // Ensure the length of the returned bytes to avoid garbage characters at the end.
                int charCount = (int)bytes / sizeof(char);
                if (null != builder)
                {
                    // Get rid of the unicode file marker at the beginning of the XML.
                    builder.Remove(0, 1);
                    builder.EnsureCapacity(charCount - 1);
                    builder.Length = charCount - 1;

                    // This isn't likely to change while we have the image open, so cache it.
                    m_xmlInfo = XDocument.Parse(builder.ToString().Trim());
                }
                else
                {
                    m_xmlInfo = null;
                }
            }

            return m_xmlInfo;
        }
    }

    public NativeMethods.WimFileHandle Handle
    {
        get;
        private set;
    }
}

public class
WimImage
{

    internal XDocument m_xmlInfo;

    public
    WimImage(
        WimFile Container,
        uint ImageIndex)
        {

        if (null == Container)
        {
            throw new ArgumentNullException("Container");
        }

        if ((Container.Handle.IsClosed) || (Container.Handle.IsInvalid))
        {
            throw new ArgumentNullException("The handle to the WIM file has already been closed, or is invalid.", "Container");
        }

        if (ImageIndex > Container.ImageCount)
        {
            throw new ArgumentOutOfRangeException("ImageIndex", "The index does not exist in the specified WIM file.");
        }

        Handle = new NativeMethods.WimImageHandle(Container, ImageIndex);
    }

    public enum
    Architectures : uint
    {
        x86   = 0x0,
        ARM   = 0x5,
        IA64  = 0x6,
        AMD64 = 0x9,
        ARM64 = 0xC
    }

    public void
    Close()
    {
        if ((!Handle.IsClosed) && (!Handle.IsInvalid))
        {
            Handle.Close();
        }
    }

    public NativeMethods.WimImageHandle
    Handle
    {
        get;
        private set;
    }

    internal XDocument
    XmlInfo
    {
        get
        {

            if (null == m_xmlInfo)
            {
                StringBuilder builder;
                uint bytes;
                if (!NativeMethods.WimGetImageInformation(Handle, out builder, out bytes))
                {
                    throw new Win32Exception();
                }

                // Ensure the length of the returned bytes to avoid garbage characters at the end.
                int charCount = (int)bytes / sizeof(char);
                if (null != builder)
                {
                    // Get rid of the unicode file marker at the beginning of the XML.
                    builder.Remove(0, 1);
                    builder.EnsureCapacity(charCount - 1);
                    builder.Length = charCount - 1;

                    // This isn't likely to change while we have the image open, so cache it.
                    m_xmlInfo = XDocument.Parse(builder.ToString().Trim());
                }
                else
                {
                    m_xmlInfo = null;
                }
            }

            return m_xmlInfo;
        }
    }

    public string
    ImageIndex
    {
        get { return XmlInfo.Element("IMAGE").Attribute("INDEX").Value; }
    }

    public string
    ImageName
    {
        get { return XmlInfo.XPathSelectElement("/IMAGE/NAME").Value; }
    }

    public string
    ImageEditionId
    {
        get { return XmlInfo.XPathSelectElement("/IMAGE/WINDOWS/EDITIONID").Value; }
    }

    public string
    ImageFlags
    {
        get
        {
            string flagValue = String.Empty;

            try
            {
                flagValue = XmlInfo.XPathSelectElement("/IMAGE/FLAGS").Value;
            }
            catch
            {

                // Some WIM files don't contain a FLAGS element in the metadata.
                // In an effort to support those WIMs too, inherit the EditionId if there
                // are no Flags.

                if (String.IsNullOrEmpty(flagValue))
                {
                    flagValue = this.ImageEditionId;

                    // Check to see if the EditionId is "ServerHyper".  If so,
                    // tweak it to be "ServerHyperCore" instead.

                    if (0 == String.Compare("serverhyper", flagValue, true))
                    {
                        flagValue = "ServerHyperCore";
                    }
                }

            }

            return flagValue;
        }
    }

    public string
    ImageProductType
    {
        get { return XmlInfo.XPathSelectElement("/IMAGE/WINDOWS/PRODUCTTYPE").Value; }
    }

    public string
    ImageInstallationType
    {
        get { return XmlInfo.XPathSelectElement("/IMAGE/WINDOWS/INSTALLATIONTYPE").Value; }
    }

    public string
    ImageDescription
    {
        get { return XmlInfo.XPathSelectElement("/IMAGE/DESCRIPTION").Value; }
    }

    public ulong
    ImageSize
    {
        get { return ulong.Parse(XmlInfo.XPathSelectElement("/IMAGE/TOTALBYTES").Value); }
    }

    public Architectures
    ImageArchitecture
    {
        get
        {
            int arch = -1;
            try
            {
                arch = int.Parse(XmlInfo.XPathSelectElement("/IMAGE/WINDOWS/ARCH").Value);
            }
            catch { }

            return (Architectures)arch;
        }
    }

    public string
    ImageDefaultLanguage
    {
        get
        {
            string lang = null;
            try
            {
                lang = XmlInfo.XPathSelectElement("/IMAGE/WINDOWS/LANGUAGES/DEFAULT").Value;
            }
            catch { }

            return lang;
        }
    }

    public Version
    ImageVersion
    {
        get
        {
            int major = 0;
            int minor = 0;
            int build = 0;
            int revision = 0;

            try
            {
                major = int.Parse(XmlInfo.XPathSelectElement("/IMAGE/WINDOWS/VERSION/MAJOR").Value);
                minor = int.Parse(XmlInfo.XPathSelectElement("/IMAGE/WINDOWS/VERSION/MINOR").Value);
                build = int.Parse(XmlInfo.XPathSelectElement("/IMAGE/WINDOWS/VERSION/BUILD").Value);
                revision = int.Parse(XmlInfo.XPathSelectElement("/IMAGE/WINDOWS/VERSION/SPBUILD").Value);
            }
            catch { }

            return (new Version(major, minor, build, revision));
        }
    }

    public string
    ImageDisplayName
    {
        get { return XmlInfo.XPathSelectElement("/IMAGE/DISPLAYNAME").Value; }
    }

    public string
    ImageDisplayDescription
    {
        get { return XmlInfo.XPathSelectElement("/IMAGE/DISPLAYDESCRIPTION").Value; }
    }
}

///<summary>
///Describes the file that is being processed for the ProcessFileEvent.
///</summary>
public class
DefaultImageEventArgs : EventArgs
{
    ///<summary>
    ///Default constructor.
    ///</summary>
    public
    DefaultImageEventArgs(
        IntPtr wideParameter,
        IntPtr leftParameter,
        IntPtr userData)
    {

        WideParameter = wideParameter;
        LeftParameter = leftParameter;
        UserData      = userData;
    }

    ///<summary>
    ///wParam
    ///</summary>
    public IntPtr WideParameter
    {
        get;
        private set;
    }

    ///<summary>
    ///lParam
    ///</summary>
    public IntPtr LeftParameter
    {
        get;
        private set;
    }

    ///<summary>
    ///UserData
    ///</summary>
    public IntPtr UserData
    {
        get;
        private set;
    }
}

///<summary>
///Describes the file that is being processed for the ProcessFileEvent.
///</summary>
public class
ProcessFileEventArgs : EventArgs
{
    ///<summary>
    ///Default constructor.
    ///</summary>
    ///<param name="file">Fully qualified path and file name. For example: c:\file.sys.</param>
    ///<param name="skipFileFlag">Default is false - skip file and continue.
    ///Set to true to abort the entire image capture.</param>
    public
    ProcessFileEventArgs(
        string file,
        IntPtr skipFileFlag)
        {

        m_FilePath = file;
        m_SkipFileFlag = skipFileFlag;
    }

    ///<summary>
    ///Skip file from being imaged.
    ///</summary>
    public void
    SkipFile()
    {
        byte[] byteBuffer =
        {
                0
        };
        int byteBufferSize = byteBuffer.Length;
        Marshal.Copy(byteBuffer, 0, m_SkipFileFlag, byteBufferSize);
    }

    ///<summary>
    ///Fully qualified path and file name.
    ///</summary>
    public string
    FilePath
    {
        get
        {
            string stringToReturn = "";
            if (m_FilePath != null)
            {
                stringToReturn = m_FilePath;
            }
            return stringToReturn;
        }
    }

    ///<summary>
    ///Flag to indicate if the entire image capture should be aborted.
    ///Default is false - skip file and continue. Setting to true will
    ///abort the entire image capture.
    ///</summary>
    public bool Abort
    {
        set { m_Abort = value; }
        get { return m_Abort;  }
    }

    private string m_FilePath;
    private bool m_Abort;
    private IntPtr m_SkipFileFlag;

}

#endregion WIM Interop

#region VHD Interop
// Based on code written by the Hyper-V Test team.
/// <summary>
/// The Virtual Hard Disk class provides methods for creating and manipulating Virtual Hard Disk files.
/// </summary>
public class
VirtualHardDisk
{
    #region Static Methods

    #region Sparse Disks

    /// <summary>
    /// Abbreviated signature of CreateSparseDisk so it's easier to use from WIM2VHD.
    /// </summary>
    /// <param name="virtualStorageDeviceType">The type of disk to create, VHD or VHDX.</param>
    /// <param name="path">The path of the disk to create.</param>
    /// <param name="size">The maximum size of the disk to create.</param>
    /// <param name="overwrite">Overwrite the VHD if it already exists.</param>
    public static void
    CreateSparseDisk(
        NativeMethods.VirtualStorageDeviceType virtualStorageDeviceType,
        string path,
        ulong size,
        bool overwrite)
        {

        CreateSparseDisk(
            path,
            size,
            overwrite,
            null,
            IntPtr.Zero,
            (virtualStorageDeviceType == NativeMethods.VirtualStorageDeviceType.VHD)
                ? NativeMethods.DEFAULT_BLOCK_SIZE
                : 0,
            virtualStorageDeviceType,
            NativeMethods.DISK_SECTOR_SIZE);
    }

    /// <summary>
    /// Creates a new sparse (dynamically expanding) virtual hard disk (.vhd). Supports both sync and async modes.
    /// The VHD image file uses only as much space on the backing store as needed to store the actual data the VHD currently contains.
    /// </summary>
    /// <param name="path">The path and name of the VHD to create.</param>
    /// <param name="size">The size of the VHD to create in bytes.
    /// When creating this type of VHD, the VHD API does not test for free space on the physical backing store based on the maximum size requested,
    /// therefore it is possible to successfully create a dynamic VHD with a maximum size larger than the available physical disk free space.
    /// The maximum size of a dynamic VHD is 2,040 GB.  The minimum size is 3 MB.</param>
    /// <param name="source">Optional path to pre-populate the new virtual disk object with block data from an existing disk
    /// This path may refer to a VHD or a physical disk.  Use NULL if you don't want a source.</param>
    /// <param name="overwrite">If the VHD exists, setting this parameter to 'True' will delete it and create a new one.</param>
    /// <param name="overlapped">If not null, the operation runs in async mode</param>
    /// <param name="blockSizeInBytes">Block size for the VHD.</param>
    /// <param name="virtualStorageDeviceType">VHD format version (VHD1 or VHD2)</param>
    /// <param name="sectorSizeInBytes">Sector size for the VHD.</param>
    /// <exception cref="ArgumentOutOfRangeException">Thrown when an invalid size is specified</exception>
    /// <exception cref="FileNotFoundException">Thrown when source VHD is not found.</exception>
    /// <exception cref="SecurityException">Thrown when there was an error while creating the default security descriptor.</exception>
    /// <exception cref="Win32Exception">Thrown when an error occurred while creating the VHD.</exception>
    public static void
    CreateSparseDisk(
        string path,
        ulong size,
        bool overwrite,
        string source,
        IntPtr overlapped,
        uint blockSizeInBytes,
        NativeMethods.VirtualStorageDeviceType virtualStorageDeviceType,
        uint sectorSizeInBytes)
        {

        // Validate the virtualStorageDeviceType
        if (virtualStorageDeviceType != NativeMethods.VirtualStorageDeviceType.VHD && virtualStorageDeviceType != NativeMethods.VirtualStorageDeviceType.VHDX)
        {

            throw (
                new ArgumentOutOfRangeException(
                    "virtualStorageDeviceType",
                    virtualStorageDeviceType,
                    "VirtualStorageDeviceType must be VHD or VHDX."
            ));
        }

        // Validate size.  It needs to be a multiple of DISK_SECTOR_SIZE (512)...
        if ((size % NativeMethods.DISK_SECTOR_SIZE) != 0)
        {

            throw (
                new ArgumentOutOfRangeException(
                    "size",
                    size,
                    "The size of the virtual disk must be a multiple of 512."
            ));
        }

        if ((!String.IsNullOrEmpty(source)) && (!System.IO.File.Exists(source)))
        {

            throw (
                new System.IO.FileNotFoundException(
                    "Unable to find the source file.",
                    source
            ));
        }

        if ((overwrite) && (System.IO.File.Exists(path)))
        {

            System.IO.File.Delete(path);
        }

        NativeMethods.CreateVirtualDiskParameters createParams = new NativeMethods.CreateVirtualDiskParameters();

        // Select the correct version.
        createParams.Version = (virtualStorageDeviceType == NativeMethods.VirtualStorageDeviceType.VHD)
            ? NativeMethods.CreateVirtualDiskVersion.Version1
            : NativeMethods.CreateVirtualDiskVersion.Version2;

        createParams.UniqueId                 = Guid.NewGuid();
        createParams.MaximumSize              = size;
        createParams.BlockSizeInBytes         = blockSizeInBytes;
        createParams.SectorSizeInBytes        = sectorSizeInBytes;
        createParams.ParentPath               = null;
        createParams.SourcePath               = source;
        createParams.OpenFlags                = NativeMethods.OpenVirtualDiskFlags.None;
        createParams.GetInfoOnly              = false;
        createParams.ParentVirtualStorageType = new NativeMethods.VirtualStorageType();
        createParams.SourceVirtualStorageType = new NativeMethods.VirtualStorageType();

        //
        // Create and init a security descriptor.
        // Since we're creating an essentially blank SD to use with CreateVirtualDisk
        // the VHD will take on the security values from the parent directory.
        //

        NativeMethods.SecurityDescriptor securityDescriptor;
        if (!NativeMethods.InitializeSecurityDescriptor(out securityDescriptor, 1))
        {

            throw (
                new SecurityException(
                    "Unable to initialize the security descriptor for the virtual disk."
            ));
        }

        NativeMethods.VirtualStorageType virtualStorageType = new NativeMethods.VirtualStorageType();
        virtualStorageType.DeviceId = virtualStorageDeviceType;
        virtualStorageType.VendorId = NativeMethods.VirtualStorageTypeVendorMicrosoft;

        SafeFileHandle vhdHandle;

        uint returnCode = NativeMethods.CreateVirtualDisk(
            ref virtualStorageType,
                path,
                (virtualStorageDeviceType == NativeMethods.VirtualStorageDeviceType.VHD)
                    ? NativeMethods.VirtualDiskAccessMask.All
                    : NativeMethods.VirtualDiskAccessMask.None,
            ref securityDescriptor,
                NativeMethods.CreateVirtualDiskFlags.None,
                0,
            ref createParams,
                overlapped,
            out vhdHandle);

        vhdHandle.Close();

        if (NativeMethods.ERROR_SUCCESS != returnCode && NativeMethods.ERROR_IO_PENDING != returnCode)
        {

            throw (
                new Win32Exception(
                    (int)returnCode
            ));
        }
    }

    #endregion Sparse Disks

    #endregion Static Methods

}
#endregion VHD Interop
}
"@
    #ifdef for Powershell V7 or greater which looks for assemblies in same path as powershell dll path
    if ($PSVersionTable.psversion.Major -ge 7){        
    Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue 
    }
    else {
    Add-Type -TypeDefinition $code -ReferencedAssemblies "System.Xml","System.Linq","System.Xml.Linq" -ErrorAction SilentlyContinue
    }
}

Function Modify-AutoUnattend {
param (
[string]$username,
[string]$password,
[string]$autologon,
[string]$hostname,
[string]$UnattendPath
    )
    [xml]$xml = get-content -path $UnattendPath
    ($xml.unattend.settings.component | where-object {$_.autologon}).autologon.password.value = $password
    ($xml.unattend.settings.component | where-object {$_.autologon}).autologon.username = $username
    ($xml.unattend.settings.component | where-object {$_.autologon}).autologon.enabled = $autologon
    ($xml.unattend.settings.component | where-object {$_.UserAccounts}).UserAccounts.LocalAccounts.localaccount.Group = "Administrators"
    ($xml.unattend.settings.component | where-object {$_.UserAccounts}).UserAccounts.LocalAccounts.localaccount.Name = $username
    ($xml.unattend.settings.component | where-object {$_.UserAccounts}).UserAccounts.LocalAccounts.localaccount.DisplayName = $username
    ($xml.unattend.settings.component | where-object {$_.UserAccounts}).UserAccounts.LocalAccounts.localaccount.Password.Value = $password
    ($xml.unattend.settings.component | where-object {$_.Computername}).Computername = $hostname
    $xml.Save("$UnattendPath")
}

function Assign-VMGPUPartitionAdapter {
param(
[string]$VMName,
[string]$GPUName,
[decimal]$GPUResourceAllocationPercentage = 100
)
    
    $PartitionableGPUList = Get-WmiObject -Class "Msvm_PartitionableGpu" -ComputerName $env:COMPUTERNAME -Namespace "ROOT\virtualization\v2" 
    if ($GPUName -eq "AUTO") {
        $DevicePathName = $PartitionableGPUList.Name[0]
        Add-VMGpuPartitionAdapter -VMName $VMName
        }
    else {
        $DeviceID = ((Get-WmiObject Win32_PNPSignedDriver | where {($_.Devicename -eq "$GPUNAME")}).hardwareid).split('\')[1]
        $DevicePathName = ($PartitionableGPUList | Where-Object name -like "*$deviceid*").Name
        Add-VMGpuPartitionAdapter -VMName $VMName -InstancePath $DevicePathName
        }

    [float]$devider = [math]::round($(100 / $GPUResourceAllocationPercentage),2)

    Set-VMGpuPartitionAdapter -VMName $VMName -MinPartitionVRAM ([math]::round($(1000000000 / $devider))) -MaxPartitionVRAM ([math]::round($(1000000000 / $devider))) -OptimalPartitionVRAM ([math]::round($(1000000000 / $devider)))
    Set-VMGPUPartitionAdapter -VMName $VMName -MinPartitionEncode ([math]::round($(18446744073709551615 / $devider))) -MaxPartitionEncode ([math]::round($(18446744073709551615 / $devider))) -OptimalPartitionEncode ([math]::round($(18446744073709551615 / $devider)))
    Set-VMGpuPartitionAdapter -VMName $VMName -MinPartitionDecode ([math]::round($(1000000000 / $devider))) -MaxPartitionDecode ([math]::round($(1000000000 / $devider))) -OptimalPartitionDecode ([math]::round($(1000000000 / $devider)))
    Set-VMGpuPartitionAdapter -VMName $VMName -MinPartitionCompute ([math]::round($(1000000000 / $devider))) -MaxPartitionCompute ([math]::round($(1000000000 / $devider))) -OptimalPartitionCompute ([math]::round($(1000000000 / $devider)))

}

Function New-GPUEnabledVM {
param(
[int64]$SizeBytes,
[int]$Edition,
[string]$VhdFormat,
[string]$VhdPath,
[string]$VMName,
[string]$DiskLayout,
[string]$UnattendPath,
[int64]$MemoryAmount,
[int]$CPUCores,
[string]$NetworkSwitch,
[string]$GPUName,
[float]$GPUResourceAllocationPercentage,
[string]$SourcePath,
[string]$Team_ID,
[string]$Key,
[string]$username,
[string]$password,
[string]$autologon
)
    $VHDPath = ConcatenateVHDPath -VHDPath $VHDPath -VMName $VMName
    $DriveLetter = PowerISO-Mount-ISO -SourcePath $params.SourcePath

    if ($(Get-VM -Name $VMName -ErrorAction SilentlyContinue) -ne $NULL) {
        SmartExit -ExitReason "Virtual Machine already exists with name $VMName, please delete existing VM or change VMName"
        }
    if (Test-Path $vhdPath) {
        SmartExit -ExitReason "Virtual Machine Disk already exists at $vhdPath, please delete existing VHDX or change VMName"
        }
    Modify-AutoUnattend -username "$username" -password "$password" -autologon $autologon -hostname $VMName -UnattendPath $UnattendPath
    $MaxAvailableVersion = (Get-VMHostSupportedVersion).Version | Where-Object {$_.Major -lt 254}| Select-Object -Last 1 
    Convert-WindowsImage -SourcePath $SourcePath -ISODriveLetter $DriveLetter -Edition $Edition -VHDFormat $Vhdformat -VHDPath $VhdPath -DiskLayout $DiskLayout -UnattendPath $UnattendPath -GPUName $GPUName -Team_ID $Team_ID -Key $Key -SizeBytes $SizeBytes| Out-Null
    if (Test-Path $vhdPath) {
        New-VM -Name $VMName -MemoryStartupBytes $MemoryAmount -VHDPath $VhdPath -Generation 2 -SwitchName $NetworkSwitch -Version $MaxAvailableVersion | Out-Null
        Set-VM -Name $VMName -ProcessorCount $CPUCores -CheckpointType Disabled -LowMemoryMappedIoSpace 3GB -HighMemoryMappedIoSpace 32GB -GuestControlledCacheTypes $true -AutomaticStopAction ShutDown
        Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false 
        $CPUManufacturer = Get-CimInstance -ClassName Win32_Processor | Foreach-Object Manufacturer
        $BuildVer = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        if (($BuildVer.CurrentBuild -lt 22000) -and ($CPUManufacturer -eq "AuthenticAMD")) {
            }
        Else {
            Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true
            }
        Set-VMKeyProtector -VMName $VMName -NewLocalKeyProtector
        Enable-VMTPM -VMName $VMName 
        Add-VMDvdDrive -VMName $VMName -Path $SourcePath
        Assign-VMGPUPartitionAdapter -GPUName $GPUName -VMName $VMName -GPUResourceAllocationPercentage $GPUResourceAllocationPercentage
        Write-Host "INFO   : Starting and connecting to VM"
        vmconnect localhost $VMName
        }
    else {
    SmartExit -ExitReason "Failed to create VHDX, stopping script"
    }
}

Check-Params @params

New-GPUEnabledVM @params

Start-VM -Name $params.VMName

SmartExit -ExitReason "If all went well the Virtual Machine will have started, 
In a few minutes it will load the Windows desktop, 
when it does, install your favorite high performance remote desktop! " 

