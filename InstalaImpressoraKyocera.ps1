<#
    INSTALADOR DE IMPRESSORAS KYOCERA - Machadao Corp
    Descoberta automatica na rede local (mascara detectada do adaptador ativo,
    /24 ou /23) + filtro SNMP por fabricante + interface WinForms.

    REQUER EXECUCAO COMO ADMINISTRADOR (driver/spooler/certificado).
    No ISE, abra como Administrador - o script avisa se nao estiver elevado.
    Os logs de andamento saem no console/ISE via Write-Host.

    Para rodar sem mostrar o console (fora do ISE), chame assim:
        powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "Instala-Kyocera.ps1"
    Nao esconda o console por dentro do script - isso trava o printui.

    Desenvolvido por @JJMoratelli
#>

# ============================================================ CHECAGEM DE ELEVACAO
$souAdmin = ([System.Security.Principal.WindowsPrincipal] `
    [System.Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $souAdmin) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Este instalador precisa ser executado como Administrador.`n`n" +
        "Feche e reabra o PowerShell ISE (ou o console) com 'Executar como administrador' e rode novamente.",
        "Permissao insuficiente",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    return
}

# ============================================================ CONSOLE
# NAO reativar o "console oculto" (ShowWindow(hWnd, 0)) aqui: esconder a janela
# do processo pai faz o rundll32 printui.dll travar indefinidamente ao registrar
# o driver (/ia) e ao criar a impressora (/if). Ja aconteceu duas vezes.
# Os logs de andamento saem por Write-Host e sao uteis no ISE.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# O ISE mantem variaveis entre execucoes - zera estado no inicio
$script:ImpressorasAchadas = @{}   # IP -> ModeloCru
$script:InfFiles           = $null
$script:FilaInstalacao     = @()   # itens marcados (validados) aguardando o Prosseguir

# Limpa temporarios de config de execucoes anteriores (sao disparados em
# background, entao nao da pra apagar na hora em que sao usados)
Get-ChildItem -Path $env:TEMP -Filter "cfg-impressora-*.ps1" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-1) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# ============================================================ PALETA
$Preto   = [System.Drawing.ColorTranslator]::FromHtml("#12161C")
$Azul    = [System.Drawing.ColorTranslator]::FromHtml("#1A5FB4")
$AzulH   = [System.Drawing.ColorTranslator]::FromHtml("#154C90")
$AzulD   = [System.Drawing.ColorTranslator]::FromHtml("#A9B2BD")
$Grafite = [System.Drawing.ColorTranslator]::FromHtml("#5B6672")
$Claro   = [System.Drawing.ColorTranslator]::FromHtml("#9AA4AF")
$Eyebrow = [System.Drawing.ColorTranslator]::FromHtml("#7C93AE")
$Credito = [System.Drawing.ColorTranslator]::FromHtml("#B4BCC5")
$Verde   = [System.Drawing.ColorTranslator]::FromHtml("#0A6F66")
$Ambar   = [System.Drawing.ColorTranslator]::FromHtml("#8A5A00")
$Vinho   = [System.Drawing.ColorTranslator]::FromHtml("#C01C28")
$VinhoBg = [System.Drawing.ColorTranslator]::FromHtml("#FBEAEA")
$Campo   = [System.Drawing.ColorTranslator]::FromHtml("#EDEFF2")

# ============================================================ PREPARACAO DOS DRIVERS (uma vez)
function Baixar-DoGoogleDrive($FileId, $Destino) {
    # Link de compartilhamento do Drive nao é download direto - o Google
    # intercala uma pagina de aviso (com um token "confirm=") antes de liberar
    # o arquivo. Faz a primeira request pra pegar o token, depois baixa de
    # verdade lendo em blocos pra poder mostrar o progresso (%) no $msg.
    $urlBase = "https://drive.google.com/uc?export=download&id=$FileId"
    $resp = Invoke-WebRequest -Uri $urlBase -SessionVariable ses -UseBasicParsing

    $urlFinal = $urlBase
    if ($resp.Content -match 'confirm=([0-9A-Za-z_\-]+)') {
        $token = $Matches[1]
        $urlFinal = "https://drive.google.com/uc?export=download&confirm=$token&id=$FileId"
    }

    $req = [System.Net.HttpWebRequest]::Create($urlFinal)
    $req.CookieContainer = $ses.Cookies
    $resposta = $req.GetResponse()
    $totalBytes = $resposta.ContentLength
    $streamEntrada = $resposta.GetResponseStream()
    $streamSaida = [System.IO.File]::Create($Destino)

    $buffer = New-Object byte[] 65536
    $totalLido = 0
    $relogio = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        while (($lido = $streamEntrada.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $streamSaida.Write($buffer, 0, $lido)
            $totalLido += $lido
            if ($relogio.ElapsedMilliseconds -gt 200) {
                $recebidoMB = [math]::Round($totalLido / 1MB, 1)
                if ($totalBytes -gt 0) {
                    $pct = [math]::Round(($totalLido / $totalBytes) * 100)
                    $totalMB = [math]::Round($totalBytes / 1MB, 1)
                    $msg.Text = "Baixando drivers... $pct% ($recebidoMB MB de $totalMB MB)"
                } else {
                    $msg.Text = "Baixando drivers... $recebidoMB MB"
                }
                [System.Windows.Forms.Application]::DoEvents()
                $relogio.Restart()
            }
        }
        $msg.Text = "Download concluido ($([math]::Round($totalLido / 1MB, 1)) MB)."
        [System.Windows.Forms.Application]::DoEvents()
    }
    finally {
        $streamSaida.Close()
        $streamEntrada.Close()
        $resposta.Close()
    }
}

function Preparar-Drivers {
    $DriverFileId = "1YJC2UHbEAAihMMqgS980WbLZe7q4AQ7S"
    $TempDir      = "C:\KyoceraDrivers"
    $ZipPath      = "$TempDir\drivers.7z"

    if (!(Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir | Out-Null }

    if (-not (Test-Path $ZipPath)) {
        Baixar-DoGoogleDrive -FileId $DriverFileId -Destino $ZipPath
    }

    $Inf = Get-ChildItem -Path $TempDir -Filter "OEMSETUP.INF" -Recurse -ErrorAction SilentlyContinue
    if (-not $Inf) {
        $msg.Text = "Extraindo drivers..."
        [System.Windows.Forms.Application]::DoEvents()
        if (Test-Path "C:\Program Files\7-Zip\7z.exe") {
            & "C:\Program Files\7-Zip\7z.exe" x $ZipPath "-o$TempDir" -y | Out-Null
        } else {
            7z x $ZipPath "-o$TempDir" -y | Out-Null
        }
        $Inf = Get-ChildItem -Path $TempDir -Filter "OEMSETUP.INF" -Recurse
    }
    return $Inf
}

# ============================================================ REDE LOCAL
function Get-FaixaRedeLocal {
    # Pega o adaptador IPv4 ativo com gateway (exclui loopback/APIPA)
    $cfg = Get-NetIPConfiguration | Where-Object {
        $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq "Up"
    } | Select-Object -First 1

    if (-not $cfg) { throw "Nenhum adaptador de rede ativo com gateway foi encontrado." }

    $ip     = $cfg.IPv4Address[0].IPAddress
    $prefix = $cfg.IPv4Address[0].PrefixLength   # usa a mascara real configurada (/24 ou /23)

    $ipBytes  = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
    [Array]::Reverse($ipBytes)
    $ipUInt32 = [BitConverter]::ToUInt32($ipBytes, 0)

    $maskUInt32 = if ($prefix -eq 0) { 0 } else { [UInt32]([UInt32]::MaxValue -shl (32 - $prefix)) }
    $redeUInt32 = $ipUInt32 -band $maskUInt32
    $broadUInt32 = $redeUInt32 -bor (-bnot $maskUInt32)

    return @{ Inicio = $redeUInt32 + 1; Fim = $broadUInt32 - 1; Prefixo = $prefix; IPLocal = $ip }
}

function UInt32-ParaIP($valor) {
    $bytes = [BitConverter]::GetBytes([UInt32]$valor)
    [Array]::Reverse($bytes)
    return ([System.Net.IPAddress]$bytes).ToString()
}

function IP-ParaUInt32([string]$ip) {
    $bytes = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

# ============================================================ AJUDANTES DE MODELO/DRIVER (do script original)
function Get-CoreModel($modeloCru) {
    $core = $modeloCru -split ' ' | Where-Object { $_ -match '\d' } | Select-Object -First 1
    if (-not $core) { $core = $modeloCru }
    return $core
}

function Find-DriverInfo($InfFiles, $CoreModel) {
    foreach ($file in $InfFiles) {
        $linhas = Get-Content $file.FullName
        foreach ($linha in $linhas) {
            if ($linha -match '^"([^"]+)"\s*=\s*([^,]+)') {
                $possivelDriver = $Matches[1].Trim()
                $possivelSecao  = $Matches[2].Trim()
                if ($possivelDriver -like "*$CoreModel*" -or $possivelSecao -like "*$CoreModel*") {
                    return @{ InfPath = $file.FullName; DriverName = $possivelDriver }
                }
            }
        }
    }
    return $null
}

function Get-ListaDrivers($InfFiles) {
    # Lista todos os drivers disponiveis no pacote, para selecao manual quando o SNMP nao ajudar
    $out = @()
    foreach ($file in $InfFiles) {
        $linhas = Get-Content $file.FullName
        foreach ($linha in $linhas) {
            if ($linha -match '^"([^"]+)"\s*=\s*([^,]+)') {
                $out += [PSCustomObject]@{ DriverName = $Matches[1].Trim(); InfPath = $file.FullName }
            }
        }
    }
    return $out | Sort-Object DriverName -Unique
}

function Aguardar-ProcessoComUI($proc, $timeoutSeg) {
    # Nao usar WaitForExit() aqui: isso bloqueia a thread da UI, que para de
    # processar mensagens do Windows - e o printui depende disso pra terminar.
    # O resultado e um deadlock em que nem o proprio timeout dispara.
    # Espera em fatias, bombeando a fila de mensagens no meio.
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $proc.HasExited -and $sw.ElapsedMilliseconds -lt ($timeoutSeg * 1000)) {
        Start-Sleep -Milliseconds 150
        [System.Windows.Forms.Application]::DoEvents()
    }
    $sw.Stop()
    if (-not $proc.HasExited) {
        try { $proc.Kill() } catch { }
        return @{ Terminou = $false; Ms = $sw.ElapsedMilliseconds; ExitCode = $null }
    }
    return @{ Terminou = $true; Ms = $sw.ElapsedMilliseconds; ExitCode = $proc.ExitCode }
}

function Install-ImpressoraKyocera($IpAlvo, $DriverInfo, $NomeFinal, [scriptblock]$StatusCallback) {
    # Logica compartilhada entre o dialogo manual e a grade de descoberta inline.
    # StatusCallback (opcional) recebe uma frase curta por etapa, pra quem chamar
    # poder mostrar andamento (a splash da grade usa isso).
    # Avisar() tambem escreve no console/ISE com timestamp, pra debug.
    function Avisar($etapa) {
        Write-Host ("[{0:HH:mm:ss.fff}] [$NomeFinal] $etapa" -f (Get-Date)) -ForegroundColor Cyan
        if ($StatusCallback) { & $StatusCallback $etapa }
    }
    function Detalhe($texto) {
        Write-Host ("[{0:HH:mm:ss.fff}]     $texto" -f (Get-Date)) -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Yellow
    Write-Host "INSTALANDO: $NomeFinal | IP: $IpAlvo" -ForegroundColor Yellow
    Write-Host "Driver: $($DriverInfo.DriverName)" -ForegroundColor Yellow
    Write-Host "INF: $($DriverInfo.InfPath)" -ForegroundColor Yellow
    Write-Host ("=" * 70) -ForegroundColor Yellow

    $portName = "IP_$IpAlvo"

    Avisar "verificando se ja existe..."
    $existePorNome  = Get-Printer -Name $NomeFinal -ErrorAction SilentlyContinue
    Detalhe "Get-Printer por nome retornou: $(if ($existePorNome) { 'EXISTE' } else { 'nao existe' })"
    $existePorPorta = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.PortName -eq $portName }
    Detalhe "Get-Printer por porta ($portName) retornou: $(if ($existePorPorta) { "EXISTE ($($existePorPorta.Name))" } else { 'nao existe' })"
    if ($existePorNome -or $existePorPorta) {
        Avisar "ja existe (mesmo nome ou mesmo IP) - pulando."
        return $false
    }

    Avisar "criando porta de rede..."
    $portaExistente = Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue
    if (-not $portaExistente) {
        Detalhe "porta nao existe, criando com Add-PrinterPort..."
        Add-PrinterPort -Name $portName -PrinterHostAddress $IpAlvo
        Detalhe "Add-PrinterPort retornou OK"
    } else {
        Detalhe "porta $portName ja existia, reutilizando"
    }

    Avisar "homologando certificado do driver..."
    $infDir = Split-Path $DriverInfo.InfPath
    $catFile = Get-ChildItem -Path $infDir -Filter "*.cat" | Select-Object -First 1
    if ($catFile) {
        Detalhe "arquivo .cat: $($catFile.Name)"
        $cert = (Get-AuthenticodeSignature $catFile.FullName).SignerCertificate
        if ($cert) {
            Detalhe "certificado encontrado, adicionando ao TrustedPublisher..."
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPublisher", "LocalMachine")
            $store.Open("ReadWrite")
            $store.Add($cert)
            $store.Close()
            Detalhe "certificado adicionado"
        } else { Detalhe "sem certificado no .cat - seguindo" }
    } else { Detalhe "nenhum .cat na pasta - seguindo" }

    Avisar "instalando driver no Windows (pnputil)..."
    $saidaPnputil = & pnputil.exe /add-driver $DriverInfo.InfPath 2>&1
    Detalhe "pnputil exit code: $LASTEXITCODE"
    foreach ($l in $saidaPnputil) { Detalhe "pnputil> $l" }

    Avisar "registrando driver no spooler (PrintUI)..."
    $printUiArgs = "printui.dll,PrintUIEntry /ia /m `"$($DriverInfo.DriverName)`" /f `"$($DriverInfo.InfPath)`""
    Detalhe "rundll32 $printUiArgs"
    $proc = Start-Process rundll32.exe -ArgumentList $printUiArgs -PassThru -WindowStyle Hidden
    $resIa = Aguardar-ProcessoComUI $proc 60
    Detalhe "PrintUI /ia terminou em $($resIa.Ms) ms, exit code $($resIa.ExitCode)"
    if (-not $resIa.Terminou) { throw "PrintUI /ia travou e foi encerrado." }
    if ($resIa.ExitCode -ne 0) { throw "Falha ao registrar o driver via PrintUI (exit $($resIa.ExitCode))." }

    Detalhe "conferindo se o driver aparece em Get-PrinterDriver..."
    $drvInstalado = Get-PrinterDriver -Name $DriverInfo.DriverName -ErrorAction SilentlyContinue
    Detalhe "Get-PrinterDriver: $(if ($drvInstalado) { 'PRESENTE' } else { 'AUSENTE (pode ser o motivo do travamento)' })"

    Avisar "criando a impressora..."
    $ifArgs = "printui.dll,PrintUIEntry /if /b `"$NomeFinal`" /f `"$($DriverInfo.InfPath)`" /r `"$portName`" /m `"$($DriverInfo.DriverName)`""
    Detalhe "rundll32 $ifArgs"
    $procIf = Start-Process rundll32.exe -ArgumentList $ifArgs -PassThru -WindowStyle Hidden
    $resIf = Aguardar-ProcessoComUI $procIf 60
    Detalhe "printui /if terminou em $($resIf.Ms) ms, exit code $($resIf.ExitCode)"

    Avisar "configurando bandeja e papel..."
    # Set-PrintConfiguration aplica a mudanca e depois nao retorna. Dispara num
    # powershell externo e segue - nao espera, nao verifica. Ja funciona.
    $scriptCfg = @'
param($nome)
$config = Get-PrintConfiguration -PrinterName $nome
[xml]$ticket = $config.PrintTicketXML
$nsm = New-Object System.Xml.XmlNamespaceManager($ticket.NameTable)
$nsm.AddNamespace("psf", "http://schemas.microsoft.com/windows/2003/08/printing/printschemaframework")
$binNode = $ticket.SelectSingleNode("//psf:Feature[@name='psk:PageInputBin']/psf:Option", $nsm)
if ($binNode) { $binNode.SetAttribute("name", "psk:Cassette") }
else {
    $frag = $ticket.CreateDocumentFragment()
    $frag.InnerXml = '<psf:Feature name="psk:PageInputBin"><psf:Option name="psk:Cassette" /></psf:Feature>'
    $ticket.DocumentElement.AppendChild($frag) | Out-Null
}
$mediaNode = $ticket.SelectSingleNode("//psf:Feature[@name='psk:PageMediaType']/psf:Option", $nsm)
if ($mediaNode) { $mediaNode.SetAttribute("name", "psk:Plain") }
else {
    $frag2 = $ticket.CreateDocumentFragment()
    $frag2.InnerXml = '<psf:Feature name="psk:PageMediaType"><psf:Option name="psk:Plain" /></psf:Feature>'
    $ticket.DocumentElement.AppendChild($frag2) | Out-Null
}
Set-PrintConfiguration -PrinterName $nome -PrintTicketXML $ticket.OuterXml
'@
    $arqCfg = Join-Path $env:TEMP "cfg-impressora-$([guid]::NewGuid().ToString('N')).ps1"
    Set-Content -Path $arqCfg -Value $scriptCfg -Encoding UTF8
    Start-Process powershell.exe `
        -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$arqCfg`"", "`"$NomeFinal`"" `
        -WindowStyle Hidden
    Detalhe "config disparada em background - seguindo"

    Write-Host ("[{0:HH:mm:ss.fff}] [$NomeFinal] CONCLUIDA COM SUCESSO" -f (Get-Date)) -ForegroundColor Green
    return $true
}

