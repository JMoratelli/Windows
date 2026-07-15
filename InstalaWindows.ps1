#Refaz Passos de Instalação Windows
# Este script busca os instaladores nas unidades de disco e inicia a instalação
# de forma sequencial, garantindo que o usuário veja e interaja com os prompts de cada instalador.
# Instala BitDefender================================================================================================
$nomeDoProcesso = "EPSecurityConsole" 
Write-Host "Verificando se o processo '$nomeDoProcesso' esta ativo..." -ForegroundColor Cyan
$processoAtivo = Get-Process -Name $nomeDoProcesso -ErrorAction SilentlyContinue

if ($processoAtivo) {
    Write-Host "BitDefender ja instalado e em execucao. Pulando instalacao." -ForegroundColor Green
}
else {
    Write-Host "Iniciando download via HTTP..." -ForegroundColor Yellow  
    $baseUrl = "http://192.168.12.223/uploads/InstaladorWindows/"
    
    # Define a pasta Downloads do usuario
    $pastaDestino = Join-Path $env:USERPROFILE "Downloads"
    
    # GARANTIA: Se a pasta Downloads ainda não existir, ele cria!
    if (-not (Test-Path -LiteralPath $pastaDestino)) {
        New-Item -ItemType Directory -Path $pastaDestino -Force | Out-Null
    }
    
    try {
        $paginaWeb = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing -ErrorAction Stop
        
        $todasAsPalavras = $paginaWeb.Content -split '["''<>\s]'
        $arquivoExeNome = $todasAsPalavras | Where-Object { $_ -like "setupdownloader_*.exe" } | Select-Object -First 1
        
        if ($arquivoExeNome) {
            $nomeLimpoParaSalvar = [uri]::UnescapeDataString($arquivoExeNome)
            Write-Host "Arquivo encontrado: $nomeLimpoParaSalvar" -ForegroundColor Green
        } else {
            Write-Host "Falha: Nenhum instalador do Bitdefender encontrado no servidor." -ForegroundColor Red
            return
        }
    } 
    catch {
        Write-Host "Erro ao conectar no servidor HTTP: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # Constroi os caminhos
    $urlDownload = "${baseUrl}${arquivoExeNome}"
    $caminhoExeLocal = Join-Path $pastaDestino $nomeLimpoParaSalvar
    
    Write-Host "Baixando o instalador para a pasta Downloads..." -ForegroundColor Cyan
    
    # Bloco isolado só para o DOWNLOAD - AGORA USANDO .NET PURO (WebClient)
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($urlDownload, $caminhoExeLocal)
        Write-Host "Download salvo com sucesso!" -ForegroundColor Green
    }
    catch {
        Write-Host "ERRO NO DOWNLOAD: $($_.Exception.Message)" -ForegroundColor Red
        return 
    }

    # Bloco isolado só para a EXECUÇÃO
    try {
        if (Test-Path -LiteralPath $caminhoExeLocal) {
            Write-Host "Iniciando instalacao..." -ForegroundColor Green
            
            # Vamos entrar na pasta Downloads e chamar via CMD para blindar contra o bug dos colchetes
            Set-Location -LiteralPath $pastaDestino
            $comandoExecucao = "/c `"`"$nomeLimpoParaSalvar`"`""
            Start-Process -FilePath "cmd.exe" -ArgumentList $comandoExecucao -Wait -NoNewWindow
            
            Write-Host "Instalacao concluida!" -ForegroundColor Green
        } else {
            Write-Host "ERRO: O arquivo sumiu ou nao foi encontrado na pasta Downloads." -ForegroundColor Red
        }    
    }
    catch {
        Write-Host "ERRO NA EXECUÇÃO: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # Limpeza
    try {
        Write-Host "Limpando instalador da pasta Downloads..." -ForegroundColor Yellow
        Remove-Item -LiteralPath $caminhoExeLocal -Force
        Write-Host "Processo finalizado!" -ForegroundColor Green
    }
    catch {
        Write-Host "Aviso: O instalador ainda esta na pasta Downloads." -ForegroundColor DarkGray
    }
}
#Fim Instala Bit
#Instala Pacote Ninite
Write-Host "--- Instalando Ninite ---" -ForegroundColor Cyan

$url = "http://192.168.12.223/uploads/InstaladorWindows/ninite.exe"
$destino = "$env:TEMP\ninite.exe"

try {
    Write-Host "Baixando o Ninite..."
    Invoke-WebRequest -Uri $url -OutFile $destino -UseBasicParsing
    
    Write-Host "Executando..."
    Start-Process -FilePath $destino -Wait -NoNewWindow
    
    Write-Host "Limpando arquivo temporario..."
    Remove-Item -Path $destino -Force
    
    Write-Host "Ninite instalado com sucesso!" -ForegroundColor Green
} 
catch {
    Write-Host "Erro durante o processo do Ninite: $($_.Exception.Message)" -ForegroundColor Red
}
#Fim Instala Ninite

# Instala UVNC
Write-Host "--- Verificando Instalacao do UltraVNC ---" -ForegroundColor Cyan

$pastaVnc = "C:\Program Files\uvnc bvba\UltraVNC"
$exeVnc = Join-Path $pastaVnc "winvnc.exe"

if (Test-Path -LiteralPath $exeVnc) {
    Write-Host "UltraVNC ja instalado nesta maquina. Pulando instalacao." -ForegroundColor Green
}
else {
    Write-Host "UltraVNC nao encontrado. Baixando instalador..." -ForegroundColor Yellow

    $urlVnc = "http://192.168.12.223/uploads/InstaladorWindows/ultravnc.msi"
    $destinoVnc = "$env:TEMP\ultravnc.msi"

    try {
        Invoke-WebRequest -Uri $urlVnc -OutFile $destinoVnc -UseBasicParsing -ErrorAction Stop
        
        Write-Host "Abrindo instalador do UltraVNC. Faça a configuracao manual..." -ForegroundColor Cyan
        Write-Host "(O script continuara automaticamente quando voce fechar o instalador)" -ForegroundColor Yellow
        
        # Abre o MSI normalmente (sem /qn) e aguarda o término (-Wait)
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$destinoVnc`"" -Wait -NoNewWindow
        
        if (Test-Path -LiteralPath $exeVnc) {
            Write-Host "Instalacao do UltraVNC concluida com sucesso!" -ForegroundColor Green
        } else {
            Write-Host "Aviso: A instalacao foi cancelada ou instalada em outro diretorio." -ForegroundColor Red
        }
        
        # Limpa o arquivo MSI baixado
        Remove-Item -Path $destinoVnc -Force -ErrorAction SilentlyContinue
    } 
    catch {
        Write-Host "Erro durante o processo do UltraVNC: $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host "--------------------------------------------------------"
#FimInstalaUltraVNC

#Atualiza Winget Sources
winget source update

# Instala OnlyOffice
winget install -e --id ONLYOFFICE.DesktopEditors --silent --scope machine --accept-package-agreements --accept-source-agreements

winget install -e --id Skillbrains.Lightshot --silent --scope machine --accept-package-agreements --accept-source-agreements


Write-Host "Processo de verificação e instalação de todos os softwares concluído."

#ConfiguraSIPGonnect
# 1. PERGUNTA INICIAL
$resposta = Read-Host "Deseja instalar o SIP (Ramal)? [S/N]"

# Correção: Removido o "-clear" que causava o erro de sintaxe
if ($resposta -match "^[Ss]") {
    Write-Host "--- Iniciando processo do GOnnect (SIP) ---" -ForegroundColor Cyan

    # 2. VERIFICAR SE JÁ ESTÁ INSTALADO
    Write-Host "Verificando se o GOnnect ja esta instalado..."
    $jaInstalado = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | 
                   Where-Object { $_.DisplayName -like "*GOnnect*" }

    if ($jaInstalado) {
        Write-Host "GOnnect ja esta instalado nesta maquina. Pulando processo." -ForegroundColor Green
    } 
    else {
        Write-Host "Buscando a versao mais recente no GitHub..." -ForegroundColor Yellow

        try {
            # 3. CONSULTAR A API DO GITHUB
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

            # 4. DOWNLOAD
            Write-Host "Baixando $nomeDoArquivo..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri $urlDownload -OutFile $destinoLocal -UseBasicParsing -ErrorAction Stop
            
            # 5. INSTALAÇÃO SILENCIOSA (ALL USERS)
            Write-Host "Iniciando instalacao silenciosa para todos os usuarios..." -ForegroundColor Green
            Start-Process -FilePath $destinoLocal -ArgumentList "/S" -Wait -NoNewWindow
            
            # 6. CONFIGURAR INICIALIZAÇÃO AUTOMÁTICA (MÁQUINA TODA)
            $caminhoExeGonnect = "C:\Program Files\GOnnect\bin\gonnect.exe"
            
            if (Test-Path -LiteralPath $caminhoExeGonnect) {
                Write-Host "Configurando para iniciar automaticamente com o computador..." -ForegroundColor Yellow
                
                $caminhoRegistroRun = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
                New-ItemProperty -Path $caminhoRegistroRun -Name "GOnnect" -Value "`"$caminhoExeGonnect`"" -PropertyType String -Force | Out-Null
                
                Write-Host "Inicializacao automatica configurada com sucesso!" -ForegroundColor Green
            } else {
                Write-Host "Aviso: O executavel nao foi encontrado no caminho padrao. Inicializacao automatica nao configurada." -ForegroundColor DarkGray
            }

            # 7. LIMPEZA
            Write-Host "Limpando arquivo temporario..." -ForegroundColor Yellow
            Remove-Item -Path $destinoLocal -Force
            
            Write-Host "Processo concluido com sucesso!" -ForegroundColor Green
        } 
        catch {
            Write-Host "Erro durante o processo do GOnnect: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} else {
    Write-Host "Instalacao do SIP (Ramal) pulada pelo usuario." -ForegroundColor Yellow
}
Write-Host "--------------------------------------------------------"
#Fim Instala Gonnect SIP

#Configura impressora
$Pergunta = Read-Host "Deseja instalar as impressoras? (S/N)"

if ($Pergunta -match '^[Ss]') {
    # ====================================================================
    # PREPARAÇÃO INICIAL (Executado apenas uma vez no início)
    # ====================================================================
    Clear-Host
    Write-Host "=== INICIALIZANDO REPOSITÓRIO DE DRIVERS KYOCERA ===" -ForegroundColor Cyan

    $DriverUrl = "http://192.168.12.223/uploads/InstaladorWindows/KyoceraDrivers.7z"
    $TempDir = "C:\KyoceraDrivers"
    $ZipPath = "$TempDir\drivers.7z"

    # Criar diretório temporário seguro
    if (!(Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir | Out-Null }

    # Fazer download (Apenas se não existir)
    if (-not (Test-Path $ZipPath)) {
        Write-Host "Baixando o pacote de drivers..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $DriverUrl -OutFile $ZipPath
    }

    # Extrair os drivers (Apenas se não extraído)
    $InfFiles = Get-ChildItem -Path $TempDir -Filter "OEMSETUP.INF" -Recurse -ErrorAction SilentlyContinue
    if (-not $InfFiles) {
        Write-Host "Extraindo os drivers..." -ForegroundColor Cyan
        if (Test-Path "C:\Program Files\7-Zip\7z.exe") {
            & "C:\Program Files\7-Zip\7z.exe" x $ZipPath "-o$TempDir" -y | Out-Null
        } else {
            7z x $ZipPath "-o$TempDir" -y | Out-Null
        }
        $InfFiles = Get-ChildItem -Path $TempDir -Filter "OEMSETUP.INF" -Recurse
    }

    # ====================================================================
    # LAÇO DE REPETIÇÃO (Para adicionar múltiplas impressoras)
    # ====================================================================
    do {
        Clear-Host
        Write-Host "=== INSTALADOR AUTOMÁTICO DE IMPRESSORAS KYOCERA ===" -ForegroundColor Green
        Write-Host ""

        # Perguntar o IP
        $IP = Read-Host "Digite o endereço IP da impressora (ex: 192.168.8.29)"
        if (-not $IP) { 
            Write-Error "O IP não pode ser vazio."
            $Continuar = Read-Host "Deseja tentar novamente? (S/N)"
            continue 
        }

        # Perguntar o Nome
        $NomeImpressora = Read-Host "Digite o nome de exibição para a impressora (ex: Kyocera Faturamento)"
        if (-not $NomeImpressora) { 
            Write-Error "O nome da impressora não pode ser vazio."
            $Continuar = Read-Host "Deseja tentar novamente? (S/N)"
            continue 
        }

        # Consulta SNMP
        Write-Host "[$IP] Consultando o modelo do equipamento via SNMP..." -ForegroundColor Cyan
        $SNMP = New-Object -ComObject olePrn.OleSNMP
        $SNMP.Open($IP, "public")
        $ModeloCru = $SNMP.Get(".1.3.6.1.2.1.25.3.2.1.3.1")
        $SNMP.Close()

        if (-not $ModeloCru) {
            Write-Error "[$IP] Não foi possível obter o modelo via SNMP. Verifique a rede da impressora."
            $Continuar = Read-Host "Deseja tentar outra impressora? (S/N)"
            continue
        }
        Write-Host "[$IP] Hardware detectado: $ModeloCru" -ForegroundColor Green

        # Isolar codenome numérico
        $CoreModel = $ModeloCru -split ' ' | Where-Object { $_ -match '\d' } | Select-Object -First 1
        if (-not $CoreModel) { $CoreModel = $ModeloCru }

        # Varredura do INF
        $InfPath = $null
        $DriverName = $null
        foreach ($file in $InfFiles) {
            $Lines = Get-Content $file.FullName
            foreach ($line in $Lines) {
                if ($line -match '^"([^"]+)"\s*=\s*([^,]+)') {
                    $PossivelDriver = $Matches[1].Trim()
                    $PossivelSecao = $Matches[2].Trim()
                    if ($PossivelDriver -like "*$CoreModel*" -or $PossivelSecao -like "*$CoreModel*") {
                        $DriverName = $PossivelDriver
                        $InfPath = $file.FullName
                        break
                    }
                }
            }
            if ($DriverName) { break }
        }

        if (-not $InfPath -or -not $DriverName) {
            Write-Error "[$IP] Driver para o modelo '$CoreModel' não localizado no arquivo INF."
            $Continuar = Read-Host "Deseja tentar outra impressora? (S/N)"
            continue
        }

        # Criar Porta
        $PortName = "IP_$IP"
        if (-not (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue)) {
            Write-Host "[$IP] Criando a porta de impressão ($PortName)..." -ForegroundColor Cyan
            Add-PrinterPort -Name $PortName -PrinterHostAddress $IP
        }

        # Certificado de segurança
        $InfDirectory = Split-Path $InfPath
        $CatFile = Get-ChildItem -Path $InfDirectory -Filter "*.cat" | Select-Object -First 1
        if ($CatFile) {
            $Cert = (Get-AuthenticodeSignature $CatFile.FullName).SignerCertificate
            if ($Cert) {
                $Store = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPublisher", "LocalMachine")
                $Store.Open("ReadWrite")
                $Store.Add($Cert)
                $Store.Close()
            }
        }

        # Injetar DriverStore
        Write-Host "[$IP] Homologando o pacote de driver no Windows..." -ForegroundColor Cyan
        pnputil.exe /add-driver $InfPath | Out-Null

        # Registrar Spooler via PrintUI
        Write-Host "[$IP] Registrando o driver no Spooler do sistema..." -ForegroundColor Cyan
        $PrintUIArgs = "printui.dll,PrintUIEntry /ia /m `"$DriverName`" /f `"$InfPath`""
        $Process = Start-Process rundll32.exe -ArgumentList $PrintUIArgs -Wait -PassThru -NoNewWindow
        if ($Process.ExitCode -ne 0) {
            Write-Error "[$IP] Falha ao registrar o driver via PrintUI."
            $Continuar = Read-Host "Deseja tentar outra impressora? (S/N)"
            continue
        }

        # Criar Impressora
        Write-Host "[$IP] Criando a impressora '$NomeImpressora' no Windows..." -ForegroundColor Cyan
        Add-Printer -Name "$NomeImpressora" -DriverName $DriverName -PortName $PortName

        # Configurações Nativas (Frente/Verso, Cassete e Comum) - Desativado
        #Write-Host "[$IP] Configurando preferências de papel e Frente/Verso..." -ForegroundColor Cyan
        #Set-PrintConfiguration -PrinterName "$NomeImpressora" -Duplexing TwoSidedLongEdge

        $Config = Get-PrintConfiguration -PrinterName "$NomeImpressora"
        [xml]$Ticket = $Config.PrintTicketXML
        $nsm = New-Object System.Xml.XmlNamespaceManager($Ticket.NameTable)
        $nsm.AddNamespace("psf", "http://schemas.microsoft.com/windows/2003/08/printing/printschemaframework")

        # Forçar Cassete
        $BinNode = $Ticket.SelectSingleNode("//psf:Feature[@name='psk:PageInputBin']/psf:Option", $nsm)
        if ($BinNode) { $BinNode.SetAttribute("name", "psk:Cassette") }
        else {
            $FragmentBin = $Ticket.CreateDocumentFragment()
            $FragmentBin.InnerXml = '<psf:Feature name="psk:PageInputBin"><psf:Option name="psk:Cassette" /></psf:Feature>'
            $Ticket.DocumentElement.AppendChild($FragmentBin) | Out-Null
        }

        # Forçar Mídia Comum
        $MediaNode = $Ticket.SelectSingleNode("//psf:Feature[@name='psk:PageMediaType']/psf:Option", $nsm)
        if ($MediaNode) { $MediaNode.SetAttribute("name", "psk:Plain") }
        else {
            $FragmentMedia = $Ticket.CreateDocumentFragment()
            $FragmentMedia.InnerXml = '<psf:Feature name="psk:PageMediaType"><psf:Option name="psk:Plain" /></psf:Feature>'
            $Ticket.DocumentElement.AppendChild($FragmentMedia) | Out-Null
        }
        Set-PrintConfiguration -PrinterName "$NomeImpressora" -PrintTicketXML $Ticket.OuterXml

        Write-Host ""
        Write-Host "🎉 SUCESSO: A impressora '$NomeImpressora' foi configurada!" -ForegroundColor Green
        Write-Host ""

        # Pergunta de Controle para o Laço
        $Continuar = Read-Host "Deseja adicionar uma nova impressora? (S/N)"

    } while ($Continuar -match '^[Ss]')

    Write-Host ""
    Write-Host "Impressora(s) Instaladas, script feito por @JJMorateli ;) Até mais!" -ForegroundColor Cyan
}
#FimConfiguraImpressora
