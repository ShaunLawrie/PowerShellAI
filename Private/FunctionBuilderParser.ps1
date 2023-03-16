# Cached result of checking if PSScriptAnalyzer is installed
$script:ScriptAnalyzerAvailable = $null
# List of PSScriptAnalyzer rules to ignore when validating functions
$script:ScriptAnalyserIgnoredRules = @(
    "PSReviewUnusedParameter"
)
# ScriptAnalyzer rules to return custom error messages for rule names that match the keys of the hashtable because the default errors trip up LLM models
$script:ScriptAnalyserCustomRuleResponses = @{
    "PSAvoidOverwritingBuiltInCmdlets" = "The name of the function is reserved, rename the function to not collide with internal PowerShell commandlets."
    "PSUseApprovedVerbs" = "The function name is using an unapproved verb, use a valid PowerShell verb" #, some common ones are $((Get-Verb | Where-Object { $_.Group -eq 'Common' } | Select-Object -ExpandProperty Verb) -join ', ')."
    "*ShouldProcess*" = "The function has to have the CmdletBinding SupportsShouldProcess and use a process block where ShouldProcess is checked inside foreach loops."
}
# ScriptAnalyzer custom error messages for messages matching keys in the hashtable because the default errors trip up LLM models
$script:ScriptAnalyserCustomMessageResponses = @{
    "Script definition uses Write-Host*" = "Avoid using Write-Host because it might not work in all hosts."
    "*Unexpected attribute 'CmdletBinding'*" = "CmdletBinding must be followed by a param block."
    "*uses a plural noun*" = "Function name can't be a plural$(Get-AifbUnavailableFunctionNames)"
}
# Simple functions that don't need named parameters to work out if they're being used correctly
$script:CommandletsExemptFromNamedParameters = @(
    "Write-Host",
    "Write-Output",
    "Write-Error",
    "Write-Warning",
    "Write-Verbose",
    "Where-Object",
    "ForEach-Object",
    "Write-Information",
    "Write-Verbose"
)
$script:UnavailableCommandletNames = @()

function Get-AifbUnavailableFunctionNames {
    if($script:UnavailableCommandletNames.Count -gt 0) {
        return " (other unavailable names are $($script:UnavailableCommandletNames | Group-Object | Select-Object -ExpandProperty "Name") -join ', ')"
    } else {
        return ""
    }
}

function Test-AifbScriptAnalyzerAvailable {
    <#
        .SYNOPSIS
            Checks if PSScriptAnalyzer is available on this system and uses a cached response to avoid using get-module all the time.
    #>
    if($null -eq $script:ScriptAnalyzerAvailable) {
        if(Get-Module "PSScriptAnalyzer" -ListAvailable -Verbose:$false) {
            $script:ScriptAnalyzerAvailable = $true
        } else {
            Add-AifbLogMessage -Level "WRN" -Message "This module performs better if you have PSScriptAnalyzer installed"
            $script:ScriptAnalyzerAvailable = $false
        }
    }

    return $script:ScriptAnalyzerAvailable
}

function Write-AifbScriptAnalyzerOutput {
    <#
        .SYNOPSIS
            This function will analyze the function text and return the error details for the first line with errors.
    #>
    [CmdletBinding()]
    param (
        # A function in a text format to be formatted
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

        Write-AifbOverlay -Line ($firstBrokenLine.Name) -Text $($FunctionText.Split("`n")[$firstBrokenLine.Name - 1]) -ForegroundColor "Yellow"

        # Write the first custom error message that matches and violated PSScriptAnalyzer rules
        foreach($ruleResponse in $script:ScriptAnalyserCustomRuleResponses.GetEnumerator()) {
            if($ruleNames | Where-Object { $_ -like $ruleResponse.Key }) {
                Write-AifbFunctionParsingOutput $ruleResponse.Value
                return
            }
        }

        # Write the first custom error message that matches and violated PSScriptAnalyzer message
        foreach($messageResponse in $script:ScriptAnalyserCustomMessageResponses.GetEnumerator()) {
            if($brokenLineErrors | Where-Object { $_ -like $messageResponse.Key }) {
                Write-AifbFunctionParsingOutput $messageResponse.Value
                return
            }
        }

        # Otherwise dump the raw error messages
        $brokenLineErrors | ForEach-Object {
            Write-AifbFunctionParsingOutput $_
        }
    }
}

