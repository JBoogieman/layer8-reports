<#
.SYNOPSIS
    Layer8 boot and crash collector. Puts the last 30 days of boots and crashes from a device's event logs into two
    WMI classes, root\cimv2 Layer8_Boot and Layer8_Crash, so ConfigMgr hardware inventory can collect them.

.DESCRIPTION
    Meant to run on each client as SYSTEM, once a day, from a configuration baseline. It changes nothing on the device
    except its own two WMI classes, which it replaces in full on every run.

    Layer8_Boot: one instance per boot, from events Windows writes on every boot:
      System log, Kernel-General 12   "The operating system started at system time ..."   -> BootStart
      System log, Kernel-Boot 27      "The boot type was 0x..."                            -> BootType
      System log, Kernel-Power 41     (written during the boot after an unexpected stop)   -> PreviousShutdown
    plus the timings from Diagnostics-Performance 100 ("Windows has started up") when Windows wrote one for that boot.
    It doesn't for every boot: in the lab, about half had one (boots nobody signed in to had none, nor the first of
    the two restarts an update install does), so boots without it keep the timing properties empty instead of being
    left out. A 100 is matched to its boot by its own BootStartTime, which in the lab was always within a second of
    event 12's StartTime. Not by when it was written: some were written during the next boot, and some carried a
    time hours off.

    Layer8_Crash: one instance per unexpected stop (Kernel-Power 41), with the bugcheck code and parameters when it
    was a blue screen, and the dump file Windows Error Reporting saved (WER-SystemErrorReporting 1001) when there is
    one. A 1001 with no 41 near it still counts as a bugcheck.

    Works in Constrained Language Mode: it reads events as XML from wevtutil.exe (never calling .NET methods on event
    objects), creates its classes with mofcomp.exe, and writes instances with the CIM cmdlets.

.PARAMETER Days
    How far back to read. 30 by default.

.PARAMETER Preview
    Show what would be stored, as objects, and don't touch WMI.

.EXAMPLE
    .\Layer8-BootAndCrash.ps1 -Preview
.EXAMPLE
    .\Layer8-BootAndCrash.ps1
#>
param(
    [ValidateRange(1, 365)][int]$Days = 30,
    [switch]$Preview
)

$ErrorActionPreference = 'Stop'
$Namespace = 'root/cimv2'

# The classes, as hardware inventory will see them. Changing a property here changes the schema: the script notices
# that the installed class differs and recreates it (its instances are rewritten on every run anyway).
$BootProperties  = 'BootId', 'BootStart', 'BootType', 'PreviousShutdown', 'BootTimeMs', 'MainPathBootTimeMs', 'PostBootTimeMs', 'UserLogonWaitMs', 'UserProfileMs', 'StartupApps'
$CrashProperties = 'CrashId', 'DetectedAt', 'Kind', 'BugcheckCode', 'BugcheckParameters', 'DumpFile'
$Mof = @'
#pragma namespace("\\\\.\\root\\cimv2")
#pragma deleteclass("Layer8_Boot", NOFAIL)
#pragma deleteclass("Layer8_Crash", NOFAIL)

[Description("Layer8: one boot per instance, from the Windows event logs. See github.com/JBoogieman/layer8-reports")]
class Layer8_Boot
{
    [key] string BootId;
    datetime BootStart;
    string   BootType;
    string   PreviousShutdown;
    uint32   BootTimeMs;
    uint32   MainPathBootTimeMs;
    uint32   PostBootTimeMs;
    uint32   UserLogonWaitMs;
    uint32   UserProfileMs;
    uint32   StartupApps;
};

[Description("Layer8: one unexpected stop per instance, from the Windows event logs. See github.com/JBoogieman/layer8-reports")]
class Layer8_Crash
{
    [key] string CrashId;
    datetime DetectedAt;
    string   Kind;
    string   BugcheckCode;
    string   BugcheckParameters;
    string   DumpFile;
};
'@

# ---------------------------------------------------------------------------------------------------------------
# Reading events

