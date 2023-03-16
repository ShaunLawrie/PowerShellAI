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

    $ErrorActionPreference = "SilentlyContinue"

    $prePrompt = $null
    if([string]::IsNullOrEmpty($Prompt)) {
        $prePrompt = "Write a PowerShell function that will"
        Write-Host -ForegroundColor Cyan -NoNewline "${prePrompt}: "
        $Prompt = Read-Host
    }
    $postPrompt = @($prePrompt, $Prompt) -join " "

    $iteration = 1

    Write-Verbose "Sending initial prompt for completion: '$postPrompt'"
    $currentFunction = Initialize-AifbFunction -Prompt $postPrompt

    Initialize-AifbRenderer
    Write-AifbFunctionOutput -FunctionText $currentFunction.Body

    while ($true) {
        if($iteration -gt $MaximumReinforcementIterations) {
            Write-AifbChat
            Write-Error "A valid function was not able to generated in $MaximumReinforcementIterations iterations, try again with a higher -MaximumReinforcementIterations value or rethink the initial prompt to be more explicit" -ErrorAction "Stop"
        }
        
        $correctionPrompt = Test-AifbFunctionSyntax -FunctionText $currentFunction.Body -FunctionName $currentFunction.Name
        
        if($correctionPrompt) { 
            Add-AifbLogMessage "Waiting for code-davinci-001 to correct syntax issues."
            $currentFunction = (Get-OpenAIEdit -InputText $currentFunction.Body -Instruction $correctionPrompt).text | ConvertTo-AifbFunction
            Write-AifbFunctionOutput -FunctionText $currentFunction.Body

            $currentFunction = Test-AifbFunctionSemantics -FunctionText $currentFunction.Body -Prompt $Prompt
            Write-AifbFunctionOutput -FunctionText $currentFunction.Body
        } else {
            Add-AifbLogMessage "Function building is complete!"
            break
        }

        $iteration++
    }

    Write-AifbFunctionOutput -FunctionText $currentFunction.Body -SyntaxHighlight

    $action = Get-AifbUserAction -Filename $suggestedFilename

    switch($action) {
        "Run" {
            $tempFile = New-TemporaryFile
            $tempFilePsm1 = "$($tempFile.FullName).psm1"
            Set-Content -Path $tempFile -Value $currentFunction.Body
            Move-Item -Path $tempFile.FullName -Destination $tempFilePsm1
            Write-Host "Importing function '$($currentFunction.Name)'"
            Import-Module $tempFilePsm1 -Global -Verbose
        }
        "Save" {
            Save-AifbFunctionOutput -FunctionText $currentFunction.Body -FunctionName $currentFunction.Name
        }
    }
}