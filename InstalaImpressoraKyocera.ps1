# ====================================================================
# 1. PERGUNTAR IP E NOME DA IMPRESSORA (Interação com o Usuário)
# ====================================================================
Clear-Host
Write-Host "=== INSTALADOR AUTOMÁTICO DE IMPRESSORAS KYOCERA ===" -ForegroundColor Green
Write-Host ""

$IP = Read-Host "Digite o endereço IP da impressora (ex: 192.168.8.29)"
if (-not $IP) { Write-Error "O IP não pode ser vazio."; return }

$NomeImpressora = Read-Host "Digite o nome de exibição para a impressora (ex: KY-RH-LJ06)"
if (-not $NomeImpressora) { Write-Error "O nome da impressora não pode ser vazio."; return }

# URL do pacote de drivers e pastas locais
$DriverUrl = "http://192.168.12.223/uploads/InstaladorWindows/KyoceraDrivers.7z"
$TempDir = "C:\KyoceraDrivers"
$ZipPath = "$TempDir\drivers.7z"

# 2. CRIAR DIRETÓRIO TEMPORÁRIO SEGURO
if (!(Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir | Out-Null }

# 3. FAZER DOWNLOAD DO PACOTE DE DRIVERS (Apenas se não existir)
if (-not (Test-Path $ZipPath)) {
    Write-Host "[$IP] Baixando o pacote de drivers..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $DriverUrl -OutFile $ZipPath
} else {
    Write-Host "[$IP] O arquivo comprimido de drivers já existe localmente. Pulando download!" -ForegroundColor Yellow
}

# 4. EXTRAIR O ARQUIVO .7z (Apenas se não extraído) 
$InfFiles = Get-ChildItem -Path $TempDir -Filter "OEMSETUP.INF" -Recurse -ErrorAction SilentlyContinue 
if (-not $InfFiles) {
    Write-Host "[$IP] Extraindo os drivers..." -ForegroundColor Cyan
    if (Test-Path "C:\Program Files\7-Zip\7z.exe") {
        & "C:\Program Files\7-Zip\7z.exe" x $ZipPath "-o$TempDir" -y | Out-Null
    } else {
        7z x $ZipPath "-o$TempDir" -y | Out-Null
    }
    $InfFiles = Get-ChildItem -Path $TempDir -Filter "OEMSETUP.INF" -Recurse 
} else {
    Write-Host "[$IP] Drivers já extraídos anteriormente. Pulando extração!" -ForegroundColor Yellow
}

# 5. CONSULTA SNMP (Para identificar o hardware real na rede)
Write-Host "[$IP] Consultando o modelo do equipamento via SNMP..." -ForegroundColor Cyan
$SNMP = New-Object -ComObject olePrn.OleSNMP
$SNMP.Open($IP, "public")
$ModeloCru = $SNMP.Get(".1.3.6.1.2.1.25.3.2.1.3.1")
$SNMP.Close()

if (-not $ModeloCru) {
    Write-Error "[$IP] Não foi possível obter o modelo via SNMP. Verifique a conexão de rede com a impressora."
    return
}
Write-Host "[$IP] Modelo de hardware detectado: $ModeloCru" -ForegroundColor Green

# 6. ISOLAR O CODENOME DO MODELO (Ex: Extrai "M3655idn" de "ECOSYS M3655idn") 
$CoreModel = $ModeloCru -split ' ' | Where-Object { $_ -match '\d' } | Select-Object -First 1
if (-not $CoreModel) { $CoreModel = $ModeloCru }

# 7. VARREDURA CIRÚRGICA DO OEMSETUP.INF 
$InfPath = $null
$DriverName = $null

foreach ($file in $InfFiles) {
    $Lines = Get-Content $file.FullName
    foreach ($line in $Lines) {
        # Procura a linha correspondente ao modelo dentro do INF 
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
    Write-Error "[$IP] Erro: Não foi possível localizar o driver para o modelo '$CoreModel' no arquivo OEMSETUP.INF." 
    return
}

Write-Host "[$IP] Driver correspondente: $DriverName" -ForegroundColor Green

# 8. CRIAR A PORTA TCP/IP
$PortName = "IP_$IP"
if (-not (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue)) {
    Write-Host "[$IP] Criando a porta de impressão ($PortName)..." -ForegroundColor Cyan
    Add-PrinterPort -Name $PortName -PrinterHostAddress $IP
}

# 9. IGNORAR POP-UP DE SEGURANÇA (Instalação 100% silenciosa)
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

# 10. HOMOLOGAR PACOTE NO DRIVERSTORE
Write-Host "[$IP] Homologando o pacote de driver no Windows..." -ForegroundColor Cyan
pnputil.exe /add-driver $InfPath | Out-Null

# 11. REGISTRAR DRIVER NO REPOSITÓRIO DE IMPRESSÃO (PrintUI) 
Write-Host "[$IP] Registrando o driver no Spooler do sistema..." -ForegroundColor Cyan
$PrintUIArgs = "printui.dll,PrintUIEntry /ia /m `"$DriverName`" /f `"$InfPath`"" 
$Process = Start-Process rundll32.exe -ArgumentList $PrintUIArgs -Wait -PassThru -NoNewWindow 

if ($Process.ExitCode -ne 0) {
    Write-Error "[$IP] Falha ao registrar o driver através do subsistema PrintUI." 
    return
}

# 12. CRIAR A IMPRESSORA DEFINITIVAMENTE (Usa o nome escolhido por você)
Write-Host "[$IP] Criando a impressora '$NomeImpressora' no Windows..." -ForegroundColor Cyan
Add-Printer -Name "$NomeImpressora" -DriverName $DriverName -PortName $PortName

# ====================================================================
# 13. CONFIGURAÇÕES PADRÃO NATIVAS (Duplex, Cassete e Mídia Comum)
# ====================================================================
Write-Host "[$IP] Configurando preferências de papel e Frente/Verso..." -ForegroundColor Cyan

# Ativar Frente e Verso automático
Set-PrintConfiguration -PrinterName "$NomeImpressora" -Duplexing TwoSidedLongEdge

# Manipular o XML interno da impressora criada
$Config = Get-PrintConfiguration -PrinterName "$NomeImpressora"
[xml]$Ticket = $Config.PrintTicketXML

$nsm = New-Object System.Xml.XmlNamespaceManager($Ticket.NameTable)
$nsm.AddNamespace("psf", "http://schemas.microsoft.com/windows/2003/08/printing/printschemaframework")

# Forçar a origem para "psk:Cassette" (o termo correto que você descobriu)
$BinNode = $Ticket.SelectSingleNode("//psf:Feature[@name='psk:PageInputBin']/psf:Option", $nsm)
if ($BinNode) {
    $BinNode.SetAttribute("name", "psk:Cassette")
} else {
    $FragmentBin = $Ticket.CreateDocumentFragment()
    $FragmentBin.InnerXml = '<psf:Feature name="psk:PageInputBin"><psf:Option name="psk:Cassette" /></psf:Feature>'
    $Ticket.DocumentElement.AppendChild($FragmentBin) | Out-Null
}

# Forçar a mídia para Papel Comum ("psk:Plain")
$MediaNode = $Ticket.SelectSingleNode("//psf:Feature[@name='psk:PageMediaType']/psf:Option", $nsm)
if ($MediaNode) {
    $MediaNode.SetAttribute("name", "psk:Plain")
} else {
    $FragmentMedia = $Ticket.CreateDocumentFragment()
    $FragmentMedia.InnerXml = '<psf:Feature name="psk:PageMediaType"><psf:Option name="psk:Plain" /></psf:Feature>'
    $Ticket.DocumentElement.AppendChild($FragmentMedia) | Out-Null
}

# Salvar as alterações de volta na impressora
Set-PrintConfiguration -PrinterName "$NomeImpressora" -PrintTicketXML $Ticket.OuterXml

Write-Host ""
Write-Host "🎉 SUCESSO: A impressora '$NomeImpressora' foi instalada no IP $IP com Duplex e Cassete configurados!" -ForegroundColor Green