# ============================================================ SNMP PURO VIA UDP (sem COM, sem processo novo)
# BER/ASN.1 minimo pra montar um GetRequest SNMPv1 e ler a resposta.
# UdpClient.Client.ReceiveTimeout eh um timeout de verdade do socket,
# cancela limpo (sem processo zumbi, sem depender do COM olePrn.OleSNMP).

function ConvertTo-BerLength([int]$len) {
    if ($len -lt 128) { return [byte[]]@($len) }
    $bytes = [BitConverter]::GetBytes([UInt32]$len)
    $out = New-Object System.Collections.Generic.List[byte]
    for ($i = 3; $i -ge 0; $i--) {
        if ($bytes[$i] -ne 0 -or $out.Count -gt 0) { $out.Add($bytes[$i]) }
    }
    if ($out.Count -eq 0) { $out.Add(0) }
    return [byte[]](@([byte](0x80 -bor $out.Count)) + $out.ToArray())
}

function New-BerTLV([byte]$tag, [byte[]]$content) {
    return [byte[]](@($tag) + (ConvertTo-BerLength $content.Length) + $content)
}

function ConvertTo-BerInteger([int]$value) {
    if ($value -eq 0) { return New-BerTLV 0x02 @([byte]0) }
    $bytes = [BitConverter]::GetBytes([Int32]$value)
    [Array]::Reverse($bytes)
    $i = 0
    while ($i -lt ($bytes.Length - 1) -and $bytes[$i] -eq 0 -and ($bytes[$i + 1] -band 0x80) -eq 0) { $i++ }
    return New-BerTLV 0x02 ([byte[]]$bytes[$i..($bytes.Length - 1)])
}

