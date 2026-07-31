<#
    Instalador-Estacao.ps1
    Preparacao de estacao Windows 11 - Machadao Corp
    Interface WPF autocontida. Desenvolvido por @JJMoratelli
#>

# ---------------------------------------------------------------- CONSOLE OCULTO
# Esconde a janela preta do PowerShell: se o tecnico fechar ela, derruba a
# instalacao no meio. Fica so a interface.
Add-Type -Namespace Nativo -Name Janela -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[DllImport("user32.dll")]   public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@ -ErrorAction SilentlyContinue

try {
    $hConsole = [Nativo.Janela]::GetConsoleWindow()
    if ($hConsole -ne [System.IntPtr]::Zero) {
        [Nativo.Janela]::ShowWindow($hConsole, 0) | Out-Null   # 0 = SW_HIDE
    }
}
catch { }   # no ISE nao existe console, e tudo bem

# ---------------------------------------------------------------- ELEVACAO
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$ident = [Security.Principal.WindowsIdentity]::GetCurrent()
$princ = New-Object Security.Principal.WindowsPrincipal($ident)
if (-not $princ.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($PSCommandPath) {
        Start-Process -FilePath "powershell.exe" -Verb RunAs `
            -WindowStyle Hidden `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
        return
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Execute este script como Administrador.", "Instalador de estacao") | Out-Null
        return
    }
}

$BaseUrl = "http://192.168.12.223/uploads/InstaladorWindows/"

# ---------------------------------------------------------------- CATALOGO
# Base: sempre instalado. Opcional: escolha do tecnico.
$Base = @(
    @{ Id='bitdefender'; Nome='BitDefender Endpoint';            Info='setupdownloader do servidor local' }
    @{ Id='7zip';        Nome='7-Zip';                            Info='7zip.7zip' }
    @{ Id='chrome';      Nome='Google Chrome';                    Info='MSI corporativo, escopo maquina' }
    @{ Id='corretto';    Nome='Amazon Corretto 8 (JDK)';          Info='Amazon.Corretto.8.JDK' }
    @{ Id='vcredist';    Nome='Redistribuiveis VC++ 2005 a 2015+';Info='x86 e x64, 12 pacotes' }
    @{ Id='dotnet';      Nome='.NET Desktop Runtime 6 e 8';       Info='x64, escopo maquina' }
    @{ Id='onlyoffice';  Nome='ONLYOFFICE Desktop';               Info='ONLYOFFICE.DesktopEditors' }
    @{ Id='notepadpp';   Nome='Notepad++';                        Info='Notepad++.Notepad++' }
    @{ Id='sumatra';     Nome='Sumatra PDF';                      Info='SumatraPDF.SumatraPDF' }
    @{ Id='lightshot';   Nome='Lightshot';                        Info='Skillbrains.Lightshot' }
    @{ Id='vlc';         Nome='VLC media player';                 Info='VideoLAN.VLC' }
    @{ Id='uvnc';        Nome='UltraVNC (server)';                Info='Servico uvnc_service + driver de video' }
)

$Opcional = @(
    @{ Id='gonnect';     Nome='GOnnect (SIP)';       Info='Ramal e configurado no proximo login';  Padrao=$true  }
    @{ Id='impressoras'; Nome='Impressoras Kyocera'; Info='Detecta o modelo por SNMP';             Padrao=$false }
)

$VcRedists = @(
    'Microsoft.VCRedist.2005.x86','Microsoft.VCRedist.2005.x64'
    'Microsoft.VCRedist.2008.x86','Microsoft.VCRedist.2008.x64'
    'Microsoft.VCRedist.2010.x86','Microsoft.VCRedist.2010.x64'
    'Microsoft.VCRedist.2012.x86','Microsoft.VCRedist.2012.x64'
    'Microsoft.VCRedist.2013.x86','Microsoft.VCRedist.2013.x64'
    'Microsoft.VCRedist.2015+.x86','Microsoft.VCRedist.2015+.x64'
)
$DotNetPkgs = @('Microsoft.DotNet.DesktopRuntime.6','Microsoft.DotNet.DesktopRuntime.8')

