$script:OpenAISettings = @{
    MaxTokens = 2048
    CodeWriter = @{
        SystemPrompt = "You respond to all questions with PowerShell function code with no explanations or comments. The answer will be code only and will always be in the form of a PowerShell function."
        Model = "gpt-3.5-turbo"
        Temperature = 0.7
    }
    CodeEditor = @{
        SystemPrompt = "You are a code editor and respond to all questions with the code provided fixed based on the requests made in the chat. If the code has no issues return the code as it is."
        Model = "gpt-3.5-turbo"
        Temperature = 0.0
        Prompts = @{
            SyntaxCorrection = @'
Fix all of these PowerShell issues in the code below:
{0}

```powershell
{1}
```
'@
        }
    }
    SemanticReinforcement = @{
        SystemPrompt = "You respond to all questions with only the word YES if the PowerShell function provided meets the requirements or a corrected version of the whole PowerShell function rewritten in its entirety."
        Model = "gpt-3.5-turbo"
        Temperature = 0.0
        Prompts = @{
            Reinforcement = @'
Will this PowerShell function meet the requirement: {0}?
If it doesn't meet ALL requirements then rewrite the function so that it does and explain what was missing.

```powershell
{1}
```
'@
            FollowUp = "What would the function look like if it was fixed?"
        }
    }
}

$script:FunctionExtractionPatterns = @(
    @{
        Regex = '(?s)(function\s+([a-z0-9\-]+)\s+\{.+})'
        FunctionNameGroup = 2
        FunctionBodyGroup = 1
    }
)

function Get-AifbUserAction {
    <#
        .SYNOPSIS
            A prompt for AIFunctionBuilder to allow the user to choose what to do with the final function output
    #>

    $actions = @(
        New-Object System.Management.Automation.Host.ChoiceDescription '&Save', 'Save this function to your local filesystem'
        New-Object System.Management.Automation.Host.ChoiceDescription '&Run', 'Save this function to your local filesystem and load it into this PowerShell session'
        New-Object System.Management.Automation.Host.ChoiceDescription '&Edit', 'Request changes to this function'
        New-Object System.Management.Automation.Host.ChoiceDescription '&Quit', 'Exit AIFunctionBuilder'
    )

    $response = $Host.UI.PromptForChoice($null, "What do you want to do?", $actions, 3)

    return $actions[$response].Label -replace '&', ''
}

