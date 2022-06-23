function Get-SqlDefaultSpConfigure {
    <#
        .SYNOPSIS
        Internal function. Returns the default sp_configure options for a given version of SQL Server.

        .NOTES
        Server Configuration Options BOL (links subject to change):
        SQL Server 2019 - https://technet.microsoft.com/en-us/library/ms189631(v=sql.150).aspx
        SQL Server 2017 - https://technet.microsoft.com/en-us/library/ms189631(v=sql.140).aspx
        SQL Server 2016 - https://technet.microsoft.com/en-us/library/ms189631(v=sql.130).aspx
        SQL Server 2014 - http://technet.microsoft.com/en-us/library/ms189631(v=sql.120).aspx
        SQL Server 2012 - http://technet.microsoft.com/en-us/library/ms189631(v=sql.110).aspx
        SQL Server 2008 R2 - http://technet.microsoft.com/en-us/library/ms189631(v=sql.105).aspx
        SQL Server 2008 - http://technet.microsoft.com/en-us/library/ms189631(v=sql.100).aspx
        SQL Server 2005 - http://technet.microsoft.com/en-us/library/ms189631(v=sql.90).aspx
        SQL Server 2000 - http://technet.microsoft.com/en-us/library/aa196706(v=sql.80).aspx (requires PDF download)

        .EXAMPLE
        Get-SqlDefaultSpConfigure -SqlVersion 11
        Returns a list of sp_configure (sys.configurations) items for SQL 2012.

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias("Version")]
        [object]$SqlVersion
    )

    switch ($SqlVersion) {

        #region SQL2000
        8 {
            [pscustomobject]@{
                "affinity mask"                  = 0
                "allow updates"                  = 0
                "awe enabled"                    = 0
                "c2 audit mode"                  = 0
                "cost threshold for parallelism" = 5
                "Cross DB Ownership Chaining"    = 0
                "cursor threshold"               = -1
                "default full-text language"     = 1033
                "default language"               = 0
                "fill factor (%)"                = 0
                "index create memory (KB)"       = 0
                "lightweight pooling"            = 0
                "locks"                          = 0
                "max degree of parallelism"      = 0
                "max server memory (MB)"         = 2147483647
                "max text repl size (B)"         = 65536
                "max worker threads"             = 255
                "media retention"                = 0
                "min memory per query (KB)"      = 1024
                "min server memory (MB)"         = 0
                "nested triggers"                = 1
                "network packet size (B)"        = 4096
                "open objects"                   = 0
                "priority boost"                 = 0
                "query governor cost limit"      = 0
                "query wait (s)"                 = -1
                "recovery interval (min)"        = 0
                "remote access"                  = 1
                "remote login timeout (s)"       = 20
                "remote proc trans"              = 0
                "remote query timeout (s)"       = 600
                "scan for startup procs"         = 0
                "set working set size"           = 0
                "show advanced options"          = 0
                "two digit year cutoff"          = 2049
                "user connections"               = 0
                "user options"                   = 0
            }
        }
        #endregion SQL2000

        #region SQL2005
        9 {
            [pscustomobject]@{
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity64 I/O mask"                = 0
                "affinity mask"                      = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow updates"                      = 0
                "awe enabled"                        = 0
                "blocked process threshold"          = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "common criteria compliance enabled" = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 8
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "PH timeout (s)"                     = 60
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote login timeout (s)"           = 20
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "SQL Mail XPs"                       = 0
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "Web Assistant Procedures"           = 0
                "xp_cmdshell"                        = 0
            }
        }

        #endregion SQL2005

        #region SQL2008&2008R2
        10 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity64 I/O mask"                = 0
                "affinity mask"                      = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow updates"                      = 0
                "awe enabled"                        = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "common criteria compliance enabled" = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote login timeout (s)"           = 20
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "SQL Mail XPs"                       = 0
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2008&2008R2

        #region SQL2012
        11 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity64 I/O mask"                = 0
                "affinity mask"                      = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow updates"                      = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2012

        #region SQL2014
        12 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity64 I/O mask"                = 0
                "affinity mask"                      = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow updates"                      = 0
                "backup checksum default"            = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2014

        #region SQL2016
        13 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity64 I/O mask"                = 0
                "affinity mask"                      = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow polybase export"              = 0
                "allow updates"                      = 0
                "automatic soft-NUMA disabled"       = 0
                "backup checksum default"            = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "external scripts enabled"           = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "hadoop connectivity"                = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "polybase network encryption"        = 1
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote data archive"                = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2016

        #region SQL2017
        14 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "affinity I/O mask"                  = 0
                "affinity mask"                      = 0
                "affinity64 I/O mask"                = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow polybase export"              = 0
                "allow updates"                      = 0
                "automatic soft-NUMA disabled"       = 0
                "backup checksum default"            = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "clr strict security"                = 1
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = -1
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 1
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "external scripts enabled"           = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "hadoop connectivity"                = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "polybase network encryption"        = 1
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote data archive"                = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "User Instance Timeout"              = 60
                "user instances enabled"             = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0

            }
        }
        #endregion SQL2017

        #region SQL2019
        15 {
            [pscustomobject]@{
                "access check cache bucket count"    = 0
                "access check cache quota"           = 0
                "Ad Hoc Distributed Queries"         = 0
                "ADR cleaner retry timeout (min)"    = 0
                "ADR Preallocation Factor"           = 0
                "affinity I/O mask"                  = 0
                "affinity mask"                      = 0
                "affinity64 I/O mask"                = 0
                "affinity64 mask"                    = 0
                "Agent XPs"                          = 0
                "allow filesystem enumeration"       = 1
                "allow polybase export"              = 0
                "allow updates"                      = 0
                "automatic soft-NUMA disabled"       = 0
                "backup checksum default"            = 0
                "backup compression default"         = 0
                "blocked process threshold (s)"      = 0
                "c2 audit mode"                      = 0
                "clr enabled"                        = 0
                "clr strict security"                = 0
                "column encryption enclave type"     = 0
                "common criteria compliance enabled" = 0
                "contained database authentication"  = 0
                "cost threshold for parallelism"     = 5
                "cross db ownership chaining"        = 0
                "cursor threshold"                   = 0
                "Database Mail XPs"                  = 0
                "default full-text language"         = 1033
                "default language"                   = 0
                "default trace enabled"              = 0
                "disallow results from triggers"     = 0
                "EKM provider enabled"               = 0
                "external scripts enabled"           = 0
                "filestream access level"            = 0
                "fill factor (%)"                    = 0
                "ft crawl bandwidth (max)"           = 100
                "ft crawl bandwidth (min)"           = 0
                "ft notify bandwidth (max)"          = 100
                "ft notify bandwidth (min)"          = 0
                "hadoop connectivity"                = 0
                "index create memory (KB)"           = 0
                "in-doubt xact resolution"           = 0
                "lightweight pooling"                = 0
                "locks"                              = 0
                "max degree of parallelism"          = 0
                "max full-text crawl range"          = 4
                "max server memory (MB)"             = 2147483647
                "max text repl size (B)"             = 65536
                "max worker threads"                 = 0
                "media retention"                    = 0
                "min memory per query (KB)"          = 1024
                "min server memory (MB)"             = 0
                "nested triggers"                    = 1
                "network packet size (B)"            = 4096
                "Ole Automation Procedures"          = 0
                "open objects"                       = 0
                "optimize for ad hoc workloads"      = 0
                "PH timeout (s)"                     = 60
                "polybase enabled"                   = 0
                "polybase network encryption"        = 1
                "precompute rank"                    = 0
                "priority boost"                     = 0
                "query governor cost limit"          = 0
                "query wait (s)"                     = -1
                "recovery interval (min)"            = 0
                "remote access"                      = 1
                "remote admin connections"           = 0
                "remote data archive"                = 0
                "remote login timeout (s)"           = 10
                "remote proc trans"                  = 0
                "remote query timeout (s)"           = 600
                "Replication XPs"                    = 0
                "scan for startup procs"             = 0
                "server trigger recursion"           = 1
                "set working set size"               = 0
                "show advanced options"              = 0
                "SMO and DMO XPs"                    = 1
                "tempdb metadata memory-optimized"   = 0
                "transform noise words"              = 0
                "two digit year cutoff"              = 2049
                "user connections"                   = 0
                "user options"                       = 0
                "xp_cmdshell"                        = 0
            }
        }
        #endregion SQL2019
    }
}

