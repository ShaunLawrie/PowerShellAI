$script:ScriptAnalyzerAvailable = $null
$script:ScriptAnalyserIgnoredRules = @(
    "PSReviewUnusedParameter"
)
$script:ScriptAnalyserCustomRuleResponses = @{
    "PSAvoidOverwritingBuiltInCmdlets" = "The name of the function is reserved, rename the function to not collide with internal PowerShell commandlets."
    "PSUseApprovedVerbs" = "The function is using an unapproved verb ({0})."
    "*ShouldProcess*" = "The function has to have the CmdletBinding SupportsShouldProcess and use a process block where ShouldProcess is checked inside foreach loops."
}
$script:ScriptAnalyserCustomMessageResponses = @{
    "*Unexpected attribute 'CmdletBinding'*" = "CmdletBinding must be followed by a param block."
}
$script:CommandletsExemptFromNamedParameters = @(
    "Write-Host",
    "Write-Output",
    "Write-Error",
    "Write-Warning",
    "Write-Verbose",
    "Where-Object",
    "Foreach-Object",
    "Write-Information",
    "Write-Verbose"
)

function Test-ScriptAnalyzerAvailable {
    <#
        .SYNOPSIS
            Checks if PSScriptAnalyzer is available on this system and uses a cached response to avoid using get-module all the time.
    #>
    if($null -eq $script:ScriptAnalyzerAvailable) {
        if(Get-Module "PSScriptAnalyzer" -ListAvailable -Verbose:$false) {
            $script:ScriptAnalyzerAvailable = $true
        } else {
            Add-LogMessage -Level "WARN" -Message "This module performs better if you have PSScriptAnalyzer installed"
            $script:ScriptAnalyzerAvailable = $false
        }
    }

    return $script:ScriptAnalyzerAvailable
}

function Write-ScriptAnalyzerOutput {
    <#
        .SYNOPSIS
            This function will analyze the function text and return the error details for the first line with errors.

        .PARAMETER FunctionText
            The text of the function to analyze.

        .EXAMPLE
            Write-ScriptAnalyzerOutput -FunctionText $functionText
    #>
    param (
        [string] $FunctionText
    )
    $scriptAnalyzerOutput = Invoke-ScriptAnalyzer -ScriptDefinition $FunctionText `
        -Severity @("Warning", "Error", "ParseError") `
        -ExcludeRule $script:ScriptAnalyserIgnoredRules `
        -Verbose:$false

    if($null -ne $scriptAnalyzerOutput) {
        $brokenLines = $scriptAnalyzerOutput | Group-Object Line

        # This originally returned the whole list of errors but it was too much for the LLM to understand, just return the errors for the first line with issues and then fix other errors on future iterations
        $firstBrokenLine = $brokenLines[0]
        $brokenLineErrors = $firstBrokenLine.Group.Message
        $ruleNames = $firstBrokenLine.Group.RuleName

        Write-Overlay -Line ($firstBrokenLine.Name) -Text $($FunctionText.Split("`n")[$firstBrokenLine.Name - 1]) -ForegroundColor "Yellow"

        # Write the first custom error message that matches and violated PSScriptAnalyzer rules
        foreach($ruleResponse in $script:ScriptAnalyserCustomRuleResponses.GetEnumerator()) {
            if($ruleNames | Where-Object { $_ -like $ruleResponse.Key }) {
                Write-FunctionParsingOutput $ruleResponse.Value
                return
            }
        }

        # Write the first custom error message that matches and violated PSScriptAnalyzer message
        foreach($messageResponse in $script:ScriptAnalyserCustomMessageResponses.GetEnumerator()) {
            if($brokenLineErrors | Where-Object { $_ -like $messageResponse.Key }) {
                Write-FunctionParsingOutput $messageResponse.Value
                return
            }
        }

        # Otherwise dump the raw error messages
        $brokenLineErrors | ForEach-Object {
            Write-FunctionParsingOutput $_
        }
    }
}