# ---------------------------------------------------------------- XAML
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Preparacao de estacao" Height="700" Width="1000"
        WindowStartupLocation="CenterScreen" Background="#EDEFF2"
        FontFamily="Segoe UI" ResizeMode="CanResize" MinWidth="900" MinHeight="620">
  <Window.Resources>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="White"/>
      <Setter Property="CornerRadius" Value="10"/>
      <Setter Property="Padding" Value="16"/>
      <Setter Property="BorderBrush" Value="#DDE1E6"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>
    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Background" Value="#1A5FB4"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="22,10"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="8"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#154C90"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Background" Value="#A9B2BD"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource Primary}">
      <Setter Property="Background" Value="#5B6672"/>
      <Setter Property="Padding" Value="14,8"/>
      <Setter Property="FontSize" Value="13"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="#12161C" Padding="22,16">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0">
          <TextBlock Text="M A C H A D A O   C O R P" Foreground="#7C93AE"
                     FontFamily="Consolas" FontSize="11"/>
          <TextBlock Text="Preparacao de estacao" Foreground="White" FontSize="24" FontWeight="Light"/>
        </StackPanel>
        <StackPanel Grid.Column="1" VerticalAlignment="Center" HorizontalAlignment="Right">
          <TextBlock x:Name="LblHost" Foreground="#C9D3DE" FontSize="12" HorizontalAlignment="Right"/>
          <TextBlock x:Name="LblOs"   Foreground="#7C93AE" FontSize="11" HorizontalAlignment="Right"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Row="1" Margin="18">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="440"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto" Margin="0,0,14,0">
        <StackPanel>

          <Border Style="{StaticResource Card}">
            <StackPanel>
              <Grid Margin="0,0,0,4">
                <TextBlock Text="Opcionais" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center"/>
                <Border Background="#FDF0E3" CornerRadius="4" Padding="7,2" HorizontalAlignment="Right">
                  <TextBlock Text="escolha do tecnico" FontSize="11" Foreground="#A8480A"/>
                </Border>
              </Grid>
              <TextBlock Text="Marque o que esta estacao precisa antes de comecar."
                         Foreground="#6B7580" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,10"/>
              <StackPanel x:Name="OptPanel"/>
            </StackPanel>
          </Border>

          <Border x:Name="PrintersCard" Style="{StaticResource Card}" Margin="0,14,0,0" Visibility="Collapsed">
            <StackPanel>
              <Grid Margin="0,0,0,8">
                <TextBlock Text="Impressoras Kyocera" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center"/>
                <Button x:Name="BtnAddPrinter" Content="+ Adicionar" Style="{StaticResource Ghost}"
                        HorizontalAlignment="Right"/>
              </Grid>
              <TextBlock Text="O modelo e o driver sao detectados por SNMP." Foreground="#6B7580"
                         FontSize="12" Margin="0,0,0,10"/>
              <StackPanel x:Name="PrintersPanel"/>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Card}" Margin="0,14,0,0">
            <StackPanel>
              <Grid Margin="0,0,0,4">
                <TextBlock Text="Base do sistema" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center"/>
                <Border Background="#EAF1FB" CornerRadius="4" Padding="7,2" HorizontalAlignment="Right">
                  <TextBlock Text="sempre instalado" FontSize="11" Foreground="#1A5FB4"/>
                </Border>
              </Grid>
              <TextBlock Text="Instalado em escopo de maquina, disponivel para qualquer usuario do dominio."
                         Foreground="#6B7580" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,10"/>
              <StackPanel x:Name="BasePanel"/>
            </StackPanel>
          </Border>

        </StackPanel>
      </ScrollViewer>

      <Border Grid.Column="1" CornerRadius="10" Background="#0B1020" Padding="4">
        <RichTextBox x:Name="LogBox" Background="Transparent" Foreground="#CBD5E1"
                     FontFamily="Consolas" FontSize="12.5" BorderThickness="0"
                     IsReadOnly="True" VerticalScrollBarVisibility="Auto"
                     HorizontalScrollBarVisibility="Disabled"/>
      </Border>
    </Grid>

    <Border Grid.Row="2" Background="White" BorderBrush="#DDE1E6" BorderThickness="0,1,0,0" Padding="18,12">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" VerticalAlignment="Center" Margin="0,0,20,0">
          <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
            <Grid x:Name="Spinner" Width="16" Height="16" Margin="0,0,9,0"
                  Visibility="Collapsed" RenderTransformOrigin="0.5,0.5">
              <Grid.RenderTransform>
                <RotateTransform Angle="0"/>
              </Grid.RenderTransform>
              <Ellipse Width="16" Height="16" Stroke="#DCE1E7" StrokeThickness="2.5"/>
              <Ellipse Width="16" Height="16" Stroke="#1A5FB4" StrokeThickness="2.5"
                       StrokeDashArray="11 40" StrokeDashCap="Round"/>
              <Grid.Triggers>
                <EventTrigger RoutedEvent="Grid.Loaded">
                  <BeginStoryboard>
                    <Storyboard RepeatBehavior="Forever">
                      <DoubleAnimation
                          Storyboard.TargetProperty="(UIElement.RenderTransform).(RotateTransform.Angle)"
                          From="0" To="360" Duration="0:0:0.9"/>
                    </Storyboard>
                  </BeginStoryboard>
                </EventTrigger>
              </Grid.Triggers>
            </Grid>
            <TextBlock x:Name="LblStatus" Text="Pronto." FontSize="13" Foreground="#3A4450"
                       VerticalAlignment="Center"/>
          </StackPanel>
          <ProgressBar x:Name="Bar" Height="6" Minimum="0" Maximum="100" Value="0"
                       Foreground="#1A5FB4" Background="#E4E8EC" BorderThickness="0"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="BtnRun" Content="Preparar estacao" Style="{StaticResource Primary}"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid x:Name="DoneOverlay" Grid.RowSpan="3" Visibility="Collapsed">
      <Rectangle Fill="#12161C" Opacity="0.72"/>
      <Border Background="White" CornerRadius="12" Padding="34,30" Width="420"
              HorizontalAlignment="Center" VerticalAlignment="Center">
        <StackPanel>
          <TextBlock x:Name="DoneTitle" Text="Estacao preparada" FontSize="22" FontWeight="Light"
                     Foreground="#12161C" HorizontalAlignment="Center"/>
          <TextBlock x:Name="DoneMsg" Text="Todos os itens foram processados."
                     FontSize="13" Foreground="#5B6672" TextWrapping="Wrap"
                     TextAlignment="Center" Margin="0,10,0,0"/>
          <TextBlock x:Name="DoneCount" Text="Fechando em 30 s" FontFamily="Consolas" FontSize="12"
                     Foreground="#9AA4AF" HorizontalAlignment="Center" Margin="0,18,0,16"/>
          <Button x:Name="BtnDone" Content="Concluir agora" Style="{StaticResource Primary}"
                  HorizontalAlignment="Center"/>
        </StackPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
try {
    $win = [Windows.Markup.XamlReader]::Load($reader)
}
catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Falha ao montar a interface:`r`n`r`n$($_.Exception.Message)",
        "Instalador de estacao") | Out-Null
    return
}

