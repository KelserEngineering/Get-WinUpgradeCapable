param (
    [switch]$BreakAnyway
)

#Requires -Version 5.1
#Requires -RunAsAdministrator

# Windows 11 compatability script (simplified)

$BreakAnyway = $False
$MinOSDiskSizeGB = 64
$MinMemoryGB = 4
$MinClockSpeedMHz = 1000
$MinLogicalCores = 2
$RequiredAddressWidth = 64

function TpmCheck {
    $tpm = Get-Tpm

    if ( $tpm.TpmPresent -and $tpm.TpmReady ) {
        return 0
    } elseif ( $null -ne $tpm ) {
        return 2
    } else { return 1 }

}

function MemoryCheck {
    $totalMemory = ((Get-Ciminstance Win32_OperatingSystem).TotalVirtualMemorySize)/1MB

    if ( $totalMemory -ge $MinMemoryGB ) {
        return 0
    } elseif ( $totalMemory -lt $MinMemoryGB ) {
        return 1
    } else { return -1 }

}

function OsDiskCheck {
    $freeSpace = ((Get-CimInstance Win32_LogicaLdisk | Where-Object -Property DeviceID -EQ 'C:').FreeSpace)/1GB

    if ( $freeSpace -ge $MinOSDiskSizeGB ) {
        return 0
    } elseif ( $freeSpace -lt $MinOSDiskSizeGB ) {
        return 1
    } else { return -1 }

}

$Source = @"
using Microsoft.Win32;
using System;
using System.Runtime.InteropServices;

    public class CpuFamilyResult
    {
        public bool IsValid { get; set; }
        public string Message { get; set; }
    }

    public class CpuFamily
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct SYSTEM_INFO
        {
            public ushort ProcessorArchitecture;
            ushort Reserved;
            public uint PageSize;
            public IntPtr MinimumApplicationAddress;
            public IntPtr MaximumApplicationAddress;
            public IntPtr ActiveProcessorMask;
            public uint NumberOfProcessors;
            public uint ProcessorType;
            public uint AllocationGranularity;
            public ushort ProcessorLevel;
            public ushort ProcessorRevision;
        }

        [DllImport("kernel32.dll")]
        internal static extern void GetNativeSystemInfo(ref SYSTEM_INFO lpSystemInfo);

        public enum ProcessorFeature : uint
        {
            ARM_SUPPORTED_INSTRUCTIONS = 34
        }

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool IsProcessorFeaturePresent(ProcessorFeature processorFeature);

        private const ushort PROCESSOR_ARCHITECTURE_X86 = 0;
        private const ushort PROCESSOR_ARCHITECTURE_ARM64 = 12;
        private const ushort PROCESSOR_ARCHITECTURE_X64 = 9;

        private const string INTEL_MANUFACTURER = "GenuineIntel";
        private const string AMD_MANUFACTURER = "AuthenticAMD";
        private const string QUALCOMM_MANUFACTURER = "Qualcomm Technologies Inc";

        public static CpuFamilyResult Validate(string manufacturer, ushort processorArchitecture)
        {
            CpuFamilyResult cpuFamilyResult = new CpuFamilyResult();

            if (string.IsNullOrWhiteSpace(manufacturer))
            {
                cpuFamilyResult.IsValid = false;
                cpuFamilyResult.Message = "Manufacturer is null or empty";
                return cpuFamilyResult;
            }

            string registryPath = "HKEY_LOCAL_MACHINE\\Hardware\\Description\\System\\CentralProcessor\\0";
            SYSTEM_INFO sysInfo = new SYSTEM_INFO();
            GetNativeSystemInfo(ref sysInfo);

            switch (processorArchitecture)
            {
                case PROCESSOR_ARCHITECTURE_ARM64:

                    if (manufacturer.Equals(QUALCOMM_MANUFACTURER, StringComparison.OrdinalIgnoreCase))
                    {
                        bool isArmv81Supported = IsProcessorFeaturePresent(ProcessorFeature.ARM_SUPPORTED_INSTRUCTIONS);

                        if (!isArmv81Supported)
                        {
                            string registryName = "CP 4030";
                            long registryValue = (long)Registry.GetValue(registryPath, registryName, -1);
                            long atomicResult = (registryValue >> 20) & 0xF;

                            if (atomicResult >= 2)
                            {
                                isArmv81Supported = true;
                            }
                        }

                        cpuFamilyResult.IsValid = isArmv81Supported;
                        cpuFamilyResult.Message = isArmv81Supported ? "" : "Processor does not implement ARM v8.1 atomic instruction";
                    }
                    else
                    {
                        cpuFamilyResult.IsValid = false;
                        cpuFamilyResult.Message = "The processor isn't currently supported for Windows 11";
                    }

                    break;

                case PROCESSOR_ARCHITECTURE_X64:
                case PROCESSOR_ARCHITECTURE_X86:

                    int cpuFamily = sysInfo.ProcessorLevel;
                    int cpuModel = (sysInfo.ProcessorRevision >> 8) & 0xFF;
                    int cpuStepping = sysInfo.ProcessorRevision & 0xFF;

                    if (manufacturer.Equals(INTEL_MANUFACTURER, StringComparison.OrdinalIgnoreCase))
                    {
                        try
                        {
                            cpuFamilyResult.IsValid = true;
                            cpuFamilyResult.Message = "";

                            if (cpuFamily >= 6 && cpuModel <= 95 && !(cpuFamily == 6 && cpuModel == 85))
                            {
                                cpuFamilyResult.IsValid = false;
                                cpuFamilyResult.Message = "";
                            }
                            else if (cpuFamily == 6 && (cpuModel == 142 || cpuModel == 158) && cpuStepping == 9)
                            {
                                string registryName = "Platform Specific Field 1";
                                int registryValue = (int)Registry.GetValue(registryPath, registryName, -1);

                                if ((cpuModel == 142 && registryValue != 16) || (cpuModel == 158 && registryValue != 8))
                                {
                                    cpuFamilyResult.IsValid = false;
                                }
                                cpuFamilyResult.Message = "PlatformId " + registryValue;
                            }
                        }
                        catch (Exception ex)
                        {
                            cpuFamilyResult.IsValid = false;
                            cpuFamilyResult.Message = "Exception:" + ex.GetType().Name;
                        }
                    }
                    else if (manufacturer.Equals(AMD_MANUFACTURER, StringComparison.OrdinalIgnoreCase))
                    {
                        cpuFamilyResult.IsValid = true;
                        cpuFamilyResult.Message = "";

                        if (cpuFamily < 23 || (cpuFamily == 23 && (cpuModel == 1 || cpuModel == 17)))
                        {
                            cpuFamilyResult.IsValid = false;
                        }
                    }
                    else
                    {
                        cpuFamilyResult.IsValid = false;
                        cpuFamilyResult.Message = "Unsupported Manufacturer: " + manufacturer + ", Architecture: " + processorArchitecture + ", CPUFamily: " + sysInfo.ProcessorLevel + ", ProcessorRevision: " + sysInfo.ProcessorRevision;
                    }

                    break;

                default:
                    cpuFamilyResult.IsValid = false;
                    cpuFamilyResult.Message = "Unsupported CPU category. Manufacturer: " + manufacturer + ", Architecture: " + processorArchitecture + ", CPUFamily: " + sysInfo.ProcessorLevel + ", ProcessorRevision: " + sysInfo.ProcessorRevision;
                    break;
            }
            return cpuFamilyResult;
        }
    }
