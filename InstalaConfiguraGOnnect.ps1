<#
    Instala e configura o GOnnect (SIP) - Machadao Corp
    Tela unica: pede Ramal e Senha, e ao confirmar ja instala e configura.

    O script roda com conta de ADMINISTRADOR diferente do usuario final.
    Por isso os caminhos de AppData NAO usam $env:LOCALAPPDATA: o perfil do
    usuario logado interativamente e resolvido via Get-UsuarioLogadoInfo.
    NAO alterar essa parte - sem ela o GOnnect nao le a configuracao.

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

# O ISE mantem variaveis entre execucoes: zera o estado logo no inicio.
$script:Concluido   = $false
$script:PodeFechar  = $true
$script:UsuarioAlvo = $null

# ============================================================ PALETA
$script:CorPreto   = [System.Drawing.ColorTranslator]::FromHtml("#12161C")
$script:CorAzul    = [System.Drawing.ColorTranslator]::FromHtml("#1A5FB4")
$script:CorAzulH   = [System.Drawing.ColorTranslator]::FromHtml("#154C90")
$script:CorCinza   = [System.Drawing.ColorTranslator]::FromHtml("#A9B2BD")
$script:CorGrafite = [System.Drawing.ColorTranslator]::FromHtml("#5B6672")
$script:CorClaro   = [System.Drawing.ColorTranslator]::FromHtml("#9AA4AF")
$script:CorEyebrow = [System.Drawing.ColorTranslator]::FromHtml("#7C93AE")
$script:CorCredito = [System.Drawing.ColorTranslator]::FromHtml("#B4BCC5")
$script:CorVerde   = [System.Drawing.ColorTranslator]::FromHtml("#0A6F66")
$script:CorAmbar   = [System.Drawing.ColorTranslator]::FromHtml("#8A5A00")
$script:CorVinho   = [System.Drawing.ColorTranslator]::FromHtml("#C01C28")
$script:CorCampo   = [System.Drawing.ColorTranslator]::FromHtml("#EDEFF2")

$script:ExeGOnnect = "C:\Program Files\GOnnect\bin\gonnect.exe"
$script:PastaExe   = "C:\Program Files\GOnnect\bin"

