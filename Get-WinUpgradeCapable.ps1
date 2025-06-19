#Requires -Version 5.1
#Requires -RunAsAdministrator
# Windows 11 compatability script (simplified)

$MinOSDiskSizeGB = 64
$MinMemoryGB = 4
$MinClockSpeedMHz = 1000
$MinLogicalCores = 2
$RequiredAddressWidth = 64

function TpmCheck {

    try {
        $tpm = Get-Tpm
    } catch {
        return -1
    }

    if ( $tpm.TpmPresent -and $tpm.TpmReady ) {
        return 0
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
    $freeSpace = ((Get-CimInstance Win32_LogicaLdisk).FreeSpace)/1GB

    if ( $freeSpace -ge $MinOSDiskSizeGB ) {
        return 0
    } elseif ( $freeSpace -lt $MinOSDiskSizeGB ) {
        return 1
    } else { return -1 }

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
        Write-Output "Clock speed does not meet the requirement for Windows 11 upgrade."
        return 1
    } elseif ( -Not $threadCount ) {
        Write-Output "Not enough CPU cores for Windows 11 upgrade."
        return 1
    } elseif ( -Not $addressWidth ) {
        Write-Output "Not running 64-bit OS, incompatible with Windows 11 upgrade."
        return 1
    } else { return -1 }

}

function WinUpgradeCapableCheck {

    if ( (TpmCheck) -eq -1 ) {
        Write-Host "An error has occurred running the TPM Check."
        exit -1
    } elseif ( (TpmCheck) -gt 0 ) {
        Write-Host "TPM not capable for Windows 11 upgrade."
        exit 1
    } else { Write-Output "TPM check succeeded." }

    if ( (MemoryCheck) -eq -1 ) {
        Write-Host "An error has occurred running the memory check."
        exit -1
    } elseif ( (MemoryCheck) -gt 0 ) {
        Write-Host "Not enough memory for Windows 11 upgrade."
        exit 1
    } else { Write-Output "Memory check succeeded." }

    if ( (OsDiskCheck) -eq -1 ) {
        Write-Host "An error has occurred running the OS disk check."
        exit -1
    } elseif ( (OsDiskCheck) -gt 0 ) {
        Write-Host "Not enough space on OS disk for Windows 11 upgrade."
        exit 1
    } else { Write-Output "OS disk check succeeded." }

    if ( (CpuCheck) -eq -1 ) {
        Write-Host "An error has occurred running the CPU check."
        exit -1
    } elseif ( (CpuCheck) -gt 0 ) {
        Write-Host "CPU not compatible for Windows 11 upgrade."
    } else { Write-Output "CPU check succeeded." }

    if ( $env:firmware_type -eq "UEFI" ) {
        Write-Host "Confirmed firmware is UEFI."
    } elseif ( $env:firmware_type -eq "Legacy" ) {
        Write-Host "Computer is not on UEFI firmware mode."
        exit 1
    } else { Write-Output "Could not confirm UEFI firmware."}
}

WinUpgradeCapableCheck