function ConvertTo-BerOctetString([string]$text) {
    return New-BerTLV 0x04 ([System.Text.Encoding]::ASCII.GetBytes($text))
}

function ConvertTo-BerNull() { return New-BerTLV 0x05 @() }

function Encode-BerOidSubid([int]$val) {
    if ($val -eq 0) { return [byte[]]@(0) }
    $pilha = New-Object System.Collections.Generic.List[byte]
    while ($val -gt 0) {
        $pilha.Insert(0, [byte]($val -band 0x7F))
        $val = $val -shr 7
    }
    for ($i = 0; $i -lt $pilha.Count - 1; $i++) { $pilha[$i] = $pilha[$i] -bor 0x80 }
    return $pilha.ToArray()
}

function ConvertTo-BerOid([string]$oidString) {
    $partes = $oidString.Trim('.') -split '\.' | ForEach-Object { [int]$_ }
    $out = New-Object System.Collections.Generic.List[byte]
    $out.AddRange([byte[]](Encode-BerOidSubid (40 * $partes[0] + $partes[1])))
    for ($i = 2; $i -lt $partes.Count; $i++) { $out.AddRange([byte[]](Encode-BerOidSubid $partes[$i])) }
    return New-BerTLV 0x06 $out.ToArray()
}

function Build-SnmpGetRequest([string]$community, [string[]]$oids, [int]$requestId) {
    $varbinds = @()
    foreach ($oid in $oids) {
        $varbinds += New-BerTLV 0x30 ([byte[]]((ConvertTo-BerOid $oid) + (ConvertTo-BerNull)))
    }
    $varbindList = New-BerTLV 0x30 ([byte[]]$varbinds)
    $pdu = New-BerTLV 0xA0 ([byte[]]((ConvertTo-BerInteger $requestId) + (ConvertTo-BerInteger 0) + (ConvertTo-BerInteger 0) + $varbindList))
    return New-BerTLV 0x30 ([byte[]]((ConvertTo-BerInteger 0) + (ConvertTo-BerOctetString $community) + $pdu))
}

function Read-BerTLV([byte[]]$bytes, [int]$offset) {
    $tag = $bytes[$offset]; $offset++
    $lenByte = $bytes[$offset]; $offset++
    if ($lenByte -band 0x80) {
        $numLenBytes = $lenByte -band 0x7F
        $length = 0
        for ($i = 0; $i -lt $numLenBytes; $i++) { $length = ($length -shl 8) -bor $bytes[$offset]; $offset++ }
    } else {
        $length = $lenByte
    }
    $content = if ($length -eq 0) { @() } else { [byte[]]$bytes[$offset..($offset + $length - 1)] }
    $offset += $length
    return @{ Tag = $tag; Length = $length; Content = $content; NextOffset = $offset }
}

function ConvertFrom-BerInteger([byte[]]$bytes) {
    $val = 0
    foreach ($b in $bytes) { $val = ($val -shl 8) -bor $b }
    return $val
}

function Get-SnmpValoresUdp([string]$ipAlvo, [string[]]$oids, [int]$timeoutMs, [string]$community = "public") {
    $reqId  = Get-Random -Minimum 1 -Maximum 2147483647
    $pacote = Build-SnmpGetRequest $community $oids $reqId

    $udp = New-Object System.Net.Sockets.UdpClient
    try {
        $udp.Client.ReceiveTimeout = $timeoutMs
        $udp.Connect($ipAlvo, 161)
        $udp.Send($pacote, $pacote.Length) | Out-Null
        $remoteEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $resposta = $udp.Receive([ref]$remoteEp)
    }
    catch [System.Net.Sockets.SocketException] {
        return "TIMEOUT"   # timeout real ou porta fechada (unreachable) - nao trava
    }
    finally { $udp.Close() }

    try {
        $msg = Read-BerTLV $resposta 0
        $off = 0
        $verTlv  = Read-BerTLV $msg.Content $off;  $off = $verTlv.NextOffset
        $commTlv = Read-BerTLV $msg.Content $off;  $off = $commTlv.NextOffset
        $pduTlv  = Read-BerTLV $msg.Content $off

        $off2 = 0
        $reqIdTlv   = Read-BerTLV $pduTlv.Content $off2; $off2 = $reqIdTlv.NextOffset
        $errStatTlv = Read-BerTLV $pduTlv.Content $off2; $off2 = $errStatTlv.NextOffset
        $errIdxTlv  = Read-BerTLV $pduTlv.Content $off2; $off2 = $errIdxTlv.NextOffset
        $vbListTlv  = Read-BerTLV $pduTlv.Content $off2

        if ((ConvertFrom-BerInteger $errStatTlv.Content) -ne 0) { return $null }

        $valores = @()
        $o = 0
        while ($o -lt $vbListTlv.Content.Length) {
            $vbTlv = Read-BerTLV $vbListTlv.Content $o
            $o = $vbTlv.NextOffset
            $oidTlv = Read-BerTLV $vbTlv.Content 0
            $valTlv = Read-BerTLV $vbTlv.Content $oidTlv.NextOffset
            if ($valTlv.Tag -eq 0x04) { $valores += [System.Text.Encoding]::ASCII.GetString($valTlv.Content) }
            else { $valores += $null }
        }
        return $valores
    }
    catch { return $null }
}

