# Clipboard.psm1 — Clipboard helpers that avoid plain-text password exposure

function Copy-StringToClipboard {
    param([string]$Value)
    Set-Clipboard -Value $Value
}

function Copy-SecureStringToClipboard {
    param([SecureString]$SecureValue)
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr) | Set-Clipboard
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Clear-Clipboard {
    Set-Clipboard -Value ''
}

Export-ModuleMember -Function Copy-StringToClipboard, Copy-SecureStringToClipboard, Clear-Clipboard
