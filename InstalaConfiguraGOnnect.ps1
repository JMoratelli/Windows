Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==========================================================================
# FUNCAO: Abre a tela de configuracao do Ramal (Usuario/Senha) e grava o INI
# ==========================================================================
function Show-ConfiguracaoRamal {

    # DEFINICAO DO CAMINHO EXATO
    $CaminhoDestino = Join-Path $env:LOCALAPPDATA "gonnect\GOnnect\gonnect"
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
userUri=sip:$Ramal@192.168.12.39

## IP do Servidor SIP (Registrar)
registrarUri=sip:192.168.12.39

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

            # Salva ou substitui o arquivo com codificacao limpa
            Set-Content -Path $CaminhoCompleto -Value $ConteudoINI -Force -Encoding UTF8

            # PROGRAMA O GONNECT PARA INICIAR NOS PROXIMOS REBOOTS (HKCU)
            $caminhoExeGonnect = "C:\Program Files\GOnnect\GOnnect.exe"
            if (Test-Path -LiteralPath $caminhoExeGonnect) {
                $caminhoRegistroRun = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
                New-ItemProperty -Path $caminhoRegistroRun -Name "GOnnect" -Value "`"$caminhoExeGonnect`"" -PropertyType String -Force | Out-Null
            }

            [System.Windows.Forms.MessageBox]::Show("Configuracao salva com sucesso!", "Sucesso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)

            # Abre o GOnnect ja logado com as novas credenciais
            if (Test-Path -LiteralPath $caminhoExeGonnect) {
                Start-Process -FilePath $caminhoExeGonnect -NoNewWindow
            }

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

            # CONFIGURAR INICIALIZACAO AUTOMATICA (MAQUINA TODA)
            $caminhoExeGonnect = "C:\Program Files\GOnnect\GOnnect.exe"

            if (Test-Path -LiteralPath $caminhoExeGonnect) {
                Write-Host "Configurando para iniciar automaticamente com o computador..." -ForegroundColor Yellow

                $caminhoRegistroRun = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
                New-ItemProperty -Path $caminhoRegistroRun -Name "GOnnect" -Value "`"$caminhoExeGonnect`"" -PropertyType String -Force | Out-Null

                Write-Host "Inicializacao automatica configurada com sucesso!" -ForegroundColor Green
            } else {
                Write-Host "Aviso: O executavel nao foi encontrado no caminho padrao. Inicializacao automatica nao configurada." -ForegroundColor DarkGray
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
    $caminhoExeGonnect = "C:\Program Files\Gonnect\bin\gonnect.exe"
    if (Test-Path -LiteralPath $caminhoExeGonnect) {
        Write-Host "Abrindo tela de configuracao do Ramal..." -ForegroundColor Cyan
        Show-ConfiguracaoRamal
    } else {
        Write-Host "GOnnect nao foi encontrado apos a instalacao. Configuracao do Ramal nao sera exibida." -ForegroundColor Red
    }
}
else {
    Write-Host "Instalacao do SIP (Ramal) pulada pelo usuario." -ForegroundColor Yellow
}

Write-Host "--------------------------------------------------------"
