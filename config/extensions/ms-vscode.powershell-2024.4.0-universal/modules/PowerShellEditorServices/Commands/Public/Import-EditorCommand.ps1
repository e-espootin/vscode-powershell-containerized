# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

function Import-EditorCommand {
    <#
    .EXTERNALHELP ..\PowerShellEditorServices.Commands-help.xml
    #>
    [OutputType([Microsoft.PowerShell.EditorServices.Extensions.EditorCommand, Microsoft.PowerShell.EditorServices])]
    [CmdletBinding(DefaultParameterSetName='ByCommand')]
    param(
        [Parameter(Position=0,
                   Mandatory,
                   ValueFromPipeline,
                   ValueFromPipelineByPropertyName,
                   ParameterSetName='ByCommand')]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Command,

        [Parameter(Position=0, Mandatory, ParameterSetName='ByModule')]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Module,

        [switch]
        $Force,

        [switch]
        $PassThru
    )
    begin {
        function GetCommandsFromModule {
            param(
                [Parameter(ValueFromPipeline)]
                [string]
                $ModuleToSearch
            )
            process {
                if (-not $ModuleToSearch) { return }

                $caller = (Get-PSCallStack)[2]

                if ($caller.InvocationInfo.MyCommand.ScriptBlock.Module.Name -eq $ModuleToSearch) {
                    $moduleInfo = $caller.InvocationInfo.MyCommand.ScriptBlock.Module

                    return $moduleInfo.Invoke(
                        {
                            $ExecutionContext.SessionState.InvokeProvider.Item.Get('function:\*') |
                                Where-Object ModuleName -eq $args[0]
                        },
                        $ModuleToSearch)
                }

                $moduleInfo = Get-Module $ModuleToSearch -ErrorAction SilentlyContinue
                return $moduleInfo.ExportedFunctions.Values
            }
        }
        $editorCommands = @{}

        foreach ($existingCommand in $psEditor.GetCommands()) {
            $editorCommands[$existingCommand.Name] = $existingCommand
        }
    }
    process {
        switch ($PSCmdlet.ParameterSetName) {
            ByModule {
                $commands = $Module | GetCommandsFromModule
            }
            ByCommand {
                $commands = $Command | Get-Command -ErrorAction SilentlyContinue
            }
        }
        $attributeType = [Microsoft.PowerShell.EditorServices.Extensions.EditorCommandAttribute, Microsoft.PowerShell.EditorServices]
        foreach ($aCommand in $commands) {
            # Get the attribute from our command to get name info.
            $details = $aCommand.ScriptBlock.Attributes | Where-Object TypeId -eq $attributeType

            if ($details) {
                # TODO: Add module name to this?
                # Name: Expand-Expression becomes ExpandExpression
                if (-not $details.Name) { $details.Name = $aCommand.Name -replace '-' }

                # DisplayName: Expand-Expression becomes Expand Expression
                if (-not $details.DisplayName) { $details.DisplayName = $aCommand.Name -replace '-', ' ' }

                # If the editor command is already loaded skip unless force is specified.
                if ($editorCommands.ContainsKey($details.Name)) {
                    if ($Force.IsPresent) {
                        $null = $psEditor.UnregisterCommand($details.Name)
                    } else {
                        $PSCmdlet.WriteVerbose($Strings.EditorCommandExists -f $details.Name)
                        continue
                    }
                }
                # Check for a context parameter.
                $contextParameter = $aCommand.Parameters.Values |
                    Where-Object ParameterType -eq ([Microsoft.PowerShell.EditorServices.Extensions.EditorContext, Microsoft.PowerShell.EditorServices])

                # If one is found then add a named argument. Otherwise call the command directly.
                if ($contextParameter) {
                    $sbText = '{0} -{1} $args[0]' -f $aCommand.Name, $contextParameter.Name
                    $scriptBlock = [scriptblock]::Create($sbText)
                } else {
                    $scriptBlock = [scriptblock]::Create($aCommand.Name)
                }

                $editorCommand = [Microsoft.PowerShell.EditorServices.Extensions.EditorCommand, Microsoft.PowerShell.EditorServices]::new(
                    <# commandName:    #> $details.Name,
                    <# displayName:    #> $details.DisplayName,
                    <# suppressOutput: #> $details.SuppressOutput,
                    <# scriptBlock:    #> $scriptBlock)

                $PSCmdlet.WriteVerbose($Strings.EditorCommandImporting -f $details.Name)
                $null = $psEditor.RegisterCommand($editorCommand)

                if ($PassThru.IsPresent -and $editorCommand) {
                    $editorCommand # yield
                }
            }
        }
    }
}

if ($PSVersionTable.PSVersion.Major -ge 5) {
    Register-ArgumentCompleter -CommandName Import-EditorCommand -ParameterName Module -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        (Get-Module).Name -like ($wordToComplete + '*') | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($PSItem, $PSItem, 'ParameterValue', $PSItem)
        }
    }
    Register-ArgumentCompleter -CommandName Import-EditorCommand -ParameterName Command -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        (Get-Command -ListImported).Name -like ($wordToComplete + '*') | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($PSItem, $PSItem, 'ParameterValue', $PSItem)
        }
    }
}

