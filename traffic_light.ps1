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
$script:workDuration = 50        # Work duration (minutes)
$script:warningDuration = 10     # Warning duration (minutes)
$script:restThreshold = 180      # Rest detection threshold (seconds)
$script:typingSpeedWindow = 5    # Typing speed calculation window (seconds)
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
$script:state = "working"        # working | warning | rest
$script:stateStartTime = [DateTime]::UtcNow
$script:lastStateChangeTime = [DateTime]::UtcNow
$script:currentPattern = 0
$script:patternTime = 0.0
$script:lastSoundState = ""
$script:restConfirmed = $false

function Get-ElapsedSeconds {
    return ([DateTime]::UtcNow - $script:stateStartTime).TotalSeconds
}

function Set-State([string]$newState) {
    if ($newState -eq $script:state) { return }

    $script:state = $newState
    $script:stateStartTime = [DateTime]::UtcNow
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
            # Check if work duration exceeded
            $workSeconds = $script:workDuration * 60
            if ($elapsed -ge $workSeconds) {
                Set-State "warning"
            }

            # Select pattern based on typing speed
            if ($typingSpeed -gt 0.5) {
                $script:currentPattern = 1  # Green breathing (active)
            } else {
                $script:currentPattern = 0  # Green solid
            }
        }

        "warning" {
            # Check if warning duration exceeded
            $warningSeconds = $script:warningDuration * 60
            if ($elapsed -ge $warningSeconds) {
                Set-State "rest"
            }

            # Warning pattern
            if ($elapsed -gt ($script:warningDuration * 60 * 0.7)) {
                $script:currentPattern = 3  # Fast flash
            } else {
                $script:currentPattern = 2  # Slow flash
            }
        }

        "rest" {
            # Check rest confirmation
            if ($script:restConfirmed -or $idleSeconds -ge $script:restThreshold) {
                Set-State "working"
                $script:restConfirmed = $false
            }

            # Rest pattern
            $script:currentPattern = 4  # Red flash
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

        <!-- Red Light -->
        <Ellipse Grid.Row="0" x:Name="RedLed" Width="40" Height="40" Margin="0,8,0,0" HorizontalAlignment="Center">
            <Ellipse.Fill>
                <RadialGradientBrush>
                    <GradientStop Color="#ff6b6b" Offset="0.3"/>
                    <GradientStop Color="#e74c3c" Offset="1"/>
                </RadialGradientBrush>
            </Ellipse.Fill>
        </Ellipse>

        <!-- Yellow Light -->
        <Ellipse Grid.Row="1" x:Name="YellowLed" Width="40" Height="40" Margin="0,4,0,0" HorizontalAlignment="Center">
            <Ellipse.Fill>
                <RadialGradientBrush>
                    <GradientStop Color="#ffe066" Offset="0.3"/>
                    <GradientStop Color="#f1c40f" Offset="1"/>
                </RadialGradientBrush>
            </Ellipse.Fill>
        </Ellipse>

        <!-- Green Light with Pedestrian -->
        <Grid Grid.Row="2" Width="40" Height="40" Margin="0,4,0,0" HorizontalAlignment="Center">
            <Ellipse x:Name="GreenLed" Width="40" Height="40">
                <Ellipse.Fill>
                    <RadialGradientBrush>
                        <GradientStop Color="#5eff8a" Offset="0.3"/>
                        <GradientStop Color="#2ecc71" Offset="1"/>
                    </RadialGradientBrush>
                </Ellipse.Fill>
            </Ellipse>
            <Canvas x:Name="PedestrianCanvas" Width="40" Height="40" Margin="0">
                <!-- Head -->
                <Ellipse x:Name="Head" Width="6" Height="6" Canvas.Left="17" Canvas.Top="4" Fill="#2d2d2d"/>
                <!-- Body -->
                <Line x:Name="Body" X1="20" Y1="10" X2="20" Y2="22" Stroke="#2d2d2d" StrokeThickness="2"/>
                <!-- Left Arm -->
                <Line x:Name="LeftArm" X1="20" Y1="14" X2="14" Y2="20" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <!-- Right Arm -->
                <Line x:Name="RightArm" X1="20" Y1="14" X2="26" Y2="20" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <!-- Left Leg -->
                <Line x:Name="LeftLeg" X1="20" Y1="22" X2="14" Y2="32" Stroke="#2d2d2d" StrokeThickness="1.5"/>
                <!-- Right Leg -->
                <Line x:Name="RightLeg" X1="20" Y1="22" X2="26" Y2="32" Stroke="#2d2d2d" StrokeThickness="1.5"/>
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
$pedestrianCanvas = $window.FindName("PedestrianCanvas")
$statusText = $window.FindName("StatusText")

# Pedestrian parts
$head = $window.FindName("Head")
$body = $window.FindName("Body")
$leftArm = $window.FindName("LeftArm")
$rightArm = $window.FindName("RightArm")
$leftLeg = $window.FindName("LeftLeg")
$rightLeg = $window.FindName("RightLeg")

# Initialize LED states
$redLed.Opacity = 0.15
$yellowLed.Opacity = 0.15
$greenLed.Opacity = 1.0

# === Pedestrian Animation ===
$script:pedestrianPhase = 0.0
$script:pedestrianSpeed = 0.0  # Current animation speed (0-2)
$script:targetSpeed = 0.0      # Target speed

function Update-PedestrianAnimation([double]$dt) {
    # Smooth transition to target speed
    $speedDiff = $script:targetSpeed - $script:pedestrianSpeed
    $script:pedestrianSpeed += $speedDiff * [Math]::Min(1.0, $dt * 3.0)

    # Update animation phase
    if ($script:pedestrianSpeed -gt 0.01) {
        $script:pedestrianPhase += $dt * $script:pedestrianSpeed * 4.0
        $script:pedestrianPhase = $script:pedestrianPhase % (2 * [Math]::PI)
    }

    # Center point for pedestrian in 40x40 green light
    $cx = 20; $cy = 22

    # Calculate leg swing angle (radians)
    $legSwing = 0.35 * $script:pedestrianSpeed
    $leftAngle = [Math]::Sin($script:pedestrianPhase) * $legSwing
    $rightAngle = [Math]::Sin($script:pedestrianPhase + [Math]::PI) * $legSwing

    # Calculate arm swing angle
    $armSwing = 0.3 * $script:pedestrianSpeed
    $leftArmAngle = [Math]::Sin($script:pedestrianPhase + [Math]::PI) * $armSwing
    $rightArmAngle = [Math]::Sin($script:pedestrianPhase) * $armSwing

    # Update left leg position
    $leftLeg.X2 = $cx + [Math]::Sin($leftAngle) * 10
    $leftLeg.Y2 = $cy + [Math]::Cos($leftAngle) * 10

    # Update right leg position
    $rightLeg.X2 = $cx + [Math]::Sin($rightAngle) * 10
    $rightLeg.Y2 = $cy + [Math]::Cos($rightAngle) * 10

    # Update left arm position
    $leftArm.X2 = $cx + [Math]::Sin($leftArmAngle) * 8
    $leftArm.Y2 = 14 + [Math]::Cos($leftArmAngle) * 8

    # Update right arm position
    $rightArm.X2 = $cx + [Math]::Sin($rightArmAngle) * 8
    $rightArm.Y2 = 14 + [Math]::Cos($rightArmAngle) * 8

    # Head bob
    $headBob = [Math]::Abs([Math]::Sin($script:pedestrianPhase * 2)) * 1.5 * $script:pedestrianSpeed
    $head.SetValue([System.Windows.Controls.Canvas]::TopProperty, [double](4 + $headBob))
}

function Set-PedestrianSpeed([double]$typingSpeed) {
    $script:targetSpeed = Get-AnimationSpeed $typingSpeed
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
$timer.Interval = [TimeSpan]::FromMilliseconds(16)  # ~60fps
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

    # 4. Update state machine
    Update-StateMachine

    # 5. Update light pattern
    $script:patternTime += ($dt * 1000)
    $result = Get-PatternResult $script:currentPattern $script:patternTime
    $redLed.Opacity = [Math]::Max(0.15, [double]$result.Red)
    $greenLed.Opacity = [Math]::Max(0.15, [double]$result.Green)

    # Yellow light state (show during warning phase)
    if ($script:state -eq "warning") {
        $yellowLed.Opacity = if (($script:patternTime % 800) -lt 400) { 1.0 } else { 0.3 }
    } else {
        $yellowLed.Opacity = 0.15
    }

    # 6. Update pedestrian animation
    Set-PedestrianSpeed $typingSpeed
    Update-PedestrianAnimation $dt

    # 7. Update status text
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
            $statusText.Text = "Rest! Ctrl+Alt+R"
            $statusText.Foreground = "#ff6b6b"
        }
    }
})
$timer.Start()

# === Start ===
$window.ShowDialog()
