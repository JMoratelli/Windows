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
    [PSCustomObject]@{ Legenda = "Instala e configura Zanthus";            Url = "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PostInstallPDV.ps1" }
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

# ============================================================ LOGICA
$script:btnFechar.Add_Click({
    $script:Concluido = $true
    $script:Form.Close()
})

$script:btnAcao.Add_Click({
    if ($script:cbScripts.SelectedIndex -lt 0) { return }

    $itemSelecionado = $ScriptsMenu[$script:cbScripts.SelectedIndex]

    $script:btnAcao.Enabled = $false
    $script:btnFechar.Enabled = $false
    $script:cbScripts.Enabled = $false
    $script:msg.ForeColor = $script:corGrafite
    $script:msg.Text = "Disparando script $($itemSelecionado.Legenda)..."
    [System.Windows.Forms.Application]::DoEvents()

    $comandoRemoto = "irm '$($itemSelecionado.Url)' | iex"
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
