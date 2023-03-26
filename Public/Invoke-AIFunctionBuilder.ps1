function Invoke-AIFunctionBuilder {
    <#
        .SYNOPSIS
            Create a PowerShell function with the help of ChatGPT
        .DESCRIPTION
            Invoke-AIFunctionBuilder is a function that uses ChatGPT to generate an initial PowerShell function to achieve the goal defined
            in the prompt by the user but goes a few steps beyond the typical interaction with an LLM by auto-validating the result
            of the AI generated script using parsing techniques that feed common issues back to the model until it resolves them.
        .EXAMPLE
            Invoke-AIFunctionBuilder
        .NOTES
            Author: Shaun Lawrie
    #>
    [CmdletBinding()]
    [alias("ifb")]
    param(
        # A prompt in the format "Write a powershell function that will sing me happy birthday"
        [string] $Prompt,
        # The maximum loop iterations to attempt to generate the function within
        [int] $MaximumReinforcementIterations = 15
    )

    Clear-Host

    $prePrompt = $null
    if([string]::IsNullOrEmpty($Prompt)) {
        $prePrompt = "Write a PowerShell function that will"
        Write-Host -ForegroundColor Cyan -NoNewline "${prePrompt}: "
        $Prompt = Read-Host
    }
    $fullPrompt = (@($prePrompt, $Prompt) | Where-Object { $null -ne $_ }) -join ' '

    $function = Initialize-AifbFunction -Prompt $fullPrompt

    Initialize-AifbRenderer -InitialPrePrompt $prePrompt -InitialPrompt $Prompt
    Write-AifbFunctionOutput -FunctionText $function.Body -Prompt $fullPrompt

    $function = Optimize-AifbFunction -Function $function -Prompt $fullPrompt

    Write-AifbFunctionOutput -FunctionText $function.Body -SyntaxHighlight -NoLogMessages -Prompt $fullPrompt

    $finished = $false
    while(-not $finished) {
        $action = Get-AifbUserAction -Function $function

        switch($action) {
            "Edit" {
                $editPrePrompt = "I also want the function to"
                Write-Host -ForegroundColor Cyan -NoNewline "${editPrePrompt}: "
                $editPrompt = Read-Host
                Write-Verbose "Re-running function optimizer with a request to edit functionality: '$editPrompt'"
                $fullPrompt = (@($fullPrompt, $editPrompt) | Where-Object { ![string]::IsNullOrWhiteSpace($_) }) -join '. The function must '
                Write-AifbFunctionOutput -FunctionText $function.Body -Prompt $fullPrompt
                $function = Optimize-AifbFunction -Function $function -Prompt $fullPrompt -Force
                Write-AifbFunctionOutput -FunctionText $function.Body -SyntaxHighlight -NoLogMessages -Prompt $fullPrompt
            }
            "Explain" {
                $explanation = (Get-GPT3Completion "Explain how the function below meets all of the requirements the following requirements, list the requirements and how they're met`nRequirements: $fullPrompt`n`n``````powershell`n$($function.Body)``````" -max_tokens 2000).Trim()
                Write-AifbFunctionOutput -FunctionText $function.Body -SyntaxHighlight -NoLogMessages -Prompt $fullPrompt
                Write-Host $explanation
                Write-Host ""
            }
            "Run" {
                $tempFile = New-TemporaryFile
                $tempFilePsm1 = "$($tempFile.FullName).psm1"
                Set-Content -Path $tempFile -Value $function.Body
                Move-Item -Path $tempFile.FullName -Destination $tempFilePsm1
                Write-Host "Importing function '$($function.Name)'"
                Import-Module $tempFilePsm1 -Global
                $command = (Get-Command $function.Name)
                $params = @{}
                $command.ParameterSets.GetEnumerator()[0].Parameters | Where-Object { $_.Position -ge 0 } | Foreach-Object { $params[$_.Name] = Read-Host "$($_.Name) ($($_.ParameterType))" }
                $previousErrorActionPreference = $ErrorActionPreference
                try {
                    $ErrorActionPreference = "Stop"
                    & $function.Name @params
                    Get-Module | Where-Object { $_.Path -eq $tempFilePsm1 } | Remove-Module
                } catch {
                    Get-Module | Where-Object { $_.Path -eq $tempFilePsm1 } | Remove-Module
                    Write-Error $_
                    $answer = Read-Host -Prompt "An error occurred, do you want to try auto-fix the function? (y/n)"
                    if($answer -eq "y") {
                        Write-AifbFunctionOutput -FunctionText $function.Body -Prompt $fullPrompt
                        $function = Optimize-AifbFunction -Function $function -Prompt $fullPrompt -RuntimeError "$($_.Exception.Message) The error occured on '$($_.InvocationInfo.Line.Trim())'"
                        Write-AifbFunctionOutput -FunctionText $function.Body -SyntaxHighlight -NoLogMessages -Prompt $fullPrompt
                    }
                }
                $ErrorActionPreference = $previousErrorActionPreference
            }
            "Save" {
                $moduleLocation = Save-AifbFunctionOutput -FunctionText $function.Body -FunctionName $function.Name -Prompt $fullPrompt
                Import-Module $moduleLocation -Global
                Write-Host "The function is available as '$($function.Name)' in your current terminal session. To import this function in the future use 'Import-Module $moduleLocation' or add the directory with all your PowerShellAI modules to your `$env:PSModulePath to have them auto import for every session."
                $finished = $true
            }
            "Quit" {
                $finished = $true
            }
        }
    }
}