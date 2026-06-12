#Requires -Version 5.1
# 默认：先 hvigor 编译 entry，再安装 entry-default-signed.hap 并启动 EntryAbility。
# 仅需重装已有 HAP、跳过编译时加 -SkipBuild（需已存在 signed hap）。
# 编译需要 JDK（JAVA_HOME 或 PATH）与 DevEco / command-line-tools 中的 Node、hvigor、SDK。
#
# HarmonyOS command-line-tools (recommended):
#   $env:HOS_COMMAND_LINE_TOOLS = "<path>\command-line-tools"   # folder containing sdk\, hvigor\, tool\node\
#   若未设置环境变量，脚本会检测 D:\Users\picha\Downloads\commandline-tools-windows-x64-6.0.2.642\command-line-tools 是否存在并自动使用。
#   $env:JAVA_HOME = "<path>\jdk-17..."                          # JDK 17+ for signing/packaging
#   .\scripts\deploy-phone.ps1
#
# Wireless (same LAN; phone: Settings -> Developer -> Wireless debugging, note port):
#   .\scripts\deploy-phone.ps1 -TconnHost 192.168.0.18
#   .\scripts\deploy-phone.ps1 -TconnHost 192.168.0.18 -TconnPort 8710
#
# DevEco embedded SDK (legacy):
#   $env:DEVECO_SDK_HOME = "<DevEco>\sdk"
#   $env:OHOS_BASE_SDK_HOME = "<DevEco>\sdk\default\openharmony"   # optional; script sets if omitted
param(
  # 为 true 时跳过 assembleHap，直接安装当前 outputs 下已有 signed hap（用于快速重装同一次构建产物）
  [switch]$SkipBuild,
  # 兼容旧参数：以前需 -Build 才会编译；现在默认即编译，传入 -Build 与不传效果相同
  [switch]$Build,
  # 真机 IPv4；会先执行 hdc tconn（鸿蒙无线调试默认端口多为 8710，以手机显示为准）
  [string]$TconnHost = '',
  [int]$TconnPort = 8710
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent

# 未设置 HOS_COMMAND_LINE_TOOLS 时，若本机已解压官方 command-line-tools，则自动指向该根目录（其下应有 sdk、hvigor、tool\node）。
# 你仍可在 PowerShell 中覆盖： $env:HOS_COMMAND_LINE_TOOLS = "...\command-line-tools"
$DeployPhoneDefaultCommandLineTools = 'D:\Users\picha\Downloads\commandline-tools-windows-x64-6.0.2.642\command-line-tools'
if (-not $env:HOS_COMMAND_LINE_TOOLS) {
  $markerHvigor = Join-Path $DeployPhoneDefaultCommandLineTools 'hvigor\bin\hvigorw.js'
  $markerSdk = Join-Path $DeployPhoneDefaultCommandLineTools 'sdk'
  if ((Test-Path $markerHvigor) -and (Test-Path $markerSdk)) {
    $env:HOS_COMMAND_LINE_TOOLS = $DeployPhoneDefaultCommandLineTools
  }
}

$DevEcoSdkDefault = "D:\Program Files\Huawei\DevEco Studio\sdk"
$NodeDevEco = "D:\Program Files\Huawei\DevEco Studio\tools\node\node.exe"
$HvigorDevEco = "D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js"
$HdcDevEco = "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"

$CltRoot = ''
if ($env:HOS_COMMAND_LINE_TOOLS) {
  $CltRoot = $env:HOS_COMMAND_LINE_TOOLS.TrimEnd('\', '/')
}

# SDK root for hvigor: command-line-tools uses ...\sdk ; DevEco Hvigor expects ...\sdk
$SdkHome = ''
if ($env:DEVECO_SDK_HOME) {
  $SdkHome = $env:DEVECO_SDK_HOME.TrimEnd('\', '/')
} elseif ($CltRoot.Length -gt 0) {
  $SdkHome = Join-Path $CltRoot 'sdk'
} else {
  $SdkHome = $DevEcoSdkDefault
}

$HdcExe = if ($env:HDC_EXE) { $env:HDC_EXE }
elseif ($CltRoot.Length -gt 0) { Join-Path $CltRoot 'sdk\default\openharmony\toolchains\hdc.exe' }
else { $HdcDevEco }

$NodeExe = if ($env:DEVECO_NODE) { $env:DEVECO_NODE }
elseif ($CltRoot.Length -gt 0) { Join-Path $CltRoot 'tool\node\node.exe' }
else { $NodeDevEco }

$HvigorJs = if ($env:HVIGORW_JS) { $env:HVIGORW_JS }
elseif ($CltRoot.Length -gt 0) { Join-Path $CltRoot 'hvigor\bin\hvigorw.js' }
else { $HvigorDevEco }

$SignedHap = Join-Path $RepoRoot "entry\build\default\outputs\default\entry-default-signed.hap"
$BundleName = "com.jonas.fmphoto"
$AbilityName = "EntryAbility"

function Test-SdkMarkerOk {
  param([string]$SdkRoot)
  $p1 = Join-Path $SdkRoot 'default\openharmony\ets\oh-uni-package.json'
  $p2 = Join-Path $SdkRoot 'openharmony\ets\oh-uni-package.json'
  return ((Test-Path $p1) -or (Test-Path $p2))
}

function Resolve-OhosBaseSdk {
  param([string]$SdkRoot)
  if (Test-Path (Join-Path $SdkRoot 'default\openharmony\ets\oh-uni-package.json')) {
    return (Join-Path $SdkRoot 'default\openharmony')
  }
  return (Join-Path $SdkRoot 'openharmony')
}

function Get-HapBundleName {
  param([string]$HapPath)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::OpenRead($HapPath)
  try {
    $entry = $zip.GetEntry('pack.info')
    if ($null -eq $entry) {
      return ''
    }
    $reader = [System.IO.StreamReader]::new($entry.Open())
    try {
      $packInfo = $reader.ReadToEnd() | ConvertFrom-Json
      return [string]$packInfo.summary.app.bundleName
    } finally {
      $reader.Dispose()
    }
  } finally {
    $zip.Dispose()
  }
}

function Ensure-JavaOnPath {
  if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
    $jb = Join-Path $env:JAVA_HOME 'bin'
    $p = $env:PATH
    if ($null -eq $p -or $p -eq '') {
      $env:PATH = $jb
    } elseif (-not $p.StartsWith($jb)) {
      $env:PATH = "$jb;$p"
    }
    return
  }
  # winget: EclipseAdoptium.Temurin.17.JDK -> C:\Program Files\Eclipse Adoptium\jdk-*-hotspot
  $adoptiumRoot = 'C:\Program Files\Eclipse Adoptium'
  if (Test-Path $adoptiumRoot) {
    $jdkDirs = @(Get-ChildItem -Path $adoptiumRoot -Directory -Filter 'jdk-*' -ErrorAction SilentlyContinue |
      Sort-Object { $_.Name } -Descending)
    foreach ($dir in $jdkDirs) {
      $javaExe = Join-Path $dir.FullName 'bin\java.exe'
      if (Test-Path $javaExe) {
        $env:JAVA_HOME = $dir.FullName
        $jb = Join-Path $env:JAVA_HOME 'bin'
        $p = $env:PATH
        if ($null -eq $p -or $p -eq '') {
          $env:PATH = $jb
        } elseif (-not $p.StartsWith($jb)) {
          $env:PATH = "$jb;$p"
        }
        return
      }
    }
  }
  $javaCmd = Get-Command java -ErrorAction SilentlyContinue
  if ($javaCmd) {
    return
  }
  throw "JDK not found (PackageHap needs java). Install JDK 17+ (e.g. winget install EclipseAdoptium.Temurin.17.JDK) or set JAVA_HOME."
}

if (-not (Test-Path $HdcExe)) {
  throw "hdc not found: $HdcExe. Set HDC_EXE or HOS_COMMAND_LINE_TOOLS."
}

# Default: run assembleHap first; use -SkipBuild to install existing signed HAP only.
if (-not $SkipBuild) {
  if (-not (Test-SdkMarkerOk -SdkRoot $SdkHome)) {
    throw "SDK incomplete: no openharmony ets at ( $SdkHome\default\... or $SdkHome\openharmony\... ). Set HOS_COMMAND_LINE_TOOLS to command-line-tools folder or DEVECO_SDK_HOME to sdk root."
  }
  if (-not (Test-Path $NodeExe) -or -not (Test-Path $HvigorJs)) {
    throw "Node or hvigorw.js not found. Set HOS_COMMAND_LINE_TOOLS, or DEVECO_NODE / HVIGORW_JS."
  }
  Ensure-JavaOnPath

  $env:DEVECO_SDK_HOME = $SdkHome
  $env:OHOS_BASE_SDK_HOME = Resolve-OhosBaseSdk -SdkRoot $SdkHome
  Write-Host ">> DEVECO_SDK_HOME=$($env:DEVECO_SDK_HOME)"
  Write-Host ">> OHOS_BASE_SDK_HOME=$($env:OHOS_BASE_SDK_HOME)"
  Write-Host ">> JAVA_HOME=$($env:JAVA_HOME)"
  Write-Host ">> Node=$NodeExe"
  Write-Host ">> hvigor=$HvigorJs"

  # Stop old hvigor daemon (may lack JAVA_HOME and break PackageHap).
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $NodeExe $HvigorJs "--stop-daemon" 2>$null | Out-Null
  } finally {
    $ErrorActionPreference = $prevEap
  }

  Push-Location $RepoRoot
  try {
    & $NodeExe $HvigorJs "--mode" "module" "-p" "module=entry@default" "-p" "product=default" "assembleHap"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  } finally {
    Pop-Location
  }
}

if (-not (Test-Path $SignedHap)) {
  throw "Signed HAP not found: $SignedHap. Run without -SkipBuild to compile first, or build in DevEco."
}

$ActualBundleName = Get-HapBundleName -HapPath $SignedHap
if ($ActualBundleName -ne $BundleName) {
  throw "Signed HAP bundleName mismatch: expected $BundleName, got $ActualBundleName. Rebuild with matching SigningConfigs before install or release."
}

if ($TconnHost -and $TconnHost.Trim().Length -gt 0) {
  $th = $TconnHost.Trim()
  $addr = if ($th -match ':\d+$') { $th } else { "${th}:${TconnPort}" }
  Write-Host ">> hdc tconn $addr"
  & $HdcExe tconn $addr
  if ($LASTEXITCODE -ne 0) {
    throw "hdc tconn failed (exit $LASTEXITCODE). On device enable wireless debugging and confirm IP:port."
  }
}

Write-Host ">> hdc list targets"
& $HdcExe list targets

Write-Host ">> hdc app install -r $SignedHap"
& $HdcExe app install -r $SignedHap
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ">> aa start -b $BundleName -a $AbilityName"
& $HdcExe shell aa start -b $BundleName -a $AbilityName
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Done. Logs: `"$HdcExe`" hilog"
