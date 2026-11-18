#Requires -Version 5.1

<#
    PAINEL DE CONFIGURACAO DOS SCRIPTS AUXILIARES - GUI
    Adaptado para o padrao visual Machadao Corp.
#>

# ============================================================ CONSOLE MINIMIZADO
# NAO esconder a janela (ShowWindow(hWnd, 0)): scripts que usam rundll32
# printui.dll travam se a janela do processo pai nao existir.
# Minimizar (6) deixa a janela fora do caminho sem remove-la.
Add-Type -Namespace Nativo -Name Janela -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")]   public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@ -ErrorAction SilentlyContinue
try {
    $h = [Nativo.Janela]::GetConsoleWindow()
    if ($h -ne [System.IntPtr]::Zero) { [Nativo.Janela]::ShowWindow($h, 6) | Out-Null }   # 6 = SW_MINIMIZE
}
catch { }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ============================================================ DADOS E FUNCOES
$ScriptsMenu = @(
    [PSCustomObject]@{ Legenda = "Instala Ventoy Atualizado";              Url = "https://raw.githubusercontent.com/JMoratelli/Windows/refs/heads/main/InstalaVentoy.ps1" }
    [PSCustomObject]@{ Legenda = "Instala e configura SIP";                Url = "https://raw.githubusercontent.com/JMoratelli/Windows/refs/heads/main/InstalaConfiguraGOnnect.ps1" }
    [PSCustomObject]@{ Legenda = "Instala e configura Impressora";         Url = "https://raw.githubusercontent.com/JMoratelli/Windows/refs/heads/main/InstalaImpressoraKyocera.ps1" }
    [PSCustomObject]@{ Legenda = "Instala e configura Zanthus";            Url = "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Windows/PostInstallPDV.ps1"; PedeToken = $true }
    [PSCustomObject]@{ Legenda = "Instala IP para WebCam";    Url = "https://raw.githubusercontent.com/JMoratelli/Windows/refs/heads/main/Softwares/InstalaRTSP2CAM.ps1" }
    [PSCustomObject]@{ Legenda = "Instala Gravador Raspi";    Url = "https://raw.githubusercontent.com/JMoratelli/Windows/refs/heads/main/Softwares/GravaRaspiOS.ps1" }
    [PSCustomObject]@{ Legenda = "Refaz Instalação de pacotes Windows";    Url = "https://raw.githubusercontent.com/JMoratelli/Windows/refs/heads/main/InstalaWindows.ps1" }
)

function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$so = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$ipLocal = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
           Where-Object { $_.InterfaceAlias -notmatch "Loopback" -and $_.IPAddress -notlike "169.254*" } |
           Select-Object -First 1 -ExpandProperty IPAddress
if (-not $ipLocal) { $ipLocal = "N/A" }
$uptime = (Get-Date) - $so.LastBootUpTime
$statusAdmin = if (Test-IsAdmin) { "SIM" } else { "NAO" }

# ============================================================ PALETA DE CORES
# Usando escopo $script e prefixo "cor" para evitar colisão com os Labels do formulário
$script:corPreto   = [System.Drawing.ColorTranslator]::FromHtml("#12161C")
$script:corAzul    = [System.Drawing.ColorTranslator]::FromHtml("#1A5FB4")
$script:corAzulH   = [System.Drawing.ColorTranslator]::FromHtml("#154C90")
$script:corGrafite = [System.Drawing.ColorTranslator]::FromHtml("#5B6672")
$script:corClaro   = [System.Drawing.ColorTranslator]::FromHtml("#9AA4AF")
$script:corEyebrow = [System.Drawing.ColorTranslator]::FromHtml("#7C93AE")
$script:corCredito = [System.Drawing.ColorTranslator]::FromHtml("#B4BCC5")
$script:corVerde   = [System.Drawing.ColorTranslator]::FromHtml("#0A6F66")
$script:corAmbar   = [System.Drawing.ColorTranslator]::FromHtml("#8A5A00")
$script:corVinho   = [System.Drawing.ColorTranslator]::FromHtml("#C01C28")
$script:corFundo   = [System.Drawing.ColorTranslator]::FromHtml("#EDEFF2")

