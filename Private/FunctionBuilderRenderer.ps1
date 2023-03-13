# TODO MAKE A REAL RENDERING BUFFER INSTEAD OF WRITE-HOST HACKERY

$script:LogMessages = [System.Collections.Queue]::new()
$script:LogMessageColors = @{
    "INFO" = "White"
    "WARN" = "Yellow"
    "ERROR" = "Red"
}
$script:LogMessagesMaxCount = 10
$script:FunctionTopLeft = @{X = 0; Y = 0}
$script:LogMessagesTopLeft = @{X = 0; Y = 0}

function Initialize-Renderer {
    $currentPosition = $Host.UI.RawUI.CursorPosition
    $script:FunctionTopLeft.X = $currentPosition.X
    $script:FunctionTopLeft.Y = $currentPosition.Y + 1
    $script:LogMessages = [System.Collections.Queue]::new()
    Add-LogMessage "Initialized function renderer at position [$($script:FunctionTopLeft.X), $($script:FunctionTopLeft.Y)]" -NoRender
}

function Write-FunctionParsingOutput {
    <#
        .SYNOPSIS
            Writes parsing output to the output stream and also to the renderer log output as errors.
    #>
    param (
        [string] $Message
    )
    Add-LogMessage -Level "WARN" -Message $Message
    Write-Output " - $Message"
}

function Write-FunctionOutput {
    param (
        [string] $Stage,
        [string] $FunctionText,
        [switch] $SyntaxHighlight
    )

    if($global:VerbosePreference -eq "Continue") {
        Write-Verbose $Stage
        Write-Verbose $FunctionText
        Write-LogMessages
        return
    }

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
        Write-Host -ForegroundColor DarkGray "$([Char]27)[48;2;25;25;25mNo function was provided`n"
    }

    Write-Host -NoNewline "$([Char]27)[0m"
    # Clear the rest of the window
    $endOfFunctionPosition = $Host.UI.RawUI.CursorPosition

    Write-Host (" " * $Host.UI.RawUI.WindowSize.Width)

    if($SyntaxHighlight) {
        $tokens = @()
        [System.Management.Automation.Language.Parser]::ParseInput($FunctionText, [ref]$tokens, [ref]$null) | Out-Null

        foreach($token in $tokens) {
            $TokenColor = switch -wildcard ($token.Kind) {
                "Function" { "DarkRed" }
                "Generic" { "Magenta" }
                "String*" { "Cyan" }
                "Variable" { "Cyan" }
                "Identifier" { "Yellow" }
                default { "White" }
            }
            if($token.TokenFlags -like "*operator*" -or $token.TokenFlags -like "*keyword*") {
                $TokenColor = "Red"
            }
            Write-Overlay -Line $token.Extent.StartLineNumber -Column $token.Extent.StartColumnNumber -Text $token.Text -ForegroundColor $TokenColor
        }
    }

    [Console]::SetCursorPosition($endOfFunctionPosition.X, $endOfFunctionPosition.Y)
    5..($Host.UI.RawUI.WindowSize.Height - $script:FunctionTopLeft.Y - $OutputLines.Count) | Foreach-Object {
        Write-Host (" " * $Host.UI.RawUI.WindowSize.Width)
    }
    
    [Console]::SetCursorPosition($endOfFunctionPosition.X, $endOfFunctionPosition.Y + 1)
    $script:LogMessagesTopLeft = $Host.UI.RawUI.CursorPosition
    Write-LogMessages
}

function Write-Overlay {
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

function Add-LogMessage {
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
        Write-LogMessages
    }
}

function Write-LogMessages {

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