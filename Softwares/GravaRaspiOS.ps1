<#
    GravaRaspiOS - Interface Windows (PowerShell / WinForms)
    Padrão Machadão Corp
    Desenvolvido por @JJMoratelli
#>

# ==============================================================================
# 1. AUTO-ELEVAÇÃO (ADMINISTRADOR)
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $srcPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    if ($srcPath) {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$srcPath`"" -Verb RunAs
    } else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$($MyInvocation.MyCommand.Definition)`"" -Verb RunAs
    }
    return
}

# ==============================================================================
# 2. OCULTAR CONSOLE POWERSHELL
# ==============================================================================
Add-Type -Namespace Nativo -Name Janela -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")]   public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@ -ErrorAction SilentlyContinue
try {
    $h = [Nativo.Janela]::GetConsoleWindow()
    if ($h -ne [System.IntPtr]::Zero) { [Nativo.Janela]::ShowWindow($h, 0) | Out-Null }
} catch { }

# ==============================================================================
# 3. INSTALAÇÃO, DOWNLOAD DO EXECUTÁVEL E CRIAÇÃO DO ATALHO
# ==============================================================================
$installDir   = "$env:ProgramFiles\GravaRaspiOS"
$targetScript = Join-Path $installDir "script.ps1"
$exePath      = Join-Path $installDir "GravaRaspiOS.exe"
$downloadUrl  = "https://github.com/JMoratelli/Windows/raw/refs/heads/main/Softwares/GravaRaspiOS.exe"

# Cria pasta em Arquivos de Programas
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

# Copia ou grava o script.ps1 na pasta de destino
$originPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
if ($originPath -and (Test-Path $originPath) -and ($originPath -ne $targetScript)) {
    Copy-Item -Path $originPath -Destination $targetScript -Force
} elseif (-not (Test-Path $targetScript)) {
    Set-Content -Path $targetScript -Value $MyInvocation.MyCommand.Definition -Force
}

# Baixa o GravaRaspiOS.exe se ainda não existir
if (-not (Test-Path $exePath)) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $exePath -UseBasicParsing
    } catch { }
}

# Cria atalho na Área de Trabalho com Ícone de Pendrive (shell32.dll, 7)
$desktopPath  = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "GravaRaspiOS.lnk"

