# Main Program - Keyboard Traffic Light (Sit Reminder)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Load Win32 Sound API
Add-Type -Namespace Win32 -Name Sound -MemberDefinition @'
[DllImport("winmm.dll", CharSet = CharSet.Auto)]
public static extern bool PlaySound(string sound, System.IntPtr hmod, int flags);
'@
$SND_ASYNC = 1; $SND_FILENAME = 0x20000

# === Path Configuration ===
$configFile = Join-Path $PSScriptRoot "config.json"
$patternsFile = Join-Path $PSScriptRoot "patterns.ps1"
$keyboardFile = Join-Path $PSScriptRoot "keyboard.ps1"

# Load modules
. $patternsFile
. $keyboardFile

# === Default Configuration ===
$script:workDuration = 50
$script:warningDuration = 10
$script:restThreshold = 180
$script:typingSpeedWindow = 5
$soundEnabled = $true
$soundFiles = @{
    working = "C:\Windows\Media\Windows Balloon.wav"
    warning = "C:\Windows\Media\Windows Message Nudge.wav"
    rest = "C:\Windows\Media\Windows Hardware Fail.wav"
}
$windowX = 100; $windowY = 100

# === Load Configuration ===
function Load-Config {
    try {
        if (Test-Path $script:configFile) {
            $cfg = Get-Content $script:configFile -Raw | ConvertFrom-Json
            if ($cfg.workDuration) { $script:workDuration = [int]$cfg.workDuration }
            if ($cfg.warningDuration) { $script:warningDuration = [int]$cfg.warningDuration }
            if ($cfg.restThreshold) { $script:restThreshold = [int]$cfg.restThreshold }
            if ($cfg.typingSpeedWindow) { $script:typingSpeedWindow = [int]$cfg.typingSpeedWindow }
            if ($cfg.sound) {
                if ($null -ne $cfg.sound.enabled) { $script:soundEnabled = $cfg.sound.enabled }
                if ($cfg.sound.files) {
                    if ($cfg.sound.files.working) { $script:soundFiles.working = $cfg.sound.files.working }
                    if ($cfg.sound.files.warning) { $script:soundFiles.warning = $cfg.sound.files.warning }
                    if ($cfg.sound.files.rest) { $script:soundFiles.rest = $cfg.sound.files.rest }
                }
            }
            if ($cfg.window) {
                if ($null -ne $cfg.window.x) { $script:windowX = [int]$cfg.window.x }
                if ($null -ne $cfg.window.y) { $script:windowY = [int]$cfg.window.y }
            }
        }
    } catch {}
}
Load-Config

# === State Machine ===
$script:state = "working"
$script:stateStartTime = [DateTime]::UtcNow
$script:currentPattern = 0
$script:patternTime = 0.0
$script:lastSoundState = ""
$script:restConfirmed = $false
$script:stateChanged = $false
$script:stateChangeTime = [DateTime]::UtcNow

function Get-ElapsedSeconds {
    return ([DateTime]::UtcNow - $script:stateStartTime).TotalSeconds
}

function Get-StateChangeElapsed {
    return ([DateTime]::UtcNow - $script:stateChangeTime).TotalSeconds
}

function Set-State([string]$newState) {
    if ($newState -eq $script:state) { return }

    $script:state = $newState
    $script:stateStartTime = [DateTime]::UtcNow
    $script:stateChangeTime = [DateTime]::UtcNow
    $script:stateChanged = $true
    $script:patternTime = 0

    Play-StateSound $newState
}

function Play-StateSound([string]$state) {
    try {
        if (-not $script:soundEnabled) { return }
        if ($state -eq $script:lastSoundState) { return }
        $script:lastSoundState = $state

        $soundFile = $script:soundFiles[$state]
        if ($soundFile -and (Test-Path $soundFile)) {
            $flags = $SND_ASYNC -bor $SND_FILENAME
            [Win32.Sound]::PlaySound($soundFile, [IntPtr]::Zero, $flags)
        }
    } catch {}
}

