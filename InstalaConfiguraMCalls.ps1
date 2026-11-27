<#
    Instala e configura o M Calls (Hexagon Call, telefone SIP) - Machadao Corp
    No lugar do GOnnect. Tela unica: ao confirmar, instala para o usuario
    logado, grava as preferencias da empresa e abre o M Calls na tela dele,
    ja no cadastro do ramal (o ramal, o servidor e a senha sao digitados la, e
    a senha vai para o Gerenciador de Credenciais do usuario).

    Preferencias da empresa: qualidade da voz ligada, gravacao das ligacoes
    por 30 dias, toque Colmeia em todos os alto-falantes no volume maximo,
    sons modernos, trazer para a frente, abrir com o sistema e as opcoes
    ocultas (ocultaConfig). Maquina da TI (caixa marcada): so o visual
    M Calls, com todas as opcoes na tela.

    O script roda com conta de ADMINISTRADOR diferente do usuario final.
    Por isso os caminhos de AppData NAO usam $env:LOCALAPPDATA: o perfil do
    usuario logado interativamente e resolvido via Get-UsuarioLogadoInfo.
    NAO alterar essa parte. O instalador do Hexagon Call e por usuario (vai
    para o AppData\Local\Programs de quem roda): por isso ele roda DENTRO da
    sessao do usuario final, por tarefa agendada, e nao como o admin.

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

# ============================================================ ELEVACAO
# Estar na conta de administrador NAO basta: sem token elevado o Windows
# nega acesso ao perfil de outro usuario. Reabre elevado.
$identidade = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal  = New-Object System.Security.Principal.WindowsPrincipal($identidade)
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # $args e variavel automatica: nao pode ser atribuida.
    $caminhoScript = $PSCommandPath
    if (-not $caminhoScript) { $caminhoScript = $MyInvocation.MyCommand.Path }

    try {
        if (-not $caminhoScript) { throw "script sem caminho em disco (rodando de selecao no ISE)" }
        $argumentos = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-WindowStyle", "Hidden",
            "-File", "`"$caminhoScript`""
        )
        Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $argumentos `
                      -Verb RunAs -WindowStyle Hidden
    }
    catch {
        [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
        [System.Windows.Forms.MessageBox]::Show(
            "Este instalador precisa ser executado como administrador." + [Environment]::NewLine +
            "Abra o PowerShell com 'Executar como administrador' e rode o arquivo .ps1 de novo.",
            "M Calls", "OK", "Warning") | Out-Null
    }
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# O ISE mantem variaveis entre execucoes: zera o estado logo no inicio.
$script:Concluido   = $false
$script:PodeFechar  = $true
$script:UsuarioAlvo = $null

# ============================================================ PALETA
$script:CorPreto    = [System.Drawing.ColorTranslator]::FromHtml("#12161C")
$script:CorAzul     = [System.Drawing.ColorTranslator]::FromHtml("#1A5FB4")
$script:CorAzulH    = [System.Drawing.ColorTranslator]::FromHtml("#154C90")
$script:CorCinza    = [System.Drawing.ColorTranslator]::FromHtml("#A9B2BD")
$script:CorGrafite  = [System.Drawing.ColorTranslator]::FromHtml("#5B6672")
$script:CorGrafiteH = [System.Drawing.ColorTranslator]::FromHtml("#4B5560")
$script:CorClaro    = [System.Drawing.ColorTranslator]::FromHtml("#9AA4AF")
$script:CorEyebrow  = [System.Drawing.ColorTranslator]::FromHtml("#7C93AE")
$script:CorCredito  = [System.Drawing.ColorTranslator]::FromHtml("#B4BCC5")
$script:CorVerde    = [System.Drawing.ColorTranslator]::FromHtml("#0A6F66")
$script:CorAmbar    = [System.Drawing.ColorTranslator]::FromHtml("#8A5A00")
$script:CorVinho    = [System.Drawing.ColorTranslator]::FromHtml("#C01C28")

$script:Repositorio = "JMoratelli/HexagonCall"
$script:Servidor    = "voip.redejcm.com.br"
# Onde o instalador fica enquanto roda: a sessao do usuario final precisa
# ler, e o TEMP do admin nao e dele.
$script:PastaDownload = Join-Path $env:ProgramData "MachadaoCorp\MCalls"

# As preferencias, chave a chave, como o app le (TOML). Com a caixa da TI
# marcada, so o visual: o ocultaConfig = 0 destrava uma maquina que ja teve
# as da empresa.
$script:PrefsEmpresa = [ordered]@{
    flavor           = '"mcalls"'
    cancelarEco      = 'true'
    reduzirRuido     = 'true'
    vozNitida        = 'true'
    gravar           = 'true'
    guardarGravacoes = '30'
    toque            = '"colmeia"'
    toqueEmTodos     = 'true'
    toqueNoMaximo    = 'true'
    sons             = '"modernos"'
    trazerParaFrente = 'true'
    abrirComOSistema = 'true'
    ocultaConfig     = '1'
}
$script:PrefsTI = [ordered]@{
    flavor       = '"mcalls"'
    ocultaConfig = '0'
}

# ============================================================ FUNCOES
# Descobre o perfil do usuario logado interativamente,
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

        # Contas de servico nao tem perfil util
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

# Pasta do shell do usuario final pelo registro dele (HKU\<SID>): com OneDrive
# ou redirecionamento de pasta no dominio, <perfil>\Desktop ou
# <perfil>\AppData\Roaming existem mas NAO sao as de verdade.
function Get-PastaShell {
    param(
        [Parameter(Mandatory=$true)]$Usuario,
        [Parameter(Mandatory=$true)][string]$Nome,     # "Desktop", "Startup", "AppData"...
        [Parameter(Mandatory=$true)][string]$Padrao    # relativo ao perfil
    )

    if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -ErrorAction SilentlyContinue | Out-Null
    }

    $chave = "HKU:\$($Usuario.SID)\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
    $valor = $null
    try { $valor = (Get-ItemProperty -Path $chave -Name $Nome -ErrorAction Stop).$Nome } catch { }

    if (-not $valor) {
        $chave = "HKU:\$($Usuario.SID)\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"
        try { $valor = (Get-ItemProperty -Path $chave -Name $Nome -ErrorAction Stop).$Nome } catch { }
    }

    if ($valor) {
        # %USERPROFILE% aqui e o do usuario final, nao o do admin
        $valor = $valor.Replace('%USERPROFILE%', $Usuario.PerfilPath)
        $valor = [Environment]::ExpandEnvironmentVariables($valor)
        if (Test-Path -LiteralPath $valor) { return $valor }
    }

    return (Join-Path $Usuario.PerfilPath $Padrao)
}