"@

function ProcessorFamilyCheck {
    Add-Type -TypeDefinition $Source

    $cpuResult = ""
    $cpuFamilyResult = [CpuFamily]::Validate([String]$cpuDetails.Manufacturer, [uint16]$cpuDetails.Architecture)
    $cpuDetailsLog = "{`nAddressWidth=$($cpuDetails.AddressWidth); MaxClockSpeed=$($cpuDetails.MaxClockSpeed); NumberOfLogicalCores=$($cpuDetails.NumberOfLogicalProcessors); Manufacturer=$($cpuDetails.Manufacturer); Caption=$($cpuDetails.Caption); $($cpuFamilyResult.Message)}"

    try {
        $cpuDetails = @(Get-CimInstance -ClassName Win32_Processor)[0]
        Write-Output ($cpuDetails)

        if ($null -eq $cpuDetails) {
            $cpuResult = "Cpu details returns null"
            return -1
        } else {
            $cpuDetailsLog = "{`nAddressWidth=$($cpuDetails.AddressWidth); MaxClockSpeed=$($cpuDetails.MaxClockSpeed); NumberOfLogicalCores=$($cpuDetails.NumberOfLogicalProcessors); Manufacturer=$($cpuDetails.Manufacturer); Caption=$($cpuDetails.Caption); $($cpuFamilyResult.Message)}"

            if ( -Not $cpuFamilyResult.IsValid ) {
                $cpuResult = "CPU details: $cpuDetailsLog"
                return 1
            } else {
                return 0
            }
        }
    }
    catch {
        Write-Host "CPU details: $cpuDetailsLog"
        return 1
    }

    # i7-7820hq CPU
    $supportedDevices = @('surface studio 2', 'precision 5520')
    $systemInfo = @(Get-CimInstance -ClassName Win32_ComputerSystem)[0]

    if ($null -ne $cpuDetails) {
        if ($cpuDetails.Name -match 'i7-7820hq cpu @ 2.90ghz') {
            $modelOrSKUCheckLog = $systemInfo.Model.Trim()
            if ($supportedDevices -contains $modelOrSKUCheckLog) {
                $cpuResult = $systemInfo.Model.Trim()
                return 0
            } else {
                $cpuResult = $systemInfo.Model.Trim() + " not supported."
                return 0
            }
        }
    }

    if ( -Not $cpuFamilyResult.IsValid ) {
        $cpuResult = "CPU details: $cpuDetailsLog"
        return 1
    } else {
        $cpuResult = "CPU details: $cpuDetailsLog"
        return 0
    }

    Write-Host $cpuResult
}