function Find-AifbCommandletOnline {
    <#
        .SYNOPSIS
            Finds a commandlet online and installs he module it belongs to if the user wants to.

        .EXAMPLE
            Find-AifbCommandletOnline -CommandletName "Get-AzActivityLog"
    #>
    [CmdletBinding()]
    param (
        # The name of the commandlet to find online
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

function Test-AifbFunctionParsing {
    <#
        .SYNOPSIS
            This function tests the quality of a PowerShell function using PSScriptAnalyzer module.

        .DESCRIPTION
            The Test-AifbFunctionParsing function checks the quality of a PowerShell script by using the PSScriptAnalyzer module.
            If any errors or warnings are detected, the function outputs a list of lines containing errors and their corresponding error messages.
            If the module is not installed, the function silently bypasses script quality validation because it's not critical to the operation of the AI Script Builder.
    #>
    [CmdletBinding()]
    param (
        # The name of the function to be tested
        [string] $FunctionName,
        # A function in a text format to be tested
        [string] $FunctionText
    )

    if(Get-Command $FunctionName -ErrorAction "SilentlyContinue") {
        Write-AifbOverlay -Line 1 -Text ($FunctionText.Split("`n")[0]) -ForegroundColor "Yellow"
        Write-AifbFunctionParsingOutput "The name of the function is reserved, rename the function to not collide with common function names$(Get-AifbUnavailableFunctionNames)."
        $script:UnavailableCommandletNames += $FunctionName
    }

    if($FunctionName -notlike "*-*") {
        Write-AifbOverlay -Line 1 -Text ($FunctionText.Split("`n")[0]) -ForegroundColor "Yellow"
        Write-AifbFunctionParsingOutput "The name of the function should follow the PowerShell format of Verb-Noun$(Get-AifbUnavailableFunctionNames)."
    }

    if(Test-AifbScriptAnalyzerAvailable) {
        Write-Verbose "Using PSScriptAnalyzer to validate script quality"
        Write-AifbScriptAnalyzerOutput -FunctionText $FunctionText
    } else {
        Add-AifbLogMessage -Level "WRN" -Message "PSScriptAnalyzer is not installed so falling back on parsing directly with PS internals."
        try {
            [scriptblock]::Create($FunctionText) | Out-Null
        } catch {
            $innerExceptionErrors = $_.Exception.InnerException.Errors
            if($innerExceptionErrors) {
                Write-AifbFunctionParsingOutput $innerExceptionErrors[0].Message
            } else {
                Write-AifbFunctionParsingOutput "The script is invalid because of a $($_.FullyQualifiedErrorId)."
            }
        }
    }
}

function Test-AifbFunctionCommandletUsage {
    <#
        .SYNOPSIS
            This function tests the usage of commandlets in a PowerShell script.

        .DESCRIPTION
            The Test-AifbFunctionCommandletUsage function checks the usage of commandlets in a PowerShell script by analyzing the Abstract Syntax Tree (AST) of the script.
            For each commandlet found in the script, the function checks whether the commandlet is valid and whether any of the commandlet parameters are invalid.

        .PARAMETER FunctionText
            Specifies the text content of the PowerShell script to be tested.

        .EXAMPLE
            $FunctionText = Get-Content -Path "C:\Scripts\MyScript.ps1" -Raw
            Test-AifbFunctionCommandletUsage -ScriptAst $scriptAst

            This example tests the usage of commandlets in a PowerShell script.
        .NOTES
            This could likely be converted to a set of PSScriptAnalyzer custom rules https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/create-custom-rule?view=ps-modules
    #>
    [CmdletBinding()]
    param (
        # The name of the function to be tested
        [string] $FunctionName,
        # A function in a text format to be tested
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

        if($commandletName -eq $FunctionName) {
            # TODO validate recursive function parameters
            Write-Verbose "This is a recursive function call"
            continue
        }

        $command = Get-Command $commandletName -ErrorAction "SilentlyContinue"
        
        # Check online if no local command is found
        if($null -eq $command) {
            $command = Find-AifbCommandletOnline -CommandletName $commandletName
        }

        if($null -eq $command) {
            Write-AifbOverlay -Line $extent.StartLineNumber -Column $extent.StartColumnNumber -Text $extent.Text -ForegroundColor "Yellow"
            Write-AifbFunctionParsingOutput "The commandlet $commandletName cannot be found, use a different command or write your own implementation."
            return
        }
        
        # Check for missing parameters
        foreach($param in $commandletParameterNames) {
            if(![string]::IsNullOrEmpty($param)) {
                if(!$command.Parameters.ContainsKey($param)) {
                    Write-AifbOverlay -Line $extent.StartLineNumber -Column $extent.StartColumnNumber -Text $extent.Text -ForegroundColor "Yellow"
                    Write-AifbFunctionParsingOutput "The commandlet $commandletName does not take a parameter named $param, use another command."
                    return
                }
            }
        }

        # Check for unnamed parameters, these are harder to validate and makes a generated script less obvious as to what it does
        if($commandletParameterElements.Count -gt 0 -and $script:CommandletsExemptFromNamedParameters -notcontains $commandletName) {
            $previousElementWasParameterName = $false
            foreach($element in $commandletParameterElements) {
                if($element.GetType().Name -eq "CommandParameterAst") {
                    $previousElementWasParameterName = $true
                } else {
                    if(!$previousElementWasParameterName) {
                        Write-AifbOverlay -Line $extent.StartLineNumber -Column $extent.StartColumnNumber -Text $extent.Text -ForegroundColor "Yellow"
                        Write-AifbFunctionParsingOutput "Use a named parameter when passing $element to $commandletName."
                        return
                    }
                    $previousElementWasParameterName = $false
                }
            }
        }

        # Check named parameters haven't been specified more than once
        $duplicateParameters = $commandletParameterNames | Group-Object | Where-Object { $_.Count -gt 1 } 
        foreach($duplicateParameter in $duplicateParameters) {
            Write-AifbOverlay -Line $extent.StartLineNumber -Column $extent.StartColumnNumber -Text $extent.Text -ForegroundColor "Yellow"
            Write-AifbFunctionParsingOutput "The parameter $($duplicateParameter.Name) cannot be provided more than once to $commandletName."
            return
        }
        
        # Check at least one parameter set is satisfied if all parameters to this commandlet have been specified by name
        if($script:CommandletsExemptFromNamedParameters -notcontains $commandletName) {
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
                Write-AifbOverlay -Line $extent.StartLineNumber -Column $extent.StartColumnNumber -Text $extent.Text -ForegroundColor "Yellow"
                Write-AifbFunctionParsingOutput "Parameter set cannot be resolved using the specified named parameters for $commandletName."
                return
            }
        }
    }
}