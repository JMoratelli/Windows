<#
    INSTALA / ATUALIZA VENTOY - Machadao Corp
    Interface WinForms no padrao da suite de scripts (PADRAO-INTERFACE.md).

    Fluxo: splash (checa Ventoy no GitHub + varre ISOs) -> tela principal
           (pendrive, ISOs, dupla confirmacao) -> gravacao com progresso.

    Desenvolvido por @JJMoratelli
#>

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

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ============================================================ ESTADO (ISE reaproveita variaveis)
$script:Isos          = @()          # catalogo encontrado + adicionados
$script:VentoyDir     = $null
$script:VentoyVersao  = "desconhecida"
$script:Discos        = @()
$script:Fase          = "pronto"     # pronto | confirmar | rodando | fim
$script:Rodando       = $false
$script:Concluido     = $false

# ============================================================ CONFIGURACAO
$script:PastaDownloads  = Join-Path $HOME "Downloads"
$script:RaizVentoy      = Join-Path $script:PastaDownloads "VentoyExtracted"
$script:CaminhosBusca   = @((Join-Path $HOME "Downloads"), (Join-Path $HOME "Documents"), (Join-Path $HOME "Desktop"))
$script:CompartLog      = "\\192.168.13.1\t.i\04_ ISOS\LEGADO"

# Catalogo oficial. 'Padrao' aceita curinga (*) para tolerar variacao de nome.
$script:Catalogo = @(
    [PSCustomObject]@{ Rotulo = "Windows 11 25H2 - Machadao Corp"; Padrao = "Win11_25H2_JJ-MachadaoCorpV7.iso" }
    [PSCustomObject]@{ Rotulo = "Windows 11 25H2 Zanthus";         Padrao = "Win11Pro_ZeusFrentedeCaixa_v1.15.iso" }
    [PSCustomObject]@{ Rotulo = "Zanthus PDV 1.14";                Padrao = "InstaladorPDV-2.U2204.680.1.14-64-001*.iso" }
)

# --- Terreno preparado: pacote "pressed" (arquivos auxiliares no pendrive) ---
# Ligue para $true quando o release existir. Extrai em <pendrive>\ventoy\pressed.
$script:UsarPressed = $false
$script:PressedUrl  = "https://github.com/JMoratelli/Windows/releases/latest/download/pressed.7z"

# ============================================================ PALETA
$script:Preto   = [System.Drawing.ColorTranslator]::FromHtml("#12161C")
$script:Azul    = [System.Drawing.ColorTranslator]::FromHtml("#1A5FB4")
$script:AzulH   = [System.Drawing.ColorTranslator]::FromHtml("#154C90")
$script:AzulOff = [System.Drawing.ColorTranslator]::FromHtml("#A9B2BD")
$script:Grafite = [System.Drawing.ColorTranslator]::FromHtml("#5B6672")
$script:Claro   = [System.Drawing.ColorTranslator]::FromHtml("#9AA4AF")
$script:Eyebrow = [System.Drawing.ColorTranslator]::FromHtml("#7C93AE")
$script:Credito = [System.Drawing.ColorTranslator]::FromHtml("#B4BCC5")
$script:Verde   = [System.Drawing.ColorTranslator]::FromHtml("#0A6F66")
$script:Ambar   = [System.Drawing.ColorTranslator]::FromHtml("#8A5A00")
$script:Vinho   = [System.Drawing.ColorTranslator]::FromHtml("#C01C28")
$script:Painel  = [System.Drawing.ColorTranslator]::FromHtml("#EDEFF2")

# ============================================================ AJUDANTES
function New-Cabecalho {
    param($Form, $Titulo, $Contexto, $Largura)
    $cab           = New-Object System.Windows.Forms.Panel
    $cab.Size      = New-Object System.Drawing.Size($Largura, 96)
    $cab.Location  = New-Object System.Drawing.Point(0, 0)
    $cab.BackColor = $script:Preto
    $Form.Controls.Add($cab)

    $eb           = New-Object System.Windows.Forms.Label
    $eb.Text      = "M A C H A D A O   C O R P"
    $eb.Font      = New-Object System.Drawing.Font("Consolas", 9)
    $eb.ForeColor = $script:Eyebrow
    $eb.Location  = New-Object System.Drawing.Point(34, 20)
    $eb.AutoSize  = $true
    $cab.Controls.Add($eb)

    $tt           = New-Object System.Windows.Forms.Label
    $tt.Text      = $Titulo
    $tt.Font      = New-Object System.Drawing.Font("Segoe UI", 19)
    $tt.ForeColor = [System.Drawing.Color]::White
    $tt.Location  = New-Object System.Drawing.Point(32, 42)
    $tt.AutoSize  = $true
    $cab.Controls.Add($tt)

    if ($Contexto) {
        $cx           = New-Object System.Windows.Forms.Label
        $cx.Text      = $Contexto
        $cx.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
        $cx.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#C9D3DE")
        $cx.Size      = New-Object System.Drawing.Size(300, 20)
        $cx.Location  = New-Object System.Drawing.Point(($Largura - 336), 58)
        $cx.TextAlign = "MiddleRight"
        $cab.Controls.Add($cx)
    }
    return $cab
}

