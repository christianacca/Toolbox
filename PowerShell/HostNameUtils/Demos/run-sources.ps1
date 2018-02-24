#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$currentDirectory = $args[0]

# import module from source code
$moduleName = 'HostNameUtils'
$modulePath = Join-Path $PSScriptRoot "..\$moduleName" -Resolve
Import-Module $modulePath -EA Stop

Set-Location $currentDirectory

# show that module loaded into PS session
Get-Module -Name $moduleName
