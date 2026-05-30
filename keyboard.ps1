# Keyboard Monitoring Module
# Uses GetAsyncKeyState to monitor global keyboard input

Add-Type -Namespace Win32 -Name Keyboard -MemberDefinition @'
[DllImport("user32.dll")]
public static extern short GetAsyncKeyState(int vKey);
'@

# Keypress history (timestamp array)
$script:keypressTimestamps = [System.Collections.ArrayList]::new()

# Typing speed (keys/second)
$script:typingSpeed = 0.0

# Last keypress time
$script:lastKeyTime = [DateTime]::MinValue

# Previous key states (for edge detection)
$script:lastKeyStates = @{}

# Keys to monitor (exclude modifiers to avoid repeat counting)
$script:MONITORED_KEYS = @(
    0x41..0x5A  # A-Z
    0x30..0x39  # 0-9
    0x20        # Space
    0x0D        # Enter
    0x08        # Backspace
    0x09        # Tab
    0xBD        # OemMinus
    0xBB        # OemPlus
    0xDB        # OemOpenBrackets
    0xDD        # OemCloseBrackets
    0xDC        # OemPipe
    0xBA        # OemSemicolon
    0xDE        # OemQuotes
    0xBC        # OemComma
    0xBE        # OemPeriod
    0xBF        # OemQuestion
    0xC0        # OemTilde
)

function Poll-Keyboard {
    $now = [DateTime]::UtcNow
    $keyPressed = $false

    foreach ($vk in $script:MONITORED_KEYS) {
        $state = [Win32.Keyboard]::GetAsyncKeyState($vk)
        $isPressed = ($state -band 0x8000) -ne 0
        $wasPressed = $script:lastKeyStates[$vk]

        # Edge detection: only record on keydown (not hold)
        if ($isPressed -and -not $wasPressed) {
            $keyPressed = $true
            $script:lastKeyTime = $now
            [void]$script:keypressTimestamps.Add($now)
        }

        $script:lastKeyStates[$vk] = $isPressed
    }

    return $keyPressed
}

function Update-TypingSpeed([int]$windowSeconds) {
    $now = [DateTime]::UtcNow
    $cutoff = $now.AddSeconds(-$windowSeconds)

    # Clean expired records
    while ($script:keypressTimestamps.Count -gt 0 -and $script:keypressTimestamps[0] -lt $cutoff) {
        $script:keypressTimestamps.RemoveAt(0)
    }

    # Calculate speed (keys/second)
    if ($windowSeconds -gt 0) {
        $script:typingSpeed = [double]$script:keypressTimestamps.Count / $windowSeconds
    } else {
        $script:typingSpeed = 0.0
    }

    return $script:typingSpeed
}

function Get-TypingSpeed {
    return $script:typingSpeed
}

function Get-LastKeyTime {
    return $script:lastKeyTime
}

function Get-IdleSeconds {
    if ($script:lastKeyTime -eq [DateTime]::MinValue) {
        return 999999.0
    }
    return ([DateTime]::UtcNow - $script:lastKeyTime).TotalSeconds
}

# Detect Ctrl+Alt+R shortcut (rest confirmation)
$script:ctrlAltRPressed = $false
$script:ctrlAltRLastCheck = $false

function Poll-RestShortcut {
    $ctrl = ([Win32.Keyboard]::GetAsyncKeyState(0x11) -band 0x8000) -ne 0
    $alt = ([Win32.Keyboard]::GetAsyncKeyState(0x12) -band 0x8000) -ne 0
    $r = ([Win32.Keyboard]::GetAsyncKeyState(0x52) -band 0x8000) -ne 0

    $current = $ctrl -and $alt -and $r
    $triggered = $current -and -not $script:ctrlAltRLastCheck
    $script:ctrlAltRLastCheck = $current

    return $triggered
}