function New-Rotulo {
    param($Form, $Texto, $Y, $X = 36)
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $Texto
    $l.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
    $l.ForeColor = $script:Grafite
    $l.Location  = New-Object System.Drawing.Point($X, $Y)
    $l.AutoSize  = $true
    $Form.Controls.Add($l)
    return $l
}

function New-Botao {
    param($Form, $Texto, $X, $Y, $Largura, $Altura, $Fundo)
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $Texto
    $b.Font      = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $b.Size      = New-Object System.Drawing.Size($Largura, $Altura)
    $b.Location  = New-Object System.Drawing.Point($X, $Y)
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $Fundo
    $b.ForeColor = [System.Drawing.Color]::White
    $Form.Controls.Add($b)
    return $b
}

function New-BotaoMini {
    param($Form, $Texto, $X, $Y, $Largura)
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $Texto
    $b.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $b.Size      = New-Object System.Drawing.Size($Largura, 30)
    $b.Location  = New-Object System.Drawing.Point($X, $Y)
    $b.FlatStyle = "Flat"
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $script:Grafite
    $b.ForeColor = [System.Drawing.Color]::White
    $Form.Controls.Add($b)
    return $b
}

function Respirar { [System.Windows.Forms.Application]::DoEvents() }

function Format-GB { param($bytes) return ("{0:N2} GB" -f ($bytes / 1GB)) }

# ============================================================ REGRAS DE NEGOCIO
function Test-Administrador {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RotuloCatalogo {
    param($Nome)
    foreach ($c in $script:Catalogo) {
        if ($Nome -like $c.Padrao) { return $c.Rotulo }
    }
    return $null
}

function Add-Iso {
    param($Caminho)
    if (-not (Test-Path -LiteralPath $Caminho)) { return $false }
    $f = Get-Item -LiteralPath $Caminho
    if ($script:Isos | Where-Object { $_.Caminho -eq $f.FullName }) { return $false }
    $rot = Get-RotuloCatalogo $f.Name
    $nomeExibido = $f.BaseName
    if ($rot) { $nomeExibido = $rot }
    $script:Isos += [PSCustomObject]@{
        Rotulo   = $nomeExibido
        Caminho  = $f.FullName
        Nome     = $f.Name
        Tamanho  = $f.Length
        NoPadrao = [bool]$rot
        Ciente   = [bool]$rot
    }
    return $true
}

function Confirm-Desatualizada {
    param($Iso)
    if ($Iso.NoPadrao) { return $true }
    $r = [System.Windows.Forms.MessageBox]::Show(
        ("A imagem`n`n    {0}`n`nnao confere com nenhuma versao do catalogo atual - provavelmente esta desatualizada.`n`nO recomendado e baixar novamente da fonte oficial.`n`nSelecionar mesmo assim, ciente de que esta desatualizada?" -f $Iso.Nome),
        "Imagem desatualizada", "YesNo", "Warning")
    if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
        $Iso.Ciente = $true
        return $true
    }
    return $false
}

function Find-IsosPadrao {
    foreach ($c in $script:Catalogo) {
        foreach ($p in $script:CaminhosBusca) {
            if (-not (Test-Path $p)) { continue }
            $hit = Get-ChildItem -Path $p -Filter $c.Padrao -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { Add-Iso $hit.FullName | Out-Null; break }
        }
    }
}