if (-not (Test-Path $shortcutPath)) {
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutPath)
        $Shortcut.TargetPath       = "powershell.exe"
        $Shortcut.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetScript`""
        $Shortcut.WorkingDirectory = $installDir
        $Shortcut.IconLocation     = "%SystemRoot%\System32\shell32.dll, 7"
        $Shortcut.Description      = "GravaRaspiOS - Gravador de Imagens Raspberry Pi OS"
        $Shortcut.Save()
    } catch { }
}

Set-Location $installDir

# ==============================================================================
# 4. INICIALIZAÇÃO GRÁFICA (WINFORMS)
# ==============================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Paleta Machadão Corp
$Preto   = [System.Drawing.ColorTranslator]::FromHtml("#12161C")
$Azul    = [System.Drawing.ColorTranslator]::FromHtml("#1A5FB4")
$Grafite = [System.Drawing.ColorTranslator]::FromHtml("#5B6672")
$Eyebrow = [System.Drawing.ColorTranslator]::FromHtml("#7C93AE")
$Credito = [System.Drawing.ColorTranslator]::FromHtml("#B4BCC5")
$Verde   = [System.Drawing.ColorTranslator]::FromHtml("#0A6F66")
$Vinho   = [System.Drawing.ColorTranslator]::FromHtml("#C01C28")
$Ambar   = [System.Drawing.ColorTranslator]::FromHtml("#8A5A00")

$script:Operando    = $false
$script:DiscosList  = @{}
$script:MotivosList = @{}

$LARG = 780
$ALT  = 620

$Form                 = New-Object System.Windows.Forms.Form
$Form.Text            = "GravaRaspiOS"
$Form.Size            = New-Object System.Drawing.Size($LARG, $ALT)
$Form.StartPosition   = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox     = $false
$Form.MinimizeBox     = $true
$Form.BackColor       = [System.Drawing.Color]::White

$Form.Add_FormClosing({
    param($s, $e)
    if ($script:Operando) { $e.Cancel = $true }
})

# ==============================================================================
# CABEÇALHO
# ==============================================================================
$cab           = New-Object System.Windows.Forms.Panel
$cab.Size      = New-Object System.Drawing.Size($LARG, 90)
$cab.BackColor = $Preto
$Form.Controls.Add($cab)

$lblEyebrow           = New-Object System.Windows.Forms.Label
$lblEyebrow.Text      = "M A C H A D A O   C O R P   /   G R A V A D O R"
$lblEyebrow.Font      = New-Object System.Drawing.Font("Consolas", 9)
$lblEyebrow.ForeColor = $Eyebrow
$lblEyebrow.Location  = New-Object System.Drawing.Point(24, 18)
$lblEyebrow.AutoSize  = $true
$cab.Controls.Add($lblEyebrow)

$lblTitulo           = New-Object System.Windows.Forms.Label
$lblTitulo.Text      = "GravaRaspiOS"
$lblTitulo.Font      = New-Object System.Drawing.Font("Segoe UI", 18)
$lblTitulo.ForeColor = [System.Drawing.Color]::White
$lblTitulo.Location  = New-Object System.Drawing.Point(22, 38)
$lblTitulo.AutoSize  = $true
$cab.Controls.Add($lblTitulo)

$btnRecarregar           = New-Object System.Windows.Forms.Button
$btnRecarregar.Text      = "Recarregar Discos"
$btnRecarregar.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$btnRecarregar.Size      = New-Object System.Drawing.Size(140, 32)
$btnRecarregar.Location  = New-Object System.Drawing.Point(($LARG - 180), 20)
$btnRecarregar.FlatStyle = "Flat"
$btnRecarregar.BackColor = [System.Drawing.Color]::White
$btnRecarregar.ForeColor = $Preto
$cab.Controls.Add($btnRecarregar)

$lblCredCab           = New-Object System.Windows.Forms.Label
$lblCredCab.Text      = "Desenvolvido por @JJMoratelli"
$lblCredCab.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$lblCredCab.ForeColor = $Credito
$lblCredCab.Location  = New-Object System.Drawing.Point(($LARG - 220), 58)
$lblCredCab.Size      = New-Object System.Drawing.Size(180, 20)
$lblCredCab.TextAlign = "MiddleRight"
$cab.Controls.Add($lblCredCab)

# ==============================================================================
# PAINEL 1: SELEÇÃO
# ==============================================================================
$pnlSelecao          = New-Object System.Windows.Forms.Panel
$pnlSelecao.Location = New-Object System.Drawing.Point(24, 100)
$pnlSelecao.Size     = New-Object System.Drawing.Size(($LARG - 60), 420)
$Form.Controls.Add($pnlSelecao)

# 1. Imagem
$lblImg           = New-Object System.Windows.Forms.Label
$lblImg.Text      = "1. ARQUIVO DE IMAGEM"
$lblImg.Font      = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$lblImg.ForeColor = $Grafite
$lblImg.Location  = New-Object System.Drawing.Point(0, 10)
$lblImg.AutoSize  = $true
$pnlSelecao.Controls.Add($lblImg)

$txtImg          = New-Object System.Windows.Forms.TextBox
$txtImg.Font     = New-Object System.Drawing.Font("Consolas", 12)
$txtImg.Location = New-Object System.Drawing.Point(0, 35)
$txtImg.Size     = New-Object System.Drawing.Size(($LARG - 200), 30)
$txtImg.ReadOnly = $true
$pnlSelecao.Controls.Add($txtImg)

$btnBrowse           = New-Object System.Windows.Forms.Button
$btnBrowse.Text      = "Procurar..."
$btnBrowse.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$btnBrowse.Location  = New-Object System.Drawing.Point(($LARG - 190), 34)
$btnBrowse.Size      = New-Object System.Drawing.Size(120, 32)
$btnBrowse.FlatStyle = "Flat"
$pnlSelecao.Controls.Add($btnBrowse)

# 2. Destino
$lblDisco           = New-Object System.Windows.Forms.Label
$lblDisco.Text      = "2. DESTINO (CARTÃO OU PENDRIVE)"
$lblDisco.Font      = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$lblDisco.ForeColor = $Grafite
$lblDisco.Location  = New-Object System.Drawing.Point(0, 95)
$lblDisco.AutoSize  = $true
$pnlSelecao.Controls.Add($lblDisco)

$cmbDisco               = New-Object System.Windows.Forms.ComboBox
$cmbDisco.Font          = New-Object System.Drawing.Font("Consolas", 11)
$cmbDisco.Location      = New-Object System.Drawing.Point(0, 120)
$cmbDisco.Size          = New-Object System.Drawing.Size(($LARG - 70), 30)
$cmbDisco.DropDownStyle = "DropDownList"
$pnlSelecao.Controls.Add($cmbDisco)

# Opção de Desbloqueio
$chkFixo           = New-Object System.Windows.Forms.CheckBox
$chkFixo.Text      = "Permitir disco fixo / leitor interno (--permitir-fixo --max-gb 2000)"
$chkFixo.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$chkFixo.ForeColor = $Grafite
$chkFixo.Location  = New-Object System.Drawing.Point(0, 160)
$chkFixo.Size      = New-Object System.Drawing.Size(520, 24)
$pnlSelecao.Controls.Add($chkFixo)

# Funções de Atualização
function Atualizar-Discos {
    $cmbDisco.Items.Clear()
    $script:DiscosList.Clear()
    $script:MotivosList.Clear()
    $cmbDisco.Items.Add("Buscando discos...") | Out-Null
    $cmbDisco.SelectedIndex = 0
    [System.Windows.Forms.Application]::DoEvents()

    if (-not (Test-Path $exePath)) {
        $cmbDisco.Items.Clear()
        $cmbDisco.Items.Add("Erro: GravaRaspiOS.exe não encontrado em $installDir") | Out-Null
        $cmbDisco.SelectedIndex = 0
        return
    }

    # Se o checkbox estiver ativo, envia --permitir-fixo e estende a trava de tamanho para até 2000 GB
    $argsList = "listar --todos --json"
    if ($chkFixo.Checked) { $argsList += " --permitir-fixo --max-gb 2000" }

    try {
        $json   = & $exePath $argsList.Split(' ')
        $discos = $json | ConvertFrom-Json
        $cmbDisco.Items.Clear()
        
        foreach ($d in $discos) {
            $gb = [math]::Round($d.tamanho / 1GB, 1)
            if ($d.gravavel) {
                $texto = "$($d.id): $($d.rotulo) ($gb GB) - Barramento: $($d.barramento)"
                $script:DiscosList[$texto] = $d.id
            } else {
                $texto = "$($d.id): $($d.rotulo) ($gb GB) [RECUSADO]"
                $script:MotivosList[$texto] = $d.motivo
            }
            $cmbDisco.Items.Add($texto) | Out-Null
        }

        if ($cmbDisco.Items.Count -gt 0) {
            $cmbDisco.SelectedIndex = 0
            Atualizar-Status-Selecao
        } else {
            $lblStatus.Text = "Nenhum disco detectado."
            $lblStatus.ForeColor = $Ambar
        }
    } catch {
        $cmbDisco.Items.Clear()
        $cmbDisco.Items.Add("Erro ao listar discos do sistema.") | Out-Null
        $cmbDisco.SelectedIndex = 0
    }
}

function Atualizar-Status-Selecao {
    $item = $cmbDisco.SelectedItem
    if (-not $item) { return }

    if ($script:DiscosList.ContainsKey($item)) {
        $lblStatus.Text = "Disco aprovado pelo núcleo. Pronto para gravar."
        $lblStatus.ForeColor = $Verde
    } elseif ($script:MotivosList.ContainsKey($item)) {
        $motivo = $script:MotivosList[$item]
        $lblStatus.Text = "Recusado pelo núcleo: $motivo"
        $lblStatus.ForeColor = $Vinho
    }
}

$cmbDisco.Add_SelectedIndexChanged({ Atualizar-Status-Selecao })
$chkFixo.Add_CheckedChanged({ Atualizar-Discos })

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Imagens Raspberry Pi (*.img;*.img.xz)|*.img;*.img.xz"
    if ($dlg.ShowDialog() -eq "OK") { $txtImg.Text = $dlg.FileName }
})

$btnRecarregar.Add_Click({ Atualizar-Discos })

# ==============================================================================
# PAINEL 2: SPLASH / EXECUÇÃO
# ==============================================================================
$pnlExec          = New-Object System.Windows.Forms.Panel
$pnlExec.Location = New-Object System.Drawing.Point(24, 100)
$pnlExec.Size     = New-Object System.Drawing.Size(($LARG - 60), 420)
$pnlExec.Visible  = $false
$Form.Controls.Add($pnlExec)

# Card Central
$cardSplash             = New-Object System.Windows.Forms.Panel
$cardSplash.Location    = New-Object System.Drawing.Point(0, 10)
$cardSplash.Size        = New-Object System.Drawing.Size(($LARG - 70), 220)
$cardSplash.BackColor   = [System.Drawing.Color]::White
$cardSplash.BorderStyle = "FixedSingle"
$pnlExec.Controls.Add($cardSplash)

$lblFase           = New-Object System.Windows.Forms.Label
$lblFase.Text      = "INICIANDO OPERAÇÃO..."
$lblFase.Font      = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$lblFase.ForeColor = $Preto
$lblFase.Location  = New-Object System.Drawing.Point(20, 30)
$lblFase.Size      = New-Object System.Drawing.Size(($LARG - 110), 30)
$lblFase.TextAlign = "MiddleCenter"
$cardSplash.Controls.Add($lblFase)

$pbProgress          = New-Object System.Windows.Forms.ProgressBar
$pbProgress.Location = New-Object System.Drawing.Point(40, 85)
$pbProgress.Size     = New-Object System.Drawing.Size(($LARG - 150), 24)
$cardSplash.Controls.Add($pbProgress)

$lblStats           = New-Object System.Windows.Forms.Label
$lblStats.Text      = "Aguardando comunicação com o dispositivo..."
$lblStats.Font      = New-Object System.Drawing.Font("Consolas", 10)
$lblStats.ForeColor = $Grafite
$lblStats.Location  = New-Object System.Drawing.Point(20, 130)
$lblStats.Size      = New-Object System.Drawing.Size(($LARG - 110), 40)
$lblStats.TextAlign = "MiddleCenter"
$cardSplash.Controls.Add($lblStats)

# Card Disclaimer
$cardDisc             = New-Object System.Windows.Forms.Panel
$cardDisc.Location    = New-Object System.Drawing.Point(0, 245)
$cardDisc.Size        = New-Object System.Drawing.Size(($LARG - 70), 120)
$cardDisc.BackColor   = [System.Drawing.ColorTranslator]::FromHtml("#FDF0D5")
$cardDisc.BorderStyle = "FixedSingle"
$pnlExec.Controls.Add($cardDisc)

$lblDiscTit           = New-Object System.Windows.Forms.Label
$lblDiscTit.Text      = "OBSERVAÇÃO SOBRE O TEMPO E PROGRESSO REAL"
$lblDiscTit.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$lblDiscTit.ForeColor = $Ambar
$lblDiscTit.Location  = New-Object System.Drawing.Point(14, 12)
$lblDiscTit.AutoSize  = $true
$cardDisc.Controls.Add($lblDiscTit)

$lblDiscTxt           = New-Object System.Windows.Forms.Label
$lblDiscTxt.Text      = "Esta operação pode levar vários minutos dependendo do cartão SD e do leitor.`nDevido ao buffer de escrita e sincronização física do kernel do Windows, o percentual e a taxa podem parecer estáticos por momentos. Por favor, aguarde a conclusão sem remover a mídia."
$lblDiscTxt.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$lblDiscTxt.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#4B545C")
$lblDiscTxt.Location  = New-Object System.Drawing.Point(14, 38)
$lblDiscTxt.Size      = New-Object System.Drawing.Size(($LARG - 100), 70)
$cardDisc.Controls.Add($lblDiscTxt)