function Remove-Comments {
    <#
        .SYNOPSIS
            Removes comments from a string of PowerShell code.

        .DESCRIPTION
            Removes comments from a string of PowerShell code.

        .PARAMETER FunctionText
            The string of PowerShell code to remove comments from.

        .EXAMPLE
            PS C:\> Remove-Comments "function foo { # comment 1 `n # comment 2 `n return 'bar' }"
            function foo {  `n  `n return 'bar' }
    #>
    param (
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

function Find-CommandletOnline {
    <#
    .SYNOPSIS
        Finds a commandlet online and installs he module it belongs to if the user wants to.

    .PARAMETER CommandletName
        The name of the commandlet to find online.

    .OUTPUTS
        The command if it's available after installing the module.

    .EXAMPLE
        Find-CommandletOnline -CommandletName "Get-AzActivityLog"
    #>
    param (
        [string] $CommandletName
    )
    $command = $null
    $onlineModules = Find-Module -Command $CommandletName -Verbose:$false
    if($onlineModules) {
        Write-Host "There are modules online that include the functions used by ChatGPT. To validate the usage of commandlets in the function the module needs to be installed locally.`n"
        Write-Host ($onlineModules | Select-Object Name, ProjectUri | Out-String).Trim()
        while($null -eq $command) {
            $onlineModuleToInstall = Read-Host "`nEnter the name of one of the modules to install or press enter to get ChatGPT to try use a different command"
            if(![string]::IsNullOrEmpty($onlineModuleToInstall)) {
                Install-Module -Name $onlineModuleToInstall.Trim() -Scope CurrentUser -Verbose:$false
                Import-Module -Name $onlineModuleToInstall.Trim() -Verbose:$false
                $command = Get-Command $CommandletName
                Write-Host ""
            } else {
                Write-Host "Asking ChatGPT to use another command instead of installing the module for '$CommandletName'."
                break
            }
        }
    } else {
        Write-Verbose "No commands matching the name '$CommandletName' were available online."
    }
    return $command
}

function Test-FunctionParsing {
    <#
        .SYNOPSIS
            This function tests the quality of a PowerShell function using PSScriptAnalyzer module.

        .DESCRIPTION
            The Test-FunctionParsing function checks the quality of a PowerShell script by using the PSScriptAnalyzer module.
            If any errors or warnings are detected, the function outputs a list of lines containing errors and their corresponding error messages.
            If the module is not installed, the function silently bypasses script quality validation because it's not critical to the operation of the AI Script Builder.

        .PARAMETER FunctionText
            Specifies the text of the PowerShell script to be tested.

        .EXAMPLE
            Test-FunctionParsing -FunctionText "Get-ChildItem | Where-Object { $_.Length -gt 1GB }"
    #>
    [CmdletBinding()]
    param (
        [string] $FunctionName,
        [string] $FunctionText
    )

    if(Get-Command $FunctionName -ErrorAction "SilentlyContinue") {
        Write-Overlay -Line 1 -Text ($FunctionText.Split("`n")[0]) -BackgroundColor "White" -ForegroundColor "Red"
        Write-FunctionParsingOutput "The name of the function is reserved, rename the function to not collide with common function names."
    }

    if(Test-ScriptAnalyzerAvailable) {
        Write-Verbose "Using PSScriptAnalyzer to validate script quality"
        Write-ScriptAnalyzerOutput -FunctionText $FunctionText
    } else {
        Add-LogMessage -Level "WARN" -Message "PSScriptAnalyzer is not installed so falling back on parsing directly with PS internals."
        try {
            [scriptblock]::Create($FunctionText) | Out-Null
        } catch {
            $innerExceptionErrors = $_.Exception.InnerException.Errors
            if($innerExceptionErrors) {
                Write-FunctionParsingOutput $innerExceptionErrors[0].Message
            } else {
                Write-FunctionParsingOutput "The script is invalid because of a $($_.FullyQualifiedErrorId)."
            }
        }
    }
}

function Test-FunctionCommandletUsage {
    <#
        .SYNOPSIS
            This function tests the usage of commandlets in a PowerShell script.

        .DESCRIPTION
            The Test-FunctionCommandletUsage function checks the usage of commandlets in a PowerShell script by analyzing the Abstract Syntax Tree (AST) of the script.
            For each commandlet found in the script, the function checks whether the commandlet is valid and whether any of the commandlet parameters are invalid.

        .PARAMETER FunctionText
            Specifies the text content of the PowerShell script to be tested.

        .EXAMPLE
            $FunctionText = Get-Content -Path "C:\Scripts\MyScript.ps1" -Raw
            Test-FunctionCommandletUsage -ScriptAst $scriptAst

            This example tests the usage of commandlets in a PowerShell script.
    #>
    param (
        [string] $FunctionText
    )

    $scriptAst = [System.Management.Automation.Language.Parser]::ParseInput($FunctionText, [ref]$null, [ref]$null)

    $commandlets = $scriptAst.FindAll({$args[0].GetType().Name -eq "CommandAst"}, $true)

    # Validate each commandlet and return on the first error found because telling the LLM about too many errors at once results in unpredictable fixes
    foreach($commandlet in $commandlets) {
        $commandletName = $commandlet.CommandElements[0].Value
        $commandletParameterNames = $commandlet.CommandElements.ParameterName
        $commandletParameterElements = @()
        $hasPipelineInput = $null -ne $commandlet.Parent -and $commandlet.Parent.GetType().Name -eq "PipelineAst" -and $commandlet.Parent.PipelineElements.Count -gt 1
        $extent = $commandlet.Extent
        if($commandlet.CommandElements.Count -gt 1) {
            $commandletParameterElements = $commandlet.CommandElements[1..($commandlet.CommandElements.Count - 1)]
        }
        $command = Get-Command $commandletName -ErrorAction "SilentlyContinue"
        
        # Check online if no local command is found
        if($null -eq $command) {
            $command = Find-CommandletOnline -CommandletName $commandletName
        }

        if($null -eq $command) {
            Write-Overlay -Line $extent.StartLineNumber -Column $extent.StartColumnNumber -Text $extent.Text -ForegroundColor "Yellow"
            Write-FunctionParsingOutput "The commandlet $commandletName cannot be found, use a different command or write your own implementation."
            return
        }
        
        # Check for missing parameters
        foreach($param in $commandletParameterNames) {
            if(![string]::IsNullOrEmpty($param)) {
                if(!$command.Parameters.ContainsKey($param)) {
                    Write-Overlay -Line $extent.StartLineNumber -Column $extent.StartColumnNumber -Text $extent.Text -ForegroundColor "Yellow"
                    Write-FunctionParsingOutput "The commandlet $commandletName does not take a parameter named $param, use another command."
                    return
                }
            }
        }

        # Check for unnamed parameters, these are harder to validate and makes a generated script less obvious as to what it does
        if($commandletParameterElements.Count -gt 0 -and !$script:CommandletsExemptFromNamedParameters.Contains($commandletName)) {
            $previousElementWasParameterName = $false
            foreach($element in $commandletParameterElements) {
                if($element.GetType().Name -eq "CommandParameterAst") {
                    $previousElementWasParameterName = $true
                } else {
                    if(!$previousElementWasParameterName) {
                        Write-Overlay -Line $extent.StartLineNumber -Column $extent.StartColumnNumber -Text $extent.Text -ForegroundColor "Yellow"
                        Write-FunctionParsingOutput "Use a named parameter when passing $element to $commandletName."
                        return
                    }
                    $previousElementWasParameterName = $false
                }
            }
        }

        # Check named parameters haven't been specified more than once
        $duplicateParameters = $commandletParameterNames | Group-Object | Where-Object { $_.Count -gt 1 } 
        foreach($duplicateParameter in $duplicateParameters) {
            Write-Overlay -Line $extent.StartLineNumber -Column $extent.StartColumnNumber -Text $extent.Text -ForegroundColor "Yellow"
            Write-FunctionParsingOutput "The parameter $($duplicateParameter.Name) cannot be provided more than once to $commandletName."
            return
        }
        
        # Check at least one parameter set is satisfied if all parameters to this commandlet have been specified by name
        if(!$script:CommandletsExemptFromNamedParameters.Contains($commandletName)) {
            $parameterSetSatisfied = $false
            if($command.ParameterSets.Count -eq 0) {
                $parameterSetSatisfied = $true
            } else {
                foreach($parameterSet in $command.ParameterSets) {
                    $mandatoryParameters = $parameterSet.Parameters | Where-Object { $_.IsMandatory }
                    $mandatoryParametersUsed = $mandatoryParameters | Where-Object { $commandletParameterNames -contains $_.Name }
                    if($hasPipelineInput -and ($mandatoryParameters | Where-Object { $_.ValueFromPipeline })) {
                        $mandatoryParametersUsed += @{
                            Name = "Pipeline Input"
                        }
                    }
                    if($mandatoryParametersUsed.Count -ge $mandatoryParameters.Count) {
                        $parameterSetSatisfied = $true
                        break
                    }
                }
            }
            if(!$parameterSetSatisfied) {
                Write-Overlay -Line $extent.StartLineNumber -Column $extent.StartColumnNumber -Text $extent.Text -ForegroundColor "Yellow"
                Write-FunctionParsingOutput "Parameter set cannot be resolved using the specified named parameters for $commandletName."
                return
            }
        }
    }
}