function Find-IsosNoPC {
    param($Status)
    # Varredura propria (em vez de Get-ChildItem -Recurse) para poder responder
    # a interface e aceitar cancelamento no meio do caminho.
    $script:CancelarBusca = $false
    $pendentes = @($script:Catalogo | Where-Object { $r = $_.Rotulo; -not ($script:Isos | Where-Object { $_.Rotulo -eq $r }) })
    if ($pendentes.Count -eq 0) { return }

    $pular = @("$env:SystemRoot\WinSxS", "$env:SystemRoot\servicing", "System Volume Information", '$Recycle.Bin')
    $letras = (Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }).DriveLetter
    $conta = 0

    foreach ($d in $letras) {
        if ($script:CancelarBusca) { return }
        $fila = New-Object System.Collections.Generic.Queue[string]
        $fila.Enqueue("${d}:\")

        while ($fila.Count -gt 0) {
            if ($script:CancelarBusca) { return }
            $dir = $fila.Dequeue()
            $conta++
            if (($conta % 12) -eq 0) {
                if ($Status) { $Status.Text = "Varrendo ${d}: ...`r`n$dir" }
                Respirar
            }

            try {
                foreach ($arq in [System.IO.Directory]::EnumerateFiles($dir, "*.iso")) {
                    $nome = [System.IO.Path]::GetFileName($arq)
                    foreach ($c in $pendentes) {
                        if ($nome -like $c.Padrao) {
                            if (Add-Iso $arq) {
                                $pendentes = @($pendentes | Where-Object { $_.Rotulo -ne $c.Rotulo })
                                if ($Status) { $Status.Text = "Encontrada: $nome"; Respirar }
                            }
                            break
                        }
                    }
                    if ($pendentes.Count -eq 0) { return }
                }
            } catch { }

            try {
                foreach ($sub in [System.IO.Directory]::EnumerateDirectories($dir)) {
                    $nomeDir = [System.IO.Path]::GetFileName($sub)
                    if ($pular -contains $nomeDir -or $pular -contains $sub) { continue }
                    $info = New-Object System.IO.DirectoryInfo $sub
                    if ($info.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
                    $fila.Enqueue($sub)
                }
            } catch { }
        }
    }
}

function Update-Ventoy {
    param($Status)
    # Baixa uma unica vez: havendo copia local, nem consulta o GitHub.
    $ja = Get-VentoyLocal
    if ($ja) {
        $script:VentoyDir    = $ja.FullName
        $script:VentoyVersao = $ja.Name
        if ($Status) { $Status.Text = "Ventoy $($ja.Name) ja instalado em Downloads. Nada a baixar."; Respirar }
        return $true
    }
    # Nao apaga nada: apenas baixa/extrai a versao ausente por cima.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if ($Status) { $Status.Text = "Consultando a versao mais recente no GitHub..."; Respirar }
        $rel   = Invoke-RestMethod -Uri "https://api.github.com/repos/ventoy/Ventoy/releases/latest" -UseBasicParsing -TimeoutSec 25
        $asset = $rel.assets | Where-Object { $_.name -like "*windows.zip" } | Select-Object -First 1
        if (-not $asset) { throw "pacote windows.zip nao encontrado no release" }

        $pasta = $asset.name -replace '-windows\.zip$', ''
        $dir   = Join-Path $script:RaizVentoy $pasta
        $exe   = Join-Path $dir "Ventoy2Disk.exe"

        if (Test-Path $exe) {
            $script:VentoyDir    = $dir
            $script:VentoyVersao = $pasta
            if ($Status) { $Status.Text = "$pasta ja esta em Downloads. Nada a baixar."; Respirar }
            return $true
        }

        if ($Status) { $Status.Text = "Baixando $($asset.name)..."; Respirar }
        $zip = Join-Path $script:PastaDownloads $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing -UserAgent "Mozilla/5.0"

        if ($Status) { $Status.Text = "Extraindo o Ventoy..."; Respirar }
        Expand-Archive -Path $zip -DestinationPath $script:RaizVentoy -Force
        Remove-Item $zip -Force -ErrorAction SilentlyContinue

        if (Test-Path $exe) {
            $script:VentoyDir    = $dir
            $script:VentoyVersao = $pasta
            return $true
        }
        throw "extracao concluida, mas Ventoy2Disk.exe nao apareceu em $dir"
    }
    catch {
        # Sem internet ou GitHub fora: cai para a copia local mais recente, se houver.
        $local = Get-VentoyLocal
        if ($local) {
            $script:VentoyDir    = $local.FullName
            $script:VentoyVersao = "$($local.Name) (local, sem checagem online)"
            if ($Status) { $Status.Text = "GitHub indisponivel. Usando copia local $($local.Name)."; Respirar }
            return $true
        }
        $script:VentoyDir = $null
        if ($Status) { $Status.Text = "Falha ao obter o Ventoy: $($_.Exception.Message)"; Respirar }
        return $false
    }
}

function Get-DiscosUSB {
    return @(Get-Disk | Where-Object { $_.BusType -eq 'USB' -and $_.Size -lt 100GB } | Sort-Object Number)
}

function Get-LetraVentoy {
    param($Numero)
    $parts = Get-Partition -DiskNumber $Numero -ErrorAction SilentlyContinue
    if (-not $parts) { return $null }
    $vol = Get-Volume -ErrorAction SilentlyContinue |
           Where-Object { $_.DriveLetter -and ($_.DriveLetter -in $parts.DriveLetter) -and $_.FileSystemLabel -eq "Ventoy" }
    if ($vol) { return $vol.DriveLetter }
    return $null
}

function Copy-ComProgresso {
    param($Origem, $Destino, $Barra, $BytesFeitos, $BytesTotais)
    $buf = New-Object byte[] (4MB)
    $ent = [System.IO.File]::OpenRead($Origem)
    $sai = [System.IO.File]::Create($Destino)
    try {
        while (($lidos = $ent.Read($buf, 0, $buf.Length)) -gt 0) {
            $sai.Write($buf, 0, $lidos)
            $script:BytesAcumulados += $lidos
            $pct = [int](($script:BytesAcumulados / $BytesTotais) * 100)
            if ($pct -gt 100) { $pct = 100 }
            $Barra.Value = $pct
            Respirar
        }
    }
    finally { $ent.Close(); $sai.Close() }
}