function Get-InfoImpressoraViaSnmp($ipAlvo) {
    # Consulta modelo (hrDeviceDescr) e fabricante (sysDescr) numa unica ida-e-volta UDP.
    # sysDescr eh quem carrega o texto "KYOCERA" - hrDeviceDescr so tem o nome
    # do modelo (ex: "ECOSYS M3655idn"), sem o fabricante.
    $valores = Get-SnmpValoresUdp $ipAlvo @(".1.3.6.1.2.1.25.3.2.1.3.1", ".1.3.6.1.2.1.1.1.0") 800
    if (-not $valores -or $valores -eq "TIMEOUT") { return $null }
    return @{ Modelo = $valores[0]; Fabricante = $valores[1] }
}

# ============================================================ JANELA PRINCIPAL
$LARG = 620
$ALT  = 560

$Form                 = New-Object System.Windows.Forms.Form
$Form.Text            = "Instalador de Impressoras Kyocera"
$Form.Size            = New-Object System.Drawing.Size($LARG, $ALT)
$Form.StartPosition   = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox     = $false
$Form.MinimizeBox     = $false
$Form.ControlBox      = $true
$Form.TopMost         = $true
$Form.BackColor       = [System.Drawing.Color]::White

# ---- Cabecalho
$cab           = New-Object System.Windows.Forms.Panel
$cab.Size      = New-Object System.Drawing.Size($LARG, 96)
$cab.BackColor = $Preto
$Form.Controls.Add($cab)

$lblEyebrow           = New-Object System.Windows.Forms.Label
$lblEyebrow.Text      = "M A C H A D A O   C O R P"
$lblEyebrow.Font      = New-Object System.Drawing.Font("Consolas", 9)
$lblEyebrow.ForeColor = $Eyebrow
$lblEyebrow.Location  = New-Object System.Drawing.Point(34, 20)
$lblEyebrow.AutoSize  = $true
$cab.Controls.Add($lblEyebrow)

$titulo           = New-Object System.Windows.Forms.Label
$titulo.Text      = "Impressoras Kyocera"
$titulo.Font      = New-Object System.Drawing.Font("Segoe UI", 19)
$titulo.ForeColor = [System.Drawing.Color]::White
$titulo.Location  = New-Object System.Drawing.Point(32, 42)
$titulo.AutoSize  = $true
$cab.Controls.Add($titulo)

$contexto           = New-Object System.Windows.Forms.Label
$contexto.Text      = "$env:COMPUTERNAME"
$contexto.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$contexto.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#C9D3DE")
$contexto.Location  = New-Object System.Drawing.Point(($LARG - 260), 58)
$contexto.Size      = New-Object System.Drawing.Size(226, 20)
$contexto.TextAlign = "MiddleRight"
$cab.Controls.Add($contexto)

# ---- Ajuda
$ajuda           = New-Object System.Windows.Forms.Label
$ajuda.Text      = "Varre a rede local e filtra por SNMP (so Kyocera)."
$ajuda.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$ajuda.ForeColor = $Grafite
$ajuda.Location  = New-Object System.Drawing.Point(36, 112)
$ajuda.AutoSize  = $true
$Form.Controls.Add($ajuda)

# ---- Botao escanear
$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "Escanear rede"
$btnScan.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$btnScan.Size = New-Object System.Drawing.Size(170, 42)
$btnScan.Location = New-Object System.Drawing.Point(36, 138)
$btnScan.FlatStyle = "Flat"
$btnScan.FlatAppearance.BorderSize = 0
$btnScan.BackColor = $Azul
$btnScan.ForeColor = [System.Drawing.Color]::White
$btnScan.FlatAppearance.MouseOverBackColor = $AzulH
$btnScan.FlatAppearance.MouseDownBackColor = $AzulH
$Form.Controls.Add($btnScan)

# ---- Botao adicionar manualmente
$btnManual = New-Object System.Windows.Forms.Button
$btnManual.Text = "Adicionar manualmente"
$btnManual.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$btnManual.Size = New-Object System.Drawing.Size(214, 42)
$btnManual.Location = New-Object System.Drawing.Point(218, 138)
$btnManual.FlatStyle = "Flat"
$btnManual.BackColor = [System.Drawing.Color]::White
$btnManual.ForeColor = $Grafite
$btnManual.FlatAppearance.BorderSize = 1
$btnManual.FlatAppearance.BorderColor = $Grafite
$btnManual.FlatAppearance.MouseOverBackColor = $Campo
$Form.Controls.Add($btnManual)

# ---- Botao prosseguir (substitui Escanear+Manual quando ha itens marcados na grade)
$btnProsseguir = New-Object System.Windows.Forms.Button
$btnProsseguir.Text = "Prosseguir"
$btnProsseguir.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$btnProsseguir.Size = New-Object System.Drawing.Size(396, 42)
$btnProsseguir.Location = New-Object System.Drawing.Point(36, 138)
$btnProsseguir.FlatStyle = "Flat"
$btnProsseguir.FlatAppearance.BorderSize = 0
$btnProsseguir.BackColor = $Verde
$btnProsseguir.ForeColor = [System.Drawing.Color]::White
$btnProsseguir.Visible = $false
$Form.Controls.Add($btnProsseguir)

# ---- Botao parar (so aparece durante o scan)
$btnParar = New-Object System.Windows.Forms.Button
$btnParar.Text = "Parar"
$btnParar.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$btnParar.Size = New-Object System.Drawing.Size(140, 42)
$btnParar.Location = New-Object System.Drawing.Point(442, 138)
$btnParar.FlatStyle = "Flat"
$btnParar.FlatAppearance.BorderSize = 0
$btnParar.BackColor = $Vinho
$btnParar.ForeColor = [System.Drawing.Color]::White
$btnParar.FlatAppearance.MouseOverBackColor = $VinhoBg
$btnParar.Visible = $false
$Form.Controls.Add($btnParar)

# ---- Grade de impressoras encontradas (nome + tipo editaveis, adicao inline)
$lista = New-Object System.Windows.Forms.DataGridView
$lista.Location = New-Object System.Drawing.Point(36, 194)
$lista.Size = New-Object System.Drawing.Size(($LARG - 72), 246)
$lista.BackgroundColor = [System.Drawing.Color]::White
$lista.BorderStyle = "None"
$lista.CellBorderStyle = "SingleHorizontal"
$lista.GridColor = $Campo
$lista.RowHeadersVisible = $false
$lista.AllowUserToAddRows = $false
$lista.AllowUserToDeleteRows = $false
$lista.AllowUserToResizeRows = $false
$lista.MultiSelect = $false
$lista.SelectionMode = "CellSelect"
$lista.EditMode = "EditOnEnter"
$lista.RowTemplate.Height = 30
$lista.EnableHeadersVisualStyles = $false
$lista.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::White
$lista.ColumnHeadersDefaultCellStyle.ForeColor = $Grafite
$lista.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lista.ScrollBars = "Vertical"   # nunca horizontal - a coluna Nome preenche o resto e o botao nunca fica encoberto
$lista.DefaultCellStyle.Font = New-Object System.Drawing.Font("Consolas", 10)
$lista.DefaultCellStyle.SelectionBackColor = $Campo
$lista.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::Black
$lista.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Black

$colIp = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colIp.Name = "colIp"; $colIp.HeaderText = "IP"; $colIp.Width = 105; $colIp.ReadOnly = $true
$lista.Columns.Add($colIp) | Out-Null

$colModelo = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colModelo.Name = "colModelo"; $colModelo.HeaderText = "Modelo"; $colModelo.Width = 95; $colModelo.ReadOnly = $true
$lista.Columns.Add($colModelo) | Out-Null

