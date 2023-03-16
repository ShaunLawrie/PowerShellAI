# TODO Make a real code block renderer instead of this cursor manipulating write-host hackery

$script:LogMessages = [System.Collections.Queue]::new()
$script:LogMessageColors = @{
    "INF" = "White"
    "WRN" = "Yellow"
    "ERR" = "Red"
}
$script:LogMessagesMaxCount = 8
$script:FunctionTopLeft = @{X = 0; Y = 0}
$script:LogMessagesTopLeft = @{X = 0; Y = 0}
$script:RendererBackground = @{ R = 35; G = 35; B = 35; }
$script:FunctionVersion = 0

function Initialize-AifbRenderer {
    <#
        .SYNOPSIS
            Setup the function renderer at the current cursor position, this will be considered the top left of the function for each draw
    #>
    $currentPosition = $Host.UI.RawUI.CursorPosition
    $script:FunctionTopLeft.X = $currentPosition.X
    $script:FunctionTopLeft.Y = $currentPosition.Y + 1
    $script:LogMessages = [System.Collections.Queue]::new()
    $script:FunctionVersion = 0
}

function Write-AifbFunctionParsingOutput {
    <#
        .SYNOPSIS
            Writes parsing output to the output stream and also to the renderer log output as errors.
    #>
    [CmdletBinding()]
    param (
        # The message to log and format
        [string] $Message
    )
    Add-AifbLogMessage -Level "WRN" -Message $Message
    Write-Output " - $Message"
}

function Get-AifbTokenColor {
    <#
        .SYNOPSIS
            Given a syntax token provide a color based on its type.
    #>
    param (
        # The kind of token identified by the PowerShell language parser
        [System.Management.Automation.Language.TokenKind] $Kind,
        # TokenFlags identified by the PowerShell language parser
        [System.Management.Automation.Language.TokenFlags] $TokenFlags
    )
    $ForegroundRgb = switch -wildcard ($Kind) {
        "Function" { @{ R = 255; G = 123; B = 114 } }
        "Generic" { @{ R = 199; G = 159; B = 252 } }
        "String*" { @{ R = 143; G = 185; B = 221 } }
        "Variable" { @{ R = 255; G = 255; B = 255 } }
        "Identifier" { @{ R = 110; G = 174; B = 231 } }
        default { @{ R = 200; G = 200; B = 200 } }
    }
    if($TokenFlags -like "*operator*" -or $TokenFlags -like "*keyword*") {
        $ForegroundRgb =  @{ R = 255; G = 123; B = 114 }
    }
    return $ForegroundRgb
}