# SIG # Begin signature block
# MIIoRgYJKoZIhvcNAQcCoIIoNzCCKDMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBCo/8RxkJRpjfH
# tv88INxNRrHwrLnOrzrSY5Y80TZvAqCCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
# Bv9XKydyAAAAAAQEMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjQwOTEyMjAxMTE0WhcNMjUwOTExMjAxMTE0WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC0KDfaY50MDqsEGdlIzDHBd6CqIMRQWW9Af1LHDDTuFjfDsvna0nEuDSYJmNyz
# NB10jpbg0lhvkT1AzfX2TLITSXwS8D+mBzGCWMM/wTpciWBV/pbjSazbzoKvRrNo
# DV/u9omOM2Eawyo5JJJdNkM2d8qzkQ0bRuRd4HarmGunSouyb9NY7egWN5E5lUc3
# a2AROzAdHdYpObpCOdeAY2P5XqtJkk79aROpzw16wCjdSn8qMzCBzR7rvH2WVkvF
# HLIxZQET1yhPb6lRmpgBQNnzidHV2Ocxjc8wNiIDzgbDkmlx54QPfw7RwQi8p1fy
# 4byhBrTjv568x8NGv3gwb0RbAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQU8huhNbETDU+ZWllL4DNMPCijEU4w
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzUwMjkyMzAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAIjmD9IpQVvfB1QehvpC
# Ge7QeTQkKQ7j3bmDMjwSqFL4ri6ae9IFTdpywn5smmtSIyKYDn3/nHtaEn0X1NBj
# L5oP0BjAy1sqxD+uy35B+V8wv5GrxhMDJP8l2QjLtH/UglSTIhLqyt8bUAqVfyfp
# h4COMRvwwjTvChtCnUXXACuCXYHWalOoc0OU2oGN+mPJIJJxaNQc1sjBsMbGIWv3
# cmgSHkCEmrMv7yaidpePt6V+yPMik+eXw3IfZ5eNOiNgL1rZzgSJfTnvUqiaEQ0X
# dG1HbkDv9fv6CTq6m4Ty3IzLiwGSXYxRIXTxT4TYs5VxHy2uFjFXWVSL0J2ARTYL
# E4Oyl1wXDF1PX4bxg1yDMfKPHcE1Ijic5lx1KdK1SkaEJdto4hd++05J9Bf9TAmi
# u6EK6C9Oe5vRadroJCK26uCUI4zIjL/qG7mswW+qT0CW0gnR9JHkXCWNbo8ccMk1
# sJatmRoSAifbgzaYbUz8+lv+IXy5GFuAmLnNbGjacB3IMGpa+lbFgih57/fIhamq
# 5VhxgaEmn/UjWyr+cPiAFWuTVIpfsOjbEAww75wURNM1Imp9NJKye1O24EspEHmb
# DmqCUcq7NqkOKIG4PVm3hDDED/WQpzJDkvu4FrIbvyTGVU01vKsg4UfcdiZ0fQ+/
# V0hf8yrtq9CkB8iIuk5bBxuPMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGiYwghoiAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAQEbHQG/1crJ3IAAAAABAQwDQYJYIZIAWUDBAIB
# BQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPZ8NEzZjgCyML6sujLTPgim
# QGyG4V5qvxM+l9MjZcEpMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
# BQAEggEAmnsADcP/wOLZrGEdAPahCh2RbnLT5gyqvRWcJW1Z9R3m1PbtpBvcb4zU
# bow1KkeBK+AudiCAgfW4c08wRaf5Hl0mcsmtFpMJyfbpQA5+qNJJxAjOTp2775hb
# 0SC7yOGt669L5Nl9JqE6zmAUlDJbgnjJrhhYY4BvH7QbIGVkQ3z4JHbtRZyPm7/W
# eaJGThuFrHle9WZ7vVVEJ2inIxwgL2h0J7VD5XkhFST+J63ixCkbacpQ/W4hqHSu
# 1sC417RIf3QUoz+aM2ry4K0nBISd8r3QIecyvHHko21Fyud9kB6iyU2b0M3D+F9Z
# kqXTkzVW0R5dmwyg/4RXW2GBUrzqZqGCF7AwghesBgorBgEEAYI3AwMBMYIXnDCC
# F5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsq
# hkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFl
# AwQCAQUABCBIkTzdMH+LB+soIYrg61W6JmtLygeL6a2hTtS+OXsmwwIGZutpKQLP
# GBMyMDI0MTAzMTEzNTEyOC4zMzJaMASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJl
# bGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVT
# Tjo1NzFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# U2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAAB+8vLbDdn5TCVAAEAAAH7MA0G
# CSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI0
# MDcyNTE4MzExM1oXDTI1MTAyMjE4MzExM1owgdMxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
# ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjU3MUEt
# MDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAqMJWQeWAq4LwvSjYsjP0
# Uvhvm0j0aAOJiMLg0sLfxKoTXAdKD6oMuq5rF5oEiOxV+9ox0H95Q8fhoZq3x9lx
# guZyTOK4l2xtcgtJCtjXRllM2bTpjOg35RUrBy0cAloBU9GJBs7LBNrcbH6rBiOv
# qDQNicPRZwq16xyjMidU1J1AJuat9yLn7taifoD58blYEcBvkj5dH1la9zU846QD
# eOoRO6NcqHLsDx8/zVKZxP30mW6Y7RMsqtB8cGCgGwVVurOnaNLXs31qTRTyVHX8
# ppOdoSihCXeqebgJCRzG8zG/e/k0oaBjFFGl+8uFELwCyh4wK9Z5+azTzfa2GD4p
# 6ihtskXs3lnW05UKfDJhAADt6viOc0Rk/c8zOiqzh0lKpf/eWUY2o/hvcDPZNgLa
# HvyfDqb8AWaKvO36iRZSXqhSw8SxJo0TCpsbCjmtx0LpHnqbb1UF7cq09kCcfWTD
# PcN12pbYLqck0bIIfPKbc7HnrkNQks/mSbVZTnDyT3O8zF9q4DCfWesSr1akycDd
# uGxCdKBvgtJh1YxDq1skTweYx5iAWXnB7KMyls3WQZbTubTCLLt8Xn8t+slcKm5D
# kvobubmHSriuTA3wTyIy4FxamTKm0VDu9mWds8MtjUSJVwNVVlBXaQ3ZMcVjijyV
# oUNVuBY9McwYcIQK62wQ20ECAwEAAaOCAUkwggFFMB0GA1UdDgQWBBRHVSGYUNQ3
# RwOl71zIAuUjIKg1KjAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBf
# BgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3Bz
# L2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmww
# bAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0El
# MjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUF
# BwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEAwzoIKOY2dnUj
# fWuMiGoz/ovoc1e86VwWaZNFdgRmOoQuRe4nLdtZONtTHNk3Sj3nkyBszzxSbZEQ
# 0DduyKHHI5P8V87jFttGnlR0wPP22FAebbvAbutkMMVQMFzhVBWiWD0VAnu9x0fj
# ifLKDAVXLwoun5rCFqwbasXFc7H/0DPiC+DBn3tUxefvcxUCys4+DC3s8CYp7WWX
# pZ8Wb/vdBhDliHmB7pWcmsB83uc4/P2GmAI3HMkOEu7fCaSYoQhouWOr07l/KM4T
# ndylIirm8f2WwXQcFEzmUvISM6ludUwGlVNfTTJUq2bTDEd3tlDKtV9AUY3rrnFw
# HTwJryLtT4IFhvgBfND3mL1eeSakKf7xTII4Jyt15SXhHd5oI/XGjSgykgJrWA57
# rGnAC7ru3/ZbFNCMK/Jj6X8X4L6mBOYa2NGKwH4A37YGDrecJ/qXXWUYvfLYqHGf
# 8ThYl12Yg1rwSKpWLolA/B1eqBw4TRcvVY0IvNNi5sm+//HJ9Aw6NJuR/uDR7X7v
# DXicpXMlRNgFMyADb8AFIvQPdHqcRpRorY+YUGlvzeJx/2gNYyezAokbrFhACsJ2
# BfyeLyCEo6AuwEHn511PKE8dK4JvlmLSoHj7VFR3NHDk3zRkx0ExkmF8aOdpvoKh
# uwBCxoZ/JhbzSzrvZ74GVjKKIyt5FA0wggdxMIIFWaADAgECAhMzAAAAFcXna54C
# m0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZp
# Y2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMy
# MjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51
# yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY
# 6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9
# cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN
# 7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDua
# Rr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74
# kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2
# K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5
# TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZk
# i1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9Q
# BXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3Pmri
# Lq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUC
# BBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9y
# eS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUA
# YgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU
# 1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIw
# MTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0w
# Ni0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/yp
# b+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulm
# ZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM
# 9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECW
# OKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4
# FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3Uw
# xTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPX
# fx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVX
# VAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGC
# onsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU
# 5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEG
# ahC0HVUzWLOhcGbyoYIDWTCCAkECAQEwggEBoYHZpIHWMIHTMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJl
# bGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVT
# Tjo1NzFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# U2VydmljZaIjCgEBMAcGBSsOAwIaAxUABHHn7NCGusZz2RfVbyuwYwPykBWggYMw
# gYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsF
# AAIFAOrN7IswIhgPMjAyNDEwMzExMTQ2MTlaGA8yMDI0MTEwMTExNDYxOVowdzA9
# BgorBgEEAYRZCgQBMS8wLTAKAgUA6s3siwIBADAKAgEAAgIyUAIB/zAHAgEAAgIU
# QjAKAgUA6s8+CwIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAow
# CAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUAA4IBAQDJByNUSy5b
# PtUE6ak+OVy+T8nn8Hq0VopL9Fsb8QsMtk5J4CHFczMYy3xtzjK7DuZCm43nLHfO
# c0iBVWGhDcsh8y3dhVEQ/8GlhwxEwWvspeia+51sVrtbgSMO5hYO5zJgfm1dpwOQ
# DAANIct53nUv/mzUt1EzliRjh2JhzvQZJ4boGQCJ0mXlbUK0l4ukFDGrmeYVwCkk
# guNQ7WBWxTuXoI0XEjmMDrlQ4yw4EjhzARFpBNz2rtTaw0llLhVwvvFGPGRdRF7X
# C1DtUZO/2l9j5Os1eUvwpYH6pHaxW6EALDx/GCuKIOzAFgfG0q01BnDtAGD3z8S/
# lTbGzThTc01wMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTACEzMAAAH7y8tsN2flMJUAAQAAAfswDQYJYIZIAWUDBAIBBQCgggFKMBoG
# CSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgExqLY4vO
# VNAfHt7kzba/AEgDAa82Vkgi5RXUWcbGmYAwgfoGCyqGSIb3DQEJEAIvMYHqMIHn
# MIHkMIG9BCA52wKr/KCFlVNYiWsCLsB4qhjEYEP3xHqYqDu1SSTlGDCBmDCBgKR+
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAB+8vLbDdn5TCVAAEA
# AAH7MCIEIOnJEktr8/+3fsaQzFjaonG4KZk+7xMXBCr9tqDMpe3XMA0GCSqGSIb3
# DQEBCwUABIICAJIGLFVs3Lvh3CNv5SSF49PSuwEqfHJLXIXehp3QWjM+af+8gPmb
# 62KxSD+sB4hL6YrfOw4OWKFJlgI/tbni/xppBp4ItZgepcjWlfY2Te/LTJV9npwi
# Kg4bJLNxCJJDIYiCOjvyi7wW0evAf+XWp/5cCNKTE3DAaG6KhwfWh+Z5sU2MnCMr
# SrqSdlypw50feZlvABma3k2mGNoCm07XTXrtLsQCJf721AgmtZXFEaASiKrvy0wC
# SQ5hJ/jk+VqsaZC+uUCy5G5RqULgZmsBkbzSwajB+Vm8ixQjs1CUaMhesbpoFk0G
# II8wXwgjsa6cL/BPc4XaOaLGQqFQheK0DoDVdvfAa3tbSHWv4dgBuRi5pRUsAYyy
# JA76HuSedLei/O8DX4AhPKWdhbQ9XVopTDllgs/vJRY/l3YY7QmOCFnV7j6u3XRt
# qtZSJPTQPh8QSuk0YGfvS7XQhdc803VTSYGdbfGG+GxKeprv09NqakSmW4/ZVOXb
# /KELh3dhvKS+vBs+F2bZqOheGWPuS3XPDJExHDt7l7gOWgCpay3cRw4J6K3D9Oho
# 3RRhi4RXX34DBv4Xz/ALYf7sEopdxLPJ7ss91hDDXLlb6seamnjXNhPIDu01gAGx
# 1IAsHTktn7kBbNJVn96p2qHkZM7wkd0S22CWsgBzFcxtNOauM/rbYoez
# SIG # End signature block