function Update-StateMachine {
    $elapsed = Get-ElapsedSeconds
    $idleSeconds = Get-IdleSeconds
    $typingSpeed = Get-TypingSpeed

    switch ($script:state) {
        "working" {
            $workSeconds = $script:workDuration * 60
            if ($elapsed -ge $workSeconds) {
                Set-State "warning"
            }
            $script:currentPattern = 0
        }

        "warning" {
            $warningSeconds = $script:warningDuration * 60
            if ($elapsed -ge $warningSeconds) {
                Set-State "rest"
            }
            if ($elapsed -gt ($script:warningDuration * 60 * 0.7)) {
                $script:currentPattern = 3
            } else {
                $script:currentPattern = 2
            }
        }

        "rest" {
            if ($script:restConfirmed -or $idleSeconds -ge $script:restThreshold) {
                Set-State "working"
                $script:restConfirmed = $false
            }
            $script:currentPattern = 4
        }
    }
}

# === WPF UI ===

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="64" Height="170" WindowStyle="None" Topmost="True"
        ShowInTaskbar="False" AllowsTransparency="True" Background="Transparent"
        Left="$windowX" Top="$windowY" ResizeMode="NoResize">
    <Grid Background="#2d2d2d" x:Name="MainGrid" Margin="0">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Red Light with Sitting Figure (stands up when active) -->
        <Grid Grid.Row="0" Width="40" Height="40" Margin="0,8,0,0" HorizontalAlignment="Center">
            <Ellipse x:Name="RedLed" Width="40" Height="40">
                <Ellipse.Fill>
                    <RadialGradientBrush>
                        <GradientStop Color="#ff6b6b" Offset="0.3"/>
                        <GradientStop Color="#e74c3c" Offset="1"/>
                    </RadialGradientBrush>
                </Ellipse.Fill>
            </Ellipse>
            <Canvas x:Name="RedCanvas" Width="40" Height="40">
                <Ellipse x:Name="RedHead" Width="6" Height="6" Canvas.Left="17" Canvas.Top="8" Fill="#2d2d2d"/>
                <Line x:Name="RedBody" X1="20" Y1="14" X2="20" Y2="24" Stroke="#2d2d2d" StrokeThickness="2"/>
                <Line x:Name="RedLeftArm" X1="20" Y1="17" X2="12" Y2="14" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <Line x:Name="RedRightArm" X1="20" Y1="17" X2="28" Y2="14" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <Line x:Name="RedLeftLeg" X1="20" Y1="24" X2="20" Y2="30" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <Line x:Name="RedRightLeg" X1="20" Y1="24" X2="20" Y2="30" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <Line x:Name="RedSeat" X1="10" Y1="30" X2="30" Y2="30" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <Rectangle x:Name="RedMonitor" Width="10" Height="7" Canvas.Left="15" Canvas.Top="22" Stroke="#2d2d2d" StrokeThickness="1" Fill="#2d2d2d" Opacity="1.0"/>
                <Line x:Name="RedStand" X1="20" Y1="29" X2="20" Y2="30" Stroke="#2d2d2d" StrokeThickness="1"/>
                <Rectangle x:Name="RedKeyboard" Width="8" Height="2" Canvas.Left="16" Canvas.Top="30" Fill="#2d2d2d" RadiusX="1" RadiusY="1" Opacity="1.0"/>
            </Canvas>
        </Grid>

        <!-- Yellow Light with Sitting Figure (stretches when active) -->
        <Grid Grid.Row="1" Width="40" Height="40" Margin="0,4,0,0" HorizontalAlignment="Center">
            <Ellipse x:Name="YellowLed" Width="40" Height="40">
                <Ellipse.Fill>
                    <RadialGradientBrush>
                        <GradientStop Color="#ffe066" Offset="0.3"/>
                        <GradientStop Color="#f1c40f" Offset="1"/>
                    </RadialGradientBrush>
                </Ellipse.Fill>
            </Ellipse>
            <Canvas x:Name="YellowCanvas" Width="40" Height="40">
                <Ellipse x:Name="YellowHead" Width="6" Height="6" Canvas.Left="17" Canvas.Top="8" Fill="#2d2d2d"/>
                <Line x:Name="YellowBody" X1="20" Y1="14" X2="20" Y2="24" Stroke="#2d2d2d" StrokeThickness="2"/>
                <Line x:Name="YellowLeftArm" X1="20" Y1="17" X2="12" Y2="14" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <Line x:Name="YellowRightArm" X1="20" Y1="17" X2="28" Y2="14" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <Line x:Name="YellowLeftLeg" X1="20" Y1="24" X2="20" Y2="30" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <Line x:Name="YellowRightLeg" X1="20" Y1="24" X2="20" Y2="30" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <Line x:Name="YellowSeat" X1="10" Y1="30" X2="30" Y2="30" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <Rectangle Width="10" Height="7" Canvas.Left="15" Canvas.Top="22" Stroke="#2d2d2d" StrokeThickness="1" Fill="#2d2d2d"/>
                <Line X1="20" Y1="29" X2="20" Y2="30" Stroke="#2d2d2d" StrokeThickness="1"/>
                <Rectangle Width="8" Height="2" Canvas.Left="16" Canvas.Top="30" Fill="#2d2d2d" RadiusX="1" RadiusY="1"/>
            </Canvas>
        </Grid>

        <!-- Green Light with Typing Figure and Computer -->
        <Grid Grid.Row="2" Width="40" Height="40" Margin="0,4,0,0" HorizontalAlignment="Center">
            <Ellipse x:Name="GreenLed" Width="40" Height="40">
                <Ellipse.Fill>
                    <RadialGradientBrush>
                        <GradientStop Color="#5eff8a" Offset="0.3"/>
                        <GradientStop Color="#2ecc71" Offset="1"/>
                    </RadialGradientBrush>
                </Ellipse.Fill>
            </Ellipse>
            <Canvas x:Name="GreenCanvas" Width="40" Height="40">
                <Ellipse x:Name="GreenHead" Width="6" Height="6" Canvas.Left="17" Canvas.Top="8" Fill="#2d2d2d"/>
                <Line x:Name="GreenBody" X1="20" Y1="14" X2="20" Y2="24" Stroke="#2d2d2d" StrokeThickness="2"/>
                <Line x:Name="GreenLeftArm" X1="20" Y1="17" X2="14" Y2="22" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <Line x:Name="GreenRightArm" X1="20" Y1="17" X2="26" Y2="22" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <Line x:Name="GreenLeftLeg" X1="20" Y1="24" X2="20" Y2="30" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <Line x:Name="GreenRightLeg" X1="20" Y1="24" X2="20" Y2="30" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <Line x:Name="GreenSeat" X1="10" Y1="30" X2="30" Y2="30" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <!-- Computer Monitor (top edge at hand level Y=22) -->
                <Rectangle Width="10" Height="7" Canvas.Left="15" Canvas.Top="22" Stroke="#2d2d2d" StrokeThickness="1" Fill="#2d2d2d"/>
                <!-- Monitor Stand (monitor bottom to seat line) -->
                <Line X1="20" Y1="29" X2="20" Y2="30" Stroke="#2d2d2d" StrokeThickness="1"/>
                <!-- Keyboard (centered on X=20, on seat line Y=30) -->
                <Rectangle x:Name="GreenKeyboard" Width="8" Height="2" Canvas.Left="16" Canvas.Top="30" Fill="#2d2d2d" RadiusX="1" RadiusY="1"/>
            </Canvas>
        </Grid>

        <!-- Status Text -->
        <TextBlock Grid.Row="3" x:Name="StatusText" Text="Working" Foreground="#FFFFFF"
                   FontSize="10" HorizontalAlignment="Center" Margin="0,4,0,8"/>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Get UI element references
