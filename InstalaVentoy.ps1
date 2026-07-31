# Instala, Configura e Atualiza Ventoy
# ==============================================================================
# CONFIGURAÇÃO DE SCRIPT
# ==============================================================================
$DownloadsFolder = "$HOME\Downloads"
$VentoyExtractRoot = Join-Path $DownloadsFolder "VentoyExtracted"

# Catálogo de ISOs suportadas.
# 'Padrao' aceita curingas (*) para tolerar variações no nome do arquivo.
$IsosCatalogo = @(
    [PSCustomObject]@{
        Rotulo = "Windows 11 25H2 - Machadao Corp V5"
        Padrao = "Win11_25H2_JJ-MachadaoCorpV6.iso"
    },
    [PSCustomObject]@{
        Rotulo = "Instalador PDV - Ubuntu 22.04 (1.14)"
        Padrao = "InstaladorPDV-2.U2204.680.1.14-64-001*.iso"
    }
)

$SearchPaths = @("$HOME\Downloads", "$HOME\Documents", "$HOME\Desktop")

# ==============================================================================
# 1. VALIDAÇÃO DE PRIVILÉGIOS
# ==============================================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Este script precisa ser executado como Administrador!"
    Exit
}

# ==============================================================================
# 2. LOCALIZAÇÃO DAS ISOs (BUSCA PADRÃO + AMPLIAÇÃO SE NECESSÁRIO)
# ==============================================================================
function Find-IsoFile {
    param(
        [string]$Padrao,
        [string[]]$Paths
    )
    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) { continue }
        $hit = Get-ChildItem -Path $path -Filter $Padrao -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

Write-Host "Procurando as ISOs nas pastas padrão..." -ForegroundColor Cyan

$IsosEncontradas = @()
foreach ($iso in $IsosCatalogo) {
    $caminho = Find-IsoFile -Padrao $iso.Padrao -Paths $SearchPaths
    if ($caminho) {
        Write-Host "  [OK]     $($iso.Rotulo)" -ForegroundColor Green
        $IsosEncontradas += [PSCustomObject]@{ Rotulo = $iso.Rotulo; Caminho = $caminho }
    } else {
        Write-Host "  [AUSENTE] $($iso.Rotulo)" -ForegroundColor DarkYellow
    }
}

# Se faltou alguma, oferece a busca ampliada em todas as unidades fixas
if ($IsosEncontradas.Count -lt $IsosCatalogo.Count) {
    Write-Host "`nNem todas as ISOs foram localizadas nas pastas padrão." -ForegroundColor Yellow
    $ampliar = Read-Host "Deseja ampliar a busca por todo o computador (Unidades C:, D:, etc.)? Isso pode levar alguns minutos (S/N)"

    if ($ampliar -match '^[sS]') {
        $localDrives = (Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }).DriveLetter
        $faltantes = $IsosCatalogo | Where-Object { $_.Rotulo -notin $IsosEncontradas.Rotulo }

        foreach ($iso in $faltantes) {
            Write-Host "Buscando '$($iso.Rotulo)' em todas as unidades locais. Aguarde..." -ForegroundColor Cyan
            foreach ($drive in $localDrives) {
                Write-Host "  Varrendo a unidade ${drive}:..." -ForegroundColor Gray
                $found = Get-ChildItem -Path "${drive}:\" -Filter $iso.Padrao -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    Write-Host "  [OK] Encontrada em: $($found.FullName)" -ForegroundColor Green
                    $IsosEncontradas += [PSCustomObject]@{ Rotulo = $iso.Rotulo; Caminho = $found.FullName }
                    break
                }
            }
        }
    }
}

# ==============================================================================
# 2.1 SELEÇÃO DAS ISOs A COPIAR
# ==============================================================================
$IsosSelecionadas = @()