function Save-AifbFunctionOutput {
    <#
        .SYNOPSIS
            Prompt the user for a destination to save their script output an save the output to disk
    #>
    param (
        # The name of the function to be tested
        [string] $FunctionName,
        # A function in a text format to be formatted
        [string] $FunctionText
    )

    $suggestedFilename = "$FunctionName.psm1"

    $defaultDirectory = Join-Path $env:HOMEDRIVE $env:HOMEPATH
    $powershellAiDirectory = Join-Path $defaultDirectory "PowerShellAI"
    $defaultFile = Join-Path $powershellAiDirectory $SuggestedFilename
    $suffix = 1
    while((Test-Path -Path $defaultFile) -and $suffix -le 10) {
        $defaultFile = $defaultFile -replace '[0-9]+\.ps1$', "$suffix.ps1"
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

function Remove-AifbComments {
    <#
        .SYNOPSIS
            Removes comments from a string of PowerShell code.

        .EXAMPLE
            PS C:\> Remove-AifbComments "function foo { # comment 1 `n # comment 2 `n return 'bar' }"
            function foo {  `n  `n return 'bar' }
    #>
    param (
        # A function in a text format to have comments stripped
        [Parameter(ValueFromPipeline = $true)]
        [string] $FunctionText
    )

    process {
        $tokens = @()

        [System.Management.Automation.Language.Parser]::ParseInput($FunctionText, [ref]$tokens, [ref]$null) | Out-Null

        $comments = $tokens | Where-Object { $_.Kind -eq "Comment" }

        # Strip comments from bottom to top to preserve extent offsets
        $comments | Sort-Object { $_.Extent.StartOffset } -Descending | ForEach-Object {
            $preComment = $FunctionText.Substring(0, $_.Extent.StartOffset)
            $postComment = $FunctionText.Substring($_.Extent.EndOffset, $FunctionText.Length - $_.Extent.EndOffset)
            $FunctionText = $preComment + $postComment
        }

        return $FunctionText
    }
}

function ConvertTo-AifbFunction {
    <#
        .SYNOPSIS
            Converts a string containing a function into a hashtable with the function name and body
        .EXAMPLE
            ConvertTo-AifbFunction "This funtion writes 'bar' to the terminal function Get-Foo { Write-Host 'bar' }"
            Would return:
            @{
                Name = "Get-Foo"
                Body = "function Get-Foo { Write-Host 'bar' }"
            }
    #>
    param (
        # Some text that contains a function name and body to extract
        [Parameter(ValueFromPipeline = $true)]
        [string] $Text
    )
    process {
        foreach($pattern in $script:FunctionExtractionPatterns) {
            if($Text -match $pattern.Regex) {
                return @{
                    Name = $Matches[$pattern.FunctionNameGroup]
                    Body = ($Matches[$pattern.FunctionBodyGroup] | Format-AifbFunction)
                }
            }
        }
        
        Write-Error "There is no function in this PowerShell code block: $Text" -ErrorAction "Stop"
    }
}

function Format-AifbFunction {
    <#
        .SYNOPSIS
            Strip all comments from a PowerShell code block and use PSScriptAnalyzer to format the script if it's available
    #>
    param (
        # A function in a text format to be formatted
        [Parameter(ValueFromPipeline = $true)]
        [string] $FunctionText
    )

    process {
        Write-Verbose "Input function input:`n$FunctionText"

        # Remove all comments because the comments can skew the LLMs interpretation of the code
        $FunctionText = $FunctionText | Remove-AifbComments
        
        # Remove empty lines to save space in the rendering window
        $FunctionText = ($FunctionText.Split("`n") | Where-Object { ![string]::IsNullOrWhiteSpace($_) }) -join "`n"
        
        if(Test-AifbScriptAnalyzerAvailable) {
            $FunctionText = $FunctionText | Invoke-Formatter -Verbose:$false
        }

        Write-Verbose "Output function:`n$FunctionText"

        return $FunctionText
    }
}

function Test-AifbFunctionSyntax {
    <#
        .SYNOPSIS
            This function tests a PowerShell script for quality and commandlet usage issues.

        .DESCRIPTION
            The Test-AifbFunctionSyntax function checks a PowerShell script for quality and commandlet usage issues by
            checking that the script:
             - Uses valid syntax
             - All commandlets are used and the correct parameters are used.
            For the first line with issues, the function returns a ChatGPT prompt that requests the LLM to perform corrections for the issues.
            Only the first line is returned because asking ChatGPT or other LLM models to do multiple things at once tends to result in pretty mangled code.

        .EXAMPLE
            $FunctionText = @"
            function Get-RunningServices { Get-Service | Where-Object {$_.Status -eq "Running"} | Sort-Object -Property Name }
            "@
            $originalPrompt = "Some Prompt"
            Test-AifbFunctionSyntax -FunctionName "Get-RunningServices" -FunctionText $FunctionText

            This example tests the specified PowerShell script for quality and commandlet usage issues. If any issues are found, the function returns a prompt for corrections.
    #>
    param (
        # The name of the function to be tested
        [string] $FunctionName,
        # A function in a text format to be formatted
        [string] $FunctionText
    )

    $issuesToCorrect = @()

    # Check syntax errors
    $issuesToCorrect += Test-AifbFunctionParsing -FunctionName $FunctionName -FunctionText $FunctionText

    # Only check commandlet usage if there are no syntax errors
    if($issuesToCorrect.Count -eq 0) {
        $issuesToCorrect += Test-AifbFunctionCommandletUsage -FunctionText $FunctionText
    }

    # Deduplicate issues
    $issuesToCorrect = $issuesToCorrect | Group-Object | Select-Object -ExpandProperty Name
    
    if($issuesToCorrect.Count -gt 0) {
        return ($issuesToCorrect -join "`n")
    } else {
        Write-Verbose "The script has no issues to correct"
    }
}

function Get-AifbSemanticFailureReason {
    <#
        .SYNOPSIS
            This function takes a chat GPT response that contains code and a reason for failing function semantic validation and returns just the reason.
    #>
    param (
        # The text response from ChatGPT format.
        [Parameter(ValueFromPipeline = $true)]
        [string] $Text
    )

    $result = $Text.Trim() -replace '(?i)NO\.?\s+', ''
    $result = $result -replace '(?s).\s+(Here is|Here''s|The function should be rewritten).+', ''

    return $result
}

function Write-AifbChat {
    <#
        .SYNOPSIS
            Write the latest chat log for debugging
    #>
    param ()
    Get-ChatInProgress | ForEach-Object {
        Write-Host -NoNewline "$($_.role): "
        Write-Host -ForegroundColor DarkGray $_.content
    }
}

function Test-AifbFunctionSemantics {
    <#
        .SYNOPSIS
            This function takes a the text of a function and the original prompt used to generate it and checks that the code will achieve the goals of the original prompt.
    #>
    param (
        # The original prompt used to generate the code provided as FunctionText
        [string] $Prompt,
        # The function as text generated by the prompt
        [string] $FunctionText
    )

    New-Chat $script:OpenAISettings.SemanticReinforcement.SystemPrompt
    
    Add-AifbLogMessage "Waiting for AI to validate semantics for prompt '$Prompt'."
    $response = Write-ChatResponse -Role "user" -Content ($script:OpenAISettings.SemanticReinforcement.Prompts.Reinforcement -f $Prompt, $FunctionText) -NonInteractive `
        -OpenAISettings @{
            model = $script:OpenAISettings.SemanticReinforcement.Model
            temperature = $script:OpenAISettings.SemanticReinforcement.Temperature
            max_tokens = $script:OpenAISettings.MaxTokens
        }
    $response = $response.Trim()

    if($response -match "(?i)^YES") {
        Add-AifbLogMessage "The function meets the original intent of the prompt."
        return $FunctionText | ConvertTo-AifbFunction
    } else {
        try {
            Add-AifbLogMessage -Level "ERR" -Message ($response | Get-AifbSemanticFailureReason)
        } catch {
            Add-AifbLogMessage -Level "ERR" -Message "The function doesn't meet the original intent of the prompt."
        }
        Start-Sleep -Seconds 10
        try {
            return $response | ConvertTo-AifbFunction
        } catch {
            try {
                Add-AifbLogMessage -Level "WRN" -Message "Following up with the AI because it didn't return any code."
                $response = Write-ChatResponse -Role "user" -Content $script:OpenAISettings.SemanticReinforcement.Prompts.FollowUp -NonInteractive `
                    -OpenAISettings @{
                        model = $script:OpenAISettings.SemanticReinforcement.Model
                        temperature = $script:OpenAISettings.SemanticReinforcement.Temperature
                        max_tokens = $script:OpenAISettings.MaxTokens
                    }
                return $response | ConvertTo-AifbFunction
            } catch {
                Write-AifbChat
                Write-Error "Failed to get something sensible out of ChatGPT, the chat log has been dumped above for debugging."
            }
        }
    }
}