# Events from one log as XML nodes, newest last. The XPath filter keeps it to $Days.
function Read-Events([string]$Log, [string]$Provider, [int]$Id)
{
    $ms = [int64]$Days * 86400000
    $query = "*[System[Provider[@Name='$Provider'] and EventID=$Id and TimeCreated[timediff(@SystemTime) <= $ms]]]"
    $raw = wevtutil.exe qe $Log "/q:$query" /f:xml /e:Events 2>$null
    if (-not $raw) { return @() }
    $doc = [xml]($raw -join '')
    @($doc.Events.Event | Where-Object { $_ } | Sort-Object { Get-EventTime $_ })
}

# A named EventData value, or $null.
function Get-Field($Event, [string]$Name)
{
    foreach ($data in @($Event.EventData.Data)) {
        if ($data.Name -eq $Name) { return $data.'#text' }
    }
    $null
}

# Event times come as UTC with up to 9 decimal places; [datetime] takes 7 at most, and seconds are plenty.
function ConvertFrom-EventTime([string]$Text)
{
    if (-not $Text) { return $null }
    [datetime]($Text -replace '\.\d+Z$', 'Z')
}

function Get-EventTime($Event) { ConvertFrom-EventTime $Event.System.TimeCreated.SystemTime }

# A number from an event field, or $null when it's missing or not a number.
function Get-Number($Event, [string]$Name)
{
    $text = Get-Field $Event $Name
    if ($text -match '^\d+$') { [uint32]$text } else { $null }
}

# Hex like 0x0000009F from a decimal or 0x field. 0x values are padded as text: a kernel address such as
# 0xFFFF... doesn't fit the signed number PowerShell reads hex into.
function ConvertTo-HexText([string]$Text, [int]$Digits)
{
    if (-not $Text) { return $null }
    if ($Text -match '^0x([0-9a-fA-F]+)$') { return '0x' + $Matches[1].ToUpper().PadLeft($Digits, '0') }
    if ($Text -match '^\d+$') { return '0x' + ('{0:X' + $Digits + '}') -f [uint64]$Text }
    $Text
}

# ---------------------------------------------------------------------------------------------------------------
# Boots

$starts   = Read-Events 'System' 'Microsoft-Windows-Kernel-General' 12
$types    = Read-Events 'System' 'Microsoft-Windows-Kernel-Boot' 27
$timings  = Read-Events 'Microsoft-Windows-Diagnostics-Performance/Operational' 'Microsoft-Windows-Diagnostics-Performance' 100
$stops    = Read-Events 'System' 'Microsoft-Windows-Kernel-Power' 41
$reports  = Read-Events 'System' 'Microsoft-Windows-WER-SystemErrorReporting' 1001

# Each boot, with the time its events start (when event 12 was written) so the other events can be matched to it.
$boots = @(foreach ($e in $starts) {
    $startText = Get-Field $e 'StartTime'
    New-Object PSObject -Property ([ordered]@{
        Logged = Get-EventTime $e
        Id     = if ($startText) { $startText } else { $e.System.TimeCreated.SystemTime }
        Start  = if ($startText) { ConvertFrom-EventTime $startText } else { Get-EventTime $e }
    })
})

# The boot an event written later in a boot belongs to (1001, and a 100 without a BootStartTime): the last one
# logged at or before it.
function Get-BootIndex([datetime]$Time)
{
    $found = -1
    for ($i = 0; $i -lt $boots.Count; $i++) {
        if ($boots[$i].Logged -le $Time.AddSeconds(5)) { $found = $i } else { break }
    }
    $found
}

# The boot a Diagnostics-Performance 100 times: the one whose start is nearest the event's BootStartTime, within a
# minute.
function Get-BootIndexByStart([datetime]$Start)
{
    $found = -1
    $best = 60
    for ($i = 0; $i -lt $boots.Count; $i++) {
        $seconds = ($boots[$i].Start - $Start).TotalSeconds
        if ($seconds -lt 0) { $seconds = -$seconds }
        if ($seconds -le $best) { $best = $seconds; $found = $i }
    }
    $found
}

