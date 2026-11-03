<#
.SYNOPSIS
  Applies all EduNestIO database scripts in order to a clean PostgreSQL instance.
.EXAMPLE
  ./apply-all.ps1 -DbPassword "<postgres-password>"
#>
param(
    [string]$DbHost = "localhost",
    [int]$DbPort = 5432,
    [string]$DbUser = "postgres",
    [Parameter(Mandatory = $true)][string]$DbPassword,
    [string]$DbName = "edunestio",
    [string]$PsqlPath = "C:\Program Files\PostgreSQL\16\bin\psql.exe"
)

$ErrorActionPreference = "Stop"
$env:PGPASSWORD = $DbPassword
$here = $PSScriptRoot

Write-Host "Creating database (if needed)..."
& $PsqlPath -U $DbUser -h $DbHost -p $DbPort -f (Join-Path $here "00_create_database.sql")

$files = @(
  "01_schema.sql","02_indexes.sql","03_functions.sql","04_procedures.sql",
  "05_views.sql","06_seed_reference_data.sql","07_test_data.sql"
)
foreach ($f in $files) {
    Write-Host "Applying $f ..."
    & $PsqlPath -U $DbUser -h $DbHost -p $DbPort -d $DbName -v ON_ERROR_STOP=1 -f (Join-Path $here $f)
}

# Module scripts (each a self-contained, idempotent vertical-slice migration).
$moduleDir = Join-Path $here "modules"
if (Test-Path $moduleDir) {
    foreach ($m in (Get-ChildItem $moduleDir -Filter *.sql | Sort-Object Name)) {
        Write-Host "Applying modules/$($m.Name) ..."
        & $PsqlPath -U $DbUser -h $DbHost -p $DbPort -d $DbName -v ON_ERROR_STOP=1 -f $m.FullName
    }
}
Write-Host "All EduNestIO database scripts applied to '$DbName'."
