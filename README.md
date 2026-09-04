# ANNOUNCEMENT:  
Easy GPU PV will be replaced with [App Sandbox](https://github.com/jamesstringer90/appsandbox)  

Compared to Easy-GPU-PV, App Sandbox is 100x easier to use: It's a full Windows app with a friendly user interface, it also removes the need for Hyper-V, so people on Win11 Home can use it.  

App Sandbox includes everything you need to create a VM, just bring your Windows 11 or Ubuntu 26.04LTS ISO and it will setup everything for you including GPU support on both Windows and Ubuntu.  You can install apps like Sunshine if you want to, but it's not a requirement.

It's also fully open source with an MIT license  

[Download it here](https://github.com/jamesstringer90/appsandbox/releases/download/v0.1.0/AppSandbox-0.1.0-x64.zip)

<img width="1028" height="446" alt="image" src="https://github.com/user-attachments/assets/2b341bb3-e2de-456b-b8e8-a0b037099b62" />

# Easy-GPU-PV
A work-in-progress project dedicated to making GPU Paravirtualization on Windows Hyper-V easier!  

GPU-PV allows you to partition your systems dedicated or integrated GPU and assign it to several Hyper-V VMs.  It's the same technology that is used in WSL2, and Windows Sandbox.  

Easy-GPU-PV aims to make this easier by automating the steps required to get a GPU-PV VM up and running.  
Easy-GPU-PV does the following...  
1) Creates a VM of your choosing
2) Automatically Installs Windows to the VM
3) Partitions your GPU of choice and copies the required driver files to the VM  

After that, you should install a GPU accelerated remote desktop app / game streaming app as well as a virtual display driver to get the most out of the VM. Check the Issues tab on this repo to get recommendations.


