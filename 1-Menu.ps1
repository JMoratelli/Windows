#Requires -Version 5.1

# ==========================================================================================
#  PAINEL DE CONFIGURACAO DOS SCRIPTS AUXILIARES
#  -> Para adicionar um novo script, so acrescente uma linha no array abaixo,
#     seguindo o padrao: Legenda = "Nome que aparece no menu"; Url = "link do .ps1"
# ==========================================================================================
$ScriptsMenu = @(
    [PSCustomObject]@{ Legenda = "Instala Ventoy Atualizado";              Url = "https://raw.githubusercontent.com/JMoratelli/Windows/refs/heads/main/InstalaVentoy.ps1" }
    [PSCustomObject]@{ Legenda = "Instala e configura SIP";                Url = "https://raw.githubusercontent.com/JMoratelli/Windows/refs/heads/main/InstalaConfiguraGOnnect.ps1" }
    [PSCustomObject]@{ Legenda = "Instala e configura Impressora";         Url = "https://raw.githubusercontent.com/JMoratelli/Windows/refs/heads/main/InstalaImpressoraKyocera.ps1" }
    [PSCustomObject]@{ Legenda = "Instala e configura Zanthus";            Url = "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PostInstallPDV.ps1" }
    [PSCustomObject]@{ Legenda = "Refaz Instalação de pacotes Windows";    Url = "https://raw.githubusercontent.com/JMoratelli/Windows/refs/heads/main/InstalaWindows.ps1" }
    # <<< Adicione novas linhas aqui, sempre no mesmo padrao >>>
)

$LarguraMenu = 72

# ==========================================================================================
#  FUNCOES AUXILIARES
# ==========================================================================================

function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Linha {
    param([string]$Caractere = "-", [string]$Cor = "DarkGray")
    Write-Host ($Caractere * $LarguraMenu) -ForegroundColor $Cor
}

function Write-Centralizado {
    param([string]$Texto, [string]$Cor = "White")
    $espacos = [Math]::Max(0, [Math]::Floor(($LarguraMenu - $Texto.Length) / 2))
    Write-Host ((" " * $espacos) + $Texto) -ForegroundColor $Cor
}

function Show-Header {
    $so = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem

    $ipLocal = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
               Where-Object { $_.InterfaceAlias -notmatch "Loopback" -and $_.IPAddress -notlike "169.254*" } |
               Select-Object -First 1 -ExpandProperty IPAddress

    if (-not $ipLocal) { $ipLocal = "N/A" }

    $uptime = (Get-Date) - $so.LastBootUpTime
    $statusAdmin = if (Test-IsAdmin) { "SIM" } else { "NAO" }
    $corAdmin    = if (Test-IsAdmin) { "Green" } else { "Yellow" }

    Write-Linha "=" "DarkCyan"
    Write-Centralizado "PAINEL DE SCRIPTS @JJMoratelli - $($env:COMPUTERNAME)" "Cyan"
    Write-Linha "=" "DarkCyan"
    Write-Host (" Maquina.......: {0}"           -f $env:COMPUTERNAME)
    Write-Host (" Usuario.......: {0}\{1}"       -f $env:USERDOMAIN, $env:USERNAME)
    Write-Host (" Dominio/Grupo.: {0}"            -f $cs.Domain)
    Write-Host (" Sistema.......: {0} ({1})"      -f $so.Caption, $so.OSArchitecture)
    Write-Host (" Versao/Build..: {0} (Build {1})" -f $so.Version, $so.BuildNumber)
    Write-Host (" IP Local......: {0}"            -f $ipLocal)
    Write-Host (" Ligado ha.....: {0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes)
    Write-Host (" PowerShell....: {0}"            -f $PSVersionTable.PSVersion)
    Write-Host (" Sessao Admin..: {0}" -f $statusAdmin) -ForegroundColor $corAdmin
    Write-Linha "=" "DarkCyan"
    Write-Host ""
}

function Show-Menu {
    Write-Centralizado "SCRIPTS DISPONIVEIS" "Yellow"
    Write-Linha "-" "DarkGray"

    if ($ScriptsMenu.Count -eq 0) {
        Write-Host "  Nenhum script configurado no painel." -ForegroundColor DarkGray
    }
    else {
        for ($i = 0; $i -lt $ScriptsMenu.Count; $i++) {
            Write-Host ("  [{0,2}] {1}" -f ($i + 1), $ScriptsMenu[$i].Legenda)
        }
    }

    Write-Linha "-" "DarkGray"
    Write-Host "  [ 0] Sair" -ForegroundColor Red
    Write-Host ""
}

function Invoke-ScriptRemoto {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Legenda
    )

    Write-Host ""
    Write-Host "Executando: $Legenda" -ForegroundColor Green
    Write-Host "Fonte.....: $Url" -ForegroundColor DarkGray
    Write-Host ""

    # Comando que sera executado dentro da sessao elevada, direto da web
    $comandoRemoto = "irm '$Url' | iex"

    $argumentos = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-NoExit",
        "-Command", $comandoRemoto
    )

    try {
        if (Test-IsAdmin) {
            # Sessao atual ja e admin: abre nova janela sem precisar de novo prompt UAC
            Start-Process -FilePath "powershell.exe" -ArgumentList $argumentos -Wait
        }
        else {
            # Forca elevacao via UAC, mantendo a sessao atual do menu aberta
            Start-Process -FilePath "powershell.exe" -ArgumentList $argumentos -Verb RunAs -Wait
        }
    }
    catch {
        Write-Host "Erro ao executar o script remoto: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Execucao finalizada. Pressione qualquer tecla para voltar ao menu..." -ForegroundColor DarkGray
    [void][System.Console]::ReadKey($true)
}

# ==========================================================================================
#  LOOP PRINCIPAL DO MENU
# ==========================================================================================
do {
    Clear-Host
    Show-Header
    Show-Menu

    $opcao = Read-Host "Selecione uma opcao"

    if ($opcao -eq "0") {
        Write-Host "Encerrando..." -ForegroundColor Yellow
        break
    }

    $indice = 0
    if ([int]::TryParse($opcao, [ref]$indice) -and $indice -ge 1 -and $indice -le $ScriptsMenu.Count) {
        $itemSelecionado = $ScriptsMenu[$indice - 1]
        Invoke-ScriptRemoto -Url $itemSelecionado.Url -Legenda $itemSelecionado.Legenda
    }
    else {
        Write-Host "Opcao invalida!" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }

} while ($true)
