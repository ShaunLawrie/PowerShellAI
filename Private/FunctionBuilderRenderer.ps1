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
$script:FunctionVersion = 1
$script:FunctionLines = @()
$script:ShowLineNumberGutter = $true
$script:LineNumberGutterSize = 0

function Initialize-AifbRenderer {
    <#
        .SYNOPSIS
            Setup the function renderer at the current cursor position, this will be considered the top left of the function for each draw
    #>
    $currentPosition = $Host.UI.RawUI.CursorPosition
    $script:BufferScrollPosition = $Host.UI.RawUI.BufferSize.Height
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
        "*String*" { @{ R = 143; G = 185; B = 221 } }
        "Variable" { @{ R = 255; G = 255; B = 255 } }
        "Identifier" { @{ R = 110; G = 174; B = 231 } }
        default { @{ R = 200; G = 200; B = 200 } }
    }
    if($TokenFlags -like "*operator*" -or $TokenFlags -like "*keyword*") {
        $ForegroundRgb =  @{ R = 255; G = 123; B = 114 }
    }
    return $ForegroundRgb
}

function Test-AifbFunctionFitsInTerminal {
    <#
        .SYNOPSIS
            Given a function check whether it will fit within the dimensions of the current terminal window.
    #>
    param (
        # The text of the function to test
        [string] $FunctionText
    )
    return ($script:FunctionTopLeft.Y + $FunctionText.Split("`n").Count + 1 + $script:LogMessagesMaxCount + 10) -lt $Host.UI.RawUI.WindowSize.Height
}