# The boot an event written early in a boot belongs to (27, 41): the nearest one, within 10 minutes. These can be
# stamped a moment before event 12, so "the last boot before it" would pick the previous boot.
function Get-NearestBootIndex([datetime]$Time)
{
    $found = -1
    $best = 600
    for ($i = 0; $i -lt $boots.Count; $i++) {
        $seconds = ($boots[$i].Logged - $Time).TotalSeconds
        if ($seconds -lt 0) { $seconds = -$seconds }
        if ($seconds -le $best) { $best = $seconds; $found = $i }
    }
    $found
}

$typeByBoot = @{}
foreach ($e in $types) {
    $i = Get-NearestBootIndex (Get-EventTime $e)
    if ($i -ge 0 -and -not $typeByBoot.ContainsKey($i)) { $typeByBoot[$i] = Get-Field $e 'BootType' }
}

$timingByBoot = @{}
foreach ($e in $timings) {
    $bootStart = ConvertFrom-EventTime (Get-Field $e 'BootStartTime')
    $i = if ($bootStart) { Get-BootIndexByStart $bootStart } else { Get-BootIndex (Get-EventTime $e) }
    if ($i -ge 0 -and -not $timingByBoot.ContainsKey($i)) { $timingByBoot[$i] = $e }
}

# ---------------------------------------------------------------------------------------------------------------
# Crashes

# Kernel-Power 41 is written early in the boot after the unexpected stop. WER 1001 comes later in the same boot.
$reportByBoot = @{}
foreach ($e in $reports) {
    $i = Get-BootIndex (Get-EventTime $e)
    if (-not $reportByBoot.ContainsKey($i)) { $reportByBoot[$i] = $e }
}

$crashes = @()
$stopByBoot = @{}
foreach ($e in $stops) {
    $i = Get-NearestBootIndex (Get-EventTime $e)
    $code = Get-Field $e 'BugcheckCode'
    $isBugcheck = $code -and $code -ne '0'
    $kind = if ($isBugcheck) { 'Bugcheck' }
            elseif ((Get-Field $e 'PowerButtonTimestamp') -notin $null, '', '0') { 'Power button held' }
            else { 'Lost power or reset' }
    $report = if ($reportByBoot.ContainsKey($i)) { $reportByBoot[$i] } else { $null }
    $parameters = $null
    if ($isBugcheck) {
        $parameters = (1..4 | ForEach-Object { ConvertTo-HexText (Get-Field $e "BugcheckParameter$_") 16 }) -join ', '
    }
    $dump = if ($report) { Get-Field $report 'param2' } else { $null }
    if ($report -and -not $isBugcheck) {
        # Kernel-Power didn't record the code but Windows Error Reporting did: it was a blue screen after all.
        $kind = 'Bugcheck'
        $code = ((Get-Field $report 'param1') -split ' ')[0]
    }
    if ($i -ge 0) { $stopByBoot[$i] = $kind }
    $crashes += New-Object PSObject -Property ([ordered]@{
        CrashId            = 'System-' + $e.System.EventRecordID
        DetectedAt         = Get-EventTime $e
        Kind               = $kind
        BugcheckCode       = if ($kind -eq 'Bugcheck') { ConvertTo-HexText $code 8 } else { $null }
        BugcheckParameters = $parameters
        DumpFile           = $dump
    })
}

# A blue screen Windows Error Reporting saw with no Kernel-Power 41 in the same boot.
foreach ($i in @($reportByBoot.Keys)) {
    if ($stopByBoot.ContainsKey($i)) { continue }
    $e = $reportByBoot[$i]
    $param1 = Get-Field $e 'param1'
    $parts = $param1 -split ' ', 2
    if ($i -ge 0) { $stopByBoot[$i] = 'Bugcheck' }
    $crashes += New-Object PSObject -Property ([ordered]@{
        CrashId            = 'System-' + $e.System.EventRecordID
        DetectedAt         = Get-EventTime $e
        Kind               = 'Bugcheck'
        BugcheckCode       = ConvertTo-HexText $parts[0] 8
        BugcheckParameters = if ($parts.Count -gt 1) { $parts[1].Trim('(', ')', ' ') } else { $null }
        DumpFile           = Get-Field $e 'param2'
    })
}

