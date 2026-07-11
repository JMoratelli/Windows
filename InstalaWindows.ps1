# Este script busca os instaladores nas unidades de disco e inicia a instalação
# de forma sequencial, garantindo que o usuário veja e interaja com os prompts de cada instalador.

$SoftwareList = @(
    "ninite.exe",
    "ultravnc.msi",
    "epskit_x64.exe"
)

Write-Host "--- Iniciando o Instalador Sequencial de Softwares ---"
Write-Host "O script irá buscar cada arquivo e executar sua instalação. Você precisará acompanhar os prompts de cada instalador."
Write-Host ""

# Loop para processar cada software na lista
foreach ($SoftwareFile in $SoftwareList) {
    Write-Host ">> Procurando por: $($SoftwareFile)..."
    $FoundPath = $null

    # Itera sobre todas as unidades de disco disponíveis (C:, D:, E:, etc.)
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        # Tenta construir e resolver o caminho para o arquivo na unidade atual.
        # O Resolve-Path é usado com -ErrorAction SilentlyContinue para ignorar erros de drives não prontos ou arquivos inexistentes.
        try {
            $PathToCheck = Join-Path -Path $drive.RootDirectory -ChildPath $SoftwareFile
            $ResolvedPaths = Resolve-Path -Path $PathToCheck -ErrorAction SilentlyContinue

            if ($ResolvedPaths) {
                # Se o caminho foi resolvido (arquivo encontrado), armazena e interrompe a busca por unidades.
                $FoundPath = $ResolvedPaths.Path
                break
            }
        }
        catch {
            # Silencia erros como 'Caminho não encontrado'
        }
    }

    if ($FoundPath) {
        Write-Host "   [SUCESSO] Instalador encontrado em: $($FoundPath)"
        Write-Host "   Iniciando a instalação. Por favor, siga as instruções na janela que será aberta."

        # Inicia o processo do instalador e espera (o -Wait) até que ele seja fechado (pelo usuário ou automaticamente).
        # Nenhum parâmetro de modo silencioso é adicionado, forçando a exibição da GUI do instalador.
        Start-Process -FilePath $FoundPath -Wait

        Write-Host "   Instalação de $($SoftwareFile) concluída ou encerrada. Movendo para o próximo software."
    }
    else {
        # Emite um aviso se o arquivo não foi encontrado após verificar todas as unidades.
        Write-Warning "   [AVISO] Não foi possível encontrar o instalador '$($SoftwareFile)' em nenhuma unidade de disco."
    }
    Write-Host "--------------------------------------------------------"
}
#Atualiza Winget Sources
winget source update

# Instala OnlyOffice
winget install -e --id ONLYOFFICE.DesktopEditors --silent --scope machine --accept-package-agreements --accept-source-agreements

winget install -e --id Skillbrains.Lightshot --silent --scope machine --accept-package-agreements --accept-source-agreements


Write-Host "Processo de verificação e instalação de todos os softwares concluído."