# ============================================================ AJUDANTES
function New-Botao($texto, $x, $y, $largura, $fundo) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $texto
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $b.Size = New-Object System.Drawing.Size($largura, 50)
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $fundo
    $b.ForeColor = [System.Drawing.Color]::White
    $script:Form.Controls.Add($b)
    return $b
}

# ============================================================ JANELA
$LARG = 720
$script:Form                 = New-Object System.Windows.Forms.Form
$script:Form.Text            = "Painel de Scripts"
$script:Form.Size            = New-Object System.Drawing.Size($LARG, 560)
$script:Form.StartPosition   = "CenterScreen"
$script:Form.FormBorderStyle = "FixedDialog"
$script:Form.MaximizeBox     = $false
$script:Form.MinimizeBox     = $false
$script:Form.ControlBox      = $false
$script:Form.TopMost         = $true
$script:Form.BackColor       = [System.Drawing.Color]::White

$script:Concluido = $false
$script:Form.Add_FormClosing({
    param($s, $e)
    if (-not $script:Concluido) { $e.Cancel = $true }
})

# ============================================================ CABECALHO
$cab           = New-Object System.Windows.Forms.Panel
$cab.Size      = New-Object System.Drawing.Size($LARG, 96)
$cab.BackColor = $script:corPreto
$script:Form.Controls.Add($cab)

$lblEyebrow           = New-Object System.Windows.Forms.Label
$lblEyebrow.Text      = "M A C H A D A O   C O R P"
$lblEyebrow.Font      = New-Object System.Drawing.Font("Consolas", 9)
$lblEyebrow.ForeColor = $script:corEyebrow
$lblEyebrow.Location  = New-Object System.Drawing.Point(34, 20)
$lblEyebrow.AutoSize  = $true
$cab.Controls.Add($lblEyebrow)

$titulo           = New-Object System.Windows.Forms.Label
$titulo.Text      = "Painel de Scripts @JJMoratelli"
$titulo.Font      = New-Object System.Drawing.Font("Segoe UI", 19)
$titulo.ForeColor = [System.Drawing.Color]::White
$titulo.Location  = New-Object System.Drawing.Point(32, 42)
$titulo.AutoSize  = $true
$cab.Controls.Add($titulo)

$contexto           = New-Object System.Windows.Forms.Label
$contexto.Text      = "$env:COMPUTERNAME"
$contexto.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$contexto.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#C9D3DE")
$contexto.Location  = New-Object System.Drawing.Point(($LARG - 260), 58)
$contexto.Size      = New-Object System.Drawing.Size(226, 20)
$contexto.TextAlign = "MiddleRight"
$cab.Controls.Add($contexto)

# ============================================================ CONTEUDO
$lblInfo           = New-Object System.Windows.Forms.Label
$infoText = "Maquina.......: {0}`nUsuario.......: {1}\{2}`nDominio/Grupo.: {3}`nSistema.......: {4} ({5})`nVersao/Build..: {6} (Build {7})`nIP Local......: {8}`nLigado ha.....: {9}d {10}h {11}m`nPowerShell....: {12}`nSessao Admin..: {13}" -f $env:COMPUTERNAME, $env:USERDOMAIN, $env:USERNAME, $cs.Domain, $so.Caption, $so.OSArchitecture, $so.Version, $so.BuildNumber, $ipLocal, $uptime.Days, $uptime.Hours, $uptime.Minutes, $PSVersionTable.PSVersion, $statusAdmin
$lblInfo.Text      = $infoText
$lblInfo.Font      = New-Object System.Drawing.Font("Consolas", 10)
$lblInfo.ForeColor = $script:corGrafite
$lblInfo.Location  = New-Object System.Drawing.Point(36, 122)
$lblInfo.Size      = New-Object System.Drawing.Size(($LARG - 70), 160)
$script:Form.Controls.Add($lblInfo)

