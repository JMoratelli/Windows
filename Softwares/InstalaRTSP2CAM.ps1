<#
    InstalaRTSP2CAM.ps1 - Instalador do RTSP2Cam (RTSP -> Webcam virtual)
    Interface WinForms - padrao Machadao Corp

    Executar:  botao direito -> "Executar com o PowerShell"
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

# ============================================================ AUTO-ELEVAR
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$id).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath 'powershell' -Verb RunAs -WindowStyle Hidden -ArgumentList `
        '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath
    return
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ============================================================ CONFIGURACOES
$script:AppName    = 'RTSP2CamJJ'
$script:Dest       = Join-Path $env:ProgramFiles $script:AppName
$script:TaskName   = 'rtsp2cam'
$script:PkgUrl     = 'https://raw.githubusercontent.com/JMoratelli/Windows/refs/heads/main/Softwares/RTSP2CAM.7z'
$script:FfmpegUrl  = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip'
$script:SevenZrUrl = 'https://www.7-zip.org/a/7zr.exe'
$script:SoftcamClsid = '{AEF3B972-5FA5-4647-9571-358EB472BC9E}'

# Modelo padrao (Intelbras/Dahua). Marcadores trocados pelo proprio rtsp2cam.
$script:UrlPadrao = 'rtsp://USUARIO:SENHA@IP:PORTA/cam/realmonitor?channel=1&subtype=0'

# ============================================================ PALETA
$Preto   = [System.Drawing.ColorTranslator]::FromHtml("#12161C")
$Azul    = [System.Drawing.ColorTranslator]::FromHtml("#1A5FB4")
$AzulH   = [System.Drawing.ColorTranslator]::FromHtml("#154C90")
$Grafite = [System.Drawing.ColorTranslator]::FromHtml("#5B6672")
$Claro   = [System.Drawing.ColorTranslator]::FromHtml("#9AA4AF")
$Eyebrow = [System.Drawing.ColorTranslator]::FromHtml("#7C93AE")
$Credito = [System.Drawing.ColorTranslator]::FromHtml("#B4BCC5")
$Verde   = [System.Drawing.ColorTranslator]::FromHtml("#0A6F66")
$Ambar   = [System.Drawing.ColorTranslator]::FromHtml("#8A5A00")
$Vinho   = [System.Drawing.ColorTranslator]::FromHtml("#C01C28")
$FundoCampo = [System.Drawing.ColorTranslator]::FromHtml("#EDEFF2")

# ============================================================ AJUDANTES DE UI
function New-Rotulo($texto, $x, $y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $texto
    $l.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $l.ForeColor = $script:Grafite
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.AutoSize = $true
    $script:Form.Controls.Add($l)
    return $l
}

function New-Campo($x, $y, $largura, $tamFonte) {
    if (-not $tamFonte) { $tamFonte = 14 }
    $c = New-Object System.Windows.Forms.TextBox
    $c.Font = New-Object System.Drawing.Font("Consolas", $tamFonte)
    $c.Location = New-Object System.Drawing.Point($x, $y)
    $c.Size = New-Object System.Drawing.Size($largura, 34)
    $script:Form.Controls.Add($c)
    return $c
}

function New-Botao($texto, $x, $y, $largura, $altura, $fundo, $fundoHover) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $texto
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $b.Size = New-Object System.Drawing.Size($largura, $altura)
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $fundo
    $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatAppearance.MouseOverBackColor = $fundoHover
    $b.FlatAppearance.MouseDownBackColor = $fundoHover
    $script:Form.Controls.Add($b)
    return $b
}

# ============================================================ JANELA
$LARG = 760
$Form                 = New-Object System.Windows.Forms.Form
$Form.Text            = "Instalador RTSP2Cam"
$Form.Size            = New-Object System.Drawing.Size($LARG, 740)
$Form.StartPosition   = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox     = $false
$Form.MinimizeBox     = $false
$Form.ControlBox      = $false
$Form.TopMost         = $true
$Form.BackColor       = [System.Drawing.Color]::White

$script:Concluido  = $false
$script:Instalando = $false
$script:IpChecado  = ''      # IP que passou (ou foi confirmado) no teste
$script:IgnorarPing = $false

$Form.Add_FormClosing({
    param($s, $e)
    if ($script:Instalando -and -not $script:Concluido) { $e.Cancel = $true }
})

# ============================================================ CABECALHO
$cab           = New-Object System.Windows.Forms.Panel
$cab.Size      = New-Object System.Drawing.Size($LARG, 96)
$cab.BackColor = $Preto
$Form.Controls.Add($cab)

$lblEyebrow           = New-Object System.Windows.Forms.Label
$lblEyebrow.Text      = "M A C H A D A O   C O R P"
$lblEyebrow.Font      = New-Object System.Drawing.Font("Consolas", 9)
$lblEyebrow.ForeColor = $Eyebrow
$lblEyebrow.Location  = New-Object System.Drawing.Point(34, 20)
$lblEyebrow.AutoSize  = $true
$cab.Controls.Add($lblEyebrow)

$titulo           = New-Object System.Windows.Forms.Label
$titulo.Text      = "RTSP2Cam - camera IP como webcam"
$titulo.Font      = New-Object System.Drawing.Font("Segoe UI", 19)
$titulo.ForeColor = [System.Drawing.Color]::White
$titulo.Location  = New-Object System.Drawing.Point(32, 42)
$titulo.AutoSize  = $true
$cab.Controls.Add($titulo)

$contexto           = New-Object System.Windows.Forms.Label
$contexto.Text      = "$env:COMPUTERNAME"
$contexto.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$contexto.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#C9D3DE")
$contexto.Location  = New-Object System.Drawing.Point(($LARG - 280), 58)
$contexto.Size      = New-Object System.Drawing.Size(246, 20)
$contexto.TextAlign = "MiddleRight"
$cab.Controls.Add($contexto)

# ============================================================ CONTEUDO
$ajuda           = New-Object System.Windows.Forms.Label
$ajuda.Text      = "Informe os dados da camera. O instalador baixa o programa, registra a webcam virtual e cria o inicio automatico."
$ajuda.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$ajuda.ForeColor = $Grafite
$ajuda.Location  = New-Object System.Drawing.Point(36, 122)
$ajuda.Size      = New-Object System.Drawing.Size(($LARG - 80), 24)
$Form.Controls.Add($ajuda)

# ---- linha 1: IP + porta + teste
New-Rotulo "IP da camera *" 36 162 | Out-Null
$txtIp = New-Campo 36 186 200
New-Rotulo "Porta *" 256 162 | Out-Null
$txtPorta = New-Campo 256 186 80
$txtPorta.Text = "554"

$btnTestar = New-Botao "Testar" 356 186 110 34 $Grafite $FundoCampo
$btnTestar.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

$lblPing           = New-Object System.Windows.Forms.Label
$lblPing.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$lblPing.ForeColor = $Claro
$lblPing.Text      = "nao testado"
$lblPing.Location  = New-Object System.Drawing.Point(478, 194)
$lblPing.Size      = New-Object System.Drawing.Size(($LARG - 520), 20)
$Form.Controls.Add($lblPing)

# ---- linha 2: usuario + senha
New-Rotulo "Usuario *" 36 236 | Out-Null
$txtUsuario = New-Campo 36 260 320
New-Rotulo "Senha *" 384 236 | Out-Null
$txtSenha = New-Campo 384 260 320
$txtSenha.UseSystemPasswordChar = $true

$chkVerSenha           = New-Object System.Windows.Forms.CheckBox
$chkVerSenha.Text      = "mostrar senha"
$chkVerSenha.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$chkVerSenha.ForeColor = $Claro
$chkVerSenha.Location  = New-Object System.Drawing.Point(384, 300)
$chkVerSenha.AutoSize  = $true
$Form.Controls.Add($chkVerSenha)

# ---- linha 3: modelo da URL
New-Rotulo "Modelo da URL RTSP" 36 336 | Out-Null

$chkEditarUrl           = New-Object System.Windows.Forms.CheckBox
$chkEditarUrl.Text      = "editar modelo"
$chkEditarUrl.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$chkEditarUrl.ForeColor = $Grafite
$chkEditarUrl.Location  = New-Object System.Drawing.Point(($LARG - 175), 336)
$chkEditarUrl.AutoSize  = $true
$Form.Controls.Add($chkEditarUrl)

$txtUrl = New-Campo 36 360 ($LARG - 80) 11
$txtUrl.Text      = $script:UrlPadrao
$txtUrl.ReadOnly  = $true
$txtUrl.BackColor = $FundoCampo

$avisoUrl           = New-Object System.Windows.Forms.Label
$avisoUrl.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$avisoUrl.ForeColor = $Ambar
$avisoUrl.Location  = New-Object System.Drawing.Point(36, 400)
$avisoUrl.Size      = New-Object System.Drawing.Size(($LARG - 80), 52)
$avisoUrl.Text      = "Mude somente se o padrao nao funcionar. Mantenha os marcadores USUARIO, SENHA, IP e PORTA - eles sao trocados pelos campos acima. Hikvision: troque o final por  /Streaming/Channels/101"
$Form.Controls.Add($avisoUrl)

# ============================================================ MENSAGEM
$msg           = New-Object System.Windows.Forms.Label
$msg.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$msg.ForeColor = $Vinho
$msg.Location  = New-Object System.Drawing.Point(36, 458)
$msg.Size      = New-Object System.Drawing.Size(($LARG - 80), 24)
$Form.Controls.Add($msg)

# ============================================================ LOG
$log                = New-Object System.Windows.Forms.TextBox
$log.Multiline      = $true
$log.ReadOnly       = $true
$log.ScrollBars     = "Vertical"
$log.Font           = New-Object System.Drawing.Font("Consolas", 9)
$log.ForeColor      = $Grafite
$log.BackColor      = $FundoCampo
$log.BorderStyle    = "None"
$log.Location       = New-Object System.Drawing.Point(36, 488)
$log.Size           = New-Object System.Drawing.Size(($LARG - 80), 138)
$Form.Controls.Add($log)

function Escrever($texto) {
    $script:log.AppendText($texto + "`r`n")
    [System.Windows.Forms.Application]::DoEvents()
}
$script:log = $log

# ============================================================ RODAPE
$creditos           = New-Object System.Windows.Forms.Label
$creditos.Text      = "Desenvolvido por @JJMoratelli"
$creditos.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$creditos.ForeColor = $Credito
$creditos.Location  = New-Object System.Drawing.Point(36, 668)
$creditos.AutoSize  = $true
$Form.Controls.Add($creditos)

$btnCancelar = New-Botao "Cancelar" ($LARG - 420) 646 160 50 ([System.Drawing.Color]::White) ([System.Drawing.ColorTranslator]::FromHtml("#FBEAEA"))
$btnCancelar.ForeColor = $Vinho
$btnCancelar.FlatAppearance.BorderSize = 1
$btnCancelar.FlatAppearance.BorderColor = $Vinho

$btnAcao = New-Botao "Instalar" ($LARG - 246) 646 210 50 $Azul $AzulH
$Form.AcceptButton = $btnAcao

# ============================================================ FUNCOES DE APOIO
function Baixar($url, $saida) {
    Escrever "      baixando: $url"
    Invoke-WebRequest -Uri $url -OutFile $saida -UseBasicParsing
}

function Extrair7z($arquivo, $destino) {
    try { & tar.exe -xf $arquivo -C $destino 2>$null } catch { }
    if (Test-Path (Join-Path $destino 'rtsp2cam.exe')) { return }
    Escrever "      (tar nao serviu; baixando o extrator 7zr.exe)"
    $z = Join-Path $env:TEMP '7zr.exe'
    Baixar $script:SevenZrUrl $z
    & $z x $arquivo "-o$destino" -y | Out-Null
    if (-not (Test-Path (Join-Path $destino 'rtsp2cam.exe'))) {
        throw "Nao consegui extrair o pacote .7z."
    }
}

function GarantirVCRuntime {
    $sys = Join-Path $env:SystemRoot 'System32'
    if ((Test-Path (Join-Path $sys 'vcruntime140.dll')) -and
        (Test-Path (Join-Path $sys 'vcruntime140_1.dll')) -and
        (Test-Path (Join-Path $sys 'msvcp140.dll'))) {
        Escrever "      runtime do Visual C++ ja presente."
        return
    }
    Escrever "      instalando o runtime do Visual C++..."
    $vc = Join-Path $env:TEMP 'vc_redist.x64.exe'
    Baixar 'https://aka.ms/vs/17/release/vc_redist.x64.exe' $vc
    $p = Start-Process -FilePath $vc -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru -WindowStyle Hidden
    Remove-Item $vc -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -notin 0, 1638, 3010) {
        throw "Falha ao instalar o Visual C++ Redistributable (codigo $($p.ExitCode))."
    }
}

function SoftcamRegistrada {
    $chaves = @(
        "HKLM:\SOFTWARE\Classes\CLSID\$($script:SoftcamClsid)\InprocServer32",
        "HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\$($script:SoftcamClsid)\InprocServer32"
    )
    foreach ($c in $chaves) { if (Test-Path $c) { return $true } }
    return $false
}

function CriarTarefaWatchdog {
    $exe = Join-Path $script:Dest 'rtsp2cam.exe'
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
    [IO.File]::WriteAllText($xmlPath, $xml, [Text.Encoding]::Unicode)
    & schtasks /Create /TN $script:TaskName /XML $xmlPath /F | Out-Null
    $ok = ($LASTEXITCODE -eq 0)
    Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue
    if (-not $ok) { throw "Falha ao criar a Tarefa Agendada (codigo $LASTEXITCODE)." }
}

# Testa a camera: ping e, depois, a porta RTSP.
function Testar-Camera($ip, $porta) {
    $r = [ordered]@{ Ping = $false; Porta = $false }
    try { $r.Ping = Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue } catch { }
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ok  = $tcp.BeginConnect($ip, [int]$porta, $null, $null).AsyncWaitHandle.WaitOne(1500, $false)
        if ($ok -and $tcp.Connected) { $r.Porta = $true }
        $tcp.Close()
    }
    catch { }
    return $r
}

function Validar {
    $script:msg.ForeColor = $script:Vinho

    $ip = $script:txtIp.Text.Trim()
    if (-not $ip) { $script:msg.Text = "Informe o IP da camera."; $script:txtIp.Focus(); return $false }
    $ipObj = $null
    if (-not [System.Net.IPAddress]::TryParse($ip, [ref]$ipObj)) {
        $script:msg.Text = "IP invalido. Use o formato 192.168.1.10."; $script:txtIp.Focus(); return $false
    }

    $porta = $script:txtPorta.Text.Trim()
    if ($porta -notmatch '^\d+$' -or [int]$porta -lt 1 -or [int]$porta -gt 65535) {
        $script:msg.Text = "Porta invalida (1 a 65535). O padrao e 554."; $script:txtPorta.Focus(); return $false
    }

    if (-not $script:txtUsuario.Text.Trim()) {
        $script:msg.Text = "Informe o usuario da camera."; $script:txtUsuario.Focus(); return $false
    }
    if (-not $script:txtSenha.Text) {
        $script:msg.Text = "Informe a senha da camera."; $script:txtSenha.Focus(); return $false
    }

    $url = $script:txtUrl.Text.Trim()
    if ($url -notmatch '^rtsp://') {
        $script:msg.Text = "O modelo da URL precisa comecar com rtsp://"; $script:txtUrl.Focus(); return $false
    }
    foreach ($marca in 'USUARIO', 'SENHA', 'IP', 'PORTA') {
        if ($url -cnotmatch $marca) {
            $script:msg.Text = "Falta o marcador $marca no modelo da URL (ele e trocado pelo valor do campo)."
            $script:txtUrl.Focus(); return $false
        }
    }
    return $true
}

# ============================================================ EVENTOS
$chkVerSenha.Add_CheckedChanged({
    $script:txtSenha.UseSystemPasswordChar = -not $script:chkVerSenha.Checked
})

$chkEditarUrl.Add_CheckedChanged({
    if ($script:chkEditarUrl.Checked) {
        $script:txtUrl.ReadOnly  = $false
        $script:txtUrl.BackColor = [System.Drawing.Color]::White
        $script:txtUrl.Focus()
    }
    else {
        $script:txtUrl.Text      = $script:UrlPadrao
        $script:txtUrl.ReadOnly  = $true
        $script:txtUrl.BackColor = $script:FundoCampo
    }
})

# Muda o IP: invalida o teste anterior.
$txtIp.Add_TextChanged({
    if ($script:txtIp.Text.Trim() -ne $script:IpChecado) {
        $script:lblPing.ForeColor = $script:Claro
        $script:lblPing.Text      = "nao testado"
        $script:IgnorarPing       = $false
    }
})

$btnTestar.Add_Click({
    $ip = $script:txtIp.Text.Trim()
    $ipObj = $null
    if (-not [System.Net.IPAddress]::TryParse($ip, [ref]$ipObj)) {
        $script:lblPing.ForeColor = $script:Vinho
        $script:lblPing.Text      = "IP invalido"
        $script:txtIp.Focus(); return
    }
    $porta = $script:txtPorta.Text.Trim()
    if ($porta -notmatch '^\d+$') { $porta = '554' }

    $script:btnTestar.Enabled = $false
    $script:lblPing.ForeColor = $script:Grafite
    $script:lblPing.Text      = "testando..."
    [System.Windows.Forms.Application]::DoEvents()

    $r = Testar-Camera $ip $porta
    $script:IpChecado = $ip
    if ($r.Porta) {
        $script:lblPing.ForeColor = $script:Verde
        $script:lblPing.Text      = "OK - responde na porta $porta"
    }
    elseif ($r.Ping) {
        $script:lblPing.ForeColor = $script:Ambar
        $script:lblPing.Text      = "responde ao ping, mas a porta $porta esta fechada"
    }
    else {
        $script:lblPing.ForeColor = $script:Vinho
        $script:lblPing.Text      = "nao respondeu"
    }
    $script:btnTestar.Enabled = $true
})

$btnCancelar.Add_Click({
    if ($script:Instalando -and -not $script:Concluido) { return }
    $script:Concluido = $true
    $script:Form.Close()
})

$btnAcao.Add_Click({
    if ($script:Concluido) { $script:Form.Close(); return }
    if (-not (Validar)) { return }

    $ip     = $script:txtIp.Text.Trim()
    $porta  = $script:txtPorta.Text.Trim()
    $login  = $script:txtUsuario.Text.Trim()
    $senha  = $script:txtSenha.Text
    $url    = $script:txtUrl.Text.Trim()

    # Teste obrigatorio antes de instalar; se falhar, exige um segundo clique.
    if (-not $script:IgnorarPing) {
        $script:msg.ForeColor = $script:Grafite
        $script:msg.Text      = "Verificando a camera..."
        [System.Windows.Forms.Application]::DoEvents()
        $r = Testar-Camera $ip $porta
        $script:IpChecado = $ip
        if ($r.Porta) {
            $script:lblPing.ForeColor = $script:Verde
            $script:lblPing.Text      = "OK - responde na porta $porta"
        }
        else {
            $script:lblPing.ForeColor = $script:Vinho
            $script:lblPing.Text      = if ($r.Ping) { "porta $porta fechada" } else { "nao respondeu" }
            $script:msg.ForeColor     = $script:Ambar
            $script:msg.Text          = "A camera nao respondeu em $ip`:$porta. Clique em Instalar de novo para continuar mesmo assim."
            $script:IgnorarPing       = $true
            return
        }
    }

    $script:Instalando        = $true
    $script:btnAcao.Enabled   = $false
    $script:btnAcao.Text      = "Aguarde..."
    $script:btnCancelar.Enabled = $false
    $script:btnTestar.Enabled = $false
    $script:msg.ForeColor     = $script:Grafite
    $script:msg.Text          = "Instalando..."
    $script:log.Clear()
    [System.Windows.Forms.Application]::DoEvents()

    try {
        Get-Process rtsp2cam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

        Escrever "[1/7] Preparando pasta: $($script:Dest)"
        New-Item -ItemType Directory -Force -Path $script:Dest | Out-Null

        Escrever "[2/7] Baixando o pacote do programa..."
        $pkg = Join-Path $env:TEMP 'RTSP2CAM.7z'
        Baixar $script:PkgUrl $pkg
        Escrever "      extraindo..."
        Extrair7z $pkg $script:Dest
        Remove-Item $pkg -Force -ErrorAction SilentlyContinue

        Escrever "[3/7] ffmpeg..."
        $ffDest = Join-Path $script:Dest 'ffmpeg.exe'
        if (Test-Path $ffDest) {
            Escrever "      ja existe na pasta, pulando o download."
        }
        else {
            $ffzip = Join-Path $env:TEMP 'ffmpeg.zip'
            Baixar $script:FfmpegUrl $ffzip
            $fftmp = Join-Path $env:TEMP ('ff_' + [guid]::NewGuid().ToString('N'))
            Expand-Archive -Path $ffzip -DestinationPath $fftmp -Force
            $ff = Get-ChildItem -Path $fftmp -Recurse -Filter 'ffmpeg.exe' | Select-Object -First 1
            if (-not $ff) { throw "ffmpeg.exe nao encontrado no pacote baixado." }
            Copy-Item $ff.FullName $ffDest -Force
            Remove-Item $ffzip -Force -ErrorAction SilentlyContinue
            Remove-Item $fftmp -Recurse -Force -ErrorAction SilentlyContinue
        }

        Escrever "[4/7] Gravando rtsp2cam.conf..."
        $conf = @"
# Configuracao do rtsp2cam (gerada pelo instalador)
# Os marcadores USUARIO, SENHA, IP e PORTA na linha RTSP sao trocados
# pelos valores abaixo. Para outra marca de camera, troque so o final:
#   Hikvision: /Streaming/Channels/101
RTSP=$url
IP=$ip
LOGIN=$login
SENHA=$senha
PORTA=$porta
WIDTH=1280
HEIGHT=720
FPS=25
"@
        [IO.File]::WriteAllText(
            (Join-Path $script:Dest 'rtsp2cam.conf'),
            $conf,
            (New-Object System.Text.UTF8Encoding($false)))
        if (-not (Test-Path (Join-Path $script:Dest 'rtsp2cam.conf'))) {
            throw "Nao consegui gravar o rtsp2cam.conf."
        }

        Escrever "[5/7] Verificando o runtime do Visual C++..."
        GarantirVCRuntime

        Escrever "[6/7] Registrando a webcam virtual (softcam)..."
        & regsvr32 /s (Join-Path $script:Dest 'softcam.dll')
        Start-Sleep -Milliseconds 500
        if (-not (SoftcamRegistrada)) {
            throw "A softcam NAO ficou registrada. Confira o runtime do Visual C++ e o modo administrador."
        }
        Escrever "      registrada e verificada (DirectShow Softcam)."

        Escrever "[7/7] Criando inicio automatico (watchdog) e iniciando..."
        CriarTarefaWatchdog
        & schtasks /run /tn $script:TaskName 2>$null | Out-Null

        Escrever ""
        Escrever "Instalado em: $($script:Dest)"
        Escrever "Abra OBS, VLC, Zoom, Teams ou o navegador e escolha 'softcam'."
        Escrever "(O app 'Camera' do Windows NAO lista a softcam - isso e normal.)"

        $script:Concluido  = $true
        $script:Instalando = $false
        $script:msg.ForeColor = $script:Verde
        $script:msg.Text      = "Instalado com sucesso. A camera 'softcam' ja deve estar ativa."
        foreach ($c in $script:txtIp, $script:txtPorta, $script:txtUsuario, $script:txtSenha, $script:txtUrl,
                       $script:chkEditarUrl, $script:chkVerSenha) { $c.Enabled = $false }
        $script:btnAcao.Text     = "Concluir"
        $script:btnAcao.Enabled  = $false
        [System.Windows.Forms.Application]::DoEvents()

        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Milliseconds 100
            [System.Windows.Forms.Application]::DoEvents()
        }
        $script:Form.Close()
    }
    catch {
        $script:Instalando = $false
        Escrever ""
        Escrever "[ERRO] $($_.Exception.Message)"
        $script:msg.ForeColor       = $script:Vinho
        $script:msg.Text            = "Falha: $($_.Exception.Message)"
        $script:btnAcao.Enabled     = $true
        $script:btnAcao.Text        = "Tentar novamente"
        $script:btnCancelar.Enabled = $true
        $script:btnTestar.Enabled   = $true
    }
})

$Form.Add_Shown({ $script:txtIp.Focus() })
$Form.ShowDialog() | Out-Null
$Form.Dispose()
