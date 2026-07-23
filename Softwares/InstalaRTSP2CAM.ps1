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
# CLSID do filtro DirectShow da softcam (usado para checar o registro).
$SoftcamClsid = '{AEF3B972-5FA5-4647-9571-358EB472BC9E}'

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

# Garante o runtime do Visual C++ (a softcam.dll depende de VCRUNTIME140 /
# MSVCP140 / UCRT). Se ja estiver presente, nao faz nada.
function GarantirVCRuntime {
    $sys = Join-Path $env:SystemRoot 'System32'
    if ((Test-Path (Join-Path $sys 'vcruntime140.dll')) -and
        (Test-Path (Join-Path $sys 'vcruntime140_1.dll')) -and
        (Test-Path (Join-Path $sys 'msvcp140.dll'))) {
        Write-Host "      runtime do Visual C++ ja presente."
        return
    }
    Write-Host "      instalando o runtime do Visual C++ (necessario para a softcam)..."
    $vc = Join-Path $env:TEMP 'vc_redist.x64.exe'
    Baixar 'https://aka.ms/vs/17/release/vc_redist.x64.exe' $vc
    $p = Start-Process -FilePath $vc -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
    Remove-Item $vc -Force -ErrorAction SilentlyContinue
    # 0 = ok, 3010 = ok (pede reinicio), 1638 = ja ha versao igual/mais nova.
    if ($p.ExitCode -notin 0, 1638, 3010) {
        throw "Falha ao instalar o Visual C++ Redistributable (codigo $($p.ExitCode))."
    }
}

# Confere no registro se o filtro DirectShow da softcam foi de fato
# registrado (a chave InprocServer32 do CLSID passa a existir).
function SoftcamRegistrada {
    $chaves = @(
        "HKLM:\SOFTWARE\Classes\CLSID\$SoftcamClsid\InprocServer32",
        "HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\$SoftcamClsid\InprocServer32"
    )
    foreach ($c in $chaves) {
        if (Test-Path $c) { return $true }
    }
    return $false
}

# Cria a Tarefa Agendada como um "watchdog":
#  - dispara no logon de qualquer usuario do grupo "Usuarios"
#    (roda como o proprio usuario, sem elevacao = integridade certa p/ camera);
#  - repete a cada 1 min, sem duplicar (se ja estiver rodando, ignora;
#    se tiver caido, sobe de novo);
#  - reinicia em caso de falha; roda oculto e sem limite de tempo.
function CriarTarefaWatchdog {
    $exe = Join-Path $Dest 'rtsp2cam.exe'
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>RTSP2Cam - mantem a webcam virtual rodando (watchdog).</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Repetition>
        <Interval>PT1M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <GroupId>S-1-5-32-545</GroupId>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>999</Count>
    </RestartOnFailure>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$exe</Command>
      <Arguments>--worker</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    $xmlPath = Join-Path $env:TEMP 'rtsp2cam_task.xml'
    [IO.File]::WriteAllText($xmlPath, $xml, [Text.Encoding]::Unicode) # UTF-16 p/ o schtasks
    & schtasks /Create /TN $TaskName /XML $xmlPath /F | Out-Null
    $ok = ($LASTEXITCODE -eq 0)
    Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue
    if (-not $ok) { throw "Falha ao criar a Tarefa Agendada (codigo $LASTEXITCODE)." }
}

try {
    Write-Host "============================================"
    Write-Host "  Instalando RTSP -> Webcam virtual"
    Write-Host "============================================`n"

    # Fecha instancia anterior, se estiver rodando.
    Get-Process rtsp2cam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    Write-Host "[1/7] Preparando pasta: $Dest"
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null

    Write-Host "[2/7] Baixando o pacote do programa..."
    $pkg = Join-Path $env:TEMP 'RTSP2CAM.7z'
    Baixar $PkgUrl $pkg
    Write-Host "      extraindo..."
    Extrair7z $pkg $Dest
    Remove-Item $pkg -Force -ErrorAction SilentlyContinue

    Write-Host "[3/7] ffmpeg..."
    $ffDest = Join-Path $Dest 'ffmpeg.exe'
    if (Test-Path $ffDest) {
        Write-Host "      ja existe na pasta, pulando o download."
    }
    else {
        Write-Host "      baixando..."
        $ffzip = Join-Path $env:TEMP 'ffmpeg.zip'
        Baixar $FfmpegUrl $ffzip
        $fftmp = Join-Path $env:TEMP ('ff_' + [guid]::NewGuid().ToString('N'))
        Expand-Archive -Path $ffzip -DestinationPath $fftmp -Force
        $ff = Get-ChildItem -Path $fftmp -Recurse -Filter 'ffmpeg.exe' | Select-Object -First 1
        if (-not $ff) { throw "ffmpeg.exe nao encontrado no pacote baixado." }
        Copy-Item $ff.FullName $ffDest -Force
        Remove-Item $ffzip -Force -ErrorAction SilentlyContinue
        Remove-Item $fftmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "`n[4/7] Dados da camera (para o rtsp2cam.conf):"
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

    Write-Host "`n[5/7] Verificando o runtime do Visual C++..."
    GarantirVCRuntime

    Write-Host "`n[6/7] Registrando a webcam virtual (softcam)..."
    & regsvr32 /s (Join-Path $Dest 'softcam.dll')
    Start-Sleep -Milliseconds 500
    if (-not (SoftcamRegistrada)) {
        throw ("A softcam NAO ficou registrada. Confira se o runtime do Visual C++ " +
               "foi instalado e se voce esta rodando como administrador.")
    }
    Write-Host "      registrada e verificada (DirectShow Softcam)."

    Write-Host "[7/7] Criando inicio automatico (watchdog) e iniciando..."
    CriarTarefaWatchdog
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