function Write-AifbFunctionOutput {
    <#
        .SYNOPSIS
            This function writes a function to the terminal with optional syntax highlighting

        .DESCRIPTION
            Using some cursor manipulation and Write-Host this re-renders overtop of itself and clears the rest of the text on the terminal.
            Then the function text is drawn and the log data is written underneath it.
    #>
    [CmdletBinding()]
    param (
        # The text of the function to render
        [string] $FunctionText,
        # Whether to syntax highlight the function
        [switch] $SyntaxHighlight,
        # The background color for the code block
        [hashtable] $BackgroundRgb = $script:RendererBackground
    )

    $script:FunctionVersion++
    $FunctionText = $FunctionText + "`n`n# AIFunctionBuilder Iteration $($script:FunctionVersion)"
    $consoleWidth = $Host.UI.RawUI.WindowSize.Width

    # Write it all to the terminal and don't overwrite on every render in verbose mode, this makes debugging easier
    if($VerbosePreference -ne "SilentlyContinue") {
        Write-Verbose "Function text:`n$FunctionText"
        return
    }

    # Initialise cursor position at the top left of the function
    [Console]::SetCursorPosition($script:FunctionTopLeft.X, $script:FunctionTopLeft.Y)
    
    $outputLines = @()
    $colorEscapeCode = "$([Char]27)[48;2;{0};{1};{2}m" -f $BackgroundRgb.R, $BackgroundRgb.G, $BackgroundRgb.B
    if($null -ne $FunctionText) {
        $outputLines = $FunctionText.Split("`n")
        foreach($line in $outputLines) {
            if($line.Length -gt $consoleWidth) {
                $line = $line.Substring(0, ($consoleWidth - 3)) + "..."
            }
            Write-Host -ForegroundColor DarkGray ($colorEscapeCode + $line + (" " * ($consoleWidth - $line.Length)))
            if(!$SyntaxHighlight) {
                Start-Sleep -Milliseconds 20
            }
        }
    } else {
        Write-Error "No function was provided to the renderer" -ErrorAction "Stop"
    }

    # Clear text formatting
    Write-Host -NoNewline "$([Char]27)[0m"

    # Add a space between the function and the log
    $endOfFunctionPosition = $Host.UI.RawUI.CursorPosition
    Write-Host (" " * $consoleWidth)

    # Write the function with some basic colors
    if($SyntaxHighlight) {
        $tokens = @()
        [System.Management.Automation.Language.Parser]::ParseInput($FunctionText, [ref]$tokens, [ref]$null) | Out-Null

        foreach($token in $tokens) {
            $ForegroundRgb = Get-AifbTokenColor -Kind $token.Kind -TokenFlags $token.TokenFlags
            Write-AifbOverlay -Line $token.Extent.StartLineNumber -Column $token.Extent.StartColumnNumber -Text $token.Text -ForegroundRgb $ForegroundRgb -BackgroundRgb $BackgroundRgb
            $nestedTokens = ($token | Where-Object { $_.Kind -eq "StringExpandable" -and $_.NestedTokens }).NestedTokens
            # Do one level deep nested token parsing to make string interpolation look good
            foreach($nestedToken in $nestedTokens) {
                $ForegroundRgb = Get-AifbTokenColor -Kind $nestedToken.Kind -TokenFlags $nestedToken.TokenFlags
                Write-AifbOverlay -Line $nestedToken.Extent.StartLineNumber -Column $nestedToken.Extent.StartColumnNumber -Text $nestedToken.Text -ForegroundRgb $ForegroundRgb -BackgroundRgb $BackgroundRgb
            }
        }
    }

    [Console]::SetCursorPosition($endOfFunctionPosition.X, $endOfFunctionPosition.Y)
    5..($Host.UI.RawUI.WindowSize.Height - $script:FunctionTopLeft.Y - $outputLines.Count) | Foreach-Object {
        Write-Host (" " * $consoleWidth)
    }
    
    [Console]::SetCursorPosition($endOfFunctionPosition.X, $endOfFunctionPosition.Y + 1)
    $script:LogMessagesTopLeft = $Host.UI.RawUI.CursorPosition
    Write-AifbLogMessages
}

