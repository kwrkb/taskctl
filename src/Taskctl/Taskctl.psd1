@{
    RootModule        = 'Taskctl.psm1'
    ModuleVersion     = '1.0.1'
    GUID              = '398ccab1-b7c5-46e9-9bb7-85d619b21780'
    Author            = 'kwrkb'
    Description       = 'Diagnose why Windows scheduled tasks fail (or are likely to) and show the concrete next step. Read-only; never modifies task settings.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('taskctl', 'Invoke-TaskctlExplain', 'Invoke-TaskctlDoctor', 'Get-TaskctlExitCode')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('TaskScheduler', 'Diagnostics', 'Windows')
            ProjectUri = 'https://github.com/kwrkb/taskctl'
        }
    }
}