# ============================================================ FUNCOES
# Descobre o AppData\Local do usuario logado interativamente,
# independente de quem esta rodando o script. NAO MEXER.
function Get-UsuarioLogadoInfo {
    # Cadeia de deteccao: para na primeira que devolver um nome.
    # 1) Win32_ComputerSystem.UserName  - vazio em RDP, sessao bloqueada
    #    ou quando o script sobe por tarefa agendada / SYSTEM
    # 2) dono do explorer.exe           - quem tem shell de verdade
    # 3) query session / quser          - sessao Active no terminal
    # 4) a propria conta que roda        - ultimo recurso
    $candidatos = New-Object System.Collections.Generic.List[string]

    try {
        $n = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($n) { $candidatos.Add($n) }
    } catch { }

    try {
        Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop |
            ForEach-Object {
                $dono = Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction SilentlyContinue
                if ($dono -and $dono.User) {
                    $dom = if ($dono.Domain) { $dono.Domain } else { $env:COMPUTERNAME }
                    $candidatos.Add("$dom\$($dono.User)")
                }
            }
    } catch { }

    try {
        $linhas = & query session 2>$null
        foreach ($linha in $linhas) {
            if ($linha -match '^\s*>?\S*\s+(\S+)\s+\d+\s+Ativ' -or
                $linha -match '^\s*>?\S*\s+(\S+)\s+\d+\s+Active') {
                $u = $matches[1]
                if ($u -and $u -notmatch '^\d+$') { $candidatos.Add("$env:COMPUTERNAME\$u") }
            }
        }
    } catch { }

    if ($env:USERNAME) {
        $dom = if ($env:USERDOMAIN) { $env:USERDOMAIN } else { $env:COMPUTERNAME }
        $candidatos.Add("$dom\$env:USERNAME")
    }

    $vistos = @{}
    foreach ($usuarioLogado in $candidatos) {
        if (-not $usuarioLogado) { continue }
        $chave = $usuarioLogado.ToLower()
        if ($vistos.ContainsKey($chave)) { continue }
        $vistos[$chave] = $true

        # Contas de servico nao tem perfil util para o GOnnect
        if ($usuarioLogado -match '\\(SYSTEM|LOCAL SERVICE|NETWORK SERVICE|DWM-\d+|UMFD-\d+)$') { continue }

        try {
            $objUser = New-Object System.Security.Principal.NTAccount($usuarioLogado)
            $sid = $objUser.Translate([System.Security.Principal.SecurityIdentifier]).Value

            $chaveProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
            if (-not (Test-Path $chaveProfile)) { continue }

            $caminhoPerfil = (Get-ItemProperty -Path $chaveProfile).ProfileImagePath
            if (-not (Test-Path -LiteralPath $caminhoPerfil)) { continue }

            return [PSCustomObject]@{
                NomeCompleto = $usuarioLogado
                NomeUsuario  = $usuarioLogado.Split('\')[-1]
                SID          = $sid
                PerfilPath   = $caminhoPerfil
                LocalAppData = (Join-Path $caminhoPerfil "AppData\Local")
            }
        }
        catch { continue }
    }

    throw "Nao foi possivel resolver o perfil do usuario final nesta maquina."
}

function Test-GOnnectInstalado {
    $chaves = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $achado = Get-ItemProperty -Path $chaves -ErrorAction SilentlyContinue |
              Where-Object { $_.DisplayName -like "*GOnnect*" }
    return [bool]$achado
}

# A release mais recente nem sempre traz instalador Windows: varre o
# historico ate achar um asset win64.
function Install-GOnnect {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $cabecalhos = @{ 'User-Agent' = 'Machadao-Instalador' }

    $releases = Invoke-RestMethod -UseBasicParsing -ErrorAction Stop -Headers $cabecalhos `
                -Uri "https://api.github.com/repos/gonicus/gonnect/releases?per_page=100"

    $asset = $null
    $tag   = $null
    foreach ($rel in $releases) {
        $achado = $rel.assets |
                  Where-Object { $_.name -like "*win64*.exe" } |
                  Select-Object -First 1
        if ($achado) { $asset = $achado; $tag = $rel.tag_name; break }
    }
    if (-not $asset) {
        throw "nenhuma das $($releases.Count) releases tem instalador win64"
    }

    $destino = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $destino `
        -UseBasicParsing -Headers $cabecalhos -ErrorAction Stop

    Start-Process -FilePath $destino -ArgumentList "/S" -Wait -WindowStyle Hidden
    Remove-Item $destino -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path -LiteralPath $script:ExeGOnnect)) {
        throw "executavel nao encontrado em $script:ExeGOnnect"
    }
    return $tag
}

function New-AtalhosGOnnect {
    $ws = New-Object -ComObject WScript.Shell

    $s1 = $ws.CreateShortcut("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\GOnnect.lnk")
    $s1.TargetPath = $script:ExeGOnnect
    $s1.WorkingDirectory = $script:PastaExe
    $s1.Save()

    $s2 = $ws.CreateShortcut("$env:Public\Desktop\GOnnect.lnk")
    $s2.TargetPath = $script:ExeGOnnect
    $s2.WorkingDirectory = $script:PastaExe
    $s2.Save()
}

