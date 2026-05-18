# ====================================================================
# CONFIGURA\UffffffffO INICIAL (Altere apenas o IP para escalar)
# ====================================================================
$IP = "192.168.8.29"
$DriverUrl = "http://192.168.12.223/uploads/InstaladorWindows/KyoceraDrivers.7z"

# Pasta na raiz do C: para livre acesso do servi\Uffffffffde Spooler (SYSTEM)
$TempDir = "C:\KyoceraDrivers"
$ZipPath = "$TempDir\drivers.7z"

# 1. CRIAR DIRET\UffffffffIO TEMPOR\UffffffffIO SEGURO
if (!(Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir | Out-Null }

# 2. FAZER DOWNLOAD DO PACOTE DE DRIVERS (Apenas se n\Uffffffffexistir)
if (-not (Test-Path $ZipPath)) {
    Write-Host "[$IP] Baixando o pacote de drivers..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $DriverUrl -OutFile $ZipPath
} else {
    Write-Host "[$IP] O arquivo comprimido j\Uffffffffxiste localmente. Pulando download!" -ForegroundColor Yellow
}

# 3. EXTRAIR O ARQUIVO .7z (Apenas se n\Uffffffffextra\Uffffffff)
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
    Write-Host "[$IP] Drivers j\Uffffffffxtra\Uffffffffs anteriormente. Pulando extra\Uffffffff!" -ForegroundColor Yellow
}

# 4. CONSULTA SNMP
Write-Host "[$IP] Consultando o modelo da impressora via SNMP..." -ForegroundColor Cyan
$SNMP = New-Object -ComObject olePrn.OleSNMP
$SNMP.Open($IP, "public")
$ModeloCru = $SNMP.Get(".1.3.6.1.2.1.25.3.2.1.3.1")
$SNMP.Close()

if (-not $ModeloCru) {
    Write-Error "[$IP] N\Ufffffffffoi poss\Uffffffffl obter o modelo via SNMP. Verifique a rede."
    return
}
Write-Host "[$IP] Modelo detectado na rede: $ModeloCru" -ForegroundColor Green

# 5. ISOLAR O CODENOME DO MODELO (Ex: Extrai "M3655idn" de "ECOSYS M3655idn")
$CoreModel = $ModeloCru -split ' ' | Where-Object { $_ -match '\d' } | Select-Object -First 1
if (-not $CoreModel) { $CoreModel = $ModeloCru }

# 6. VARREDURA CIR\UffffffffGICA DO OEMSETUP.INF
$InfPath = $null
$DriverName = $null

