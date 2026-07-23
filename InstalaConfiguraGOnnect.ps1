#Instala e Configura SIP GOnnect
# ==========================================================================
# Este script foi ajustado para ser executado com uma conta de ADMINISTRADOR
# diferente do usuario final que vai efetivamente usar o GOnnect.
# Por isso, os caminhos de AppData NAO usam $env:LOCALAPPDATA (que aponta
# para o perfil do administrador), e sim o perfil do usuario logado
# interativamente na maquina, resolvido via Get-UsuarioLogadoAppDataLocal.
# ==========================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==========================================================================
# FUNCAO: Descobre o AppData\Local do usuario logado interativamente
# (independente de quem esta rodando o script)
# ==========================================================================
function Get-UsuarioLogadoInfo {
    # Descobre o usuario logado interativamente na sessao do console
    $usuarioLogado = (Get-CimInstance Win32_ComputerSystem).UserName

    if ([string]::IsNullOrEmpty($usuarioLogado)) {
        throw "Nao foi possivel identificar um usuario logado interativamente na maquina."
    }

    # UserName vem como DOMINIO\usuario ou MAQUINA\usuario - extrai so o nome
    $nomeUsuario = $usuarioLogado.Split('\')[-1]

    # Converte o nome da conta em SID
    $objUser = New-Object System.Security.Principal.NTAccount($usuarioLogado)
    $sid = $objUser.Translate([System.Security.Principal.SecurityIdentifier]).Value

    # Busca o caminho do perfil real desse SID no registro
    $chaveProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
    if (-not (Test-Path $chaveProfile)) {
        throw "Perfil do usuario $usuarioLogado nao encontrado no registro (SID: $sid)."
    }

    $caminhoPerfil = (Get-ItemProperty -Path $chaveProfile).ProfileImagePath
    $localAppData = Join-Path $caminhoPerfil "AppData\Local"

    return [PSCustomObject]@{
        NomeCompleto  = $usuarioLogado
        NomeUsuario   = $nomeUsuario
        SID           = $sid
        PerfilPath    = $caminhoPerfil
        LocalAppData  = $localAppData
    }
}

# Resolve uma vez no inicio do script e usa em tudo daqui pra frente
try {
    $UsuarioAlvo = Get-UsuarioLogadoInfo
    Write-Host "Usuario final identificado: $($UsuarioAlvo.NomeCompleto)" -ForegroundColor Cyan
    Write-Host "Perfil: $($UsuarioAlvo.PerfilPath)" -ForegroundColor DarkGray
}
catch {
    Write-Host "ERRO: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Nao e possivel continuar sem identificar o usuario final." -ForegroundColor Red
    return
}

# ==========================================================================
# FUNCAO: Abre a tela de configuracao do Ramal (Usuario/Senha) e grava o INI
# ==========================================================================
function Show-ConfiguracaoRamal {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LocalAppDataUsuario
    )

    # DEFINICAO DO CAMINHO EXATO (no perfil do USUARIO FINAL, nao do admin)
    $CaminhoDestino = Join-Path $LocalAppDataUsuario "gonnect\GOnnect\gonnect"
    $NomeArquivo = "01-sip.conf"
    $CaminhoCompleto = Join-Path $CaminhoDestino $NomeArquivo

    # FECHA O GONNECT CASO JA ESTEJA ABERTO
    # (Garante que ele libere a pasta e leia o novo arquivo ao reabrir)
    Stop-Process -Name "GOnnect" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    # CRIACAO DA INTERFACE GRAFICA (GUI)
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Configuracao de Ramal - GOnnect"
    $Form.Size = New-Object System.Drawing.Size(350,220)
    $Form.StartPosition = "CenterScreen"
    $Form.FormBorderStyle = "FixedDialog"
    $Form.MaximizeBox = $false
    $Form.MinimizeBox = $false
    $Form.TopMost = $true # Mantem a janela na frente

    $lblUsuario = New-Object System.Windows.Forms.Label
    $lblUsuario.Location = New-Object System.Drawing.Point(20,20)
    $lblUsuario.Size = New-Object System.Drawing.Size(100,20)
    $lblUsuario.Text = "Ramal (Usuario):"
    $Form.Controls.Add($lblUsuario)

    $txtUsuario = New-Object System.Windows.Forms.TextBox
    $txtUsuario.Location = New-Object System.Drawing.Point(130,17)
    $txtUsuario.Size = New-Object System.Drawing.Size(160,20)
    $Form.Controls.Add($txtUsuario)

    $lblSenha = New-Object System.Windows.Forms.Label
    $lblSenha.Location = New-Object System.Drawing.Point(20,60)
    $lblSenha.Size = New-Object System.Drawing.Size(100,20)
    $lblSenha.Text = "Senha do Ramal:"
    $Form.Controls.Add($lblSenha)

    $txtSenha = New-Object System.Windows.Forms.TextBox
    $txtSenha.Location = New-Object System.Drawing.Point(130,57)
    $txtSenha.Size = New-Object System.Drawing.Size(160,20)
    $txtSenha.PasswordChar = '*'
    $Form.Controls.Add($txtSenha)

    $btnSalvar = New-Object System.Windows.Forms.Button
    $btnSalvar.Location = New-Object System.Drawing.Point(100,110)
    $btnSalvar.Size = New-Object System.Drawing.Size(130,30)
    $btnSalvar.Text = "Salvar e Iniciar"
    $Form.Controls.Add($btnSalvar)

    # ACAO AO CLICAR NO BOTAO SALVAR
    $btnSalvar.Add_Click({
        $Ramal = $txtUsuario.Text.Trim()
        $Senha = $txtSenha.Text.Trim()

        if ([string]::IsNullOrEmpty($Ramal) -or [string]::IsNullOrEmpty($Senha)) {
            [System.Windows.Forms.MessageBox]::Show("Por favor, preencha o Ramal e a Senha para salvar!", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        try {
            # CRIA O DESTINO CASO NAO EXISTA
            if (-not (Test-Path -LiteralPath $CaminhoDestino)) {
                New-Item -ItemType Directory -Path $CaminhoDestino -Force | Out-Null
            }

            # Template do arquivo de configuracao
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

            # Salva ou substitui o arquivo com codificacao limpa (01-sip.conf)
            Set-Content -Path $CaminhoCompleto -Value $ConteudoINI -Force -Encoding UTF8

            # GERAR O ARQUIVO 99-USER.CONF
            $CaminhoUserConf = Join-Path $CaminhoDestino "99-user.conf"
            $ConteudoUserConf = @"
[generic]
showTrayDialog=true
noSyncSystemMute=false
showMainWindowOnStart=true
useOwnWindowDecoration=false
"@
            Set-Content -Path $CaminhoUserConf -Value $ConteudoUserConf -Force -Encoding UTF8

            # AJUSTA PERMISSOES PARA QUE O USUARIO FINAL (dono do perfil) TENHA
            # CONTROLE TOTAL, ja que o script roda com outra conta (admin)
            icacls $CaminhoCompleto /grant "Todos:(F)" | Out-Null
            icacls $CaminhoUserConf /grant "Todos:(F)" | Out-Null

            $caminhoExeGonnect = "C:\Program Files\GOnnect\bin\gonnect.exe"
            $pastaTrabalho = "C:\Program Files\GOnnect\bin"

            # 1. PROGRAMA O GONNECT PARA INICIAR NOS PROXIMOS REBOOTS E CRIA ATALHOS
            if (Test-Path -LiteralPath $caminhoExeGonnect) {
                $WshShell = New-Object -ComObject WScript.Shell

                # Atalho na pasta Startup de todos os usuários
                $caminhoStartup = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\GOnnect.lnk"
                $AtalhoStartup = $WshShell.CreateShortcut($caminhoStartup)
                $AtalhoStartup.TargetPath = $caminhoExeGonnect
                $AtalhoStartup.WorkingDirectory = $pastaTrabalho
                $AtalhoStartup.Save()

                # Atalho na Área de Trabalho de todos os usuários
                $caminhoDesktop = "$env:Public\Desktop\GOnnect.lnk"
                $AtalhoDesktop = $WshShell.CreateShortcut($caminhoDesktop)
                $AtalhoDesktop.TargetPath = $caminhoExeGonnect
                $AtalhoDesktop.WorkingDirectory = $pastaTrabalho
                $AtalhoDesktop.Save()
            }

            # 2. MENSAGEM DE SUCESSO E FECHAR TELA
            [System.Windows.Forms.MessageBox]::Show("Configuracao salva com sucesso! O GOnnect sera iniciado em seguida.", "Sucesso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)

            $Form.Close()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Erro ao criar pastas ou salvar o arquivo: $($_.Exception.Message)", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

    # Exibe a tela
    $Form.ShowDialog() | Out-Null
}

# ==========================================================================
# FUNCAO: Inicia um executavel DENTRO DA SESSAO do usuario final, mesmo
# que o script esteja rodando com a conta do administrador da empresa.
# Usa uma tarefa agendada temporaria com token interativo (/IT), que so
# funciona se o usuario alvo estiver de fato logado no console - o que
# e exatamente o nosso caso.
# ==========================================================================
function Start-ProcessoNaSessaoDoUsuario {
    param(
        [Parameter(Mandatory=$true)]
        [string]$NomeUsuario,
        [Parameter(Mandatory=$true)]
        [string]$CaminhoExe,
        [Parameter(Mandatory=$true)]
        [string]$PastaTrabalho
    )

    $nomeTarefa = "GOnnect-Start-Temp"
    $comando = "`"$CaminhoExe`""

    try {
        # Remove tarefa antiga com o mesmo nome, se existir (idempotente)
        schtasks /Delete /TN $nomeTarefa /F 2>$null | Out-Null

        # Cria a tarefa para rodar AGORA (ST = daqui 1 minuto), no contexto
        # do usuario logado, usando token interativo (nao pede senha)
        $horaExec = (Get-Date).AddMinutes(1).ToString("HH:mm")

        schtasks /Create /TN $nomeTarefa /TR $comando /SC ONCE /ST $horaExec `
                 /RU $NomeUsuario /IT /F | Out-Null

        schtasks /Run /TN $nomeTarefa | Out-Null

        # Aguarda um instante para o processo subir antes de limpar a tarefa
        Start-Sleep -Seconds 5
        schtasks /Delete /TN $nomeTarefa /F 2>$null | Out-Null

        Write-Host "GOnnect iniciado na sessao de $NomeUsuario." -ForegroundColor Green
    }
    catch {
        Write-Host "Nao foi possivel iniciar o GOnnect na sessao do usuario automaticamente." -ForegroundColor Yellow
        Write-Host "O atalho de Startup ja criado vai iniciar o programa no proximo login." -ForegroundColor Yellow
        Write-Host "Detalhe do erro: $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}

# ==========================================================================
# FLUXO PRINCIPAL: Instalacao (se necessario) + Configuracao do Ramal
# ==========================================================================

$resposta = Read-Host "Deseja instalar o SIP (Ramal)? [S/N]"

if ($resposta -match "^[Ss]") {
    Write-Host "--- Iniciando processo do GOnnect (SIP) ---" -ForegroundColor Cyan

    # VERIFICAR SE JA ESTA INSTALADO
    Write-Host "Verificando se o GOnnect ja esta instalado..."
    $jaInstalado = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                   Where-Object { $_.DisplayName -like "*GOnnect*" }

    if ($jaInstalado) {
        Write-Host "GOnnect ja esta instalado nesta maquina. Pulando instalacao." -ForegroundColor Green
    }
    else {
        Write-Host "Buscando a versao mais recente no GitHub..." -ForegroundColor Yellow
        try {
            # CONSULTAR A API DO GITHUB
            $urlApi = "https://api.github.com/repos/gonicus/gonnect/releases/latest"
            $respostaApi = Invoke-RestMethod -Uri $urlApi -UseBasicParsing -ErrorAction Stop

            $assetValido = $respostaApi.assets | Where-Object { $_.name -like "*win64.exe" } | Select-Object -First 1

            if (-not $assetValido) {
                Write-Host "Erro: Nao foi possivel localizar o arquivo win64.exe no GitHub." -ForegroundColor Red
                return
            }
            $urlDownload = $assetValido.browser_download_url
            $nomeDoArquivo = $assetValido.name
            $destinoLocal = "$env:TEMP\$nomeDoArquivo"

            # DOWNLOAD
            Write-Host "Baixando $nomeDoArquivo..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri $urlDownload -OutFile $destinoLocal -UseBasicParsing -ErrorAction Stop

            # INSTALACAO SILENCIOSA (ALL USERS)
            Write-Host "Iniciando instalacao silenciosa para todos os usuarios..." -ForegroundColor Green
            Start-Process -FilePath $destinoLocal -ArgumentList "/S" -Wait -NoNewWindow

            # CONFIGURAR INICIALIZACAO AUTOMATICA E ATALHOS (MAQUINA TODA)
            $caminhoExeGonnect = "C:\Program Files\GOnnect\bin\gonnect.exe"
            $pastaTrabalho = "C:\Program Files\GOnnect\bin"

            if (Test-Path -LiteralPath $caminhoExeGonnect) {
                Write-Host "Criando atalhos na Area de Trabalho e na pasta de Inicializacao..." -ForegroundColor Yellow

                $WshShell = New-Object -ComObject WScript.Shell

                # Criar Atalho na pasta Startup
                $caminhoStartup = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\GOnnect.lnk"
                $AtalhoStartup = $WshShell.CreateShortcut($caminhoStartup)
                $AtalhoStartup.TargetPath = $caminhoExeGonnect
                $AtalhoStartup.WorkingDirectory = $pastaTrabalho
                $AtalhoStartup.Save()

                # Criar Atalho na Área de Trabalho
                $caminhoDesktop = "$env:Public\Desktop\GOnnect.lnk"
                $AtalhoDesktop = $WshShell.CreateShortcut($caminhoDesktop)
                $AtalhoDesktop.TargetPath = $caminhoExeGonnect
                $AtalhoDesktop.WorkingDirectory = $pastaTrabalho
                $AtalhoDesktop.Save()

                Write-Host "Atalhos e inicializacao automatica configurados com sucesso!" -ForegroundColor Green
            } else {
                Write-Host "Aviso: O executavel nao foi encontrado no caminho ($caminhoExeGonnect). Inicializacao automatica e atalho nao configurados." -ForegroundColor DarkGray
            }

            # LIMPEZA
            Write-Host "Limpando arquivo temporario..." -ForegroundColor Yellow
            Remove-Item -Path $destinoLocal -Force

            Write-Host "Instalacao concluida com sucesso!" -ForegroundColor Green
        }
        catch {
            Write-Host "Erro durante o processo do GOnnect: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "--------------------------------------------------------"
            return
        }
    }

    # ACOPLA A CONFIGURACAO DO RAMAL LOGO APOS GARANTIR A INSTALACAO
    $caminhoExeGonnect = "C:\Program Files\GOnnect\bin\gonnect.exe"
    $pastaTrabalho = "C:\Program Files\GOnnect\bin"
    if (Test-Path -LiteralPath $caminhoExeGonnect) {
        Write-Host "Abrindo tela de configuracao do Ramal..." -ForegroundColor Cyan
        Show-ConfiguracaoRamal -LocalAppDataUsuario $UsuarioAlvo.LocalAppData

        # INICIA O GONNECT NA SESSAO DO USUARIO FINAL (nao na do admin)
        Write-Host "Iniciando o GOnnect na sessao do usuario final..." -ForegroundColor Green
        Start-ProcessoNaSessaoDoUsuario -NomeUsuario $UsuarioAlvo.NomeCompleto `
                                        -CaminhoExe $caminhoExeGonnect `
                                        -PastaTrabalho $pastaTrabalho

    } else {
        Write-Host "GOnnect nao foi encontrado apos a instalacao. Configuracao do Ramal nao sera exibida." -ForegroundColor Red
    }
}
else {
    Write-Host "Instalacao do SIP (Ramal) pulada pelo usuario." -ForegroundColor Yellow
}

Write-Host "--------------------------------------------------------"
