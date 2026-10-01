<#
    InstalaRTSP2CAM.ps1 - Instala, atualiza ou reconfigura o RTSP2CAM
    (camera IP RTSP -> webcam virtual). Interface WinForms - padrao Machadao Corp

    Todo o trabalho fica no rtsp2cam.exe (instalador, servico e tela de
    configuracao num arquivo so). Este script so:
      1. baixa o RTSP2CAM.exe do repositorio e confere o SHA256;
      2. se a mesma versao ja esta instalada -> abre a tela de configuracao;
         se nao -> roda "rtsp2cam.exe --instalar" (instala/atualiza e pede a
         configuracao da camera se ela ainda nao existir);
      3. sem internet, mas ja instalado -> abre a configuracao da versao local;
      4. se sobrou qualquer coisa da versao antiga (softcam, Tarefa Agendada,
         pasta RTSP2CamJJ), sempre passa pelo --instalar, que remove tudo e
         aproveita a configuracao da camera.

    Executar:  pelo 1-Menu.ps1, botao direito -> "Executar com o PowerShell"
               ou: powershell -ExecutionPolicy Bypass -File .\InstalaRTSP2CAM.ps1

    Desenvolvido por @JJMoratelli
#>

$ErrorActionPreference = 'Stop'

# ============================================================ CONSOLE OCULTO
Add-Type -Namespace Nativo -Name Janela -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")]   public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@ -ErrorAction SilentlyContinue
try {
    $h = [Nativo.Janela]::GetConsoleWindow()
    if ($h -ne [System.IntPtr]::Zero) { [Nativo.Janela]::ShowWindow($h, 0) | Out-Null }
}
catch { }

# ============================================================ CONFIGURACOES
$script:Base       = 'https://raw.githubusercontent.com/JMoratelli/Windows/refs/heads/main/Softwares'
# Para testar antes de publicar: RTSP2CAM_BASE=file:///C:/caminho/da/pasta
if ($env:RTSP2CAM_BASE) { $script:Base = $env:RTSP2CAM_BASE.TrimEnd('/') }
$script:ExeUrl     = "$($script:Base)/RTSP2CAM.exe"
$script:HashUrl    = "$($script:Base)/RTSP2CAM.exe.sha256"
$script:ScriptUrl  = "$($script:Base)/InstalaRTSP2CAM.ps1"
$script:Instalado  = Join-Path $env:ProgramFiles 'RTSP2CAM\rtsp2cam.exe'

# ============================================================ AUTO-ELEVAR
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$id).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    # Rodando de arquivo: relanca o arquivo. Via "irm | iex": relanca o mesmo comando.
    if ($PSCommandPath) {
        $argsElev = @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    }
    else {
        $argsElev = @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-Command',
            "irm '$($script:ScriptUrl)' | iex")
    }
    Start-Process -FilePath 'powershell' -Verb RunAs -WindowStyle Hidden -ArgumentList $argsElev
    return
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ============================================================ PALETA
$CorPreto   = [System.Drawing.ColorTranslator]::FromHtml("#12161C")
$CorAzul    = [System.Drawing.ColorTranslator]::FromHtml("#1A5FB4")
$CorAzulH   = [System.Drawing.ColorTranslator]::FromHtml("#154C90")
$CorGrafite = [System.Drawing.ColorTranslator]::FromHtml("#5B6672")
$CorClaro   = [System.Drawing.ColorTranslator]::FromHtml("#9AA4AF")
$CorEyebrow = [System.Drawing.ColorTranslator]::FromHtml("#7C93AE")
$CorCredito = [System.Drawing.ColorTranslator]::FromHtml("#B4BCC5")
$CorVerde   = [System.Drawing.ColorTranslator]::FromHtml("#0A6F66")
$CorAmbar   = [System.Drawing.ColorTranslator]::FromHtml("#8A5A00")
$CorErro    = [System.Drawing.ColorTranslator]::FromHtml("#C01C28")
$CorPainel  = [System.Drawing.ColorTranslator]::FromHtml("#EDEFF2")

# ============================================================ JANELA
$LARG = 560
$script:Form = New-Object System.Windows.Forms.Form
$script:Form.Text            = "RTSP2CAM - Webcam virtual"
$script:Form.ClientSize      = New-Object System.Drawing.Size($LARG, 300)
$script:Form.FormBorderStyle = 'FixedDialog'
$script:Form.MaximizeBox     = $false
$script:Form.MinimizeBox     = $false
$script:Form.StartPosition   = 'CenterScreen'
$script:Form.TopMost         = $true
$script:Form.BackColor       = [System.Drawing.Color]::White