if ($IsosEncontradas.Count -eq 0) {
    Write-Host "`nNão foram encontradas as ISOs." -ForegroundColor Red
    $continuar = Read-Host "Continuar sem copiar ISOs para o pendrive? (S/N)"
    if ($continuar -notmatch '^[sS]') {
        Write-Host "Operação cancelada."
        Exit
    }
    Write-Host "Ok, o Ventoy será instalado/atualizado sem copiar nenhuma ISO." -ForegroundColor Yellow
}
else {
    Write-Host "`n--- ISOs DISPONÍVEIS PARA CÓPIA ---" -ForegroundColor Yellow
    for ($i = 0; $i -lt $IsosEncontradas.Count; $i++) {
        $tamGB = [Math]::Round((Get-Item $IsosEncontradas[$i].Caminho).Length / 1GB, 2)
        Write-Host "[$($i + 1)] $($IsosEncontradas[$i].Rotulo)  ($tamGB GB)" -ForegroundColor White
        Write-Host "     $($IsosEncontradas[$i].Caminho)" -ForegroundColor DarkGray
    }
    Write-Host "[T] Todas as ISOs listadas" -ForegroundColor White
    Write-Host "[0] Nenhuma (apenas instalar/atualizar o Ventoy)" -ForegroundColor White

    $escolhaValida = $false
    while (-not $escolhaValida) {
        $escolha = (Read-Host "`nDigite sua escolha (ex: 1, ou 1,2, ou T, ou 0)").Trim()

        if ($escolha -match '^[tT]$') {
            $IsosSelecionadas = $IsosEncontradas
            $escolhaValida = $true
        }
        elseif ($escolha -eq '0') {
            $IsosSelecionadas = @()
            $escolhaValida = $true
        }
        elseif ($escolha -match '^\s*\d+(\s*,\s*\d+)*\s*$') {
            $indices = $escolha -split ',' | ForEach-Object { [int]$_.Trim() } | Select-Object -Unique
            if (($indices | Where-Object { $_ -lt 1 -or $_ -gt $IsosEncontradas.Count }).Count -gt 0) {
                Write-Host "Seleção fora do intervalo. Tente novamente." -ForegroundColor Red
            } else {
                $IsosSelecionadas = @($indices | ForEach-Object { $IsosEncontradas[$_ - 1] })
                $escolhaValida = $true
            }
        }
        else {
            Write-Host "Entrada inválida. Tente novamente." -ForegroundColor Red
        }
    }

    if ($IsosSelecionadas.Count -eq 0) {
        Write-Host "Nenhuma ISO será copiada. Seguindo apenas com o Ventoy." -ForegroundColor Yellow
    } else {
        Write-Host "Selecionado(s): $($IsosSelecionadas.Rotulo -join ' | ')" -ForegroundColor Green
    }
}

# ==============================================================================
# 3. CHECAGEM DE VERSÃO E DOWNLOAD AUTOMÁTICO DO VENTOY (GITHUB)
# ==============================================================================
Write-Host "`nBuscando a versão mais recente do Ventoy no GitHub..." -ForegroundColor Cyan
$repoUrl = "https://api.github.com/repos/ventoy/Ventoy/releases/latest"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    $releaseInfo = Invoke-RestMethod -Uri $repoUrl -UseBasicParsing
    $asset = $releaseInfo.assets | Where-Object { $_.name -like "*windows.zip" } | Select-Object -First 1

    if (-not $asset) { throw "Não foi possível encontrar o arquivo zip do Windows no GitHub." }

    # Identifica o nome esperado da pasta interna (ex: ventoy-1.0.99)
    $expectedFolderName = $asset.name -replace '-windows\.zip$', ''
    $VentoyDir = Join-Path $VentoyExtractRoot $expectedFolderName
    $ventoyExePath = Join-Path $VentoyDir "Ventoy2Disk.exe"

    # Verifica se a versão do GitHub já bate com a local
    if (Test-Path $ventoyExePath) {
        Write-Host "A versão mais recente ($expectedFolderName) já está disponível localmente. Pulando download!" -ForegroundColor Green
    } else {
        Write-Host "Nova versão detectada ou arquivos ausentes. Baixando $($asset.name)..." -ForegroundColor Cyan
        $zipPath = Join-Path $DownloadsFolder $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UserAgent "Mozilla/5.0"

        Write-Host "Extraindo arquivos do Ventoy..." -ForegroundColor Cyan
        if (Test-Path $VentoyExtractRoot) { Remove-Item $VentoyExtractRoot -Recurse -Force }
        Expand-Archive -Path $zipPath -DestinationPath $VentoyExtractRoot -Force

        # Redireciona para a pasta correta extraída
        $VentoyDir = (Get-ChildItem $VentoyExtractRoot -Directory | Where-Object { $_.Name -like "ventoy-*" } | Select-Object -First 1).FullName
        Remove-Item $zipPath -Force
    }
}
catch {
    Write-Error "Falha ao processar o Ventoy do GitHub: $_"
    Exit
}

