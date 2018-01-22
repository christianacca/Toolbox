$projectRoot = Resolve-Path "$PSScriptRoot\.."
$moduleRoot = Split-Path (Resolve-Path "$projectRoot\*\*.psm1")
$moduleName = Split-Path $moduleRoot -Leaf
Describe 'Add-Hostnames' {
    BeforeAll {
        Import-Module (Join-Path $moduleRoot "$moduleName.psm1") -force 
    }

    AfterAll {
        Remove-Hostnames foobar -EA 'Continue'
        1..10 | ForEach-Object { 
            @("foo$_") | Remove-Hostnames -EA 'Continue'
        }
        Remove-Module $moduleName -Force
    }

    It 'Can add one hostfile' {
        # when
        Add-Hostnames 127.0.0.1 foobar

        # then
        'foobar' | Should -BeIn (Get-Hostnames | Select -Exp Hostname)
    }
    
    
    It 'Should not error on write lock' {
        # when
        1..10 | ForEach-Object { 
            @("foo$_") | Add-Hostnames "127.0.0.$_" 
        }

        # then
        (1..10 | %{ "foo$_"}) | Should -BeIn (Get-Hostnames | Select -Exp Hostname)
    }
}