$lblSelecione           = New-Object System.Windows.Forms.Label
$lblSelecione.Text      = "Selecione o script para executar:"
$lblSelecione.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$lblSelecione.ForeColor = $script:corGrafite
$lblSelecione.Location  = New-Object System.Drawing.Point(36, 290)
$lblSelecione.AutoSize  = $true
$script:Form.Controls.Add($lblSelecione)

$script:cbScripts = New-Object System.Windows.Forms.ComboBox
$script:cbScripts.Location = New-Object System.Drawing.Point(36, 316)
$script:cbScripts.Size = New-Object System.Drawing.Size(($LARG - 88), 30)
$script:cbScripts.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$script:cbScripts.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
foreach ($item in $ScriptsMenu) {
    $script:cbScripts.Items.Add($item.Legenda) | Out-Null
}
if ($script:cbScripts.Items.Count -gt 0) { $script:cbScripts.SelectedIndex = 0 }
$script:Form.Controls.Add($script:cbScripts)

# ============================================================ MENSAGEM
$script:msg           = New-Object System.Windows.Forms.Label
$script:msg.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$script:msg.ForeColor = $script:corGrafite
$script:msg.Location  = New-Object System.Drawing.Point(36, 360)
$script:msg.Size      = New-Object System.Drawing.Size(($LARG - 88), 44)
$script:msg.Text      = "Pronto. Aguardando seleção."
$script:Form.Controls.Add($script:msg)

# ============================================================ RODAPE
$lblCreditos           = New-Object System.Windows.Forms.Label
$lblCreditos.Text      = "Desenvolvido por @JJMoratelli"
$lblCreditos.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$lblCreditos.ForeColor = $script:corCredito
$lblCreditos.Location  = New-Object System.Drawing.Point(36, 482)
$lblCreditos.AutoSize  = $true
$script:Form.Controls.Add($lblCreditos)

$script:btnAcao = New-Botao "Executar" ($LARG - 244) 462 190 $script:corAzul
$script:btnFechar = New-Botao "Sair" ($LARG - 384) 462 130 $script:corGrafite
$script:Form.AcceptButton = $script:btnAcao

