$script:PowerShellAI = @{
    MaxTokens = 2048
}

$script:SystemPrompts = @{
    ScriptWriter = "You respond to all questions with PowerShell function code with no explanations or comments. The answer will be code only and will always be in the form of a PowerShell function."
    SemanticReinforcement = "You respond to all questions with ONLY THE WORD YES if the PowerShell function provided meets the requirements or a corrected version of the whole PowerShell function rewritten in its entirety. Remember if you say NO you need to return a corrected version of the function. Always return PowerShell code!"
}

$script:UserPrompts = @{
    SemanticReinforcement = @'
Will this PowerShell function {0}?
If it doesn't meet ALL requirements then rewrite the function so that it does and explain what was missing.

```powershell
{1}
```
'@
    SemanticFollowUp = @'
What would the function look like if it was fixed?
'@
    SyntaxCorrection = @"
Fix all of these PowerShell issues:
{0}
"@
}

$script:FunctionExtractionPatterns = @(
    @{
        Regex = '(?s)(function\s+([a-z0-9\-]+)\s+\{.+})'
        FunctionNameGroup = 2
        FunctionBodyGroup = 1
    }
)

function Get-UserAction {
    <#
        .SYNOPSIS
            A prompt for AIFunctionBuilder to allow the user to choose what to do with the final script
    #>
    $actions = @(
        New-Object System.Management.Automation.Host.ChoiceDescription '&Save', 'Save this function to your local filesystem'
        New-Object System.Management.Automation.Host.ChoiceDescription '&Run', 'Save this function to your local filesystem and load it into this PowerShell session'
        New-Object System.Management.Automation.Host.ChoiceDescription '&Quit', 'Exit AIFunctionBuilder'
    )

    $response = $Host.UI.PromptForChoice($null, "What do you want to do?", $actions, 2)

    return $actions[$response].Label -replace '&', ''
}

function Save-FunctionOutput {
    <#
        .SYNOPSIS
            Prompt the user for a destination to save their script output an save the output to disk
    #>
    param (
        [string] $FunctionText,
        [string] $FunctionName
    )

    $suggestedFilename = "$FunctionName.psm1"

    $defaultDirectory = Join-Path $env:HOMEDRIVE $env:HOMEPATH
    $powershellAiDirectory = Join-Path $defaultDirectory "PowerShellAI"
    $defaultFile = Join-Path $powershellAiDirectory $SuggestedFilename
    $suffix = 1
    while((Test-Path -Path $defaultFile) -and $suffix -le 10) {
        $defaultFile = $defaultFile -replace '[0-9]+\.psm1$', "$suffix.psm1"
        $suffix++
    }

    while($true) {
        $finalDestination = Read-Host -Prompt "Enter a location to save or press enter for the default ($defaultFile)"
        if([string]::IsNullOrEmpty($finalDestination)) {
            $finalDestination = $defaultFile
            if(!(Test-Path $powershellAiDirectory)) {
                New-Item -Path $powershellAiDirectory -ItemType Directory -Force | Out-Null
            }
        }

        if(Test-Path $finalDestination) {
            Write-Error "There is already a file at '$finalDestination'"
        } else {
            Set-Content -Path $finalDestination -Value $FunctionText
            Write-Output $finalDestination
            break
        }
    }
}

function ConvertTo-Function {
    <#
        .SYNOPSIS
            Converts a string containing a function into a hashtable with the function name and body
        .PARAMETER Text
            The text containing the function
        .EXAMPLE
            ConvertTo-Function "This funtion writes 'bar' to the terminal function Get-Foo { Write-Host 'bar' }"
            Would return:
            @{
                Name = "Get-Foo"
                Body = "function Get-Foo { Write-Host 'bar' }"
            }
    #>
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string] $Text
    )
    process {
        foreach($pattern in $script:FunctionExtractionPatterns) {
            if($Text -match $pattern.Regex) {
                return @{
                    Name = $Matches[$pattern.FunctionNameGroup]
                    Body = ($Matches[$pattern.FunctionBodyGroup] | Format-Function)
                }
            }
        }
        
        Write-Error "There is no function in this PowerShell code block: $Text" -ErrorAction "Stop"
    }
}

