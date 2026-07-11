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

#Instala UVNC
Write-Host "--- Verificando Instalacao do UltraVNC ---" -ForegroundColor Cyan

$pastaVnc = "C:\Program Files\uvnc bvba\UltraVNC"
$exeVnc = Join-Path $pastaVnc "winvnc.exe"

# TRAVA: Verifica se o executável principal já existe na pasta de destino
if (Test-Path -LiteralPath $exeVnc) {
    Write-Host "UltraVNC ja instalado e configurado nesta maquina. Pulando instalacao." -ForegroundColor Green
}
else {
    Write-Host "UltraVNC nao encontrado. Iniciando instalacao..." -ForegroundColor Yellow

    $urlVnc = "http://192.168.12.223/uploads/InstaladorWindows/ultravnc.msi"
    $destinoVnc = "$env:TEMP\ultravnc.msi"

    try {
        Write-Host "Baixando o UltraVNC (MSI)..."
        Invoke-WebRequest -Uri $urlVnc -OutFile $destinoVnc -UseBasicParsing -ErrorAction Stop
        
        Write-Host "Executando instalacao silenciosa..."
        # Deixamos ele instalar o padrao sem reclamar para nao falhar
        $argumentosMsi = "/i `"$destinoVnc`" /qn /norestart ALLUSERS=1"
        Start-Process -FilePath "msiexec.exe" -ArgumentList $argumentosMsi -Wait -NoNewWindow
        
        if (Test-Path -LiteralPath $exeVnc) {
            Write-Host "Instalacao base concluida. Removendo Viewer e Repeater..." -ForegroundColor Yellow
            
            # A Mágica: Caça e deleta qualquer executável que seja do Viewer ou do Repeater
            Get-ChildItem -Path $pastaVnc -Filter "*viewer*.exe" -ErrorAction SilentlyContinue | Remove-Item -Force
            Get-ChildItem -Path $pastaVnc -Filter "*repeater*.exe" -ErrorAction SilentlyContinue | Remove-Item -Force
            
            Write-Host "Lixo removido! Configurando o servico do VNC Server..." -ForegroundColor Green
            
            # Forca o registro do VNC no Windows Services
            Start-Process -FilePath $exeVnc -ArgumentList "-install" -Wait -NoNewWindow
            
            # Inicia o servico
            Start-Service -Name "uvnc_service" -ErrorAction SilentlyContinue
            
            Write-Host "Servico do UltraVNC registrado e iniciado com sucesso!" -ForegroundColor Green
        } else {
            Write-Host "ERRO: O msiexec rodou, mas o VNC nao foi encontrado na pasta." -ForegroundColor Red
        }
        
        Write-Host "Limpando instalador temporario..."
        Remove-Item -Path $destinoVnc -Force
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
