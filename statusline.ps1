$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8NoBom
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

$script:DisableColor = $false
$script:UseAscii = $false
$script:SingleLine = $false

function Get-EnvBool {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $value = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($value)) {
    return $false
  }

  return $value -match '^(?i:1|true|yes|on)$'
}

function Get-NestedValue {
  param(
    [AllowNull()]
    $Object,

    [Parameter(Mandatory = $true)]
    [string[]]$Path
  )

  $current = $Object
  foreach ($segment in $Path) {
    if ($null -eq $current) {
      return $null
    }

    $property = $current.PSObject.Properties[$segment]
    if ($null -eq $property) {
      return $null
    }

    $current = $property.Value
  }

  return $current
}

function Get-LeafName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  try {
    return Split-Path -Path $Path -Leaf
  }
  catch {
    return $Path
  }
}

function Join-StatusSegment {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Segments
  )

  $usable = @($Segments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  return ($usable -join '  |  ')
}

function Colorize {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Text,

    [Parameter(Mandatory = $true)]
    [string]$Code
  )

  if ($script:DisableColor -or [string]::IsNullOrEmpty($Text)) {
    return $Text
  }

  $esc = [char]27
  return "$esc[$Code" + "m$Text$esc[0m"
}

function Find-GitRootPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory
  )

  try {
    $item = Get-Item -LiteralPath $WorkingDirectory -ErrorAction Stop
  }
  catch {
    return $null
  }

  $directory = $item
  if ($item -is [System.IO.FileInfo]) {
    $directory = $item.Directory
  }

  while ($null -ne $directory) {
    $gitMarker = Join-Path -Path $directory.FullName -ChildPath '.git'
    if (Test-Path -LiteralPath $gitMarker) {
      return $directory.FullName
    }

    $directory = $directory.Parent
  }

  return $null
}

function Invoke-GitText {
  param(
    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory,

    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    return $null
  }

  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & git -C $WorkingDirectory @Arguments 2>$null
  }
  catch {
    return $null
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }

  if ($LASTEXITCODE -ne 0) {
    return $null
  }

  if ($output -is [System.Array]) {
    return (($output -join "`n").Trim())
  }

  return ([string]$output).Trim()
}

function Get-GitInfo {
  param(
    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory
  )

  if (-not (Test-Path -LiteralPath $WorkingDirectory)) {
    return [pscustomobject]@{
      RepoName = Get-LeafName -Path $WorkingDirectory
      Branch = $null
      Dirty = $false
    }
  }

  $topLevel = Find-GitRootPath -WorkingDirectory $WorkingDirectory
  if ([string]::IsNullOrWhiteSpace($topLevel)) {
    return [pscustomobject]@{
      RepoName = Get-LeafName -Path $WorkingDirectory
      Branch = $null
      Dirty = $false
    }
  }

  $branch = Invoke-GitText -WorkingDirectory $WorkingDirectory -Arguments @('symbolic-ref', '--short', 'HEAD')
  if ([string]::IsNullOrWhiteSpace($branch)) {
    $branch = Invoke-GitText -WorkingDirectory $WorkingDirectory -Arguments @('rev-parse', '--short', 'HEAD')
  }

  $dirtyOutput = Invoke-GitText -WorkingDirectory $WorkingDirectory -Arguments @('status', '--porcelain', '--untracked-files=normal')
  $isDirty = -not [string]::IsNullOrWhiteSpace($dirtyOutput)

  return [pscustomobject]@{
    RepoName = Get-LeafName -Path $topLevel
    Branch = $branch
    Dirty = $isDirty
  }
}

function Convert-ToPercent {
  param(
    [AllowNull()]
    $Value
  )

  if ($null -eq $Value) {
    return $null
  }

  try {
    $number = [double]$Value
    if ($number -lt 0) {
      $number = 0
    }

    if ($number -gt 100) {
      $number = 100
    }

    return [Math]::Round($number)
  }
  catch {
    return $null
  }
}

