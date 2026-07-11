Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 1. DEFINIÇÃO DO CAMINHO EXATO
$CaminhoDestino = Join-Path $env:LOCALAPPDATA "gonnect\GOnnect\gonnect"
$NomeArquivo = "01-sip.conf"
$CaminhoCompleto = Join-Path $CaminhoDestino $NomeArquivo

# 2. FECHA O GONNECT CASO ELE JÁ ESTEJA ABERTO
# (Garante que ele libere a pasta e leia o novo arquivo ao reabrir)
Stop-Process -Name "GOnnect" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# 3. CRIAÇÃO DA INTERFACE GRÁFICA (GUI)
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "Configuracao de Ramal - GOnnect"
$Form.Size = New-Object System.Drawing.Size(350,220)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox = $false
$Form.MinimizeBox = $false
$Form.TopMost = $true # Mantém a janela na frente

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

# 4. AÇÃO AO CLICAR NO BOTÃO SALVAR
$btnSalvar.Add_Click({
    $Ramal = $txtUsuario.Text.Trim()
    $Senha = $txtSenha.Text.Trim()

    if ([string]::IsNullOrEmpty($Ramal) -or [string]::IsNullOrEmpty($Senha)) {
        [System.Windows.Forms.MessageBox]::Show("Por favor, preencha o Ramal e a Senha para salvar!", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    try {
        # CRIA O DESTINO CASO NÃO EXISTA: O -Force cria toda a árvore de pastas de uma vez só
        if (-not (Test-Path -LiteralPath $CaminhoDestino)) {
            New-Item -ItemType Directory -Path $CaminhoDestino -Force | Out-Null
        }

        # Template do arquivo de configuração
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

        # Salva ou substitui o arquivo com codificação limpa
        Set-Content -Path $CaminhoCompleto -Value $ConteudoINI -Force -Encoding UTF8

        # 5. PROGRAMA O GONNECT PARA INICIAR NOS PRÓXIMOS REBOOTS (HKCU)
        $caminhoExeGonnect = "C:\Program Files\GOnnect\GOnnect.exe"
        if (Test-Path -LiteralPath $caminhoExeGonnect) {
            $caminhoRegistroRun = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
            New-ItemProperty -Path $caminhoRegistroRun -Name "GOnnect" -Value "`"$caminhoExeGonnect`"" -PropertyType String -Force | Out-Null
        }

        [System.Windows.Forms.MessageBox]::Show("Configuracao salva com sucesso!", "Sucesso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        
        # Abre o GOnnect agora já logado com as novas credenciais
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