# ==============================================================================
# RODAPÉ
# ==============================================================================
$lblStatus           = New-Object System.Windows.Forms.Label
$lblStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$lblStatus.ForeColor = $Grafite
$lblStatus.Location  = New-Object System.Drawing.Point(24, 535)
$lblStatus.Size      = New-Object System.Drawing.Size(420, 30)
$lblStatus.Text      = "Selecione uma imagem e o destino."
$Form.Controls.Add($lblStatus)

$btnGravar           = New-Object System.Windows.Forms.Button
$btnGravar.Text      = "Gravar Imagem"
$btnGravar.Font      = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$btnGravar.Size      = New-Object System.Drawing.Size(160, 42)
$btnGravar.Location  = New-Object System.Drawing.Point(($LARG - 320), 525)
$btnGravar.FlatStyle = "Flat"
$btnGravar.FlatAppearance.BorderSize = 0
$btnGravar.BackColor = $Azul
$btnGravar.ForeColor = [System.Drawing.Color]::White
$Form.Controls.Add($btnGravar)

$btnSair           = New-Object System.Windows.Forms.Button
$btnSair.Text      = "Sair"
$btnSair.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$btnSair.Size      = New-Object System.Drawing.Size(110, 42)
$btnSair.Location  = New-Object System.Drawing.Point(($LARG - 145), 525)
$btnSair.FlatStyle = "Flat"
$btnSair.BackColor = [System.Drawing.Color]::White
$btnSair.ForeColor = $Preto
$btnSair.Add_Click({ $Form.Close() })
$Form.Controls.Add($btnSair)

