param(
    [string]$RepoUrl = "https://github.com/Dejavu75/sh_export_office.git",
    [string]$Branch = "main",
    [string]$BasePath = ".",
    [string]$FolderName = "CH10-EXP",
    [switch]$ForzarReclone
)

$ErrorActionPreference = "Stop"

function Es-ComentarioOBlanco {
    param([string]$Linea)

    if ($null -eq $Linea) { return $true }
    if ($Linea.Trim() -eq "") { return $true }
    if ($Linea.Trim().StartsWith("#")) { return $true }
    return $false
}

function Leer-EnvArchivo {
    param([string]$Path)

    $lineas = Get-Content -LiteralPath $Path -Encoding UTF8
    $items = @()

    foreach ($linea in $lineas) {
        if (Es-ComentarioOBlanco $linea) {
            $items += [pscustomobject]@{
                Tipo  = "raw"
                Linea = $linea
                Key   = $null
                Value = $null
            }
            continue
        }

        $idx = $linea.IndexOf("=")
        if ($idx -lt 0) {
            $items += [pscustomobject]@{
                Tipo  = "raw"
                Linea = $linea
                Key   = $null
                Value = $null
            }
            continue
        }

        $key = $linea.Substring(0, $idx).Trim()
        $value = $linea.Substring($idx + 1)

        $items += [pscustomobject]@{
            Tipo  = "env"
            Linea = $null
            Key   = $key
            Value = $value
        }
    }

    return $items
}

function Guardar-EnvArchivo {
    param(
        [string]$Path,
        [array]$Items
    )

    $salida = New-Object System.Collections.Generic.List[string]

    foreach ($item in $Items) {
        if ($item.Tipo -eq "raw") {
            $salida.Add([string]$item.Linea)
        } else {
            $salida.Add("$($item.Key)=$($item.Value)")
        }
    }

    [System.IO.File]::WriteAllLines($Path, $salida, [System.Text.UTF8Encoding]::new($false))
}

function Pedir-Valor {
    param(
        [string]$Nombre,
        [string]$ValorActual
    )

    $prompt = "$Nombre [$ValorActual]"
    $nuevo = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($nuevo)) { return $ValorActual }
    return $nuevo
}

function Verificar-Comando {
    param([string]$Nombre)

    $cmd = Get-Command $Nombre -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "No se encontró el comando '$Nombre'."
    }
}

$RepoPath = Join-Path $BasePath $FolderName

Write-Host ""
Write-Host "=== Setup CH10-EXP ===" -ForegroundColor Cyan
Write-Host "RepoUrl : $RepoUrl"
Write-Host "Branch  : $Branch"
Write-Host "Destino : $RepoPath"
Write-Host ""

Verificar-Comando "git"
Verificar-Comando "docker"

if (!(Test-Path -LiteralPath $BasePath)) {
    New-Item -ItemType Directory -Path $BasePath -Force | Out-Null
}

if ($ForzarReclone -and (Test-Path -LiteralPath $RepoPath)) {
    Write-Host "Eliminando carpeta existente por -ForzarReclone..." -ForegroundColor Yellow
    Remove-Item -LiteralPath $RepoPath -Recurse -Force
}

if (!(Test-Path -LiteralPath $RepoPath)) {
    Write-Host "Clonando repositorio..." -ForegroundColor Green
    git clone --branch $Branch $RepoUrl $RepoPath
    if ($LASTEXITCODE -ne 0) { throw "Falló git clone." }
} else {
    Write-Host "La carpeta ya existe. Actualizando repo..." -ForegroundColor Yellow
    Push-Location $RepoPath
    try {
        git fetch origin
        if ($LASTEXITCODE -ne 0) { throw "Falló git fetch." }

        git checkout $Branch
        if ($LASTEXITCODE -ne 0) { throw "Falló git checkout." }

        git pull origin $Branch
        if ($LASTEXITCODE -ne 0) { throw "Falló git pull." }
    }
    finally {
        Pop-Location
    }
}

$DefaultEnvPath = Join-Path $RepoPath "default.env"
$EnvPath        = Join-Path $RepoPath ".env"
$ComposePath    = Join-Path $RepoPath "docker-compose.yml"

if (!(Test-Path -LiteralPath $DefaultEnvPath)) {
    throw "No existe el archivo default.env en $RepoPath"
}

if (!(Test-Path -LiteralPath $ComposePath)) {
    throw "No existe el archivo docker-compose.yml en $RepoPath"
}

if (!(Test-Path -LiteralPath $EnvPath)) {
    Write-Host "Copiando default.env a .env..." -ForegroundColor Green
    Copy-Item -LiteralPath $DefaultEnvPath -Destination $EnvPath -Force
} else {
    Write-Host "Ya existe .env, se va a usar ese archivo." -ForegroundColor Yellow
}

$items = Leer-EnvArchivo -Path $EnvPath

Write-Host ""
Write-Host "=== Configuración de variables ===" -ForegroundColor Cyan
Write-Host "Enter deja el valor actual."
Write-Host ""

foreach ($item in $items) {
    if ($item.Tipo -ne "env") { continue }
    $item.Value = Pedir-Valor -Nombre $item.Key -ValorActual $item.Value
}

Guardar-EnvArchivo -Path $EnvPath -Items $items

Write-Host ""
Write-Host "Archivo .env guardado." -ForegroundColor Green
Write-Host ""

Push-Location $RepoPath
try {
    Write-Host "Levantando contenedores..." -ForegroundColor Green
    docker compose up -d
    if ($LASTEXITCODE -ne 0) { throw "Falló docker compose up -d." }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "Todo listo." -ForegroundColor Cyan