$colNome = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colNome.Name = "colNome"; $colNome.HeaderText = "Nome (KY-AREA-LJxx/ATAC)"
$colNome.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill   # ocupa o resto - nunca sobra sob rolagem
$lista.Columns.Add($colNome) | Out-Null

$colAcao = New-Object System.Windows.Forms.DataGridViewButtonColumn
$colAcao.Name = "colAcao"; $colAcao.HeaderText = ""; $colAcao.Width = 90
$colAcao.FlatStyle = "Flat"
$colAcao.UseColumnTextForButtonValue = $false
$colAcao.DefaultCellStyle.BackColor = $Azul
$colAcao.DefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$colAcao.DefaultCellStyle.SelectionBackColor = $AzulH
$colAcao.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
$lista.Columns.Add($colAcao) | Out-Null

$Form.Controls.Add($lista)

# ---- Painel de instalacao (substitui a grade na mesma janela - sem modal aninhada,
# que era o que travava o Add-Printer)
$painelInstalacao = New-Object System.Windows.Forms.Panel
$painelInstalacao.Location = New-Object System.Drawing.Point(36, 138)
$painelInstalacao.Size = New-Object System.Drawing.Size(($LARG - 72), 302)
$painelInstalacao.BackColor = [System.Drawing.Color]::White
$painelInstalacao.Visible = $false
$Form.Controls.Add($painelInstalacao)

$lblInstTitulo = New-Object System.Windows.Forms.Label
$lblInstTitulo.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$lblInstTitulo.ForeColor = $Grafite
$lblInstTitulo.Location = New-Object System.Drawing.Point(0, 0)
$lblInstTitulo.Size = New-Object System.Drawing.Size(($LARG - 72), 24)
$painelInstalacao.Controls.Add($lblInstTitulo)

$lstInstLog = New-Object System.Windows.Forms.ListBox
$lstInstLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$lstInstLog.Location = New-Object System.Drawing.Point(0, 30)
$lstInstLog.Size = New-Object System.Drawing.Size(($LARG - 72), 200)
$lstInstLog.ForeColor = $Grafite
$painelInstalacao.Controls.Add($lstInstLog)

$btnInstConcluir = New-Object System.Windows.Forms.Button
$btnInstConcluir.Text = "Aguarde..."
$btnInstConcluir.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$btnInstConcluir.Size = New-Object System.Drawing.Size(180, 50)
$btnInstConcluir.Location = New-Object System.Drawing.Point((($LARG - 72) - 180), 240)
$btnInstConcluir.FlatStyle = "Flat"
$btnInstConcluir.FlatAppearance.BorderSize = 0
$btnInstConcluir.BackColor = $AzulD
$btnInstConcluir.ForeColor = [System.Drawing.Color]::White
$btnInstConcluir.FlatAppearance.MouseOverBackColor = $AzulH
$btnInstConcluir.Enabled = $false
$painelInstalacao.Controls.Add($btnInstConcluir)

# ---- Status/mensagem
$msg           = New-Object System.Windows.Forms.Label
$msg.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$msg.ForeColor = $Grafite
$msg.Location  = New-Object System.Drawing.Point(36, 448)
$msg.Size      = New-Object System.Drawing.Size(($LARG - 72), 20)
$msg.Text      = 'Clique em "Escanear rede" para localizar as impressoras.'
$Form.Controls.Add($msg)

# ---- Creditos
$creditos           = New-Object System.Windows.Forms.Label
$creditos.Text      = "Desenvolvido por @JJMoratelli"
$creditos.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$creditos.ForeColor = $Credito
$creditos.Location  = New-Object System.Drawing.Point(36, 492)
$creditos.AutoSize  = $true
$Form.Controls.Add($creditos)

# ============================================================ ESCANEAR
$btnScan.Add_Click({
    $lista.Rows.Clear()
    $script:ImpressorasAchadas.Clear()
    $script:FilaInstalacao = @()
    $script:PararSolicitado = $false
    $btnScan.Enabled = $false
    $btnScan.Text = "Aguarde..."
    $btnManual.Enabled = $false
    $btnParar.Visible = $true
    $btnProsseguir.Visible = $false
    $btnScan.Visible = $true
    $btnManual.Visible = $true
    $painelInstalacao.Visible = $false
    $lista.Visible = $true
    $msg.ForeColor = $script:Grafite
    $msg.Text = "Preparando drivers..."
    [System.Windows.Forms.Application]::DoEvents()

    try {
        if (-not $script:InfFiles) { $script:InfFiles = Preparar-Drivers }

        $faixa = Get-FaixaRedeLocal
        $qtdHosts = $faixa.Fim - $faixa.Inicio + 1
        $msg.Text = "Testando $qtdHosts enderecos (/$($faixa.Prefixo)) a partir de $($faixa.IPLocal)..."
        [System.Windows.Forms.Application]::DoEvents()

        # ---- Fase 1: ping em paralelo (assincrono) com timeout de 500ms
        # Guarda tambem o objeto Ping pra poder descartar depois: cada um segura
        # um handle de socket, e centenas deles pendurados travam a chamada
        # CIM/WMI do Add-Printer mais adiante.
        $pings = @{}
        $objetosPing = New-Object System.Collections.Generic.List[object]
        for ($n = $faixa.Inicio; $n -le $faixa.Fim; $n++) {
            $alvoIP = UInt32-ParaIP $n
            $p = New-Object System.Net.NetworkInformation.Ping
            $objetosPing.Add($p)
            $pings[$alvoIP] = $p.SendPingAsync($alvoIP, 500)
        }
        # WaitAll puro bloqueia a fila de mensagens do WinForms sem pumpar -
        # troca por um loop com DoEvents, igual ao resto do script, pra nao
        # correr risco de represar callback assincrono do Ping preso na UI thread
        $swPing = [System.Diagnostics.Stopwatch]::StartNew()
        while (($pings.Values | Where-Object { -not $_.IsCompleted }).Count -gt 0 -and $swPing.ElapsedMilliseconds -lt 15000) {
            Start-Sleep -Milliseconds 100
            [System.Windows.Forms.Application]::DoEvents()
        }
        $swPing.Stop()

        $vivos = $pings.GetEnumerator() | Where-Object {
            $_.Value.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion -and
            $_.Value.Result.Status -eq [System.Net.NetworkInformation.IPStatus]::Success
        } | ForEach-Object { $_.Key } | Sort-Object { IP-ParaUInt32 $_ }   # ordem ascendente: .1, .2, .3...

        # Libera todos os sockets antes de seguir - sem isso o Add-Printer trava
        foreach ($objPing in $objetosPing) {
            try { $objPing.SendAsyncCancel() } catch { }
            try { $objPing.Dispose() } catch { }
        }
        $objetosPing.Clear()
        $pings.Clear()
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()

        $msg.Text = "$qtdHosts enderecos testados, $($vivos.Count) hosts ativos. Consultando SNMP..."
        [System.Windows.Forms.Application]::DoEvents()

        # ---- Fase 2: SNMP via UDP, em ordem, incremental (linha aparece assim que acha),
        # cancelavel pelo botao Parar sem perder o que ja foi encontrado
        $i = 0
        foreach ($alvoIP in $vivos) {
            if ($script:PararSolicitado) {
                $msg.ForeColor = $script:Ambar
                $msg.Text = "Escaneamento interrompido ($i de $($vivos.Count) hosts verificados)."
                break
            }
            $i++
            $msg.ForeColor = $script:Grafite
            $msg.Text = "Consultando SNMP: $alvoIP ($i de $($vivos.Count) hosts ativos)..."
            [System.Windows.Forms.Application]::DoEvents()

            $info = Get-InfoImpressoraViaSnmp $alvoIP
            if ($info -and $info.Fabricante -match "KYOCERA") {
                $script:ImpressorasAchadas[$alvoIP] = $info.Modelo
                $modeloCurto = Get-CoreModel $info.Modelo
                $idxLinha = $lista.Rows.Add($alvoIP, $modeloCurto, "KY-", "Adicionar")
                $lista.FirstDisplayedScrollingRowIndex = $idxLinha
                [System.Windows.Forms.Application]::DoEvents()
            }
        }

        if (-not $script:PararSolicitado) {
            if ($lista.Rows.Count -eq 0) {
                $msg.ForeColor = $script:Ambar
                $msg.Text = "Nenhuma impressora Kyocera encontrada na rede."
            } else {
                $msg.ForeColor = $script:Verde
                $msg.Text = "$($lista.Rows.Count) impressora(s) Kyocera encontrada(s)."
            }
        }
    }
    catch {
        $msg.ForeColor = $script:Vinho
        $msg.Text = "Falha na varredura: $($_.Exception.Message)"
    }
    finally {
        # Rede defensiva: se estourou excecao antes da limpeza da fase 1,
        # garante que nenhum socket de ping fique pendurado
        if ($objetosPing) {
            foreach ($objPing in $objetosPing) {
                try { $objPing.SendAsyncCancel() } catch { }
                try { $objPing.Dispose() } catch { }
            }
            $objetosPing.Clear()
        }
        $btnScan.Enabled = $true
        $btnScan.Text = "Escanear rede"
        $btnManual.Enabled = $true
        $btnParar.Visible = $false
    }
})

