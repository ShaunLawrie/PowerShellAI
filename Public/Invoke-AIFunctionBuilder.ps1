function Invoke-AIFunctionBuilder {
    <#
        .SYNOPSIS
            Create a PowerShell script with the help of ChatGPT
        .DESCRIPTION
            Invoke-AIFunctionBuilder is a function that uses ChatGPT to generate an initial PowerShell function to achieve the goal defined
            in the prompt by the user but goes a few steps beyond the typical interaction with an LLM by auto-validating the result
            of the AI generated script using parsing techniques that feed common issues back to the model until it resolves them.
        .EXAMPLE
            Invoke-AIFunctionBuilder
    #>
    [CmdletBinding()]
    [alias("ifb")]
    param(
        [string] $Prompt,
        [int] $MaximumReinforcementIterations = 15
    )

    $ErrorActionPreference = "SilentlyContinue"

    if([string]::IsNullOrEmpty($Prompt)) {
        $prePrompt = "Write a PowerShell function that will"
        Write-Host -ForegroundColor Green -NoNewline "`n${prePrompt}: "
        $Prompt = Read-Host
    }

    $iteration = 1

    Write-Verbose "Sending initial prompt for completion: '$Prompt'"
    $currentFunction = Initialize-Function -Prompt $Prompt

    Initialize-Renderer
    Write-FunctionOutput -Stage "$iteration stage 1 (syntax validation)" -FunctionText $currentFunction.Body

    while ($true) {
        if($iteration -gt $MaximumReinforcementIterations) {
            Write-Error "A valid function was not able to generated in $MaximumReinforcementIterations iterations, try again with a higher -MaximumReinforcementIterations value or rethink the initial prompt to be more explicit"
            return
        }
        
        $correctionPrompt = Test-FunctionSyntax -FunctionText $currentFunction.Body -FunctionName $currentFunction.Name
        
        if($correctionPrompt) { 
            Add-LogMessage "Waiting for code-davinci-001 to correct syntax issues."
            $currentFunction = (Get-OpenAIEdit -InputText $currentFunction.Body -Instruction $correctionPrompt).text | ConvertTo-Function
            Write-FunctionOutput -Stage "$iteration stage 2 (semantic validation)" -FunctionText $currentFunction.Body

            $currentFunction = Test-FunctionSemantics -FunctionText $currentFunction.Body -Prompt $Prompt
            Write-FunctionOutput -Stage "$iteration stage 1 (syntax validation)" -FunctionText $currentFunction.Body
        } else {
            break
        }

        $iteration++
    }

    Write-FunctionOutput -Stage "$iteration stage 3 (syntax highlighting)" -FunctionText $currentFunction.Body -SyntaxHighlight

    $action = Get-UserAction -Filename $suggestedFilename

    switch($action) {
        "Run" {
            $scriptLocation = Save-FunctionOutput -FunctionText $currentFunction.Body -FunctionName $currentFunction.Name
            Write-Host "Running '. $scriptLocation'`n`nYou can now use this function"
            Import-Module $scriptLocation
        }
        "Save" {
            Save-FunctionOutput -FunctionText $currentFunction.Body -FunctionName $currentFunction.Name
        }
    }
}