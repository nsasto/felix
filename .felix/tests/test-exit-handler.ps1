<#
.SYNOPSIS
Tests for exit handler utilities
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/exit-handler.ps1"

Describe "ConvertTo-Hashtable" {

    It "should convert PSCustomObject to hashtable" {
        $obj = [PSCustomObject]@{
            name  = "test"
            value = 42
        }
        
        $result = ConvertTo-Hashtable -InputObject $obj
        
        Assert-Equal "System.Collections.Hashtable" $result.GetType().FullName
        Assert-Equal "test" $result["name"]
        Assert-Equal 42 $result["value"]
    }

    It "should handle nested PSCustomObjects" {
        $obj = [PSCustomObject]@{
            outer = [PSCustomObject]@{
                inner = "nested"
            }
        }
        
        $result = ConvertTo-Hashtable -InputObject $obj
        
        Assert-Equal "System.Collections.Hashtable" $result.GetType().FullName
        Assert-Equal "System.Collections.Hashtable" $result["outer"].GetType().FullName
        Assert-Equal "nested" $result["outer"]["inner"]
    }

    It "should handle arrays of PSCustomObjects" {
        $obj = [PSCustomObject]@{
            items = @(
                [PSCustomObject]@{ id = 1 }
                [PSCustomObject]@{ id = 2 }
            )
        }
        
        $result = ConvertTo-Hashtable -InputObject $obj
        
        Assert-Equal "System.Collections.Hashtable" $result.GetType().FullName
        Assert-Equal 2 $result["items"].Count
        Assert-Equal "System.Collections.Hashtable" $result["items"][0].GetType().FullName
        Assert-Equal 1 $result["items"][0]["id"]
    }

    It "should return non-PSCustomObject unchanged" {
        $result = ConvertTo-Hashtable -InputObject "string"
        Assert-Equal "string" $result
        
        $result = ConvertTo-Hashtable -InputObject 42
        Assert-Equal 42 $result
        
        $result = ConvertTo-Hashtable -InputObject $null
        Assert-Null $result
    }

    It "should handle empty PSCustomObject" {
        $obj = [PSCustomObject]@{}
        
        $result = ConvertTo-Hashtable -InputObject $obj
        
        Assert-Equal "System.Collections.Hashtable" $result.GetType().FullName
        Assert-Equal 0 $result.Count
    }
}

Describe "Exit-FelixAgent" {

    It "should exit with provided exit code" {
        # This test verifies the function exists and can be called
        # Actual exit behavior cannot be easily tested in unit tests
        # We'll just verify the function is defined
        $functionExists = Get-Command Exit-FelixAgent -ErrorAction SilentlyContinue
        Assert-NotNull $functionExists
    }
}