function Get-BlockMeterText {
  param(
    [AllowNull()]
    $Percent,

    [Parameter(Mandatory = $true)]
    [string]$FilledCode,

    [Parameter(Mandatory = $true)]
    [string]$EmptyCode
  )

  if ($null -eq $Percent) {
    return (Colorize -Text '--' -Code $EmptyCode)
  }

  $filledSymbol = [string][char]0x2588  # filled block
  $emptySymbol = [string][char]0x2591   # light shade
  if ($script:UseAscii) {
    $filledSymbol = '#'
    $emptySymbol = '.'
  }

  $slots = 10
  $filledCount = [Math]::Round(([double]$Percent / 100.0) * $slots, [System.MidpointRounding]::AwayFromZero)
  if ($filledCount -lt 0) {
    $filledCount = 0
  }
  if ($filledCount -gt $slots) {
    $filledCount = $slots
  }

  $filledText = if ($filledCount -gt 0) { [string]::new($filledSymbol[0], $filledCount) } else { '' }
  $emptyCount = $slots - $filledCount
  $emptyText = if ($emptyCount -gt 0) { [string]::new($emptySymbol[0], $emptyCount) } else { '' }

  return ((Colorize -Text $filledText -Code $FilledCode) + (Colorize -Text $emptyText -Code $EmptyCode))
}

function Get-MeterText {
  param(
    [AllowNull()]
    $Percent,

    [Parameter(Mandatory = $true)]
    [string]$FilledCode,

    [Parameter(Mandatory = $true)]
    [string]$EmptyCode
  )

  if ($null -eq $Percent) {
    return (Colorize -Text '--' -Code $EmptyCode)
  }

  $filledSymbol = [string][char]0x25CF
  $emptySymbol = [string][char]0x25CB
  if ($script:UseAscii) {
    $filledSymbol = '#'
    $emptySymbol = '.'
  }

  $slots = 10
  $filledCount = [Math]::Round(([double]$Percent / 100.0) * $slots, [System.MidpointRounding]::AwayFromZero)
  if ($filledCount -lt 0) {
    $filledCount = 0
  }
  if ($filledCount -gt $slots) {
    $filledCount = $slots
  }

  $filledText = if ($filledCount -gt 0) { [string]::new($filledSymbol[0], $filledCount) } else { '' }
  $emptyCount = $slots - $filledCount
  $emptyText = if ($emptyCount -gt 0) { [string]::new($emptySymbol[0], $emptyCount) } else { '' }

  return ((Colorize -Text $filledText -Code $FilledCode) + (Colorize -Text $emptyText -Code $EmptyCode))
}

function Format-ResetAt {
  param(
    [AllowNull()]
    $Value,

    [Parameter(Mandatory = $true)]
    [ValidateSet('current', 'weekly')]
    [string]$Mode
  )

  if ($null -eq $Value) {
    return '--'
  }

  try {
    $epoch = [double]$Value
    $date = [DateTimeOffset]::FromUnixTimeSeconds([long]$epoch).LocalDateTime
    if ($Mode -eq 'current') {
      return $date.ToString('HH:mm')
    }

    return $date.ToString('M/d HH:mm')
  }
  catch {
    return '--'
  }
}

function Build-UsageLine {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Label,

    [AllowNull()]
    $Percent,

    [AllowNull()]
    $ResetsAt,

    [Parameter(Mandatory = $true)]
    [string]$ActiveColor,

    [Parameter(Mandatory = $true)]
    [string]$Mode
  )

  $labelText = (Colorize -Text $Label.PadRight(7) -Code '38;5;252')
  $meter = Get-MeterText -Percent $Percent -FilledCode $ActiveColor -EmptyCode '38;5;240'
  $percentText = if ($null -eq $Percent) { Colorize -Text '--' -Code '38;5;240' } else { Colorize -Text ('{0,3}%' -f $Percent) -Code $ActiveColor }
  $resetText = Colorize -Text (Format-ResetAt -Value $ResetsAt -Mode $Mode) -Code '38;5;245'

  return "$labelText $meter $percentText  $resetText"
}

function Get-StatusInput {
  $stdinText = [Console]::In.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($stdinText)) {
    return $null
  }

  try {
    return ($stdinText | ConvertFrom-Json)
  }
  catch {
    return $null
  }
}