$btnParar.Add_Click({ $script:PararSolicitado = $true })

# ---- Marcar linha pra instalacao (valida, fica verde - nao instala ainda)
$lista.Add_CellContentClick({
    param($s, $e)
    if ($e.RowIndex -lt 0) { return }
    if ($lista.Columns[$e.ColumnIndex].Name -ne "colAcao") { return }

    $lista.EndEdit()
    $linha = $lista.Rows[$e.RowIndex]
    if ($linha.Cells["colAcao"].Value -eq "Adicionado") { return }   # ja marcada

    $ipAlvo    = $linha.Cells["colIp"].Value
    $modeloCru = $script:ImpressorasAchadas[$ipAlvo]
    $nomeTexto = ([string]$linha.Cells["colNome"].Value).Trim()

    if ($nomeTexto -match '(?i)^KY-([^-]+)-(ATAC|LJ\d{2})$') {
        $area = $Matches[1]
        $sufixo = $Matches[2].ToUpper()
        $nomeFinal = "KY-$area-$sufixo"
    } else {
        $linha.Cells["colAcao"].Value = "Nome invalido"
        $linha.Cells["colAcao"].Style.BackColor = $script:Vinho
        return
    }

    $script:FilaInstalacao += , @{ IP = $ipAlvo; Modelo = $modeloCru; NomeFinal = $nomeFinal; LinhaIndex = $e.RowIndex; Sucesso = $false }

    $linha.Cells["colNome"].Value = $nomeFinal
    $linha.Cells["colNome"].ReadOnly = $true
    $linha.Cells["colAcao"].Value = "Adicionado"
    $linha.Cells["colAcao"].Style.BackColor = $script:Verde

    $btnScan.Visible = $false
    $btnManual.Visible = $false
    $btnProsseguir.Visible = $true
    $btnProsseguir.Text = "Prosseguir ($($script:FilaInstalacao.Count) selecionada(s))"
})

# ============================================================ EXECUTAR FILA DE INSTALACAO (inline, sem modal aninhada)
function Executar-FilaInstalacao($fila) {
    # TopMost atrapalha o printui: ele cria janela propria e fica esperando
    # interacao que nunca chega com uma janela sempre-no-topo por cima.
    $topMostAnterior = $Form.TopMost
    $Form.TopMost = $false

    $lblInstTitulo.Text = "Instalando $($fila.Count) impressora(s)..."
    $lstInstLog.Items.Clear()
    $btnInstConcluir.Enabled = $false
    $btnInstConcluir.Text = "Aguarde..."
    $btnInstConcluir.BackColor = $script:AzulD
    [System.Windows.Forms.Application]::DoEvents()

    $sucesso = 0; $falha = 0
    for ($k = 0; $k -lt $fila.Count; $k++) {
        $itemFila = $fila[$k]
        $lblInstTitulo.Text = "Instalando $($k + 1) de $($fila.Count): $($itemFila.NomeFinal)"
        $lstInstLog.Items.Add("-> $($itemFila.NomeFinal) ($($itemFila.IP))...") | Out-Null
        $lstInstLog.TopIndex = $lstInstLog.Items.Count - 1
        [System.Windows.Forms.Application]::DoEvents()

        try {
            $coreModel = Get-CoreModel $itemFila.Modelo
            $driverInfo = Find-DriverInfo $script:InfFiles $coreModel
            if (-not $driverInfo) { throw "Driver nao localizado no pacote INF." }
            $instalou = Install-ImpressoraKyocera -IpAlvo $itemFila.IP -DriverInfo $driverInfo -NomeFinal $itemFila.NomeFinal -StatusCallback {
                param($etapa)
                $lstInstLog.Items[$lstInstLog.Items.Count - 1] = "-> $($itemFila.NomeFinal) ($($itemFila.IP)): $etapa"
                $lstInstLog.TopIndex = $lstInstLog.Items.Count - 1
                [System.Windows.Forms.Application]::DoEvents()
            }
            if ($instalou) {
                $lstInstLog.Items[$lstInstLog.Items.Count - 1] = "OK  $($itemFila.NomeFinal) ($($itemFila.IP)) instalada."
            } else {
                $lstInstLog.Items[$lstInstLog.Items.Count - 1] = "JA EXISTIA  $($itemFila.NomeFinal) ($($itemFila.IP)) - nada a fazer."
            }
            $itemFila.Sucesso = $true
            $sucesso++
        }
        catch {
            Write-Host "EXCECAO em $($itemFila.NomeFinal): $($_.Exception.GetType().FullName)" -ForegroundColor Red
            Write-Host "  Mensagem: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
            $lstInstLog.Items[$lstInstLog.Items.Count - 1] = "FALHOU  $($itemFila.NomeFinal): $($_.Exception.Message)"
            $itemFila.Sucesso = $false
            $falha++
        }
        $lstInstLog.TopIndex = $lstInstLog.Items.Count - 1
        [System.Windows.Forms.Application]::DoEvents()
    }
    $lblInstTitulo.Text = "Concluido: $sucesso instalada(s), $falha com falha."
    $btnInstConcluir.Enabled = $true
    $btnInstConcluir.Text = "Concluir"
    $btnInstConcluir.BackColor = $script:Azul
    $Form.TopMost = $topMostAnterior
}

$btnProsseguir.Add_Click({
    if ($script:FilaInstalacao.Count -eq 0) { return }

    $lista.Visible = $false
    $btnProsseguir.Visible = $false
    $painelInstalacao.Visible = $true
    $painelInstalacao.BringToFront()

    Executar-FilaInstalacao $script:FilaInstalacao
})

$btnInstConcluir.Add_Click({
    foreach ($itemFila in $script:FilaInstalacao) {
        $linha = $lista.Rows[$itemFila.LinhaIndex]
        if ($itemFila.Sucesso) {
            $linha.Cells["colAcao"].Value = "Instalada!"
        } else {
            $linha.Cells["colAcao"].Value = "Falhou"
            $linha.Cells["colAcao"].Style.BackColor = $script:Vinho
            $linha.Cells["colNome"].ReadOnly = $false
        }
    }

    $script:FilaInstalacao = @($script:FilaInstalacao | Where-Object { -not $_.Sucesso })

    $painelInstalacao.Visible = $false
    $lista.Visible = $true
    if ($script:FilaInstalacao.Count -eq 0) {
        $btnScan.Visible = $true
        $btnManual.Visible = $true
    } else {
        $btnProsseguir.Visible = $true
        $btnProsseguir.Text = "Prosseguir ($($script:FilaInstalacao.Count) selecionada(s))"
    }
})

