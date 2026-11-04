# Openness installer for Windows (PowerShell 5.1 or later).
#
#   irm https://raw.githubusercontent.com/s4e-io/openness/main/install.ps1 | iex
#
# Installs the latest releases of:
#   openness-collector.exe (collector, from github.com/s4e-io/openness-collector)
#   openness-resolver.exe  (resolver,  from github.com/s4e-io/openness-resolver)
#
# Every download is verified against the release's SHA256SUMS file before it
# is installed. The install directory is added to the user PATH (no admin
# rights needed).
#
# Environment variables:
#   OPENNESS_INSTALL_DIR        install directory (default: $env:LOCALAPPDATA\Openness)
#   GITHUB_TOKEN or GH_TOKEN    GitHub token, sent as a Bearer token. Needed while
#                               a release needs authentication.
#   OPENNESS_COMPONENTS         space separated subset of "collector resolver" (default: both)
#   OPENNESS_COLLECTOR_VERSION  release tag to install instead of the latest (e.g. v0.4.9)
#   OPENNESS_RESOLVER_VERSION   release tag to install instead of the latest (e.g. v0.1.0)
#   OPENNESS_DRY_RUN=1          resolve versions and assets, print the plan, install nothing
#   OPENNESS_NO_MODIFY_PATH=1   do not change the user PATH
#
# Testing overrides (not needed for normal use):
#   OPENNESS_ARCH               pretend to be another architecture (amd64|arm64)
#   OPENNESS_LOCAL_RELEASES     read releases from a local directory instead of GitHub.
#                               Layout: <dir>\<repo>\LATEST (contains the tag, e.g. v0.4.9)
#                                       <dir>\<repo>\<tag>\<asset files and SHA256SUMS>