$redLed = $window.FindName("RedLed")
$yellowLed = $window.FindName("YellowLed")
$greenLed = $window.FindName("GreenLed")
$statusText = $window.FindName("StatusText")

# Red light figure parts
$redHead = $window.FindName("RedHead")
$redBody = $window.FindName("RedBody")
$redLeftArm = $window.FindName("RedLeftArm")
$redRightArm = $window.FindName("RedRightArm")
$redLeftLeg = $window.FindName("RedLeftLeg")
$redRightLeg = $window.FindName("RedRightLeg")
$redMonitor = $window.FindName("RedMonitor")
$redStand = $window.FindName("RedStand")
$redKeyboard = $window.FindName("RedKeyboard")

# Yellow light figure parts
$yellowHead = $window.FindName("YellowHead")
$yellowBody = $window.FindName("YellowBody")
$yellowLeftArm = $window.FindName("YellowLeftArm")
$yellowRightArm = $window.FindName("YellowRightArm")
$yellowLeftLeg = $window.FindName("YellowLeftLeg")
$yellowRightLeg = $window.FindName("YellowRightLeg")
$yellowSeat = $window.FindName("YellowSeat")

# Green light figure parts
$greenHead = $window.FindName("GreenHead")
$greenBody = $window.FindName("GreenBody")
$greenLeftArm = $window.FindName("GreenLeftArm")
$greenRightArm = $window.FindName("GreenRightArm")
$greenLeftLeg = $window.FindName("GreenLeftLeg")
$greenRightLeg = $window.FindName("GreenRightLeg")