# Grava os .conf no perfil do USUARIO FINAL (nao no do admin). NAO MEXER
# nos caminhos nem no icacls: sem isso o GOnnect nao le nem regrava.
function Write-ConfiguracaoRamal {
    param(
        [Parameter(Mandatory=$true)][string]$LocalAppDataUsuario,
        [Parameter(Mandatory=$true)][string]$Ramal,
        [Parameter(Mandatory=$true)][string]$Senha
    )

    $CaminhoDestino  = Join-Path $LocalAppDataUsuario "gonnect\GOnnect\gonnect"
    $CaminhoCompleto = Join-Path $CaminhoDestino "01-sip.conf"
    $CaminhoUserConf = Join-Path $CaminhoDestino "99-user.conf"

    # Fecha o GOnnect para liberar a pasta e forcar releitura ao reabrir
    Stop-Process -Name "GOnnect" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    if (-not (Test-Path -LiteralPath $CaminhoDestino)) {
        New-Item -ItemType Directory -Path $CaminhoDestino -Force | Out-Null
    }

    $ConteudoINI = @"
[template]
name="Local SIP Configuration"
plain=true

[generic]
autostart=true
showCallWindowOnStartup=true
busyOnBusy=true
showMainWindowOnStart=true

[ua]
maxCalls=4

[account0]
## Endereco do usuario (Ramal + IP do Servidor)
userUri=sip:$Ramal@voip.redejcm.com.br

## IP do Servidor SIP (Registrar)
registrarUri=sip:voip.redejcm.com.br

## Desativado para conexoes locais sem certificado SSL
srtpUse=disabled
srtpSecureSignaling=0

## Porta padrao para SIP UDP
port=5060

contactRewriteMethod=always-update
contactUseSrcPort=true

## Aponta para a secao de autenticacao abaixo
auth=auth0

## Transporte alterado para UDP (padrao em redes locais)
transport=udp

## Define o protocolo de rede como automatico (IPv4)
network=auto

#Ativa texto em tempo real
realTimeText=true

[auth0]
## Esquema de autenticacao padrao
scheme=Digest

## Usuario (Seu Ramal)
username=$Ramal

## Aceita qualquer realm do servidor local
realm=*

## Tipo da senha
type=plain

## Senha do Ramal
data=$Senha
"@

    $ConteudoUserConf = @"
[generic]
showTrayDialog=true
noSyncSystemMute=false
showMainWindowOnStart=true
useOwnWindowDecoration=false
"@

    Set-Content -Path $CaminhoCompleto -Value $ConteudoINI      -Force -Encoding UTF8
    Set-Content -Path $CaminhoUserConf -Value $ConteudoUserConf -Force -Encoding UTF8

    # O script roda como admin: libera controle total para o dono do perfil
    icacls $CaminhoCompleto /grant "Todos:(F)" | Out-Null
    icacls $CaminhoUserConf /grant "Todos:(F)" | Out-Null

    # Confere o que gravou antes de dizer que deu certo
    if (-not (Test-Path -LiteralPath $CaminhoCompleto)) {
        throw "o arquivo 01-sip.conf nao foi gravado em $CaminhoDestino"
    }
    if (-not ((Get-Content -LiteralPath $CaminhoCompleto -Raw) -match [regex]::Escape("username=$Ramal"))) {
        throw "o 01-sip.conf gravado nao contem o ramal informado"
    }
}

# Sobe o GOnnect DENTRO DA SESSAO do usuario final via tarefa agendada
# temporaria com token interativo (/IT).
function Start-ProcessoNaSessaoDoUsuario {
    param(
        [Parameter(Mandatory=$true)][string]$NomeUsuario,
        [Parameter(Mandatory=$true)][string]$CaminhoExe
    )

    $nomeTarefa = "GOnnect-Start-Temp"
    $comando    = "`"$CaminhoExe`""
    $horaExec   = (Get-Date).AddMinutes(1).ToString("HH:mm")

    schtasks /Delete /TN $nomeTarefa /F 2>$null | Out-Null
    schtasks /Create /TN $nomeTarefa /TR $comando /SC ONCE /ST $horaExec `
             /RU $NomeUsuario /IT /F | Out-Null
    schtasks /Run /TN $nomeTarefa | Out-Null
    Start-Sleep -Seconds 5
    schtasks /Delete /TN $nomeTarefa /F 2>$null | Out-Null
}

# ============================================================ JANELA
$LARG = 660
$script:Form          = New-Object System.Windows.Forms.Form
$Form                 = $script:Form
$Form.Text            = "GOnnect (SIP) - Machadao Corp"
$Form.Size            = New-Object System.Drawing.Size($LARG, 470)
$Form.StartPosition   = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox     = $false
$Form.MinimizeBox     = $false
$Form.ControlBox      = $false
$Form.TopMost         = $true
$Form.BackColor       = [System.Drawing.Color]::White

$Form.Add_FormClosing({
    param($s, $e)
    if (-not $script:PodeFechar) { $e.Cancel = $true }
})

# ============================================================ CABECALHO
$cab           = New-Object System.Windows.Forms.Panel
$cab.Size      = New-Object System.Drawing.Size($LARG, 96)
$cab.BackColor = $script:CorPreto
$Form.Controls.Add($cab)

$eyebrow           = New-Object System.Windows.Forms.Label
$eyebrow.Text      = "M A C H A D A O   C O R P"
$eyebrow.Font      = New-Object System.Drawing.Font("Consolas", 9)
$eyebrow.ForeColor = $script:CorEyebrow
$eyebrow.Location  = New-Object System.Drawing.Point(34, 20)
$eyebrow.AutoSize  = $true
$cab.Controls.Add($eyebrow)