# ==============================================================================
# 4. SELEÇÃO DA UNIDADE REMOVÍVEL
# ==============================================================================
Write-Host "`nBuscando unidades USB qualificadas (< 100GB)..." -ForegroundColor Cyan
$disks = @(Get-Disk | Where-Object { $_.BusType -eq 'USB' -and $_.Size -lt 100GB })

if ($disks.Count -eq 0) {
    Write-Error "Nenhum pendrive USB menor que 100GB foi detectado."
    Exit
}

Write-Host "`n--- UNIDADES USB DETECTADAS ---" -ForegroundColor Yellow
for ($i = 0; $i -lt $disks.Count; $i++) {
    $sizeGB = [Math]::Round($disks[$i].Size / 1GB, 2)
    Write-Host "[$i] Disco Nº $($disks[$i].Number) - Nome: $($disks[$i].FriendlyName) - Tamanho: $sizeGB GB" -ForegroundColor White
}

$selection = Read-Host "`nDigite o número correspondente ao pendrive que deseja usar (ex: 0, 1)"
if ($selection -match '^\d+$' -and [int]$selection -lt $disks.Count) {
    $targetDisk = $disks[[int]$selection]
    $diskNumber = $targetDisk.Number
} else {
    Write-Error "Seleção inválida."
    Exit
}

# ==============================================================================
# 5. ANÁLISE /U OU /I (MANTÉM OU FORMATA)
# ==============================================================================
$partitions = Get-Partition -DiskNumber $diskNumber
$ventoyVolume = Get-Volume | Where-Object { $_.DriveLetter -and ($_.DriveLetter -in $partitions.DriveLetter) -and $_.FileSystemLabel -eq "Ventoy" }

if ($ventoyVolume) {
    $action = "/U"
    Write-Host "Ventoy detectado no pendrive. O script usará ATUALIZAÇÃO (/U) para preservar arquivos." -ForegroundColor Yellow
} else {
    $action = "/I"
    Write-Host "Instalação limpa necessária. ATENÇÃO: Todos os dados do pendrive selecionado serão apagados pelo Ventoy!" -ForegroundColor Red
    $confirm = Read-Host "Deseja continuar? (S/N)"
    if ($confirm -notmatch '^[sS]') { Write-Host "Operação cancelada."; Exit }
}

# ==============================================================================
# 6. INSTALAÇÃO/ATUALIZAÇÃO DO VENTOY CLI
# ==============================================================================
Set-Location $VentoyDir
$ventoyExe = ".\Ventoy2Disk.exe"

if ($action -eq "/I") {
    $ventoyArgs = @("VTOYCLI", "/I", "/PhyDrive:$diskNumber", "/GPT")
} else {
    $ventoyArgs = @("VTOYCLI", "/U", "/PhyDrive:$diskNumber")
}

Write-Host "Executando o Ventoy... Não desconecte o dispositivo." -ForegroundColor Cyan
$process = Start-Process -FilePath $ventoyExe -ArgumentList $ventoyArgs -WorkingDirectory $VentoyDir -Wait -NoNewWindow -PassThru