# Initialize LED states
$redLed.Opacity = 0.15
$yellowLed.Opacity = 0.15
$greenLed.Opacity = 1.0

# === Animation State ===
$script:greenTypingPhase = 0.0
$script:greenTypingSpeed = 0.0
$script:greenTargetSpeed = 0.0

$script:yellowStretchPhase = 0.0
$script:yellowStretchActive = $false

$script:redThrowPhase = 0.0
$script:redThrowActive = $false

# === Green Light: Typing Animation ===
function Update-GreenTyping([double]$dt) {
    # Smooth speed transition
    $speedDiff = $script:greenTargetSpeed - $script:greenTypingSpeed
    $script:greenTypingSpeed += $speedDiff * [Math]::Min(1.0, $dt * 3.0)

    # Update typing phase
    if ($script:greenTypingSpeed -gt 0.01) {
        $script:greenTypingPhase += $dt * $script:greenTypingSpeed * 6.0
        $script:greenTypingPhase = $script:greenTypingPhase % (2 * [Math]::PI)
    }

    # Base positions for sitting pose
    $headY = 8
    $bodyY1 = 14
    $bodyY2 = 24
    $armBaseY = 22

    # Typing animation: arms move up and down alternately
    $armAmplitude = 3.0 * $script:greenTypingSpeed

    # Left arm: strikes keyboard
    $leftArmOffset = [Math]::Sin($script:greenTypingPhase) * $armAmplitude
    $greenLeftArm.X2 = 14
    $greenLeftArm.Y2 = $armBaseY - $leftArmOffset

    # Right arm: strikes keyboard (opposite phase)
    $rightArmOffset = [Math]::Sin($script:greenTypingPhase + [Math]::PI) * $armAmplitude
    $greenRightArm.X2 = 26
    $greenRightArm.Y2 = $armBaseY - $rightArmOffset

    # Head bob slightly while typing
    $headBob = [Math]::Abs([Math]::Sin($script:greenTypingPhase)) * 0.5 * $script:greenTypingSpeed
    $greenHead.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]($headY + $headBob))

    # Body leans forward slightly when typing fast
    $bodyLean = $script:greenTypingSpeed * 0.5
    $greenBody.Y1 = $bodyY1 + $bodyLean
}

function Set-GreenTypingSpeed([double]$typingSpeed) {
    $script:greenTargetSpeed = Get-AnimationSpeed $typingSpeed
}

# === Yellow Light: Sitting Stretch Animation ===
function Update-YellowStretch([double]$dt) {
    if (-not $script:yellowStretchActive) {
        # Idle sitting pose - legs together, arms down
        $yellowHead.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]8)
        $yellowBody.Y1 = 14; $yellowBody.Y2 = 24
        $yellowLeftArm.X2 = 16; $yellowLeftArm.Y2 = 20
        $yellowRightArm.X2 = 24; $yellowRightArm.Y2 = 20
        $yellowLeftLeg.X2 = 20; $yellowLeftLeg.Y2 = 30
        $yellowRightLeg.X2 = 20; $yellowRightLeg.Y2 = 30
        return
    }

    $script:yellowStretchPhase += $dt
    $progress = [Math]::Min(1.0, $script:yellowStretchPhase / 2.0)

    # Stretch animation: arms raise up, body straightens slightly
    if ($progress -lt 0.5) {
        # Phase 1: Raise arms
        $p = $progress * 2
        $armY = 20 - ($p * 14)  # Arms go from 20 to 6
        $yellowLeftArm.X2 = 16 - ($p * 8)  # Arms spread wider
        $yellowLeftArm.Y2 = $armY
        $yellowRightArm.X2 = 24 + ($p * 8)
        $yellowRightArm.Y2 = $armY
        # Body leans back slightly
        $yellowBody.Y1 = 14 - ($p * 2)
        # Head tilts up
        $yellowHead.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double](8 - $p * 3))
    } else {
        # Phase 2: Hold stretch, slight relaxation
        $p = ($progress - 0.5) * 2
        $armY = 6 + ($p * 2)  # Arms relax slightly
        $yellowLeftArm.X2 = 8 + ($p * 4)
        $yellowLeftArm.Y2 = $armY
        $yellowRightArm.X2 = 32 - ($p * 4)
        $yellowRightArm.Y2 = $armY
        $yellowBody.Y1 = 12 + $p
        $yellowHead.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double](5 + $p))
    }

    # Loop the animation
    if ($script:yellowStretchPhase -ge 2.5) {
        $script:yellowStretchPhase = 0.0
    }
}

