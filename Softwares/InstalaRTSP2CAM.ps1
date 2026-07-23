# ============================================================
#  instalar.ps1  -  Instalador do RTSP2Cam (RTSP -> Webcam)
# ============================================================
#  O que faz:
#   1. Se eleva para Administrador.
#   2. Baixa o pacote (rtsp2cam.exe + softcam.dll) e o extrai em
#      C:\Program Files\RTSP2CamJJ
#   3. Baixa o ffmpeg.exe e deixa junto.
#   4. Pergunta IP, usuario e senha da camera e gera o rtsp2cam.conf.
#   5. Registra a webcam virtual (softcam) silenciosamente.
#   6. Cria a Tarefa Agendada de inicio automatico e ja inicia.
#
#  Como rodar:
#   - Botao direito neste arquivo -> "Executar com o PowerShell"
#   - Ou:  powershell -ExecutionPolicy Bypass -File .\instalar.ps1
# ============================================================

$ErrorActionPreference = 'Stop'

# ---- Configuracoes ----
$AppName    = 'RTSP2CamJJ'
$Dest       = Join-Path $env:ProgramFiles $AppName
$TaskName   = 'rtsp2cam'
$PkgUrl     = 'https://raw.githubusercontent.com/JMoratelli/Windows/refs/heads/main/Softwares/RTSP2CAM.7z'
$FfmpegUrl  = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip'
$SevenZrUrl = 'https://www.7-zip.org/a/7zr.exe'

# ---- Auto-elevar para Administrador ----
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$id).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Solicitando privilegios de administrador..."
    Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList `
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath
    exit
}

# TLS 1.2 (necessario em Windows PowerShell 5.1 para baixar do GitHub).
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Baixar($url, $saida) {
    Write-Host "  baixando: $url"
    Invoke-WebRequest -Uri $url -OutFile $saida -UseBasicParsing
}

# Extrai um .7z: tenta o tar.exe embutido; se falhar, usa o 7zr.exe oficial.
function Extrair7z($arquivo, $destino) {
    try { & tar.exe -xf $arquivo -C $destino 2>$null } catch { }
    if (Test-Path (Join-Path $destino 'rtsp2cam.exe')) { return }

    Write-Host "  (tar nao serviu; baixando o extrator 7zr.exe)"
    $z = Join-Path $env:TEMP '7zr.exe'
    Baixar $SevenZrUrl $z
    & $z x $arquivo "-o$destino" -y | Out-Null
    if (-not (Test-Path (Join-Path $destino 'rtsp2cam.exe'))) {
        throw "Nao consegui extrair o pacote .7z."
    }
}

try {
    Write-Host "============================================"
    Write-Host "  Instalando RTSP -> Webcam virtual"
    Write-Host "============================================`n"

    # Fecha instancia anterior, se estiver rodando.
    Get-Process rtsp2cam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    Write-Host "[1/6] Preparando pasta: $Dest"
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null

    Write-Host "[2/6] Baixando o pacote do programa..."
    $pkg = Join-Path $env:TEMP 'RTSP2CAM.7z'
    Baixar $PkgUrl $pkg
    Write-Host "      extraindo..."
    Extrair7z $pkg $Dest
    Remove-Item $pkg -Force -ErrorAction SilentlyContinue

    Write-Host "[3/6] Baixando o ffmpeg..."
    $ffzip = Join-Path $env:TEMP 'ffmpeg.zip'
    Baixar $FfmpegUrl $ffzip
    $fftmp = Join-Path $env:TEMP ('ff_' + [guid]::NewGuid().ToString('N'))
    Expand-Archive -Path $ffzip -DestinationPath $fftmp -Force
    $ff = Get-ChildItem -Path $fftmp -Recurse -Filter 'ffmpeg.exe' | Select-Object -First 1
    if (-not $ff) { throw "ffmpeg.exe nao encontrado no pacote baixado." }
    Copy-Item $ff.FullName (Join-Path $Dest 'ffmpeg.exe') -Force
    Remove-Item $ffzip -Force -ErrorAction SilentlyContinue
    Remove-Item $fftmp -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "`n[4/6] Dados da camera (para o rtsp2cam.conf):"
    $ip    = Read-Host "      IP da camera (ex: 192.168.1.10)"
    $login = Read-Host "      Usuario"
    $sec   = Read-Host "      Senha" -AsSecureString
    $bstr  = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    $senha = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    $conf = @"
# Configuracao do rtsp2cam (gerada pelo instalador)
# Os marcadores USUARIO, SENHA, IP e PORTA na linha RTSP sao trocados
# pelos valores abaixo. Para outra marca de camera, troque so o final:
#   Hikvision: /Streaming/Channels/101
RTSP=rtsp://USUARIO:SENHA@IP:PORTA/cam/realmonitor?channel=1&subtype=0
IP=$ip
LOGIN=$login
SENHA=$senha
PORTA=554
WIDTH=1280
HEIGHT=720
FPS=25
"@
    [IO.File]::WriteAllText(
        (Join-Path $Dest 'rtsp2cam.conf'),
        $conf,
        (New-Object System.Text.UTF8Encoding($false)))  # UTF-8 sem BOM

    Write-Host "`n[5/6] Registrando a webcam virtual (softcam)..."
    & regsvr32 /s (Join-Path $Dest 'softcam.dll')
    if ($LASTEXITCODE -ne 0) { throw "Falha ao registrar a softcam.dll." }

    Write-Host "[6/6] Criando inicio automatico e iniciando..."
    & (Join-Path $Dest 'rtsp2cam.exe') --install-task | Out-Null
    # Inicia agora pela tarefa (roda como usuario normal, sem elevacao,
    # que e o correto para a camera aparecer nos apps).
    & schtasks /run /tn $TaskName 2>$null | Out-Null

    Write-Host "`n============================================"
    Write-Host "  Instalado com sucesso!"
    Write-Host "============================================`n"
    Write-Host "Instalado em: $Dest"
    Write-Host "A camera 'softcam' ja deve estar ativa."
    Write-Host "Abra OBS, VLC, Zoom, Teams ou o navegador e escolha 'softcam'."
    Write-Host "(O app 'Camera' do Windows NAO lista a softcam - isso e normal.)`n"
}
catch {
    Write-Host "`n[ERRO] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Verifique sua conexao com a internet e tente de novo."
}
finally {
    Read-Host "Pressione Enter para sair"
}