function Write-AifbFunctionOutput {
    <#
        .SYNOPSIS
            This function writes a function to the terminal with optional syntax highlighting

        .DESCRIPTION
            Using some cursor manipulation and Write-Host this re-renders overtop of itself and clears the rest of the text on the terminal.
            Then the function text is drawn and the log data is written underneath it.
    #>
    param (
        # The text of the function to render
        [string] $FunctionText,
        # Prompt info
        [string] $Prompt,
        # Whether to syntax highlight the function
        [switch] $SyntaxHighlight,
        # The background color for the code block
        [hashtable] $BackgroundRgb = $script:RendererBackground,
        # Don't output the log viewer
        [switch] $NoLogMessages
    )

    $FunctionText = $FunctionText.Trim() + "`n`n<#`nAIFunctionBuilder Iteration $([int]$script:FunctionVersion++)`n$Prompt`n#>"
    $script:LineNumberGutterSize = $FunctionText.Split("`n").Count.ToString().Length + 1
    $script:FunctionLines = @()

    # Write it all to the terminal and don't overwrite on every render in verbose mode, this makes debugging easier
    if($VerbosePreference -ne "SilentlyContinue") {
        Write-Verbose "Function text:`n$FunctionText"
        return
    }

    # Make sure the script will fit in the function editor UI
    while(!(Test-AifbFunctionFitsInTerminal -FunctionText $FunctionText)) {
        [Console]::SetCursorPosition($script:FunctionTopLeft.X, $script:FunctionTopLeft.Y)
        Write-Warning "Zoom out to fit the function in your terminal window, the function length exceeds the height of your terminal"
        [Console]::SetCursorPosition($script:FunctionTopLeft.X, $script:FunctionTopLeft.Y)
        Start-Sleep -Seconds 1
    }
    
    # Work out the width of the console minus the line-number gutter
    $gutterSize = 0
    if($script:ShowLineNumberGutter) {
        $gutterSize = $script:LineNumberGutterSize
    }
    $consoleWidth = $Host.UI.RawUI.WindowSize.Width - $gutterSize

    try {
        # Put the cursor position at the top left of the function
        [Console]::CursorVisible = $false
        [Console]::SetCursorPosition($script:FunctionTopLeft.X, $script:FunctionTopLeft.Y)
        
        $totalLinesRendered = 0
        $functionLineNumber = 1
        $renderedFunctionLines = @()
        $backgroundColorEscapeCode = "$([Char]27)[48;2;{0};{1};{2}m" -f $BackgroundRgb.R, $BackgroundRgb.G, $BackgroundRgb.B
        if($null -ne $FunctionText) {
            $renderedFunctionLines = $FunctionText.Split("`n")
            foreach($line in $renderedFunctionLines) {
                $currentLine = @()
                if($line.Length -gt $consoleWidth) {
                    $wrappedLineSegments = ($line | Select-String -Pattern ".{1,$consoleWidth}" -AllMatches).Matches.Value
                    $wrappedLineSegmentNumber = 0
                    foreach($wrappedLineSegment in $wrappedLineSegments) {
                        if($script:ShowLineNumberGutter) {
                            $gutterText = " "
                            if($wrappedLineSegmentNumber -eq 0) {
                                $gutterText = $functionLineNumber.ToString()
                            }
                            Write-Host -NoNewline -ForegroundColor DarkGray -BackgroundColor Black $gutterText.PadRight($gutterSize)
                        }
                        Write-Host -ForegroundColor DarkGray ($backgroundColorEscapeCode + $wrappedLineSegment + (" " * ($consoleWidth - $wrappedLineSegment.Length)))
                        $currentLine += $wrappedLineSegment
                        $wrappedLineSegmentNumber++
                        $totalLinesRendered++
                    }
                } else {
                    if($script:ShowLineNumberGutter) {
                        Write-Host -NoNewline -ForegroundColor DarkGray -BackgroundColor Black $functionLineNumber.ToString().PadRight($gutterSize)
                    }
                    Write-Host -ForegroundColor DarkGray ($backgroundColorEscapeCode + $line + (" " * ($consoleWidth - $line.Length - 1)))
                    $currentLine += $line
                    $totalLinesRendered++
                }
                if(!$SyntaxHighlight) {
                    Start-Sleep -Milliseconds 20
                }
                $script:FunctionLines += ,$currentLine
                $functionLineNumber++
            }
        } else {
            Write-Error "No function was provided to the renderer" -ErrorAction "Stop"
        }

        # Clear text formatting
        Write-Host -NoNewline "$([Char]27)[0m"

        # Add a space between the function and anything below it
        $endOfFunctionPosition = $Host.UI.RawUI.CursorPosition
        Write-Host (" " * $Host.UI.RawUI.WindowSize.Width)

        # Write overtop of the function with some basic colors
        if($SyntaxHighlight) {
            $tokens = @()
            [System.Management.Automation.Language.Parser]::ParseInput($FunctionText, [ref]$tokens, [ref]$null) | Out-Null

            # Color all tokens
            foreach($token in $tokens) {
                if([string]::IsNullOrWhiteSpace($token.Text)) {
                    continue
                }
                $ForegroundRgb = Get-AifbTokenColor -Kind $token.Kind -TokenFlags $token.TokenFlags
                Write-AifbOverlay -Line $token.Extent.StartLineNumber -Column $token.Extent.StartColumnNumber -Text $token.Text -ForegroundRgb $ForegroundRgb -BackgroundRgb $BackgroundRgb
                # Do one level deep nested token parsing to make string interpolation look good
                $nestedTokens = ($token | Where-Object { $_.Kind -like "*StringExpandable" -and $_.NestedTokens }).NestedTokens
                foreach($nestedToken in $nestedTokens) {
                    $ForegroundRgb = Get-AifbTokenColor -Kind $nestedToken.Kind -TokenFlags $nestedToken.TokenFlags
                    Write-AifbOverlay -Line $nestedToken.Extent.StartLineNumber -Column $nestedToken.Extent.StartColumnNumber -Text $nestedToken.Text -ForegroundRgb $ForegroundRgb -BackgroundRgb $BackgroundRgb
                }
            }
        }

        [Console]::SetCursorPosition($endOfFunctionPosition.X, $endOfFunctionPosition.Y)
        3..($Host.UI.RawUI.WindowSize.Height - $script:FunctionTopLeft.Y - $totalLinesRendered) | Foreach-Object {
            Write-Host (" " * $Host.UI.RawUI.WindowSize.Width)
        }
        [Console]::SetCursorPosition($endOfFunctionPosition.X, $endOfFunctionPosition.Y + 1)
        $script:LogMessagesTopLeft = $Host.UI.RawUI.CursorPosition
        if(!$NoLogMessages) {
            Write-AifbLogMessages
        }
    } catch {
        throw $_
    } finally {
        [Console]::CursorVisible = $true
    }
}

