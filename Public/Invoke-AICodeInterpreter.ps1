#requires -Module PwshSpectreConsole

$script:WorkingStoragePath = $null
$script:PreviousRuns = $null
$global:WarningPreference = "SilentlyContinue"

function Initialize-AICodeInterpreter {
    param (
        [string] $Start
    )

    # Quick way of creating a directory to work in which will be reused if the exact same starting prompt is used a second time
    $sha256 = [System.Security.Cryptography.SHA256Managed]::new()
    $paramBytes = [System.Text.Encoding]::Default.GetBytes($Start)
    $hashBytes = $sha256.ComputeHash($paramBytes)
    $hashKey = [Convert]::ToBase64String($hashBytes)
    $pattern = '[' + ([System.IO.Path]::GetInvalidFileNameChars() -join '').Replace('\','\\') + ']+'
    $workingDir = [regex]::Replace($hashKey, $pattern, "-")

    if ($PSVersionTable.Platform -eq 'Unix') {
        $Script:WorkingStoragePath = Join-Path $env:HOME '~/PowerShellAI/ChatGPT/CodeInterpreter'
    }
    else {
        $Script:WorkingStoragePath = Join-Path $env:APPDATA 'PowerShellAI/ChatGPT/CodeInterpreter'
    }

    $path = "$script:WorkingStoragePath\$workingDir"
    New-Item -Path "$path" -ItemType "Directory" -Force | Out-Null

    Write-Host "Working in directory: $path`n"

    return $path
}

function Export-AITestDefinition {
    param (
        [string] $Path,
        [string] $TestDefinition
    )

    $pathName = "$Path\function.Tests.ps1"
    Set-Content -Path $pathName -Value $TestDefinition

    return $pathName
}

function Export-AIFunctionDefinition {
    param (
        [string] $Path,
        [string] $FunctionDefinition
    )

    $pathName = "$Path\function.psm1"
    Set-Content -Path $pathName -Value $FunctionDefinition

    return $pathName
}

