. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/output-normalizer.ps1"

Describe "Normalize-AgentOutput" {

    It "should normalize Windows line endings to LF" {
        $result = Normalize-AgentOutput -Output "line1`r`nline2`rline3"
        Assert-Equal "line1`nline2`nline3" $result
    }

    It "should remove ANSI escape sequences while preserving markdown" {
        $escape = [char]27
        $input = "$escape[32m**Task:**$escape[0m`r`n- [ ] keep markdown"
        $result = Normalize-AgentOutput -Output $input

        Assert-Equal "**Task:**`n- [ ] keep markdown" $result
    }

    It "should trim leading shell banner noise" {
        $input = @(
            "Windows PowerShell",
            "Copyright (C) Microsoft Corporation. All rights reserved.",
            "Install the latest PowerShell for new features and improvements! https://aka.ms/PSWindows",
            "",
            "real output",
            "<promise>PLAN_COMPLETE</promise>",
            ""
        ) -join "`r`n"

        $result = Normalize-AgentOutput -Output $input
        Assert-Equal "real output`n<promise>PLAN_COMPLETE</promise>" $result
    }

    It "should preserve structured output lines after normalization" {
        $escape = [char]27
        $input = @(
            "$($escape)[90m{""type"":""result"",""subtype"":""success"",""is_error"":false,""result"":""Updated **plan**""}$($escape)[0m",
            '{"type":"completion","finalText":"<promise>PLAN_COMPLETE</promise>"}'
        ) -join "`r`n"

        $result = Normalize-AgentOutput -Output $input
        Assert-True ($result -match '^\{"type":"result"') "Expected JSON line to remain parseable"
        Assert-True ($result -match '\*\*plan\*\*') "Expected markdown to be preserved in structured output"
        Assert-True ($result -match 'PLAN_COMPLETE') "Expected completion signal to remain present"
    }
}

Get-TestResults