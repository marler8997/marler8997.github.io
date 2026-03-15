$ErrorActionPreference = "Stop"

function Run {
    param([string]$Cwd, [string[]]$Argv)
    if ($Cwd) {
        Write-Host "run: cd `"$Cwd`" && $Argv"
        Push-Location $Cwd
        try { & $Argv[0] $Argv[1..($Argv.Length-1)] }
        finally { Pop-Location }
    } else {
        Write-Host "run: $Argv"
        & $Argv[0] $Argv[1..($Argv.Length-1)]
    }
    if ($LASTEXITCODE -ne 0) { throw "$($Argv[0]) exited with code $LASTEXITCODE" }
}

function Read-Sha {
    param([string]$Path)
    $sha = (Get-Content $Path -Raw).Substring(0, 40)
    if ($sha -notmatch '^[0-9a-f]{40}$') { throw "invalid git SHA `"$sha`" from '$Path'" }
    return $sha
}

function Fetch-DotMaster {
    param([string]$Src)
    if (-not (Test-Path $Src)) {
        Run $null @("git", "clone", "https://github.com/marler8997/dot", $Src, "-b", "master")
    }
    Run $null @("git", "-C", $Src, "fetch", "origin", "master")
    return Read-Sha (Join-Path $Src ".git/FETCH_HEAD")
}

function Test-Writable {
    param([string]$Dir)
    if (-not (Test-Path $Dir)) { return $false }
    $testFile = Join-Path $Dir "dof.exe.test"
    try {
        [IO.File]::WriteAllText($testFile, "")
        Remove-Item $testFile
        return $true
    } catch {
        return $false
    }
}

function Add-ToUserPath {
    param([string]$Dir)
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -notlike "*$Dir*") {
        Write-Host "dof: adding '$Dir' to user PATH"
        [Environment]::SetEnvironmentVariable("PATH", "$userPath;$Dir", "User")
        Write-Host "dof: restart your shell for PATH changes to take effect"
    }
}

function Prompt-CustomDir {
    $custom = Read-Host "Enter a directory to install dof into"
    if (-not (Test-Path $custom)) {
        $confirm = Read-Host "'$custom' does not exist, create it? [y/N]"
        if ($confirm -notmatch '^[Yy]$') { return $null }
        New-Item -ItemType Directory -Force $custom | Out-Null
    }
    if (-not (Test-Writable $custom)) {
        Write-Host "error: '$custom' is not writable"
        return $null
    }
    return $custom
}

function Select-InstallDir {
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $systemPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $pathDirs = ($userPath + ";" + $systemPath) -split ";" | Where-Object { $_ -ne "" } | Select-Object -Unique

    $writableDirs = @()
    foreach ($dir in $pathDirs) {
        if (Test-Writable $dir) {
            $writableDirs += $dir
        } else {
            Write-Host "  (skipping '$dir' - not writable)"
        }
    }

    if ($writableDirs.Length -eq 0) {
        Write-Host "note: no writable directories found in PATH"
        while ($true) {
            $dir = Prompt-CustomDir
            if ($dir) {
                Add-ToUserPath $dir
                return $dir
            }
            Write-Host "please try again"
        }
    }

    Write-Host ""
    Write-Host "Where would you like to install dof?"
    Write-Host ""
    $i = 1
    foreach ($dir in $writableDirs) {
        Write-Host "  $i) $dir"
        $i++
    }
    Write-Host "  C) Enter a custom directory (will be added to your PATH)"
    Write-Host ""

    while ($true) {
        $choice = Read-Host "Choice"
        if ($choice -match '^\d+$') {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $writableDirs.Length) {
                return $writableDirs[$idx]
            }
            Write-Host "invalid choice, please try again"
        } elseif ($choice -match '^[Cc]$') {
            $dir = Prompt-CustomDir
            if ($dir) {
                Add-ToUserPath $dir
                return $dir
            }
            Write-Host "please try again"
        } else {
            Write-Host "invalid choice, please try again"
        }
    }
}

$existingDot = Get-Command "dof.exe" -ErrorAction SilentlyContinue
if ($existingDot) {
    Write-Host "dof: already installed at '$($existingDot.Source)'"
    exit 0
}

foreach ($tool in @("git", "zig")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "error: dof requires '$tool' but it was NOT found in PATH"
        exit 1
    }
}

$appData = Join-Path $env:LOCALAPPDATA "dof"
Write-Host "appdata '$appData'"
New-Item -ItemType Directory -Force $appData | Out-Null

$src = Join-Path $appData "src"

if ($installPath) {
    if (-not (Test-Path $installPath)) {
        Write-Host "error: '$installPath' does not exist"
        exit 1
    }
    $installDir = (Resolve-Path $installPath).Path
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $systemPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $allPaths = ($userPath + ";" + $systemPath) -split ";" | Where-Object { $_ -ne "" }
    if ($installDir -notin $allPaths) {
        Write-Host "error: '$installDir' is not in PATH"
        exit 1
    }
} else {
    $installDir = (Resolve-Path (Select-InstallDir)).Path
}
Write-Host "dof: installing to '$installDir'"

$master = Fetch-DotMaster $src
Run $null @("git", "-C", $src, "reset", "--hard", $master)
Run $src @("zig", "build", "install", "-Dsha=$master", "--prefix", $installDir)

Write-Host "dof has been installed and added to PATH"