# === Red Light: Throw Computer Animation ===
function Update-RedThrow([double]$dt) {
    if (-not $script:redThrowActive) {
        Reset-RedIdle
        return
    }

    $script:redThrowPhase += $dt
    $cyc = $script:redThrowPhase % 2.0

    if ($cyc -lt 0.6) {
        # Phase 1: Stand up, right arm reaches toward monitor
        $p = $cyc / 0.6
        $headY = 8 - ($p * 3)
        $bodyY1 = 14 - ($p * 3)
        $bodyY2 = 24 - ($p * 2)
        $redHead.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]$headY)
        $redBody.Y1 = $bodyY1; $redBody.Y2 = $bodyY2
        $redLeftLeg.X2 = 20 - ($p * 4); $redLeftLeg.Y2 = 30 + ($p * 2)
        $redRightLeg.X2 = 20 + ($p * 4); $redRightLeg.Y2 = 30 + ($p * 2)
        $redLeftArm.X2 = 16; $redLeftArm.Y2 = 20
        $redRightArm.X2 = 24 - ($p * 10); $redRightArm.Y2 = 20 + ($p * 5)
        $redMonitor.Opacity = 1.0
        $redMonitor.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]15)
        $redMonitor.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]22)
        $redStand.Opacity = 1.0
        $redKeyboard.Opacity = 1.0
    } elseif ($cyc -lt 1.1) {
        # Phase 2: Grab monitor, pull up
        $p = ($cyc - 0.6) / 0.5
        $redHead.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double](5 - $p * 2))
        $redBody.Y1 = 11 - ($p * 2); $redBody.Y2 = 22
        $redRightArm.X2 = 14 - ($p * 2); $redRightArm.Y2 = 25 - ($p * 10)
        $redLeftArm.X2 = 16; $redLeftArm.Y2 = 20
        $monitorX = 15 + ($p * 5); $monitorY = 22 - ($p * 10)
        $redMonitor.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]$monitorX)
        $redMonitor.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]$monitorY)
        $redMonitor.Opacity = 1.0
        $redStand.Opacity = 1.0 - $p
        $redKeyboard.Opacity = 1.0 - $p
    } elseif ($cyc -lt 1.6) {
        # Phase 3: Throw diagonally - arm swings right-up, monitor flies
        $p = ($cyc - 1.1) / 0.5
        $redRightArm.X2 = 12 + ($p * 20); $redRightArm.Y2 = 15 - ($p * 15)
        $redLeftArm.X2 = 16; $redLeftArm.Y2 = 20
        $redBody.Y1 = 9 - ($p * 3); $redBody.Y2 = 22
        $monitorX = 20 + ($p * 25); $monitorY = 12 - ($p * 15)
        $redMonitor.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]$monitorX)
        $redMonitor.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]$monitorY)
        $redMonitor.Opacity = 1.0 - ($p * 0.7)
        $redStand.Opacity = 0.0
        $redKeyboard.Opacity = 0.0
    } else {
        # Phase 4: Frozen throw pose, then instant reset
        $redRightArm.X2 = 32; $redRightArm.Y2 = 0
        $redLeftArm.X2 = 16; $redLeftArm.Y2 = 20
        $redBody.Y1 = 6; $redBody.Y2 = 22
        $redMonitor.Opacity = 0.0
        $redStand.Opacity = 0.0
        $redKeyboard.Opacity = 0.0
        if ($cyc -ge 1.9) {
            Reset-RedIdle
        }
    }
}

function Reset-RedIdle {
    $redHead.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]8)
    $redBody.Y1 = 14; $redBody.Y2 = 24
    $redLeftArm.X2 = 16; $redLeftArm.Y2 = 20
    $redRightArm.X2 = 24; $redRightArm.Y2 = 20
    $redLeftLeg.X2 = 20; $redLeftLeg.Y2 = 30
    $redRightLeg.X2 = 20; $redRightLeg.Y2 = 30
    $redMonitor.Opacity = 1.0
    $redMonitor.SetValue([System.Windows.Controls.Canvas]::LeftProperty, [double]15)
    $redMonitor.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double]22)
    $redStand.Opacity = 1.0
    $redKeyboard.Opacity = 1.0
}