function CpuCheck {

    $cpu = (Get-CimInstance Win32_Processor)
    $clockSpeed = ($cpu.MaxClockSpeed -gt $MinClockSpeedMHz)
    $threadCount = ($cpu.ThreadCount -or $cpu.NumberOfCores -ge $MinLogicalCores)
    $addressWidth = ($cpu.AddressWidth -eq $RequiredAddressWidth)
    $compatible = $clockSpeed -and $threadCount -and $addressWidth

    if ( $compatible ) {
        return 0
    } elseif ( -Not $clockSpeed ) {
        Write-Host "Failed CPU clock speed requirement."
        return 1
    } elseif ( -Not $threadCount ) {
        Write-Host "Failed CPU thread count requirement."
        return 2
    } elseif ( -Not $addressWidth ) {
        Write-Host "Failed CPU Architecture requirement."
        Write-Host "Is installed Windows 64-bit?"
        return 3
    } elseif ( -Not (ProcessorFamilyCheck) ) {
        Write-Host "Could not satisfy processor family requirement."
        return 4
    } else { 
        return -1
    }
}

function WinUpgradeCapableCheck {
    $tpmStatus = TpmCheck
    $memoryStatus = MemoryCheck
    $osDiskStatus = OsDiskCheck
    $cpuStatus = CpuCheck
    $secureBootStatus = Confirm-SecureBootUEFI

    # TPM Check
    if ( $tpmStatus -eq -1 ) {
        Write-Host "Failed TPM requirement."
        Write-Host "An error has occurred running the TPM Check."
        exit -1
    } elseif ( $tpmStatus -gt 0 ) {
        Write-Host "Failed TPM requirement."
        Write-Host "Disabled in BIOS, or not present?"
        exit 1
    } else { Write-Host "TPM requirement satisfied." }

    # Memory Check
    if ( $memoryStatus -eq -1 ) {
        Write-Host "Failed memory requirement."
        Write-Host "An error has occurred running the memory check."
        exit -1
    } elseif ( $memoryStatus -gt 0 ) {
        Write-Host "Failed memory requirement."
        Write-Host "Not enough memory for Windows 11 upgrade."
        exit 1
    } else { Write-Host "Memory requirement satisfied." }

    # CPU Check
    if ( $cpuStatus -eq -1 ) {
        Write-Host "Failed CPU requirement."
        Write-Host "An error has occurred running the CPU check."
        exit -1
    } elseif ( $cpuStatus -gt 0) {
        Write-Host "Failed CPU requirement."
    } else { Write-Host "CPU requirement satisfied." }

    # Firmware check
    if ( $env:firmware_type -eq "Legacy" ) {
        Write-Host "Failed firmware requirement."
        Write-Host "Computer is not on UEFI firmware."
        exit 1
    } elseif ( $env:firmware_type -eq "UEFI" ) {
        Write-Host "Confirmed firmware is UEFI."
        Write-Host "Firmware requirement satisfied."
    } else {
        Write-Host "Failed firmware requirement."
        Write-Host "Could not confirm UEFI firmware."
        exit 1
    }

    # Windows cannot check this if TPM is disabled in BIOS
    if ( $secureBootStatus -eq $False ) {
        Write-Host "Failed secure boot requirement."
        Write-Host "Secure boot is not enabled."
        exit 1
    } elseif ( $secureBootStatus -eq $True ) {
        Write-Host "Secure boot requirement satisfied."
    } else {
        Write-Host "Failed secure boot requirement."
        Write-Host "Secure boot could not be checked, verify UEFI."
        exit -1
    }

    # Check disk last in the case it just needs cleanup
    if ( $osDiskStatus -eq -1 ) {
        Write-Host "Failed OS disk requirement."
        Write-Host "An error has occurred running the OS disk check."
        exit -1
    } elseif ( $osDiskStatus -gt 0 ) {
        Write-Host "Failed OS disk requirement."
        Write-Host "Not enough space on OS disk for Windows 11 upgrade."
        exit 1
    } else {
        Write-Host "OS disk requirement satisfied."
    }

    # Forced failure mode 
    if ( $BreakAnyway -eq $True ) {
        Write-Host "Script in test mode set to break, terminating with Failed result."
        Write-Host $_
        exit 1
    }

    Write-Host "All checks succeeded, Windows Upgrade can commence."
}

WinUpgradeCapableCheck