function Initialize-AifbFunction {
    <#
        .SYNOPSIS
            This function creates the first version of the code that will be used to start the function builder loop.
    #>
    param (
        # The prompt format is "Write a PowerShell function that will do something"
        [string] $Prompt
    )

    Write-Verbose "Getting initial powershell function with prompt '$Prompt'"
    Add-AifbLogMessage -NoRender "Waiting for AI to correct syntax issues."

    New-Chat $script:OpenAISettings.CodeWriter.SystemPrompt -Verbose:$false
    return Write-ChatResponse -Role "user" -Content $Prompt -NonInteractive `
        -OpenAISettings @{
            model = $script:OpenAISettings.CodeWriter.Model
            temperature = $script:OpenAISettings.CodeWriter.Temperature
            max_tokens = $script:OpenAISettings.MaxTokens
        } | ConvertTo-AifbFunction
}

function Optimize-AifbFunction {
    <#
        .SYNOPSIS
            This function takes a the text of a function and the original prompt used to generate it and iterates on it until it meets the intent
            of the original prompt and is also syntacticly correct.
    #>
    param (
        # The original prompt
        [string] $Prompt,
        # The initial state of the function
        [hashtable] $Function,
        # The maximum number of times to loop before giving up
        [int] $MaximumReinforcementIterations = 15,
        # Force semantic re-evaluation
        [switch] $Force
    )

    $iteration = 1
    while ($true) {
        if($iteration -gt $MaximumReinforcementIterations) {
            Write-AifbChat
            Write-Error "A valid function was not able to generated in $MaximumReinforcementIterations iterations, try again with a higher -MaximumReinforcementIterations value or rethink the initial prompt to be more explicit" -ErrorAction "Stop"
        }
        
        $corrections = Test-AifbFunctionSyntax -FunctionText $Function.Body -FunctionName $Function.Name
        
        if($corrections -or ($Force -and $iteration -eq 1)) {
            Add-AifbLogMessage "Waiting for AI to correct syntax issues."
            New-Chat $script:OpenAISettings.CodeEditor.SystemPrompt -Verbose:$false
            $Function = Write-ChatResponse -Role "user" -Content ($script:OpenAISettings.CodeEditor.Prompts.SyntaxCorrection -f $corrections, $Function.Body) -NonInteractive `
                -OpenAISettings @{
                    model = $script:OpenAISettings.CodeEditor.Model
                    temperature = $script:OpenAISettings.CodeEditor.Temperature
                    max_tokens = $script:OpenAISettings.MaxTokens
                } | ConvertTo-AifbFunction

            $Function = Test-AifbFunctionSemantics -FunctionText $Function.Body -Prompt $Prompt
            Write-AifbFunctionOutput -FunctionText $Function.Body -Prompt $Prompt
        } else {
            Add-AifbLogMessage "Function building is complete!"
            break
        }

        $iteration++
    }

    return $Function
}