# === State Change Detection ===
function Handle-StateChange {
    if (-not $script:stateChanged) { return }
    $script:stateChanged = $false

    $script:yellowStretchActive = $false
    $script:redThrowActive = $false

    switch ($script:state) {
        "warning" {
            $script:yellowStretchActive = $true
            $script:yellowStretchPhase = 0.0
        }
        "rest" {
            $script:redThrowActive = $true
            $script:redThrowPhase = 0.0
        }
    }
}

# === Window Drag and Menu ===
$window.Add_MouseLeftButtonDown({ $window.DragMove() })

$menu = New-Object System.Windows.Controls.ContextMenu
$muteItem = New-Object System.Windows.Controls.MenuItem
$muteItem.Header = "Mute"
$muteItem.Add_Click({
    $script:soundEnabled = -not $script:soundEnabled
    $muteItem.Header = if ($script:soundEnabled) { "Mute" } else { "Unmute" }
})
$menu.Items.Add($muteItem) | Out-Null

$separator = New-Object System.Windows.Controls.Separator
$menu.Items.Add($separator) | Out-Null

$resetItem = New-Object System.Windows.Controls.MenuItem
$resetItem.Header = "Reset Timer"
$resetItem.Add_Click({
    Set-State "working"
})
$menu.Items.Add($resetItem) | Out-Null

$separator2 = New-Object System.Windows.Controls.Separator
$menu.Items.Add($separator2) | Out-Null

$exitItem = New-Object System.Windows.Controls.MenuItem
$exitItem.Header = "Exit"
$exitItem.Add_Click({ $window.Close() })
$menu.Items.Add($exitItem) | Out-Null
$window.ContextMenu = $menu

# === Main Timer ===
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(16)
$script:lastTickTime = [DateTime]::UtcNow

$timer.Add_Tick({
    $now = [DateTime]::UtcNow
    $dt = ($now - $script:lastTickTime).TotalSeconds
    $script:lastTickTime = $now

    # 1. Poll keyboard
    Poll-Keyboard | Out-Null

    # 2. Update typing speed
    $typingSpeed = Update-TypingSpeed $script:typingSpeedWindow

    # 3. Check rest shortcut
    if (Poll-RestShortcut) {
        $script:restConfirmed = $true
    }

    # 4. Handle state changes
    Handle-StateChange

    # 5. Update state machine
    Update-StateMachine

    # 6. Update light patterns
    $script:patternTime += ($dt * 1000)
    $result = Get-PatternResult $script:currentPattern $script:patternTime
    $redLed.Opacity = [Math]::Max(0.15, [double]$result.Red)
    if ($script:state -eq "working") {
        $greenLed.Opacity = [Math]::Max(0.15, [double]$result.Green)
    } else {
        $greenLed.Opacity = 0.15
    }

    # Yellow light
    if ($script:state -eq "warning") {
        $yellowLed.Opacity = if (($script:patternTime % 800) -lt 400) { 1.0 } else { 0.3 }
    } else {
        $yellowLed.Opacity = 0.15
    }

    # 7. Update animations based on state
    switch ($script:state) {
        "working" {
            Set-GreenTypingSpeed $typingSpeed
            Update-GreenTyping $dt
        }
        "warning" {
            Update-YellowStretch $dt
        }
        "rest" {
            Update-RedThrow $dt
        }
    }

    # 8. Update status text
    switch ($script:state) {
        "working" {
            $remaining = [Math]::Max(0, $script:workDuration * 60 - (Get-ElapsedSeconds))
            $mins = [Math]::Floor($remaining / 60)
            $secs = [Math]::Floor($remaining % 60)
            $statusText.Text = "Working {0:D2}:{1:D2}" -f $mins, $secs
            $statusText.Foreground = "#FFFFFF"
        }
        "warning" {
            $remaining = [Math]::Max(0, $script:warningDuration * 60 - (Get-ElapsedSeconds))
            $mins = [Math]::Floor($remaining / 60)
            $secs = [Math]::Floor($remaining % 60)
            $statusText.Text = "Break {0:D2}:{1:D2}" -f $mins, $secs
            $statusText.Foreground = "#ffe066"
        }
        "rest" {
            $statusText.Text = "Working"
            $statusText.Foreground = "#ff6b6b"
        }
    }
})
$timer.Start()

# === Start ===
$window.ShowDialog()
