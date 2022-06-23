function Show-DbaInstanceFileSystem {
    <#
    .SYNOPSIS
        Shows file system on remote SQL Server in a local GUI and returns the selected directory name

    .DESCRIPTION
        Similar to the remote file system popup you see when browsing a remote SQL Server in SQL Server Management Studio, this function allows you to traverse the remote SQL Server's file structure.

        Show-DbaInstanceFileSystem uses SQL Management Objects to browse the directories and what you see is limited to the permissions of the account running the command.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, FileSystem, OS
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Show-DbaInstanceFileSystem

    .EXAMPLE
        PS C:\> Show-DbaInstanceFileSystem -SqlInstance sql2017

        Shows a list of databases using Windows Authentication to connect to the SQL Server. Returns a string of the selected path.

    .EXAMPLE
        PS C:\> Show-DbaInstanceFileSystem -SqlInstance sql2017 -SqlCredential $cred

        Shows a list of databases using SQL credentials to connect to the SQL Server. Returns a string of the selected path.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    begin {
        try {
            Add-Type -AssemblyName PresentationFramework
        } catch {
            Stop-Function -Message "Windows Presentation Framework required but not installed."
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

            if ($name.length -eq 1) {
                $image.Source = $diskicon
                $textblock.Text = "$name`:"
                $childitem.Tag = "$name`:"

            } else {
                $image.Source = $foldericon
                $textblock.Text = $name
                $childitem.Tag = "$tag\$name"
            }

            [void]$stackpanel.Children.Add($image)
            [void]$stackpanel.Children.Add($textblock)

            $childitem.Header = $stackpanel

            [void]$childitem.Items.Add("*")
            [void]$parent.Items.Add($childitem)
        }

        function Get-SubDirectory {
            param (
                [string]$nameSpace,
                [object]$treeviewItem
            )

            $textbox.Text = $nameSpace
            try {
                $dirs = $server.EnumDirectories($nameSpace)
            } catch {
                return
            }
            $subdirs = $dirs.Name

            foreach ($subdir in $subdirs) {
                if (!$subdir.StartsWith("$") -and $subdir -ne 'System Volume Information') {
                    Add-TreeItem -Name $subdir -Parent $treeviewItem -Tag $nameSpace
                }
            }
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

        $diskicon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABkAAAAZCAYAAADE6YVjAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAACxEAAAsRAX9kX5EAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAJtSURBVEhLtZJLa1NBGIa78ze4EZeu3bjS36BduVOsVCGmUqo1QlMaTV3E0oVugm0obdUQTZtYEnNvboTczjlN0ubaWE2aWGhuVQQXKbzOBM+BmokinA48nI+XmefjfDNDAE4dZig3zFBumKHcMEO5YYZywwwppVL5QrG4+217OweO30IiySPJCT1ozQsp7GTzoHvoXpZDpC/4Ut2/nc7sRIhYqO3Xuq1GA512C53WSY46bbSaTVQr1S5pLNAz9OyfPopUlMuf9KFAWO9yeit2uwtWiw1Ohwd+XwBBfxjBAIF+f9dkLzZ9QTg/umGzuuGwe+F0uivBQEhPXcwmJtM6HOSA2+VDOBRBaisNno4nwSOR4PqIx5LgyRhzuQK4NIdYPE7ORXsO6hK9FKkYHb0Po3ENGXIHzVabRP9ex13gsHkI7qcdobwTyUgapncWUBdZ/U3Gxx/j9aoJqVQGpd0KCsWvhPpAavXv8Ls5KCfGcMN7EcOay9CpX8D8/gOoS/RSTjQxLK6QlyRgt1xFvlAn1AZSq/yAZzOCW7pruHpwBlc056C+8xxr5o3BTRSKid6fZHM5VKoH2PvcIjQH0mwcwx/gcFN1HcOxs7ikPI+ZsTnyWHygLtFLkQq1ehZTUxpYrRvI58sQhAIhP5Bsbg9+Txzzcy+hddzDkwUVnk3PY1arA3WJXopUmEwWjIzcheqRGsa3ZjK65b+y8GoJy0tvyEWvY9W+CJvXhqczup6DukQvRSqi0QQMhhVMTk5DqXzYm+v/oFA8IJPQkhdqBnWJXopUnCbMUG6YodwwQ7lhhnLDDOWGGcoNM5QXDP0CA9dqCMSSjzkAAAAASUVORK5CYII="
        $foldericon = Convert-b64toimg "iVBORw0KGgoAAAANSUhEUgAAABkAAAAZCAYAAADE6YVjAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAACxEAAAsRAX9kX5EAAAAYdEVYdFNvZnR3YXJlAHBhaW50Lm5ldCA0LjAuNWWFMmUAAAU0SURBVEhLtZXpU5NXFIf9q/qto9bRuhc3xqUiUK3KoLYq6ihu1VIU1DpjRZ3BHVR8i6hUkDUJASNL2EJIWLKvBLJAAmHRpwfb6ai10Q/2w29u3pP3/p57zrn3vnOA/13/CkwMlzLuv0rMfYaoM59R+1ki1lwiFtHgGcIDuYT6fiZoPsWI6SSBnmyGeo4yZDxN2KEQHXr54H3Pdx5mNe6/QnzkGtMxNVNjeqK+AkLWQ/iMWdg7sxnz3uZ1vIrJSBnx0O9MhBQmggqxkRJC9hsEzFc+Dol5cpkcFaNXHbyasTMVNzARqWXEeZv+lh+xG/OIRWrgtU5ebxG1yu9meb+JEct57C+2fwLEe04g95mOPxJV8JphCcPUuBOHfg/6qm/pa8klNvyA6fFqZqbqZaxiZqKWQF8uVm3qp0LuMTNZyfREuUx+JuEo8agLe1smHTXpGLXSB3O+lKqMV5N1UtZypqJ/SCwHS2P6J0Iis5BqgTyR3tyVcIj4mAtL807aq1IxqLJwdR6TJhfL/xUCK3kjn/Ekg9rvPg6JevL/hlQJ5KmU4qGEg9IXCwNN22ir3ES3ap9AjjLqvU48/FBgN0SFeAzZDDSk3nnf852HWY25zxKPFEut/4JMRmcX5mM8bKJPm0bLs/V01e/B2X6IsPMyscAtRt2XRZdwdx1kQPsJ5Rp1nRGIZCKQqZhs09FiCTuJhQyYNFtoLl9HZ20mjtb9BK0XJJsrhG3nZJvn4Wr/AUfbEc+I/fFsI//xfAcwq4gjR0pTxPRkhQAeMh66zavpHkYDWoz1m3j5ZDWd1duxN+9muO80IVuejCcImI7h0W/F2boLtyFfrBJAwtZTjAdvMTn+VFZ/j7HADSbGahh2FGGoWYeuLImOynRsL3bg7zksgGP4DPvwdu2W52wp4wH6NJvFKgEkaP2J6LA0dKxMxruM+q9LFnfxmH+hu3oVTY+S0FekyFbdhrdzr1wnWXg6MnC1phBwVuOxqelvSBOrBJCRgWOM+a9JmUqI+AoJea4SlMY6pamdlStoVJbTVr6BQemPq22ngDJwNm/B3rSKgFuPzz0gmXwEEug7TMTzm5TpDkHXZYbtFxm2XsTenkX7s2VoS76m9cla+lUbcbxMlQxmAclYNEsIuzSE3N0CSRWrBBC/6RBB50XC3kICtl/xD+bh78/DIveWvnwJDQ8W0iJ96atNxtYoIN0GrA1JWOoX4Ler8Dq7MKu3iFUCiK/ngKw8Xy7EAnwDZ6UXOXjkGh/QZdL2dDHq+1/RXLoSc80aMV+LTbsKm3opHvU8buoqKdC1YFKliFUCiKdrr6w8B7/lAu7eUzi7j+PoPCIH8XtaHi9CXTyPZmUJpqqVDKq/wapZgUO9mKB2LqmlVSQ9bKG3fqNYJYA4O3bhMZ2QDHJxdGVj0x/E2rafXnW6QBaiKZ7LS2URpucrGFQtF8hyHJqlDGkXcLz0OnuVUno/loldvwO37He3MQebXB3W1n1yMe7BKBNnIeqiL9GVLHwDsaiWYdMsw6pehl1A7bXraK7birlhh1glgLi6T2Br24tZmyqr34BJvZn+xu1y2r+l9fF86m5+gbZ4PsbnazDXJ9OvXv9mNNUl45LSDck3x91bKFYJIF7TJWVQl6mYNGn6fl0WpoYMeupSaK9Yje7RcjmMqbSWZ9gNz9crxvotSq86TTHWpiiGmk2KUZWuOAyXlBG3Snnb8x3A2wp6m3b6rE+wtp+nq2oDL0oX01CaQndjAVZjbdGH5vyXPhj83Ppg8POKOX8Cx4yjZbQFLr4AAAAASUVORK5CYII="
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
        [xml]$xaml = '<Window
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Locate Folder" Height="620" Width="440" Background="#F0F0F0"
        WindowStartupLocation="CenterScreen">
    <Grid>
        <TreeView Name="treeview" Height="462" Width="391" Background="#FFFFFF" BorderBrush="#FFFFFF" Foreground="#FFFFFF" Margin="11,36,11,79"/>
        <Label x:Name="label" Content="Select the folder:" HorizontalAlignment="Left" Margin="15,4,0,0" VerticalAlignment="Top"/>
        <Label x:Name="path" Content="Selected Path" HorizontalAlignment="Left" Margin="15,502,0,0" VerticalAlignment="Top"/>
        <TextBox Name="textbox" HorizontalAlignment="Left" Height="Auto" Margin="111,504,0,0" TextWrapping="NoWrap" Text="C:\" VerticalAlignment="Top" Width="292"/>
        <Button Name="okbutton" Content="OK" HorizontalAlignment="Left" Margin="241,540,0,0" VerticalAlignment="Top" Width="75"/>
        <Button Name="cancelbutton" Content="Cancel" HorizontalAlignment="Left" Margin="328.766,540,0,0" VerticalAlignment="Top" Width="75"/>
    </Grid>
</Window>
'
        # Turn XAML into PowerShell objects
        $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
        $window.icon = $dbatoolsicon

        $xaml.SelectNodes("//*[@Name]") | ForEach-Object { Set-Variable -Name ($_.Name) -Value $window.FindName($_.Name) -Scope Script }

        try {
            $drives = ($server.EnumAvailableMedia()).Name
        } catch {
            Stop-Function -Message "No access to remote SQL Server files." -Target $SqlInstance
            return
        }

        foreach ($drive in $drives) {
            $drive = $drive.Replace(":", "")
            Add-TreeItem -Name $drive -Parent $treeview -Tag $drive
        }

        $window.Add_SourceInitialized( {
                [System.Windows.RoutedEventHandler]$Event = {
                    if ($_.OriginalSource -is [System.Windows.Controls.TreeViewItem]) {
                        $treeviewItem = $_.OriginalSource
                        $treeviewItem.items.clear()
                        Get-SubDirectory -NameSpace $treeviewItem.Tag -TreeViewItem $treeviewItem
                    }
                }
                $treeview.AddHandler([System.Windows.Controls.TreeViewItem]::ExpandedEvent, $Event)
                $treeview.AddHandler([System.Windows.Controls.TreeViewItem]::SelectedEvent, $Event)
            })

        $okbutton.Add_Click( {
                $window.Close()
            })

        $cancelbutton.Add_Click( {
                $textbox.Text = $null
                $window.Close()
            })

        $null = $window.ShowDialog()
    }

    end {

        if ($textbox.Text.Length -gt 0) {
            $drive = $textbox.Text + '\'
            return $drive
        }
    }
}
# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUaTclV+6QuJRXFmjN3zicY/If
# ID+gghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFDA/nhn8HLjCJBJ8j7gnRXXIiXSVMA0G
# CSqGSIb3DQEBAQUABIIBACQGYdDMu0d7SOBoo+hudWebXltSGou6DcpPXrq0g0eC
# /n/LlDhiqGH49cJQWPLFT6zR4DkG2CW4tJz/0YugiF7xU9OhKtxWNAEb58LKLrq+
# H7Kletv3MNHH9JejNTQP90BKWtkoNL0eRCQ5oY5gXuSl7cZ2sQbKCXnusY1z53ge
# Gt4VpIKVElOvsE21XPgkBzBJNANONQEw3pq/aVdeixd3nSbvYH1jIlc6Ns6AsNSk
# vSIDhaBwPpaisTm/p+O60c3g9sTGBjc1ejjKzeUUjuWUP1EBMKVA8ROIvg5VSIxF
# +4wySCWhkr8rNgmdWAK4tylsQx4UGOZVHhPYMJFBQsKhggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDIzWjAvBgkqhkiG9w0BCQQxIgQghRKBVkonyoBbvSX0qBHD
# azPKpmTYM1hPDmifBB3Q3t8wDQYJKoZIhvcNAQEBBQAEggIARkJzPEhJJm1OZe3U
# OgbOHwZn0vVtSqQv8kMzzpBXuox2nbTMZ1yM7hWldov0ctIDfhURfFhvNXzpHGsZ
# 2jzDOQv5V4Kh0SVK7PnUnMmCUqA3bBwulFOQNex9F09Uaxc5U37FRoB0LsrvdxHB
# r9twDN4qpN2qRR+y1ae/Dy19pSXIwsQ91DTEmfg9Bpm6DMs+WX+lIAqvklFh/NjT
# j/ogWc6bcGaXuqKX2xihXSITt8gllZBHU1V8bxGZJu0Q/MkIiFaFqmqga3+Ft4aQ
# od6FjrVWxrxc+DbUvTemNx+JjYkLYfZKl/qTEfcaDv/qWu78CD2cfV/iaaD3k9YO
# 5EQtBSx29J6v/FLIZCtwNjH0gExDvdYzS9n056fCeuYIk9wNUFu3kC76JmP6/JV9
# knpfKYpuTMcQA0sm5XwkdTUAFFSPje42JE2uIRZl2MOPusQL4UCHQ+8fEdbljUGC
# TcHPmbyV7h33h7J4fiijIHh82Feohich64V3apN/Agxv8wbg5cdzUVTfJ4T5ddD8
# 9gf3VQltBtfetc1UmOUL+D0dXajXyatomKVE3pFHgbgJve8C6Cj8j98R3tECKPmU
# 9S8LoMxeRvZtzg/gJz1TAp/gpe77PElqN+B2CSar2HPdgJW5DRtH7VOtrrbWNRM3
# RJOl3gRwf8lJqemeQRucOTBrtVE=
# SIG # End signature block
