$ErrorActionPreference = "Stop"

$nodeJsInstalled = Get-Command "npx" -ErrorAction "SilentlyContinue"
if(-not $nodeJsInstalled) {
    Write-Error @"
You need nodejs installed along with its 'npx' command.
You can manage nodejs installs on Windows with 'winget install nvm-windows'
See https://learn.microsoft.com/en-us/windows/dev-environment/javascript/nodejs-on-windows#install-nvm-windows-nodejs-and-npm for more details.
"@
}

if(-not (Test-Path "$PSScriptRoot/docusaurus")) {
    $command = "npx create-docusaurus@latest docusaurus classic"
    Invoke-Expression $command
    if($LASTEXITCODE -ne 0) {
        Write-Error "'$command' failed. Found and exit code of '$LASTEXITCODE', expected '0'"
    }
}

Import-Module "$PSScriptRoot/PowerShellAI.psd1" -Force

$suffix = @'
> **NOTE**  
> This documentation is generated from the PowerShell comment based help for the functions in the module.  
> To update the documentation please open a PR to update the comments on this function.  
'@

New-DocusaurusHelp -Module "PowerShellAI" -NoPlaceHolderExamples -AppendMarkdown $suffix

Push-Location
try {
    Set-Location "$PSScriptRoot/docusaurus"
    $command = "npx yarn start"
    Invoke-Expression $command
    if($LASTEXITCODE -ne 0) {
        Write-Error "'$command' failed. Found and exit code of '$LASTEXITCODE', expected '0'"
    }

} finally {
    Pop-Location
}