$titulo           = New-Object System.Windows.Forms.Label
$titulo.Text      = "Instalacao do ramal GOnnect"
$titulo.Font      = New-Object System.Drawing.Font("Segoe UI", 19)
$titulo.ForeColor = [System.Drawing.Color]::White
$titulo.Location  = New-Object System.Drawing.Point(32, 42)
$titulo.AutoSize  = $true
$cab.Controls.Add($titulo)

# Duas linhas: maquina em cima, usuario embaixo. Nomes de dominio+usuario
# nao cabem numa linha so ao lado do titulo - por isso separados.
$script:Contexto           = New-Object System.Windows.Forms.Label
$script:Contexto.Text      = "$env:COMPUTERNAME"
$script:Contexto.Font      = New-Object System.Drawing.Font("Consolas", 9)
$script:Contexto.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#C9D3DE")
$script:Contexto.Location  = New-Object System.Drawing.Point(360, 46)
$script:Contexto.Size      = New-Object System.Drawing.Size(($LARG - 394), 18)
$script:Contexto.TextAlign = "MiddleRight"
$script:Contexto.AutoEllipsis = $true
$cab.Controls.Add($script:Contexto)

$script:ContextoUsuario           = New-Object System.Windows.Forms.Label
$script:ContextoUsuario.Text      = ""
$script:ContextoUsuario.Font      = New-Object System.Drawing.Font("Consolas", 9)
$script:ContextoUsuario.ForeColor = $script:CorEyebrow
$script:ContextoUsuario.Location  = New-Object System.Drawing.Point(360, 66)
$script:ContextoUsuario.Size      = New-Object System.Drawing.Size(($LARG - 394), 18)
$script:ContextoUsuario.TextAlign = "MiddleRight"
$script:ContextoUsuario.AutoEllipsis = $true
$cab.Controls.Add($script:ContextoUsuario)

# ============================================================ CONTEUDO
$ajuda           = New-Object System.Windows.Forms.Label
$ajuda.Text      = "Informe o ramal e a senha. O GOnnect sera instalado e configurado para o usuario logado."
$ajuda.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$ajuda.ForeColor = $script:CorGrafite
$ajuda.Location  = New-Object System.Drawing.Point(36, 122)
$ajuda.Size      = New-Object System.Drawing.Size(($LARG - 70), 24)
$Form.Controls.Add($ajuda)

$lblRamal           = New-Object System.Windows.Forms.Label
$lblRamal.Text      = "Ramal"
$lblRamal.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$lblRamal.ForeColor = $script:CorGrafite
$lblRamal.Location  = New-Object System.Drawing.Point(36, 160)
$lblRamal.AutoSize  = $true
$Form.Controls.Add($lblRamal)

$script:TxtRamal          = New-Object System.Windows.Forms.TextBox
$script:TxtRamal.Font     = New-Object System.Drawing.Font("Consolas", 16)
$script:TxtRamal.Location = New-Object System.Drawing.Point(36, 182)
$script:TxtRamal.Size     = New-Object System.Drawing.Size(240, 38)
$Form.Controls.Add($script:TxtRamal)

$lblSenha           = New-Object System.Windows.Forms.Label
$lblSenha.Text      = "Senha do ramal"
$lblSenha.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$lblSenha.ForeColor = $script:CorGrafite
$lblSenha.Location  = New-Object System.Drawing.Point(312, 160)
$lblSenha.AutoSize  = $true
$Form.Controls.Add($lblSenha)

$script:TxtSenha              = New-Object System.Windows.Forms.TextBox
$script:TxtSenha.Font         = New-Object System.Drawing.Font("Consolas", 16)
$script:TxtSenha.Location     = New-Object System.Drawing.Point(312, 182)
$script:TxtSenha.Size         = New-Object System.Drawing.Size(276, 38)
$script:TxtSenha.PasswordChar = '*'
$Form.Controls.Add($script:TxtSenha)

$script:LblPerfil           = New-Object System.Windows.Forms.Label
$script:LblPerfil.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$script:LblPerfil.ForeColor = $script:CorClaro
$script:LblPerfil.Location  = New-Object System.Drawing.Point(36, 228)
$script:LblPerfil.Size      = New-Object System.Drawing.Size(($LARG - 70), 20)
$Form.Controls.Add($script:LblPerfil)

# ============================================================ MENSAGEM
$script:Msg           = New-Object System.Windows.Forms.Label
$script:Msg.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$script:Msg.ForeColor = $script:CorGrafite
$script:Msg.Location  = New-Object System.Drawing.Point(36, 256)
$script:Msg.Size      = New-Object System.Drawing.Size(($LARG - 70), 44)
$Form.Controls.Add($script:Msg)