function Write-LogForaPadrao {
    param($Acao, $Disco, $Selecionadas)
    # Silencio absoluto: qualquer falha aqui nao pode aparecer na tela.
    try {
        $fora = @($Selecionadas | Where-Object { -not $_.NoPadrao })
        if ($fora.Count -eq 0) { return }
        $agora = Get-Date
        $linhas = @(
            "=== Gravacao de ISO FORA DO PADRAO ==="
            "Data/hora : $($agora.ToString('yyyy-MM-dd HH:mm:ss'))"
            "Maquina   : $env:COMPUTERNAME"
            "Usuario   : $env:USERDOMAIN\$env:USERNAME"
            "Ventoy    : $script:VentoyVersao ($Acao)"
            "Pendrive  : Disco $($Disco.Number) - $($Disco.FriendlyName) - $(Format-GB $Disco.Size)"
            ""
            "Fora do padrao:"
        )
        foreach ($i in $fora) { $linhas += "  - $($i.Nome)  [$(Format-GB $i.Tamanho)]  origem: $($i.Caminho)" }
        $dentro = @($Selecionadas | Where-Object { $_.NoPadrao })
        if ($dentro.Count -gt 0) {
            $linhas += ""
            $linhas += "Tambem gravadas (padrao):"
            foreach ($i in $dentro) { $linhas += "  - $($i.Nome)" }
        }
        $linhas += ""

        $arq = "FORAPADRAO_{0}_{1}_{2}.txt" -f $env:COMPUTERNAME, $env:USERNAME, $agora.ToString('yyyyMMdd-HHmmss')
        $texto = $linhas -join "`r`n"

        try {
            $docs = [Environment]::GetFolderPath('MyDocuments')
            if ($docs) { [System.IO.File]::WriteAllText((Join-Path $docs $arq), $texto, [System.Text.Encoding]::UTF8) }
        } catch { }

        try {
            if (Test-Path -LiteralPath $script:CompartLog) {
                [System.IO.File]::WriteAllText((Join-Path $script:CompartLog $arq), $texto, [System.Text.Encoding]::UTF8)
            }
        } catch { }
    }
    catch { }
}