$cab = New-Object System.Windows.Forms.Panel
$cab.BackColor = $CorPreto
$cab.Location  = New-Object System.Drawing.Point(0, 0)
$cab.Size      = New-Object System.Drawing.Size($LARG, 94)
$script:Form.Controls.Add($cab)

$eyebrow = New-Object System.Windows.Forms.Label
$eyebrow.Text      = "M A C H A D A O   C O R P"
$eyebrow.Font      = New-Object System.Drawing.Font("Consolas", 9)
$eyebrow.ForeColor = $CorEyebrow
$eyebrow.Location  = New-Object System.Drawing.Point(36, 18)
$eyebrow.AutoSize  = $true
$cab.Controls.Add($eyebrow)

$titulo = New-Object System.Windows.Forms.Label
$titulo.Text      = "RTSP2CAM  Webcam virtual"
$titulo.Font      = New-Object System.Drawing.Font("Segoe UI", 19)
$titulo.ForeColor = [System.Drawing.Color]::White
$titulo.Location  = New-Object System.Drawing.Point(32, 38)
$titulo.AutoSize  = $true
$cab.Controls.Add($titulo)

$maquina = New-Object System.Windows.Forms.Label
$maquina.Text      = $env:COMPUTERNAME
$maquina.Font      = New-Object System.Drawing.Font("Consolas", 10)
$maquina.ForeColor = $CorClaro
$maquina.TextAlign = 'MiddleRight'
$maquina.Location  = New-Object System.Drawing.Point(($LARG - 236), 22)
$maquina.Size      = New-Object System.Drawing.Size(200, 20)
$cab.Controls.Add($maquina)

$script:msg = New-Object System.Windows.Forms.Label
$script:msg.Font      = New-Object System.Drawing.Font("Segoe UI", 11)
$script:msg.ForeColor = $CorGrafite
$script:msg.Location  = New-Object System.Drawing.Point(36, 122)
$script:msg.Size      = New-Object System.Drawing.Size(($LARG - 72), 80)
$script:msg.Text      = "Preparando..."
$script:Form.Controls.Add($script:msg)

$credito = New-Object System.Windows.Forms.Label
$credito.Text      = "Desenvolvido por @JJMoratelli"
$credito.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$credito.ForeColor = $CorCredito
$credito.Location  = New-Object System.Drawing.Point(36, 252)
$credito.AutoSize  = $true
$script:Form.Controls.Add($credito)

$script:btn = New-Object System.Windows.Forms.Button
$script:btn.Text      = "Aguarde..."
$script:btn.Font      = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$script:btn.Size      = New-Object System.Drawing.Size(190, 52)
$script:btn.Location  = New-Object System.Drawing.Point(($LARG - 36 - 190), 224)
$script:btn.FlatStyle = 'Flat'
$script:btn.FlatAppearance.BorderSize = 0
$script:btn.BackColor = $CorAzul
$script:btn.ForeColor = [System.Drawing.Color]::White
$script:btn.FlatAppearance.MouseOverBackColor = $CorAzulH
$script:btn.FlatAppearance.MouseDownBackColor = $CorAzulH
$script:btn.Enabled   = $false
$script:Form.Controls.Add($script:btn)

$script:Ocupado = $true
$script:Form.Add_FormClosing({ if ($script:Ocupado) { $_.Cancel = $true } })

# ============================================================ AJUDANTES
function Mensagem($texto, $cor) {
    $script:msg.ForeColor = $cor
    $script:msg.Text      = $texto
    [System.Windows.Forms.Application]::DoEvents()
}