# ============================================================ JANELA DE NOME (KY-Setor-LJxx / -ATAC)
function Show-DialogNome {
    param($ipAlvo, $modeloCru, [switch]$Manual)

    $altura = if ($Manual) { 470 } else { 380 }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Adicionar impressora"
    $dlg.Size = New-Object System.Drawing.Size(460, $altura)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.TopMost = $true
    $dlg.BackColor = [System.Drawing.Color]::White

    $script:DlgConcluido = $false
    $script:ModeloDetectado = $modeloCru
    $dlg.Add_FormClosing({ param($s, $e) if (-not $script:DlgConcluido) { $e.Cancel = $false } })

    $yBase = 0
    if ($Manual) {
        $lblIpTitulo = New-Object System.Windows.Forms.Label
        $lblIpTitulo.Text = "Endereco IP da impressora"
        $lblIpTitulo.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $lblIpTitulo.ForeColor = $script:Grafite
        $lblIpTitulo.Location = New-Object System.Drawing.Point(30, 16)
        $lblIpTitulo.AutoSize = $true
        $dlg.Controls.Add($lblIpTitulo)

        $txtIp = New-Object System.Windows.Forms.TextBox
        $txtIp.Font = New-Object System.Drawing.Font("Consolas", 14)
        $txtIp.Location = New-Object System.Drawing.Point(30, 40)
        $txtIp.Size = New-Object System.Drawing.Size(250, 32)
        $dlg.Controls.Add($txtIp)

        $btnDetectar = New-Object System.Windows.Forms.Button
        $btnDetectar.Text = "Detectar (SNMP)"
        $btnDetectar.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $btnDetectar.Size = New-Object System.Drawing.Size(140, 34)
        $btnDetectar.Location = New-Object System.Drawing.Point(290, 39)
        $btnDetectar.FlatStyle = "Flat"
        $btnDetectar.FlatAppearance.BorderSize = 0
        $btnDetectar.BackColor = $script:Grafite
        $btnDetectar.ForeColor = [System.Drawing.Color]::White
        $dlg.Controls.Add($btnDetectar)

        $lblStatusSnmp = New-Object System.Windows.Forms.Label
        $lblStatusSnmp.Text = "Informe o IP e detecte o modelo, ou selecione o driver manualmente abaixo."
        $lblStatusSnmp.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $lblStatusSnmp.ForeColor = $script:Grafite
        $lblStatusSnmp.Location = New-Object System.Drawing.Point(30, 78)
        $lblStatusSnmp.Size = New-Object System.Drawing.Size(400, 32)
        $dlg.Controls.Add($lblStatusSnmp)

        $lblDriverTitulo = New-Object System.Windows.Forms.Label
        $lblDriverTitulo.Text = "Nao foi possivel identificar - selecione o driver:"
        $lblDriverTitulo.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $lblDriverTitulo.ForeColor = $script:Vinho
        $lblDriverTitulo.Location = New-Object System.Drawing.Point(30, 114)
        $lblDriverTitulo.AutoSize = $true
        $lblDriverTitulo.Visible = $false
        $dlg.Controls.Add($lblDriverTitulo)

        $cmbDriver = New-Object System.Windows.Forms.ComboBox
        $cmbDriver.Font = New-Object System.Drawing.Font("Consolas", 10)
        $cmbDriver.Location = New-Object System.Drawing.Point(30, 138)
        $cmbDriver.Size = New-Object System.Drawing.Size(390, 30)
        $cmbDriver.DropDownStyle = "DropDownList"
        foreach ($d in (Get-ListaDrivers $script:InfFiles)) { $cmbDriver.Items.Add($d.DriverName) | Out-Null }
        $cmbDriver.Visible = $false
        $dlg.Controls.Add($cmbDriver)

        $script:DriverAutoDetectado = $null

        $btnDetectar.Add_Click({
            $ipDigitado = $txtIp.Text.Trim()
            if (-not $ipDigitado) {
                $lblStatusSnmp.ForeColor = $script:Vinho
                $lblStatusSnmp.Text = "Informe o IP antes de detectar."
                return
            }
            $lblDriverTitulo.Visible = $false
            $cmbDriver.Visible = $false
            $script:ModeloDetectado = $null
            $script:DriverAutoDetectado = $null

            $lblStatusSnmp.ForeColor = $script:Grafite
            $lblStatusSnmp.Text = "Consultando SNMP em $ipDigitado..."
            [System.Windows.Forms.Application]::DoEvents()

            $info = Get-InfoImpressoraViaSnmp $ipDigitado

            if (-not $info -or -not $info.Fabricante) {
                $lblStatusSnmp.ForeColor = $script:Vinho
                $lblStatusSnmp.Text = "SNMP nao respondeu nesse IP."
                $lblDriverTitulo.Visible = $true
                $cmbDriver.Visible = $true
                return
            }
            if ($info.Fabricante -notmatch "KYOCERA") {
                $lblStatusSnmp.ForeColor = $script:Ambar
                $lblStatusSnmp.Text = "Respondeu, mas nao parece Kyocera: $($info.Fabricante)"
                $lblDriverTitulo.Visible = $true
                $cmbDriver.Visible = $true
                return
            }

            $script:ModeloDetectado = $info.Modelo
            $coreModel = Get-CoreModel $info.Modelo
            $driverInfo = Find-DriverInfo $script:InfFiles $coreModel
            if (-not $driverInfo) {
                $lblStatusSnmp.ForeColor = $script:Ambar
                $lblStatusSnmp.Text = "Detectado $($info.Modelo), mas sem driver correspondente no pacote."
                $lblDriverTitulo.Visible = $true
                $cmbDriver.Visible = $true
                return
            }

            $script:DriverAutoDetectado = $driverInfo
            $lblStatusSnmp.ForeColor = $script:Verde
            $lblStatusSnmp.Text = "Detectado: $($info.Modelo)"
        })

        $yBase = 90
    }
    else {
        $lblIp = New-Object System.Windows.Forms.Label
        $lblIp.Text = "$ipAlvo - $modeloCru"
        $lblIp.Font = New-Object System.Drawing.Font("Consolas", 9)
        $lblIp.ForeColor = $script:Grafite
        $lblIp.Location = New-Object System.Drawing.Point(30, 20)
        $lblIp.Size = New-Object System.Drawing.Size(400, 20)
        $dlg.Controls.Add($lblIp)
    }

    $lblNome = New-Object System.Windows.Forms.Label
    $lblNome.Text = "Nome da impressora"
    $lblNome.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblNome.ForeColor = $script:Grafite
    $lblNome.Location = New-Object System.Drawing.Point(30, (50 + $yBase))
    $lblNome.AutoSize = $true
    $dlg.Controls.Add($lblNome)

    $lblPrefixo = New-Object System.Windows.Forms.Label
    $lblPrefixo.Text = "KY-"
    $lblPrefixo.Font = New-Object System.Drawing.Font("Consolas", 14, [System.Drawing.FontStyle]::Bold)
    $lblPrefixo.ForeColor = $script:Grafite
    $lblPrefixo.Location = New-Object System.Drawing.Point(30, (85 + $yBase))
    $lblPrefixo.AutoSize = $true
    $dlg.Controls.Add($lblPrefixo)

    $txtNome = New-Object System.Windows.Forms.TextBox
    $txtNome.Font = New-Object System.Drawing.Font("Consolas", 14)
    $txtNome.Location = New-Object System.Drawing.Point(70, (82 + $yBase))
    $txtNome.Size = New-Object System.Drawing.Size(350, 32)
    $dlg.Controls.Add($txtNome)

    $lblAjudaFormato = New-Object System.Windows.Forms.Label
    $lblAjudaFormato.Text = "Formato: AREA-ATAC ou AREA-LJxx (xx = numero da loja, 2 digitos)"
    $lblAjudaFormato.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblAjudaFormato.ForeColor = $script:Claro
    $lblAjudaFormato.Location = New-Object System.Drawing.Point(70, (117 + $yBase))
    $lblAjudaFormato.AutoSize = $true
    $dlg.Controls.Add($lblAjudaFormato)

    $lblPreview = New-Object System.Windows.Forms.Label
    $lblPreview.Font = New-Object System.Drawing.Font("Consolas", 11)
    $lblPreview.ForeColor = $script:Eyebrow
    $lblPreview.Location = New-Object System.Drawing.Point(30, (146 + $yBase))
    $lblPreview.Size = New-Object System.Drawing.Size(390, 24)
    $dlg.Controls.Add($lblPreview)

    $msgDlg = New-Object System.Windows.Forms.Label
    $msgDlg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $msgDlg.ForeColor = $script:Vinho
    $msgDlg.Location = New-Object System.Drawing.Point(30, (222 + $yBase))
    $msgDlg.Size = New-Object System.Drawing.Size(390, 40)
    $dlg.Controls.Add($msgDlg)

    $script:NomeFinalValido = $null

    function Atualizar-Preview {
        $texto = $txtNome.Text.Trim()
        $partes = $texto -split '-', 2
        $area   = $partes[0]
        $sufixo = if ($partes.Count -gt 1) { $partes[1].ToUpper() } else { $null }

        $script:NomeFinalValido = $null

        if (-not $area) {
            $lblPreview.ForeColor = $script:Claro
            $lblPreview.Text = "Digite a area, depois um hifen e ATAC ou LJxx."
            return
        }
        if ($null -eq $sufixo) {
            $lblPreview.ForeColor = $script:Claro
            $lblPreview.Text = "KY-$area-..."
            return
        }
        if ($sufixo -eq "ATAC" -or $sufixo -match '^LJ\d{2}$') {
            $nomeFinal = "KY-$area-$sufixo"
            $lblPreview.ForeColor = $script:Verde
            $lblPreview.Text = "Nome final: $nomeFinal"
            $script:NomeFinalValido = $nomeFinal
            return
        }
        if ("ATAC".StartsWith($sufixo) -or $sufixo -match '^LJ\d{0,1}$') {
            $lblPreview.ForeColor = $script:Claro
            $lblPreview.Text = "KY-$area-$sufixo..."
            return
        }
        $lblPreview.ForeColor = $script:Vinho
        $lblPreview.Text = "Sufixo invalido - use ATAC ou LJxx (ex: LJ01)."
    }
    $txtNome.Add_TextChanged({ Atualizar-Preview })
    Atualizar-Preview

    $btnCancelar = New-Object System.Windows.Forms.Button
    $btnCancelar.Text = "Cancelar"
    $btnCancelar.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $btnCancelar.Size = New-Object System.Drawing.Size(140, 50)
    $btnCancelar.Location = New-Object System.Drawing.Point(30, (280 + $yBase))
    $btnCancelar.FlatStyle = "Flat"
    $btnCancelar.BackColor = [System.Drawing.Color]::White
    $btnCancelar.ForeColor = $script:Vinho
    $btnCancelar.FlatAppearance.BorderSize = 1
    $btnCancelar.FlatAppearance.BorderColor = $script:Vinho
    $btnCancelar.FlatAppearance.MouseOverBackColor = $script:VinhoBg
    $btnCancelar.Add_Click({ $dlg.DialogResult = "Cancel"; $dlg.Close() })
    $dlg.Controls.Add($btnCancelar)

    $btnConfirmar = New-Object System.Windows.Forms.Button
    $btnConfirmar.Text = "Instalar"
    $btnConfirmar.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $btnConfirmar.Size = New-Object System.Drawing.Size(180, 50)
    $btnConfirmar.Location = New-Object System.Drawing.Point(210, (280 + $yBase))
    $btnConfirmar.FlatStyle = "Flat"
    $btnConfirmar.FlatAppearance.BorderSize = 0
    $btnConfirmar.BackColor = $script:Azul
    $btnConfirmar.ForeColor = [System.Drawing.Color]::White
    $btnConfirmar.FlatAppearance.MouseOverBackColor = $script:AzulH
    $btnConfirmar.FlatAppearance.MouseDownBackColor = $script:AzulH
    $dlg.Controls.Add($btnConfirmar)
    $dlg.AcceptButton = $btnConfirmar

    $btnConfirmar.Add_Click({
        if ($script:DlgConcluido) { $dlg.Close(); return }

        $ipFinal = if ($Manual) { $txtIp.Text.Trim() } else { $ipAlvo }
        if ($Manual -and -not $ipFinal) {
            $msgDlg.ForeColor = $script:Vinho
            $msgDlg.Text = "Informe o IP da impressora."
            $txtIp.Focus()
            return
        }

        if (-not $script:NomeFinalValido) {
            $msgDlg.ForeColor = $script:Vinho
            $msgDlg.Text = "Complete o nome no formato KY-AREA-ATAC ou KY-AREA-LJxx."
            $txtNome.Focus()
            return
        }
        $nomeFinal = $script:NomeFinalValido

        $btnConfirmar.Enabled = $false
        $btnConfirmar.Text = "Aguarde..."
        $btnCancelar.Enabled = $false
        $msgDlg.ForeColor = $script:Grafite
        $msgDlg.Text = "Instalando $nomeFinal..."
        [System.Windows.Forms.Application]::DoEvents()

        try {
            $driverInfo = $null
            if ($Manual) {
                if ($script:DriverAutoDetectado) {
                    $driverInfo = $script:DriverAutoDetectado
                }
                elseif ($cmbDriver.Visible -and $cmbDriver.SelectedIndex -ge 0) {
                    $nomeDriverEscolhido = $cmbDriver.SelectedItem.ToString()
                    $driverInfo = (Get-ListaDrivers $script:InfFiles) | Where-Object { $_.DriverName -eq $nomeDriverEscolhido } | Select-Object -First 1
                }
                else {
                    throw "Clique em 'Detectar (SNMP)' primeiro, ou selecione o driver manualmente."
                }
            }
            else {
                if (-not $script:ModeloDetectado) { throw "Modelo nao identificado." }
                $coreModel = Get-CoreModel $script:ModeloDetectado
                $driverInfo = Find-DriverInfo $script:InfFiles $coreModel
            }
            if (-not $driverInfo) { throw "Driver nao localizado no pacote INF." }

            # TopMost atrapalha o printui (mesmo motivo do lote) - abaixa durante a instalacao
            $dlgTopMostAnterior = $dlg.TopMost
            $formTopMostAnterior = $Form.TopMost
            $dlg.TopMost = $false
            $Form.TopMost = $false
            try {
                $instalou = Install-ImpressoraKyocera -IpAlvo $ipFinal -DriverInfo $driverInfo -NomeFinal $nomeFinal
            }
            finally {
                $dlg.TopMost = $dlgTopMostAnterior
                $Form.TopMost = $formTopMostAnterior
            }

            $script:DlgConcluido = $true
            $msgDlg.ForeColor = $script:Verde
            if ($instalou) {
                $msgDlg.Text = "Impressora '$nomeFinal' instalada com sucesso."
            } else {
                $msgDlg.Text = "Impressora '$nomeFinal' ja existia (mesmo nome ou IP) - nada a fazer."
            }
            $txtNome.Enabled = $false
            if ($Manual) { $txtIp.Enabled = $false; $cmbDriver.Enabled = $false; $btnDetectar.Enabled = $false }
            $btnConfirmar.Text = "Concluir"
            $btnConfirmar.Enabled = $false
            [System.Windows.Forms.Application]::DoEvents()

            for ($k = 0; $k -lt 25; $k++) {
                Start-Sleep -Milliseconds 100
                [System.Windows.Forms.Application]::DoEvents()
            }
            $dlg.DialogResult = "OK"
            $dlg.Close()
        }
        catch {
            $msgDlg.ForeColor = $script:Vinho
            $msgDlg.Text = "Falha: $($_.Exception.Message)"
            $btnConfirmar.Enabled = $true
            $btnConfirmar.Text = "Tentar novamente"
            $btnCancelar.Enabled = $true
        }
    })

    if ($Manual) { $dlg.Add_Shown({ $txtIp.Focus() }) }
    else { $dlg.Add_Shown({ $txtNome.Focus() }) }
    $dlg.ShowDialog($Form) | Out-Null
    $dlg.Dispose()
}

# ============================================================ ADICIONAR MANUALMENTE
$btnManual.Add_Click({
    if (-not $script:InfFiles) {
        $btnManual.Enabled = $false
        $msg.ForeColor = $script:Grafite
        $msg.Text = "Preparando drivers..."
        [System.Windows.Forms.Application]::DoEvents()
        try { $script:InfFiles = Preparar-Drivers }
        catch {
            $msg.ForeColor = $script:Vinho
            $msg.Text = "Falha ao preparar drivers: $($_.Exception.Message)"
            $btnManual.Enabled = $true
            return
        }
        $btnManual.Enabled = $true
        $msg.ForeColor = $script:Grafite
        $msg.Text = 'Clique em "Escanear rede" para localizar as impressoras.'
    }
    Show-DialogNome $null $null -Manual
})

$Form.ShowDialog() | Out-Null
$Form.Dispose()