function Install-Pressed {
    param($Letra)
    # Terreno preparado: baixa pressed.7z e extrai em <pendrive>\ventoy\pressed.
    # Depende de 7z.exe/7za.exe no PATH ou no Program Files. Falha em silencio.
    if (-not $script:UsarPressed) { return }
    try {
        $tmp = Join-Path $env:TEMP "pressed.7z"
        Invoke-WebRequest -Uri $script:PressedUrl -OutFile $tmp -UseBasicParsing -UserAgent "Mozilla/5.0"
        $sete = @("7z.exe", "7za.exe", "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") |
                Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
        if (-not $sete) { return }
        $destino = "${Letra}:\ventoy\pressed"
        New-Item -ItemType Directory -Path $destino -Force | Out-Null
        Start-Process -FilePath $sete -ArgumentList @("x", "`"$tmp`"", "-o`"$destino`"", "-y") -WindowStyle Hidden -Wait
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    catch { }
}

# ============================================================ PRE-REQUISITO
if (-not (Test-Administrador)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Este script precisa ser executado como Administrador.",
        "Ventoy - Machadao Corp", "OK", "Warning") | Out-Null
    return
}

# ============================================================ SPLASH
$SL = 520
$Splash                 = New-Object System.Windows.Forms.Form
$Splash.Text            = "Preparando"
$Splash.ClientSize      = New-Object System.Drawing.Size($SL, 250)
$Splash.StartPosition   = "CenterScreen"
$Splash.FormBorderStyle = "FixedDialog"
$Splash.MaximizeBox     = $false
$Splash.MinimizeBox     = $false
$Splash.ControlBox      = $false
$Splash.TopMost         = $true
$Splash.BackColor       = [System.Drawing.Color]::White
$Splash.Add_FormClosing({ param($s, $e) if (-not $script:SplashPronto) { $e.Cancel = $true } })
New-Cabecalho $Splash "Preparando o ambiente" $env:COMPUTERNAME $SL | Out-Null

$slStatus           = New-Object System.Windows.Forms.Label
$slStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$slStatus.ForeColor = $script:Grafite
$slStatus.Location  = New-Object System.Drawing.Point(36, 126)
$slStatus.Size      = New-Object System.Drawing.Size(($SL - 72), 44)
$slStatus.Text      = "Iniciando..."
$Splash.Controls.Add($slStatus)

$slBarra          = New-Object System.Windows.Forms.ProgressBar
$slBarra.Style    = "Marquee"
$slBarra.Location = New-Object System.Drawing.Point(36, 178)
$slBarra.Size     = New-Object System.Drawing.Size(($SL - 72), 10)
$Splash.Controls.Add($slBarra)

$slNota           = New-Object System.Windows.Forms.Label
$slNota.Text      = "Nada e apagado nesta etapa."
$slNota.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$slNota.ForeColor = $script:Claro
$slNota.Location  = New-Object System.Drawing.Point(36, 198)
$slNota.AutoSize  = $true
$Splash.Controls.Add($slNota)

$script:SplashPronto = $false
$Splash.Add_Shown({
    Respirar
    Update-Ventoy $slStatus | Out-Null
    Start-Sleep -Milliseconds 400
    $slStatus.Text = "Procurando as ISOs em Downloads, Documentos e Area de Trabalho..."
    Respirar
    Find-IsosPadrao
    $slStatus.Text = "Pronto."
    Respirar
    Start-Sleep -Milliseconds 300
    $script:SplashPronto = $true
    $Splash.Close()
})
$Splash.ShowDialog() | Out-Null
$Splash.Dispose()

if (-not $script:VentoyDir) {
    [System.Windows.Forms.MessageBox]::Show(
        "Nao foi possivel obter o Ventoy (GitHub indisponivel e nenhuma copia local em $script:RaizVentoy).",
        "Ventoy - Machadao Corp", "OK", "Error") | Out-Null
    return
}

# ============================================================ JANELA PRINCIPAL
$LARG = 760
$Form                 = New-Object System.Windows.Forms.Form
$Form.Text            = "Ventoy - pendrive de instalacao"
$Form.ClientSize      = New-Object System.Drawing.Size($LARG, 628)
$Form.StartPosition   = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox     = $false
$Form.MinimizeBox     = $false
$Form.ControlBox      = $false
$Form.TopMost         = $true
$Form.BackColor       = [System.Drawing.Color]::White
$Form.Add_FormClosing({ param($s, $e) if ($script:Rodando) { $e.Cancel = $true } })

New-Cabecalho $Form "Pendrive de instalacao" "$env:COMPUTERNAME  -  $env:USERNAME" $LARG | Out-Null

$ajuda           = New-Object System.Windows.Forms.Label
$ajuda.Text      = "Ventoy $script:VentoyVersao. Escolha o pendrive e as imagens; a gravacao pede dupla confirmacao."
$ajuda.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$ajuda.ForeColor = $script:Grafite
$ajuda.Location  = New-Object System.Drawing.Point(36, 110)
$ajuda.Size      = New-Object System.Drawing.Size(($LARG - 72), 22)
$Form.Controls.Add($ajuda)

New-Rotulo $Form "Pendrive USB (ate 100 GB)" 142 | Out-Null

$cboDisco           = New-Object System.Windows.Forms.ComboBox
$cboDisco.Font      = New-Object System.Drawing.Font("Consolas", 11)
$cboDisco.Location  = New-Object System.Drawing.Point(36, 164)
$cboDisco.Size      = New-Object System.Drawing.Size(560, 30)
$cboDisco.DropDownStyle = "DropDownList"
$Form.Controls.Add($cboDisco)

$btnReler = New-BotaoMini $Form "Reler USB" 610 164 114

New-Rotulo $Form "Imagens ISO a copiar" 210 | Out-Null

$clbIsos           = New-Object System.Windows.Forms.CheckedListBox
$clbIsos.Font      = New-Object System.Drawing.Font("Consolas", 10)
$clbIsos.Location  = New-Object System.Drawing.Point(36, 232)
$clbIsos.Size      = New-Object System.Drawing.Size(($LARG - 72), 140)
$clbIsos.CheckOnClick = $true
$clbIsos.BorderStyle  = "FixedSingle"
$Form.Controls.Add($clbIsos)

$btnAdd    = New-BotaoMini $Form "+ Adicionar ISO..." 36 382 160
$btnBuscar = New-BotaoMini $Form "Buscar em todo o PC" 206 382 180

$lblEspaco           = New-Object System.Windows.Forms.Label
$lblEspaco.Font      = New-Object System.Drawing.Font("Consolas", 10)
$lblEspaco.ForeColor = $script:Grafite
$lblEspaco.Location  = New-Object System.Drawing.Point(36, 420)
$lblEspaco.Size      = New-Object System.Drawing.Size(($LARG - 72), 20)
$Form.Controls.Add($lblEspaco)

$barra          = New-Object System.Windows.Forms.ProgressBar
$barra.Location = New-Object System.Drawing.Point(36, 450)
$barra.Size     = New-Object System.Drawing.Size(($LARG - 72), 10)
$barra.Minimum  = 0
$barra.Maximum  = 100
$Form.Controls.Add($barra)

$msg           = New-Object System.Windows.Forms.Label
$msg.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$msg.ForeColor = $script:Grafite
$msg.Location  = New-Object System.Drawing.Point(36, 468)
$msg.Size      = New-Object System.Drawing.Size(($LARG - 72), 80)
$Form.Controls.Add($msg)

$creditos           = New-Object System.Windows.Forms.Label
$creditos.Text      = "Desenvolvido por @JJMoratelli"
$creditos.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$creditos.ForeColor = $script:Credito
$creditos.Location  = New-Object System.Drawing.Point(36, 574)
$creditos.AutoSize  = $true
$Form.Controls.Add($creditos)

$btnFechar  = New-Botao $Form "Fechar"  362 552 140 52 $script:Grafite
$btnIniciar = New-Botao $Form "Iniciar" ($LARG - 246) 552 210 52 $script:Azul

# ============================================================ POPULAR / RECALCULAR
function Update-ListaIsos {
    $script:Ignorar = $true
    $marcados = @()
    for ($i = 0; $i -lt $clbIsos.Items.Count; $i++) {
        if ($clbIsos.GetItemChecked($i)) { $marcados += $script:Visiveis[$i].Caminho }
    }
    $clbIsos.Items.Clear()
    $script:Visiveis = @($script:Isos)
    foreach ($iso in $script:Visiveis) {
        $tag = "[DESATUALIZADA] "
        if ($iso.NoPadrao) { $tag = "                " }
        $clbIsos.Items.Add(("{0}{1,-32} {2,10}  {3}" -f $tag, $iso.Rotulo, (Format-GB $iso.Tamanho), $iso.Nome)) | Out-Null
    }
    for ($i = 0; $i -lt $script:Visiveis.Count; $i++) {
        if ($script:Visiveis[$i].Caminho -in $marcados) { $clbIsos.SetItemChecked($i, $true) }
    }
    $script:Ignorar = $false
    Update-Espaco
}

function Get-Selecionadas {
    $sel = @()
    foreach ($i in $clbIsos.CheckedIndices) { $sel += $script:Visiveis[$i] }
    return $sel
}

function Update-Espaco {
    $sel   = Get-Selecionadas
    $total = ($sel | Measure-Object -Property Tamanho -Sum).Sum
    if (-not $total) { $total = 0 }
    $livre = $null
    if ($cboDisco.SelectedIndex -ge 0) {
        $d = $script:Discos[$cboDisco.SelectedIndex]
        $l = Get-LetraVentoy $d.Number
        if ($l) { $livre = (Get-Volume -DriveLetter $l).SizeRemaining }
    }
    if ($null -ne $livre) {
        $lblEspaco.Text = "Selecionado: $(Format-GB $total)   |   Livre no pendrive: $(Format-GB $livre)"
        $lblEspaco.ForeColor = if ($total -gt $livre) { $script:Vinho } else { $script:Grafite }
    } else {
        $lblEspaco.Text = "Selecionado: $(Format-GB $total)   |   Pendrive sera formatado pelo Ventoy (instalacao limpa)"
        $lblEspaco.ForeColor = $script:Grafite
    }
    if ($script:Fase -eq "confirmar") { Reset-Confirmacao }
}

function Update-Discos {
    $script:Discos = Get-DiscosUSB
    $cboDisco.Items.Clear()
    foreach ($d in $script:Discos) {
        $l   = Get-LetraVentoy $d.Number
        $est = "sem Ventoy (sera formatado)"
        if ($l) { $est = "Ventoy em ${l}: (sera atualizado)" }
        $cboDisco.Items.Add(("Disco {0} - {1} - {2} - {3}" -f $d.Number, $d.FriendlyName, (Format-GB $d.Size), $est)) | Out-Null
    }
    if ($cboDisco.Items.Count -gt 0) { $cboDisco.SelectedIndex = 0 }
    else {
        $msg.ForeColor = $script:Vinho
        $msg.Text = "Nenhum pendrive USB abaixo de 100 GB detectado. Conecte o dispositivo e clique em Reler USB."
    }
    Update-Espaco
}

function Set-InterfaceAtiva {
    param([bool]$Ativa)
    $cboDisco.Enabled   = $Ativa
    $clbIsos.Enabled    = $Ativa
    $btnAdd.Enabled     = $Ativa
    $btnReler.Enabled   = $Ativa
    $btnBuscar.Enabled  = $Ativa
    $btnIniciar.Enabled = $Ativa
    $btnFechar.Enabled  = $Ativa
    Respirar
}

function Reset-Confirmacao {
    $script:Fase = "pronto"
    $btnIniciar.Text      = "Iniciar"
    $btnIniciar.BackColor = $script:Azul
    $btnIniciar.Enabled   = $true
}

# ============================================================ EVENTOS
$clbIsos.Add_ItemCheck({
    param($s, $e)
    if ($script:Ignorar) { return }
    if ($e.NewValue -eq [System.Windows.Forms.CheckState]::Checked) {
        $iso = $script:Visiveis[$e.Index]
        if (-not $iso.Ciente) {
            if (-not (Confirm-Desatualizada $iso)) {
                $e.NewValue = [System.Windows.Forms.CheckState]::Unchecked
                return
            }
        }
        if (-not $iso.NoPadrao) {
            $msg.ForeColor = $script:Ambar
            $msg.Text = "Imagem desatualizada selecionada: $($iso.Nome)"
        }
    }
    # o estado ainda nao mudou neste evento; recalcula logo depois
    $script:Adiar = $true
})
$clbIsos.Add_SelectedIndexChanged({ if ($script:Adiar) { $script:Adiar = $false; Update-Espaco } })
$clbIsos.Add_MouseUp({ Update-Espaco })
$clbIsos.Add_KeyUp({ Update-Espaco })

$cboDisco.Add_SelectedIndexChanged({ Update-Espaco })

$btnReler.Add_Click({
    $msg.ForeColor = $script:Grafite
    $msg.Text = "Relendo dispositivos USB..."
    Respirar
    Update-Discos
    if ($script:Discos.Count -gt 0) { $msg.Text = "" }
})

$btnAdd.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter      = "Imagens ISO (*.iso)|*.iso"
    $dlg.Multiselect = $true
    $dlg.Title       = "Selecione uma ou mais imagens ISO"
    $Form.TopMost = $false
    $r = $dlg.ShowDialog()
    $Form.TopMost = $true
    if ($r -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $novas = 0; $recusadas = 0
    foreach ($c in $dlg.FileNames) {
        $nome = [System.IO.Path]::GetFileName($c)
        if (-not (Get-RotuloCatalogo $nome)) {
            $falso = [PSCustomObject]@{ Nome = $nome; NoPadrao = $false; Ciente = $false }
            if (-not (Confirm-Desatualizada $falso)) { $recusadas++; continue }
            if (Add-Iso $c) {
                $novas++
                ($script:Isos | Where-Object { $_.Caminho -eq (Get-Item -LiteralPath $c).FullName })[0].Ciente = $true
            }
            continue
        }
        if (Add-Iso $c) { $novas++ }
    }
    Update-ListaIsos
    $script:Ignorar = $true
    for ($i = 0; $i -lt $script:Visiveis.Count; $i++) {
        if ($script:Visiveis[$i].Ciente -and $script:Visiveis[$i].Caminho -in $dlg.FileNames) { $clbIsos.SetItemChecked($i, $true) }
    }
    $script:Ignorar = $false
    Update-Espaco
    $msg.ForeColor = $script:Grafite
    $msg.Text = "$novas imagem(ns) adicionada(s)."
    if ($recusadas -gt 0) { $msg.Text += " $recusadas descartada(s) por estar(em) desatualizada(s)." }
})