function Esperar($ms) {
    $fim = (Get-Date).AddMilliseconds($ms)
    while ((Get-Date) -lt $fim) {
        Start-Sleep -Milliseconds 50
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Hash($arquivo) { (Get-FileHash -Path $arquivo -Algorithm SHA256).Hash.ToUpperInvariant() }

# Baixa o exe e confere com o .sha256 publicado ao lado. Devolve o caminho
# ou $null se nao der (sem internet, download corrompido).
function Baixar {
    Get-ChildItem -Path $env:TEMP -Filter 'rtsp2cam-*.exe' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    $destino = Join-Path $env:TEMP ("rtsp2cam-{0}.exe" -f [guid]::NewGuid().ToString('N'))
    try {
        $resp = Invoke-WebRequest -Uri $script:HashUrl -UseBasicParsing -TimeoutSec 30
        # Conforme o servidor, o conteudo vem como texto ou como bytes.
        $texto = if ($resp.Content -is [byte[]]) { [Text.Encoding]::ASCII.GetString($resp.Content) } else { [string]$resp.Content }
        $esperado = ($texto.Trim() -split '\s+')[0].ToUpperInvariant()
        if ($esperado -notmatch '^[0-9A-F]{64}$') { throw "arquivo .sha256 invalido" }
        Invoke-WebRequest -Uri $script:ExeUrl -OutFile $destino -UseBasicParsing -TimeoutSec 300
    }
    catch {
        $script:ErroDownload = $_.Exception.Message
        return $null
    }
    if ((Hash $destino) -ne $esperado) {
        Remove-Item $destino -Force -ErrorAction SilentlyContinue
        $script:ErroDownload = "o arquivo baixado nao confere com o SHA256 publicado (download corrompido)"
        return $null
    }
    return $destino
}

function Abrir($exe, $argumento) {
    Start-Process -FilePath $exe -ArgumentList $argumento
}

# Restos da versao antiga (softcam + Tarefa Agendada em RTSP2CamJJ). Quem
# remove tudo e o "RTSP2CAM.exe --instalar": encerra os processos, apaga a
# tarefa, desregistra a softcam, importa a configuracao (senha passa a ser
# protegida) e apaga a pasta antiga, que tinha a senha em texto puro.
function TemVersaoAntiga {
    if (Test-Path (Join-Path $env:ProgramFiles 'RTSP2CamJJ')) { return $true }
    if (Get-ScheduledTask -TaskName 'rtsp2cam' -ErrorAction SilentlyContinue) { return $true }
    foreach ($k in 'HKLM:\SOFTWARE\Classes\CLSID\{AEF3B972-5FA5-4647-9571-358EB472BC9E}',
                   'HKLM:\SOFTWARE\WOW6432Node\Classes\CLSID\{AEF3B972-5FA5-4647-9571-358EB472BC9E}') {
        if (Test-Path $k) { return $true }
    }
    return $false
}

# Arquivos temporarios que o instalador antigo deixava para tras.
function LimparTemporariosAntigos {
    foreach ($n in 'RTSP2CAM.7z', 'ffmpeg.zip', '7zr.exe') {
        Remove-Item (Join-Path $env:TEMP $n) -Force -ErrorAction SilentlyContinue
    }
    Get-ChildItem -Path $env:TEMP -Directory -Filter 'ff_*' -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

function Executar {
    $script:Ocupado     = $true
    $script:btn.Enabled = $false
    $script:btn.Text    = "Aguarde..."
    $script:ErroDownload = $null

    LimparTemporariosAntigos
    $antiga = TemVersaoAntiga

    Mensagem "Baixando a versao mais recente do RTSP2CAM..." $CorGrafite
    $baixado = Baixar
    $temLocal = Test-Path $script:Instalado

    if ($antiga -and ($baixado -or $temLocal)) {
        # Sobrou algo da versao antiga: sempre passa pelo --instalar, que limpa.
        $exe = if ($baixado) { $baixado } else { $script:Instalado }
        Mensagem "Removendo a versao antiga (softcam) e instalando o RTSP2CAM novo. A configuracao da camera e aproveitada..." $CorVerde
        Abrir $exe '--instalar'
    }
    elseif ($baixado) {
        if ($temLocal -and ((Hash $baixado) -eq (Hash $script:Instalado))) {
            Remove-Item $baixado -Force -ErrorAction SilentlyContinue
            Mensagem "Ja esta na versao mais recente. Abrindo a configuracao da camera..." $CorVerde
            Abrir $script:Instalado '--configurar'
        }
        elseif ($temLocal) {
            Mensagem "Atualizando o RTSP2CAM. A configuracao atual e mantida..." $CorVerde
            Abrir $baixado '--instalar'
        }
        else {
            Mensagem "Abrindo o instalador do RTSP2CAM..." $CorVerde
            Abrir $baixado '--instalar'
        }
    }
    elseif ($temLocal) {
        Mensagem "Sem acesso ao repositorio ($($script:ErroDownload)). Abrindo a configuracao da versao ja instalada..." $CorAmbar
        Abrir $script:Instalado '--configurar'
    }
    else {
        $script:Ocupado     = $false
        $script:btn.Enabled = $true
        $script:btn.Text    = "Tentar novamente"
        Mensagem "Nao foi possivel baixar o RTSP2CAM: $($script:ErroDownload)" $CorErro
        return
    }

    # A janela do rtsp2cam.exe assume daqui; esta fecha sozinha.
    $script:Ocupado = $false
    Esperar 2500
    $script:Form.Close()
}

$script:btn.Add_Click({ if (-not $script:Ocupado) { Executar } })
$script:Form.Add_Shown({ Executar })
[void]$script:Form.ShowDialog()
$script:Form.Dispose()