### Prerequisites:
* Windows 10 20H1+ Pro, Enterprise or Education OR Windows 11 Pro, Enterprise or Education.  Windows 11 on host and VM is preferred due to better compatibility.  
* Matched Windows versions between the host and VM. Mismatches may cause compatibility issues, blue-screens, or other issues. (Win10 21H1 + Win10 21H1, or Win11 21H2 + Win11 21H2, for example)  
* Desktop Computer with dedicated NVIDIA/AMD GPU or Integrated Intel GPU - Laptops with NVIDIA GPUs are not supported at this time, but Intel integrated GPUs work on laptops.  GPU must support hardware video encoding (NVIDIA NVENC, Intel Quicksync or AMD AMF).  
* Latest GPU driver from Intel.com or NVIDIA.com, don't rely on Device manager or Windows update.  
* Latest Windows 10 ISO [downloaded from here](https://www.microsoft.com/en-gb/software-download/windows10ISO) / Windows 11 ISO [downloaded from here.](https://www.microsoft.com/en-us/software-download/windows11) - Do not use Media Creation Tool, if no direct ISO link is available, follow [this guide.](https://www.nextofwindows.com/downloading-windows-10-iso-images-using-rufus)
* Virtualisation enabled in the motherboard and [Hyper-V fully enabled](https://docs.microsoft.com/en-us/virtualization/hyper-v-on-windows/quick-start/enable-hyper-v) on the Windows 10/ 11 OS (requires reboot).  
* Allow Powershell scripts to run on your system - typically by running "Set-ExecutionPolicy unrestricted" in Powershell running as Administrator.  

### Instructions
1. Make sure your system meets the prerequisites.
2. [Download the Repo and extract.](https://github.com/jamesstringerparsec/Easy-GPU-PV/archive/refs/heads/main.zip)
3. Search your system for Powershell ISE and run as Administrator.
4. In the extracted folder you downloaded, open PreChecks.ps1 in Powershell ISE.  Run the files from within the extracted folder. Do not move them.
5. Open and Run PreChecks.ps1 in Powershell ISE using the green play button and copy the GPU Listed (or the warnings that you need to fix).
6. Open CopyFilesToVM.ps1 Powershell ISE and edit the params section at the top of the file, you need to be careful about how much ram, storage and hard drive you give it as your system needs to have that available.  On Windows 10 the GPUName must be left as "AUTO", In Windows 11 it can be either "AUTO" or the specific name of the GPU you want to partition exactly how it appears in PreChecks.ps1.  Additionally, you need to provide the path to the Windows 10/11 ISO file you downloaded.
7. Run CopyFilesToVM.ps1 with your changes to the params section - this may take 5-10 minutes.
8. Download a GPU based remote desktop / game streaming tool as well as a virtual display adapter driver (not included) to take full advantage of the GPU accelerated desktop.  The issues tab of this repo has lots of good ideas and advice about how to get the best out of your new VM.
9. You should be good to go!

### Upgrading GPU Drivers when you update the host GPU Drivers
It's important to update the VM GPU Drivers after you have updated the Host GPUs drivers. You can do this by...  
1. Reboot the host after updating GPU Drivers.  
2. Open Powershell as administrator and change directory (CD) to the path that CopyFilesToVM.ps1 and Update-VMGpuPartitionDriver.ps1 are located. 
3. Run ```Update-VMGpuPartitionDriver.ps1 -VMName "Name of your VM" -GPUName "Name of your GPU"```    (Windows 10 GPU name must be "AUTO")

### Values
  ```VMName = "GPUP"``` - Name of VM in Hyper-V and the computername / hostname  
  ```SourcePath = "C:\Users\james\Downloads\Win11_English_x64.iso"``` - path to Windows 10/ 11 ISO on your host   
  ```Edition    = 6``` - Leave as 6, this means Windows 10/11 Pro  
  ```VhdFormat  = "VHDX"``` - Leave this value alone  
  ```DiskLayout = "UEFI"``` - Leave this value alone  
  ```SizeBytes  = 40gb``` - Disk size, in this case 40GB, the minimum is 20GB  
  ```MemoryAmount = 8GB``` - Memory size, in this case 8GB  
  ```CPUCores = 4``` - CPU Cores you want to give VM, in this case 4   
  ```NetworkSwitch = "Default Switch"``` - Leave this alone unless you're not using the default Hyper-V Switch  
  ```VHDPath = "C:\Users\Public\Documents\Hyper-V\Virtual Hard Disks\"``` - Path to the folder you want the VM Disk to be stored in, it must already exist  
  ```UnattendPath = "$PSScriptRoot"+"\autounattend.xml"``` -Leave this value alone  
  ```GPUName = "AUTO"``` - AUTO selects the first available GPU. On Windows 11 you may also use the exact name of the GPU you want to share with the VM in multi GPU situations (GPU selection is not available in Windows 10 and must be set to AUTO)    
  ```GPUResourceAllocationPercentage = 50``` - Percentage of the GPU you want to share with the VM   
  ```Username = "GPUVM"``` - The VM Windows Username, do not include special characters, and must be different from the "VMName" value you set  
  ```Password = "CoolestPassword!"``` - The VM Windows Password, cannot be blank    
  ```Autologon = "true"```- If you want the VM to automatically login to the Windows Desktop


### Thanks to:  
- [Hyper-ConvertImage](https://github.com/tabs-not-spaces/Hyper-ConvertImage) for creating an updated version of [Convert-WindowsImage](https://github.com/MicrosoftDocs/Virtualization-Documentation/tree/master/hyperv-tools/Convert-WindowsImage) that is compatible with Windows 10 and 11.
- [gawainXX](https://github.com/gawainXX) for help testing and pointing out bugs and feature improvements.  


### Notes:    
- Always use a GPU accelerated remote desktop / game streaming app to connect to the VM.  Keep the Microsft Hyper-V Video adapter disabled. Using RDP and Hyper-V Enhanced Session mode will result in broken behaviour and black screens in your GPU accelerated remote desktop.  RDP and the Hyper-V video adapter only offer a maximum of 30FPS. Using GPU accelerated remote desktops + a virtual display driver will allow you to use up to 4k60 FPS.
- If you get "ERROR  : Cannot bind argument to parameter 'Path' because it is null." this probably means you used Media Creation Tool to download the ISO.  You unfortunately cannot use that, if you don't see a direct ISO download link at the Microsoft page, follow [this guide.](https://www.nextofwindows.com/downloading-windows-10-iso-images-using-rufus)  
- Your GPU on the host will have a Microsoft driver in device manager, rather than an nvidia/intel/amd driver. As long as it doesn't have a yellow triangle over top of the device in device manager, it's working correctly.  
- A powered on display / HDMI dummy dongle must be plugged into the GPU to allow your GPU accelerated remote desktop / game streaming app to capture the screen.  You only need one of these per host machine regardless of number of VM's.
- Vulkan renderer is unavailable and GL games may or may not work.  [This](https://www.microsoft.com/en-us/p/opencl-and-opengl-compatibility-pack/9nqpsl29bfff?SilentAuth=1&wa=wsignin1.0#activetab=pivot:overviewtab) may help with some OpenGL apps.  
- If you do not have administrator permissions on the machine it means you set the username and vmname to the same thing, these needs to be different.  
- AMD Polaris GPUS like the RX 580 do not support hardware video encoding via GPU Paravirtualization at this time.  
- To download Windows ISOs with Rufus, it must have "Check for updates" enabled.