$btnBuscar.Add_Click({
    if ($script:Buscando) {
        $script:CancelarBusca = $true
        $btnBuscar.Text    = "Cancelando..."
        $btnBuscar.Enabled = $false
        return
    }

    $script:Buscando = $true
    Set-InterfaceAtiva $false
    $btnBuscar.Enabled   = $true
    $btnBuscar.Text      = "Cancelar varredura"
    $btnBuscar.BackColor = $script:Vinho
    $msg.ForeColor = $script:Grafite
    $msg.Text = "Varrendo as unidades fixas. Isso pode levar alguns minutos..."
    Respirar

    try   { Find-IsosNoPC $msg }
    catch { }

    $cancelada = $script:CancelarBusca
    $script:Buscando = $false
    Update-ListaIsos
    $btnBuscar.Text      = "Buscar em todo o PC"
    $btnBuscar.BackColor = $script:Grafite
    Set-InterfaceAtiva $true
    $msg.ForeColor = $script:Grafite
    if ($cancelada) { $msg.Text = "Varredura cancelada. $($script:Isos.Count) imagem(ns) na lista." }
    else            { $msg.Text = "Busca concluida. $($script:Isos.Count) imagem(ns) na lista." }
})

$btnFechar.Add_Click({
    if ($script:Rodando) { return }
    if ($script:Fase -eq "confirmar") { Reset-Confirmacao; $msg.Text = "Gravacao cancelada."; return }
    $script:Concluido = $true
    $Form.Close()
})