# ==============================================================================
# DIÁLOGO DE CONFIRMAÇÃO (COM ESPERA DE 10S)
# ==============================================================================
function Mostrar-Confirmacao {
    $f                 = New-Object System.Windows.Forms.Form
    $f.Text            = "AÇÃO DESTRUTIVA"
    $f.Size            = New-Object System.Drawing.Size(520, 220)
    $f.StartPosition   = "CenterParent"
    $f.FormBorderStyle = "FixedDialog"
    $f.ControlBox      = $false
    $f.BackColor       = [System.Drawing.Color]::White

    $l          = New-Object System.Windows.Forms.Label
    $l.Text     = "Tudo no disco selecionado será APAGADO e sobrescrito.`n`nVocê tem certeza que deseja prosseguir?"
    $l.Font     = New-Object System.Drawing.Font("Segoe UI", 11)
    $l.Location = New-Object System.Drawing.Point(24, 24)
    $l.Size     = New-Object System.Drawing.Size(460, 60)
    $f.Controls.Add($l)

    $bConf           = New-Object System.Windows.Forms.Button
    $bConf.Size      = New-Object System.Drawing.Size(220, 42)
    $bConf.Location  = New-Object System.Drawing.Point(260, 110)
    $bConf.BackColor = $Vinho
    $bConf.ForeColor = [System.Drawing.Color]::White
    $bConf.FlatStyle = "Flat"
    $bConf.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $bConf.Enabled   = $false
    $f.Controls.Add($bConf)

    $bCanc           = New-Object System.Windows.Forms.Button
    $bCanc.Text      = "Cancelar"
    $bCanc.Size      = New-Object System.Drawing.Size(130, 42)
    $bCanc.Location  = New-Object System.Drawing.Point(24, 110)
    $bCanc.FlatStyle = "Flat"
    $bCanc.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
    $bCanc.Add_Click({ $f.DialogResult = "Cancel"; $f.Close() })
    $f.Controls.Add($bCanc)

    $t          = New-Object System.Windows.Forms.Timer
    $t.Interval = 1000
    $script:resta = 10
    $bConf.Text   = "Confirmar ($script:resta)"
    
    $t.Add_Tick({
        $script:resta--
        if ($script:resta -le 0) {
            $bConf.Enabled = $true
            $bConf.Text    = "APAGAR E GRAVAR"
            $t.Stop()
        } else {
            $bConf.Text    = "Confirmar ($script:resta)"
        }
    })
    $bConf.Add_Click({ $f.DialogResult = "OK"; $f.Close() })

    $f.Add_Shown({ $t.Start() })
    $res = $f.ShowDialog()
    $f.Dispose()
    return ($res -eq "OK")
}