Start-Sleep -Seconds 3
$cliDonePath = Join-Path $VentoyDir "cli_done.txt"
if (Test-Path $cliDonePath) {
    if ((Get-Content $cliDonePath -Raw).Trim() -ne "0") {
        Write-Error "Ocorreu um erro na execução do Ventoy. Verifique cli_log.txt em $VentoyDir para detalhes."
        Exit
    }
} else {
    Write-Warning "Não foi possível confirmar o resultado (cli_done.txt não encontrado). Verifique manualmente o pendrive."
}

# ==============================================================================
# 7. IDENTIFICAÇÃO DA LETRA DA UNIDADE E CÓPIA DAS ISOs
# ==============================================================================
if ($IsosSelecionadas.Count -eq 0) {
    Write-Host "`n[CONCLUÍDO] Ventoy instalado/atualizado com sucesso. Nenhuma ISO foi copiada." -ForegroundColor Green
    Exit
}

Write-Host "`nAguardando o sistema remontar as partições nativas do Ventoy..." -ForegroundColor Cyan
Start-Sleep -Seconds 6

$partitions = Get-Partition -DiskNumber $diskNumber
$ventoyVolume = Get-Volume | Where-Object { $_.DriveLetter -and ($_.DriveLetter -in $partitions.DriveLetter) -and $_.FileSystemLabel -eq "Ventoy" }

$finalDriveLetter = $ventoyVolume.DriveLetter
if (-not $finalDriveLetter) {
    # Fallback caso a etiqueta de volume demore para carregar no Windows
    $finalDriveLetter = ($partitions | Where-Object DriveLetter | Sort-Object Size -Descending | Select-Object -First 1).DriveLetter
}

if (-not $finalDriveLetter) {
    Write-Error "Não foi possível obter a letra do drive para transferir os dados."
    Exit
}

$destinationPath = "$($finalDriveLetter):\"

# Calcula o espaço necessário, ignorando ISOs que já existem com o mesmo tamanho
$aCopiar = @()
foreach ($item in $IsosSelecionadas) {
    $origem = Get-Item $item.Caminho
    $destino = Join-Path $destinationPath $origem.Name
    if ((Test-Path $destino) -and ((Get-Item $destino).Length -eq $origem.Length)) {
        Write-Host "'$($origem.Name)' já está no pendrive com o mesmo tamanho. Pulando." -ForegroundColor Yellow
        continue
    }
    $aCopiar += $origem
}

if ($aCopiar.Count -eq 0) {
    Write-Host "`n[CONCLUÍDO] Nada a copiar - o pendrive já está atualizado." -ForegroundColor Green
    Exit
}

$totalBytes = ($aCopiar | Measure-Object -Property Length -Sum).Sum
$freeSpaceBytes = (Get-Volume -DriveLetter $finalDriveLetter).SizeRemaining
if ($freeSpaceBytes -lt $totalBytes) {
    $totalGB = [Math]::Round($totalBytes / 1GB, 2)
    $freeSpaceGB = [Math]::Round($freeSpaceBytes / 1GB, 2)
    Write-Error "Espaço insuficiente no pendrive. Necessário: $totalGB GB / Livre: $freeSpaceGB GB."
    Exit
}

foreach ($origem in $aCopiar) {
    Write-Host "Copiando '$($origem.Name)' para $destinationPath ..." -ForegroundColor Cyan
    try {
        Copy-Item -Path $origem.FullName -Destination $destinationPath -Force -ErrorAction Stop
        Write-Host "  Concluído." -ForegroundColor Green
    } catch {
        Write-Error "Falha ao copiar '$($origem.Name)': $_"
    }
}

Write-Host "`n[CONCLUÍDO] Script finalizado com sucesso! Seu pendrive bootável está pronto utilizando o padrão nativo do Ventoy." -ForegroundColor Green
