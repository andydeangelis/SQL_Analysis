function Show-DbaDbList {
    <#
    .SYNOPSIS
        Shows a list of databases in a GUI.

    .DESCRIPTION
        Shows a list of databases in a GUI. Returns a string holding the name of the selected database. Hitting cancel returns null.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances..

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Title
        Title of the window being displayed. Default is "Select Database".

    .PARAMETER Header
        Header text displayed above the database listing. Default is "Select the database:".

    .PARAMETER DefaultDb
        Specify a database to have selected when the window appears.

    .PARAMETER EnableException
        By default in most of our commands, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This command, however, gifts you  with "sea of red" exceptions, by default, because it is useful for advanced scripting.

        Using this switch turns our "nice by default" feature on which makes errors into pretty warnings.

    .NOTES
        Tags: Database, FileSystem
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Show-DbaDbList

    .EXAMPLE
        PS C:\> Show-DbaDbList -SqlInstance sqlserver2014a

        Shows a GUI list of databases using Windows Authentication to connect to the SQL Server. Returns a string of the selected database.

    .EXAMPLE
        PS C:\> Show-DbaDbList -SqlInstance sqlserver2014a -SqlCredential $cred

        Shows a GUI list of databases using SQL credentials to connect to the SQL Server. Returns a string of the selected database.

    .EXAMPLE
        PS C:\> Show-DbaDbList -SqlInstance sqlserver2014a -DefaultDb master

        Shows a GUI list of databases using Windows Authentication to connect to the SQL Server. The "master" database will be selected when the lists shows. Returns a string of the selected database.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Title = "Select Database",
        [string]$Header = "Select the database:",
        [string]$DefaultDb,
        [switch]$EnableException
    )

    begin {
        try {
            Add-Type -AssemblyName PresentationFramework
        } catch {
            Stop-Function -Message "Windows Presentation Framework required but not installed"
            return
        }

        function Add-TreeItem {
            param (
                [string]$name,
                [object]$parent,
                [string]$tag
            )

            $childitem = New-Object System.Windows.Controls.TreeViewItem
            $textblock = New-Object System.Windows.Controls.TextBlock
            $textblock.Margin = "5,0"
            $stackpanel = New-Object System.Windows.Controls.StackPanel
            $stackpanel.Orientation = "Horizontal"
            $image = New-Object System.Windows.Controls.Image
            $image.Height = 20
            $image.Width = 20
            $image.Stretch = "Fill"
            $image.Source = $dbicon
            $textblock.Text = $name
            $childitem.Tag = $name

            if ($name -eq $DefaultDb) {
                $childitem.IsSelected = $true
                $script:selected = $name
            }

            [void]$stackpanel.Children.Add($image)
            [void]$stackpanel.Children.Add($textblock)

            $childitem.Header = $stackpanel
            [void]$parent.Items.Add($childitem)
        }

        function Convert-b64toimg {
            param ($base64)

            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String($base64)
            $bitmap.EndInit()
            $bitmap.Freeze()
            return $bitmap
        }

        $dbicon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAFRSURBVDhPY/j//z9VMVZBSjCCgQZunFn6/8zenv+7llf83zA75/+6WTn/N80v+L93ddP/M/tnY2jAayDIoNvn5/5/cX/t/89vdv7/9fUQGIPYj2+t/H/xyJT/O1ZUoWjCaeCOxcX///48ShSeWhMC14jXwC9Xs/5/fzHr/6/PW+GaQS78/WH9/y+Pe8DyT3fYEmcgKJw+HHECawJp/vZ60f8v95v/fzgd8P/tVtn/L1cw/n+0iOH/7TlMxBkIigBiDewr9iVsICg2qWrg6qnpA2dgW5YrYQOX9icPAQPfU9PA2S2RRLuwMtaGOAOf73X+//FyGl4DL03jIM5AEFjdH/x//+Lo/1cOlP9/dnMq2MA3x/z/312l/P/4JNH/axoU/0/INUHRhNdAEDi+pQ1cZIFcDEpvoPCaVOTwf1Gjy/9ds5MxNGAYSC2MVZB8/J8BAGcHwqQBNWHRAAAAAElFTkSuQmCC"
        $foldericon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAHaSURBVDhPY/j//z9VMVZBSjBWQUowVkFKMApnzZL+/+gYWZ4YDGeANL95sun/j3fbwPjbm5X/Pz+cRLKhcAayq2B45YKe/8vndoHx4lltYLxgajMKhumHYRQDf37Yh4J/fNry//fb1f9/v1n6/8/Tqf//3O/6/+dO9f9fV4v+fzmV/v/L0aj/lflJQO1YDAS5AmwI1MvfPyAZ9KgbYtDlvP/fzyT9/3w45P+HPT7/z8+UwG0gyDvIBmIYBnQVyDCQq0CGPV9p8v94P/f/rKQwoHYsBs4HhgfIQJjLfr+YjdOwt5tt/z9eov1/fxf3/+ggD6B2HAaCXQYKM6hhv+81oYQXzLCXq03/P5qn/H9LE/9/LycroHYsBs7oq4EYCDIM6FVshr3Z4gg2DOS6O9Nk/q+sFvlvZawD1I7FwKldleC0h2zY9wuZEMP2+aMYdn+W/P/rE0T/zy+T+q+jJg/UjsXASe1l/z/cX/T/1dn8/492ePy/vc7s/82VOv8vLVT9f3yGwv89ffL/1zXL/l9dJwF2GciwaYVy/xVlxIDasRjY31Lyv7Uy+39ZTvz/1JiA/8Hejv8dLA3+62sqgTWJC/HixDAzQBjOoBbGKkgJxipICcYqSD7+zwAAkIiWzSGuSg0AAAAASUVORK5CYII="
        $dbatoolsicon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABkAAAAZCAYAAADE6YVjAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAO9SURBVEhL3VVdTFNXHO9MzPTF+OzDeBixFdTMINIWsAUK3AIVkFvAIQVFRLYZKR8Wi1IEKV9DYB8PGFAyEx8QScySabYY5+I2JvK18iWISKGk0JGhLzA3+e2c29uHtpcvH/0lv9yennN+v3vO/3fOFb2fCAg4vXWPNOmMRJ745TtTSskqeElviGXJ0XtkWvjJkyGLPoFAVQZoe/NkX/n6Mh/ysu4Qy7WZdJAutxRW6zT6LcNQaE4LiGgREH4cibpCMNqzCIk9hbScEoSSZ0zKOa7fRxG/k5d1h8ukvO4a5ubmMT1jw5E0vZcBZWzqOTS3dcB8tRXZeRX4/v5DZH5uIu0Wrn8NEzaNDjgYoUPd120oMjViX2iql8H6ZFd8DzE7eFl3iOWpuyQydlh44kbJroilSd8RuQ+cqh7wC9Z+JJaxY8KTN0gp+5Yk9DaREzYhb5FOBwZFZ6LlZifKa5ux//AxYTHCvSEp8A9O5n77B6dwqXS119guZ+GrGq9jfn4eM7ZZxB/PdxN2UfOpHq3kRWq/uoE8Yx3u/fQLzhSYUdN0g+tfN126z0oxNj6BJz0Dq0b4E2UawuJzuPhKyZmKYr/AocgMrk37VzWRBLGRdE/psuXqk9wkT/GNUCJLWqS3By/rDh9FxjaSrnahiZ7cq8wCUzKImLIJqC+Ngbk4gmjjIKKKB6Aq7l+OLBmfVF0YnlQZR1p4eSd2y5IiyEr+oyJ0CwIi0gUNKAOPmnG04Q0utf+DHweWkFjjQOyVWajLpsCUPkeUcRgqAzE09Dfz8k64aqI9YcDziUk87bMgOCZL0CQ0ux2J9UtIbXyFwall/PD0NeLKrU6DkhGymj8RXtRDjU7x8k64TKpJQmi6bLOzSEgv8DYhNWMujiK+9jU0VQs4Vm/H2MwSOh4vcP+rii2cQVh+F+IqbRJe3glyReuoSFBUJtpu3eWulv2h3ueE1iOu0g5N9QL3jLk8jerbdrz59y1yGoYQUdSLsII/CLscIsD9UPrLUz4myXhBhWjCPMVdPBBnhMbsIAZzSDDbcOvRIhyLy6i4+Qyq82QFxECR9xjK/K5OXtodNHo+CsW2tagunbxADbK+sXP16Bv/G7lNQ8hpHEX21UGoDb/j8NmfoSzoNvCymwdTPvMotsKGB32LaL1H0mS0oOHOFLpH/0L3iAOF3/YSk4dgTBMh/JTNgdVbtzNl1il12UuSpHE+SRayTb0IL3yCMP2vUJKtUuh/szNNK8Jfxw3BZNpiMoGjiKPJm54Ffw8gEv0PQRYX7wDAUKEAAAAASUVORK5CYII="

    }

    process {
        if (Test-FunctionInterrupt) { return }

        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }

        # Create XAML form in Visual Studio, ensuring the ListView looks chromeless
        [xml]$xaml = "<Window
        xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='$Title' SizeToContent='WidthAndHeight' Background='#F0F0F0'
        WindowStartupLocation='CenterScreen' MaxHeight='600'>
    <Grid>
        <TreeView Name='treeview' Height='Auto' Width='Auto' Background='#FFFFFF' BorderBrush='#FFFFFF' Foreground='#FFFFFF' Margin='11,36,11,79'/>
        <Label x:Name='label' Content='$header' HorizontalAlignment='Left' Margin='15,4,10,0' VerticalAlignment='Top'/>
        <StackPanel HorizontalAlignment='Right' Orientation='Horizontal' VerticalAlignment='Bottom' Margin='0,50,10,30'>
        <Button Name='okbutton' Content='OK'  Margin='0,0,0,0' Width='75'/>
        <Label Width='10'/>
        <Button Name='cancelbutton' Content='Cancel' Margin='0,0,0,0' Width='75'/>
    </StackPanel>