# ==============================================================================
# LÓGICA DE GRAVAÇÃO
# ==============================================================================
$btnGravar.Add_Click({
    if (-not $txtImg.Text) {
        [System.Windows.Forms.MessageBox]::Show("Selecione um arquivo de imagem.", "GravaRaspiOS", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    
    $selItem = $cmbDisco.SelectedItem
    if (-not $selItem -or (-not $script:DiscosList.ContainsKey($selItem))) {
        $motivo = if ($script:MotivosList.ContainsKey($selItem)) { $script:MotivosList[$selItem] } else { "Seleção inválida." }
        [System.Windows.Forms.MessageBox]::Show("Este destino não pode ser gravado:`n`n$motivo", "Disco Bloqueado", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $id = $script:DiscosList[$selItem]

    if (-not (Mostrar-Confirmacao)) { return }

    # Transita para a tela de Splash
    $script:Operando       = $true
    $pnlSelecao.Visible    = $false
    $pnlExec.Visible       = $true
    $btnRecarregar.Enabled = $false
    $btnGravar.Enabled     = $false
    $btnSair.Enabled       = $false
    $lblStatus.Text        = "Gravando..."

    [System.Windows.Forms.Application]::DoEvents()

    # Passa os parâmetros do desbloqueio no momento da gravação
    $cmdArgs = "gravar --imagem `"$($txtImg.Text)`" --destino $id --confirmar $id --progresso json"
    if ($chkFixo.Checked) { $cmdArgs += " --permitir-fixo --max-gb 2000" }

    try {
        $psi                         = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName                = $exePath
        $psi.Arguments               = $cmdArgs
        $psi.UseShellExecute         = $false
        $psi.RedirectStandardOutput  = $true
        $psi.RedirectStandardError   = $true
        $psi.CreateNoWindow          = $true
        $proc                        = [System.Diagnostics.Process]::Start($psi)

        while (-not $proc.HasExited) {
            while (-not $proc.StandardOutput.EndOfStream) {
                $linha = $proc.StandardOutput.ReadLine()
                if ([string]::IsNullOrWhiteSpace($linha)) { continue }

                try {
                    $p        = $linha | ConvertFrom-Json
                    $pctOrig  = [double]$p.pct
                    $fase     = [string]$p.fase
                    $taxa     = [double]$p.taxa
                    $resta    = [int]$p.resta_seg

                    # Mapeamento do Progresso Global (0 a 100%)
                    if ($fase -eq "gravando") {
                        $pctReal = $pctOrig * 0.70
                        $lblFase.Text = "GRAVANDO IMAGEM NO DISCO"
                        $mbs = [math]::Round($taxa / 1MB, 1)
                        $mins = [math]::Floor($resta / 60)
                        $segs = $resta % 60
                        $timeTxt = if ($mins -gt 0) { "${mins}m ${segs}s" } else { "${segs}s" }
                        $lblStats.Text = "Velocidade: $mbs MB/s  •  Estimativa da gravação: $timeTxt"
                    }
                    elseif ($fase -eq "sincronizando") {
                        $pctReal = 75
                        $lblFase.Text = "SINCRONIZANDO ARQUIVOS (SYNC)"
                        $lblStats.Text = "Despejando buffer do kernel no cartão de memória..."
                    }
                    elseif ($fase -eq "conferindo") {
                        $pctReal = 88
                        $lblFase.Text = "CONFERINDO INTEGRIDADE DOS DADOS"
                        $mbs = [math]::Round($taxa / 1MB, 1)
                        $lblStats.Text = if ($mbs -gt 0) { "Lendo e comparando bloco a bloco ($mbs MB/s)..." } else { "Comparando dados gravados..." }
                    }
                    elseif ($fase -eq "concluido") {
                        $pctReal = 100
                        $lblFase.Text = "GRAVAÇÃO FINALIZADA COM SUCESSO"
                        $lblStats.Text = "Conteúdo confere byte a byte."
                    }

                    $pbProgress.Value = [math]::Min([math]::Max([int]$pctReal, 0), 100)
                    [System.Windows.Forms.Application]::DoEvents()
                } catch { }
            }
            Start-Sleep -Milliseconds 50
            [System.Windows.Forms.Application]::DoEvents()
        }

        $err = $proc.StandardError.ReadToEnd()
        $rc  = $proc.ExitCode

        $script:Operando = $false
        $btnSair.Enabled = $true
        $btnSair.Text    = "Fechar"

        if ($rc -eq 0) {
            $pbProgress.Value = 100
            $lblFase.Text     = "GRAVAÇÃO FINALIZADA"
            $lblStats.Text    = "Você já pode fechar esta tela e remover o cartão."
            $lblStatus.Text   = "Sucesso."
            $lblStatus.ForeColor = $Verde
        } else {
            $pbProgress.Value = 0
            $lblFase.Text     = "OCORREU UM ERRO"
            $lblStats.Text    = "Código de erro: $rc"
            $lblStatus.Text   = "Falhou."
            $lblStatus.ForeColor = $Vinho
            [System.Windows.Forms.MessageBox]::Show("A gravação falhou (Código $rc):`n`n$err", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    } catch {
        $script:Operando     = $false
        $btnSair.Enabled     = $true
        $lblStatus.Text      = "Falha de Execução."
        $lblStatus.ForeColor = $Vinho
        [System.Windows.Forms.MessageBox]::Show("Falha ao iniciar o processo:`n`n$($_.Exception.Message)", "Erro Fatal", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$Form.Add_Shown({ Atualizar-Discos })
$Form.ShowDialog() | Out-Null
$Form.Dispose()
