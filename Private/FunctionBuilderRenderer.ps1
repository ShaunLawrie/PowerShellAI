# TODO MAKE A REAL RENDERING BUFFER INSTEAD OF WRITE-HOST HACKERY

$script:LogMessages = [System.Collections.Queue]::new()
$script:LogMessageColors = @{
    "INFO" = "White"
    "WARN" = "Yellow"
    "ERROR" = "Red"
}
$script:LogMessagesMaxCount = 8
$script:FunctionTopLeft = @{X = 0; Y = 0}
$script:LogMessagesTopLeft = @{X = 0; Y = 0}

function Initialize-AifbRenderer {
    <#
        .SYNOPSIS
            Setup the function renderer at the current cursor position, this will be considered the top left of the function for each draw
    #>
    $currentPosition = $Host.UI.RawUI.CursorPosition
    $script:FunctionTopLeft.X = $currentPosition.X
    $script:FunctionTopLeft.Y = $currentPosition.Y + 1
    $script:LogMessages = [System.Collections.Queue]::new()
    Add-AifbLogMessage "Initialized function renderer at position [$($script:FunctionTopLeft.X), $($script:FunctionTopLeft.Y)]" -NoRender
}

function Write-AifbFunctionParsingOutput {
    <#
        .SYNOPSIS
            Writes parsing output to the output stream and also to the renderer log output as errors.
    #>
    param (
        # The message to log and format
        [string] $Message
    )
    Add-AifbLogMessage -Level "WARN" -Message $Message
    Write-Output " - $Message"
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
        [switch] $SyntaxHighlight
    )

    # Write it all to the terminal and don't overwrite on every render, this makes debugging easier
    if($VerbosePreference -ne "SilentlyContinue") {
        Write-Verbose $Stage
        Write-Verbose $FunctionText
        Write-AifbLogMessages
        return
    }

    # Initialise cursor position at the top left of the function
    [Console]::SetCursorPosition($script:FunctionTopLeft.X, $script:FunctionTopLeft.Y)
    
    $OutputLines = @()
    if($null -ne $FunctionText) {
        $OutputLines = $FunctionText.Split("`n")
        foreach($line in $OutputLines) {
            Write-Host -ForegroundColor DarkGray ("$([Char]27)[48;2;25;25;25m" + $line + (" " * ($Host.UI.RawUI.WindowSize.Width - $line.Length)))
            if(!$SyntaxHighlight) {
                Start-Sleep -Milliseconds 20
            }
        }
    } else {
        Write-Error "No function was provided to the renderer"
    }

    # Clear text formatting
    Write-Host -NoNewline "$([Char]27)[0m"

    # Add a space between the function and the log
    $endOfFunctionPosition = $Host.UI.RawUI.CursorPosition
    Write-Host (" " * $Host.UI.RawUI.WindowSize.Width)

    # Write the function with some basic colors
    if($SyntaxHighlight) {
        $tokens = @()
        [System.Management.Automation.Language.Parser]::ParseInput($FunctionText, [ref]$tokens, [ref]$null) | Out-Null

        foreach($token in $tokens) {
            $TokenColor = switch -wildcard ($token.Kind) {
                "Function" { "$([Char]27)[48;2;255;123;114m)" }
                "Generic" { "$([Char]27)[48;2;199;159;242m)" }
                "String*" { "$([Char]27)[48;2;143;185;221m)" }
                "Variable" { "$([Char]27)[48;2;255;255;255m)" }
                "Identifier" { "$([Char]27)[48;2;110;174;231m)" }
                default { "$([Char]27)[48;2;220;220;220m)" }
            }
            if($token.TokenFlags -like "*operator*" -or $token.TokenFlags -like "*keyword*") {
                $TokenColor = "$([Char]27)[48;2;255;123;114m)"
            }
            Write-AifbOverlay -Line $token.Extent.StartLineNumber -Column $token.Extent.StartColumnNumber -Text ($TokenColor + $token.Text)
        }
    }

    [Console]::SetCursorPosition($endOfFunctionPosition.X, $endOfFunctionPosition.Y)
    5..($Host.UI.RawUI.WindowSize.Height - $script:FunctionTopLeft.Y - $OutputLines.Count) | Foreach-Object {
        Write-Host (" " * $Host.UI.RawUI.WindowSize.Width)
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
    param (
        [string] $Text,
        [string] $ForegroundColor,
        [string] $BackgroundColor = $null,
        [ValidateRange(1, [int]::MaxValue)]
        [int] $Line,
        [ValidateRange(1, [int]::MaxValue)]
        [int] $Column = 1
    )

    if($global:VerbosePreference -eq "Continue") {
        Write-Error $Text
        return
    }

    $initialCursorPosition = $Host.UI.RawUI.CursorPosition
    try {
        [Console]::CursorVisible = $false
        $x = $script:FunctionTopLeft.X + $Column - 1
        $y = $script:FunctionTopLeft.Y + $Line - 1
        [Console]::SetCursorPosition($x, $y)
        foreach($letter in $Text.ToCharArray()) {
            if($BackgroundColor) {
                Write-Host -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor -NoNewline $letter
            } else {
                Write-Host -ForegroundColor $ForegroundColor -NoNewline ("$([Char]27)[48;2;25;25;25m" + $letter)
            }
            Write-Host -NoNewline "$([Char]27)[0m"
        }
    } finally {
        [Console]::CursorVisible = $true
        [Console]::SetCursorPosition($initialCursorPosition.X, $initialCursorPosition.Y)
    }
}

function Add-AifbLogMessage {
    param (
        [string] $Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string] $Level = "INFO",
        [switch] $NoRender
    )

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

    if($global:VerbosePreference) {
        $script:LogMessages | Foreach-Object {
            Write-Verbose "$($_.Date) $($_.Level) $($_.Message)"
        }
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
                Write-Host -ForegroundColor $script:LogMessageColors[$_.Level] ($message + (" " * ($Host.UI.RawUI.WindowSize.Width - $message.Length)))
            } else {
                $message = (" " * $logPrefix.Length) + " $line"
                Write-Host -ForegroundColor $script:LogMessageColors[$_.Level] ($message + (" " * ($Host.UI.RawUI.WindowSize.Width - $message.Length)))
            }
            $lineNumber++
        }   
    }
    Write-Host ""
}