$BasePanel     = $win.FindName("BasePanel")
$OptPanel      = $win.FindName("OptPanel")
$PrintersCard  = $win.FindName("PrintersCard")
$PrintersPanel = $win.FindName("PrintersPanel")
$BtnAddPrinter = $win.FindName("BtnAddPrinter")
$BtnRun        = $win.FindName("BtnRun")
$LogBox        = $win.FindName("LogBox")
$Bar           = $win.FindName("Bar")
$LblStatus     = $win.FindName("LblStatus")
$Spinner       = $win.FindName("Spinner")
$DoneOverlay   = $win.FindName("DoneOverlay")
$DoneTitle     = $win.FindName("DoneTitle")
$DoneMsg       = $win.FindName("DoneMsg")
$DoneCount     = $win.FindName("DoneCount")
$BtnDone       = $win.FindName("BtnDone")

$win.FindName("LblHost").Text = "$env:COMPUTERNAME  /  $env:USERNAME"
$win.FindName("LblOs").Text   = (Get-CimInstance Win32_OperatingSystem).Caption

# ---------------------------------------------------------------- LINHAS DA UI
$Checks = @{}
$Status = @{}

function New-StatusText {
    $st = New-Object Windows.Controls.TextBlock
    $st.Text = "aguardando"
    $st.FontSize = 11
    $st.FontFamily = "Consolas"
    $st.Foreground = "#9AA4AF"
    $st.VerticalAlignment = "Center"
    $st.Margin = "8,0,0,0"
    return $st
}
function New-Row($panel, $left, $status) {
    $g = New-Object Windows.Controls.Grid
    $g.Margin = "0,4,0,4"
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = "*"
    $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = "Auto"
    $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
    [Windows.Controls.Grid]::SetColumn($left,0)
    [Windows.Controls.Grid]::SetColumn($status,1)
    $g.Children.Add($left) | Out-Null
    $g.Children.Add($status) | Out-Null
    $panel.Children.Add($g) | Out-Null
}
function New-Info($texto, $recuo) {
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $texto
    $t.FontSize = 11.5
    $t.Foreground = "#6B7580"
    $t.Margin = "$recuo,0,0,0"
    $t.TextWrapping = "Wrap"
    return $t
}

foreach ($t in $Base) {
    $sp = New-Object Windows.Controls.StackPanel
    $ttl = New-Object Windows.Controls.TextBlock
    $ttl.Text = $t.Nome
    $ttl.FontSize = 14
    $sp.Children.Add($ttl) | Out-Null
    $sp.Children.Add((New-Info $t.Info 0)) | Out-Null
    $st = New-StatusText
    New-Row $BasePanel $sp $st
    $Status[$t.Id] = $st
}

foreach ($t in $Opcional) {
    $sp = New-Object Windows.Controls.StackPanel
    $cb = New-Object Windows.Controls.CheckBox
    $cb.Content = $t.Nome
    $cb.IsChecked = $t.Padrao
    $sp.Children.Add($cb) | Out-Null
    $sp.Children.Add((New-Info $t.Info 24)) | Out-Null
    $st = New-StatusText
    New-Row $OptPanel $sp $st
    $Checks[$t.Id] = $cb
    $Status[$t.Id] = $st
}

$togglePrinters = {
    if ($Checks['impressoras'].IsChecked) {
        $PrintersCard.Visibility = "Visible"
        # ja abre com uma linha pronta, sem obrigar um clique extra no "+"
        if ($PrinterRows.Count -eq 0) { Add-PrinterRow }
    } else {
        $PrintersCard.Visibility = "Collapsed"
    }
}
$Checks['impressoras'].Add_Checked($togglePrinters)
$Checks['impressoras'].Add_Unchecked($togglePrinters)

# ---------------------------------------------------------------- IMPRESSORAS
$PrinterRows = New-Object System.Collections.ArrayList

function Add-PrinterRow {
    $g = New-Object Windows.Controls.Grid
    $g.Margin = "0,0,0,8"
    foreach ($w in @("120","*","Auto")) {
        $c = New-Object Windows.Controls.ColumnDefinition
        $c.Width = $w
        $g.ColumnDefinitions.Add($c)
    }
    $ip = New-Object Windows.Controls.TextBox
    $ip.Height=30; $ip.Padding="6,4"; $ip.Margin="0,0,8,0"; $ip.VerticalContentAlignment="Center"
    $ip.ToolTip = "IP da impressora"
    $nm = New-Object Windows.Controls.TextBox
    $nm.Height=30; $nm.Padding="6,4"; $nm.Margin="0,0,8,0"; $nm.VerticalContentAlignment="Center"
    $nm.ToolTip = "Nome de exibicao"
    $rm = New-Object Windows.Controls.Button
    $rm.Content="x"; $rm.Width=30; $rm.Height=30; $rm.Background="#E4E8EC"; $rm.BorderThickness=0
    $rm.Cursor="Hand"; $rm.ToolTip="Remover"

    [Windows.Controls.Grid]::SetColumn($ip,0)
    [Windows.Controls.Grid]::SetColumn($nm,1)
    [Windows.Controls.Grid]::SetColumn($rm,2)
    $g.Children.Add($ip)|Out-Null; $g.Children.Add($nm)|Out-Null; $g.Children.Add($rm)|Out-Null

    $entry = [pscustomobject]@{ Grid=$g; Ip=$ip; Nome=$nm }
    $rm.Add_Click({
        $PrintersPanel.Children.Remove($g)
        $PrinterRows.Remove($entry)
    }.GetNewClosure())

    $PrintersPanel.Children.Add($g) | Out-Null
    $PrinterRows.Add($entry) | Out-Null
    $ip.Focus() | Out-Null
}

