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

    Initialize-AifbRenderer
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
                Write-AifbFunctionOutput -FunctionText $function.Body -Prompt $fullPrompt
                $fullPrompt = (@($fullPrompt, $editPrompt) | Where-Object { $null -ne $_ }) -join ' AND '
                $function = Optimize-AifbFunction -Function $function -Prompt $fullPrompt -Force
                Write-AifbFunctionOutput -FunctionText $function.Body -SyntaxHighlight -NoLogMessages -Prompt $fullPrompt
            }
            "Run" {
                $tempFile = New-TemporaryFile
                $tempFilePsm1 = "$($tempFile.FullName).psm1"
                Set-Content -Path $tempFile -Value $function.Body
                Move-Item -Path $tempFile.FullName -Destination $tempFilePsm1
                Write-Host "Importing function '$($function.Name)'"
                Import-Module $tempFilePsm1 -Global
                & $function.Name
            }
            "Save" {
                Save-AifbFunctionOutput -FunctionText $function.Body -FunctionName $function.Name
                $finished = $true
            }
            "Quit" {
                $finished = $true
            }
        }
    }
}