function Write-AifbOverlay {
    <#
        .SYNOPSIS
            Writes colored text to the console at a specific line and column.
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

    Start-Sleep -Milliseconds 5

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

    $gutterSize = 0
    if($script:ShowLineNumberGutter) {
        $gutterSize = $script:LineNumberGutterSize
    }
    $consoleWidth = $Host.UI.RawUI.WindowSize.Width - $gutterSize
    
    [Console]::CursorVisible = $false
    $initialCursorPosition = $Host.UI.RawUI.CursorPosition
    try {
        # Get the vertical offset for all lines before this one, this could include lines that had their content wrapped
        $precedingWrappedLinesCount = 0
        if($Line -ge 2) {
            $precedingWrappedLinesCount = ($script:FunctionLines[0..($Line - 2)] | Measure-Object -Sum -Property Count).Sum
        }
        
        # Multiline tokens need to be split before rendering to handle the gutter indent
        $tokenLinesRendered = 0
        foreach($tokenLine in $Text.Split("`n")) {
            # Overruns are parts of this token that extend beyond the width of the terminal and need their own line wrapping
            $overrunText = @()
            # This token might be on a wrapped part of this line, make sure to find the correct start point
            $columnIndex = $Column - 1
            $wrappedLineIndex = [Math]::Floor($columnIndex / $consoleWidth)
            $x = ($columnIndex % $consoleWidth) + $gutterSize
            # Multiline tokens need x reset to the start of the line to wrap properly like heredoc strings
            if($tokenLinesRendered -gt 0) {
                $x = $gutterSize
            }
            $y = $script:FunctionTopLeft.Y + $precedingWrappedLinesCount + $wrappedLineIndex
            # Handle token running beyond the width of the terminal
            if(($x + $tokenLine.Length) -gt ($consoleWidth + $gutterSize)) {
                # First line is special because it starts at a random point, not at the start
                $fullTokenLine = $tokenLine
                $endOfTextOnCurrentLine = $consoleWidth - $x + $gutterSize
                $tokenLine = $tokenLine.Substring(0, $endOfTextOnCurrentLine)
                $remainingText = $fullTokenLine.Substring($endOfTextOnCurrentLine, $fullTokenLine.Length - $endOfTextOnCurrentLine)
                if($remainingText.Length -gt $consoleWidth) {
                    $overrunText += ($remainingText | Select-String "(.{1,$consoleWidth})+").Matches.Groups[1].Captures.Value
                } else {
                    $overrunText += $remainingText
                }
            }
            
            # Print the first line of this token
            [Console]::SetCursorPosition($x, $y + [int]$tokenLinesRendered++)
            Write-Host @writeHostParams ($colorEscapeCode + $tokenLine)
            Write-Host -NoNewline "$([Char]27)[0m"

            # Print any parts of this line that extended beyond the width of the terminal
            foreach($overrun in $overrunText) {
                [Console]::SetCursorPosition($gutterSize, $y + [int]$tokenLinesRendered++)
                Write-Host @writeHostParams ($colorEscapeCode + $overrun)
                Write-Host -NoNewline "$([Char]27)[0m"
            }
        }
    } catch {
        throw $_
    } finally {
        [Console]::CursorVisible = $true
        [Console]::SetCursorPosition($initialCursorPosition.X, $initialCursorPosition.Y)
    }
}

function Add-AifbLogMessage {
    <#
        .SYNOPSIS
            Add a log message to the function builder log.
    #>
    param (
        # The message to add
        [string] $Message,
        # The level to log it at
        [ValidateSet("INF", "WRN", "ERR")]
        [string] $Level = "INF",
        # Whether to skip rendering the latest log to the terminal
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
    <#
        .SYNOPSIS
            Given a syntax token provide a color based on its type.
    #>
    if($VerbosePreference) {
        return
    }

    $consoleWidth = $Host.UI.RawUI.WindowSize.Width
    [Console]::SetCursorPosition($script:LogMessagesTopLeft.X, $script:LogMessagesTopLeft.Y)
    $script:LogMessages | Foreach-Object {
        $logPrefix = "$($_.Date) $($_.Level.PadRight(4))"
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
                $message = $logPrefix + $line
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