foreach ($file in $InfFiles) {
    $Lines = Get-Content $file.FullName
    foreach ($line in $Lines) {
        # Captura apenas strings dentro de aspas antes do sinal de igual (=) 
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
    Write-Error "[$IP] Erro: N\Ufffffffffoi poss\Uffffffffl localizar a linha de mapeamento para o driver de '$CoreModel'."
    return
}

Write-Host "[$IP] Nome do Driver mapeado: $DriverName" -ForegroundColor Green
Write-Host "[$IP] Arquivo INF localizado: $InfPath" -ForegroundColor Green

# 7. CRIAR A PORTA TCP/IP
$PortName = "IP_$IP"
if (-not (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue)) {
    Write-Host "[$IP] Criando a porta de impress\Uffffffff($PortName)..." -ForegroundColor Cyan
    Add-PrinterPort -Name $PortName -PrinterHostAddress $IP
}

# 8. IGNORAR POP-UP DE SEGURAN\Uffffffff (Adiciona certificado digital)
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

# 9. HOMOLOGAR PACOTE NO DRIVERSTORE
Write-Host "[$IP] Injetando pacote no reposit\Uffffffff seguro (PnPUtil)..." -ForegroundColor Cyan
pnputil.exe /add-driver $InfPath | Out-Null

# 10. REGISTRAR DRIVER VIA PRINTUI.DLL (Substitui\Uffffffff cir\Uffffffffa contra o erro 0x80070057)
Write-Host "[$IP] Registrando driver no Spooler atrav\Uffffffffdo subsistema PrintUI..." -ForegroundColor Cyan
$PrintUIArgs = "printui.dll,PrintUIEntry /ia /m `"$DriverName`" /f `"$InfPath`""
$Process = Start-Process rundll32.exe -ArgumentList $PrintUIArgs -Wait -PassThru -NoNewWindow

if ($Process.ExitCode -ne 0) {
    Write-Error "[$IP] Falha cr\Uffffffffca ao registrar o driver via PrintUI. C\Uffffffffo de sa\Uffffffff: $($Process.ExitCode)"
    return
}

# ====================================================================
# 11. CRIAR A IMPRESSORA DEFINITIVAMENTE
# ====================================================================
Write-Host "[$IP] Finalizando a cria\Uffffffff da impressora no Windows..." -ForegroundColor Cyan
Add-Printer -Name $ModeloCru -DriverName $DriverName -PortName $PortName

# ====================================================================
# 12. CONFIGURA\UffffffffES PADR\Uffffffff DE IMPRESS\Uffffffff (Ajustado para Kyocera)
# ====================================================================
Write-Host "[$IP] Aplicando padr\Uffffffffde impress\Uffffffff(Duplex, Cassete e M\Uffffffffa Comum)..." -ForegroundColor Cyan

# 1. Ativar o Duplex (Frente e Verso)
Set-PrintConfiguration -PrinterName "$ModeloCru" -Duplexing TwoSidedLongEdge

# 2. Capturar o XML de configura\Uffffffffs da impressora
$Config = Get-PrintConfiguration -PrinterName "$ModeloCru"
[xml]$Ticket = $Config.PrintTicketXML

# Criar o gerenciador de mapa do XML
$nsm = New-Object System.Xml.XmlNamespaceManager($Ticket.NameTable)
$nsm.AddNamespace("psf", "http://schemas.microsoft.com/windows/2003/08/printing/printschemaframework")

# 3. ALTERAR A ORIGEM DO PAPEL (Para o psk:Cassette que voc\Uffffffffncontrou)
$BinNode = $Ticket.SelectSingleNode("//psf:Feature[@name='psk:PageInputBin']/psf:Option", $nsm)
if ($BinNode) {
    $BinNode.SetAttribute("name", "psk:Cassette")
    Write-Host "[$IP] -> Origem definida para: Cassete" -ForegroundColor Yellow
} else {
    # Se o n\Ufffffffftiver oculto, for\Uffffffffa cria\Uffffffff dele com o nome correto
    $FragmentBin = $Ticket.CreateDocumentFragment()
    $FragmentBin.InnerXml = '<psf:Feature name="psk:PageInputBin"><psf:Option name="psk:Cassette" /></psf:Feature>'
    $Ticket.DocumentElement.AppendChild($FragmentBin) | Out-Null
    Write-Host "[$IP] -> Origem injetada com sucesso: Cassete" -ForegroundColor Yellow
}

# 4. ALTERAR O TIPO DE M\UffffffffIA (Papel Comum)
$MediaNode = $Ticket.SelectSingleNode("//psf:Feature[@name='psk:PageMediaType']/psf:Option", $nsm)
if ($MediaNode) {
    $MediaNode.SetAttribute("name", "psk:Plain")
    Write-Host "[$IP] -> Tipo de m\Uffffffffa definido para: Comum (Plain)" -ForegroundColor Yellow
} else {
    $FragmentMedia = $Ticket.CreateDocumentFragment()
    $FragmentMedia.InnerXml = '<psf:Feature name="psk:PageMediaType"><psf:Option name="psk:Plain" /></psf:Feature>'
    $Ticket.DocumentElement.AppendChild($FragmentMedia) | Out-Null
    Write-Host "[$IP] -> Tipo de m\Uffffffffa injetado com sucesso: Comum (Plain)" -ForegroundColor Yellow
}

# 5. Salvar o XML modificado de volta na impressora
Set-PrintConfiguration -PrinterName "$ModeloCru" -PrintTicketXML $Ticket.OuterXml

Write-Host "?? Impressora $ModeloCru instalada e configurada com sucesso no IP $IP!" -ForegroundColor Green