$hdr = New-Object Windows.Controls.Grid
foreach ($w in @("120","*","Auto")) {
    $c = New-Object Windows.Controls.ColumnDefinition; $c.Width = $w; $hdr.ColumnDefinitions.Add($c)
}
$h1 = New-Object Windows.Controls.TextBlock; $h1.Text="IP";   $h1.FontSize=11; $h1.Foreground="#6B7580"
$h2 = New-Object Windows.Controls.TextBlock; $h2.Text="Nome"; $h2.FontSize=11; $h2.Foreground="#6B7580"
[Windows.Controls.Grid]::SetColumn($h1,0); [Windows.Controls.Grid]::SetColumn($h2,1)
$hdr.Children.Add($h1)|Out-Null; $hdr.Children.Add($h2)|Out-Null
$PrintersPanel.Children.Add($hdr)|Out-Null

$BtnAddPrinter.Add_Click({ Add-PrinterRow })

# ---------------------------------------------------------------- ESTADO COMPARTILHADO
$sync = [hashtable]::Synchronized(@{})
$sync.Win        = $win
$sync.Log        = $LogBox
$sync.Bar        = $Bar
$sync.Lbl        = $LblStatus
$sync.Status     = $Status
$sync.BaseUrl    = $BaseUrl
$sync.BtnRun     = $BtnRun
$sync.VcRedists  = $VcRedists
$sync.DotNetPkgs = $DotNetPkgs

function Write-Log([string]$msg, [string]$hex = "#CBD5E1") {
    $p = New-Object Windows.Documents.Paragraph
    $p.Margin = "0"
    $r = New-Object Windows.Documents.Run($msg)
    $r.Foreground = (New-Object Windows.Media.BrushConverter).ConvertFromString($hex)
    $p.Inlines.Add($r)
    $LogBox.Document.Blocks.Add($p)
    $LogBox.ScrollToEnd()
}
function Set-Status($id, $txt, $hex) {
    if (-not $Status.ContainsKey($id)) { return }
    $Status[$id].Text = $txt
    $Status[$id].Foreground = (New-Object Windows.Media.BrushConverter).ConvertFromString($hex)
}

Write-Log "Estacao $env:COMPUTERNAME pronta para preparacao." "#7C93AE"
Write-Log ""

# ---------------------------------------------------------------- PRE-CHECAGEM
$UninstallPaths = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                  "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
$Instalados = @(Get-ItemProperty -Path $UninstallPaths -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName } | Select-Object -ExpandProperty DisplayName)

function Test-Nome($pattern) { [bool]($Instalados | Where-Object { $_ -like $pattern }) }

# Chrome pode estar por maquina ou por usuario, entao o registro HKLM nao basta
function Test-Chrome {
    $exes = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )
    foreach ($e in $exes) { if (Test-Path -LiteralPath $e) { return $true } }

    foreach ($perfil in (Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath "$($perfil.FullName)\AppData\Local\Google\Chrome\Application\chrome.exe") {
            return $true
        }
    }

    $chaves = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
        "HKLM:\SOFTWARE\WOW6432Node\Google\Update\Clients\{8A69D345-D564-463c-AFF1-A69D9E530F96}"
    )
    foreach ($k in $chaves) { if (Test-Path $k) { return $true } }
    return $false
}

$Presentes = @{}
function Mark-Ok($id) { Set-Status $id "ja instalado" "#0A6F66"; $Presentes[$id] = $true }

if ((Get-Process -Name "EPSecurityConsole" -ErrorAction SilentlyContinue) -or
    (Test-Nome "*Bitdefender*") -or
    (Test-Path "C:\Program Files\Bitdefender\Endpoint Security")) { Mark-Ok 'bitdefender' }
if (Test-Path "C:\Program Files\uvnc bvba\UltraVNC\winvnc.exe") { Mark-Ok 'uvnc' }
if (Test-Nome "*GOnnect*")      { Mark-Ok 'gonnect'; $Checks['gonnect'].IsChecked = $false }
if (Test-Nome "7-Zip*")         { Mark-Ok '7zip' }
if (Test-Chrome)                { Mark-Ok 'chrome' }
if (Test-Nome "Amazon Corretto*8*") { Mark-Ok 'corretto' }
if (Test-Nome "*ONLYOFFICE*")   { Mark-Ok 'onlyoffice' }
if (Test-Nome "*Lightshot*")    { Mark-Ok 'lightshot' }
if (Test-Nome "Notepad++*")     { Mark-Ok 'notepadpp' }
if (Test-Nome "*Sumatra*")      { Mark-Ok 'sumatra' }
if (Test-Nome "VLC media player*") { Mark-Ok 'vlc' }

$qtdVc = @($Instalados | Where-Object { $_ -like "Microsoft Visual C++*Redistributable*" }).Count
if ($qtdVc -ge 12) { Mark-Ok 'vcredist' } elseif ($qtdVc -gt 0) { Set-Status 'vcredist' "$qtdVc de 12" "#8A5A00" }

$temNet6 = Test-Nome "Microsoft Windows Desktop Runtime - 6.*x64*"
$temNet8 = Test-Nome "Microsoft Windows Desktop Runtime - 8.*x64*"
if ($temNet6 -and $temNet8) { Mark-Ok 'dotnet' } elseif ($temNet6 -or $temNet8) { Set-Status 'dotnet' "parcial" "#8A5A00" }

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Log "AVISO: winget nao encontrado nesta maquina." "#F59E0B"
    Write-Log "Instale o App Installer pela Microsoft Store antes de continuar." "#F59E0B"
    Write-Log ""
}

