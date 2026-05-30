# Light Pattern Engine
# Each pattern function receives $t (milliseconds), returns @{ Red = 0.0~1.0; Green = 0.0~1.0 }

function Square-Wave([double]$t, [double]$period, [double]$duty) {
    $phase = ($t % $period) / $period
    if ($phase -lt $duty) { return 1.0 } else { return 0.0 }
}

function Pulse([double]$t, [double]$period, [double]$duration) {
    if (($t % $period) -lt $duration) { return 1.0 } else { return 0.0 }
}

# === Working State ===

# 0: Green solid (working - basic)
function PatternWorking([double]$t) {
    return @{ Red = 0.0; Green = 1.0 }
}

# 1: Green breathing (working - active typing)
function PatternWorkingActive([double]$t) {
    $g = 0.6 + 0.4 * [Math]::Sin(2 * [Math]::PI * $t / 2000.0)
    return @{ Red = 0.0; Green = $g }
}

# === Warning State ===

# 2: Yellow flash (time to rest - gentle)
function PatternWarning([double]$t) {
    $g = Square-Wave $t 1000 0.5
    return @{ Red = 0.0; Green = $g * 0.3 }
}

# 3: Yellow fast flash (time to rest - urgent)
function PatternWarningUrgent([double]$t) {
    $g = Square-Wave $t 500 0.5
    return @{ Red = 0.0; Green = $g * 0.5 }
}

# === Rest State ===

# 4: Red flash (must rest)
function PatternRest([double]$t) {
    $r = Square-Wave $t 800 0.5
    return @{ Red = $r; Green = 0.0 }
}

# 5: Red heartbeat (must rest - heartbeat effect)
function PatternRestHeartbeat([double]$t) {
    $pulse = [Math]::Abs([Math]::Sin([Math]::PI * $t / 800.0))
    $pulse = [Math]::Pow($pulse, 3)
    return @{ Red = $pulse; Green = 0.0 }
}

# === Special States ===

# 6: Rest complete celebration (green fade in)
function PatternRestComplete([double]$t) {
    $progress = [Math]::Min(1.0, $t / 2000.0)
    $g = $progress
    return @{ Red = 0.0; Green = $g }
}

# 7: All off
function PatternOff([double]$t) {
    return @{ Red = 0.0; Green = 0.0 }
}

# === Helper Functions ===

# Map typing speed to animation speed multiplier
function Get-AnimationSpeed([double]$typingSpeed) {
    # typingSpeed: keys/second
    # returns: 0.0 ~ 2.0 animation speed multiplier
    if ($typingSpeed -le 0) { return 0.0 }
    if ($typingSpeed -le 1) { return $typingSpeed * 0.5 }
    if ($typingSpeed -le 3) { return 0.5 + ($typingSpeed - 1) * 0.25 }
    if ($typingSpeed -le 6) { return 1.0 + ($typingSpeed - 3) * 0.2 }
    return 2.0
}

# Get pattern result
function Get-PatternResult([int]$pattern, [double]$t) {
    switch ($pattern) {
        0 { return (PatternWorking $t) }
        1 { return (PatternWorkingActive $t) }
        2 { return (PatternWarning $t) }
        3 { return (PatternWarningUrgent $t) }
        4 { return (PatternRest $t) }
        5 { return (PatternRestHeartbeat $t) }
        6 { return (PatternRestComplete $t) }
        7 { return (PatternOff $t) }
        default { return (PatternWorking $t) }
    }
}
