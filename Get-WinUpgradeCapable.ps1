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
    } else { return -1 }
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
        Write-Host "Failed CPU clock speed requirement."
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

    if ( $BreakAnyway -eq $True ) {
        Write-Host "Script in test mode set to break, terminating with Failed result."
        Write-Host $_
        exit 1
    }

    Write-Host "All checks succeeded, Windows Upgrade can commence."
}

WinUpgradeCapableCheck