function Invoke-AICodeInterpreter {
    [CmdletBinding()]
    param (
        [string] $FunctionName = "Get-MagicNumber",
        [string] $ModuleName = "TestingModule",
        [string] $Start = "Write pester tests for a function $FunctionName from the module $ModuleName that takes an integer as input and returns another integer. Given an number of 2 I expect an output of 99. Given an number of 43 I expect an output of 103.",
        [string] $Build = "Now that the tests are written, write powershell function code that will pass the tests using logic to deduce what the best quality code to solve the problem will be. If you need to do any math write the powershell to do the math and I will execute it for you."
    )

    Set-ChatSessionOption -model "gpt-4" -max_tokens 1024
    New-Chat -Content @"
You are an expert powershell with the following skills:
 - You develop and you test code
 - You are capable of evaluating math when it's required to meet function requirements
 - When given a list of requirements for a function you will write pester tests without mocks
 - You always write tests before attempting to solve the requirements.
"@ | Out-Null

    $path = Initialize-AICodeInterpreter -Start $Start

    Push-Location "."
    try {
        Set-Location $path

        $testFile = $null
        $functionFile = $null

        $response = (Get-GPT4Completion $Start).Trim()
        $test = $response | ConvertTo-AifbTest
        $text = $response -replace '(?s)```.+?```', '' -replace ':', '.' -replace '[\n]{2}', "`n"

        Write-SpectrePanel -Title "[white] :robot: PowerShellAI [/]" -Color "IndianRed1_1" -Data "$([Spectre.Console.Markup]::Escape($text))" -Expand
        
        if($test) {
            Write-Host ""
            Write-Codeblock $test -SyntaxHighlight -ShowLineNumbers
            $testFile = Export-AITestDefinition -Path $path -TestDefinition $test
            Write-Host ""
        } else {
            $global:LASTAIRESPONSE = $response
            throw "Fuck"
        }

        $response = (Get-GPT4Completion $Build).Trim()
        $function = $response | ConvertTo-AifbFunction -ErrorAction "SilentlyContinue"
        $text = $response -replace '(?s)```.+?```', '' -replace ':', '.' -replace '[\n]{2}', "`n"
        
        Write-SpectrePanel -Title "[white] :robot: PowerShellAI [/]" -Color "IndianRed1_1" -Data "$([Spectre.Console.Markup]::Escape($text))" -Expand

        if($function) {
            Write-Host ""
            Write-Codeblock $function.Body -SyntaxHighlight -ShowLineNumbers
            $functionFile = Export-AIFunctionDefinition -Path $path -FunctionDefinition $function.Body
        } else {
            $global:LASTAIRESPONSE = $response
            throw "Fuck"
        }

        Import-Module $functionFile -Force
        $results = Invoke-Pester -Passthru
        $testResult = $LASTEXITCODE
        $results = $results | ConvertTo-NUnitReport -AsString
        # get rid of values that change each run or caching won't work
        $results = $results -replace '\s+time=".+?"', '' -replace 'date=".+?"', 'date="2023-01-01"'
        Write-Host ""

        $attempts = 0
        $maxAttempts = 4
        $semanticallyCorrect = $false
        while($semanticallyCorrect -ne $true) {
            $attempts++
            if($attempts -gt $maxAttempts) {
                Write-Error "Reached maximum attempts $attempts"
                exit
            }
            while ($testResult -ne 0) {
                $function = $null
                $text = "Not set"
                if($testResult -eq 9001) {
                    $question = "The code doesn't meet all requirements, the code needs fixing:"
                    Write-Verbose "Failing on semantics"
                    Write-Verbose $question
                    $response = (Get-GPT4Completion $question -NoCache).Trim()
                    $function = $response | ConvertTo-AifbFunction -ErrorAction "SilentlyContinue"
                    $text = $response -replace '(?s)```.+?```', '' -replace ':', '.' -replace '[\n]{2}', "`n"
                } else {
                    Write-Verbose "Failing on testing"
                    $question = "Some tests failed, the code needs fixing:`n$results"
                    Write-Verbose $question
                    $response = (Get-GPT4Completion $question).Trim()
                    $function = $response | ConvertTo-AifbFunction -ErrorAction "SilentlyContinue"
                    $text = $response -replace '(?s)```.+?```', '' -replace ':', '.' -replace '[\n]{2}', "`n"
                }

                Write-SpectrePanel -Title "[white] :robot: PowerShellAI [/]" -Color "IndianRed1_1" -Data "$([Spectre.Console.Markup]::Escape($text))" -Expand

                if($function) {
                    Write-Host ""
                    Write-Codeblock $function.Body -SyntaxHighlight -ShowLineNumbers
                    $functionFile = Export-AIFunctionDefinition -Path $path -FunctionDefinition $function.Body
                } else {
                    $global:LASTAIRESPONSE = $response
                    throw "Fuck"
                }

                Import-Module $functionFile -Force
                $results = Invoke-Pester -Passthru
                $testResult = $LASTEXITCODE
                $results = $results | ConvertTo-NUnitReport -AsString
                # get rid of values that change each run or caching won't work
                $results = $results -replace '\s+time=".+?"', '' -replace 'date=".+?"', 'date="2023-01-01"'
                Write-Host ""
            }

            # check semantics work
            $question = 'Does the code meet all requirements? Respond with "Yes" or "No" followed by an explanation.'
            Write-Verbose $question
            $response = (Get-GPT4Completion $question).Trim()
            $text = $response -replace '(?s)```.+?```', '' -replace ':', '.' -replace '[\n]{2}', "`n"
            Write-SpectrePanel -Title "[white] :robot: PowerShellAI [/]" -Color "IndianRed1_1" -Data "$([Spectre.Console.Markup]::Escape($text))" -Expand
            if($response -like "*yes*") {
                $semanticallyCorrect = $true
                $testResult = 0
            } else {
                $semanticallyCorrect = $false
                $testResult = 9001
            }
        }

    } finally {
        Pop-Location
    }
}