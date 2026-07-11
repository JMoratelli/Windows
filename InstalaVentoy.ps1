# ==============================================================================
# CONFIGURAÇÃO DE SCRIPT
# ==============================================================================
$IsoName = "WindowsMachadaoCorp.iso"
$DownloadsFolder = "$HOME\Downloads"
$VentoyExtractRoot = Join-Path $DownloadsFolder "VentoyExtracted"

# ==============================================================================
# 1. VALIDAÇÃO DE PRIVILÉGIOS
# ==============================================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Este script precisa ser executado como Administrador!"
    Exit
}

# ==============================================================================
# 2. LOCALIZAÇÃO DA ISO (BUSCA PADRÃO + AMPLIAÇÃO SE NECESSÁRIO)
# ==============================================================================
Write-Host "Procurando o arquivo '$IsoName' nas pastas padrão..." -ForegroundColor Cyan
$searchPaths = @("$HOME\Downloads", "$HOME\Documents", "$HOME\Desktop")
$IsoPath = $null

foreach ($path in $searchPaths) {
    $targetFile = Join-Path $path $IsoName
    if (Test-Path $targetFile) {
        $IsoPath = $targetFile
        break
    }
}

if (-not $IsoPath) {
    Write-Host "A ISO não foi encontrada em Downloads, Documentos ou Desktop." -ForegroundColor Yellow
    $ampliar = Read-Host "Deseja ampliar a busca por todo o computador (Unidades C:, D:, etc.)? Isso pode levar alguns minutos (S/N)"
    
    if ($ampliar -match '^[sS]') {
        Write-Host "Buscando em todas as unidades de armazenamento locais. Aguarde..." -ForegroundColor Cyan
        $localDrives = (Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }).DriveLetter
        
        foreach ($drive in $localDrives) {
            Write-Host "Varrendo a unidade ${drive}:..." -ForegroundColor Gray
            $foundFile = Get-ChildItem -Path "${drive}:\" -Filter $IsoName -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($foundFile) {
                $IsoPath = $foundFile.FullName
                break
            }
        }
    }
}

if (-not $IsoPath) {
    Write-Error "Erro: O arquivo '$IsoName' não foi localizado. Certifique-se de que o nome está correto e o arquivo está no PC."
    Exit
}
Write-Host "ISO encontrada com sucesso em: $IsoPath" -ForegroundColor Green

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
# 7. IDENTIFICAÇÃO DA LETRA DA UNIDADE E CÓPIA DA ISO
# ==============================================================================
Write-Host "Aguardando o sistema remontar as partições nativas do Ventoy..." -ForegroundColor Cyan
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

$isoSizeBytes = (Get-Item $IsoPath).Length
$freeSpaceBytes = (Get-Volume -DriveLetter $finalDriveLetter).SizeRemaining
if ($freeSpaceBytes -lt $isoSizeBytes) {
    $isoSizeGB = [Math]::Round($isoSizeBytes / 1GB, 2)
    $freeSpaceGB = [Math]::Round($freeSpaceBytes / 1GB, 2)
    Write-Error "Espaço insuficiente no pendrive. ISO: $isoSizeGB GB / Livre: $freeSpaceGB GB."
    Exit
}

Write-Host "Copiando '$IsoName' para a raiz do seu Ventoy ($destinationPath)..." -ForegroundColor Cyan
Copy-Item -Path $IsoPath -Destination $destinationPath

Write-Host "`n[CONCLUÍDO] Script finalizado com sucesso! Seu pendrive bootável está pronto utilizando o padrão nativo do Ventoy." -ForegroundColor Green