$btnIniciar.Add_Click({
    if ($script:Fase -eq "fim") { $Form.Close(); return }
    if ($script:Rodando) { return }

    # ---------- validacao ----------
    $msg.ForeColor = $script:Vinho
    if ($cboDisco.SelectedIndex -lt 0) { $msg.Text = "Selecione o pendrive."; return }
    $disco = $script:Discos[$cboDisco.SelectedIndex]
    $sel   = Get-Selecionadas

    $letra = Get-LetraVentoy $disco.Number
    $acao  = "/I"
    if ($letra) { $acao = "/U" }

    if ($sel.Count -gt 0 -and $letra) {
        $total = ($sel | Measure-Object -Property Tamanho -Sum).Sum
        $livre = (Get-Volume -DriveLetter $letra).SizeRemaining
        # ja existentes com mesmo tamanho nao ocupam espaco novo
        foreach ($i in $sel) {
            $dst = "${letra}:\$($i.Nome)"
            if ((Test-Path -LiteralPath $dst) -and ((Get-Item -LiteralPath $dst).Length -eq $i.Tamanho)) { $total -= $i.Tamanho }
        }
        if ($total -gt $livre) {
            $msg.Text = "Espaco insuficiente: precisa de $(Format-GB $total) e ha $(Format-GB $livre) livres."
            return
        }
    }

    # ---------- 1a confirmacao: espera de 10s ----------
    if ($script:Fase -eq "pronto") {
        $script:Fase = "confirmar"
        $msg.ForeColor = $script:Ambar
        $resumo = "Atualizacao do Ventoy no Disco $($disco.Number) ($($disco.FriendlyName)), preservando os arquivos."
        if ($acao -eq "/I") { $resumo = "INSTALACAO LIMPA no Disco $($disco.Number) ($($disco.FriendlyName)). TODOS OS DADOS DO PENDRIVE SERAO APAGADOS." }
        $msg.Text = "$resumo`nSerao copiadas $($sel.Count) imagem(ns). Confirme para prosseguir."
        $btnIniciar.BackColor = $script:AzulOff
        $btnIniciar.Enabled   = $false
        Respirar
        for ($s = 10; $s -ge 1; $s--) {
            $btnIniciar.Text = "Confirmar ($s)"
            for ($k = 0; $k -lt 10; $k++) { Start-Sleep -Milliseconds 100; Respirar }
            if ($script:Fase -ne "confirmar") { return }   # cancelado no meio
        }
        $btnIniciar.Text      = "Confirmar gravacao"
        $btnIniciar.BackColor = $script:Vinho
        $btnIniciar.Enabled   = $true
        return
    }

    # ---------- 2a confirmacao: executa ----------
    $script:Rodando = $true
    $script:Fase    = "rodando"
    $btnIniciar.Enabled = $false
    $btnIniciar.Text    = "Aguarde..."
    $btnFechar.Enabled  = $false
    $btnAdd.Enabled     = $false
    $btnBuscar.Enabled  = $false
    $btnReler.Enabled   = $false
    $cboDisco.Enabled   = $false
    $clbIsos.Enabled    = $false
    $msg.ForeColor      = $script:Grafite
    $barra.Value        = 0

    try {
        Write-LogForaPadrao $acao $disco $sel

        $msg.Text = "Gravando o Ventoy no pendrive. Nao remova o dispositivo..."
        Respirar
        $exe = Join-Path $script:VentoyDir "Ventoy2Disk.exe"
        $arg = @("VTOYCLI", "/U", "/PhyDrive:$($disco.Number)")
        if ($acao -eq "/I") { $arg = @("VTOYCLI", "/I", "/PhyDrive:$($disco.Number)", "/GPT") }
        Start-Process -FilePath $exe -ArgumentList $arg -WorkingDirectory $script:VentoyDir -WindowStyle Hidden -Wait
        $barra.Value = 15
        Respirar

        $done = Join-Path $script:VentoyDir "cli_done.txt"
        if (Test-Path $done) {
            $cod = (Get-Content $done -Raw).Trim()
            if ($cod -ne "0") { throw "Ventoy2Disk retornou codigo $cod. Veja cli_log.txt em $script:VentoyDir." }
        }

        $msg.Text = "Aguardando o Windows remontar as particoes..."
        Respirar
        for ($k = 0; $k -lt 70; $k++) { Start-Sleep -Milliseconds 100; Respirar }

        $letra = Get-LetraVentoy $disco.Number
        if (-not $letra) {
            $p = Get-Partition -DiskNumber $disco.Number | Where-Object DriveLetter | Sort-Object Size -Descending | Select-Object -First 1
            $letra = $p.DriveLetter
        }
        if (-not $letra -and $sel.Count -gt 0) { throw "Nao foi possivel obter a letra do pendrive para copiar as imagens." }

        Install-Pressed $letra

        if ($sel.Count -eq 0) {
            $barra.Value = 100
            $msg.ForeColor = $script:Verde
            $msg.Text = "Ventoy $script:VentoyVersao gravado. Nenhuma imagem foi copiada."
        }
        else {
            $aCopiar = @()
            foreach ($i in $sel) {
                $dst = "${letra}:\$($i.Nome)"
                if ((Test-Path -LiteralPath $dst) -and ((Get-Item -LiteralPath $dst).Length -eq $i.Tamanho)) { continue }
                $aCopiar += $i
            }
            if ($aCopiar.Count -eq 0) {
                $barra.Value = 100
                $msg.ForeColor = $script:Verde
                $msg.Text = "Ventoy atualizado. As imagens selecionadas ja estavam no pendrive."
            }
            else {
                $script:BytesAcumulados = 0
                $bytesTotais = ($aCopiar | Measure-Object -Property Tamanho -Sum).Sum
                $n = 0
                foreach ($i in $aCopiar) {
                    $n++
                    $msg.Text = "Copiando $n de $($aCopiar.Count): $($i.Nome)  ($(Format-GB $i.Tamanho))"
                    Respirar
                    Copy-ComProgresso $i.Caminho "${letra}:\$($i.Nome)" $barra $script:BytesAcumulados $bytesTotais
                }
                $barra.Value = 100
                $msg.ForeColor = $script:Verde
                $msg.Text = "Concluido. Ventoy $script:VentoyVersao em ${letra}: com $($aCopiar.Count) imagem(ns) copiada(s)."
            }
        }

        $script:Rodando   = $false
        $script:Concluido = $true
        $script:Fase      = "fim"
        $btnIniciar.Text      = "Concluir"
        $btnIniciar.BackColor = $script:Verde
        $btnIniciar.Enabled   = $false
        Respirar
        for ($k = 0; $k -lt 25; $k++) { Start-Sleep -Milliseconds 100; Respirar }
        $Form.Close()
    }
    catch {
        $script:Rodando = $false
        $script:Fase    = "pronto"
        $msg.ForeColor  = $script:Vinho
        $msg.Text       = "Falha: $($_.Exception.Message)"
        $barra.Value    = 0
        $btnIniciar.Text      = "Tentar novamente"
        $btnIniciar.BackColor = $script:Azul
        $btnIniciar.Enabled   = $true
        $btnFechar.Enabled    = $true
        $btnAdd.Enabled       = $true
        $btnBuscar.Enabled    = $true
        $btnReler.Enabled     = $true
        $cboDisco.Enabled     = $true
        $clbIsos.Enabled      = $true
    }
})

# ============================================================ ABERTURA
$script:Visiveis = @()
$Form.Add_Shown({
    Update-Discos
    Update-ListaIsos
    $script:Ignorar = $true
    for ($i = 0; $i -lt $script:Visiveis.Count; $i++) { $clbIsos.SetItemChecked($i, $true) }
    $script:Ignorar = $false
    Update-Espaco
    $faltam = @($script:Catalogo | Where-Object { $r = $_.Rotulo; -not ($script:Isos | Where-Object { $_.Rotulo -eq $r }) })
    if ($faltam.Count -gt 0) {
        $linhas = @("Nao encontrei nas pastas padrao (use 'Buscar em todo o PC' ou '+ Adicionar ISO...'):")
        foreach ($f in $faltam) { $linhas += "   - $($f.Rotulo)" }
        $msg.ForeColor = $script:Ambar
        $msg.Text = $linhas -join "`r`n"
    }
})
$Form.ShowDialog() | Out-Null
$Form.Dispose()