# ---------------------------------------------------------------------------------------------------------------
# The boot rows

$bootTypeNames = @{ '0' = 'Full boot'; '1' = 'Fast startup'; '2' = 'Resume from hibernation' }
$bootRows = @(for ($i = 0; $i -lt $boots.Count; $i++) {
    $type = $typeByBoot[$i]
    $timing = $timingByBoot[$i]
    $previous = if ($stopByBoot.ContainsKey($i)) { $stopByBoot[$i] } else { 'Normal' }
    New-Object PSObject -Property ([ordered]@{
        BootId             = $boots[$i].Id
        BootStart          = $boots[$i].Start
        BootType           = if ($null -eq $type) { $null } elseif ($bootTypeNames.ContainsKey([string]$type)) { $bootTypeNames[[string]$type] } else { "Other ($type)" }
        PreviousShutdown   = $previous
        BootTimeMs         = if ($timing) { Get-Number $timing 'BootTime' } else { $null }
        MainPathBootTimeMs = if ($timing) { Get-Number $timing 'MainPathBootTime' } else { $null }
        PostBootTimeMs     = if ($timing) { Get-Number $timing 'BootPostBootTime' } else { $null }
        UserLogonWaitMs    = if ($timing) { Get-Number $timing 'UserLogonWaitDuration' } else { $null }
        UserProfileMs      = if ($timing) { Get-Number $timing 'BootUserProfileProcessingTime' } else { $null }
        StartupApps        = if ($timing) { Get-Number $timing 'BootNumStartupApps' } else { $null }
    })
})

if ($Preview) {
    $bootRows
    $crashes
    return
}

# ---------------------------------------------------------------------------------------------------------------
# Writing to WMI

# Create or recreate the classes when they're missing or don't have exactly the properties above.
function Test-Class([string]$Name, [string[]]$Expected)
{
    $class = Get-CimClass -Namespace $Namespace -ClassName $Name -ErrorAction SilentlyContinue
    if (-not $class) { return $false }
    $have = @($class.CimClassProperties | ForEach-Object { $_.Name } | Sort-Object) -join ','
    $have -eq (@($Expected | Sort-Object) -join ',')
}

if (-not (Test-Class 'Layer8_Boot' $BootProperties) -or -not (Test-Class 'Layer8_Crash' $CrashProperties)) {
    $mofFile = Join-Path $env:TEMP 'Layer8-BootAndCrash.mof'
    Set-Content -Path $mofFile -Value $Mof -Encoding Unicode
    $output = mofcomp.exe $mofFile 2>&1
    $exit = $LASTEXITCODE
    Remove-Item $mofFile -ErrorAction SilentlyContinue
    if ($exit -ne 0) { throw "mofcomp failed ($exit): $($output -join ' ')" }
}

# Only the properties that have a value: WMI leaves the rest empty.
function Write-Instance([string]$Class, $Row)
{
    $values = @{}
    foreach ($p in $Row.PSObject.Properties) {
        if ($null -ne $p.Value -and $p.Value -ne '') { $values[$p.Name] = $p.Value }
    }
    New-CimInstance -Namespace $Namespace -ClassName $Class -Property $values | Out-Null
}

Get-CimInstance -Namespace $Namespace -ClassName Layer8_Boot  | Remove-CimInstance
Get-CimInstance -Namespace $Namespace -ClassName Layer8_Crash | Remove-CimInstance
foreach ($row in $bootRows) { Write-Instance 'Layer8_Boot' $row }
foreach ($row in $crashes)  { Write-Instance 'Layer8_Crash' $row }

$timed = @($bootRows | Where-Object { $null -ne $_.BootTimeMs }).Count
$bugchecks = @($crashes | Where-Object { $_.Kind -eq 'Bugcheck' }).Count
"Layer8 boot and crash collector: last $Days days, $($bootRows.Count) boots ($timed with timings), $($crashes.Count) unexpected stops ($bugchecks bugchecks)"