function Format-Function {
    <#
        .SYNOPSIS
            Strip all comments from a PowerShell code block and use PSScriptAnalyzer to format the script if it's available
    #>
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string] $FunctionText
    )

    process {
        Write-Verbose "Input function input:`n$FunctionText"

        # Remove all comments because the comments can skew the LLMs interpretation of the code
        $FunctionText = $FunctionText | Remove-Comments
        
        # Remove empty lines to save space in the rendering window
        $FunctionText = ($FunctionText.Split("`n") | Where-Object { ![string]::IsNullOrWhiteSpace($_) }) -join "`n"
        
        if(Test-ScriptAnalyzerAvailable) {
            $FunctionText = $FunctionText | Invoke-Formatter -Verbose:$false
        }

        Write-Verbose "Output function:`n$FunctionText"

        return $FunctionText
    }
}

function Test-FunctionSyntax {
    <#
        .SYNOPSIS
            This function tests a PowerShell script for quality and commandlet usage issues.

        .DESCRIPTION
            The Test-FunctionSyntax function checks a PowerShell script for quality and commandlet usage issues by calling the
            validating the script parses correctly and all commandlets exist and have the correct parameters used.
            If any issues are found, the function returns a ChatGPT prompt that requests the LLM to perform corrections for the issues.

        .PARAMETER FunctionName
            Specifies the name of the PowerShell function to be tested.

        .PARAMETER FunctionText
            Specifies the text of the PowerShell script to be tested.

        .EXAMPLE
            $FunctionText = @"
            function Get-RunningServices { Get-Service | Where-Object {$_.Status -eq "Running"} | Sort-Object -Property Name }
            "@
            $originalPrompt = "Some Prompt"
            Test-FunctionSyntax -FunctionName "Get-RunningServices" -FunctionText $FunctionText

            This example tests the specified PowerShell script for quality and commandlet usage issues. If any issues are found, the function returns a prompt for corrections.
    #>
    param (
        [string] $FunctionName,
        [string] $FunctionText
    )

    $issuesToCorrect = @()

    # Check syntax errors
    $issuesToCorrect += Test-FunctionParsing -FunctionName $FunctionName -FunctionText $FunctionText
    # Only check commandlet usage if there are no syntax errors
    if($issuesToCorrect.Count -eq 0) {
        $issuesToCorrect += Test-FunctionCommandletUsage -FunctionText $FunctionText
    }

    # Deduplicate issues
    $issuesToCorrect = $issuesToCorrect | Group-Object | Select-Object -ExpandProperty Name
    
    if($issuesToCorrect.Count -gt 0) {
        return ($script:UserPrompts.SyntaxCorrection -f ($issuesToCorrect -join "`n"))
    } else {
        Write-Verbose "The script has no issues to correct"
    }
}

function Test-FunctionSemantics {
    param (
        [string] $Prompt,
        [string] $FunctionText
    )
    New-Chat $script:SystemPrompts.SemanticReinforcement -Verbose:$false
    Add-LogMessage "Waiting for gpt-3.5-turbo to validate semantics."
    $response = Write-ChatResponse -Role "user" -Content ($script:UserPrompts.SemanticReinforcement -f $Prompt, $FunctionText) -max_tokens $script:PowerShellAI.MaxTokens -NonInteractive
    if($response.Trim() -match "(?i)^YES") {
        Add-LogMessage "The function meets the original intent of the prompt."
        return $FunctionText | ConvertTo-Function
    } else {
        if($response -match '(?s)^(.+)(\s+Here.+?a corrected|\s+function\s+([a-z0-9\-]+)\s+\{)') {
            Add-LogMessage -Level "ERROR" -Message (($Matches[1].Trim() -replace '(?i)NO\.?\s+', '') -replace '(?s).\s+(Here is|Here''s).+', '')
        } else {
            Add-LogMessage -Level "ERROR" -Message "The function doesn't meet the original intent of the prompt."
        }
        try {
            return $response | ConvertTo-Function
        } catch {
            Add-LogMessage -Level "WARN" -Message "Following up with ChatGPT because it didn't return any code."
            $response = Write-ChatResponse -Role "user" -Content $script:UserPrompts.SemanticFollowUp -max_tokens $script:PowerShellAI.MaxTokens -NonInteractive
            return $response | ConvertTo-Function
        }
    }
}

function Initialize-Function {
    param (
        [string] $Prompt
    )
    New-Chat $script:SystemPrompts.ScriptWriter -Verbose:$false
    return Write-ChatResponse -Role "user" -Content $Prompt -max_tokens $script:PowerShellAI.MaxTokens -NonInteractive | ConvertTo-Function
}