function Get-ExeMCalls {
    param([Parameter(Mandatory=$true)]$Usuario)
    return (Join-Path $Usuario.LocalAppData "Programs\HexagonCall\HexagonCall.exe")
}

# A pasta de dados do app no perfil do usuario final: o Hexagon Call usa o
# AppData\Roaming (%APPDATA%\hexagon-call).
function Get-PastaDadosMCalls {
    param([Parameter(Mandatory=$true)]$Usuario)
    $roaming = Get-PastaShell -Usuario $Usuario -Nome "AppData" -Padrao "AppData\Roaming"
    return (Join-Path $roaming "hexagon-call")
}

# O GOnnect, que o M Calls substitui, sai do login e dos atalhos do usuario:
# os dois no mesmo ramal disputam o registro (o PBX guarda um aparelho so por
# ramal). O programa fica instalado.
function Disable-GOnnect {
    param([Parameter(Mandatory=$true)]$Usuario)

    Stop-Process -Name "gonnect" -Force -ErrorAction SilentlyContinue

    if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -ErrorAction SilentlyContinue | Out-Null
    }
    $run = "HKU:\$($Usuario.SID)\Software\Microsoft\Windows\CurrentVersion\Run"
    if (Test-Path $run) {
        $valores = Get-ItemProperty -Path $run -ErrorAction SilentlyContinue
        if ($valores) {
            foreach ($p in $valores.PSObject.Properties) {
                if ($p.Name -like 'PS*') { continue }
                if ("$($p.Value)" -match '(?i)gonnect\.exe') {
                    Remove-ItemProperty -Path $run -Name $p.Name -ErrorAction SilentlyContinue
                }
            }
        }
    }

    $atalhos = @(
        (Join-Path (Get-PastaShell -Usuario $Usuario -Nome "Startup" `
            -Padrao "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup") "GOnnect.lnk"),
        (Join-Path (Get-PastaShell -Usuario $Usuario -Nome "Desktop" -Padrao "Desktop") "GOnnect.lnk"),
        (Join-Path $Usuario.PerfilPath "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\GOnnect.lnk"),
        (Join-Path "$env:Public\Desktop" "GOnnect.lnk"),
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\GOnnect.lnk"
    )
    foreach ($a in $atalhos) {
        if (Test-Path -LiteralPath $a) { Remove-Item -LiteralPath $a -Force -ErrorAction SilentlyContinue }
    }

    # O proprio GOnnect recria a entrada do login se a opcao dele estiver ligada.
    $pasta = Join-Path $Usuario.LocalAppData "gonnect\GOnnect\gonnect"
    foreach ($conf in @("01-sip.conf", "99-user.conf")) {
        $c = Join-Path $pasta $conf
        if (Test-Path -LiteralPath $c) {
            $texto = [System.IO.File]::ReadAllText($c)
            if ($texto -match '(?m)^autostart=true') {
                $texto = $texto -replace '(?m)^autostart=true', 'autostart=false'
                [System.IO.File]::WriteAllText($c, $texto, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }
}

# Grava as chaves no preferencias.toml do usuario final, uma a uma, sem mexer
# nas outras (o microfone escolhido, por exemplo) nem nos comentarios. O app
# completa as que faltam com o padrao ao abrir.
function Write-PreferenciasMCalls {
    param(
        [Parameter(Mandatory=$true)]$Usuario,
        [Parameter(Mandatory=$true)][System.Collections.Specialized.OrderedDictionary]$Chaves
    )

    $pasta   = Get-PastaDadosMCalls -Usuario $Usuario
    $arquivo = Join-Path $pasta "preferencias.toml"
    if (-not (Test-Path -LiteralPath $pasta)) {
        New-Item -ItemType Directory -Path $pasta -Force -ErrorAction Stop | Out-Null
    }

    $linhas = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $arquivo) {
        # ReadAllText entende o BOM (UTF-8 ou UTF-16) e, sem ele, le UTF-8.
        $texto = [System.IO.File]::ReadAllText($arquivo)
        foreach ($l in ($texto -split "\r?\n")) { $linhas.Add($l) }
        while ($linhas.Count -gt 0 -and $linhas[$linhas.Count - 1] -eq "") { $linhas.RemoveAt($linhas.Count - 1) }
    }

    foreach ($chave in $Chaves.Keys) {
        $nova = "$chave = $($Chaves[$chave])"
        # O app le "marca" como o flavor de antes: com os dois, a chave repete.
        $nomes = @($chave)
        if ($chave -eq "flavor") { $nomes += "marca" }
        $achou = @()
        for ($i = 0; $i -lt $linhas.Count; $i++) {
            if ($linhas[$i] -match '^\s*([A-Za-z]+)\s*=' -and $nomes -contains $matches[1]) { $achou += $i }
        }
        if ($achou.Count -gt 0) {
            $linhas[$achou[0]] = $nova
            for ($k = $achou.Count - 1; $k -ge 1; $k--) { $linhas.RemoveAt($achou[$k]) }
        }
        else {
            $linhas.Add($nova)
        }
    }

    $novo = ($linhas -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($arquivo, $novo, (New-Object System.Text.UTF8Encoding($false)))

    # O script roda como admin: o dono do perfil precisa gravar a pasta (o
    # app regrava o arquivo por troca de nome).
    icacls "$pasta" /grant "*$($Usuario.SID):(OI)(CI)F" 2>$null | Out-Null

    # Confere o que gravou antes de dizer que deu certo
    $lido = [System.IO.File]::ReadAllText($arquivo)
    foreach ($chave in $Chaves.Keys) {
        $esperado = "(?m)^" + [regex]::Escape("$chave = $($Chaves[$chave])") + "\s*$"
        if ($lido -notmatch $esperado) { throw "o preferencias.toml gravado nao tem $chave" }
    }
    return $arquivo
}

# A release mais nova (nem rascunho nem previa) que traga o instalador do
# Windows e o SHA256SUMS.txt, como o atualizador do app procura.
function Get-ReleaseMCalls {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $cabecalhos = @{ 'User-Agent' = 'Machadao-Instalador' }
    $releases = Invoke-RestMethod -UseBasicParsing -ErrorAction Stop -Headers $cabecalhos -TimeoutSec 45 `
                -Uri "https://api.github.com/repos/$script:Repositorio/releases?per_page=30"
    foreach ($rel in $releases) {
        if ($rel.draft -or $rel.prerelease) { continue }
        $setup = $rel.assets | Where-Object { $_.name -like "HexagonCallSetup-*.exe" } | Select-Object -First 1
        $somas = $rel.assets | Where-Object { $_.name -eq "SHA256SUMS.txt" } | Select-Object -First 1
        if ($setup -and $somas) {
            return [PSCustomObject]@{ Tag = $rel.tag_name; Setup = $setup; Somas = $somas }
        }
    }
    throw "nenhuma release do M Calls traz o instalador do Windows"
}

# Baixa o instalador e confere o sha256 pelo SHA256SUMS.txt da release.
function Save-InstaladorMCalls {
    param([Parameter(Mandatory=$true)]$Release)

    $cabecalhos = @{ 'User-Agent' = 'Machadao-Instalador' }
    # A barra de progresso do Invoke-* deixa o download absurdamente lento e
    # e o que faz a tela parecer travada. Desliga durante a operacao.
    $progAnterior = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        if (-not (Test-Path -LiteralPath $script:PastaDownload)) {
            New-Item -ItemType Directory -Path $script:PastaDownload -Force -ErrorAction Stop | Out-Null
        }
        $destino = Join-Path $script:PastaDownload $Release.Setup.name
        $somas   = Join-Path $script:PastaDownload "SHA256SUMS.txt"
        Invoke-WebRequest -Uri $Release.Somas.browser_download_url -OutFile $somas `
            -UseBasicParsing -Headers $cabecalhos -TimeoutSec 60 -ErrorAction Stop
        Invoke-WebRequest -Uri $Release.Setup.browser_download_url -OutFile $destino `
            -UseBasicParsing -Headers $cabecalhos -TimeoutSec 600 -ErrorAction Stop

        $esperado = $null
        foreach ($linha in [System.IO.File]::ReadAllLines($somas)) {
            $campos = $linha.Trim() -split '\s+'
            if ($campos.Count -eq 2 -and $campos[1].TrimStart('*') -eq $Release.Setup.name) { $esperado = $campos[0] }
        }
        Remove-Item -LiteralPath $somas -Force -ErrorAction SilentlyContinue
        if (-not $esperado) { throw "o SHA256SUMS.txt da release nao tem o $($Release.Setup.name)" }
        $obtido = (Get-FileHash -LiteralPath $destino -Algorithm SHA256).Hash
        if ($obtido -ne $esperado.ToUpper()) {
            Remove-Item -LiteralPath $destino -Force -ErrorAction SilentlyContinue
            throw "o instalador baixado nao confere com o SHA256SUMS.txt (download corrompido?)"
        }
        return $destino
    }
    finally { $ProgressPreference = $progAnterior }
}

# Roda um programa DENTRO DA SESSAO do usuario final: tarefa agendada
# temporaria, interativa, com o token dele (so funciona com ele logado, que e
# o caso aqui). Pelos cmdlets, sem as aspas do schtasks /TR.
function Start-NaSessaoDoUsuario {
    param(
        [Parameter(Mandatory=$true)]$Usuario,
        [Parameter(Mandatory=$true)][string]$Exe,
        [string]$Argumentos,
        [Parameter(Mandatory=$true)][string]$NomeTarefa
    )

    Unregister-ScheduledTask -TaskName $NomeTarefa -Confirm:$false -ErrorAction SilentlyContinue
    if ($Argumentos) { $acao = New-ScheduledTaskAction -Execute $Exe -Argument $Argumentos }
    else             { $acao = New-ScheduledTaskAction -Execute $Exe }
    $quem   = New-ScheduledTaskPrincipal -UserId $Usuario.NomeCompleto -LogonType Interactive -RunLevel Limited
    # Sem limite de tempo: a tarefa que abre o app fica "rodando" com ele.
    $ajuste = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
              -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName $NomeTarefa -Action $acao -Principal $quem -Settings $ajuste `
                           -Force -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $NomeTarefa -ErrorAction Stop
}

function Remove-TarefaTemporaria {
    param([Parameter(Mandatory=$true)][string]$NomeTarefa)
    Unregister-ScheduledTask -TaskName $NomeTarefa -Confirm:$false -ErrorAction SilentlyContinue
}

# Instala na sessao do usuario final, em silencio. O instalador abre o app
# sozinho no fim (o [Run] da instalacao silenciosa); aqui so se espera.
function Install-MCalls {
    param(
        [Parameter(Mandatory=$true)]$Usuario,
        [Parameter(Mandatory=$true)][string]$Instalador
    )

    $tarefa = "MCalls-Instala-Temp"
    $exe    = Get-ExeMCalls -Usuario $Usuario
    Start-NaSessaoDoUsuario -Usuario $Usuario -Exe $Instalador `
        -Argumentos "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -NomeTarefa $tarefa
    try {
        $limite = (Get-Date).AddMinutes(5)
        do {
            for ($i = 0; $i -lt 10; $i++) {
                Start-Sleep -Milliseconds 200
                [System.Windows.Forms.Application]::DoEvents()
            }
            $estado = (Get-ScheduledTask -TaskName $tarefa -ErrorAction SilentlyContinue).State
            $rodando = ("$estado" -eq "Running") -or [bool](Get-Process -Name "HexagonCallSetup*" -ErrorAction SilentlyContinue)
        } while ($rodando -and (Get-Date) -lt $limite)
        if ($rodando) { throw "a instalacao nao terminou em 5 minutos" }
        # 267011 (0x41303): a tarefa nunca rodou, o usuario nao esta logado.
        $info = Get-ScheduledTaskInfo -TaskName $tarefa -ErrorAction SilentlyContinue
    }
    finally { Remove-TarefaTemporaria -NomeTarefa $tarefa }

    Remove-Item -LiteralPath $Instalador -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $exe)) {
        if ($info -and $info.LastTaskResult -eq 267011) {
            throw "a instalacao nao rodou na sessao de $($Usuario.NomeUsuario): ele precisa estar logado na maquina"
        }
        throw "o instalador terminou, mas o M Calls nao esta em $exe"
    }
}

