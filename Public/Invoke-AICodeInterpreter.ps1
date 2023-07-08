$script:WorkingStoragePath = $null
$global:WarningPreference = "SilentlyContinue"

function Initialize-AICodeInterpreter {
    param (
        [string] $RunId
    )

    if ($PSVersionTable.Platform -eq 'Unix') {
        $Script:WorkingStoragePath = Join-Path $env:HOME '~/PowerShellAI/ChatGPT/CodeInterpreter'
    }
    else {
        $Script:WorkingStoragePath = Join-Path $env:APPDATA 'PowerShellAI/ChatGPT/CodeInterpreter'
    }

    $path = "$script:WorkingStoragePath\$RunId"
    New-Item -Path "$path" -ItemType "Directory" -Force | Out-Null

    Write-Host "Working in directory: $path`n"

    return $path
}

function Export-AITestDefinition {
    param (
        [string] $RunId,
        [string] $TestDefinition
    )

    $path = "$script:WorkingStoragePath\$RunId\function.Tests.ps1"
    Set-Content -Path $path -Value $TestDefinition

    return $path
}

function Export-AIFunctionDefinition {
    param (
        [string] $RunId,
        [string] $FunctionDefinition
    )

    $path = "$script:WorkingStoragePath\$RunId\function.psm1"
    Set-Content -Path $path -Value $FunctionDefinition

    return $path
}

function Invoke-AICodeInterpreter {
    param (
        [string] $FunctionName = "Get-MagicNumber",
        [string] $ModuleName = "TestingModule",
        [string] $Start = "Write pester tests for a function $FunctionName from the module $ModuleName that takes an integer as input and returns another integer. Given an number of 2 I expect an output of 99. Given an number of 43 I expect an output of 103.",
        [string] $Build = "Now that the tests are written, write powershell function code that will pass the tests using logic to deduce what the best quality code to solve the problem will be. If you need to do any math write the powershell to do the math and I will execute it for you."
    )

    $runId = [Guid]::NewGuid().Guid

    Set-ChatSessionOption -model "gpt-4" -max_tokens 1024
    New-Chat -Content "You are an expert powershell developer and you test and write code" | Out-Null

    $path = Initialize-AICodeInterpreter -RunId $runId

    Push-Location "."
    try {
        Set-Location $path

        $testFile = $null
        $functionFile = $null

        $response = (Get-GPT4Completion $Start).Trim()
        $test = $response | ConvertTo-AifbTest
        $text = $response -replace '(?s)```.+?```', '' -replace ':', '.' -replace '[\n]{2}', "`n"

        Write-Host $text
        
        if($test) {
            Write-Host ""
            Write-Codeblock $test -SyntaxHighlight -ShowLineNumbers
            $testFile = Export-AITestDefinition -RunId $runId -TestDefinition $test
            Write-Host ""
        } else {
            $global:LASTAIRESPONSE = $response
            throw "Fuck"
        }

        $response = (Get-GPT4Completion $Build).Trim()
        $function = $response | ConvertTo-AifbFunction -ErrorAction "SilentlyContinue"
        $text = $response -replace '(?s)```.+?```', '' -replace ':', '.' -replace '[\n]{2}', "`n"
        
        Write-Host $text

        if($function) {
            Write-Host ""
            Write-Codeblock $function.Body -SyntaxHighlight -ShowLineNumbers
            $functionFile = Export-AIFunctionDefinition -RunId $runId -FunctionDefinition $function.Body
        } else {
            $global:LASTAIRESPONSE = $response
            throw "Fuck"
        }

        Import-Module $functionFile -Force
        $results = Invoke-Pester -Passthru
        $results = $results | ConvertTo-NUnitReport -AsString
        Write-Host ""

        if($LASTEXITCODE -ne 0) {
            $question = "Some tests failed, the code needs fixing:`n$results"
            $response = (Get-GPT4Completion $question).Trim()
            $function = $response | ConvertTo-AifbFunction -ErrorAction "SilentlyContinue"
            $text = $response -replace '(?s)```.+?```', '' -replace ':', '.' -replace '[\n]{2}', "`n"

            Write-Host $text

            if($function) {
                Write-Host ""
                Write-Codeblock $function.Body -SyntaxHighlight -ShowLineNumbers
                $functionFile = Export-AIFunctionDefinition -RunId $runId -FunctionDefinition $function.Body
            } else {
                $global:LASTAIRESPONSE = $response
                throw "Fuck"
            }

            Import-Module $functionFile -Force
            Invoke-Pester
            Write-Host ""
        }

    } finally {
        Pop-Location
    }
}