function Write-AifbOverlay {
    <#
        .SYNOPSIS
            Writes text to the console at a specific line and column.
        .DESCRIPTION
            Writes text to the console at a specific line and column.
            This function does not use zero based indexing, rows start at 1 and columns start at 1 because it's how they're represented in a text editor.
            This is used to hack together syntax highlighting.
        .PARAMETER Line
            The line number to write to.
        .PARAMETER Text
            The text to write.
        .PARAMETER ForegroundColor
            The foreground color to use.
        .PARAMETER BackgroundColor
            The background color to use.
        .PARAMETER Column
            The column to write to.
    #>
    [CmdletBinding()]
    param (
        [string] $Text,
        [string] $ForegroundColor = $null,
        [string] $BackgroundColor = $null,
        [hashtable] $ForegroundRgb = $null,
        [hashtable] $BackgroundRgb = $script:RendererBackground,
        [ValidateRange(1, [int]::MaxValue)]
        [int] $Line,
        [ValidateRange(1, [int]::MaxValue)]
        [int] $Column = 1
    )

    # Write it all to the terminal and don't overwrite on every render, this makes debugging easier
    if($VerbosePreference -ne "SilentlyContinue") {
        Write-Verbose "Overlay text for line $Line, column ${Column}: $FunctionText"
        return
    }

    $initialCursorPosition = $Host.UI.RawUI.CursorPosition
    try {
        [Console]::CursorVisible = $false
        $x = $script:FunctionTopLeft.X + $Column - 1
        $y = $script:FunctionTopLeft.Y + $Line - 1
        if(($x + $Text.Length) -gt ($Host.UI.RawUI.WindowSize.Width - 3)) {
            Write-Verbose "Skipping writing an overlay because the line is wider than the console"
            return
        }
        [Console]::SetCursorPosition($x, $y)

        $writeHostParams = @{
            "NoNewline" = $true
        }

        if($ForegroundColor) {
            $writeHostParams["ForegroundColor"] = $ForegroundColor
        }
        if($BackgroundColor) {
            $writeHostParams["BackgroundColor"] = $BackgroundColor
        }

        $colorEscapeCode = ""
        if($ForegroundRgb) {
            $colorEscapeCode += "$([Char]27)[38;2;{0};{1};{2}m" -f $ForegroundRgb.R, $ForegroundRgb.G, $ForegroundRgb.B
        }
        if($BackgroundRgb) {
            $colorEscapeCode += "$([Char]27)[48;2;{0};{1};{2}m" -f $BackgroundRgb.R, $BackgroundRgb.G, $BackgroundRgb.B
        }

        foreach($letter in $Text.ToCharArray()) {
            Write-Host @writeHostParams ($colorEscapeCode + $letter)
        }
        Write-Host -NoNewline "$([Char]27)[0m"
    } finally {
        [Console]::CursorVisible = $true
        [Console]::SetCursorPosition($initialCursorPosition.X, $initialCursorPosition.Y)
    }
}

function Add-AifbLogMessage {
    [CmdletBinding()]
    param (
        [string] $Message,
        [ValidateSet("INF", "WRN", "ERR")]
        [string] $Level = "INF",
        [switch] $NoRender
    )

    Write-Verbose "$Level $Message"

    $logItem = @{
        Date = (Get-Date).ToString("HH:mm:ss")
        Message = $Message
        Level = $Level
    }
    $script:LogMessages.Enqueue($logItem)

    if($script:LogMessages.Count -gt $script:LogMessagesMaxCount) {
        $script:LogMessages.Dequeue() | Out-Null
    }

    if(!$NoRender) {
        Write-AifbLogMessages
    }
}

function Write-AifbLogMessages {
    [CmdletBinding()]
    param()

    if($VerbosePreference) {
        return
    }

    $consoleWidth = $Host.UI.RawUI.WindowSize.Width
    [Console]::SetCursorPosition($script:LogMessagesTopLeft.X, $script:LogMessagesTopLeft.Y)
    $script:LogMessages | Foreach-Object {
        $logPrefix = "$($_.Date) $($_.Level.PadRight(5))"
        $line = $_.Message -replace "`n", ". "
        $messageWidth = $consoleWidth - $logPrefix.Length - 1
        if($line.Length -gt $messageWidth) {
            $lines = ($line | Select-String "(.{1,$messageWidth})+").Matches.Groups[1].Captures.Value
        } else {
            $lines = @($line)
        }
        $lineNumber = 0
        foreach($line in $lines) {
            if($lineNumber -eq 0) {
                $message = $logPrefix + " $line"
                Write-Host -ForegroundColor $script:LogMessageColors[$_.Level] ($message + (" " * ($consoleWidth - $message.Length)))
            } else {
                $message = (" " * $logPrefix.Length) + " $line"
                Write-Host -ForegroundColor $script:LogMessageColors[$_.Level] ($message + (" " * ($consoleWidth - $message.Length)))
            }
            $lineNumber++
        }   
    }
    Write-Host ""
}