& {
    Set-StrictMode -Version 2.0
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    $Owner = 's4e-io'
    $Api = 'https://api.github.com'

    function Get-EnvOr([string]$Name, [string]$Default) {
        $v = [Environment]::GetEnvironmentVariable($Name)
        if ([string]::IsNullOrEmpty($v)) { return $Default }
        return $v
    }

    $LocalReleases = Get-EnvOr 'OPENNESS_LOCAL_RELEASES' ''
    $DryRun = (Get-EnvOr 'OPENNESS_DRY_RUN' '0') -eq '1'
    $NoModifyPath = (Get-EnvOr 'OPENNESS_NO_MODIFY_PATH' '0') -eq '1'
    $Components = (Get-EnvOr 'OPENNESS_COMPONENTS' 'collector resolver') -split '\s+' | Where-Object { $_ }
    $Token = Get-EnvOr 'GITHUB_TOKEN' (Get-EnvOr 'GH_TOKEN' '')

    $DefaultDir = ''
    if ($env:LOCALAPPDATA) { $DefaultDir = Join-Path $env:LOCALAPPDATA 'Openness' }
    $InstallDir = Get-EnvOr 'OPENNESS_INSTALL_DIR' $DefaultDir
    if (-not $InstallDir) { throw 'LOCALAPPDATA is not set. Set OPENNESS_INSTALL_DIR to the install directory.' }

    # Windows PowerShell 5.1 does not enable TLS 1.2 by default on older systems.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }

    function Get-Arch {
        $o = Get-EnvOr 'OPENNESS_ARCH' ''
        if ($o) { return $o }
        # A 32-bit PowerShell on 64-bit Windows reports x86 here, the real
        # architecture is in PROCESSOR_ARCHITEW6432.
        $a = $env:PROCESSOR_ARCHITEW6432
        if (-not $a) { $a = $env:PROCESSOR_ARCHITECTURE }
        switch ($a) {
            'AMD64' { return 'amd64' }
            'ARM64' { return 'arm64' }
            default { throw "Unsupported CPU architecture: $a. Supported: amd64 (and arm64 through x64 emulation)." }
        }
    }

    function Get-Headers([string]$Accept) {
        $h = @{ 'Accept' = $Accept; 'X-GitHub-Api-Version' = '2022-11-28' }
        if ($Token) { $h['Authorization'] = "Bearer $Token" }
        return $h
    }

    function Get-AccessHint {
        if (-not $Token) {
            return "The release could not be fetched without authentication. Set GH_TOKEN (or GITHUB_TOKEN) to a token of a GitHub account that has access, for example: `$env:GH_TOKEN = (gh auth token)"
        }
        return "Check that the token is valid and that its account has access to github.com/$Owner/<repo>."
    }

    function Get-Release([string]$Repo, [string]$Want) {
        if ($LocalReleases) {
            $tag = $Want
            if (-not $tag) {
                $latest = Join-Path (Join-Path $LocalReleases $Repo) 'LATEST'
                if (-not (Test-Path $latest)) { throw "local release dir has no $Repo\LATEST file" }
                $tag = (Get-Content -Raw $latest).Trim()
            }
            $dir = Join-Path (Join-Path $LocalReleases $Repo) $tag
            if (-not (Test-Path $dir)) { throw "local release dir has no $Repo\$tag" }
            $assets = @(Get-ChildItem -File $dir | ForEach-Object { [pscustomobject]@{ name = $_.Name; url = $_.FullName } })
            return [pscustomobject]@{ tag_name = $tag; assets = $assets }
        }
        if ($Want) { $url = "$Api/repos/$Owner/$Repo/releases/tags/$Want" } else { $url = "$Api/repos/$Owner/$Repo/releases/latest" }
        try {
            return Invoke-RestMethod -UseBasicParsing -UserAgent 'openness-installer' -Uri $url -Headers (Get-Headers 'application/vnd.github+json')
        } catch {
            $err = $_
            $code = 0
            try { $code = [int]$err.Exception.Response.StatusCode } catch { $code = 0 }
            $what = "the latest release of $Owner/$Repo"
            if ($Want) { $what = "release $Want of $Owner/$Repo" }
            if ($code -eq 404) { throw "Could not find $what (HTTP 404). $(Get-AccessHint)" }
            if ($code -eq 401) { throw "GitHub rejected the token (HTTP 401) for $Repo. $(Get-AccessHint)" }
            if ($code -eq 403 -or $code -eq 429) { throw "GitHub refused the request for $Repo (HTTP $code, possibly the anonymous rate limit). $(Get-AccessHint)" }
            throw "Could not fetch $what. $($err.Exception.Message)"
        }
    }

    function Save-Asset($Repo, $Release, $Asset, [string]$OutFile) {
        if ($LocalReleases) {
            Copy-Item -LiteralPath $Asset.url -Destination $OutFile -Force
            return
        }
        if ($Token) {
            # The API asset URL works for public and private repositories. It redirects to
            # a signed CDN URL; PowerShell does not forward the Authorization
            # header across that redirect.
            $url = $Asset.url
        } else {
            $url = $Asset.browser_download_url
        }
        Invoke-WebRequest -UseBasicParsing -UserAgent 'openness-installer' -Uri $url -Headers (Get-Headers 'application/octet-stream') -OutFile $OutFile
    }

    function Get-ExpectedHash([string]$SumsFile, [string]$Name) {
        foreach ($line in Get-Content $SumsFile) {
            $parts = $line.Trim() -split '\s+', 2
            if ($parts.Count -eq 2 -and $parts[1].TrimStart('*') -eq $Name) { return $parts[0].ToLowerInvariant() }
        }
        return $null
    }

    $Arch = Get-Arch
    Write-Host 'Openness installer (beta)'
    Write-Host "Platform: windows/$Arch"
    Write-Host "Install directory: $InstallDir"
    if ($LocalReleases) { Write-Host "Release source: local directory $LocalReleases" }
    elseif ($Token) { Write-Host 'Release source: GitHub (authenticated)' }
    else { Write-Host 'Release source: GitHub (anonymous)' }
    Write-Host ''

    $Tmp = Join-Path ([IO.Path]::GetTempPath()) ("openness-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $Tmp | Out-Null
    if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null }

    $installed = @()
    $failed = @()
    try {
        foreach ($c in $Components) {
            switch ($c) {
                'collector' { $repo = 'openness-collector'; $prefix = 'openness-collector'; $bin = 'openness-collector.exe'; $want = Get-EnvOr 'OPENNESS_COLLECTOR_VERSION' '' }
                'resolver' { $repo = 'openness-resolver'; $prefix = 'openness-resolver'; $bin = 'openness-resolver.exe'; $want = Get-EnvOr 'OPENNESS_RESOLVER_VERSION' '' }
                default { throw "Unknown component: $c (use collector and/or resolver)" }
            }

            $rel = Get-Release $repo $want
            $tag = [string]$rel.tag_name
            $ver = $tag.TrimStart('v')
            $names = @($rel.assets | ForEach-Object { [string]$_.name })

            $assetName = "${prefix}_${ver}_windows_${Arch}.exe"
            # Collector releases before the rename publish openness_<version>_windows_<arch>.exe.
            if ($c -eq 'collector' -and ($names -notcontains $assetName) -and ($names -contains "openness_${ver}_windows_${Arch}.exe")) {
                $prefix = 'openness'
                $assetName = "openness_${ver}_windows_${Arch}.exe"
            }
            if (($names -notcontains $assetName) -and $Arch -eq 'arm64') {
                # Windows on ARM runs x64 binaries through emulation.
                $fallback = "${prefix}_${ver}_windows_amd64.exe"
                if ($names -contains $fallback) {
                    Write-Host "No arm64 build of $repo $tag, using the amd64 build (runs under x64 emulation)."
                    $assetName = $fallback
                }
            }
            if ($names -notcontains $assetName) {
                $avail = @($names | Where-Object { $_ -like "${prefix}_${ver}_*" } | ForEach-Object { ($_ -replace "^${prefix}_${ver}_", '') -replace '\.exe$', '' }) -join ' '
                if (-not $avail) { $avail = 'none' }
                Write-Warning "$repo $tag has no Windows build (expected asset $assetName). Platforms in this release: $avail"
                if ($c -eq 'resolver') { Write-Warning 'Windows builds of the resolver ship with the next resolver release. Until then run the resolver on Linux, or build it from source with Go.' }
                else { Write-Warning 'A Windows build of the collector ships with the next collector release.' }
                $failed += $c
                continue
            }

            if ($DryRun) {
                Write-Host "[dry-run] ${c}: would install $repo $tag asset $assetName as $(Join-Path $InstallDir $bin)"
                $installed += $bin
                continue
            }

            if ($names -notcontains 'SHA256SUMS') { throw "$repo $tag has no SHA256SUMS file, refusing to install unverified binaries" }

            Write-Host "Downloading $assetName ($repo $tag)"
            $sums = Join-Path $Tmp "$repo.SHA256SUMS"
            $file = Join-Path $Tmp $assetName
            Save-Asset $repo $rel ($rel.assets | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1) $sums
            Save-Asset $repo $rel ($rel.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1) $file

            $expected = Get-ExpectedHash $sums $assetName
            if (-not $expected) { throw "$assetName is not listed in SHA256SUMS, refusing to install it" }
            $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLowerInvariant()
            if ($expected -ne $actual) { throw "Checksum mismatch for $assetName (expected $expected, got $actual)" }
            Write-Host 'Checksum OK'

            $dest = Join-Path $InstallDir $bin
            $staging = "$dest.new"
            Copy-Item -LiteralPath $file -Destination $staging -Force
            try {
                Move-Item -LiteralPath $staging -Destination $dest -Force
            } catch {
                Remove-Item -LiteralPath $staging -Force -ErrorAction SilentlyContinue
                throw "Could not replace $dest. Close any running $bin and retry. $($_.Exception.Message)"
            }
            $installed += $bin
        }
    } finally {
        Remove-Item -Recurse -Force -LiteralPath $Tmp -ErrorAction SilentlyContinue
    }

    if ($installed.Count -eq 0) {
        throw "Nothing was installed (no Windows build for: $($failed -join ', '))."
    }

    Write-Host ''
    if ($DryRun) {
        Write-Host 'Dry run finished, nothing was installed.'
    } else {
        Write-Host 'Installed:'
        foreach ($b in $installed) {
            $p = Join-Path $InstallDir $b
            $v = ''
            try { $v = (& $p version 2>&1 | Select-Object -First 1) } catch { $v = "(could not run '$b version')" }
            Write-Host "  $p  $v"
        }

        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (-not $userPath) { $userPath = '' }
        $onPath = @($userPath -split ';' | Where-Object { $_.TrimEnd('\') -ieq $InstallDir.TrimEnd('\') }).Count -gt 0
        if (-not $onPath) {
            if ($NoModifyPath) {
                Write-Host ''
                Write-Host "$InstallDir is not on your PATH (OPENNESS_NO_MODIFY_PATH=1, left unchanged)."
            } else {
                $newPath = $InstallDir
                if ($userPath) { $newPath = $userPath.TrimEnd(';') + ';' + $InstallDir }
                [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
                Write-Host ''
                Write-Host "Added $InstallDir to your user PATH. Open a new terminal to use it everywhere."
            }
        }
        if (-not (@($env:Path -split ';') -contains $InstallDir)) { $env:Path = "$env:Path;$InstallDir" }
    }

    Write-Host ''
    Write-Host 'Next steps:'
    Write-Host '  1. Collect evidence on the host to assess (an Administrator terminal gives fuller evidence):'
    Write-Host '       openness-collector collect --output .\host.openness'
    Write-Host '  2. Download only the advisory feeds that evidence needs:'
    Write-Host '       openness-resolver feed sync --for .\host.openness --data-dir .\openness-data'
    Write-Host '  3. Resolve findings:'
    Write-Host '       openness-resolver resolve --input .\host.openness --output findings.json --data-dir .\openness-data'
    Write-Host ''
    Write-Host 'Openness is in beta and licensed under the Apache License 2.0. Developed and maintained by S4E: https://s4e.io'

    if ($failed.Count -gt 0) {
        Write-Warning "Not installed: $($failed -join ', ') (see the warnings above)."
    }
}
