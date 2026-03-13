<#
.SYNOPSIS
Text formatting and processing utilities

.DESCRIPTION
Provides functions for formatting text output:
- Format-PlainText: Convert markdown to plain text (for git commits, logs)
- Format-MarkdownText: Convert markdown to ANSI-styled terminal output
#>

function Format-PlainText {
    <#
    .SYNOPSIS
    Formats text by converting escape sequences and stripping markdown
    
    .DESCRIPTION
    Converts markdown-style text to plain text suitable for git commits and logs:
    - Converts literal escape sequences (\n, \t, \", \')
    - Strips markdown formatting (**bold**, *italic*)
    - Returns clean plain text without any formatting codes
    
    .PARAMETER Text
    The text to format
    
    .EXAMPLE
    Format-PlainText -Text "**Task:** Fix bug\n\n- Item 1\n- Item 2"
    Returns: "Task: Fix bug
    
    - Item 1
    - Item 2"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )
    
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }
    
    # Convert literal escape sequences to actual characters
    $formatted = $Text -replace '\\n', "`n"
    $formatted = $formatted -replace '\\t', "`t"
    $formatted = $formatted -replace '\\"', '"'
    $formatted = $formatted -replace "\\'", "'"
    $formatted = $formatted -replace '\\r', "`r"
    
    # Strip markdown formatting
    $formatted = $formatted -replace '\*\*([^\*]+)\*\*', '$1'  # **bold** → bold
    $formatted = $formatted -replace '\*([^\*]+)\*', '$1'      # *italic* → italic
    $formatted = $formatted -replace '`([^`]+)`', '$1'         # `code` → code
    
    return $formatted
}

function Format-MarkdownText {
    <#
    .SYNOPSIS
    Formats markdown-style text for terminal display with ANSI colors
    
    .DESCRIPTION
    Renders markdown-style formatting with ANSI escape codes:
    - **bold** text → ANSI bold/bright
    - Bullet points and lists with colored markers
    - Proper line breaks (replaces \n)
    - UTF-8 encoding fixes for PowerShell 5.1
    
    .PARAMETER Text
    The text to format
    
    .EXAMPLE
    Format-MarkdownText -Text "**Task:** Complete\n- Item 1\n- Item 2"
    Returns text with ANSI color codes for terminal display
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )
    
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }
    
    # Define ANSI color codes (compatible with PowerShell 5.1)
    $esc = if ($PSVersionTable.PSVersion.Major -ge 7) { "`e" } else { [char]0x1b }
    $colors = @{
        Reset        = "$esc[0m"
        Bold         = "$esc[1m"
        Cyan         = "$esc[36m"
        BrightWhite  = "$esc[97m"
    }
    
    # Replace literal \n with actual newlines
    $formatted = $Text -replace '\\n', "`n"
    
    # Fix UTF-8 encoding issues (PowerShell 5.1 console rendering)
    $formatted = $formatted -replace '├ó┼ôÔÇª', '✅'
    $formatted = $formatted -replace '├ó┼ôÔîÅ', '❌'
    $formatted = $formatted -replace 'Ôêö', '✅'
    $formatted = $formatted -replace 'Ôêù', '❌'
    $formatted = $formatted -replace 'ÔêÅ', '✓'
    $formatted = $formatted -replace 'ÔØ×', '✓'
    
    # Replace **bold** with ANSI bold
    $formatted = $formatted -replace '\*\*([^\*]+)\*\*', "$($colors.Bold)$($colors.BrightWhite)`$1$($colors.Reset)"
    
    # Add indentation to bullet points
    $formatted = $formatted -replace '(?m)^- ', "  $($colors.Cyan)•$($colors.Reset) "
    $formatted = $formatted -replace '(?m)^\* ', "  $($colors.Cyan)•$($colors.Reset) "
    
    # Indent numbered lists
    $formatted = $formatted -replace '(?m)^(\d+)\. ', "  $($colors.Cyan)`$1.$($colors.Reset) "
    
    return $formatted
}
