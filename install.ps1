# Install the coding standards markdown files from GitHub into ~/.claude/

$ErrorActionPreference = "Stop"

$RawBaseUrl = "https://raw.githubusercontent.com/Androsh7/CLAUDE.md/main"
$DestinationDirectory = Join-Path $HOME ".claude"
$StandardFiles = @("CLAUDE.md", "GIT.md", "DOCKER.md", "PYTHON.md", "REACT.md")

New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null

foreach ($standardFile in $StandardFiles) {
    $destinationPath = Join-Path $DestinationDirectory $standardFile

    if (Test-Path $destinationPath) {
        $answer = Read-Host "Overwrite ${destinationPath}? [y/N]"
        if ($answer -ne "y") {
            Write-Host "Skipped   $standardFile"
            continue
        }
    }

    $temporaryPath = [System.IO.Path]::GetTempFileName()
    Invoke-WebRequest -Uri "$RawBaseUrl/$standardFile" -OutFile $temporaryPath -UseBasicParsing
    Move-Item -Path $temporaryPath -Destination $destinationPath -Force
    Write-Host "Installed $standardFile"
}