# ============================================================ TOKEN DO ZANTHUS
# O repositorio Zanthus e privado: a opcao dele pede o token de leitura na hora
# e o confere antes de disparar. O script roda oculto, e um token errado faria a
# instalacao falhar sem ninguem ver. O token nunca entra aqui (repositorio publico).
function Read-TokenZanthus($url) {
    $script:tkUrl   = $url
    $script:tkToken = $null

    $script:tkForm                 = New-Object System.Windows.Forms.Form
    $script:tkForm.Text            = "Token do repositório"
    $script:tkForm.ClientSize      = New-Object System.Drawing.Size(560, 316)
    $script:tkForm.StartPosition   = "CenterParent"
    $script:tkForm.FormBorderStyle = "FixedDialog"
    $script:tkForm.MaximizeBox     = $false
    $script:tkForm.MinimizeBox     = $false
    $script:tkForm.ControlBox      = $false
    $script:tkForm.ShowInTaskbar   = $false
    $script:tkForm.TopMost         = $true
    $script:tkForm.BackColor       = [System.Drawing.Color]::White

    $cabTk           = New-Object System.Windows.Forms.Panel
    $cabTk.Size      = New-Object System.Drawing.Size(560, 92)
    $cabTk.BackColor = $script:corPreto
    $script:tkForm.Controls.Add($cabTk)

    $eyebrowTk           = New-Object System.Windows.Forms.Label
    $eyebrowTk.Text      = "M A C H A D A O   C O R P"
    $eyebrowTk.Font      = New-Object System.Drawing.Font("Consolas", 9)
    $eyebrowTk.ForeColor = $script:corEyebrow
    $eyebrowTk.Location  = New-Object System.Drawing.Point(34, 18)
    $eyebrowTk.AutoSize  = $true
    $cabTk.Controls.Add($eyebrowTk)

    $tituloTk           = New-Object System.Windows.Forms.Label
    $tituloTk.Text      = "Token do repositório Zanthus"
    $tituloTk.Font      = New-Object System.Drawing.Font("Segoe UI", 19)
    $tituloTk.ForeColor = [System.Drawing.Color]::White
    $tituloTk.Location  = New-Object System.Drawing.Point(32, 38)
    $tituloTk.AutoSize  = $true
    $cabTk.Controls.Add($tituloTk)

    $ajudaTk           = New-Object System.Windows.Forms.Label
    $ajudaTk.Text      = "Cole o token de leitura. Ele está no manual de instalação, no botão Copiar token."
    $ajudaTk.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
    $ajudaTk.ForeColor = $script:corGrafite
    $ajudaTk.Location  = New-Object System.Drawing.Point(36, 114)
    $ajudaTk.Size      = New-Object System.Drawing.Size(488, 40)
    $script:tkForm.Controls.Add($ajudaTk)

    $script:tkCampo                       = New-Object System.Windows.Forms.TextBox
    $script:tkCampo.Font                  = New-Object System.Drawing.Font("Consolas", 14)
    $script:tkCampo.Location              = New-Object System.Drawing.Point(36, 158)
    $script:tkCampo.Size                  = New-Object System.Drawing.Size(488, 30)
    $script:tkCampo.UseSystemPasswordChar = $true
    $script:tkForm.Controls.Add($script:tkCampo)

    $script:tkAviso           = New-Object System.Windows.Forms.Label
    $script:tkAviso.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
    $script:tkAviso.ForeColor = $script:corGrafite
    $script:tkAviso.Location  = New-Object System.Drawing.Point(36, 196)
    $script:tkAviso.Size      = New-Object System.Drawing.Size(488, 40)
    $script:tkForm.Controls.Add($script:tkAviso)

    $script:tkContinuar = New-Object System.Windows.Forms.Button
    $script:tkVoltar    = New-Object System.Windows.Forms.Button
    foreach ($b in @(
        @{ Botao = $script:tkContinuar; Texto = "Continuar"; X = 334; Largura = 190; Fundo = $script:corAzul;    Hover = $script:corAzulH },
        @{ Botao = $script:tkVoltar;    Texto = "Voltar";    X = 192; Largura = 130; Fundo = $script:corGrafite; Hover = $script:corPreto })) {
        $b.Botao.Text      = $b.Texto
        $b.Botao.Font      = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
        $b.Botao.Size      = New-Object System.Drawing.Size($b.Largura, 50)
        $b.Botao.Location  = New-Object System.Drawing.Point($b.X, 244)
        $b.Botao.FlatStyle = "Flat"
        $b.Botao.FlatAppearance.BorderSize = 0
        $b.Botao.FlatAppearance.MouseOverBackColor = $b.Hover
        $b.Botao.FlatAppearance.MouseDownBackColor = $b.Hover
        $b.Botao.BackColor = $b.Fundo
        $b.Botao.ForeColor = [System.Drawing.Color]::White
        $script:tkForm.Controls.Add($b.Botao)
    }
    $script:tkVoltar.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $script:tkForm.AcceptButton   = $script:tkContinuar
    $script:tkForm.CancelButton   = $script:tkVoltar

    $script:tkContinuar.Add_Click({
        $t = $script:tkCampo.Text.Trim()
        if ($t -notmatch '^[A-Za-z0-9_]+$') {
            $script:tkAviso.ForeColor = $script:corVinho
            $script:tkAviso.Text = if ($t) { "O token tem só letras, números e _. Confira se não veio espaço ou quebra de linha." } else { "Cole o token para continuar." }
            return
        }

        $script:tkContinuar.Enabled = $false
        $script:tkContinuar.Text = "Aguarde..."
        $script:tkAviso.ForeColor = $script:corGrafite
        $script:tkAviso.Text = "Conferindo o token no GitHub..."
        [System.Windows.Forms.Application]::DoEvents()

        try {
            Invoke-WebRequest -UseBasicParsing -Method Head -TimeoutSec 20 `
                -Headers @{ Authorization = "token $t" } -Uri $script:tkUrl | Out-Null
            $script:tkToken = $t
            $script:tkForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        }
        catch {
            $codigo = 0
            if ($_.Exception.Response) { $codigo = [int]$_.Exception.Response.StatusCode }
            $script:tkAviso.ForeColor = $script:corVinho
            $script:tkAviso.Text = if ($codigo -in 401, 403, 404) { "O GitHub recusou o token. Confira se ele foi copiado inteiro." } else { "Sem resposta do GitHub: $($_.Exception.Message)" }
            $script:tkContinuar.Text = "Tentar novamente"
            $script:tkContinuar.Enabled = $true
        }
    })

    $resultado = $script:tkForm.ShowDialog($script:Form)
    $script:tkForm.Dispose()
    if ($resultado -eq [System.Windows.Forms.DialogResult]::OK) { return $script:tkToken }
    return $null
}

# ============================================================ LOGICA
$script:btnFechar.Add_Click({
    $script:Concluido = $true
    $script:Form.Close()
})

$script:btnAcao.Add_Click({
    if ($script:cbScripts.SelectedIndex -lt 0) { return }

    $itemSelecionado = $ScriptsMenu[$script:cbScripts.SelectedIndex]

    $cabecalho = ""
    if ($itemSelecionado.PedeToken) {
        $token = Read-TokenZanthus $itemSelecionado.Url
        if (-not $token) {
            $script:msg.ForeColor = $script:corGrafite
            $script:msg.Text = "Execução cancelada: token não informado."
            return
        }
        $cabecalho = "-Headers @{ Authorization = 'token $token' } "
    }

    $script:btnAcao.Enabled = $false
    $script:btnFechar.Enabled = $false
    $script:cbScripts.Enabled = $false
    $script:msg.ForeColor = $script:corGrafite
    $script:msg.Text = "Disparando script $($itemSelecionado.Legenda)..."
    [System.Windows.Forms.Application]::DoEvents()

    $comandoRemoto = "irm $cabecalho'$($itemSelecionado.Url)' | iex"
    # Sem -NoExit: com a janela oculta, ela ficaria pendurada pra sempre depois
    # que o script terminasse, acumulando processos powershell.exe invisiveis.
    $argumentos = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-WindowStyle", "Hidden",
        "-Command", $comandoRemoto
    )

    # TopMost atrapalha scripts que abrem janela propria - abaixa enquanto
    # dispara e restaura depois.
    $topMostAnterior = $script:Form.TopMost
    $script:Form.TopMost = $false

    try {
        # O -Wait foi removido para liberar a interface na mesma hora.
        # -WindowStyle Hidden vai tanto no argumento do powershell quanto no
        # Start-Process: sem os dois o console pisca antes de sumir.
        if (Test-IsAdmin) {
            Start-Process -FilePath "powershell.exe" -ArgumentList $argumentos -WindowStyle Hidden
        }
        else {
            Start-Process -FilePath "powershell.exe" -ArgumentList $argumentos -Verb RunAs -WindowStyle Hidden
        }

        Start-Sleep -Milliseconds 400
        $script:msg.ForeColor = $script:corVerde
        $script:msg.Text = "O script foi disparado em segundo plano. O painel está liberado."
    }
    catch {
        $script:msg.ForeColor = $script:corVinho
        $script:msg.Text = "Erro: $($_.Exception.Message)"
    }
    finally {
        $script:Form.TopMost = $topMostAnterior
    }

    $script:btnAcao.Enabled = $true
    $script:btnFechar.Enabled = $true
    $script:cbScripts.Enabled = $true
})

$script:Form.ShowDialog() | Out-Null
$script:Form.Dispose()