$script:Barra          = New-Object System.Windows.Forms.ProgressBar
$script:Barra.Location = New-Object System.Drawing.Point(36, 306)
$script:Barra.Size     = New-Object System.Drawing.Size(($LARG - 70), 6)
$script:Barra.Maximum  = 6
$script:Barra.Style    = "Continuous"
$Form.Controls.Add($script:Barra)

# ============================================================ RODAPE
$creditos           = New-Object System.Windows.Forms.Label
$creditos.Text      = "Desenvolvido por @JJMoratelli"
$creditos.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$creditos.ForeColor = $script:CorCredito
$creditos.Location  = New-Object System.Drawing.Point(36, 392)
$creditos.AutoSize  = $true
$Form.Controls.Add($creditos)

$script:BtnAcao = New-Object System.Windows.Forms.Button
$script:BtnAcao.Text      = "Instalar e configurar"
$script:BtnAcao.Font      = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$script:BtnAcao.Size      = New-Object System.Drawing.Size(210, 50)
$script:BtnAcao.Location  = New-Object System.Drawing.Point(($LARG - 254), 372)
$script:BtnAcao.FlatStyle = "Flat"
$script:BtnAcao.FlatAppearance.BorderSize = 0
$script:BtnAcao.BackColor = $script:CorAzul
$script:BtnAcao.ForeColor = [System.Drawing.Color]::White
$Form.Controls.Add($script:BtnAcao)
$Form.AcceptButton = $script:BtnAcao

# Caminho de saida sempre visivel; some so enquanto a instalacao roda.
$script:BtnFechar = New-Object System.Windows.Forms.Button
$script:BtnFechar.Text      = "Fechar"
$script:BtnFechar.Font      = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$script:BtnFechar.Size      = New-Object System.Drawing.Size(120, 50)
$script:BtnFechar.Location  = New-Object System.Drawing.Point(($LARG - 386), 372)
$script:BtnFechar.FlatStyle = "Flat"
$script:BtnFechar.FlatAppearance.BorderSize = 0
$script:BtnFechar.BackColor = $script:CorGrafite
$script:BtnFechar.ForeColor = [System.Drawing.Color]::White
$Form.Controls.Add($script:BtnFechar)

$script:BtnFechar.Add_Click({
    if (-not $script:PodeFechar) { return }
    $script:Concluido = $true
    $script:Form.Close()
})

# ============================================================ LOGICA
function Set-Etapa {
    param([string]$Texto, [int]$Passo, $Cor = $null)
    if ($null -eq $Cor) { $Cor = $script:CorGrafite }
    $script:Msg.ForeColor = $Cor
    $script:Msg.Text      = $Texto
    if ($Passo -ge 0) { $script:Barra.Value = [Math]::Min($Passo, $script:Barra.Maximum) }
    [System.Windows.Forms.Application]::DoEvents()
}

