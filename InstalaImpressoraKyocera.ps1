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

    # Configurações Nativas (Frente/Verso, Cassete e Comum)
    Write-Host "[$IP] Configurando preferências de papel e Frente/Verso..." -ForegroundColor Cyan
    Set-PrintConfiguration -PrinterName "$NomeImpressora" -Duplexing TwoSidedLongEdge

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