# SIG # Begin signature block
# MIIdsAYJKoZIhvcNAQcCoIIdoTCCHZ0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUR5hOuxk3ZvMN/Su68CjF+vj3
# nRCgghfOMIIFGjCCBAKgAwIBAgIQAwW7hiGwoWNfv96uEgTnbTANBgkqhkiG9w0B
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
# AQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFHOfIlDscc3J90y73ZrFC+6XY8mRMA0G
# CSqGSIb3DQEBAQUABIIBAEgwSDntieP8sWvFMEbW9RqTr4MFXvK37q/3ulxDzkjx
# 2WTFeR31vhrL/5J9C7swflvdnaVYF83Wg3KXYWo0ahWmiiZFLUlD96UoX3UkxmCN
# kPNojDjexipPgy20GldJxX3Jh3g5WSjL3PzX0XYEj2z6O3HGpecLsroDne1Exn6X
# VSj4MOxCQOs6p/eD5O90i/MvQocTqxJfURF95I2KMKef8/UX32qtdU+Nw5Jmr9vZ
# psak/skA6wen9h3rRbpBVNil/xP8ElGUoV4vGQLM90i2zezaMvJCigkyljMob7ZW
# cVfMj8NRcuykTEYl2iqtlfUm3T7P9hdEHElNQixK5W6hggMgMIIDHAYJKoZIhvcN
# AQkGMYIDDTCCAwkCAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBT
# SEEyNTYgVGltZVN0YW1waW5nIENBAhAKekqInsmZQpAGYzhNhpedMA0GCWCGSAFl
# AwQCAQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUx
# DxcNMjIwNTI2MjIxNDUxWjAvBgkqhkiG9w0BCQQxIgQgwhZnmvCcXqtJIFIgS5li
# 9vwhOcjuhctUqSRGa/6KHAswDQYJKoZIhvcNAQEBBQAEggIAeWQ+iVyAqoHAyA56
# AOi6bhbWVjzdnOpeUD6CogdI8a6s+DnIsKvEMMk7KuBG6NGiN4qfkkPlMfCr1WPr
# XtBm6UJAH8jOLES5zIlGXZheNeLtE7r5P++GyeTbz2aNVOZvnNIDrzdlmqOkHLPc
# Xs9D+KWF4QTW9PzciwHROvrfSH8WR4anYGMl6tyvJk2tf3QDTsuq9R/E2+o/WzcU
# Yu4GW8C80kh0srj/sR0js9YHJWJbQYLJ2YPwYSiqUGyQYdTM3nMr3lXnVKUe47zx
# gKTobcM5EP60ZdPSQhRgSsoz9zVz2yCm2Md6cwGXXxGMH2885r0djDbstGeJFF8I
# YemQee3fXlZyGa8pWYKO/gr3arQ9pRbYk8fwmpWyQ2a8nNIYYwMZqnRnuqW4hYtb
# IVTX7mgRyELJr4iyx2ZAPjXJUGIxXzARwvzcWX7PNEzo1zgLe+4b9g0JJWI8MZZU
# l+jdpHS34Zz8B1+ZyKXkrMpr3oFtTG7LIvs7N+Xy+3tQ8iast9S3nuqL5FGkhmmd
# GdblN7MmBZmqiDTK/1edOkpbp6ept/7pGYrBNaUrE8oo8a2o4whlN2256osZhHtZ
# 4WEJUOOpufmErWddge0251qgjWh7OtX8/lhadBbFhmd/zp3YPiS/HOk8OsbDnHti
# 1NLwJXodmDTV3nZHq8R6+MY4rmo=
# SIG # End signature block