$script:BtnAcao.Add_Click({
    if ($script:Concluido) { $script:Form.Close(); return }

    $ramal = $script:TxtRamal.Text.Trim()
    $senha = $script:TxtSenha.Text.Trim()

    if (-not $ramal) { Set-Etapa "Informe o ramal." (-1) $script:CorVinho; $script:TxtRamal.Focus(); return }
    if (-not $senha) { Set-Etapa "Informe a senha do ramal." (-1) $script:CorVinho; $script:TxtSenha.Focus(); return }

    $script:PodeFechar        = $false
    $script:BtnAcao.Enabled   = $false
    $script:BtnAcao.BackColor = $script:CorCinza
    $script:BtnAcao.Text      = "Aguarde..."
    $script:BtnFechar.Enabled = $false
    $script:TxtRamal.Enabled  = $false
    $script:TxtSenha.Enabled  = $false

    try {
        # ==================================================================
        # CAMINHO "JA INSTALADO"  <-- mexa aqui se quiser mudar esse fluxo
        # Se o GOnnect ja existe na maquina, NAO baixa e NAO reinstala:
        # a tela e a mesma e o script segue direto para regravar o
        # 01-sip.conf / 99-user.conf com o ramal informado.
        # Para forcar reinstalacao sempre, troque a condicao do if por
        # $false. Para nem tentar instalar, troque por $true.
        # ==================================================================
        Set-Etapa "Verificando se o GOnnect ja esta instalado..." 1
        if ((Test-GOnnectInstalado) -and (Test-Path -LiteralPath $script:ExeGOnnect)) {
            Set-Etapa "GOnnect ja instalado. Apenas atualizando o ramal." 2
        }
        else {
            Set-Etapa "Procurando a ultima versao com instalador win64..." 1
            $script:BtnAcao.Text = "Aguarde..."
            $tag = Install-GOnnect
            Set-Etapa "Versao $tag instalada para todos os usuarios." 2
        }

        Set-Etapa "Conferindo atalhos e inicializacao automatica..." 3
        New-AtalhosGOnnect

        Set-Etapa "Gravando o ramal no perfil de $($script:UsuarioAlvo.NomeUsuario)..." 4
        Write-ConfiguracaoRamal -LocalAppDataUsuario $script:UsuarioAlvo.LocalAppData `
                                -Ramal $ramal -Senha $senha

        # Tenta subir na sessao do usuario final (tarefa /IT). Se nao subir,
        # cai para Start-Process direto - o GOnnect precisa ficar aberto.
        Set-Etapa "Iniciando o GOnnect..." 5
        try {
            Start-ProcessoNaSessaoDoUsuario -NomeUsuario $script:UsuarioAlvo.NomeCompleto `
                                            -CaminhoExe $script:ExeGOnnect
        }
        catch { }

        if (-not (Get-Process -Name "gonnect" -ErrorAction SilentlyContinue)) {
            try {
                Start-Process -FilePath $script:ExeGOnnect `
                              -WorkingDirectory $script:PastaExe -WindowStyle Hidden
                Start-Sleep -Seconds 3
            }
            catch { }
        }

        if (-not (Get-Process -Name "gonnect" -ErrorAction SilentlyContinue)) {
            Set-Etapa "Configurado. O GOnnect abrira no proximo login do usuario." 5 $script:CorAmbar
            Start-Sleep -Milliseconds 1200
        }

        $script:Concluido  = $true
        $script:PodeFechar = $true
        Set-Etapa "Ramal $ramal configurado para $($script:UsuarioAlvo.NomeUsuario)." 6 $script:CorVerde
        $script:BtnAcao.Text      = "Concluido"
        $script:BtnFechar.Enabled = $true

        for ($i = 0; $i -lt 25; $i++) {
            Start-Sleep -Milliseconds 100
            [System.Windows.Forms.Application]::DoEvents()
        }
        $script:Form.Close()
    }
    catch {
        $script:PodeFechar        = $true
        Set-Etapa "Falha: $($_.Exception.Message)" (-1) $script:CorVinho
        $script:TxtRamal.Enabled  = $true
        $script:TxtSenha.Enabled  = $true
        $script:BtnAcao.Enabled   = $true
        $script:BtnAcao.BackColor = $script:CorAzul
        $script:BtnAcao.Text      = "Tentar novamente"
        $script:BtnFechar.Enabled = $true
    }
})

$Form.Add_Shown({
    try {
        $script:UsuarioAlvo = Get-UsuarioLogadoInfo
        $script:Contexto.Text         = "$env:COMPUTERNAME"
        $script:ContextoUsuario.Text  = "$($script:UsuarioAlvo.NomeCompleto)"
        $script:LblPerfil.Text = "Perfil de destino: $($script:UsuarioAlvo.PerfilPath)"

        # Mesma tela nos dois casos: so muda o texto do botao e do aviso.
        if ((Test-GOnnectInstalado) -and (Test-Path -LiteralPath $script:ExeGOnnect)) {
            $script:BtnAcao.Text = "Atualizar ramal"
            Set-Etapa "GOnnect ja instalado: o ramal informado sera apenas regravado." 0 $script:CorGrafite
        }

        $script:TxtRamal.Focus()
    }
    catch {
        # Sem usuario final identificado nao ha o que configurar: unico
        # caminho de saida vira o botao Fechar.
        Set-Etapa "$($_.Exception.Message)" (-1) $script:CorVinho
        $script:LblPerfil.Text    = "Faca login com o usuario final na maquina e rode de novo."
        $script:TxtRamal.Enabled  = $false
        $script:TxtSenha.Enabled  = $false
        $script:Concluido         = $true
        $script:PodeFechar        = $true
        $script:BtnAcao.Text      = "Fechar"
        $script:BtnAcao.BackColor = $script:CorGrafite
    }
})

$Form.ShowDialog() | Out-Null
$Form.Dispose()