$sync.Presentes = $Presentes
if ($Presentes.Count -gt 0) {
    Write-Log "$($Presentes.Count) item(ns) ja presentes nesta maquina serao pulados." "#0A6F66"
}

Write-Log "Clique em Preparar estacao para comecar." "#7C93AE"

# ---------------------------------------------------------------- WORKER
$worker = {

    function W([string]$m, [string]$hex = "#CBD5E1") {
        $sync.Win.Dispatcher.Invoke([action]{
            $p = New-Object Windows.Documents.Paragraph
            $p.Margin = "0"
            $r = New-Object Windows.Documents.Run($m)
            $r.Foreground = (New-Object Windows.Media.BrushConverter).ConvertFromString($hex)
            $p.Inlines.Add($r)
            $sync.Log.Document.Blocks.Add($p)
            $sync.Log.ScrollToEnd()
        })
    }
    function Head($m) { W ""; W ("-- " + $m) "#7C93AE" }
    function Ok($m)   { W ("   [ok] "   + $m) "#22C55E" }
    function Skip($m) { W ("   [ja] "   + $m) "#0A6F66" }
    function Err($m)  { W ("   [erro] " + $m) "#F87171" }
    function St($id,$t,$hex) {
        $sync.Win.Dispatcher.Invoke([action]{
            if ($sync.Status.ContainsKey($id)) {
                $sync.Status[$id].Text = $t
                $sync.Status[$id].Foreground = (New-Object Windows.Media.BrushConverter).ConvertFromString($hex)
            }
        })
    }
    function Prog($v,$txt) {
        $sync.Win.Dispatcher.Invoke([action]{
            $sync.Bar.Value = $v
            $sync.Lbl.Text = $txt
        })
    }

    # Confere no registro se o programa esta instalado neste momento
    function TemNoRegistro([string]$pattern) {
        $p = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
             "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        [bool](Get-ItemProperty -Path $p -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -like $pattern })
    }

    # Chrome pode estar por maquina ou por usuario
    function TemChrome {
        $exes = @(
            "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
        )
        foreach ($e in $exes) { if (Test-Path -LiteralPath $e) { return $true } }
        foreach ($perfil in (Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue)) {
            if (Test-Path -LiteralPath "$($perfil.FullName)\AppData\Local\Google\Chrome\Application\chrome.exe") {
                return $true
            }
        }
        $chaves = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
            "HKLM:\SOFTWARE\WOW6432Node\Google\Update\Clients\{8A69D345-D564-463c-AFF1-A69D9E530F96}"
        )
        foreach ($k in $chaves) { if (Test-Path $k) { return $true } }
        return $false
    }

    # winget com tratamento de "ja instalado" e fallback de escopo
    function Wg([string]$pkg, [string]$Confere, [switch]$SemEscopoSeFalhar) {
        if ($Confere -and (TemNoRegistro $Confere)) {
            Skip "$pkg (ja presente)"
            return $true
        }

        $comuns = @('-e','--id',$pkg,'--silent','--accept-package-agreements',
                    '--accept-source-agreements','--disable-interactivity')
        $saida = & winget install @comuns --scope machine 2>&1
        $code  = $LASTEXITCODE
        $texto = ($saida | Out-String)

        if ($code -ne 0 -and $SemEscopoSeFalhar) {
            W "   $pkg : escopo de maquina recusado, tentando por usuario..." "#93A5B8"
            $saida = & winget install @comuns 2>&1
            $code  = $LASTEXITCODE
            $texto = ($saida | Out-String)
        }

        if ($code -eq 0)        { Ok  $pkg; return $true }
        if ($code -eq 3010)     { Ok "$pkg (requer reinicializacao)"; return $true }

        # Falhou: se o programa esta no registro, era so redundancia
        if ($Confere -and (TemNoRegistro $Confere)) {
            Skip "$pkg (ja estava instalado, winget retornou $code)"
            return $true
        }

        $primeira = ($texto -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
        Err "$pkg : codigo $code $primeira"
        return $false
    }

    $total = $sync.Jobs.Count
    $i = 0
    $totalFalhas = 0

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Prog 0 "Atualizando fontes do winget..."
        W "-- Fontes do winget" "#7C93AE"
        winget source update --disable-interactivity 2>&1 | Out-Null
        Ok "fontes atualizadas"
    }

    foreach ($job in $sync.Jobs) {
        $i++
        Prog ([math]::Round((($i-1)/$total)*100)) "$($job.Nome)  ($i de $total)"

        if ($sync.Presentes[$job.Id]) {
            Head $job.Nome
            Skip "ja instalado nesta maquina, pulando"
            St $job.Id "ja instalado" "#0A6F66"
            continue
        }

        St $job.Id "rodando" "#8A5A00"
        Head $job.Nome

        try {
            switch ($job.Id) {

                'bitdefender' {
                    $pasta = Join-Path $env:USERPROFILE "Downloads"
                    if (-not (Test-Path -LiteralPath $pasta)) {
                        New-Item -ItemType Directory -Path $pasta -Force | Out-Null
                    }
                    W "   consultando o servidor..."
                    $pagina = Invoke-WebRequest -Uri $sync.BaseUrl -UseBasicParsing -ErrorAction Stop
                    $nome = ($pagina.Content -split '["''<>\s]') |
                            Where-Object { $_ -like "setupdownloader_*.exe" } | Select-Object -First 1
                    if (-not $nome) { throw "instalador nao encontrado no servidor" }
                    $limpo = [uri]::UnescapeDataString($nome)
                    W "   arquivo: $limpo"
                    $destino = Join-Path $pasta $limpo
                    (New-Object System.Net.WebClient).DownloadFile("$($sync.BaseUrl)$nome", $destino)
                    W "   instalando, isso demora alguns minutos..."
                    Start-Process -FilePath "cmd.exe" -WorkingDirectory $pasta `
                        -ArgumentList "/c `"`"$limpo`"`"" -Wait -WindowStyle Hidden
                    Remove-Item -LiteralPath $destino -Force -ErrorAction SilentlyContinue
                    Ok "BitDefender concluido"
                }

                '7zip'       { if (-not (Wg '7zip.7zip' -Confere '7-Zip*'))                  { throw "falhou" } }
                'chrome' {
                    if (TemChrome) { Skip "Chrome ja presente" }
                    else {
                        $msi = "$env:TEMP\chrome_enterprise64.msi"
                        $arquivo = "googlechromestandaloneenterprise64.msi"
                        try {
                            W "   baixando do servidor local..."
                            Invoke-WebRequest -Uri "$($sync.BaseUrl)$arquivo" -OutFile $msi -UseBasicParsing -ErrorAction Stop
                        }
                        catch {
                            W "   nao encontrado no servidor, baixando da Google..." "#93A5B8"
                            Invoke-WebRequest -Uri "https://dl.google.com/dl/chrome/install/$arquivo" `
                                -OutFile $msi -UseBasicParsing -ErrorAction Stop
                        }
                        W "   instalando via msiexec..."
                        $pr = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
                        Remove-Item $msi -Force -ErrorAction SilentlyContinue
                        if ($pr.ExitCode -eq 0)          { Ok "Chrome instalado" }
                        elseif ($pr.ExitCode -eq 3010)   { Ok "Chrome instalado (requer reinicializacao)" }
                        elseif ($pr.ExitCode -eq 1638)   { Skip "Chrome ja estava instalado" }
                        elseif (TemChrome)               { Skip "Chrome presente (msiexec retornou $($pr.ExitCode))" }
                        else { throw "msiexec retornou $($pr.ExitCode)" }
                    }
                }
                'corretto'   { if (-not (Wg 'Amazon.Corretto.8.JDK' -Confere 'Amazon Corretto*8*')) { throw "falhou" } }
                'onlyoffice' { if (-not (Wg 'ONLYOFFICE.DesktopEditors' -Confere '*ONLYOFFICE*')) { throw "falhou" } }
                'notepadpp'  { if (-not (Wg 'Notepad++.Notepad++' -Confere 'Notepad++*'))    { throw "falhou" } }
                'sumatra'    { if (-not (Wg 'SumatraPDF.SumatraPDF' -Confere '*Sumatra*' -SemEscopoSeFalhar)) { throw "falhou" } }
                'vlc'        { if (-not (Wg 'VideoLAN.VLC' -Confere 'VLC media player*'))    { throw "falhou" } }
                'lightshot'  { if (-not (Wg 'Skillbrains.Lightshot' -Confere '*Lightshot*' -SemEscopoSeFalhar)) { throw "falhou" } }

                'vcredist' {
                    $falhas = 0
                    foreach ($p in $sync.VcRedists) { if (-not (Wg $p)) { $falhas++ } }
                    if ($falhas -gt 0) { throw "$falhas de $($sync.VcRedists.Count) pacotes falharam" }
                }

                'dotnet' {
                    $falhas = 0
                    foreach ($p in $sync.DotNetPkgs) { if (-not (Wg $p)) { $falhas++ } }
                    if ($falhas -gt 0) { throw "$falhas pacote(s) falharam" }
                }

                'uvnc' {
                    $exe = "C:\Program Files\uvnc bvba\UltraVNC\winvnc.exe"
                    $destino = "$env:TEMP\UltraVNC_Setup.exe"
                    W "   baixando..."
                    Invoke-WebRequest -Uri "$($sync.BaseUrl)UltraVNC_Setup.exe" -OutFile $destino -UseBasicParsing -ErrorAction Stop
                    W "   instalando somente o server, como servico..."
                    $a = '/TYPE=custom /COMPONENTS="ultravnc_server" /TASKS="installservice,startservice,installdriver" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOICONS'
                    Start-Process -FilePath $destino -ArgumentList $a -Wait -WindowStyle Hidden
                    Start-Sleep -Seconds 3
                    Remove-Item $destino -Force -ErrorAction SilentlyContinue

                    $svc = Get-Service -Name "uvnc_service" -ErrorAction SilentlyContinue
                    if (-not $svc) {
                        $svc = Get-Service | Where-Object { $_.Name -match 'vnc' -or $_.DisplayName -match 'VNC' } | Select-Object -First 1
                    }
                    if ((Test-Path -LiteralPath $exe) -and $svc) { Ok "servico $($svc.Name) - $($svc.Status)" }
                    elseif (Test-Path -LiteralPath $exe) { throw "winvnc.exe existe, mas nenhum servico de VNC foi encontrado" }
                    else { throw "instalacao nao confirmada" }
                }

                'gonnect' {
                    W "   consultando a ultima versao no GitHub..."
                    $api = Invoke-RestMethod -Uri "https://api.github.com/repos/gonicus/gonnect/releases/latest" `
                           -UseBasicParsing -ErrorAction Stop
                    $asset = $api.assets | Where-Object { $_.name -like "*win64.exe" } | Select-Object -First 1
                    if (-not $asset) { throw "win64.exe nao localizado no release" }
                    $destino = "$env:TEMP\$($asset.name)"
                    W "   baixando $($asset.name)..."
                    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $destino -UseBasicParsing -ErrorAction Stop
                    W "   instalando para todos os usuarios..."
                    Start-Process -FilePath $destino -ArgumentList "/S" -Wait -WindowStyle Hidden

                    $exe = "C:\Program Files\GOnnect\bin\gonnect.exe"
                    if (Test-Path -LiteralPath $exe) {
                        $ws = New-Object -ComObject WScript.Shell
                        $s1 = $ws.CreateShortcut("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\GOnnect.lnk")
                        $s1.TargetPath = $exe; $s1.Save()
                        $s2 = $ws.CreateShortcut("$env:Public\Desktop\GOnnect.lnk")
                        $s2.TargetPath = $exe; $s2.Save()
                        Ok "atalhos e inicializacao automatica criados"
                        W "   o ramal sera pedido no proximo login do usuario." "#93A5B8"
                    } else { throw "executavel nao encontrado em $exe" }
                    Remove-Item $destino -Force -ErrorAction SilentlyContinue
                }

                'impressoras' {
                    $TempDir = "C:\KyoceraDrivers"
                    if (!(Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir | Out-Null }

                    $Infs = Get-ChildItem -Path $TempDir -Filter "OEMSETUP.INF" -Recurse -ErrorAction SilentlyContinue

                    if (-not $Infs) {
                        # Preferimos .zip: o Expand-Archive e nativo e nao depende do 7-Zip
                        $zip  = "$TempDir\drivers.zip"
                        $sete = "$TempDir\drivers.7z"
                        $usouZip = $false

                        if (-not (Test-Path $zip) -and -not (Test-Path $sete)) {
                            try {
                                W "   baixando KyoceraDrivers.zip..."
                                Invoke-WebRequest -Uri "$($sync.BaseUrl)KyoceraDrivers.zip" -OutFile $zip -ErrorAction Stop
                                $usouZip = $true
                            }
                            catch {
                                W "   zip nao encontrado no servidor, tentando o 7z..." "#93A5B8"
                                Invoke-WebRequest -Uri "$($sync.BaseUrl)KyoceraDrivers.7z" -OutFile $sete -ErrorAction Stop
                            }
                        }

                        if (Test-Path $zip) { $usouZip = $true }

                        if ($usouZip) {
                            W "   extraindo com Expand-Archive..."
                            Expand-Archive -LiteralPath $zip -DestinationPath $TempDir -Force -ErrorAction Stop
                        }
                        else {
                            W "   extraindo com 7-Zip..."
                            $sevenZip = "C:\Program Files\7-Zip\7z.exe"
                            if (-not (Test-Path $sevenZip)) {
                                throw "pacote em .7z e o 7-Zip nao esta instalado nesta maquina"
                            }
                            & $sevenZip x $sete "-o$TempDir" -y | Out-Null
                        }

                        $Infs = Get-ChildItem -Path $TempDir -Filter "OEMSETUP.INF" -Recurse
                    }

                    if (-not $Infs) { throw "nenhum OEMSETUP.INF apos a extracao" }

                    foreach ($p in $sync.Printers) {
                        W ""
                        W "   [$($p.Ip)] $($p.Nome)" "#93A5B8"
                        try {
                            $snmp = New-Object -ComObject olePrn.OleSNMP
                            $snmp.Open($p.Ip, "public")
                            $modelo = $snmp.Get(".1.3.6.1.2.1.25.3.2.1.3.1")
                            $snmp.Close()
                            if (-not $modelo) { throw "sem resposta SNMP" }
                            W "   hardware: $modelo"

                            $core = ($modelo -split ' ' | Where-Object { $_ -match '\d' } | Select-Object -First 1)
                            if (-not $core) { $core = $modelo }

                            $InfPath = $null; $DriverName = $null
                            foreach ($f in $Infs) {
                                foreach ($line in (Get-Content $f.FullName)) {
                                    if ($line -match '^"([^"]+)"\s*=\s*([^,]+)') {
                                        $d = $Matches[1].Trim(); $s = $Matches[2].Trim()
                                        if ($d -like "*$core*" -or $s -like "*$core*") {
                                            $DriverName = $d; $InfPath = $f.FullName; break
                                        }
                                    }
                                }
                                if ($DriverName) { break }
                            }
                            if (-not $DriverName) { throw "driver para '$core' nao localizado no INF" }
                            W "   driver: $DriverName"

                            $Port = "IP_$($p.Ip)"
                            if (-not (Get-PrinterPort -Name $Port -ErrorAction SilentlyContinue)) {
                                Add-PrinterPort -Name $Port -PrinterHostAddress $p.Ip -ErrorAction Stop
                            }

                            $cat = Get-ChildItem -Path (Split-Path $InfPath) -Filter "*.cat" | Select-Object -First 1
                            if ($cat) {
                                $cert = (Get-AuthenticodeSignature $cat.FullName).SignerCertificate
                                if ($cert) {
                                    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPublisher","LocalMachine")
                                    $store.Open("ReadWrite"); $store.Add($cert); $store.Close()
                                }
                            }

                            pnputil.exe /add-driver $InfPath | Out-Null

                            $printUiArgs = "printui.dll,PrintUIEntry /ia /m `"$DriverName`" /f `"$InfPath`""
                            $proc = Start-Process rundll32.exe -ArgumentList $printUiArgs -Wait -PassThru -WindowStyle Hidden
                            if ($proc.ExitCode -ne 0) { throw "PrintUI retornou $($proc.ExitCode)" }

                            Add-Printer -Name $p.Nome -DriverName $DriverName -PortName $Port -ErrorAction Stop

                            $cfg = Get-PrintConfiguration -PrinterName $p.Nome
                            [xml]$ticket = $cfg.PrintTicketXML
                            $nsm = New-Object System.Xml.XmlNamespaceManager($ticket.NameTable)
                            $nsm.AddNamespace("psf","http://schemas.microsoft.com/windows/2003/08/printing/printschemaframework")

                            $bin = $ticket.SelectSingleNode("//psf:Feature[@name='psk:PageInputBin']/psf:Option",$nsm)
                            if ($bin) { $bin.SetAttribute("name","psk:Cassette") }
                            else {
                                $fr = $ticket.CreateDocumentFragment()
                                $fr.InnerXml = '<psf:Feature name="psk:PageInputBin"><psf:Option name="psk:Cassette" /></psf:Feature>'
                                $ticket.DocumentElement.AppendChild($fr) | Out-Null
                            }
                            $md = $ticket.SelectSingleNode("//psf:Feature[@name='psk:PageMediaType']/psf:Option",$nsm)
                            if ($md) { $md.SetAttribute("name","psk:Plain") }
                            else {
                                $fr = $ticket.CreateDocumentFragment()
                                $fr.InnerXml = '<psf:Feature name="psk:PageMediaType"><psf:Option name="psk:Plain" /></psf:Feature>'
                                $ticket.DocumentElement.AppendChild($fr) | Out-Null
                            }
                            Set-PrintConfiguration -PrinterName $p.Nome -PrintTicketXML $ticket.OuterXml -ErrorAction Stop

                            Ok "$($p.Nome) configurada"
                        }
                        catch { Err "[$($p.Ip)] $($_.Exception.Message)" }
                    }
                }
            }
            St $job.Id "concluido" "#0A6F66"
        }
        catch {
            Err $_.Exception.Message
            St $job.Id "falhou" "#C01C28"
            $totalFalhas++
        }
    }

    Prog 100 "Preparacao concluida."
    W ""
    if ($totalFalhas -eq 0) { W "Tudo certo. Nenhuma falha registrada." "#22C55E" }
    else { W "Concluido com $totalFalhas item(ns) com falha. Verifique o log acima." "#F59E0B" }
    W "Desenvolvido por @JJMoratelli" "#7C93AE"

    $sync.Falhas = $totalFalhas
    $sync.Done = $true
}

# ---------------------------------------------------------------- EXECUCAO
$BtnRun.Add_Click({
    $jobs = @()
    foreach ($t in $Base)     { $jobs += ,@{ Id=$t.Id; Nome=$t.Nome } }
    foreach ($t in $Opcional) { if ($Checks[$t.Id].IsChecked) { $jobs += ,@{ Id=$t.Id; Nome=$t.Nome } } }

    $printers = @()
    if ($Checks['impressoras'].IsChecked) {
        foreach ($r in $PrinterRows) {
            $ip = $r.Ip.Text.Trim(); $nm = $r.Nome.Text.Trim()
            if (-not $ip -and -not $nm) { continue }
            if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { Write-Log "IP invalido: '$ip'" "#F59E0B"; return }
            if (-not $nm) { Write-Log "Falta o nome da impressora $ip." "#F59E0B"; return }
            $printers += ,@{ Ip=$ip; Nome=$nm }
        }
        if ($printers.Count -eq 0) {
            Write-Log "Adicione ao menos uma impressora ou desmarque a tarefa." "#F59E0B"
            return
        }
    }

    $sync.Jobs = $jobs
    $sync.Printers = $printers

    $BtnRun.IsEnabled = $false
    $BtnRun.Content = "Preparando..."
    $Bar.Value = 0
    $Spinner.Visibility = "Visible"
    $timerPoll.Start()

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"
    $rs.ThreadOptions  = "ReuseThread"
    $rs.Open()
    $rs.SessionStateProxy.SetVariable("sync", $sync)
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript($worker) | Out-Null
    $ps.BeginInvoke() | Out-Null
})

$sync.Done = $false
$script:PodeFechar = $false
$script:Finalizando = $false
$script:Restante = 30

function Encerrar {
    $script:PodeFechar = $true
    $win.Close()
}

# Enquanto nao concluir, a janela nao fecha: nem pelo X, nem por Alt+F4.
$win.Add_Closing({
    param($s, $e)
    if (-not $script:PodeFechar) { $e.Cancel = $true }
})

$timerConta = New-Object Windows.Threading.DispatcherTimer
$timerConta.Interval = [TimeSpan]::FromSeconds(1)
$timerConta.Add_Tick({
    $script:Restante--
    if ($script:Restante -le 0) {
        $timerConta.Stop()
        Encerrar
    } else {
        $DoneCount.Text = "Fechando em $($script:Restante) s"
    }
})

$timerPoll = New-Object Windows.Threading.DispatcherTimer
$timerPoll.Interval = [TimeSpan]::FromMilliseconds(400)
$timerPoll.Add_Tick({
    if ($sync.Done -and -not $script:Finalizando) {
        $script:Finalizando = $true
        $timerPoll.Stop()
        $Spinner.Visibility = "Collapsed"
        if ($sync.Falhas -gt 0) {
            $DoneTitle.Text = "Preparacao concluida com avisos"
            $DoneMsg.Text = "$($sync.Falhas) item(ns) nao foram instalados. Confira o log antes de entregar a maquina."
        } else {
            $DoneTitle.Text = "Estacao preparada"
            $DoneMsg.Text = "Todos os itens foram instalados com sucesso."
        }
        $DoneCount.Text = "Fechando em 30 s"
        $DoneOverlay.Visibility = "Visible"
        $timerConta.Start()
    }
})

$BtnDone.Add_Click({
    $timerConta.Stop()
    Encerrar
})

$win.ShowDialog() | Out-Null
