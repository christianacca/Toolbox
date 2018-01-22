function Remove-Hostnames {
    <#
    .SYNOPSIS
    Removes one or more hostnames from the hosts file.

    .DESCRIPTION
    The hosts file is used to map hostnames to IP addresses.

    .PARAMETER Hostnames
    One or more hostnames to remove from the hosts file.

    .EXAMPLE
    Remove-TecBoxHostnames foobar

    Description
    -----------
    Assume the following line was previously added to the hosts file:

    127.0.0.1    foobar

    After running "Remove-TecBoxHostnames foobar" the hosts file no longer contains this
    line.

    .EXAMPLE
    Remove-TecBoxHostnames foo

    Description
    -----------
    Assume the following line was previously added to the hosts file:

    127.0.0.1    foobar foo bar

    After running "Remove-TecBoxHostnames foo" the line in the hosts file is updated
    to remove the specified hostname ("foo"):

    127.0.0.1    foobar bar

    .EXAMPLE
    Remove-TecBoxTecBoxHostnames foo, bar

    Description
    -----------
    Assume the following line was previously added to the hosts file:

    127.0.0.1    foobar foo bar

    After running "Remove-TecBoxHostnames foo, bar" the line in the hosts file is updated to
    remove the specified hostnames ("foo" and "bar"):

    127.0.0.1    foobar

    .NOTES
    This script must be run with administrator privileges.
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]] $Hostnames
    )

    begin
    {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = "Stop"

        function Execute-WithRetry([ScriptBlock] $command) {
            $attemptCount = 0
            $operationIncomplete = $true
            $maxFailures = 5
            $sleepBetweenFailures = 2
        
            while ($operationIncomplete -and $attemptCount -lt $maxFailures) {
                $attemptCount = ($attemptCount + 1)
        
                if ($attemptCount -ge 2) {
                    Write-Verbose "Waiting for $sleepBetweenFailures seconds before retrying..."
                    Start-Sleep -s $sleepBetweenFailures
                    Write-Verbose "Retrying..."
                }
        
                try {
                    # Call the script block
                    & $command
        
                    $operationIncomplete = $false
                } catch [System.Exception] {
                    if ($attemptCount -lt ($maxFailures)) {
                        Write-Warning ("Attempt $attemptCount of $maxFailures failed: " + $_.Exception.Message)
                    } else {
                        throw
                    }
                }
            }
        }

        function CreateHostsEntryObject(
            [string] $ipAddress,
            [string[]] $hostnames,
            <# [string] #> $comment) #HACK: never $null if type is specified
        {
            $hostsEntry = New-Object PSObject
            $hostsEntry | Add-Member NoteProperty -Name "IpAddress" `
                -Value $ipAddress

            [System.Collections.ArrayList] $hostnamesList =
                New-Object System.Collections.ArrayList

            $hostsEntry | Add-Member NoteProperty -Name "Hostnames" `
                -Value $hostnamesList

            If ($hostnames -ne $null)
            {
                $hostnames | foreach {
                    $hostsEntry.Hostnames.Add($_) | Out-Null
                }
            }

            $hostsEntry | Add-Member NoteProperty -Name "Comment" -Value $comment

            return $hostsEntry
        }

        function ParseHostsEntry(
            [string] $line)
        {
            $hostsEntry = CreateHostsEntryObject

            Write-Debug "Parsing hosts entry: $line"

            If ($line.Contains("#") -eq $true)
            {
                If ($line -eq "#")
                {
                    $hostsEntry.Comment = [string]::Empty
                }
                Else
                {
                    $hostsEntry.Comment = $line.Substring($line.IndexOf("#") + 1)
                }

                $line = $line.Substring(0, $line.IndexOf("#"))
            }

            $line = $line.Trim()

            If ($line.Length -gt 0)
            {
                $hostsEntry.IpAddress = ($line -Split "\s+")[0]

                Write-Debug "Parsed address: $($hostsEntry.IpAddress)"

                [string[]] $parsedHostnames = $line.Substring(
                    $hostsEntry.IpAddress.Length + 1).Trim() -Split "\s+"

                Write-Debug ("Parsed hostnames ($($parsedHostnames.Length)):" `
                    + " $parsedHostnames")

                $parsedHostnames | foreach {
                    $hostsEntry.Hostnames.Add($_) | Out-Null
                }
            }

            return $hostsEntry
        }

        function ParseHostsFile
        {
            $hostsEntries = New-Object System.Collections.ArrayList

            [string] $hostsFile = $env:WINDIR + "\System32\drivers\etc\hosts"

            If ((Test-Path $hostsFile) -eq $false)
            {
                Write-Verbose "Hosts file does not exist."
            }
            Else
            {
                [string[]] $hostsContent = Get-Content $hostsFile

                $hostsContent | foreach {
                    $hostsEntry = ParseHostsEntry $_

                    $hostsEntries.Add($hostsEntry) | Out-Null
                }
            }

            # HACK: Return an array (containing the ArrayList) to avoid issue with
            # PowerShell returning $null (when hosts file does not exist)
            return ,$hostsEntries
        }

        function UpdateHostsFile(
            $hostsEntries = $(Throw "Value cannot be null: hostsEntries"))
        {
            Write-Verbose "Updatings hosts file..."

            [string] $hostsFile = $env:WINDIR + "\System32\drivers\etc\hosts"

            $buffer = New-Object System.Text.StringBuilder

            $hostsEntries | foreach {

                If ([string]::IsNullOrEmpty($_.IpAddress) -eq $false)
                {
                    $buffer.Append($_.IpAddress) | Out-Null
                    $buffer.Append("`t") | Out-Null
                }

                If ($_.Hostnames -ne $null)
                {
                    [bool] $firstHostname = $true

                    $_.Hostnames | foreach {
                        If ($firstHostname -eq $false)
                        {
                            $buffer.Append(" ") | Out-Null
                        }
                        Else
                        {
                            $firstHostname = $false
                        }

                        $buffer.Append($_) | Out-Null
                    }
                }

                If ($_.Comment -ne $null)
                {
                    If ([string]::IsNullOrEmpty($_.IpAddress) -eq $false)
                    {
                        $buffer.Append(" ") | Out-Null
                    }

                    $buffer.Append("#") | Out-Null
                    $buffer.Append($_.Comment) | Out-Null
                }

                $buffer.Append([System.Environment]::NewLine) | Out-Null
            }

            [string] $hostsContent = $buffer.ToString()

            $hostsContent = $hostsContent.Trim()

            Execute-WithRetry { Set-Content -Path $hostsFile -Value $hostsContent -Force -Encoding ASCII }

            Write-Verbose "Successfully updated hosts file."
        }

        [bool] $isInputFromPipeline =
            ($PSBoundParameters.ContainsKey("Hostnames") -eq $false)

        [int] $pendingUpdates = 0

        [Collections.ArrayList] $hostsEntries = ParseHostsFile
    }

    process
    {
        If ($isInputFromPipeline -eq $true)
        {
            $items = $_
        }
        Else
        {
            $items = $Hostnames
        }

        $items | foreach {
            [string] $hostname = $_

            for ([int] $i = 0; $i -lt $hostsEntries.Count; $i++)
            {
                $hostsEntry = $hostsEntries[$i]

                Write-Debug "Hosts entry: $hostsEntry"

                If ($hostsEntry.Hostnames.Count -eq 0)
                {
                    continue
                }

                for ([int] $j = 0; $j -lt $hostsEntry.Hostnames.Count; $j++)
                {
                    [string] $parsedHostname = $hostsEntry.Hostnames[$j]

                    Write-Debug ("Comparing specified hostname" `
                        + " ($hostname) to existing hostname" `
                        + " ($parsedHostname)...")

                    If ([string]::Compare($hostname, $parsedHostname, $true) -eq 0)
                    {
                        Write-Debug "Removing hostname ($hostname) from host entry ($hostsEntry)..."

                        $hostsEntry.Hostnames.RemoveAt($j)
                        $j--

                        $pendingUpdates++
                    }
                }

                If ($hostsEntry.Hostnames.Count -eq 0)
                {
                    Write-Debug ("Removing host entry (because it no longer specifies" `
                        + " any hostnames)...")

                    $hostsEntries.RemoveAt($i)
                    $i--
                }
            }
        }
    }

    end
    {
        If ($pendingUpdates -eq 0)
        {
            Write-Verbose "No changes to the hosts file are necessary."

            return
        }

        Write-Verbose ("There are $pendingUpdates pending update(s) to the hosts" `
            + " file.")

        UpdateHostsFile $hostsEntries
    }
}