# Abrir com o sistema pela chave Run do proprio usuario, como o app grava
# (o nome "Hexagon Call" e o mesmo que o desinstalador tira). O app regrava
# ao abrir, por causa do abrirComOSistema; aqui vale ja no proximo login.
function Set-AutoStartMCalls {
    param([Parameter(Mandatory=$true)]$Usuario)

    if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -ErrorAction SilentlyContinue | Out-Null
    }
    $run = "HKU:\$($Usuario.SID)\Software\Microsoft\Windows\CurrentVersion\Run"
    if (-not (Test-Path $run)) { New-Item -Path $run -Force -ErrorAction Stop | Out-Null }
    $valor = "`"$(Get-ExeMCalls -Usuario $Usuario)`" --bandeja"
    Set-ItemProperty -Path $run -Name "Hexagon Call" -Value $valor -ErrorAction Stop

    $lido = (Get-ItemProperty -Path $run -Name "Hexagon Call" -ErrorAction Stop)."Hexagon Call"
    if ($lido -ne $valor) { throw "chave Run nao gravou" }
}

function Test-ContaCadastrada {
    param([Parameter(Mandatory=$true)]$Usuario)
    $contas = Join-Path (Get-PastaDadosMCalls -Usuario $Usuario) "contas.toml"
    if (-not (Test-Path -LiteralPath $contas)) { return $false }
    return ([System.IO.File]::ReadAllText($contas) -match '(?m)^\s*\[\[conta\]\]')
}

# ============================================================ JANELA
$LARG = 660
$script:Form          = New-Object System.Windows.Forms.Form
$Form                 = $script:Form
$Form.Text            = "M Calls (SIP) - Machadao Corp"
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
$titulo.Text      = "Instalacao do M Calls"
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
# y: ajuda 122-166, TI 178-202, apoio 204-222, perfil 234-254,
#    mensagem 262-306, barra 312-318, botoes 372-422
$ajuda           = New-Object System.Windows.Forms.Label
$ajuda.Text      = "O M Calls sera instalado para o usuario logado e, no fim, abre na tela dele: " +
                   "cadastre o ramal, o servidor $script:Servidor e a senha."
$ajuda.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$ajuda.ForeColor = $script:CorGrafite
$ajuda.Location  = New-Object System.Drawing.Point(36, 122)
$ajuda.Size      = New-Object System.Drawing.Size(($LARG - 70), 44)
$Form.Controls.Add($ajuda)

$script:ChkTI           = New-Object System.Windows.Forms.CheckBox
$script:ChkTI.Text      = "Maquina da TI"
$script:ChkTI.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$script:ChkTI.ForeColor = $script:CorGrafite
$script:ChkTI.Location  = New-Object System.Drawing.Point(36, 178)
$script:ChkTI.Size      = New-Object System.Drawing.Size(($LARG - 70), 24)
$script:ChkTI.Checked   = $false
$Form.Controls.Add($script:ChkTI)

$script:LblTI           = New-Object System.Windows.Forms.Label
$script:LblTI.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$script:LblTI.ForeColor = $script:CorClaro
$script:LblTI.Location  = New-Object System.Drawing.Point(54, 204)
$script:LblTI.Size      = New-Object System.Drawing.Size(($LARG - 88), 18)
$Form.Controls.Add($script:LblTI)

function Update-TextoTI {
    if ($script:ChkTI.Checked) {
        $script:LblTI.Text = "Marcada: so o visual M Calls, com todas as opcoes na tela."
    }
    else {
        $script:LblTI.Text = "Desmarcada: as opcoes da empresa, ocultas na tela (padrao)."
    }
}
Update-TextoTI
$script:ChkTI.Add_CheckedChanged({ Update-TextoTI })

$script:LblPerfil           = New-Object System.Windows.Forms.Label
$script:LblPerfil.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$script:LblPerfil.ForeColor = $script:CorClaro
$script:LblPerfil.Location  = New-Object System.Drawing.Point(36, 234)
$script:LblPerfil.Size      = New-Object System.Drawing.Size(($LARG - 70), 20)
$Form.Controls.Add($script:LblPerfil)

# ============================================================ MENSAGEM
$script:Msg           = New-Object System.Windows.Forms.Label
$script:Msg.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$script:Msg.ForeColor = $script:CorGrafite
$script:Msg.Location  = New-Object System.Drawing.Point(36, 262)
$script:Msg.Size      = New-Object System.Drawing.Size(($LARG - 70), 44)
$Form.Controls.Add($script:Msg)

$script:Barra          = New-Object System.Windows.Forms.ProgressBar
$script:Barra.Location = New-Object System.Drawing.Point(36, 312)
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
$script:BtnAcao.FlatAppearance.MouseOverBackColor = $script:CorAzulH
$script:BtnAcao.FlatAppearance.MouseDownBackColor = $script:CorAzulH
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
$script:BtnFechar.FlatAppearance.MouseOverBackColor = $script:CorGrafiteH
$script:BtnFechar.FlatAppearance.MouseDownBackColor = $script:CorGrafiteH
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

    $script:PodeFechar        = $false
    $script:BtnAcao.Enabled   = $false
    $script:BtnAcao.BackColor = $script:CorCinza
    $script:BtnAcao.Text      = "Aguarde..."
    $script:BtnFechar.Enabled = $false
    $script:ChkTI.Enabled     = $false

    $u   = $script:UsuarioAlvo
    $ti  = $script:ChkTI.Checked
    $exe = Get-ExeMCalls -Usuario $u

    try {
        Set-Etapa "Tirando o GOnnect do login de $($u.NomeUsuario)..." 1
        Disable-GOnnect -Usuario $u

        Set-Etapa "Gravando as preferencias do M Calls..." 2
        if ($ti) { $prefs = $script:PrefsTI } else { $prefs = $script:PrefsEmpresa }
        Write-PreferenciasMCalls -Usuario $u -Chaves $prefs | Out-Null

        # ==================================================================
        # CAMINHO "JA INSTALADO": nao baixa nem reinstala (o app se atualiza
        # sozinho); so reabre, para as preferencias novas valerem.
        # ==================================================================
        if (Test-Path -LiteralPath $exe) {
            Set-Etapa "M Calls ja instalado. Reabrindo com as preferencias novas..." 4
            Stop-Process -Name "HexagonCall" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            Start-NaSessaoDoUsuario -Usuario $u -Exe $exe -NomeTarefa "MCalls-Abre-Temp"
            Start-Sleep -Seconds 3
            Remove-TarefaTemporaria -NomeTarefa "MCalls-Abre-Temp"
        }
        else {
            Set-Etapa "Consultando o GitHub e baixando o instalador..." 3
            $release = Get-ReleaseMCalls
            $instalador = Save-InstaladorMCalls -Release $release

            Set-Etapa "Instalando a versao $($release.Tag) para $($u.NomeUsuario) (na sessao dele)..." 4
            Install-MCalls -Usuario $u -Instalador $instalador
        }

        $falhas = New-Object System.Collections.Generic.List[string]
        if (-not $ti) {
            Set-Etapa "Ligando o abrir com o sistema..." 5
            try { Set-AutoStartMCalls -Usuario $u } catch { $falhas.Add("abrir com o sistema") }
        }

        # O app tem de ficar aberto na tela do usuario (o cadastro do ramal).
        for ($i = 0; $i -lt 25 -and -not (Get-Process -Name "HexagonCall" -ErrorAction SilentlyContinue); $i++) {
            Start-Sleep -Milliseconds 200
            [System.Windows.Forms.Application]::DoEvents()
        }
        if (-not (Get-Process -Name "HexagonCall" -ErrorAction SilentlyContinue)) {
            $falhas.Add("abrir o M Calls agora (abra pelo atalho da area de trabalho)")
        }

        $script:Concluido  = $true
        $script:PodeFechar = $true
        if (Test-ContaCadastrada -Usuario $u) {
            $fim = "M Calls configurado para $($u.NomeUsuario), com o ramal que ja estava cadastrado."
        }
        else {
            $fim = "M Calls instalado para $($u.NomeUsuario). Na tela dele: cadastre o ramal, o servidor $script:Servidor e a senha."
        }
        if ($falhas.Count -gt 0) {
            Set-Etapa ("$fim Nao foi possivel: " + ($falhas -join ", ") + ".") 6 $script:CorAmbar
        }
        else {
            Set-Etapa $fim 6 $script:CorVerde
        }
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
        $script:ChkTI.Enabled     = $true
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
        if (Test-Path -LiteralPath (Get-ExeMCalls -Usuario $script:UsuarioAlvo)) {
            $script:BtnAcao.Text = "Reconfigurar"
            Set-Etapa "M Calls ja instalado: as preferencias serao regravadas e o app reaberto." 0 $script:CorGrafite
        }

        $script:BtnAcao.Focus()
    }
    catch {
        # Sem usuario final identificado nao ha o que configurar: unico
        # caminho de saida vira o botao Fechar.
        Set-Etapa "$($_.Exception.Message)" (-1) $script:CorVinho
        $script:LblPerfil.Text    = "Faca login com o usuario final na maquina e rode de novo."
        $script:ChkTI.Enabled     = $false
        $script:Concluido         = $true
        $script:PodeFechar        = $true
        $script:BtnAcao.Text      = "Fechar"
        $script:BtnAcao.BackColor = $script:CorGrafite
    }
})

$Form.ShowDialog() | Out-Null
$Form.Dispose()