</Grid>
</Window>"
        #second pushes it down
        # Turn XAML into PowerShell objects
        $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
        $window.icon = $dbatoolsicon

        $xaml.SelectNodes("//*[@Name]") | ForEach-Object { Set-Variable -Name ($_.Name) -Value $window.FindName($_.Name) -Scope Script }

        $childitem = New-Object System.Windows.Controls.TreeViewItem
        $textblock = New-Object System.Windows.Controls.TextBlock
        $textblock.Margin = "5,0"
        $stackpanel = New-Object System.Windows.Controls.StackPanel
        $stackpanel.Orientation = "Horizontal"
        $image = New-Object System.Windows.Controls.Image
        $image.Height = 20
        $image.Width = 20
        $image.Stretch = "Fill"
        $image.Source = $foldericon
        $textblock.Text = "Databases"
        $childitem.Tag = "Databases"
        $childitem.isExpanded = $true
        [void]$stackpanel.Children.Add($image)
        [void]$stackpanel.Children.Add($textblock)
        $childitem.Header = $stackpanel
        #Variable marked as unused by PSScriptAnalyzer
        $null = $treeview.Items.Add($childitem)

        try {
            $databases = $server.Databases.Name
        } catch {
            return
        }

        foreach ($database in $databases) {
            Add-TreeItem -Name $database -Parent $childitem -Tag $nameSpace
        }

        $okbutton.Add_Click( {
                $window.Close()
                $script:okay = $true
            })

        $cancelbutton.Add_Click( {
                $script:selected = $null
                $window.Close()
            })

        $window.Add_SourceInitialized( {
                [System.Windows.RoutedEventHandler]$Event = {
                    if ($_.OriginalSource -is [System.Windows.Controls.TreeViewItem]) {
                        $script:selected = $_.OriginalSource.Tag
                    }
                }
                $treeview.AddHandler([System.Windows.Controls.TreeViewItem]::SelectedEvent, $Event)
            })

        $null = $window.ShowDialog()
    }

    end {
        if ($script:selected.length -gt 0 -and $script:okay -eq $true) {
            return $script:selected
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU20oTa7Edtg2KiquJfZPMcTjL
# n5qgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
# AQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFz
# c3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMB4XDTIwMDUxMjAwMDAwMFoXDTIzMDYw
# ODEyMDAwMFowVzELMAkGA1UEBhMCVVMxETAPBgNVBAgTCFZpcmdpbmlhMQ8wDQYD
# VQQHEwZWaWVubmExETAPBgNVBAoTCGRiYXRvb2xzMREwDwYDVQQDEwhkYmF0b29s
# czCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALy/Y3ur47++CAG2mOa1
# 6h8WjXjSTvcldDmw4PpAvOOCKNr6xyhg/FOYVIiaeq2N9kVaa5wBawOIxVWuj/rI
# aOxeYklQDugPkGUx0Ap+6KrjnnxgE6ONzQGnc1tjlka6N0KazD2WodEBWKXo/Vmk
# C/cP9PJVWroCMOwlj7GtEv2IxzxikPm2ICP5KxFK5PmrA+5bzcHJEeqRonlgMn9H
# zZkqHr0AU1egnfEIlH4/v6lry1t1KBF/bnDhl9g/L0icS+ychFVkx4OOO4a+qvT8
# xqvvdQjv3PQ1hbzTI3/tXOWu9XxGeeIdZjaJv16FmWKCnloSp1Xb9cVU9XhIpomz
# xH0CAwEAAaOCAcUwggHBMB8GA1UdIwQYMBaAFFrEuXsqCqOl6nEDwGD5LfZldQ5Y
# MB0GA1UdDgQWBBTwwKD7tgOAQ077Cdfd33qxy+OeIjAOBgNVHQ8BAf8EBAMCB4Aw
# EwYDVR0lBAwwCgYIKwYBBQUHAwMwdwYDVR0fBHAwbjA1oDOgMYYvaHR0cDovL2Ny
# bDMuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJlZC1jcy1nMS5jcmwwNaAzoDGGL2h0
# dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQtY3MtZzEuY3JsMEwG
# A1UdIARFMEMwNwYJYIZIAYb9bAMBMCowKAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3
# LmRpZ2ljZXJ0LmNvbS9DUFMwCAYGZ4EMAQQBMIGEBggrBgEFBQcBAQR4MHYwJAYI
# KwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBOBggrBgEFBQcwAoZC
# aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0U0hBMkFzc3VyZWRJ
# RENvZGVTaWduaW5nQ0EuY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQAD
# ggEBAI/N+XCVDB/WNqQSrKY85zScHGJjsXgXByYvsitMuG5vo+ODhlh+ILv0CTPl
# o2Wo75MnSSqCWR+c6xyN8pDPMPBxm2EtVmXzeKDMIudYyjxmT8PZ3hktj16wXCo8
# 2+65UOse+CHsfoMn/M9WbkQ4rSyWNPRRDodATC2i4flLyeuoIZnyMoz/4N4mWb6s
# IAYZ/tNXzm6qwCfkmoMSf9tcTUCXIbVDliJcUZLlJ/SpLg2KzDu9GtnpBzg3AG3L
# hwBiPMM8OLGitYjz4VU5RYox0vu1XyLf3f9fKTCxxwKy0EKntWdJk37i+DOMQlCq
# Xm5B/KyNxb2utv+qLGlyw9MphEcwggUwMIIEGKADAgECAhAECRgbX9W7ZnVTQ7Vv
# lVAIMA0GCSqGSIb3DQEBCwUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdp
# Q2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0Rp
# Z2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0xMzEwMjIxMjAwMDBaFw0yODEw
# MjIxMjAwMDBaMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMx
# GTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNI
# QTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQD407Mcfw4Rr2d3B9MLMUkZz9D7RZmxOttE9X/lqJ3bMtdx
# 6nadBS63j/qSQ8Cl+YnUNxnXtqrwnIal2CWsDnkoOn7p0WfTxvspJ8fTeyOU5JEj
# lpB3gvmhhCNmElQzUHSxKCa7JGnCwlLyFGeKiUXULaGj6YgsIJWuHEqHCN8M9eJN
# YBi+qsSyrnAxZjNxPqxwoqvOf+l8y5Kh5TsxHM/q8grkV7tKtel05iv+bMt+dDk2
# DZDv5LVOpKnqagqrhPOsZ061xPeM0SAlI+sIZD5SlsHyDxL0xY4PwaLoLFH3c7y9
# hbFig3NBggfkOItqcyDQD2RzPJ6fpjOp/RnfJZPRAgMBAAGjggHNMIIByTASBgNV
# HRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggrBgEF
# BQcDAzB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRp
# Z2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCBgQYDVR0fBHoweDA6oDig
# NoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9v
# dENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# QXNzdXJlZElEUm9vdENBLmNybDBPBgNVHSAESDBGMDgGCmCGSAGG/WwAAgQwKjAo
# BggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAKBghghkgB
# hv1sAzAdBgNVHQ4EFgQUWsS5eyoKo6XqcQPAYPkt9mV1DlgwHwYDVR0jBBgwFoAU
# Reuir/SSy4IxLVGLp6chnfNtyA8wDQYJKoZIhvcNAQELBQADggEBAD7sDVoks/Mi
# 0RXILHwlKXaoHV0cLToaxO8wYdd+C2D9wz0PxK+L/e8q3yBVN7Dh9tGSdQ9RtG6l
# jlriXiSBThCk7j9xjmMOE0ut119EefM2FAaK95xGTlz/kLEbBw6RFfu6r7VRwo0k
# riTGxycqoSkoGjpxKAI8LpGjwCUR4pwUR6F6aGivm6dcIFzZcbEMj7uo+MUSaJ/P
# QMtARKUT8OZkDCUIQjKyNookAv4vcn4c10lFluhZHen6dGRrsutmQ9qzsIzV6Q3d
# 9gEgzpkxYz0IGhizgZtPxpMQBvwHgfqL2vmCSfdibqFT+hKUGIUukpHqaGxEMrJm
# oecYpJpkUe8wggauMIIElqADAgECAhAHNje3JFR82Ees/ShmKl5bMA0GCSqGSIb3
# DQEBCwUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0
# ZWQgUm9vdCBHNDAeFw0yMjAzMjMwMDAwMDBaFw0zNzAzMjIyMzU5NTlaMGMxCzAJ
# BgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGln
# aUNlcnQgVHJ1c3RlZCBHNCBSU0E0MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0Ew
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDGhjUGSbPBPXJJUVXHJQPE
# 8pE3qZdRodbSg9GeTKJtoLDMg/la9hGhRBVCX6SI82j6ffOciQt/nR+eDzMfUBML
# JnOWbfhXqAJ9/UO0hNoR8XOxs+4rgISKIhjf69o9xBd/qxkrPkLcZ47qUT3w1lbU
# 5ygt69OxtXXnHwZljZQp09nsad/ZkIdGAHvbREGJ3HxqV3rwN3mfXazL6IRktFLy
# dkf3YYMZ3V+0VAshaG43IbtArF+y3kp9zvU5EmfvDqVjbOSmxR3NNg1c1eYbqMFk
# dECnwHLFuk4fsbVYTXn+149zk6wsOeKlSNbwsDETqVcplicu9Yemj052FVUmcJgm
# f6AaRyBD40NjgHt1biclkJg6OBGz9vae5jtb7IHeIhTZgirHkr+g3uM+onP65x9a
# bJTyUpURK1h0QCirc0PO30qhHGs4xSnzyqqWc0Jon7ZGs506o9UD4L/wojzKQtwY
# SH8UNM/STKvvmz3+DrhkKvp1KCRB7UK/BZxmSVJQ9FHzNklNiyDSLFc1eSuo80Vg
# vCONWPfcYd6T/jnA+bIwpUzX6ZhKWD7TA4j+s4/TXkt2ElGTyYwMO1uKIqjBJgj5
# FBASA31fI7tk42PgpuE+9sJ0sj8eCXbsq11GdeJgo1gJASgADoRU7s7pXcheMBK9
# Rp6103a50g5rmQzSM7TNsQIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIB
# ADAdBgNVHQ4EFgQUuhbZbU2FL3MpdpovdYxqII+eyG8wHwYDVR0jBBgwFoAU7Nfj
# gtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsG
# AQUFBwMIMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3Au
# ZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0
# hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0
# LmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcN
# AQELBQADggIBAH1ZjsCTtm+YqUQiAX5m1tghQuGwGC4QTRPPMFPOvxj7x1Bd4ksp
# +3CKDaopafxpwc8dB+k+YMjYC+VcW9dth/qEICU0MWfNthKWb8RQTGIdDAiCqBa9
# qVbPFXONASIlzpVpP0d3+3J0FNf/q0+KLHqrhc1DX+1gtqpPkWaeLJ7giqzl/Yy8
# ZCaHbJK9nXzQcAp876i8dU+6WvepELJd6f8oVInw1YpxdmXazPByoyP6wCeCRK6Z
# JxurJB4mwbfeKuv2nrF5mYGjVoarCkXJ38SNoOeY+/umnXKvxMfBwWpx2cYTgAnE
# tp/Nh4cku0+jSbl3ZpHxcpzpSwJSpzd+k1OsOx0ISQ+UzTl63f8lY5knLD0/a6fx
# ZsNBzU+2QJshIUDQtxMkzdwdeDrknq3lNHGS1yZr5Dhzq6YBT70/O3itTK37xJV7
# 7QpfMzmHQXh6OOmc4d0j/R0o08f56PGYX/sr2H7yRp11LB4nLCbbbxV7HhmLNriT
# 1ObyF5lZynDwN7+YAN8gFk8n+2BnFqFmut1VwDophrCYoCvtlUG3OtUVmDG0YgkP
# Cr2B2RP+v6TR81fZvAT6gt4y3wSJ8ADNXcL50CN/AAvkdgIm2fBldkKmKYcJRyvm
# fxqkhQ/8mJb2VVQrH4D6wPIOK+XW+6kvRBVK5xMOHds3OBqhK/bt1nz8MIIGxjCC
# BK6gAwIBAgIQCnpKiJ7JmUKQBmM4TYaXnTANBgkqhkiG9w0BAQsFADBjMQswCQYD
# VQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lD
# ZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBTSEEyNTYgVGltZVN0YW1waW5nIENBMB4X
# DTIyMDMyOTAwMDAwMFoXDTMzMDMxNDIzNTk1OVowTDELMAkGA1UEBhMCVVMxFzAV
# BgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMSQwIgYDVQQDExtEaWdpQ2VydCBUaW1lc3Rh
# bXAgMjAyMiAtIDIwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC5KpYj
# ply8X9ZJ8BWCGPQz7sxcbOPgJS7SMeQ8QK77q8TjeF1+XDbq9SWNQ6OB6zhj+TyI
# ad480jBRDTEHukZu6aNLSOiJQX8Nstb5hPGYPgu/CoQScWyhYiYB087DbP2sO37c
# KhypvTDGFtjavOuy8YPRn80JxblBakVCI0Fa+GDTZSw+fl69lqfw/LH09CjPQnkf
# O8eTB2ho5UQ0Ul8PUN7UWSxEdMAyRxlb4pguj9DKP//GZ888k5VOhOl2GJiZERTF
# KwygM9tNJIXogpThLwPuf4UCyYbh1RgUtwRF8+A4vaK9enGY7BXn/S7s0psAiqwd
# jTuAaP7QWZgmzuDtrn8oLsKe4AtLyAjRMruD+iM82f/SjLv3QyPf58NaBWJ+cCzl
# K7I9Y+rIroEga0OJyH5fsBrdGb2fdEEKr7mOCdN0oS+wVHbBkE+U7IZh/9sRL5ID
# MM4wt4sPXUSzQx0jUM2R1y+d+/zNscGnxA7E70A+GToC1DGpaaBJ+XXhm+ho5GoM
# j+vksSF7hmdYfn8f6CvkFLIW1oGhytowkGvub3XAsDYmsgg7/72+f2wTGN/GbaR5
# Sa2Lf2GHBWj31HDjQpXonrubS7LitkE956+nGijJrWGwoEEYGU7tR5thle0+C2Fa
# 6j56mJJRzT/JROeAiylCcvd5st2E6ifu/n16awIDAQABo4IBizCCAYcwDgYDVR0P
# AQH/BAQDAgeAMAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# IAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcBMB8GA1UdIwQYMBaAFLoW
# 2W1NhS9zKXaaL3WMaiCPnshvMB0GA1UdDgQWBBSNZLeJIf5WWESEYafqbxw2j92v
# DTBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGln
# aUNlcnRUcnVzdGVkRzRSU0E0MDk2U0hBMjU2VGltZVN0YW1waW5nQ0EuY3JsMIGQ
# BggrBgEFBQcBAQSBgzCBgDAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNl
# cnQuY29tMFgGCCsGAQUFBzAChkxodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRUcnVzdGVkRzRSU0E0MDk2U0hBMjU2VGltZVN0YW1waW5nQ0EuY3J0
# MA0GCSqGSIb3DQEBCwUAA4ICAQANLSN0ptH1+OpLmT8B5PYM5K8WndmzjJeCKZxD
# bwEtqzi1cBG/hBmLP13lhk++kzreKjlaOU7YhFmlvBuYquhs79FIaRk4W8+JOR1w
# cNlO3yMibNXf9lnLocLqTHbKodyhK5a4m1WpGmt90fUCCU+C1qVziMSYgN/uSZW3
# s8zFp+4O4e8eOIqf7xHJMUpYtt84fMv6XPfkU79uCnx+196Y1SlliQ+inMBl9AEi
# ZcfqXnSmWzWSUHz0F6aHZE8+RokWYyBry/J70DXjSnBIqbbnHWC9BCIVJXAGcqlE
# O2lHEdPu6cegPk8QuTA25POqaQmoi35komWUEftuMvH1uzitzcCTEdUyeEpLNypM
# 81zctoXAu3AwVXjWmP5UbX9xqUgaeN1Gdy4besAzivhKKIwSqHPPLfnTI/KeGeAN
# lCig69saUaCVgo4oa6TOnXbeqXOqSGpZQ65f6vgPBkKd3wZolv4qoHRbY2beayy4
# eKpNcG3wLPEHFX41tOa1DKKZpdcVazUOhdbgLMzgDCS4fFILHpl878jIxYxYaa+r
# PeHPzH0VrhS/inHfypex2EfqHIXgRU4SHBQpWMxv03/LvsEOSm8gnK7ZczJZCOct
# kqEaEf4ymKZdK5fgi9OczG21Da5HYzhHF1tvE9pqEG4fSbdEW7QICodaWQR2EaGn
# dwITHDGCBUwwggVIAgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdp
# Q2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERp
# Z2lDZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEAMFu4YhsKFj
# X7/erhIE520wCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAw
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFGfmBaKPVptMvzBNfsrG8+2MjZTHMA0G
# CSqGSIb3DQEBAQUABIIBAFPx8cUqy10516BouDoI9Eau4aGojrmmqhuGeRp868h8
# yIaDOGy5NxrHPMoksF8xvCK++XwalEwyVwZs34FAoYLOkMBrUFX00dK51B3jyQtK
# dYAdphS4uVoWJCeAtCXxI+SGiNbo2YssQ4d92gTReDJobvJGuwcEXC7N3/bt5kbA
# C9Xieacka0KDCRBYM0nFiEfN59ZtZSc35pD4FZrvee/C08EJSjEay45Rze8hV6w3
# U5o4WbUF21HvO/Gx5DJdvq5Kx2zggOi9AchguBQyvXp+eF3/meAGHUmTOOXwG/KH
# 3KuQufaD7trtCo+wVS1O9G6Daa2IwCVTLf8c0r2+GeehggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDIzWjAvBgkqhkiG9w0BCQQxIgQg3H3CcJDfsZTKBm0bRNZP
# RZ1jmpc3+ZkwkbsyZ0JnGnQwDQYJKoZIhvcNAQEBBQAEggIAOrZtX4AMyE7NIElK
# iX9Vk0aVkRaNTW7cjSx/v14rcyAcnQwQODzr4P4UzK65maB9SQmnx34B4onL8SLt
# QWRyhnJ/3N8nDbFpgEPa/KyaNke6tMWY0HZHHHTYpolqDTbwxP9MfH5QqNWSMRgj
# fkwB830XaPBThiXlNr0lTaeTU4OHC9X5MnI+4k5my4WJ+lPU1nKX1w6aZ8lUJYg9
# XmboFauL7iVtV9O62329VqluXlByyZXNRKW9lLibqwuUtJq2bXu5mqhWWESYj8vi
# LbUOReSvU83k1toR/FkvCYGBFsepTttwvrzgJj0kOx3g4i2+xkCI3NQy9WDI0wlz
# DcIYpRIM7Qjr/tNLR7E1mLMIj25U1gmdRKKCK0oK4qum7/8Fbat3FwNQVja/rSBi
# 1HtjLiFREnPz5Rq6lI+AU22eaYbyVbc4J8wuk9SCjHRrxY+bkcliDkNNmgePZIY3
# vU5sjWxJ/8/QvQF3NmwzvUk8JFu+eFhWXB53FtukPP4NZeRzsaM86dQS3karo03E
# ApYiWWIQF1QQvNFIp3SqQk5KdKZo2eNKqEtJWopPFjObGUf/XvoACHr199SLaBkm
# yzof6D0qbRRjJnB+b7JBsEv3HPaG1DiluSJc+0kNrLSyXvSrFx7jG8YlBKy45xTG
# lWHRQ38B23AW4x2c4YXeyy4PpmA=
# SIG # End signature block
