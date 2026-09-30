Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$uiLanguage = try { (Get-WinUserLanguageList | Select-Object -First 1).LanguageTag } catch { (Get-Culture).Name }
$script:UseTurkish = $uiLanguage -like 'tr*'
function L([string]$tr, [string]$en) { if ($script:UseTurkish) { return $tr }; return $en }

function Show-Error([string]$message) {
  [System.Windows.Forms.MessageBox]::Show($message, 'CATIA Large Assembly Profile', 'OK', 'Error') | Out-Null
}

function Select-Folder([string]$initialPath) {
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  $dialog.Description = 'Klasör seçin'
  if ($initialPath -and (Test-Path -LiteralPath $initialPath)) { $dialog.SelectedPath = $initialPath }
  if ($dialog.ShowDialog() -eq 'OK') { return $dialog.SelectedPath }
  return $null
}

function Select-File([string]$initialPath, [string]$filter) {
  $dialog = New-Object System.Windows.Forms.OpenFileDialog
  $dialog.Filter = $filter
  if ($initialPath -and (Test-Path -LiteralPath $initialPath)) { $dialog.InitialDirectory = $initialPath }
  if ($dialog.ShowDialog() -eq 'OK') { return $dialog.FileName }
  return $null
}

function Find-CatEnvFolders {
  $candidates = @(
    (Join-Path $env:ProgramData 'DassaultSystemes\CATEnv'),
    (Join-Path $env:APPDATA 'DassaultSystemes\CATEnv')
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
  return $candidates
}

function Get-EnvironmentFiles([string]$folder) {
  if (-not (Test-Path -LiteralPath $folder)) { return @() }
  return @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.CATEnv','.txt','' } | Sort-Object Name)
}

function Get-NormalizedPath([string]$path) {
  if ([string]::IsNullOrWhiteSpace($path)) { return $null }
  try { return [IO.Path]::GetFullPath($path.Trim().Trim('"')) } catch { return $null }
}

function Test-PathWithin([string]$path, [string]$root, [bool]$allowEqual = $true) {
  $fullPath = Get-NormalizedPath $path
  $fullRoot = Get-NormalizedPath $root
  if (-not $fullPath -or -not $fullRoot) { return $false }
  $rootPrefix = $fullRoot.TrimEnd('\') + '\'
  if ($allowEqual -and $fullPath.TrimEnd('\') -ieq $fullRoot.TrimEnd('\')) { return $true }
  return $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-SafeProfileInputs([string]$source, [string]$environmentRoot, [string]$settingsRoot, [string]$catStart) {
  $safeEnvRoots = Find-CatEnvFolders
  if (-not ($safeEnvRoots | Where-Object { Test-PathWithin $source $_ $false })) { throw 'Kaynak environment dosyası yalnızca CATIA CATEnv klasörlerinden seçilebilir.' }
  if ([IO.Path]::GetExtension($source) -notin '.txt','.CATEnv') { throw 'Kaynak yalnızca CATIA environment (.txt veya .CATEnv) dosyası olabilir.' }
  if ((Get-Item -LiteralPath $source).Length -gt 2MB) { throw 'Kaynak environment dosyası beklenenden büyük; güvenlik için işlem durduruldu.' }
  $expectedEnvRoot = Join-Path $env:APPDATA 'DassaultSystemes\CATEnv'
  $expectedSettingsParent = Join-Path $env:APPDATA 'DassaultSystemes'
  if ((Get-NormalizedPath $environmentRoot) -ine (Get-NormalizedPath $expectedEnvRoot)) { throw 'Güvenlik için yeni environment yalnızca kullanıcı CATEnv klasörüne yazılabilir.' }
  if (-not (Test-PathWithin $settingsRoot $expectedSettingsParent $false) -or ([IO.Path]::GetFileName((Get-NormalizedPath $settingsRoot)) -notmatch '^CATSettings[_-]')) { throw 'Güvenlik için CATSettings klasörü AppData\\Roaming\\DassaultSystemes altında CATSettings_ ile başlamalıdır.' }
  $installRoot = Join-Path $env:ProgramFiles 'Dassault Systemes'
  if (-not (Test-PathWithin $catStart $installRoot $false) -or [IO.Path]::GetFileName($catStart) -ine 'CATSTART.exe') { throw 'CATSTART.exe yalnızca doğrulanmış Dassault Systemes kurulum yolundan kullanılabilir.' }
  foreach ($directory in @($environmentRoot, $settingsRoot)) { if ((Test-Path -LiteralPath $directory) -and ((Get-Item -LiteralPath $directory).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Bağlantı/junction klasörlerine yazma güvenlik için engellendi.' } }
  foreach ($value in @($source, $environmentRoot, $settingsRoot, $catStart)) { if ($value.Contains('"')) { throw 'Yollarda çift tırnak karakteri kullanılamaz.' } }
}

function Replace-CatUserSettingPath([string]$content, [string]$settingsPath) {
  $newLine = "CATUserSettingPath=$settingsPath"
  $pattern = '(?im)^\s*CATUserSettingPath\s*=.*$'
  if ($content -match $pattern) { return [regex]::Replace($content, $pattern, $newLine) }
  $ending = if ($content.EndsWith("`r`n")) { '' } else { "`r`n" }
  return "$content$ending$newLine`r`n"
}

function ConvertTo-UserEnvironment([string]$content) {
  $content = [regex]::Replace($content, '(?im)^!\s*MODE\s*:\s*Global\s*$', '! MODE : User')
  $content = [regex]::Replace($content, '(?im)^!\s*ARGS\s*:\s*.*$', '! ARGS : -cs CATIA -a user -icon yes -menu yes -tools')
  return $content
}

function Set-QuickStartupVariables([string]$content, [bool]$enabled) {
  $variables = [ordered]@{
    'CATNoStartDocument' = if ($enabled) { 'YES' } else { 'NO' }
    'CNEXTSPLASHSCREEN'  = if ($enabled) { 'NO' } else { 'YES' }
    'CNEXTBACKGROUND'    = if ($enabled) { 'NO' } else { 'YES' }
  }
  foreach ($name in $variables.Keys) {
    $line = "$name=$($variables[$name])"
    $pattern = "(?im)^\s*$([regex]::Escape($name))\s*=.*$"
    if ($content -match $pattern) {
      $content = [regex]::Replace($content, $pattern, $line)
    } else {
      if (-not $content.EndsWith("`n")) { $content += "`r`n" }
      $content += "$line`r`n"
    }
  }
  return $content
}

function Find-CatStart([string]$environmentFile) {
  try {
    $text = [IO.File]::ReadAllText($environmentFile)
    $match = [regex]::Match($text, '(?im)^\s*CATInstallPath\s*=\s*(.+?)\s*$')
    if ($match.Success) {
      $candidate = Join-Path $match.Groups[1].Value.Trim() 'code\bin\CATSTART.exe'
      if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
  } catch { }
  return $null
}

function Set-ApplicationIcon([string]$catStartPath) {
  try { if ($catStartPath -and (Test-Path -LiteralPath $catStartPath -PathType Leaf)) { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($catStartPath) } } catch { }
}

function Resolve-CatPath([string]$path) {
  return $path.Trim().Trim('"').Replace('CSIDL_APPDATA', $env:APPDATA).Replace('CSIDL_LOCAL_APPDATA', $env:LOCALAPPDATA)
}

function Find-CatUserSettingPath([string]$environmentFile) {
  try {
    $text = [IO.File]::ReadAllText($environmentFile)
    $match = [regex]::Match($text, '(?im)^\s*CATUserSettingPath\s*=\s*(.+?)\s*$')
    if ($match.Success) { return Resolve-CatPath $match.Groups[1].Value }
  } catch { }
  return $null
}

function Copy-LicenseSetting([string]$sourceEnvironment, [string]$targetSettings) {
  $sourceSettings = Find-CatUserSettingPath $sourceEnvironment
  if (-not $sourceSettings -or -not (Test-Path -LiteralPath $sourceSettings -PathType Container)) { return 'Kaynak CATSettings klasörü bulunamadı; lisans seçimi kopyalanmadı.' }
  $license = Get-ChildItem -LiteralPath $sourceSettings -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq 'licenses.CATSettings' } | Select-Object -First 1
  if (-not $license) { return 'Kaynakta licenses.CATSettings bulunamadı; CATIA lisans seçimi ilk açılışta yapılır.' }
  $target = Join-Path $targetSettings 'licenses.CATSettings'
  if (Test-Path -LiteralPath $target -PathType Leaf) { return 'Yeni profildeki mevcut licenses.CATSettings korundu; üzerine yazılmadı.' }
  Copy-Item -LiteralPath $license.FullName -Destination $target -ErrorAction Stop
  return 'Mevcut licenses.CATSettings kopyalandı; lisans seçimi korundu.'
}

function Write-CatiaApplyMacro([string]$settingsPath, [int]$cacheSizeMB) {
  $macroPath = Join-Path $settingsPath 'ApplyLargeAssemblyProfile.CATScript'
  $logPath = Join-Path $settingsPath 'ApplyLargeAssemblyProfile.log'
  $macro = @'
Language="VBSCRIPT"
Sub CATMain()
  Dim controllers, cache, visual, part, fso, logFile
  Set fso = CreateObject("Scripting.FileSystemObject")
  Set logFile = fso.CreateTextFile("__LOG__", True)
  logFile.WriteLine "CATIA Large Assembly profile - " & Now
  On Error Resume Next
  Set controllers = CATIA.SettingControllers
  Set cache = controllers.Item("CATSysCacheSettingCtrl")
  cache.ActivationMode = True
  cache.CacheMaxSize = __CACHE__
  cache.SaveRepository
  logFile.WriteLine "Cache controller: " & Err.Number & " " & Err.Description
  Err.Clear
  logFile.WriteLine "Cache verification: ActivationMode=" & cache.ActivationMode & "; CacheMaxSize=" & cache.CacheMaxSize
  Set visual = controllers.Item("CATVizVisualizationSettingCtrl")
  visual.Viz3DAccuracyMode = False
  visual.Viz3DFixedAccuracy = 0.1
  visual.Viz3DCurveAccuracy = 0.1
  visual.Viz2DAccuracyMode = False
  visual.Viz2DFixedAccuracy = 0.02
  visual.StaticLOD = 0.5
  visual.DynamicLOD = 13.5
  visual.StaticCull = 2
  visual.DynamicCull = 14
  visual.TransparencyMode = False
  visual.SaveRepository
  logFile.WriteLine "Display controller: " & Err.Number & " " & Err.Description
  Err.Clear
  Set part = controllers.Item("CATMmuPartInfrastructureSettingCtrl")
  part.HybridDesignMode = False
  part.SaveRepository
  logFile.WriteLine "Part controller: " & Err.Number & " " & Err.Description
  logFile.Close
End Sub
'@
  $macro = $macro.Replace('__CACHE__', [string]$cacheSizeMB).Replace('__LOG__', $logPath)
  Set-Content -LiteralPath $macroPath -Value $macro -Encoding ascii
  return $macroPath
}

$form = New-Object System.Windows.Forms.Form
$form.Text = L 'CATIA V5 Büyük Montaj Profili' 'CATIA V5 Large Assembly Profile'
$form.Size = New-Object System.Drawing.Size(900, 460)
$form.MinimumSize = New-Object System.Drawing.Size(860, 460)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)

$header = New-Object System.Windows.Forms.Panel
$header.BackColor = [System.Drawing.Color]::FromArgb(14, 45, 79)
$header.Dock = 'Top'; $header.Height = 106
$form.Controls.Add($header)

$title = New-Object System.Windows.Forms.Label
$title.Text = L 'Güvenli, ayrı CATIA büyük montaj profili oluştur' 'Create a safe, separate CATIA large assembly profile'
$title.ForeColor = [System.Drawing.Color]::White
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16, [System.Drawing.FontStyle]::Regular)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(28, 20)
$header.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = L 'Mevcut environment ve CATSettings değiştirilmez. Kaynak environment klonlanır; yalnızca yeni klondaki CATUserSettingPath güncellenir.' 'Your current environment and CATSettings are not changed. The source environment is copied and only CATUserSettingPath in the copy is updated.'
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(208,222,237)
$subtitle.AutoSize = $false; $subtitle.Size = New-Object System.Drawing.Size(820, 42); $subtitle.Location = New-Object System.Drawing.Point(30, 56)
$header.Controls.Add($subtitle)

$script:basicControls = New-Object System.Collections.ArrayList
function Add-Card([int]$x, [string]$heading, [string]$detail, [System.Drawing.Color]$accent) {
  $card = New-Object System.Windows.Forms.Panel; $card.Location = New-Object System.Drawing.Point($x, 132); $card.Size = New-Object System.Drawing.Size(260, 124); $card.BackColor = [System.Drawing.Color]::White; $card.BorderStyle = 'FixedSingle'; $form.Controls.Add($card)
  $stripe = New-Object System.Windows.Forms.Panel; $stripe.BackColor = $accent; $stripe.Location = New-Object System.Drawing.Point(0,0); $stripe.Size = New-Object System.Drawing.Size(6,124); $card.Controls.Add($stripe)
  $cardTitle = New-Object System.Windows.Forms.Label; $cardTitle.Text = $heading; $cardTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold',10); $cardTitle.ForeColor = [System.Drawing.Color]::FromArgb(25,40,55); $cardTitle.AutoSize = $true; $cardTitle.Location = New-Object System.Drawing.Point(18,18); $card.Controls.Add($cardTitle)
  $cardText = New-Object System.Windows.Forms.Label; $cardText.Text = $detail; $cardText.ForeColor = [System.Drawing.Color]::FromArgb(85,97,110); $cardText.AutoSize = $false; $cardText.Size = New-Object System.Drawing.Size(220,64); $cardText.Location = New-Object System.Drawing.Point(18,48); $card.Controls.Add($cardText)
  [void]$script:basicControls.Add($card)
}
Add-Card 28 (L 'İzole profil' 'Isolated profile') (L 'Ayrı CATSettings ile mevcut çalışma düzeniniz korunur.' 'Your current working setup stays untouched.') ([System.Drawing.Color]::FromArgb(30,120,190))
Add-Card 320 (L 'Performans' 'Performance') (L 'Cache, görüntüleme ve hibrit tasarım ayarları uygulanır.' 'Cache, display, and hybrid-design settings are applied.') ([System.Drawing.Color]::FromArgb(30,150,105))
Add-Card 612 (L 'Güvenli başlatma' 'Safe launch') (L 'Lisans seçimi korunur ve yalnız doğrulanmış CATIA başlatılır.' 'License selection is retained; only verified CATIA is launched.') ([System.Drawing.Color]::FromArgb(218,132,35))

$quickStartupToggle = New-Object System.Windows.Forms.CheckBox
$quickStartupToggle.Text = L 'Hızlı açılış: başlangıç dokümanı, açılış logosu ve arka planı gösterme' 'Fast startup: hide start document, splash screen, and background'
$quickStartupToggle.Checked = $true
$quickStartupToggle.AutoSize = $true; $quickStartupToggle.Location = New-Object System.Drawing.Point(30, 286)
$form.Controls.Add($quickStartupToggle)

$advancedToggle = New-Object System.Windows.Forms.CheckBox
$advancedToggle.Text = L 'İleri seviye ayarları göster' 'Show advanced settings'
$advancedToggle.AutoSize = $true; $advancedToggle.Location = New-Object System.Drawing.Point(30, 318)
$form.Controls.Add($advancedToggle)

$script:advancedControls = New-Object System.Collections.ArrayList

function Add-Field([string]$label, [int]$y, [string]$defaultValue, [bool]$browse, [string]$browseKind) {
  $caption = New-Object System.Windows.Forms.Label; $caption.Text = $label; $caption.AutoSize = $true; $caption.Location = New-Object System.Drawing.Point(28, $y + 4); $form.Controls.Add($caption); [void]$script:advancedControls.Add($caption)
  $box = New-Object System.Windows.Forms.TextBox; $box.Text = $defaultValue; $box.Location = New-Object System.Drawing.Point(230, $y); $box.Size = New-Object System.Drawing.Size(470, 25); $box.Anchor = 'Top,Left,Right'; $form.Controls.Add($box); [void]$script:advancedControls.Add($box)
  if ($browse) { $button = New-Object System.Windows.Forms.Button; $button.Text = 'Gözat…'; $button.Location = New-Object System.Drawing.Point(710, $y - 1); $button.Size = New-Object System.Drawing.Size(75, 27); $button.Anchor = 'Top,Right'; $button.Tag = [PSCustomObject]@{ Box = $box; Kind = $browseKind }; $form.Controls.Add($button); [void]$script:advancedControls.Add($button); $button.Add_Click({ $ctx = $this.Tag; if ($ctx.Kind -eq 'folder') { $result = Select-Folder $ctx.Box.Text } else { $result = Select-File (Split-Path $ctx.Box.Text -Parent) 'CATIA ortam dosyaları|*.CATEnv;*.txt|Tüm dosyalar|*.*' }; if ($result) { $ctx.Box.Text = $result } }) }
  return $box
}

$folders = Find-CatEnvFolders
$defaultEnvFolder = if ($folders.Count -gt 0) { $folders[0] } else { Join-Path $env:APPDATA 'DassaultSystemes\CATEnv' }
$sourceBox = Add-Field (L 'Kaynak environment dosyası' 'Source environment file') 112 '' $true 'file'
$newNameBox = Add-Field (L 'Yeni environment adı' 'New environment name') 152 'CATIA.V5.LargeAssembly' $false ''
$userEnvBox = Add-Field (L 'Yeni environment klasörü' 'New environment folder') 192 (Join-Path $env:APPDATA 'DassaultSystemes\CATEnv') $true 'folder'
$settingsBox = Add-Field (L 'Yeni CATSettings klasörü' 'New CATSettings folder') 232 (Join-Path $env:APPDATA 'DassaultSystemes\CATSettings_LargeAssembly') $true 'folder'
$catstartBox = Add-Field (L 'CATSTART.exe (otomatik bulunur)' 'CATSTART.exe (found automatically)') 272 '' $true 'file'

$sourceList = New-Object System.Windows.Forms.ComboBox
$sourceList.Location = New-Object System.Drawing.Point(230, 312); $sourceList.Size = New-Object System.Drawing.Size(470, 25); $sourceList.DropDownStyle = 'DropDownList'; $sourceList.Anchor='Top,Left,Right'
$files = @(); foreach ($folder in $folders) { $files += Get-EnvironmentFiles $folder }
foreach ($item in $files) { [void]$sourceList.Items.Add($item.FullName) }
if ($sourceList.Items.Count -gt 0) { $sourceList.SelectedIndex = 0; $sourceBox.Text = $sourceList.SelectedItem; $catstartBox.Text = Find-CatStart $sourceBox.Text; Set-ApplicationIcon $catstartBox.Text }
$sourceLabel = New-Object System.Windows.Forms.Label; $sourceLabel.Text=(L 'Algılanan environment dosyaları' 'Detected environment files'); $sourceLabel.AutoSize=$true; $sourceLabel.Location=New-Object System.Drawing.Point(28,316); $form.Controls.Add($sourceLabel); $form.Controls.Add($sourceList)
$script:advancedControls.AddRange(@($sourceLabel, $sourceList))
$sourceList.Add_SelectedIndexChanged({ $sourceBox.Text = [string]$sourceList.SelectedItem; $detected = Find-CatStart $sourceBox.Text; if ($detected) { $catstartBox.Text = $detected; Set-ApplicationIcon $detected } })

$cacheLabel = New-Object System.Windows.Forms.Label; $cacheLabel.Text=(L 'Önerilen cache kapasitesi (MB)' 'Recommended cache capacity (MB)'); $cacheLabel.AutoSize=$true; $cacheLabel.Location=New-Object System.Drawing.Point(28, 357); $form.Controls.Add($cacheLabel)
$cacheBox = New-Object System.Windows.Forms.NumericUpDown; $cacheBox.Minimum=1024; $cacheBox.Maximum=1048576; $cacheBox.Increment=1024; $cacheBox.Value=10240; $cacheBox.Location=New-Object System.Drawing.Point(230,352); $cacheBox.Size=New-Object System.Drawing.Size(140,25); $form.Controls.Add($cacheBox)
$cacheHelp = New-Object System.Windows.Forms.Label; $cacheHelp.Text=(L 'Varsayılan: 10 GB. Bu değer plan dosyasına kaydedilir; CATIA Settings Management ekranında doğrulanır.' 'Default: 10 GB. This value is saved in the plan and verified in CATIA Settings Management.'); $cacheHelp.AutoSize=$true; $cacheHelp.Location=New-Object System.Drawing.Point(380,357); $form.Controls.Add($cacheHelp)
$script:advancedControls.AddRange(@($cacheLabel, $cacheBox, $cacheHelp))

$summary = New-Object System.Windows.Forms.TextBox
$summary.Multiline=$true; $summary.ReadOnly=$true; $summary.ScrollBars='Vertical'; $summary.Location=New-Object System.Drawing.Point(28,397); $summary.Size=New-Object System.Drawing.Size(757,145); $summary.Anchor='Top,Bottom,Left,Right'
$summary.Text = "Oluşturulacaklar:`r`n• Kaynak environment dosyasının yeni kopyası`r`n• Kopyada CATUserSettingPath = yeni CATSettings klasörü`r`n• CATIA_Settings_Plan.json doğrulama planı`r`n• Masaüstüne CATIA Large Assembly başlatma kısayolu"
$form.Controls.Add($summary)
$script:advancedControls.Add($summary)

$create = New-Object System.Windows.Forms.Button; $create.Text=(L 'Profili oluştur' 'Create profile'); $create.Size=New-Object System.Drawing.Size(185,42); $create.Location=New-Object System.Drawing.Point(675,352); $create.Anchor='Bottom,Right'; $create.FlatStyle='Flat'; $create.FlatAppearance.BorderSize=0; $create.BackColor=[System.Drawing.Color]::FromArgb(14,96,164); $create.ForeColor=[System.Drawing.Color]::White; $create.Font=New-Object System.Drawing.Font('Segoe UI Semibold',10); $form.Controls.Add($create)

foreach ($control in $script:advancedControls) { $control.Visible = $false }
$advancedToggle.Add_CheckedChanged({
  $showAdvanced = $advancedToggle.Checked
  foreach ($control in $script:advancedControls) { $control.Visible = $showAdvanced }
  foreach ($control in $script:basicControls) { $control.Visible = -not $showAdvanced }
  $quickStartupToggle.Visible = -not $showAdvanced
  if ($showAdvanced) {
    $form.Size = New-Object System.Drawing.Size(900, 700)
    $advancedToggle.Location = New-Object System.Drawing.Point(30, 625)
    $create.Location = New-Object System.Drawing.Point(675,620)
  } else {
    $form.Size = New-Object System.Drawing.Size(900, 460)
    $advancedToggle.Location = New-Object System.Drawing.Point(30, 318)
    $create.Location = New-Object System.Drawing.Point(675,352)
  }
})

$create.Add_Click({
  try {
    $source = Get-NormalizedPath $sourceBox.Text; $profile = $newNameBox.Text.Trim(); $envRoot = Get-NormalizedPath $userEnvBox.Text; $settings = Get-NormalizedPath $settingsBox.Text
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Kaynak environment dosyasını seçin.' }
    if ($profile -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$') { throw 'Yeni environment adı harf veya sayı ile başlamalı; en fazla 81 güvenli karakter içerebilir.' }
    if (-not $envRoot -or -not $settings) { throw 'Environment ve CATSettings yolları boş bırakılamaz.' }
    $catStart = Get-NormalizedPath $catstartBox.Text; if (-not $catStart) { $catStart = Find-CatStart $source }
    if (-not $catStart -or -not (Test-Path -LiteralPath $catStart -PathType Leaf)) { throw 'CATSTART.exe otomatik bulunamadı. Lütfen CATSTART.exe dosyasını seçin; masaüstü kısayolu olmadan profil oluşturulmaz.' }
    Assert-SafeProfileInputs $source $envRoot $settings $catStart
    New-Item -ItemType Directory -Path $envRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $settings -Force | Out-Null
    $extension = [IO.Path]::GetExtension($source); if (-not $extension) { $extension = '.CATEnv' }
    $destination = Join-Path $envRoot ($profile + $extension)
    $profileWasExisting = Test-Path -LiteralPath $destination
    if ($profileWasExisting) {
      $existingContent = [IO.File]::ReadAllText($destination)
      $existingMatch = [regex]::Match($existingContent, '(?im)^\s*CATUserSettingPath\s*=\s*(.+?)\s*$')
      if (-not $existingMatch.Success -or $existingMatch.Groups[1].Value.Trim().Trim('"') -ne $settings.Trim().Trim('"')) {
        throw "Bu isimde bir profil zaten var ancak farklı bir CATSettings yoluna bağlı. Güvenlik için üzerine yazılmadı. Yeni bir environment adı seçin."
      }
      $repaired = ConvertTo-UserEnvironment (Replace-CatUserSettingPath $existingContent $settings)
      $repaired = Set-QuickStartupVariables $repaired $quickStartupToggle.Checked
      [IO.File]::WriteAllText($destination, $repaired, [Text.UTF8Encoding]::new($false))
    } else {
      $content = [IO.File]::ReadAllText($source)
      $updated = ConvertTo-UserEnvironment (Replace-CatUserSettingPath $content $settings)
      $updated = Set-QuickStartupVariables $updated $quickStartupToggle.Checked
      [IO.File]::WriteAllText($destination, $updated, [Text.UTF8Encoding]::new($false))
    }
    $licenseStatus = Copy-LicenseSetting $source $settings
    $macroPath = Write-CatiaApplyMacro $settings ([int]$cacheBox.Value)
    $plan = [ordered]@{
      createdAt = (Get-Date).ToString('o'); profileName = $profile; sourceEnvironment = $source; environmentFile = $destination; catUserSettingPath = $settings; cacheSizeMB = [int]$cacheBox.Value; quickStartup = [bool]$quickStartupToggle.Checked; licenseSettings = $licenseStatus; applyMacro = $macroPath
      manualSettings = [ordered]@{
        cacheSystem = 'enabled'; displayPerformance = [ordered]@{'3DFixed'=0.10;'CurvesAccuracyRatio'=0.10;'2DFixed'=0.02;'LODStatic'=0.5;'LODWhileMoving'=13.5;'PixelCullingStatic'=2;'PixelCullingWhileMoving'=14;'TransparencyQuality'='Low'}; hybridDesign = 'disabled'
      }
    }
    $planPath = Join-Path $settings 'CATIA_Settings_Plan.json'; $plan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $planPath -Encoding UTF8
    $macroCommand = ('CNEXT -macro {0}' -f $macroPath)
    $desktop = [Environment]::GetFolderPath('Desktop'); $shortcutPath = Join-Path $desktop "CATIA Large Assembly - $profile.lnk"; $shell = New-Object -ComObject WScript.Shell; $shortcut = $shell.CreateShortcut($shortcutPath); $shortcut.TargetPath = $catStart; $shortcut.Arguments = ('-env "{0}" -direnv "{1}" -run "{2}"' -f $profile, $envRoot, $macroCommand); $shortcut.WorkingDirectory = Split-Path $catStart -Parent; $shortcut.IconLocation = "$catStart,0"; $shortcut.Description = 'CATIA V5 büyük montaj profili'; $shortcut.Save(); $shortcutMessage = "Masaüstü kısayolu oluşturuldu: $shortcutPath"
    $status = if ($profileWasExisting) { 'Mevcut profil doğrulandı; eksik kısayol tamamlandı.' } else { 'Yeni profil oluşturuldu.' }
    $startupStatus = if ($quickStartupToggle.Checked) { 'Hızlı açılış etkin: CATNoStartDocument=YES, CNEXTSPLASHSCREEN=NO, CNEXTBACKGROUND=NO' } else { 'Hızlı açılış kapalı: başlangıç ekranı ve dokümanı geri getirildi.' }
    $summary.Text = "Başarılı.`r`n`r`n$status`r`n$startupStatus`r`n$licenseStatus`r`nPerformans ayar makrosu: $macroPath`r`nEnvironment: $destination`r`nCATSettings: $settings`r`nPlan dosyası: $planPath`r`n$shortcutMessage`r`n`r`nSonraki adım: Yeni masaüstü kısayoluyla CATIA'yı açın."
    [System.Windows.Forms.MessageBox]::Show("$status`r`n`r
$shortcutMessage", 'CATIA Large Assembly Profile', 'OK', 'Information') | Out-Null
  } catch { Show-Error $_.Exception.Message }
})

[void]$form.ShowDialog()
