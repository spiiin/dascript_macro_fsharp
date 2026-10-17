param([Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference='Stop'
$Destination=[IO.Path]::GetFullPath($Destination)
# Never overwrite an application checkout or an earlier export.
if(Test-Path -LiteralPath $Destination){throw 'Destination must be a new directory.'}
$modules=@(Get-Content (Join-Path $PSScriptRoot 'public_modules.json') -Raw | ConvertFrom-Json)
$actual=@(Get-ChildItem (Join-Path $PSScriptRoot 'lib') -File -Filter '*.das'|Select-Object -ExpandProperty Name)
if(@(Compare-Object $modules $actual).Count){throw 'public_modules.json does not match lib/'}
foreach($name in $modules) {
    if([IO.Path]::GetFileName($name) -ne $name -or -not(Test-Path -LiteralPath (Join-Path $PSScriptRoot ("lib/"+$name)))){throw "Invalid module: $name"}
}
# Verify that the distribution contains the transitive local require closure.
foreach($name in $modules) {
    foreach($match in [regex]::Matches([IO.File]::ReadAllText((Join-Path $PSScriptRoot ("lib/"+$name))),'(?m)^require\s+([\w./]+)')) {
        $dependency=$match.Groups[1].Value
        if($dependency.StartsWith('daslib/')){continue}
        $dependency=[IO.Path]::GetFileNameWithoutExtension($dependency)+'.das'
        if($dependency -notin $modules){throw "Missing public dependency: $dependency (from $name)"}
    }
}
New-Item -ItemType Directory -Path (Join-Path $Destination 'lib') -Force | Out-Null
foreach($name in $modules){Copy-Item -LiteralPath (Join-Path $PSScriptRoot ("lib/"+$name)) -Destination (Join-Path $Destination 'lib')}
foreach($name in @('main.das','identity_builder.das')){
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "integration_example/$name") -Destination $Destination
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'INTEGRATION.md') -Destination (Join-Path $Destination 'README.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PUBLIC_API.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'TASKS.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'TASK_COMPOSITION.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'TASK_SCHEDULER.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'TASK_CANCELLATION.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'TASK_DELAY.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'TASK_ARRAY.md') -Destination $Destination
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'TASK_AND_BIND.md') -Destination $Destination
$modules | ForEach-Object {[pscustomobject]@{File="lib/$_";Sha256=(Get-FileHash -LiteralPath (Join-Path $Destination "lib/$_")).Hash}} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Destination 'manifest.json')
Write-Host "Exported $($modules.Count) library modules and a standalone integration example to $Destination"