try {
  $script:DisableColor = (Get-EnvBool -Name 'CC_STATUSLINE_NO_COLOR') -or (Get-EnvBool -Name 'NO_COLOR')
  $script:UseAscii = Get-EnvBool -Name 'CC_STATUSLINE_ASCII'
  $script:SingleLine = Get-EnvBool -Name 'CC_STATUSLINE_SINGLE_LINE'

  $statusInput = Get-StatusInput
  if ($null -eq $statusInput) {
    exit 0
  }

  $currentDirectory = Get-NestedValue -Object $statusInput -Path @('workspace', 'current_dir')
  if ([string]::IsNullOrWhiteSpace($currentDirectory)) {
    $currentDirectory = Get-NestedValue -Object $statusInput -Path @('cwd')
  }
  if ([string]::IsNullOrWhiteSpace($currentDirectory)) {
    $currentDirectory = (Get-Location).Path
  }

  $modelName = Get-NestedValue -Object $statusInput -Path @('model', 'display_name')
  if ([string]::IsNullOrWhiteSpace($modelName)) {
    $modelName = Get-NestedValue -Object $statusInput -Path @('model', 'name')
  }
  if ([string]::IsNullOrWhiteSpace($modelName)) {
    $modelName = Get-NestedValue -Object $statusInput -Path @('model', 'id')
  }
  if ([string]::IsNullOrWhiteSpace($modelName)) {
    $modelName = 'Claude Code'
  }

  $gitInfo = Get-GitInfo -WorkingDirectory $currentDirectory
  $repoSegment = Colorize -Text $gitInfo.RepoName -Code '38;5;45'
  if (-not [string]::IsNullOrWhiteSpace($gitInfo.Branch)) {
    $branchSuffix = if ($gitInfo.Dirty) { '*' } else { '' }
    $repoSegment += ' ' + (Colorize -Text ("({0}{1})" -f $gitInfo.Branch, $branchSuffix) -Code '38;5;47')
  }

  $contextPercent = Convert-ToPercent -Value (Get-NestedValue -Object $statusInput -Path @('context_window', 'used_percentage'))

  # Read rate_limits from stdin JSON (provided by Claude Code v2.1.80+)
  $currentPercent = Convert-ToPercent -Value (Get-NestedValue -Object $statusInput -Path @('rate_limits', 'five_hour', 'used_percentage'))
  $currentReset = Get-NestedValue -Object $statusInput -Path @('rate_limits', 'five_hour', 'resets_at')
  $weeklyPercent = Convert-ToPercent -Value (Get-NestedValue -Object $statusInput -Path @('rate_limits', 'seven_day', 'used_percentage'))
  $weeklyReset = Get-NestedValue -Object $statusInput -Path @('rate_limits', 'seven_day', 'resets_at')

  $topSegments = @(
    (Colorize -Text $modelName -Code '38;5;39'),
    $repoSegment
  )

  $topLine = Join-StatusSegment -Segments $topSegments

  $contextColor = if ($null -eq $contextPercent) { '38;5;82' }
    elseif ($contextPercent -ge 90) { '38;5;196' }
    elseif ($contextPercent -ge 80) { '38;5;208' }
    elseif ($contextPercent -ge 60) { '38;5;220' }
    else { '38;5;82' }

  $contextLabelText = (Colorize -Text 'context'.PadRight(7) -Code '38;5;252')
  $contextMeter = Get-BlockMeterText -Percent $contextPercent -FilledCode $contextColor -EmptyCode '38;5;240'
  $contextPercentText = if ($null -eq $contextPercent) { Colorize -Text '--' -Code '38;5;240' } else { Colorize -Text ('{0,3}%' -f $contextPercent) -Code $contextColor }
  $contextLine = "$contextLabelText $contextMeter $contextPercentText"

  $currentLine = Build-UsageLine -Label 'current' -Percent $currentPercent -ResetsAt $currentReset -ActiveColor '38;5;47' -Mode 'current'
  $weeklyLine = Build-UsageLine -Label 'weekly' -Percent $weeklyPercent -ResetsAt $weeklyReset -ActiveColor '38;5;220' -Mode 'weekly'

  if ($script:SingleLine) {
    $usageSummary = Join-StatusSegment -Segments @(
      (Colorize -Text ("context {0}" -f (if ($null -eq $contextPercent) { '--' } else { "$contextPercent%" })) -Code $contextColor),
      (Colorize -Text ("current {0}" -f (if ($null -eq $currentPercent) { '--' } else { "$currentPercent%" })) -Code '38;5;47'),
      (Colorize -Text ("weekly {0}" -f (if ($null -eq $weeklyPercent) { '--' } else { "$weeklyPercent%" })) -Code '38;5;220')
    )

    Write-Output (Join-StatusSegment -Segments @($topLine, $usageSummary))
    exit 0
  }

  Write-Output $topLine
  Write-Output $contextLine
  Write-Output $currentLine
  Write-Output $weeklyLine
}
catch {
  if (Get-EnvBool -Name 'CC_STATUSLINE_DEBUG') {
    Write-Error -ErrorRecord $_
  }

  exit 0
}
