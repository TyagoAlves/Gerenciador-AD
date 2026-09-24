Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# ============================================================
# GERENCIADOR AD - APLICATIVO UNICO
# Reune:
#   - Cadastro / padronizacao de usuarios (modo criar e editar)
#   - Reset/desbloqueio de senha
#   - Consulta de acessos e grupos
#   - Gerenciar grupos (adicionar, remover, copiar, comparar)
#   - Desativacao e movimentacao para OU de desativados
#   - Mover maquinas para OU
#   - Gerar relatorios e historico
#   - Alteracao em massa
#   - Central de inconsistencias
#
# Requisito:
#   - Windows PowerShell 5.1
#   - RSAT / modulo ActiveDirectory
#
# Configuracao:
#   No primeiro uso, abra em "Valores padronizados" e configure as listas,
#   o dominio de e-mail e as OUs de acordo com a sua organizacao.
#   Os valores ficam salvos em padroes.json (veja a barra de status da tela).
#
# A credencial administrativa e solicitada UMA vez no login
# e permanece somente em memoria durante a execucao.
# ============================================================

$script:AdminCreds = $null
$script:CurrentUser = ""
$script:OUDestinoDesativados = ""

# ============================================================
# CORES / CONFIGURACAO
# ============================================================

$script:Colors = @{
    Primary   = [System.Drawing.Color]::FromArgb(0, 122, 204)
    Success   = [System.Drawing.Color]::FromArgb(40, 167, 69)
    Danger    = [System.Drawing.Color]::FromArgb(220, 53, 69)
    Warning   = [System.Drawing.Color]::FromArgb(230, 145, 30)
    Dark      = [System.Drawing.Color]::FromArgb(35, 39, 43)
    Sidebar   = [System.Drawing.Color]::FromArgb(245, 247, 250)
    Border    = [System.Drawing.Color]::FromArgb(220, 224, 230)
    Text      = [System.Drawing.Color]::FromArgb(35, 39, 43)
    Muted     = [System.Drawing.Color]::FromArgb(100, 108, 118)
    White     = [System.Drawing.Color]::White
}

# ============================================================
# FUNCOES DE APOIO
# ============================================================

function Show-ErrorMessage {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        "Erro",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

function Show-WarningMessage {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        "Aviso",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
}

function Show-InfoMessage {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        "Concluido",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

function Confirm-Action {
    param(
        [string]$Message,
        [string]$Title = "Confirmar Operacao"
    )

    return (
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        ) -eq [System.Windows.Forms.DialogResult]::Yes
    )
}

function Ensure-ADModule {
    try {
        if (-not (Get-Module -Name ActiveDirectory)) {
            Import-Module ActiveDirectory -ErrorAction Stop
        }
        return $true
    }
    catch {
        Show-ErrorMessage "Nao foi possivel carregar o modulo ActiveDirectory.`r`n`r`n$($_.Exception.Message)"
        return $false
    }
}

function Get-UserDisplayName {
    param($ADUser)

    if ($ADUser.DisplayName) {
        return $ADUser.DisplayName
    }

    return $ADUser.SamAccountName
}

function Get-FormattedExpirationDate {
    param($ADUser)

    if ($ADUser.AccountExpirationDate) {
        return $ADUser.AccountExpirationDate.ToString("dd/MM/yyyy")
    }

    return (Get-Date).ToString("dd/MM/yyyy")
}

function Add-StandardTitle {
    param(
        [System.Windows.Forms.Panel]$Panel,
        [string]$Title,
        [string]$Subtitle
    )

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Title
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = $script:Colors.Text
    $lbl.Location = New-Object System.Drawing.Point(25, 20)
    $lbl.Size = New-Object System.Drawing.Size(900, 35)
    $Panel.Controls.Add($lbl)

    if ($Subtitle) {
        $sub = New-Object System.Windows.Forms.Label
        $sub.Text = $Subtitle
        $sub.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $sub.ForeColor = $script:Colors.Muted
        $sub.Location = New-Object System.Drawing.Point(27, 58)
        $sub.Size = New-Object System.Drawing.Size(900, 25)
        $Panel.Controls.Add($sub)
    }
}

function New-Label {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 300,
        [int]$H = 22
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($W, $H)
    $label.ForeColor = $script:Colors.Text
    return $label
}

function New-TextBox {
    param(
        [int]$X,
        [int]$Y,
        [int]$W = 400,
        [int]$H = 28
    )

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point($X, $Y)
    $txt.Size = New-Object System.Drawing.Size($W, $H)
    return $txt
}

function New-ActionButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 180,
        [int]$H = 38,
        [System.Drawing.Color]$BackColor = $script:Colors.Primary
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($W, $H)
    $btn.BackColor = $BackColor
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    return $btn
}

function New-GroupBox {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H
    )

    $gb = New-Object System.Windows.Forms.GroupBox
    $gb.Text = $Text
    $gb.Location = New-Object System.Drawing.Point($X, $Y)
    $gb.Size = New-Object System.Drawing.Size($W, $H)
    return $gb
}

# ============================================================
# LOGIN UNICO
# ============================================================

function Show-LoginWindow {
    $script:loginForm = New-Object System.Windows.Forms.Form
    $script:loginForm.Text = "Login Administrativo - Active Directory"
    $script:loginForm.Size = New-Object System.Drawing.Size(430, 285)
    $script:loginForm.StartPosition = "CenterScreen"
    $script:loginForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $script:loginForm.MaximizeBox = $false
    $script:loginForm.MinimizeBox = $false
    $script:loginForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Acesso ao Gerenciador AD"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
    $title.Location = New-Object System.Drawing.Point(20, 18)
    $title.Size = New-Object System.Drawing.Size(370, 30)
    $title.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $script:loginForm.Controls.Add($title)

    $lblUser = New-Label "Usuario administrativo (Ex: dominio\admin):" 25 65 360 22
    $script:loginForm.Controls.Add($lblUser)

    $script:txtUser = New-TextBox 25 88 360 28
    $script:loginForm.Controls.Add($script:txtUser)

    $lblPass = New-Label "Senha:" 25 123 360 22
    $script:loginForm.Controls.Add($lblPass)

    $script:txtPass = New-TextBox 25 146 360 28
    $script:txtPass.UseSystemPasswordChar = $true
    $script:loginForm.Controls.Add($script:txtPass)

    $btnLogin = New-ActionButton "Entrar" 25 190 360 38 $script:Colors.Success
    $script:loginForm.Controls.Add($btnLogin)

    $script:loginForm.AcceptButton = $btnLogin

    $script:AdminCreds = $null

    $btnLogin.Add_Click({
        $login = $script:txtUser.Text.Trim()
        $senha = $script:txtPass.Text

        if ([string]::IsNullOrWhiteSpace($login) -or [string]::IsNullOrWhiteSpace($senha)) {
            Show-WarningMessage "Preencha o usuario e a senha."
            return
        }

        try {
            $securePass = ConvertTo-SecureString $senha -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential($login, $securePass)

            Import-Module ActiveDirectory -ErrorAction Stop

            # Valida a credencial contra o AD.
            $null = Get-ADUser -Filter * -ResultSetSize 1 -Credential $cred -ErrorAction Stop

            $script:AdminCreds = $cred
            $script:CurrentUser = $login

            $script:loginForm.Close()
        }
        catch {
            $script:AdminCreds = $null
            Show-ErrorMessage "Nao foi possivel validar o login no Active Directory.`r`n`r`n$($_.Exception.Message)"
        }
    })

    [void]$script:loginForm.ShowDialog()
    return $script:AdminCreds
}

# ============================================================
# FORMULARIO PRINCIPAL
# ============================================================

$form = New-Object System.Windows.Forms.Form
$form.Text = "Gerenciador Administrativo do Active Directory"
$form.Size = New-Object System.Drawing.Size(1280, 820)
$form.MinimumSize = New-Object System.Drawing.Size(1100, 700)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $true
$form.MinimizeBox = $true
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.BackColor = [System.Drawing.Color]::White

# ============================================================
# MENU
# ============================================================

$menuStrip = New-Object System.Windows.Forms.MenuStrip

$menuArquivo = New-Object System.Windows.Forms.ToolStripMenuItem("Arquivo")
$menuLogin = New-Object System.Windows.Forms.ToolStripMenuItem("Trocar login")
$menuSair = New-Object System.Windows.Forms.ToolStripMenuItem("Sair")

[void]$menuArquivo.DropDownItems.Add($menuLogin)
[void]$menuArquivo.DropDownItems.Add($menuSair)

$menuFerramentas = New-Object System.Windows.Forms.ToolStripMenuItem("Ferramentas")

$menuSenha = New-Object System.Windows.Forms.ToolStripMenuItem("Reset / desbloqueio de senha")
$menuAcessos = New-Object System.Windows.Forms.ToolStripMenuItem("Consultar acessos")
$menuDesativar = New-Object System.Windows.Forms.ToolStripMenuItem("Desativar usuario")
$menuMaquinas = New-Object System.Windows.Forms.ToolStripMenuItem("Mover maquinas para OU")
$menuRelatorio = New-Object System.Windows.Forms.ToolStripMenuItem("Gerar relatorio")
$menuLog = New-Object System.Windows.Forms.ToolStripMenuItem("Historico do usuario")
$menuCadastro = New-Object System.Windows.Forms.ToolStripMenuItem("Cadastro de usuario")
$menuCentral = New-Object System.Windows.Forms.ToolStripMenuItem("Central de inconsistencias")
$menuEmMassa = New-Object System.Windows.Forms.ToolStripMenuItem("Alteracao em massa")
$menuGrupos = New-Object System.Windows.Forms.ToolStripMenuItem("Gerenciar grupos")
$menuPadroes = New-Object System.Windows.Forms.ToolStripMenuItem("Valores padronizados")

[void]$menuFerramentas.DropDownItems.Add($menuSenha)
[void]$menuFerramentas.DropDownItems.Add($menuAcessos)
[void]$menuFerramentas.DropDownItems.Add($menuDesativar)
[void]$menuFerramentas.DropDownItems.Add($menuMaquinas)
[void]$menuFerramentas.DropDownItems.Add($menuRelatorio)
[void]$menuFerramentas.DropDownItems.Add($menuLog)
[void]$menuFerramentas.DropDownItems.Add($menuCadastro)
[void]$menuFerramentas.DropDownItems.Add($menuCentral)
[void]$menuFerramentas.DropDownItems.Add($menuEmMassa)
[void]$menuFerramentas.DropDownItems.Add($menuGrupos)
[void]$menuFerramentas.DropDownItems.Add($menuPadroes)

[void]$menuStrip.Items.Add($menuArquivo)
[void]$menuStrip.Items.Add($menuFerramentas)

$form.MainMenuStrip = $menuStrip
$form.Controls.Add($menuStrip)

# ============================================================
# CABECALHO
# ============================================================

$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 24)
$header.Size = New-Object System.Drawing.Size(1280, 70)
$header.BackColor = $script:Colors.Dark
$header.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($header)

$lblApp = New-Object System.Windows.Forms.Label
$lblApp.Text = "GERENCIADOR AD"
$lblApp.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblApp.ForeColor = [System.Drawing.Color]::White
$lblApp.Location = New-Object System.Drawing.Point(22, 10)
$lblApp.Size = New-Object System.Drawing.Size(300, 30)
$header.Controls.Add($lblApp)

$lblLogged = New-Object System.Windows.Forms.Label
$lblLogged.Location = New-Object System.Drawing.Point(22, 39)
$lblLogged.Size = New-Object System.Drawing.Size(600, 22)
$lblLogged.ForeColor = [System.Drawing.Color]::Gainsboro
$header.Controls.Add($lblLogged)

# ============================================================
# SIDEBAR
# ============================================================

$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Location = New-Object System.Drawing.Point(0, 94)
$sidebar.Size = New-Object System.Drawing.Size(245, 680)
$sidebar.AutoScroll = $true
$sidebar.BackColor = $script:Colors.Sidebar
$sidebar.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$form.Controls.Add($sidebar)

$lblMenu = New-Object System.Windows.Forms.Label
$lblMenu.Text = "OPERACOES"
$lblMenu.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblMenu.ForeColor = $script:Colors.Muted
$lblMenu.Location = New-Object System.Drawing.Point(18, 18)
$lblMenu.Size = New-Object System.Drawing.Size(200, 25)
$sidebar.Controls.Add($lblMenu)

# ============================================================
# AREA DE CONTEUDO
# ============================================================

$content = New-Object System.Windows.Forms.Panel
$content.Location = New-Object System.Drawing.Point(245, 94)
$content.Size = New-Object System.Drawing.Size(1015, 680)
$content.BackColor = [System.Drawing.Color]::White
$content.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$content.AutoScroll = $true
$form.Controls.Add($content)

# ============================================================
# STATUS BAR
# ============================================================

$status = New-Object System.Windows.Forms.StatusStrip

$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = "Pronto."
[void]$status.Items.Add($statusLabel)

$statusRight = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusRight.Spring = $true
[void]$status.Items.Add($statusRight)

$statusLogin = New-Object System.Windows.Forms.ToolStripStatusLabel
[void]$status.Items.Add($statusLogin)

$form.Controls.Add($status)

# ============================================================
# FUNCAO PARA ATUALIZAR STATUS
# ============================================================

function Set-AppStatus {
    param([string]$Text)

    $statusLabel.Text = $Text
    $status.Refresh()
}

function Update-LoginDisplay {
    $lblLogged.Text = "Conectado como: $script:CurrentUser"
    $statusLogin.Text = "AD: $script:CurrentUser"
}

# ============================================================
# LIMPA CONTEUDO
# ============================================================

function Clear-Content {
    $content.Controls.Clear()
}

# ============================================================
# MENU LATERAL
# ============================================================

function Add-SidebarButton {
    param(
        [string]$Text,
        [int]$Y,
        [scriptblock]$Action
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point(15, $Y)
    $button.Size = New-Object System.Drawing.Size(215, 43)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $button.Padding = New-Object System.Windows.Forms.Padding(14, 0, 0, 0)
    $button.BackColor = $script:Colors.Sidebar
    $button.ForeColor = $script:Colors.Text
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $button.Add_Click($Action)

    $button.Add_MouseEnter({
        $this.BackColor = [System.Drawing.Color]::FromArgb(225, 230, 236)
    })

    $button.Add_MouseLeave({
        $this.BackColor = $script:Colors.Sidebar
    })

    $sidebar.Controls.Add($button)

    return $button
}

# ============================================================
# LOG PADRONIZADO (gravado no atributo info/Observacoes)
# ============================================================

function Get-LogLine {
    param([string]$Message)

    $data = (Get-Date).ToString("dd/MM/yyyy HH:mm")
    return "[$data] [$($script:CurrentUser)] $Message"
}

# ============================================================
# FILTRO LDAP DE BUSCA DE USUARIO
# ============================================================

function Get-UserSearchFilter {
    param(
        [string]$Campo,
        [string]$Termo
    )

    $e = $Termo -replace '([\*\(\)\\])', '\$1'

    switch ($Campo) {
        "Nome" {
            return "(&(objectCategory=person)(objectClass=user)(|(displayName=*$e*)(cn=*$e*)))"
        }
        "Login" {
            return "(&(objectCategory=person)(objectClass=user)(sAMAccountName=*$e*))"
        }
        "Cargo" {
            return "(&(objectCategory=person)(objectClass=user)(title=*$e*))"
        }
        "Descricao" {
            return "(&(objectCategory=person)(objectClass=user)(description=*$e*))"
        }
        default {
            return "(&(objectCategory=person)(objectClass=user)(|(displayName=*$e*)(cn=*$e*)(sAMAccountName=*$e*)(title=*$e*)(description=*$e*)))"
        }
    }
}

# ============================================================
# BUSCA PADRONIZADA DE USUARIO (usada em todas as operacoes)
# ============================================================

function Add-UserSearch {
    param(
        [int]$Y,
        [scriptblock]$Callback,
        [int]$ListHeight = 170
    )

    $script:SearchCallback = $Callback

    $lblCampo = New-Label "Buscar em:" 25 $Y 120 22
    $script:lblCampoBusca = $lblCampo
    $content.Controls.Add($lblCampo)

    $script:cbCampo = New-Object System.Windows.Forms.ComboBox
    $script:cbCampo.Location = New-Object System.Drawing.Point(25, ($Y + 25))
    $script:cbCampo.Size = New-Object System.Drawing.Size(160, 28)
    $script:cbCampo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$script:cbCampo.Items.Add("Nome")
    [void]$script:cbCampo.Items.Add("Login")
    [void]$script:cbCampo.Items.Add("Cargo")
    [void]$script:cbCampo.Items.Add("Descricao")
    [void]$script:cbCampo.Items.Add("Todos")
    $script:cbCampo.SelectedIndex = 4
    $content.Controls.Add($script:cbCampo)

    $script:txtBusca = New-TextBox 195 ($Y + 25) 400 30
    $content.Controls.Add($script:txtBusca)

    $script:btnPesquisar = New-ActionButton "Pesquisar" 640 ($Y + 23) 130 34
    $content.Controls.Add($script:btnPesquisar)

    $script:btnUsar = New-ActionButton "Usar selecionado" 782 ($Y + 23) 148 34 $script:Colors.Success
    $content.Controls.Add($script:btnUsar)

    $script:list = New-Object System.Windows.Forms.ListView
    $script:list.Location = New-Object System.Drawing.Point(25, ($Y + 65))
    $script:list.Size = New-Object System.Drawing.Size(935, $ListHeight)
    $script:list.View = [System.Windows.Forms.View]::Details
    $script:list.FullRowSelect = $true
    $script:list.GridLines = $true
    $script:list.MultiSelect = $false
    $script:list.Scrollable = $true
    $script:list.UseCompatibleStateImageBehavior = $false
    [void]$script:list.Columns.Add("Nome", 210)
    [void]$script:list.Columns.Add("Usuario", 140)
    [void]$script:list.Columns.Add("Cargo", 220)
    [void]$script:list.Columns.Add("Descricao", 340)
    $content.Controls.Add($script:list)

    $script:btnPesquisar.Add_Click({
        $termo = $script:txtBusca.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($termo)) {
            Show-WarningMessage "Digite um termo para buscar."
            return
        }

        if (-not (Ensure-ADModule)) { return }

        try {
            $script:btnPesquisar.Enabled = $false
            $script:btnPesquisar.Text = "Pesquisando..."
            Set-AppStatus "Pesquisando usuarios no AD..."

            $script:list.Items.Clear()

            $campo = $script:cbCampo.SelectedItem.ToString()
            $filtro = Get-UserSearchFilter $campo $termo

            $encontrados = Get-ADUser `
                -LDAPFilter $filtro `
                -Properties Description, Title, SamAccountName, DisplayName `
                -Credential $script:AdminCreds `
                -ErrorAction Stop

            foreach ($u in $encontrados) {
                $nome = if ($u.DisplayName) { $u.DisplayName } else { $u.SamAccountName }
                $cargo = if ($u.Title) { $u.Title } else { "[Sem Cargo]" }
                $desc = if ($u.Description) { $u.Description } else { "[Sem Descricao]" }

                $item = New-Object System.Windows.Forms.ListViewItem($nome)
                [void]$item.SubItems.Add($u.SamAccountName)
                [void]$item.SubItems.Add($cargo)
                [void]$item.SubItems.Add($desc)
                $item.Tag = $u.SamAccountName
                [void]$script:list.Items.Add($item)
            }

            Set-AppStatus "Pesquisa concluida. Encontrados: $($script:list.Items.Count)."
        }
        catch {
            Show-ErrorMessage "Erro ao pesquisar no Active Directory:`r`n`r`n$($_.Exception.Message)"
            Set-AppStatus "Erro na pesquisa."
        }
        finally {
            $script:btnPesquisar.Enabled = $true
            $script:btnPesquisar.Text = "Pesquisar"
        }
    })

    $script:btnUsar.Add_Click({
        if ($script:list.SelectedItems.Count -eq 0) {
            Show-WarningMessage "Selecione um usuario na lista."
            return
        }

        $login = $script:list.SelectedItems[0].Tag
        if ($script:SearchCallback) {
            & $script:SearchCallback $login
        }
    })

    $script:list.Add_DoubleClick({
        if ($script:list.SelectedItems.Count -gt 0) {
            $login = $script:list.SelectedItems[0].Tag
            if ($script:SearchCallback) {
                & $script:SearchCallback $login
            }
        }
    })

    return ($Y + 65 + $ListHeight + 10)
}

# ============================================================
# DASHBOARD
# ============================================================

function Show-Dashboard {

    Clear-Content

    Add-StandardTitle `
        $content `
        "Gerenciador Administrativo do Active Directory" `
        "Centralize as operacoes administrativas em uma unica aplicacao."

    $info = New-Object System.Windows.Forms.Label
    $info.Text = @"
LOGIN UNICO

Voce esta conectado com:
$script:CurrentUser

Ferramentas disponiveis:

• Cadastrar / padronizar usuario (criar ou editar, incluindo descricao)
• Resetar e desbloquear senha
• Consultar grupos e acessos
• Gerenciar grupos de um usuario para outro (inclui copiar)
• Desativar usuario, remover grupos e mover para a OU de desativados

A credencial administrativa permanece somente em memoria enquanto
o aplicativo estiver aberto.
"@
    $info.Location = New-Object System.Drawing.Point(30, 110)
    $info.Size = New-Object System.Drawing.Size(850, 250)
    $info.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $info.ForeColor = $script:Colors.Text
    $content.Controls.Add($info)

    $box = New-GroupBox "Sessao atual" 30 390 850 120
    $content.Controls.Add($box)

    $sessionLabel = New-Object System.Windows.Forms.Label
    $sessionLabel.Text = "Usuario administrativo: $script:CurrentUser`r`nStatus: Conectado"
    $sessionLabel.Location = New-Object System.Drawing.Point(20, 30)
    $sessionLabel.Size = New-Object System.Drawing.Size(500, 55)
    $sessionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $box.Controls.Add($sessionLabel)

    $btnTrocar = New-ActionButton "Trocar Login" 650 28 160 38 $script:Colors.Warning
    $box.Controls.Add($btnTrocar)

    $btnTrocar.Add_Click({
        $cred = Show-LoginWindow
        if ($cred) {
            Update-LoginDisplay
            Show-Dashboard
            Set-AppStatus "Login alterado com sucesso."
        }
    })
}

# ============================================================
# ============================================================
# TELA - RESET DE SENHA
# ============================================================

function Show-ResetSenha {

    Clear-Content

    Add-StandardTitle `
        $content `
        "Reset e desbloqueio de senha" `
        "Busque o usuario, gere uma senha temporaria, desbloqueia e redefine a conta."

    $nextY = Add-UserSearch 95 {
        param($login)
        $script:txtUsuario.Text = $login
        Set-AppStatus "Usuario selecionado: $login"
    } 140

    $lblU = New-Label "Username do colaborador:" 25 ($nextY + 5) 400 22
    $content.Controls.Add($lblU)

    $script:txtUsuario = New-TextBox 25 ($nextY + 30) 600 30
    $content.Controls.Add($script:txtUsuario)

    $lblIni = New-Label "Iniciais para gerar senha (3 letras):" 25 ($nextY + 80) 300 22
    $content.Controls.Add($lblIni)

    $script:txtIniciais = New-TextBox 25 ($nextY + 105) 100 30
    $script:txtIniciais.MaxLength = 3
    $content.Controls.Add($script:txtIniciais)

    $btnGerar = New-ActionButton "Gerar" 135 ($nextY + 103) 80 32 $script:Colors.Dark
    $content.Controls.Add($btnGerar)

    $script:txtSenha = New-TextBox 230 ($nextY + 105) 220 30
    $script:txtSenha.ReadOnly = $true
    $script:txtSenha.BackColor = [System.Drawing.Color]::White
    $content.Controls.Add($script:txtSenha)

    $btnCopiar = New-ActionButton "Copiar" 460 ($nextY + 103) 90 32 $script:Colors.Dark
    $content.Controls.Add($btnCopiar)

    $script:chkTroca = New-Object System.Windows.Forms.CheckBox
    $script:chkTroca.Text = "Exigir troca de senha no proximo logon"
    $script:chkTroca.Location = New-Object System.Drawing.Point(25, ($nextY + 155))
    $script:chkTroca.Size = New-Object System.Drawing.Size(400, 25)
    $script:chkTroca.Checked = $true
    $content.Controls.Add($script:chkTroca)

    $script:btnExecutar = New-ActionButton "Desbloquear e resetar conta" 25 ($nextY + 210) 525 45 $script:Colors.Primary
    $content.Controls.Add($script:btnExecutar)

    $btnGerar.Add_Click({
        $texto = $script:txtIniciais.Text.Trim()

        if ($texto.Length -ne 3 -or $texto -match '[^a-zA-Z]') {
            Show-WarningMessage "Digite exatamente 3 letras (A-Z)."
            return
        }

        $primeira = $texto.Substring(0,1).ToUpper()
        $resto = $texto.Substring(1,2).ToLower()
        $dataHoje = (Get-Date).ToString("ddMM") + (Get-Date).Year

        $script:txtSenha.Text = "$primeira$resto`@$dataHoje"
    })

    $btnCopiar.Add_Click({
        if ([string]::IsNullOrWhiteSpace($script:txtSenha.Text)) {
            Show-WarningMessage "Nenhuma senha foi gerada."
            return
        }

        Set-Clipboard $script:txtSenha.Text
        Show-InfoMessage "Senha temporaria copiada para a area de transferencia."
    })

    $script:btnExecutar.Add_Click({

        $usuario = $script:txtUsuario.Text.Trim()
        $novaSenha = $script:txtSenha.Text

        if ([string]::IsNullOrWhiteSpace($usuario) -or [string]::IsNullOrWhiteSpace($novaSenha)) {
            Show-WarningMessage "Informe o usuario e gere a senha temporaria."
            return
        }

        if (-not (Ensure-ADModule)) { return }

        try {
            $script:btnExecutar.Enabled = $false
            Set-AppStatus "Consultando usuario..."

            $u = Get-ADUser `
                -Identity $usuario `
                -Properties DisplayName, info `
                -Credential $script:AdminCreds `
                -ErrorAction Stop

            $nome = Get-UserDisplayName $u

            if (-not (Confirm-Action `
                "Confirma o desbloqueio e reset de senha para:`r`n`r`n$nome ($usuario)?" `
                "Confirmar operacao")) {
                return
            }

            Unlock-ADAccount `
                -Identity $usuario `
                -Credential $script:AdminCreds `
                -ErrorAction Stop

            $securePassword = ConvertTo-SecureString $novaSenha -AsPlainText -Force

            Set-ADAccountPassword `
                -Identity $usuario `
                -NewPassword $securePassword `
                -Credential $script:AdminCreds `
                -ErrorAction Stop

            if ($script:chkTroca.Checked) {
                Set-ADUser `
                    -Identity $usuario `
                    -ChangePasswordAtLogon $true `
                    -Credential $script:AdminCreds `
                    -ErrorAction Stop
            }

            $dataHoje = (Get-Date).ToString("dd/MM/yyyy HH:mm")
            $novoLog = Get-LogLine "Reset e desbloqueio de senha executados por $($script:CurrentUser). Troca no proximo logon: $($script:chkTroca.Checked)"

            if ($u.info) {
                $novoLog = "$novoLog`r`n$($u.info)"
            }

            Set-ADUser `
                -Identity $usuario `
                -Replace @{info = $novoLog} `
                -Credential $script:AdminCreds `
                -ErrorAction Stop

            Show-InfoMessage "A conta de '$nome' foi redefinida com sucesso."

            $script:txtUsuario.Clear()
            $script:txtIniciais.Clear()
            $script:txtSenha.Clear()

            Set-AppStatus "Senha redefinida."
        }
        catch {
            Show-ErrorMessage "Erro ao processar a solicitacao:`r`n`r`n$($_.Exception.Message)"
        }
        finally {
            $script:btnExecutar.Enabled = $true
        }
    })
}

# ============================================================
# TELA - CONSULTAR ACESSOS
# ============================================================

function Show-Acessos {

    Clear-Content

    Add-StandardTitle `
        $content `
        "Consultar acessos" `
        "Consulta nome, e-mail e grupos dos quais o usuario e membro."

    $nextY = Add-UserSearch 95 {
        param($login)
        $script:txtUsuario.Text = $login
        $script:btnConsultar.PerformClick()
    } 200

    $lblU = New-Label "Username do colaborador:" 25 ($nextY + 5) 350 22
    $content.Controls.Add($lblU)

    $script:txtUsuario = New-TextBox 25 ($nextY + 30) 650 30
    $content.Controls.Add($script:txtUsuario)

    $script:btnConsultar = New-ActionButton "Consultar acessos" 690 ($nextY + 28) 180 34
    $content.Controls.Add($script:btnConsultar)

    $script:txtResultado = New-Object System.Windows.Forms.TextBox
    $script:txtResultado.Location = New-Object System.Drawing.Point(25, ($nextY + 80))
    $script:txtResultado.Size = New-Object System.Drawing.Size(935, 330)
    $script:txtResultado.Multiline = $true
    $script:txtResultado.ScrollBars = "Both"
    $script:txtResultado.ReadOnly = $true
    $script:txtResultado.Font = New-Object System.Drawing.Font("Consolas", 10)
    $content.Controls.Add($script:txtResultado)

    $script:btnConsultar.Add_Click({

        $usuario = $script:txtUsuario.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($usuario)) {
            Show-WarningMessage "Digite o username do usuario."
            return
        }

        if (-not (Ensure-ADModule)) { return }

        try {
            $script:btnConsultar.Enabled = $false
            $script:btnConsultar.Text = "Buscando..."
            Set-AppStatus "Consultando acessos..."

            $u = Get-ADUser `
                -Identity $usuario `
                -Properties MemberOf, DisplayName, Mail `
                -Credential $script:AdminCreds `
                -ErrorAction Stop

            $relatorio = "=== RELATORIO DE ACESSOS (AD) ===`r`n"
            $relatorio += "Nome: $($u.DisplayName)`r`n"
            $relatorio += "Login: $usuario`r`n"
            $relatorio += "E-mail Principal: $($u.Mail)`r`n"
            $relatorio += "------------------------------------------------------------`r`n"
            $relatorio += "GRUPOS (Membro de):`r`n`r`n"

            if ($u.MemberOf) {
                foreach ($grupoDn in $u.MemberOf) {
                    $nomeGrupo = ($grupoDn -split ',')[0].Replace('CN=', '')
                    $relatorio += " [X] $nomeGrupo`r`n"
                }
            }
            else {
                $relatorio += " (O usuario nao pertence a nenhum grupo de permissao no AD)`r`n"
            }

            $script:txtResultado.Text = $relatorio
            Set-AppStatus "Consulta concluida."
        }
        catch {
            $script:txtResultado.Text = "Erro na consulta.`r`n`r`n$($_.Exception.Message)"
            Show-ErrorMessage "Erro ao consultar o Active Directory:`r`n`r`n$($_.Exception.Message)"
        }
        finally {
            $script:btnConsultar.Enabled = $true
            $script:btnConsultar.Text = "Consultar acessos"
        }
    })
}

# ============================================================
# TELA - DESATIVAR USUARIO
# ============================================================

function Show-Desativar {

    Clear-Content

    Add-StandardTitle `
        $content `
        "Desativar usuario" `
        "Desativa a conta, registra o historico, remove grupos e move para a OU de desativados."

    $warning = New-Object System.Windows.Forms.Label
    $warning.Text = "ATENCAO: esta e uma operacao critica e nao deve ser executada sem conferencia."
    $warning.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $warning.ForeColor = $script:Colors.Danger
    $warning.Location = New-Object System.Drawing.Point(25, 95)
    $warning.Size = New-Object System.Drawing.Size(900, 28)
    $content.Controls.Add($warning)

    $nextY = Add-UserSearch 140 {
        param($login)
        $script:txtUsuario.Text = $login
        Set-AppStatus "Usuario selecionado: $login"
    } 120

    $lblU = New-Label "Username do usuario:" 25 ($nextY + 5) 350 22
    $content.Controls.Add($lblU)

    $script:txtUsuario = New-TextBox 25 ($nextY + 30) 700 30
    $content.Controls.Add($script:txtUsuario)

    $lblTipo = New-Label "Tipo de desligamento:" 25 ($nextY + 80) 300 22
    $content.Controls.Add($lblTipo)

    $script:rdCobertura = New-Object System.Windows.Forms.RadioButton
    $script:rdCobertura.Text = "Cobertura"
    $script:rdCobertura.Location = New-Object System.Drawing.Point(25, ($nextY + 105))
    $script:rdCobertura.Size = New-Object System.Drawing.Size(150, 25)
    $script:rdCobertura.Checked = $true
    $content.Controls.Add($script:rdCobertura)

    $script:rdDefinitivo = New-Object System.Windows.Forms.RadioButton
    $script:rdDefinitivo.Text = "Definitivo"
    $script:rdDefinitivo.Location = New-Object System.Drawing.Point(200, ($nextY + 105))
    $script:rdDefinitivo.Size = New-Object System.Drawing.Size(150, 25)
    $content.Controls.Add($script:rdDefinitivo)

    $script:rdCobertura.Add_CheckedChanged({
        if ($script:rdCobertura.Checked) {
            $script:txtTicket.Clear()
            $script:info.Text = "Modo COBERTURA selecionado.`r`n`r`nA descricao sera:`r`nDesativado - SETOR - Final da Cobertura [data do AD]."
        }
    })

    $script:rdDefinitivo.Add_CheckedChanged({
        if ($script:rdDefinitivo.Checked) {
            $script:info.Text = "Modo DEFINITIVO selecionado.`r`n`r`nA descricao sera:`r`nDesativado - SETOR - Ticket NUMERO."
        }
    })

    $lblSetor = New-Label "Setor / Sigla (Ex: TI, RH, FIN):" 25 ($nextY + 150) 350 22
    $content.Controls.Add($lblSetor)

    $script:txtSetor = New-TextBox 25 ($nextY + 175) 700 30
    $content.Controls.Add($script:txtSetor)

    $lblTicket = New-Label "Numero do Ticket:" 25 ($nextY + 225) 350 22
    $content.Controls.Add($lblTicket)

    $script:txtTicket = New-TextBox 25 ($nextY + 250) 700 30
    $content.Controls.Add($script:txtTicket)

    $script:info = New-Object System.Windows.Forms.TextBox
    $script:info.Location = New-Object System.Drawing.Point(25, ($nextY + 305))
    $script:info.Size = New-Object System.Drawing.Size(935, 170)
    $script:info.Multiline = $true
    $script:info.ReadOnly = $true
    $script:info.ScrollBars = "Vertical"
    $script:info.Font = New-Object System.Drawing.Font("Consolas", 9)
    $script:info.Text = "OU de destino:`r`n$script:OUDestinoDesativados"
    $content.Controls.Add($script:info)

    $script:btnExecutar = New-ActionButton "Desativar e mover conta" 25 ($nextY + 505) 350 45 $script:Colors.Danger
    $content.Controls.Add($script:btnExecutar)

    $script:btnExecutar.Add_Click({

        $usuario = $script:txtUsuario.Text.Trim()
        $setor = $script:txtSetor.Text.Trim().ToUpper()
        $ticket = $script:txtTicket.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($usuario) -or [string]::IsNullOrWhiteSpace($setor)) {
            Show-WarningMessage "Preencha o usuario e o setor."
            return
        }

        $cobertura = $script:rdCobertura.Checked

        if (-not $cobertura -and [string]::IsNullOrWhiteSpace($ticket)) {
            Show-WarningMessage "Para desligamento Definitivo informe o numero do ticket."
            return
        }

        if ($ticket -and $ticket -notmatch '^\d+$') {
            Show-WarningMessage "O numero do ticket deve conter apenas digitos numericos."
            return
        }

        if (-not (Ensure-ADModule)) { return }

        try {
            $script:btnExecutar.Enabled = $false
            Set-AppStatus "Consultando usuario..."

            $u = Get-ADUser `
                -Identity $usuario `
                -Properties AccountExpirationDate, MemberOf, Description, info, DistinguishedName, DisplayName `
                -Credential $script:AdminCreds `
                -ErrorAction Stop

            $nome = Get-UserDisplayName $u

            $data = Get-FormattedExpirationDate $u

            if ($cobertura) {
                $novaDescricao = "Desativado - $setor - Final da Cobertura $data"
            }
            else {
                $novaDescricao = "Desativado - $setor - Ticket $ticket"
            }

            $confirmacao = @"
ATENCAO - OPERACAO CRITICA

Colaborador:
$nome

Login:
$usuario

Tipo de desligamento:
$(if ($cobertura) { "COBERTURA" } else { "DEFINITIVO" })

Nova descricao:
$novaDescricao

Esta operacao ira:

1. Desativar a conta
2. Alterar a descricao
3. Registrar o historico e os grupos atuais no atributo info
4. Remover o usuario dos grupos, exceto Domain Users
5. Mover a conta para:

$script:OUDestinoDesativados

Deseja continuar?
"@

            if (-not (Confirm-Action $confirmacao "Confirmar desligamento")) {
                return
            }

            $dataHoje = (Get-Date).ToString("dd/MM/yyyy HH:mm")
            $descricaoAntiga = if ($u.Description) { $u.Description } else { "[Sem descricao anterior]" }

            $gruposText = if ($u.MemberOf) {
                ($u.MemberOf | ForEach-Object { ($_ -split ',')[0].Replace('CN=', '') }) -join ", "
            }
            else {
                "[Nenhum grupo alem de Domain Users]"
            }

            $novoLog = Get-LogLine "Usuario DESATIVADO ($(if ($cobertura) { "Cobertura" } else { "Definitivo" })). Historico de Descricao anterior: $descricaoAntiga"
            $novoLog = "$novoLog`r`n$(Get-LogLine "Grupos no momento da desativacao: $gruposText")"

            if ($u.info) {
                $novoLog = "$novoLog`r`n$($u.info)"
            }

            Set-ADUser `
                -Identity $usuario `
                -Description $novaDescricao `
                -Replace @{info = $novoLog} `
                -Enabled $false `
                -Credential $script:AdminCreds `
                -ErrorAction Stop

            $gruposRemovidos = 0

            if ($u.MemberOf) {
                foreach ($grupo in $u.MemberOf) {
                    if ($grupo -notlike "*Domain Users*") {
                        Remove-ADGroupMember `
                            -Identity $grupo `
                            -Members $usuario `
                            -Credential $script:AdminCreds `
                            -Confirm:$false `
                            -ErrorAction Stop

                        $gruposRemovidos++
                    }
                }
            }

            Move-ADObject `
                -Identity $u.DistinguishedName `
                -TargetPath $script:OUDestinoDesativados `
                -Credential $script:AdminCreds `
                -ErrorAction Stop

            Show-InfoMessage @"
Usuario desativado com sucesso.

Colaborador: $nome
Login: $usuario

Descricao:
$novaDescricao

Grupos removidos: $gruposRemovidos
Grupos registrados no historico: $gruposText

Conta movida para:
$script:OUDestinoDesativados
"@

            $script:txtUsuario.Clear()
            $script:txtSetor.Clear()
            $script:txtTicket.Clear()
            $script:info.Text = "OU de destino:`r`n$script:OUDestinoDesativados"

            Set-AppStatus "Usuario desativado e movido."
        }
        catch {
            Show-ErrorMessage "Erro ao processar a desativacao:`r`n`r`n$($_.Exception.Message)"
        }
        finally {
            $script:btnExecutar.Enabled = $true
        }
    })
}

# ============================================================
# TELA - MOVER MAQUINAS PARA OU
# ============================================================

function Format-NomeComputador {
    param([string]$Nome)

    if ($null -eq $Nome) { return "" }
    $n = $Nome.Trim()
    if ($n.EndsWith('$')) { $n = $n.Substring(0, $n.Length - 1) }
    return $n.Trim()
}

function Convert-PathOUToDN {
    param([string]$Caminho)

    if ([string]::IsNullOrWhiteSpace($Caminho)) {
        return ""
    }

    $valor = $Caminho.Trim()

    if ($valor -match '^(?i)(OU|CN)=' -and $valor -match '(?i),DC=') {
        return $valor
    }

    $valor = $valor -replace '^(?i)https?://', ''
    $valor = $valor.Trim('/', ' ')

    $partes = @($valor -split '/' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($partes.Count -lt 2) {
        throw "Informe o caminho no formato dominio.com.br/WORKSTATIONS/.../OU/"
    }

    $dominio = $partes[0].Trim().ToLower()
    if ($dominio -notmatch '\.') {
        throw "O dominio informado deve seguir o formato dominio.com.br."
    }

    $ouBase = @($partes[1..($partes.Count - 1)])

    $dnOUs = @()
    for ($i = $ouBase.Count - 1; $i -ge 0; $i--) {
        $nomeOU = $ouBase[$i].Trim()
        if ([string]::IsNullOrWhiteSpace($nomeOU)) { continue }

        $nomeEscapado = $nomeOU.Replace('\', '\5c').Replace(',', '\2c').Replace('+', '\2b').Replace('"', '\22').Replace('<', '\3c').Replace('>', '\3e').Replace(';', '\3b').Replace('=', '\3d')
        $dnOUs += "OU=$nomeEscapado"
    }

    $dcs = @($dominio -split '\.' | ForEach-Object { "DC=$_" })

    return ((($dnOUs -join ',') ) + ',' + ($dcs -join ','))
}

function Test-OUExists {
    param([string]$OU)

    $dn = $null

    try {
        $dn = Convert-PathOUToDN $OU

        if ([string]::IsNullOrWhiteSpace($dn)) {
            throw "O campo da OU esta vazio."
        }

        $obj = Get-ADOrganizationalUnit `
            -Identity $dn `
            -Credential $script:AdminCreds `
            -ErrorAction Stop

        return [PSCustomObject]@{
            Sucesso = $true
            OU      = $obj
            DN      = $dn
            Erro    = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Sucesso = $false
            OU      = $null
            DN      = $dn
            Erro    = $_.Exception.Message
        }
    }
}

function Get-ComputerBySamName {
    param([string]$Nome)

    $n = Format-NomeComputador $Nome
    if ([string]::IsNullOrWhiteSpace($n)) { return $null }

    try {
        return Get-ADComputer `
            -Identity $n `
            -Properties DistinguishedName, Name, SamAccountName `
            -Credential $script:AdminCreds `
            -ErrorAction Stop
    }
    catch { return $null }
}

function Write-OpLog {
    param([string]$Message)

    if ($null -eq $script:log) { return }
    $script:log.AppendText("[$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')] $Message`r`n")
    $script:log.SelectionStart = $script:log.TextLength
    $script:log.ScrollToCaret()
}

function Update-ComputerCount {
    if ($null -eq $script:list) { return }

    $total = $script:list.Items.Count
    $ok = @($script:list.Items | Where-Object { $_.SubItems[2].Text -eq "Encontrada" -or $_.SubItems[2].Text -eq "Movida" }).Count
    $nao = @($script:list.Items | Where-Object { $_.SubItems[2].Text -eq "Nao encontrada" }).Count
    $script:contador.Text = "Maquinas: $total | Encontradas: $ok | Nao encontradas: $nao"
}

function Show-Maquinas {

    Clear-Content

    Add-StandardTitle `
        $content `
        "Mover maquinas para OU" `
        "Cole os nomes das maquinas, informe a OU de destino, valide e confirme a movimentacao."

    $gOU = New-GroupBox "OU de destino" 25 95 965 90
    $content.Controls.Add($gOU)

    $lblCaminho = New-Label "Caminho da OU:" 15 28 125 25
    $gOU.Controls.Add($lblCaminho)

    $script:txtOU = New-TextBox 140 25 700 28
    $script:txtOU.Text = "dominio.com.br/WORKSTATIONS/OU_PADRAO/"
    $gOU.Controls.Add($script:txtOU)

    $script:btnOU = New-ActionButton "Validar OU" 850 23 100 30 $script:Colors.Dark
    $gOU.Controls.Add($script:btnOU)

    $script:ouStatus = New-Label "Aceita caminho amigavel (dominio.com.br/...) ou DN do Active Directory." 140 58 800 22
    $gOU.Controls.Add($script:ouStatus)

    $gM = New-GroupBox "Maquinas" 25 200 335 380
    $content.Controls.Add($gM)

    $info = New-Label "Um computador por linha. Aceita PC-001 ou PC-001$." 15 28 300 40
    $gM.Controls.Add($info)

    $script:txtM = New-Object System.Windows.Forms.TextBox
    $script:txtM.Location = New-Object System.Drawing.Point(15, 75)
    $script:txtM.Size = New-Object System.Drawing.Size(300, 230)
    $script:txtM.Multiline = $true
    $script:txtM.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $script:txtM.AcceptsReturn = $true
    $script:txtM.Font = New-Object System.Drawing.Font("Consolas", 10)
    $gM.Controls.Add($script:txtM)

    $script:btnValidar = New-ActionButton "Validar maquinas" 15 320 140 35
    $gM.Controls.Add($script:btnValidar)

    $script:btnLimpar = New-ActionButton "Limpar" 170 320 140 35 $script:Colors.Dark
    $gM.Controls.Add($script:btnLimpar)

    $dica = New-Label "A validacao nao altera o AD. A movimentacao so ocorre apos confirmacao." 15 370 300 40
    $gM.Controls.Add($dica)

    $gR = New-GroupBox "Resultado da validacao" 375 200 615 240
    $content.Controls.Add($gR)

    $script:list = New-Object System.Windows.Forms.ListView
    $script:list.Location = New-Object System.Drawing.Point(15, 28)
    $script:list.Size = New-Object System.Drawing.Size(585, 170)
    $script:list.View = [System.Windows.Forms.View]::Details
    $script:list.FullRowSelect = $true
    $script:list.GridLines = $true
    $script:list.MultiSelect = $true
    $script:list.UseCompatibleStateImageBehavior = $false
    [void]$script:list.Columns.Add("Maquina", 130)
    [void]$script:list.Columns.Add("SamAccountName", 160)
    [void]$script:list.Columns.Add("Status", 110)
    [void]$script:list.Columns.Add("OU atual", 180)
    $gR.Controls.Add($script:list)

    $script:btnSel = New-ActionButton "Selecionar todas" 15 210 125 25 $script:Colors.Dark
    $gR.Controls.Add($script:btnSel)

    $script:btnDes = New-ActionButton "Desmarcar todas" 155 210 130 25 $script:Colors.Dark
    $gR.Controls.Add($script:btnDes)

    $script:contador = New-Label "Maquinas: 0 | Encontradas: 0 | Nao encontradas: 0" 300 213 300 25
    $gR.Controls.Add($script:contador)

    $gL = New-GroupBox "Log da operacao" 375 455 615 90
    $content.Controls.Add($gL)

    $script:log = New-Object System.Windows.Forms.TextBox
    $script:log.Location = New-Object System.Drawing.Point(15, 28)
    $script:log.Size = New-Object System.Drawing.Size(585, 52)
    $script:log.Multiline = $true
    $script:log.ReadOnly = $true
    $script:log.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $script:log.BackColor = [System.Drawing.Color]::White
    $script:log.Font = New-Object System.Drawing.Font("Consolas", 9)
    $gL.Controls.Add($script:log)

    $script:btnMover = New-ActionButton "CONFIRMAR E MOVER" 650 560 340 45 $script:Colors.Danger
    $content.Controls.Add($script:btnMover)

    $script:btnOU.Add_Click({
        $ou = $script:txtOU.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($ou)) {
            Show-WarningMessage "Informe a OU de destino."
            return
        }

        $x = Test-OUExists $ou

        if ($x.Sucesso) {
            $script:ouStatus.Text = "OU encontrada: $($x.OU.Name) | DN: $($x.DN)"
            $script:ouStatus.ForeColor = [System.Drawing.Color]::DarkGreen
            Set-AppStatus "OU validada."
        }
        else {
            $script:ouStatus.Text = "OU nao encontrada."
            $script:ouStatus.ForeColor = [System.Drawing.Color]::DarkRed
            Show-ErrorMessage "Nao foi possivel localizar a OU informada.`r`n`r`nCaminho informado:`r`n$ou`r`n`r`nDN convertido:`r`n$($x.DN)`r`n`r`n$($x.Erro)"
        }
    })

    $script:btnValidar.Add_Click({
        $script:list.Items.Clear()
        $script:log.Clear()

        $ou = $script:txtOU.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($ou)) {
            Show-WarningMessage "Informe a OU de destino."
            return
        }

        $validacaoOU = Test-OUExists $ou
        if (-not $validacaoOU.Sucesso) {
            Show-ErrorMessage "A OU de destino e invalida ou nao pode ser consultada.`r`n`r`nDN convertido:`r`n$($validacaoOU.DN)`r`n`r`n$($validacaoOU.Erro)"
            return
        }

        $nomes = @($script:txtM.Lines |
            ForEach-Object { Format-NomeComputador $_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique)

        if ($nomes.Count -eq 0) {
            Show-WarningMessage "Informe pelo menos uma maquina."
            return
        }

        $script:btnValidar.Enabled = $false
        $script:btnOU.Enabled = $false

        try {
            foreach ($nome in $nomes) {
                $item = New-Object System.Windows.Forms.ListViewItem($nome)
                $c = Get-ComputerBySamName $nome

                if ($null -ne $c) {
                    [void]$item.SubItems.Add($c.SamAccountName)
                    [void]$item.SubItems.Add("Encontrada")
                    [void]$item.SubItems.Add($c.DistinguishedName)
                    $item.ForeColor = [System.Drawing.Color]::DarkGreen
                    Write-OpLog "Encontrada: $($c.Name) | OU atual: $($c.DistinguishedName)"
                }
                else {
                    [void]$item.SubItems.Add("")
                    [void]$item.SubItems.Add("Nao encontrada")
                    [void]$item.SubItems.Add("")
                    $item.ForeColor = [System.Drawing.Color]::DarkRed
                    Write-OpLog "Nao encontrada: $nome"
                }

                [void]$script:list.Items.Add($item)
                $form.Refresh()
            }

            Update-ComputerCount
            Write-OpLog "Validacao concluida: $($nomes.Count) maquina(s)."
        }
        finally {
            $script:btnValidar.Enabled = $true
            $script:btnOU.Enabled = $true
        }
    })

    $script:btnSel.Add_Click({
        foreach ($i in $script:list.Items) {
            if ($i.SubItems[2].Text -eq "Encontrada" -or $i.SubItems[2].Text -eq "Movida") {
                $i.Selected = $true
            }
        }
    })

    $script:btnDes.Add_Click({
        $script:list.SelectedItems.Clear()
    })

    $script:btnLimpar.Add_Click({
        $script:txtM.Clear()
        $script:list.Items.Clear()
        $script:log.Clear()
        Update-ComputerCount
        $script:ouStatus.Text = "OU ainda nao validada."
        $script:ouStatus.ForeColor = [System.Drawing.SystemColors]::ControlText
    })

    $script:btnMover.Add_Click({
        $ou = $script:txtOU.Text.Trim()
        $validacaoOU = Test-OUExists $ou

        if (-not $validacaoOU.Sucesso) {
            Show-ErrorMessage "A OU de destino nao e valida.`r`n`r`nDN convertido:`r`n$($validacaoOU.DN)`r`n`r`n$($validacaoOU.Erro)"
            return
        }

        $ou = $validacaoOU.DN

        if ($script:list.Items.Count -eq 0) {
            Show-WarningMessage "Primeiro valide as maquinas."
            return
        }

        $selecionadas = @($script:list.SelectedItems | Where-Object { $_.SubItems[2].Text -eq "Encontrada" })
        if ($selecionadas.Count -eq 0) {
            $selecionadas = @($script:list.Items | Where-Object { $_.SubItems[2].Text -eq "Encontrada" })
        }

        if ($selecionadas.Count -eq 0) {
            Show-WarningMessage "Nenhuma maquina valida para mover."
            return
        }

        $nomes = ($selecionadas | ForEach-Object { $_.SubItems[0].Text }) -join ", "

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Serao movidas $($selecionadas.Count) maquina(s) para:`r`n`r`n$ou`r`n`r`nMaquinas: $nomes`r`n`r`nDeseja continuar?",
            "Confirmar movimentacao",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning)

        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $script:btnMover.Enabled = $false
        $script:btnValidar.Enabled = $false
        $script:btnOU.Enabled = $false

        $sucesso = 0
        $erros = 0

        try {
            foreach ($item in $selecionadas) {
                $nome = $item.SubItems[0].Text
                $dn = $item.SubItems[3].Text

                try {
                    Move-ADObject `
                        -Identity $dn `
                        -TargetPath $ou `
                        -Credential $script:AdminCreds `
                        -Confirm:$false `
                        -ErrorAction Stop

                    $item.SubItems[2].Text = "Movida"
                    $item.SubItems[3].Text = $ou
                    $item.ForeColor = [System.Drawing.Color]::DarkGreen
                    Write-OpLog "SUCESSO: $nome -> $ou"
                    $sucesso++
                }
                catch {
                    $item.SubItems[2].Text = "Erro"
                    $item.ForeColor = [System.Drawing.Color]::DarkRed
                    Write-OpLog "ERRO: $nome -> $($_.Exception.Message)"
                    $erros++
                }

                $form.Refresh()
            }
        }
        finally {
            $script:btnMover.Enabled = $true
            $script:btnValidar.Enabled = $true
            $script:btnOU.Enabled = $true
        }

        $icon = if ($erros -gt 0) { [System.Windows.Forms.MessageBoxIcon]::Warning }
                else { [System.Windows.Forms.MessageBoxIcon]::Information }

        [System.Windows.Forms.MessageBox]::Show(
            "Operacao concluida.`r`n`r`nMovidas: $sucesso`r`nErros: $erros",
            "Resultado",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            $icon) | Out-Null

        Update-ComputerCount
    })
}

# ============================================================
# TELA - HISTORICO DO USUARIO (atributo info/Observacoes)
# ============================================================

function Show-Log {

    Clear-Content

    Add-StandardTitle `
        $content `
        "Historico do usuario" `
        "Busque o usuario para visualizar as Observacoes (atributo info) do AD delegados as alteracoes."

    $nextY = Add-UserSearch 95 {
        param($login)

        $script:txtUsuario.Text = $login

        if (-not (Ensure-ADModule)) { return }

        try {
            $script:btnExecutar.Enabled = $false
            Set-AppStatus "Consultando historico..."

            $u = Get-ADUser `
                -Identity $login `
                -Properties info, DisplayName `
                -Credential $script:AdminCreds `
                -ErrorAction Stop

            $nome = Get-UserDisplayName $u

            if ($u.info) {
                $script:txtResultado.Text = "=== OBSERVACOES / HISTORICO DE: $login ==="
                $script:txtResultado.Text += "`r`n=== Nome: $nome ==="
                $script:txtResultado.Text += "`r`n`r`n$($u.info)"
            }
            else {
                $script:txtResultado.Text = "O usuario '$login' nao possui historico (atributo info vazio)."
            }

            Set-AppStatus "Historico carregado."
        }
        catch {
            Show-ErrorMessage "Erro ao consultar o historico:`r`n`r`n$($_.Exception.Message)"
        }
        finally {
            $script:btnExecutar.Enabled = $true
        }
    } 160

    $lblU = New-Label "Username do usuario:" 25 ($nextY + 5) 350 22
    $content.Controls.Add($lblU)

    $script:txtUsuario = New-TextBox 25 ($nextY + 30) 650 30
    $content.Controls.Add($script:txtUsuario)

    $script:btnExecutar = New-ActionButton "Carregar historico" 690 ($nextY + 28) 180 34
    $content.Controls.Add($script:btnExecutar)

    $script:txtResultado = New-Object System.Windows.Forms.TextBox
    $script:txtResultado.Location = New-Object System.Drawing.Point(25, ($nextY + 80))
    $script:txtResultado.Size = New-Object System.Drawing.Size(935, 380)
    $script:txtResultado.Multiline = $true
    $script:txtResultado.ReadOnly = $true
    $script:txtResultado.ScrollBars = "Both"
    $script:txtResultado.Font = New-Object System.Drawing.Font("Consolas", 9)
    $content.Controls.Add($script:txtResultado)

    $script:btnExecutar.Add_Click({
        $login = $script:txtUsuario.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($login)) {
            Show-WarningMessage "Digite o username do usuario."
            return
        }

        if (-not (Ensure-ADModule)) { return }

        try {
            $script:btnExecutar.Enabled = $false
            Set-AppStatus "Consultando historico..."

            $u = Get-ADUser `
                -Identity $login `
                -Properties info, DisplayName `
                -Credential $script:AdminCreds `
                -ErrorAction Stop

            $nome = Get-UserDisplayName $u

            if ($u.info) {
                $script:txtResultado.Text = "=== OBSERVACOES / HISTORICO DE: $login ==="
                $script:txtResultado.Text += "`r`n=== Nome: $nome ==="
                $script:txtResultado.Text += "`r`n`r`n$($u.info)"
            }
            else {
                $script:txtResultado.Text = "O usuario '$login' nao possui historico (atributo info vazio)."
            }

            Set-AppStatus "Historico carregado."
        }
        catch {
            Show-ErrorMessage "Erro ao consultar o historico:`r`n`r`n$($_.Exception.Message)"
        }
        finally {
            $script:btnExecutar.Enabled = $true
        }
    })
}

# ============================================================
# TELA - GERAR RELATORIO
# ============================================================

function Show-Report {

    Clear-Content

    Add-StandardTitle `
        $content `
        "Gerar relatorio" `
        "Gera relatorios a partir do Active Directory."

    $lblTipo = New-Label "Tipo de relatorio:" 25 100 200 22
    $content.Controls.Add($lblTipo)

    $script:cmbRelatorio = New-Object System.Windows.Forms.ComboBox
    $script:cmbRelatorio.Location = New-Object System.Drawing.Point(25, 125)
    $script:cmbRelatorio.Size = New-Object System.Drawing.Size(360, 28)
    $script:cmbRelatorio.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$script:cmbRelatorio.Items.Add("Usuarios por cargo")
    [void]$script:cmbRelatorio.Items.Add("Usuarios de cobertura")
    [void]$script:cmbRelatorio.Items.Add("Usuarios desativados")
    [void]$script:cmbRelatorio.Items.Add("Usuarios ativos")
    [void]$script:cmbRelatorio.Items.Add("Usuarios sem login ha mais de 90 dias")
    $script:cmbRelatorio.SelectedIndex = 0
    $content.Controls.Add($script:cmbRelatorio)

    $script:btnGerar = New-ActionButton "Gerar relatorio" 410 123 180 34 $script:Colors.Primary
    $content.Controls.Add($script:btnGerar)

    $script:txtRelatorio = New-Object System.Windows.Forms.TextBox
    $script:txtRelatorio.Location = New-Object System.Drawing.Point(25, 180)
    $script:txtRelatorio.Size = New-Object System.Drawing.Size(935, 470)
    $script:txtRelatorio.Multiline = $true
    $script:txtRelatorio.ReadOnly = $true
    $script:txtRelatorio.ScrollBars = "Both"
    $script:txtRelatorio.Font = New-Object System.Drawing.Font("Consolas", 9)
    $script:txtRelatorio.WordWrap = $true
    $content.Controls.Add($script:txtRelatorio)

    $script:btnGerar.Add_Click({

        if (-not (Ensure-ADModule)) { return }

        try {
            $tipo = $script:cmbRelatorio.SelectedItem.ToString()

            $script:btnGerar.Enabled = $false
            $script:btnGerar.Text = "Gerando..."
            Set-AppStatus "Gerando relatorio: $tipo..."

            $linhas = New-Object System.Collections.Generic.List[string]

            switch ($tipo) {
                "Usuarios por cargo" {
                    $usuarios = Get-ADUser `
                        -Filter { title -like "*" } `
                        -Properties title, Description, DisplayName `
                        -Credential $script:AdminCreds `
                        -ErrorAction Stop

                    $linhas.Add("=== USUARIOS POR CARGO ===")
                    $linhas.Add("")
                    $linhas.Add("Total: $($usuarios.Count)")
                    $qtdCargo = @{}

                    foreach ($u in $usuarios) {
                        $cargo = if ($u.title) { $u.title } else { "[Sem cargo]" }
                        if ($qtdCargo.ContainsKey($cargo)) {
                            $qtdCargo[$cargo]++
                        }
                        else {
                            $qtdCargo[$cargo] = 1
                        }
                    }

                    $linhas.Add("")
                    $linhas.Add("--- Resumo por cargo ---")
                    foreach ($c in ($qtdCargo.GetEnumerator() | Sort-Object Value -Descending)) {
                        $linhas.Add("$($c.Key): $($c.Value) usuario(s)")
                    }

                    $linhas.Add("")
                    $linhas.Add("--- Detalhamento ---")
                    foreach ($u in ($usuarios | Sort-Object title, DisplayName)) {
                        $cargo = if ($u.title) { $u.title } else { "[Sem cargo]" }
                        $linhas.Add("$cargo | $($u.DisplayName) | $($u.SamAccountName)")
                    }
                }
                "Usuarios de cobertura" {
                    $usuarios = Get-ADUser `
                        -Filter { (enabled -eq $true) -and (description -like "*Cobertura*") } `
                        -Properties Description, AccountExpirationDate, DisplayName `
                        -Credential $script:AdminCreds `
                        -ErrorAction Stop

                    $linhas.Add("=== USUARIOS DE COBERTURA ===")
                    $linhas.Add("")
                    $linhas.Add("Total: $($usuarios.Count)")
                    $linhas.Add("")

                    foreach ($u in ($usuarios | Sort-Object DisplayName)) {
                        $exp = Get-FormattedExpirationDate $u
                        $linhas.Add("$($u.DisplayName) | $($u.SamAccountName) | Final: $exp")
                    }
                }
                "Usuarios desativados" {
                    $usuarios = Get-ADUser `
                        -Filter { enabled -eq $false } `
                        -Properties Description, DisplayName `
                        -Credential $script:AdminCreds `
                        -ErrorAction Stop

                    $linhas.Add("=== USUARIOS DESATIVADOS ===")
                    $linhas.Add("")
                    $linhas.Add("Total: $($usuarios.Count)")
                    $linhas.Add("")

                    foreach ($u in ($usuarios | Sort-Object DisplayName)) {
                        $linhas.Add("$($u.DisplayName) | $($u.SamAccountName) | $($u.Description)")
                    }
                }
                "Usuarios ativos" {
                    $usuarios = Get-ADUser `
                        -Filter { enabled -eq $true } `
                        -Properties Description, DisplayName `
                        -Credential $script:AdminCreds `
                        -ErrorAction Stop

                    $linhas.Add("=== USUARIOS ATIVOS ===")
                    $linhas.Add("")
                    $linhas.Add("Total: $($usuarios.Count)")
                    $linhas.Add("")

                    foreach ($u in ($usuarios | Sort-Object DisplayName)) {
                        $linhas.Add("$($u.DisplayName) | $($u.SamAccountName) | $($u.Description)")
                    }
                }
                "Usuarios sem login ha mais de 90 dias" {
                    $corte = (Get-Date).AddDays(-90)

                    $usuarios = Get-ADUser `
                        -Filter { enabled -eq $true } `
                        -Properties LastLogonDate, DisplayName `
                        -Credential $script:AdminCreds `
                        -ErrorAction Stop

                    $semLogin = @($usuarios | Where-Object { -not $_.LastLogonDate -or $_.LastLogonDate -lt $corte })

                    $linhas.Add("=== USUARIOS ATIVOS SEM LOGIN HA MAIS DE 90 DIAS ===")
                    $linhas.Add("")
                    $linhas.Add("Corte de referencia: $($corte.ToString('dd/MM/yyyy'))")
                    $linhas.Add("Total: $($semLogin.Count)")
                    $linhas.Add("")

                    foreach ($u in ($semLogin | Sort-Object LastLogonDate)) {
                        $dataLogin = if ($u.LastLogonDate) { $u.LastLogonDate.ToString("dd/MM/yyyy HH:mm") } else { "[Nunca logou]" }
                        $linhas.Add("$($u.DisplayName) | $($u.SamAccountName) | Ultimo login: $dataLogin")
                    }
                }
            }

            $script:txtRelatorio.Text = $linhas -join "`r`n"
            Set-AppStatus "Relatorio '$tipo' gerado ($($usuarios.Count) usuario(s))."
        }
        catch {
            Show-ErrorMessage "Erro ao gerar o relatorio:`r`n`r`n$($_.Exception.Message)"
        }
        finally {
            $script:btnGerar.Enabled = $true
            $script:btnGerar.Text = "Gerar relatorio"
        }
    })
}

# ============================================================
# CADASTRO / PADRONIZACAO DE USUARIOS
# ============================================================

$script:ProfilesCadastro = @{
    "Servidor" = @{
        EmpresaObrigatoria   = $true
        EmpresaEsperada      = $null
        CargoObrigatorio     = $true
        DepartamentoObrig    = $true
        EmailObrigatorio     = $true
    }
    "Colaborador" = @{
        EmpresaObrigatoria   = $true
        EmpresaEsperada      = $null
        CargoObrigatorio     = $true
        DepartamentoObrig    = $true
        EmailObrigatorio     = $true
    }
    "Estagiario" = @{
        EmpresaObrigatoria   = $true
        EmpresaEsperada      = $null
        CargoObrigatorio     = $true
        DepartamentoObrig    = $true
        EmailObrigatorio     = $true
    }
}

function Test-CadastroCompletude {
    param(
        [string]$Perfil,
        [string]$Empresa,
        [string]$Cargo,
        [string]$Departamento,
        [string]$Email
    )

    $linhas = New-Object System.Collections.Generic.List[string]

    if (-not $script:ProfilesCadastro.ContainsKey($Perfil)) {
        $linhas.Add("INVALIDO - Perfil $Perfil nao reconhecido")
        return @($linhas)
    }

    $p = $script:ProfilesCadastro[$Perfil]

    foreach ($chave in @('Empresa','Cargo','Departamento','Email')) {
        $valor = switch ($chave) {
            'Empresa'     { $Empresa }
            'Cargo'       { $Cargo }
            'Departamento' { $Departamento }
            'Email'       { $Email }
        }

        $obrigatorio = switch ($chave) {
            'Empresa'     { $p.EmpresaObrigatoria }
            'Cargo'       { $p.CargoObrigatorio }
            'Departamento' { $p.DepartamentoObrig }
            'Email'       { $p.EmailObrigatorio }
        }

        $preenchido = -not [string]::IsNullOrWhiteSpace($valor)

        if ($obrigatorio -and -not $preenchido) {
            $linhas.Add("FALTA - $chave")
        }
        elseif ($preenchido -and $chave -eq 'Empresa' -and $p.EmpresaEsperada -and $valor -ne $p.EmpresaEsperada) {
            $linhas.Add("ATENCAO - Empresa esperada: $($p.EmpresaEsperada) (atual: $valor)")
        }
        else {
            $linhas.Add("OK - $chave")
        }
    }

    return @($linhas)
}

function Show-Cadastro {

    Clear-Content

    Add-StandardTitle `
        $content `
        "Cadastro de usuario" `
        "Crie um novo usuario ou busque um existente e padronize seus dados conforme os valores padronizados."

    $script:cadLogin = ""
    $script:cadNome = ""
    $script:cadUserAD = $null

    $script:rdbModoEditar = New-Object System.Windows.Forms.RadioButton
    $script:rdbModoEditar.Text = "Editar usuario existente"
    $script:rdbModoEditar.Location = New-Object System.Drawing.Point(25, 95)
    $script:rdbModoEditar.Size = New-Object System.Drawing.Size(190, 24)
    $script:rdbModoEditar.Checked = $true
    $content.Controls.Add($script:rdbModoEditar)

    $script:rdbModoCriar = New-Object System.Windows.Forms.RadioButton
    $script:rdbModoCriar.Text = "Criar novo usuario"
    $script:rdbModoCriar.Location = New-Object System.Drawing.Point(235, 95)
    $script:rdbModoCriar.Size = New-Object System.Drawing.Size(170, 24)
    $content.Controls.Add($script:rdbModoCriar)

    $nextY = Add-UserSearch 145 {
        param($login)
        $script:cadLogin = $login

        if (-not (Ensure-ADModule)) { return }

        try {
            $u = Get-ADUser `
                -Identity $login `
                -Properties givenName, sn, DisplayName, Mail, Enabled, title, department, company, `
                    physicalDeliveryOfficeName, employeeType, telephoneNumber, mobile, `
                    Description, info, AccountExpirationDate `
                -Credential $script:AdminCreds `
                -ErrorAction Stop

            $script:cadNome = Get-UserDisplayName $u
            $script:cadUserAD = $u

            $script:lblInfoNome.Text = "Nome:  " + (Get-UserDisplayName $u)
            $script:lblInfoLogin.Text = "Login:  $login"
            $script:lblInfoEmail.Text = "E-mail:  " + $(if ($u.Mail) { $u.Mail } else { "nao informado" })
            $script:lblInfoStatus.Text = "Status:  " + $(if ($u.Enabled) { "ATIVO" } else { "DESATIVADO" })

            $script:txtDisplayName.Text = [string]$u.DisplayName
            $script:cmbCargo.Text = [string]$u.title
            $script:cmbDepartamento.Text = [string]$u.department
            $script:cmbEmpresa.Text = [string]$u.company
            $script:cmbEscritorio.Text = [string]$u.physicalDeliveryOfficeName
            $script:txtEmail.Text = [string]$u.Mail
            $script:txtTelefone.Text = [string]$u.telephoneNumber
            $script:txtTicket.Text = ""
            $script:chkCobertura.Checked = $false

            $setorAD = ""
            if ($u.Description) {
                $setorAD = (($u.Description -split ' - ')[0]).Trim()
            }

            if ($setorAD -and $script:cmbSetor.Items.Contains($setorAD)) {
                $script:cmbSetor.SelectedItem = $setorAD
            }
            else {
                $script:cmbSetor.Text = $setorAD
            }

            $vinculo = [string]$u.employeeType
            if ($script:cmbVinculo.Items.Contains($vinculo)) {
                $script:cmbVinculo.SelectedItem = $vinculo
            }
            else {
                $script:cmbVinculo.SelectedIndex = 0
            }

            $desc = [string]$u.Description
            if ($vinculo -eq "Colaborador" -and $desc -match "Final da Cobertura") {
                $script:chkCobertura.Checked = $true
                $m = [regex]::Match($desc, 'Ticket\s+(\S+)')
                if ($m.Success) {
                    $script:txtTicket.Text = $m.Groups[1].Value.Trim()
                }
            }
            elseif ($desc -match 'Ticket\s+(\S+)') {
                $m = [regex]::Match($desc, 'Ticket\s+(\S+)')
                if ($m.Success) {
                    $script:txtTicket.Text = $m.Groups[1].Value.Trim()
                }
            }

            Set-AppStatus "Usuario carregado: $login"
        }
        catch {
            Show-ErrorMessage "Erro ao carregar o usuario:`r`n`r`n$($_.Exception.Message)"
        }
    } 140

    $script:boxNovo = New-GroupBox "Novo usuario" 25 145 935 160
    $script:boxNovo.Visible = $false
    $content.Controls.Add($script:boxNovo)

    $lblCadLogin = New-Label "Login (SAM):" 20 24 150 22
    $script:boxNovo.Controls.Add($lblCadLogin)

    $script:txtCadLogin = New-TextBox 20 48 400 28
    $script:boxNovo.Controls.Add($script:txtCadLogin)

    $lblCadOU = New-Label "OU de destino (DN):" 480 24 200 22
    $script:boxNovo.Controls.Add($lblCadOU)

    $script:txtCadOU = New-TextBox 480 48 430 28
    $script:txtCadOU.Text = $script:Padroes.OUUsuarios
    $script:boxNovo.Controls.Add($script:txtCadOU)

    $lblCadObs = New-Label "E-mail e descricao serao gerados automaticamente a partir do login e dos campos abaixo." 20 100 800 22
    $lblCadObs.ForeColor = $script:Colors.Muted
    $script:boxNovo.Controls.Add($lblCadObs)

    $script:boxInfo = New-GroupBox "Usuario encontrado" 25 ($nextY + 5) 935 100
    $content.Controls.Add($script:boxInfo)

    $script:lblInfoNome = New-Object System.Windows.Forms.Label
    $script:lblInfoNome.Location = New-Object System.Drawing.Point(20, 20)
    $script:lblInfoNome.Size = New-Object System.Drawing.Size(420, 22)
    $script:lblInfoNome.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $script:lblInfoNome.ForeColor = $script:Colors.Text
    $script:boxInfo.Controls.Add($script:lblInfoNome)

    $script:lblInfoLogin = New-Object System.Windows.Forms.Label
    $script:lblInfoLogin.Location = New-Object System.Drawing.Point(20, 48)
    $script:lblInfoLogin.Size = New-Object System.Drawing.Size(420, 22)
    $script:lblInfoLogin.ForeColor = $script:Colors.Text
    $script:boxInfo.Controls.Add($script:lblInfoLogin)

    $script:lblInfoEmail = New-Object System.Windows.Forms.Label
    $script:lblInfoEmail.Location = New-Object System.Drawing.Point(480, 20)
    $script:lblInfoEmail.Size = New-Object System.Drawing.Size(440, 22)
    $script:lblInfoEmail.ForeColor = $script:Colors.Text
    $script:boxInfo.Controls.Add($script:lblInfoEmail)

    $script:lblInfoStatus = New-Object System.Windows.Forms.Label
    $script:lblInfoStatus.Location = New-Object System.Drawing.Point(480, 48)
    $script:lblInfoStatus.Size = New-Object System.Drawing.Size(440, 22)
    $script:lblInfoStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $script:lblInfoStatus.ForeColor = $script:Colors.Text
    $script:boxInfo.Controls.Add($script:lblInfoStatus)

    $script:boxDados = New-GroupBox "Dados organizacionais" 25 ($nextY + 120) 935 225
    $content.Controls.Add($script:boxDados)

    $lblVinculo = New-Label "Vinculo:" 20 24 120 22
    $script:boxDados.Controls.Add($lblVinculo)

    $script:cmbVinculo = New-Object System.Windows.Forms.ComboBox
    $script:cmbVinculo.Location = New-Object System.Drawing.Point(20, 48)
    $script:cmbVinculo.Size = New-Object System.Drawing.Size(220, 28)
    $script:cmbVinculo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$script:cmbVinculo.Items.Add("Servidor")
    [void]$script:cmbVinculo.Items.Add("Colaborador")
    [void]$script:cmbVinculo.Items.Add("Estagiario")
    $script:cmbVinculo.SelectedIndex = 0
    $script:boxDados.Controls.Add($script:cmbVinculo)

    $lblSetor = New-Label "Setor / Sigla:" 270 24 150 22
    $script:boxDados.Controls.Add($lblSetor)

    $script:cmbSetor = New-Object System.Windows.Forms.ComboBox
    $script:cmbSetor.Location = New-Object System.Drawing.Point(270, 48)
    $script:cmbSetor.Size = New-Object System.Drawing.Size(220, 28)
    $script:cmbSetor.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    foreach ($v in $script:Padroes.Setores) { [void]$script:cmbSetor.Items.Add($v) }
    $script:boxDados.Controls.Add($script:cmbSetor)

    $lblDisplayName = New-Label "Nome completo:" 20 86 160 22
    $script:boxDados.Controls.Add($lblDisplayName)

    $script:txtDisplayName = New-TextBox 20 110 420 28
    $script:boxDados.Controls.Add($script:txtDisplayName)

    $lblCargo = New-Label "Cargo:" 20 148 100 22
    $script:boxDados.Controls.Add($lblCargo)

    $script:cmbCargo = New-Object System.Windows.Forms.ComboBox
    $script:cmbCargo.Location = New-Object System.Drawing.Point(20, 172)
    $script:cmbCargo.Size = New-Object System.Drawing.Size(420, 28)
    $script:cmbCargo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    foreach ($v in $script:Padroes.Cargos) { [void]$script:cmbCargo.Items.Add($v) }
    $script:boxDados.Controls.Add($script:cmbCargo)

    $lblDepartamento = New-Label "Departamento:" 480 86 150 22
    $script:boxDados.Controls.Add($lblDepartamento)

    $script:cmbDepartamento = New-Object System.Windows.Forms.ComboBox
    $script:cmbDepartamento.Location = New-Object System.Drawing.Point(480, 110)
    $script:cmbDepartamento.Size = New-Object System.Drawing.Size(430, 28)
    $script:cmbDepartamento.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    foreach ($v in $script:Padroes.Departamentos) { [void]$script:cmbDepartamento.Items.Add($v) }
    $script:boxDados.Controls.Add($script:cmbDepartamento)

    $lblEmpresa = New-Label "Empresa:" 480 148 100 22
    $script:boxDados.Controls.Add($lblEmpresa)

    $script:cmbEmpresa = New-Object System.Windows.Forms.ComboBox
    $script:cmbEmpresa.Location = New-Object System.Drawing.Point(480, 172)
    $script:cmbEmpresa.Size = New-Object System.Drawing.Size(430, 28)
    $script:cmbEmpresa.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    foreach ($v in $script:Padroes.Empresas) { [void]$script:cmbEmpresa.Items.Add($v) }
    $script:boxDados.Controls.Add($script:cmbEmpresa)

    $script:boxContato = New-GroupBox "Contato" 25 ($nextY + 365) 935 100
    $content.Controls.Add($script:boxContato)

    $lblEmail = New-Label "E-mail:" 20 24 100 22
    $script:boxContato.Controls.Add($lblEmail)

    $script:txtEmail = New-TextBox 20 48 420 28
    $script:boxContato.Controls.Add($script:txtEmail)

    $lblEscritorio = New-Label "Escritorio / Unidade:" 480 24 180 22
    $script:boxContato.Controls.Add($lblEscritorio)

    $script:cmbEscritorio = New-Object System.Windows.Forms.ComboBox
    $script:cmbEscritorio.Location = New-Object System.Drawing.Point(480, 48)
    $script:cmbEscritorio.Size = New-Object System.Drawing.Size(220, 28)
    $script:cmbEscritorio.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    foreach ($v in $script:Padroes.Escritorios) { [void]$script:cmbEscritorio.Items.Add($v) }
    $script:boxContato.Controls.Add($script:cmbEscritorio)

    $lblTelefone = New-Label "Telefone:" 720 24 100 22
    $script:boxContato.Controls.Add($lblTelefone)

    $script:txtTelefone = New-TextBox 720 48 190 28
    $script:boxContato.Controls.Add($script:txtTelefone)

    $script:boxDesc = New-GroupBox "Descricao" 25 ($nextY + 480) 935 200
    $content.Controls.Add($script:boxDesc)

    $lblDescHint = New-Label "Modelo: SETOR - Ticket NUMERO  |  Colaborador de cobertura: SETOR - Final da Cobertura DATA - Ticket NUMERO" 20 24 860 22
    $lblDescHint.ForeColor = $script:Colors.Muted
    $script:boxDesc.Controls.Add($lblDescHint)

    $lblTicket = New-Label "Numero do ticket:" 20 58 150 22
    $script:boxDesc.Controls.Add($lblTicket)

    $script:txtTicket = New-TextBox 20 82 200 28
    $script:boxDesc.Controls.Add($script:txtTicket)

    $script:chkCobertura = New-Object System.Windows.Forms.CheckBox
    $script:chkCobertura.Text = "E da cobertura (somente Colaborador)"
    $script:chkCobertura.Location = New-Object System.Drawing.Point(250, 84)
    $script:chkCobertura.Size = New-Object System.Drawing.Size(300, 24)
    $script:boxDesc.Controls.Add($script:chkCobertura)

    $script:txtDescricao = New-Object System.Windows.Forms.TextBox
    $script:txtDescricao.Location = New-Object System.Drawing.Point(20, 116)
    $script:txtDescricao.Size = New-Object System.Drawing.Size(640, 60)
    $script:txtDescricao.Multiline = $true
    $script:txtDescricao.ScrollBars = "Vertical"
    $script:txtDescricao.Font = New-Object System.Drawing.Font("Consolas", 10)
    $script:boxDesc.Controls.Add($script:txtDescricao)

    $script:btnGerarDesc = New-ActionButton "Gerar descricao" 680 116 230 30 $script:Colors.Dark
    $script:boxDesc.Controls.Add($script:btnGerarDesc)

    $script:boxAudit = New-GroupBox "Consistencia do cadastro" 25 ($nextY + 695) 935 155
    $content.Controls.Add($script:boxAudit)

    $script:txtAuditCadastro = New-Object System.Windows.Forms.TextBox
    $script:txtAuditCadastro.Location = New-Object System.Drawing.Point(20, 24)
    $script:txtAuditCadastro.Size = New-Object System.Drawing.Size(660, 105)
    $script:txtAuditCadastro.Multiline = $true
    $script:txtAuditCadastro.ReadOnly = $true
    $script:txtAuditCadastro.ScrollBars = "Vertical"
    $script:txtAuditCadastro.Font = New-Object System.Drawing.Font("Consolas", 9)
    $script:boxAudit.Controls.Add($script:txtAuditCadastro)

    $script:btnPrevia = New-ActionButton "Pre-visualizar" 700 24 210 40 $script:Colors.Primary
    $script:boxAudit.Controls.Add($script:btnPrevia)

    $script:btnLimpar = New-ActionButton "Limpar" 700 72 210 34 $script:Colors.Dark
    $script:boxAudit.Controls.Add($script:btnLimpar)

    $script:btnAtualizar = New-ActionButton "Atualizar usuario" 25 ($nextY + 880) 935 45 $script:Colors.Success
    $content.Controls.Add($script:btnAtualizar)

    $script:UpdateCadastroModo = {
        $criar = $script:rdbModoCriar.Checked

        $script:lblCampoBusca.Visible = -not $criar
        $script:cbCampo.Visible     = -not $criar
        $script:txtBusca.Visible    = -not $criar
        $script:btnPesquisar.Visible = -not $criar
        $script:btnUsar.Visible     = -not $criar
        $script:list.Visible        = -not $criar
        $script:boxInfo.Visible     = -not $criar
        $script:boxNovo.Visible     = $criar

        if ($criar) {
            $script:btnAtualizar.Text = "Criar usuario"
            $yDados = 320
            $yContato = 565
            $yDesc = 680
            $yAudit = 895
            $yBtn = 1080
        }
        else {
            $script:btnAtualizar.Text = "Atualizar usuario"
            $yDados = $nextY + 120
            $yContato = $nextY + 365
            $yDesc = $nextY + 480
            $yAudit = $nextY + 695
            $yBtn = $nextY + 880
        }

        $script:boxDados.Location = New-Object System.Drawing.Point(25, $yDados)
        $script:boxContato.Location = New-Object System.Drawing.Point(25, $yContato)
        $script:boxDesc.Location = New-Object System.Drawing.Point(25, $yDesc)
        $script:boxAudit.Location = New-Object System.Drawing.Point(25, $yAudit)
        $script:btnAtualizar.Location = New-Object System.Drawing.Point(25, $yBtn)
    }

    $script:rdbModoEditar.Add_CheckedChanged({ & $script:UpdateCadastroModo })
    $script:rdbModoCriar.Add_CheckedChanged({ & $script:UpdateCadastroModo })

    $script:txtCadLogin.Add_TextChanged({
        if ($script:rdbModoCriar.Checked) {
            $login = $script:txtCadLogin.Text.Trim()
            if ($login) {
                $script:txtEmail.Text = "$login@$($script:Padroes.EmailDominio)"
            }
            else {
                $script:txtEmail.Text = ""
            }
        }
    })

    $script:btnGerarDesc.Add_Click({
        $setor = $script:cmbSetor.Text.Trim().ToUpper()
        $ticket = $script:txtTicket.Text.Trim()
        $perfil = $script:cmbVinculo.SelectedItem.ToString()
        $cobertura = ($perfil -eq "Colaborador" -and $script:chkCobertura.Checked)

        if (-not $setor) {
            Show-WarningMessage "Informe o Setor antes de gerar a descricao."
            return
        }

        if (-not $ticket) {
            Show-WarningMessage "Informe o numero do ticket."
            return
        }

        if ($cobertura) {
            $dataFim = Get-FormattedExpirationDate $script:cadUserAD
            $script:txtDescricao.Text = "$setor - Final da Cobertura $dataFim - Ticket $ticket"
        }
        else {
            $script:txtDescricao.Text = "$setor - Ticket $ticket"
        }
    })

    $script:chkCobertura.Add_CheckedChanged({
        if ($script:chkCobertura.Checked) {
            $perfil = $script:cmbVinculo.SelectedItem.ToString()
            if ($perfil -ne "Colaborador") {
                $script:chkCobertura.Checked = $false
                Show-WarningMessage "Cobertura somente se aplica a Colaboradores."
            }
        }
    })

    $script:btnLimpar.Add_Click({
        $script:cadLogin = ""
        $script:cadNome = ""
        $script:cadUserAD = $null

        foreach ($nome in @('lblInfoNome','lblInfoLogin','lblInfoEmail','lblInfoStatus')) {
            (Get-Variable -Name $nome -Scope Script).Value.Text = ""
        }

        foreach ($nome in @('txtCadLogin','txtDisplayName','txtEmail','txtTelefone','txtTicket','txtDescricao','txtAuditCadastro')) {
            (Get-Variable -Name $nome -Scope Script).Value.Clear()
        }

        $script:txtCadOU.Text = $script:Padroes.OUUsuarios

        foreach ($nome in @('cmbSetor','cmbCargo','cmbDepartamento','cmbEmpresa','cmbEscritorio')) {
            (Get-Variable -Name $nome -Scope Script).Value.Text = ""
        }

        $script:cmbVinculo.SelectedIndex = 0
        $script:chkCobertura.Checked = $false
        Set-AppStatus "Campos limpos."
    })

    $script:btnPrevia.Add_Click({
        $perfil = $script:cmbVinculo.SelectedItem.ToString()
        $empresa = $script:cmbEmpresa.Text.Trim()
        $cargo = $script:cmbCargo.Text.Trim()
        $departamento = $script:cmbDepartamento.Text.Trim()
        $email = $script:txtEmail.Text.Trim()

        $resultado = Test-CadastroCompletude $perfil $empresa $cargo $departamento $email

        $inconsistentes = 0
        $linhas = @()
        foreach ($r in $resultado) {
            if ($r -like "FALTA*" -or $r -like "ATENCAO*") { $inconsistentes++ }
            $linhas += $r
        }

        $setor = $script:cmbSetor.Text.Trim()
        if (-not $setor) { $inconsistentes++; $linhas += "FALTA - Setor" }
        if (-not $script:txtTicket.Text.Trim()) { $inconsistentes++; $linhas += "FALTA - Ticket" }

        $script:txtAuditCadastro.Text = "PERFIL: $perfil" + "`r`n" + ($linhas -join "`r`n") + "`r`n`r`n$inconsistentes pendencia(s) encontrada(s)."

        $desc = $script:txtDescricao.Text.Trim()
        $msgExtra = ""
        if ($script:rdbModoCriar.Checked) {
            $msgExtra = "LOGIN: $($script:txtCadLogin.Text.Trim())`r`nOU: $($script:txtCadOU.Text.Trim())`r`n"
        }
        $msg = "Pre-visualizacao`r`n`r`n$msgExtra`r`nPERFIL: $perfil`r`nSETOR: $setor`r`nEMPRESA: $empresa`r`nCARGO: $cargo`r`nDEPARTAMENTO: $departamento`r`nEMAIL: $email`r`nCOBERTURA: $(if ($perfil -eq "Colaborador" -and $script:chkCobertura.Checked) { "Sim" } else { "Nao" })`r`n`r`nDESCRICAO:`r`n$desc`r`n`r`nPendencias: $inconsistentes"

        Show-InfoMessage $msg
    })

    $script:btnAtualizar.Add_Click({

        if ($script:rdbModoCriar.Checked) {
            $cadLogin = $script:txtCadLogin.Text.Trim()
            $cadNome = $script:txtDisplayName.Text.Trim()
            $cadPerfil = $script:cmbVinculo.SelectedItem.ToString()
            $cadEmpresa = $script:cmbEmpresa.Text.Trim()
            $cadDepartamento = $script:cmbDepartamento.Text.Trim()
            $cadCargo = $script:cmbCargo.Text.Trim()
            $cadEscritorio = $script:cmbEscritorio.Text.Trim()
            $cadEmail = $script:txtEmail.Text.Trim()
            $cadOU = $script:txtCadOU.Text.Trim()
            $cadSetor = $script:cmbSetor.Text.Trim()
            $cadDescricao = $script:txtDescricao.Text.Trim()

            if ([string]::IsNullOrWhiteSpace($cadLogin) -or
                [string]::IsNullOrWhiteSpace($cadNome) -or
                [string]::IsNullOrWhiteSpace($cadCargo) -or
                [string]::IsNullOrWhiteSpace($cadDepartamento) -or
                [string]::IsNullOrWhiteSpace($cadEmpresa) -or
                [string]::IsNullOrWhiteSpace($cadEscritorio) -or
                [string]::IsNullOrWhiteSpace($cadOU) -or
                [string]::IsNullOrWhiteSpace($cadSetor) -or
                [string]::IsNullOrWhiteSpace($cadDescricao)) {
                Show-WarningMessage "Preencha todos os campos para criar o usuario (inclua a descricao, gerada pelo botao 'Gerar descricao')."
                return
            }

            if ($cadLogin -notmatch '^[a-z0-9][a-z0-9.\-_]*$') {
                Show-WarningMessage "Login invalido. Use apenas letras minusculas, numeros, ponto, hifen e underscore."
                return
            }

            if ($script:Padroes.Empresas -and $script:Padroes.Empresas -notcontains $cadEmpresa) {
                Show-WarningMessage "Empresa '$cadEmpresa' nao esta na lista padronizada. Cadastre-a em Valores padronizados."
                return
            }
            if ($script:Padroes.Departamentos -and $script:Padroes.Departamentos -notcontains $cadDepartamento) {
                Show-WarningMessage "Departamento '$cadDepartamento' nao esta na lista padronizada."
                return
            }
            if ($script:Padroes.Cargos -and $script:Padroes.Cargos -notcontains $cadCargo) {
                Show-WarningMessage "Cargo '$cadCargo' nao esta na lista padronizada."
                return
            }
            if ($script:Padroes.Escritorios -and $script:Padroes.Escritorios -notcontains $cadEscritorio) {
                Show-WarningMessage "Escritorio '$cadEscritorio' nao esta na lista padronizada."
                return
            }
            if ($script:Padroes.Setores -and $script:Padroes.Setores -notcontains $cadSetor) {
                Show-WarningMessage "Setor '$cadSetor' nao esta na lista padronizada."
                return
            }

            if (-not (Ensure-ADModule)) { return }

            try {
                Get-ADUser -Identity $cadLogin -Credential $script:AdminCreds -ErrorAction Stop | Out-Null
                Show-WarningMessage "Login '$cadLogin' ja existe no Active Directory."
                return
            }
            catch {
            }

            $cadUpn = "$cadLogin@$($script:Padroes.EmailDominio)"

            if (-not (Confirm-Action `
                "Novo usuario:`r`n`r`nNome:  $cadNome`r`nLogin: $cadLogin`r`nUPN:   $cadUpn`r`nVinculo: $cadPerfil`r`nSetor:  $cadSetor`r`nCargo:  $cadCargo`r`nDepartamento: $cadDepartamento`r`nEmpresa: $cadEmpresa`r`nEscritorio: $cadEscritorio`r`nOU:     $cadOU`r`n`r`nDescricao:`r`n$cadDescricao`r`n`r`nDeseja criar o usuario?" `
                "Confirmar cadastro")) {
                return
            }

            try {
                $script:btnAtualizar.Enabled = $false
                $script:btnAtualizar.Text = "Criando..."
                Set-AppStatus "Criando usuario..."

                $senha = "#NovaSenha@$((Get-Random -Maximum 99999).ToString('00000'))"
                $sec = ConvertTo-SecureString $senha -AsPlainText -Force

                New-ADUser `
                    -SamAccountName $cadLogin `
                    -UserPrincipalName $cadUpn `
                    -Name $cadNome `
                    -DisplayName $cadNome `
                    -GivenName $cadNome `
                    -Title $cadCargo `
                    -Department $cadDepartamento `
                    -Company $cadEmpresa `
                    -Office $cadEscritorio `
                    -EmployeeType $cadPerfil `
                    -EmailAddress $cadEmail `
                    -Description $cadDescricao `
                    -Path $cadOU `
                    -AccountPassword $sec `
                    -ChangePasswordAtLogon $true `
                    -Enabled $true `
                    -Credential $script:AdminCreds `
                    -ErrorAction Stop

                $novoLog = Get-LogLine "Usuario criado pelo cadastro. Perfil: $cadPerfil, Cargo: $cadCargo, Departamento: $cadDepartamento, Empresa: $cadEmpresa, Escritorio: $cadEscritorio, Setor: $cadSetor."

                Set-ADUser `
                    -Identity $cadLogin `
                    -Replace @{info = $novoLog} `
                    -Credential $script:AdminCreds `
                    -ErrorAction SilentlyContinue

                Show-InfoMessage "Usuario '$cadLogin' criado com sucesso.`r`n`r`nSenha temporaria (copia abaixo):`r`n$senha`r`n`r`nO usuario devera trocar a senha no proximo login."

                $script:txtCadLogin.Clear()
                $script:txtDisplayName.Clear()
                $script:txtEmail.Clear()
                $script:txtDescricao.Clear()
                $script:txtTicket.Clear()
                $script:cmbSetor.Text = ""
                $script:cmbCargo.Text = ""
                $script:cmbDepartamento.Text = ""
                $script:cmbEmpresa.Text = ""
                $script:cmbEscritorio.Text = ""
                $script:chkCobertura.Checked = $false
                $script:txtAuditCadastro.Text = ""

                Set-AppStatus "Usuario criado."
            }
            catch {
                Show-ErrorMessage "Erro ao criar o usuario:`r`n`r`n$($_.Exception.Message)"
            }
            finally {
                $script:btnAtualizar.Enabled = $true
                $script:btnAtualizar.Text = "Criar usuario"
            }
            return
        }

        $login = $script:cadLogin

        if ([string]::IsNullOrWhiteSpace($login)) {
            Show-WarningMessage "Busque e selecione um usuario na lista antes de atualizar."
            return
        }

        $perfil = $script:cmbVinculo.SelectedItem.ToString()
        $empresa = $script:cmbEmpresa.Text.Trim()
        $cargo = $script:cmbCargo.Text.Trim()
        $departamento = $script:cmbDepartamento.Text.Trim()
        $email = $script:txtEmail.Text.Trim()
        $setor = $script:cmbSetor.Text.Trim()
        $ticket = $script:txtTicket.Text.Trim()

        $resultado = Test-CadastroCompletude $perfil $empresa $cargo $departamento $email
        $pendencias = @($resultado | Where-Object { $_ -like "FALTA*" -or $_ -like "ATENCAO*" })

        if (-not $setor) {
            $pendencias += "FALTA - Setor"
        }

        if (-not $ticket) {
            $pendencias += "FALTA - Ticket"
        }

        if ($pendencias.Count -gt 0) {
            $confirma = Confirm-Action `
                "O cadastro possui pendencia(s):`r`n`r`n$($pendencias -join "`r`n")`r`n`r`nDeseja aplicar mesmo assim?" `
                "Confirmar atualizacao"
            if (-not $confirma) {
                return
            }
        }

        if (-not (Ensure-ADModule)) { return }

        try {
            $script:btnAtualizar.Enabled = $false
            $script:btnAtualizar.Text = "Atualizando..."

            $u = Get-ADUser `
                -Identity $login `
                -Properties DisplayName, title, department, company, physicalDeliveryOfficeName, `
                    employeeType, Mail, telephoneNumber, Description, info `
                -Credential $script:AdminCreds `
                -ErrorAction Stop

            $novoLog = Get-LogLine "Cadastro atualizado. Perfil: $perfil"

            $diffs = @()

            if ($u.DisplayName -ne $script:txtDisplayName.Text.Trim()) {
                Set-ADUser -Identity $login -DisplayName $script:txtDisplayName.Text.Trim() -Credential $script:AdminCreds -ErrorAction SilentlyContinue
                $diffs += "DisplayName"
            }

            if ($u.title -ne $cargo) {
                Set-ADUser -Identity $login -Title $cargo -Credential $script:AdminCreds -ErrorAction SilentlyContinue
                $diffs += "Cargo"
            }

            if ($u.department -ne $departamento) {
                Set-ADUser -Identity $login -Department $departamento -Credential $script:AdminCreds -ErrorAction SilentlyContinue
                $diffs += "Departamento"
            }

            if ($u.company -ne $empresa) {
                Set-ADUser -Identity $login -Company $empresa -Credential $script:AdminCreds -ErrorAction SilentlyContinue
                $diffs += "Empresa"
            }

            if ($u.physicalDeliveryOfficeName -ne $script:cmbEscritorio.Text.Trim()) {
                Set-ADUser -Identity $login -Office $script:cmbEscritorio.Text.Trim() -Credential $script:AdminCreds -ErrorAction SilentlyContinue
                $diffs += "Escritorio"
            }

            if ($u.employeeType -ne $perfil) {
                Set-ADUser -Identity $login -Replace @{employeeType = $perfil} -Credential $script:AdminCreds -ErrorAction SilentlyContinue
                $diffs += "Vinculo"
            }

            if ($u.Mail -ne $email) {
                Set-ADUser -Identity $login -Replace @{mail = $email} -Credential $script:AdminCreds -ErrorAction SilentlyContinue
                $diffs += "E-mail"
            }

            if ($u.telephoneNumber -ne $script:txtTelefone.Text.Trim()) {
                Set-ADUser -Identity $login -OfficePhone $script:txtTelefone.Text.Trim() -Credential $script:AdminCreds -ErrorAction SilentlyContinue
                $diffs += "Telefone"
            }

            if ($u.Description -ne $script:txtDescricao.Text.Trim()) {
                Set-ADUser -Identity $login -Description $script:txtDescricao.Text.Trim() -Credential $script:AdminCreds -ErrorAction SilentlyContinue
                $diffs += "Descricao"
            }

            if ($diffs.Count -gt 0) {
                $novoLog = "$novoLog`r`n$(Get-LogLine "Campos alterados: $($diffs -join ', ')")"
            }
            else {
                $novoLog = "$novoLog`r`n$(Get-LogLine "Nenhum campo alterado.")"
            }

            if ($u.info) {
                $novoLog = "$novoLog`r`n$($u.info)"
            }

            Set-ADUser `
                -Identity $login `
                -Replace @{info = $novoLog} `
                -Credential $script:AdminCreds `
                -ErrorAction Stop

            Show-InfoMessage "Cadastro de '$($script:cadNome)' atualizado com sucesso.`r`n`r`nCampos alterados:`r`n$($diffs -join "`r`n")"

            Set-AppStatus "Cadastro atualizado."
        }
        catch {
            Show-ErrorMessage "Erro ao atualizar o cadastro:`r`n`r`n$($_.Exception.Message)"
        }
        finally {
            $script:btnAtualizar.Enabled = $true
            $script:btnAtualizar.Text = "Atualizar usuario"
        }
    })
}

# ============================================================
# VALORES PADRONIZADOS (JSON LOCAL)
# ============================================================

$script:PadroesDir = Join-Path $env:APPDATA "Gerenciador-AD"
$script:PadroesFile = Join-Path $script:PadroesDir "padroes.json"

$script:Padroes = @{
    Empresas      = @("EMPRESA")
    Escritorios   = @("ESCRITORIO")
    Departamentos = @("DEPARTAMENTO")
    Cargos        = @("CARGO")
    Setores       = @("SETOR")
    EmailDominio  = "dominio.com.br"
    OUUsuarios    = "OU=USUARIOS,DC=dominio,DC=com,DC=br"
}

function Load-Padroes {
    if (Test-Path $script:PadroesFile) {
        try {
            $json = Get-Content $script:PadroesFile -Raw | ConvertFrom-Json

            $padroesDefault = @{
                Empresas      = @("EMPRESA")
                Escritorios   = @("ESCRITORIO")
                Departamentos = @("DEPARTAMENTO")
                Cargos        = @("CARGO")
                Setores       = @("SETOR")
                EmailDominio  = "dominio.com.br"
                OUUsuarios    = "OU=USUARIOS,DC=dominio,DC=com,DC=br"
            }

            $novaLista = {
                param($nome)
                $valores = @($json.$nome | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_ ) })
                if ($valores.Count -eq 0) { @($padroesDefault.$nome) } else { $valores }
            }

            $script:Padroes = @{
                Empresas      = @(& $novaLista "Empresas")
                Escritorios   = @(& $novaLista "Escritorios")
                Departamentos = @(& $novaLista "Departamentos")
                Cargos        = @(& $novaLista "Cargos")
                Setores       = @(& $novaLista "Setores")
                EmailDominio  = if ([string]::IsNullOrWhiteSpace([string]$json.EmailDominio)) { $padroesDefault.EmailDominio } else { [string]$json.EmailDominio }
                OUUsuarios    = if ([string]::IsNullOrWhiteSpace([string]$json.OUUsuarios)) { $padroesDefault.OUUsuarios } else { [string]$json.OUUsuarios }
            }
        }
        catch {
            Set-AppStatus "Falha ao ler padroes.json; usando valores padrao."
        }
    }
    else {
        Save-Padroes
    }
}

function Save-Padroes {
    if (-not (Test-Path $script:PadroesDir)) {
        New-Item -ItemType Directory -Path $script:PadroesDir -Force | Out-Null
    }

    @{
        Empresas      = @($script:Padroes.Empresas)
        Escritorios   = @($script:Padroes.Escritorios)
        Departamentos = @($script:Padroes.Departamentos)
        Cargos        = @($script:Padroes.Cargos)
        Setores       = @($script:Padroes.Setores)
        EmailDominio  = $script:Padroes.EmailDominio
        OUUsuarios    = $script:Padroes.OUUsuarios
    } | ConvertTo-Json | Set-Content -Path $script:PadroesFile -Encoding UTF8
}

function Reset-PadroesCombo {
    param($Combo, [string[]]$Valores, [string]$Placeholder = "(nao alterar)")

    $Combo.Items.Clear()

    if ($Placeholder) {
        [void]$Combo.Items.Add($Placeholder)
    }

    foreach ($v in $Valores) {
        [void]$Combo.Items.Add($v)
    }

    $Combo.SelectedIndex = 0
}

function Show-Padroes {

    Clear-Content

    Add-StandardTitle `
        $content `
        "Valores padronizados" `
        "Listas usadas nos cadastros, na alteracao em massa e no assistente. Salvas localmente."

    $lblEmpresa = New-Label "Empresas:" 25 95 200 22
    $content.Controls.Add($lblEmpresa)

    $script:lstPadEmpresas = New-Object System.Windows.Forms.ListBox
    $script:lstPadEmpresas.Location = New-Object System.Drawing.Point(25, 120)
    $script:lstPadEmpresas.Size = New-Object System.Drawing.Size(280, 160)
    foreach ($v in $script:Padroes.Empresas) { [void]$script:lstPadEmpresas.Items.Add($v) }
    $content.Controls.Add($script:lstPadEmpresas)

    $script:txtPadEmpresa = New-TextBox 25 290 180 28
    $content.Controls.Add($script:txtPadEmpresa)

    $script:btnPadAddEmpresa = New-ActionButton "Adicionar" 210 288 95 30 $script:Colors.Success
    $content.Controls.Add($script:btnPadAddEmpresa)

    $script:btnPadRemoveEmpresa = New-ActionButton "Remover" 315 288 95 30 $script:Colors.Danger
    $content.Controls.Add($script:btnPadRemoveEmpresa)

    $lblEscritorio = New-Label "Escritorios:" 455 95 200 22
    $content.Controls.Add($lblEscritorio)

    $script:lstPadEscritorios = New-Object System.Windows.Forms.ListBox
    $script:lstPadEscritorios.Location = New-Object System.Drawing.Point(455, 120)
    $script:lstPadEscritorios.Size = New-Object System.Drawing.Size(280, 160)
    foreach ($v in $script:Padroes.Escritorios) { [void]$script:lstPadEscritorios.Items.Add($v) }
    $content.Controls.Add($script:lstPadEscritorios)

    $script:txtPadEscritorio = New-TextBox 455 290 180 28
    $content.Controls.Add($script:txtPadEscritorio)

    $script:btnPadAddEscritorio = New-ActionButton "Adicionar" 640 288 95 30 $script:Colors.Success
    $content.Controls.Add($script:btnPadAddEscritorio)

    $script:btnPadRemoveEscritorio = New-ActionButton "Remover" 745 288 95 30 $script:Colors.Danger
    $content.Controls.Add($script:btnPadRemoveEscritorio)

    $lblDepartamento = New-Label "Departamentos:" 25 335 200 22
    $content.Controls.Add($lblDepartamento)

    $script:lstPadDepartamentos = New-Object System.Windows.Forms.ListBox
    $script:lstPadDepartamentos.Location = New-Object System.Drawing.Point(25, 360)
    $script:lstPadDepartamentos.Size = New-Object System.Drawing.Size(280, 160)
    foreach ($v in $script:Padroes.Departamentos) { [void]$script:lstPadDepartamentos.Items.Add($v) }
    $content.Controls.Add($script:lstPadDepartamentos)

    $script:txtPadDepartamento = New-TextBox 25 530 180 28
    $content.Controls.Add($script:txtPadDepartamento)

    $script:btnPadAddDepartamento = New-ActionButton "Adicionar" 210 528 95 30 $script:Colors.Success
    $content.Controls.Add($script:btnPadAddDepartamento)

    $script:btnPadRemoveDepartamento = New-ActionButton "Remover" 315 528 95 30 $script:Colors.Danger
    $content.Controls.Add($script:btnPadRemoveDepartamento)

    $lblCargo = New-Label "Cargos:" 455 335 200 22
    $content.Controls.Add($lblCargo)

    $script:lstPadCargos = New-Object System.Windows.Forms.ListBox
    $script:lstPadCargos.Location = New-Object System.Drawing.Point(455, 360)
    $script:lstPadCargos.Size = New-Object System.Drawing.Size(280, 160)
    foreach ($v in $script:Padroes.Cargos) { [void]$script:lstPadCargos.Items.Add($v) }
    $content.Controls.Add($script:lstPadCargos)

    $script:txtPadCargo = New-TextBox 455 530 180 28
    $content.Controls.Add($script:txtPadCargo)

    $script:btnPadAddCargo = New-ActionButton "Adicionar" 640 528 95 30 $script:Colors.Success
    $content.Controls.Add($script:btnPadAddCargo)

    $script:btnPadRemoveCargo = New-ActionButton "Remover" 745 528 95 30 $script:Colors.Danger
    $content.Controls.Add($script:btnPadRemoveCargo)

    $lblSetor = New-Label "Setores:" 25 585 200 22
    $content.Controls.Add($lblSetor)

    $script:lstPadSetores = New-Object System.Windows.Forms.ListBox
    $script:lstPadSetores.Location = New-Object System.Drawing.Point(25, 610)
    $script:lstPadSetores.Size = New-Object System.Drawing.Size(280, 160)
    foreach ($v in $script:Padroes.Setores) { [void]$script:lstPadSetores.Items.Add($v) }
    $content.Controls.Add($script:lstPadSetores)

    $script:txtPadSetor = New-TextBox 25 780 180 28
    $content.Controls.Add($script:txtPadSetor)

    $script:btnPadAddSetor = New-ActionButton "Adicionar" 210 778 95 30 $script:Colors.Success
    $content.Controls.Add($script:btnPadAddSetor)

    $script:btnPadRemoveSetor = New-ActionButton "Remover" 315 778 95 30 $script:Colors.Danger
    $content.Controls.Add($script:btnPadRemoveSetor)

    $boxConfig = New-GroupBox "Configuracao" 770 120 190 170
    $content.Controls.Add($boxConfig)

    $lblDom = New-Label "Dominio de e-mail:" 780 140 170 22
    $boxConfig.Controls.Add($lblDom)

    $script:txtPadDominio = New-TextBox 780 165 160 28
    $script:txtPadDominio.Text = $script:Padroes.EmailDominio
    $boxConfig.Controls.Add($script:txtPadDominio)

    $lblOU = New-Label "OU de usuarios (novos):" 780 205 170 22
    $boxConfig.Controls.Add($lblOU)

    $script:txtPadOU = New-TextBox 780 230 160 50
    $script:txtPadOU.Multiline = $true
    $script:txtPadOU.Text = $script:Padroes.OUUsuarios
    $boxConfig.Controls.Add($script:txtPadOU)

    $script:btnPadSalvar = New-ActionButton "Salvar padroes" 25 840 450 42 $script:Colors.Success
    $content.Controls.Add($script:btnPadSalvar)

    $script:lblPadArquivo = New-Label ("Arquivo: " + $script:PadroesFile) 25 895 900 22
    $script:lblPadArquivo.ForeColor = $script:Colors.Muted
    $content.Controls.Add($script:lblPadArquivo)

    $script:btnPadSalvar.Add_Click({
        $script:Padroes.Empresas = @($script:lstPadEmpresas.Items)
        $script:Padroes.Escritorios = @($script:lstPadEscritorios.Items)
        $script:Padroes.Departamentos = @($script:lstPadDepartamentos.Items)
        $script:Padroes.Cargos = @($script:lstPadCargos.Items)
        $script:Padroes.Setores = @($script:lstPadSetores.Items)
        $script:Padroes.EmailDominio = $script:txtPadDominio.Text.Trim()
        $script:Padroes.OUUsuarios = $script:txtPadOU.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($script:Padroes.EmailDominio)) {
            Show-WarningMessage "Informe o dominio de e-mail."
            return
        }

        Save-Padroes
        Show-InfoMessage "Padroes salvos com sucesso em:`r`n`r`n$script:PadroesFile"
        Set-AppStatus "Padroes salvos."
    })

    $script:btnPadAddEmpresa.Add_Click({ Add-PadroesItem "Empresas" $script:lstPadEmpresas $script:txtPadEmpresa })
    $script:btnPadRemoveEmpresa.Add_Click({ Remove-PadroesItem $script:lstPadEmpresas })
    $script:btnPadAddEscritorio.Add_Click({ Add-PadroesItem "Escritorios" $script:lstPadEscritorios $script:txtPadEscritorio })
    $script:btnPadRemoveEscritorio.Add_Click({ Remove-PadroesItem $script:lstPadEscritorios })
    $script:btnPadAddDepartamento.Add_Click({ Add-PadroesItem "Departamentos" $script:lstPadDepartamentos $script:txtPadDepartamento })
    $script:btnPadRemoveDepartamento.Add_Click({ Remove-PadroesItem $script:lstPadDepartamentos })
    $script:btnPadAddCargo.Add_Click({ Add-PadroesItem "Cargos" $script:lstPadCargos $script:txtPadCargo })
    $script:btnPadRemoveCargo.Add_Click({ Remove-PadroesItem $script:lstPadCargos })
    $script:btnPadAddSetor.Add_Click({ Add-PadroesItem "Setores" $script:lstPadSetores $script:txtPadSetor })
    $script:btnPadRemoveSetor.Add_Click({ Remove-PadroesItem $script:lstPadSetores })
}

function Add-PadroesItem {
    param([string]$Chave, $Lista, $Txt)

    $valor = $Txt.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($valor)) {
        Show-WarningMessage "Digite o valor a adicionar."
        return
    }

    if ($Lista.Items.Contains($valor)) {
        Show-WarningMessage "Valor ja existe na lista."
        return
    }

    [void]$Lista.Items.Add($valor)
    $Txt.Clear()
    Set-AppStatus "Valor '$valor' adicionado. Lembre de clicar em Salvar padroes."
}

function Remove-PadroesItem {
    param($Lista)

    if ($Lista.SelectedIndex -lt 0) {
        Show-WarningMessage "Selecione um valor para remover."
        return
    }

    $Lista.Items.RemoveAt($Lista.SelectedIndex)
    Set-AppStatus "Valor removido. Lembre de clicar em Salvar padroes."
}

# ============================================================
# ALTERACAO EM MASSA
# ============================================================

function Show-EmMassa {

    Clear-Content

    Add-StandardTitle `
        $content `
        "Alteracao em massa" `
        "Selecione varios usuarios e padronize cargo, departamento, escritorio e empresa."

    $lblCampo = New-Label "Buscar em:" 25 95 120 22
    $content.Controls.Add($lblCampo)

    $script:cbCampo = New-Object System.Windows.Forms.ComboBox
    $script:cbCampo.Location = New-Object System.Drawing.Point(25, 120)
    $script:cbCampo.Size = New-Object System.Drawing.Size(160, 28)
    $script:cbCampo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$script:cbCampo.Items.Add("Nome")
    [void]$script:cbCampo.Items.Add("Login")
    [void]$script:cbCampo.Items.Add("Cargo")
    [void]$script:cbCampo.Items.Add("Descricao")
    [void]$script:cbCampo.Items.Add("Todos")
    $script:cbCampo.SelectedIndex = 4
    $content.Controls.Add($script:cbCampo)

    $script:txtBusca = New-TextBox 195 120 430 30
    $content.Controls.Add($script:txtBusca)

    $script:btnPesquisar = New-ActionButton "Pesquisar" 640 118 130 34
    $content.Controls.Add($script:btnPesquisar)

    $script:btnMarcar = New-ActionButton "Marcar todos" 780 118 155 34 $script:Colors.Dark
    $content.Controls.Add($script:btnMarcar)

    $lblLista = New-Label "Usuarios encontrados:" 25 165 500 22
    $content.Controls.Add($lblLista)

    $script:list = New-Object System.Windows.Forms.ListView
    $script:list.Location = New-Object System.Drawing.Point(25, 190)
    $script:list.Size = New-Object System.Drawing.Size(935, 290)
    $script:list.View = [System.Windows.Forms.View]::Details
    $script:list.CheckBoxes = $true
    $script:list.FullRowSelect = $true
    $script:list.GridLines = $true
    $script:list.MultiSelect = $true
    $script:list.Scrollable = $true
    $script:list.UseCompatibleStateImageBehavior = $false

    [void]$script:list.Columns.Add("Nome", 170)
    [void]$script:list.Columns.Add("Usuario", 120)
    [void]$script:list.Columns.Add("Cargo", 180)
    [void]$script:list.Columns.Add("Departamento", 150)
    [void]$script:list.Columns.Add("Escritorio", 140)
    [void]$script:list.Columns.Add("Empresa", 140)

    $content.Controls.Add($script:list)

    $script:lblCount = New-Label "0 usuario(s) selecionado(s)" 25 490 400 25
    $script:lblCount.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $content.Controls.Add($script:lblCount)

    $boxCampos = New-GroupBox "Campos a alterar" 25 525 935 105
    $content.Controls.Add($boxCampos)

    $lblMassCargo = New-Label "Cargo:" 20 24 100 22
    $boxCampos.Controls.Add($lblMassCargo)

    $script:cmbMassCargo = New-Object System.Windows.Forms.ComboBox
    $script:cmbMassCargo.Location = New-Object System.Drawing.Point(20, 48)
    $script:cmbMassCargo.Size = New-Object System.Drawing.Size(210, 28)
    $script:cmbMassCargo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    Reset-PadroesCombo $script:cmbMassCargo $script:Padroes.Cargos
    $boxCampos.Controls.Add($script:cmbMassCargo)

    $lblMassDepartamento = New-Label "Departamento:" 255 24 120 22
    $boxCampos.Controls.Add($lblMassDepartamento)

    $script:cmbMassDepartamento = New-Object System.Windows.Forms.ComboBox
    $script:cmbMassDepartamento.Location = New-Object System.Drawing.Point(255, 48)
    $script:cmbMassDepartamento.Size = New-Object System.Drawing.Size(210, 28)
    $script:cmbMassDepartamento.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    Reset-PadroesCombo $script:cmbMassDepartamento $script:Padroes.Departamentos
    $boxCampos.Controls.Add($script:cmbMassDepartamento)

    $lblMassEscritorio = New-Label "Escritorio:" 490 24 120 22
    $boxCampos.Controls.Add($lblMassEscritorio)

    $script:cmbMassEscritorio = New-Object System.Windows.Forms.ComboBox
    $script:cmbMassEscritorio.Location = New-Object System.Drawing.Point(490, 48)
    $script:cmbMassEscritorio.Size = New-Object System.Drawing.Size(210, 28)
    $script:cmbMassEscritorio.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    Reset-PadroesCombo $script:cmbMassEscritorio $script:Padroes.Escritorios
    $boxCampos.Controls.Add($script:cmbMassEscritorio)

    $lblMassEmpresa = New-Label "Empresa:" 725 24 100 22
    $boxCampos.Controls.Add($lblMassEmpresa)

    $script:cmbMassEmpresa = New-Object System.Windows.Forms.ComboBox
    $script:cmbMassEmpresa.Location = New-Object System.Drawing.Point(725, 48)
    $script:cmbMassEmpresa.Size = New-Object System.Drawing.Size(190, 28)
    $script:cmbMassEmpresa.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    Reset-PadroesCombo $script:cmbMassEmpresa $script:Padroes.Empresas
    $boxCampos.Controls.Add($script:cmbMassEmpresa)

    $script:btnMassPrevia = New-ActionButton "Pre-visualizar alteracoes" 25 645 350 40 $script:Colors.Primary
    $content.Controls.Add($script:btnMassPrevia)

    $script:btnMassConfirmar = New-ActionButton "Confirmar alteracoes" 390 645 300 40 $script:Colors.Danger
    $script:btnMassConfirmar.Enabled = $false
    $content.Controls.Add($script:btnMassConfirmar)

    $script:lblMassResumo = New-Label "0 alteracao(es) prevista(s)" 700 655 225 25
    $script:lblMassResumo.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $content.Controls.Add($script:lblMassResumo)

    $lblPrev = New-Label "Pre-visualizacao (antes x depois):" 25 695 400 22
    $content.Controls.Add($lblPrev)

    $script:txtMassPreview = New-Object System.Windows.Forms.TextBox
    $script:txtMassPreview.Location = New-Object System.Drawing.Point(25, 720)
    $script:txtMassPreview.Size = New-Object System.Drawing.Size(935, 150)
    $script:txtMassPreview.Multiline = $true
    $script:txtMassPreview.ReadOnly = $true
    $script:txtMassPreview.ScrollBars = "Vertical"
    $script:txtMassPreview.Font = New-Object System.Drawing.Font("Consolas", 9)
    $content.Controls.Add($script:txtMassPreview)

    $script:updateCount = {
        $count = 0
        foreach ($item in $script:list.Items) {
            if ($item.Checked) { $count++ }
        }
        $script:lblCount.Text = "$count usuario(s) selecionado(s)"
    }

    $script:list.Add_ItemCheck({
        $content.BeginInvoke([Action]$script:updateCount) | Out-Null
    })

    $script:btnMarcar.Add_Click({
        $all = $true
        foreach ($item in $script:list.Items) {
            if (-not $item.Checked) {
                $all = $false
                break
            }
        }

        foreach ($item in $script:list.Items) {
            $item.Checked = -not $all
        }

        $script:btnMarcar.Text = if ($all) { "Marcar todos" } else { "Desmarcar todos" }

        & $script:updateCount
    })

    $script:btnPesquisar.Add_Click({
        $termo = $script:txtBusca.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($termo)) {
            Show-WarningMessage "Digite um termo para buscar."
            return
        }

        if (-not (Ensure-ADModule)) { return }

        try {
            $script:btnPesquisar.Enabled = $false
            $script:btnPesquisar.Text = "Pesquisando..."
            Set-AppStatus "Pesquisando usuarios no AD..."

            $script:list.Items.Clear()

            $campo = $script:cbCampo.SelectedItem.ToString()
            $filtro = Get-UserSearchFilter $campo $termo

            $encontrados = Get-ADUser `
                -LDAPFilter $filtro `
                -Properties Description, Title, SamAccountName, DisplayName, Department, physicalDeliveryOfficeName, Company `
                -Credential $script:AdminCreds `
                -ErrorAction Stop

            foreach ($u in $encontrados) {
                $nome = if ($u.DisplayName) { $u.DisplayName } else { $u.SamAccountName }
                $cargo = if ($u.Title) { $u.Title } else { "[sem]" }
                $dept = if ($u.Department) { $u.Department } else { "[sem]" }
                $esc = if ($u.physicalDeliveryOfficeName) { $u.physicalDeliveryOfficeName } else { "[sem]" }
                $emp = if ($u.Company) { $u.Company } else { "[sem]" }

                $item = New-Object System.Windows.Forms.ListViewItem($nome)
                [void]$item.SubItems.Add($u.SamAccountName)
                [void]$item.SubItems.Add($cargo)
                [void]$item.SubItems.Add($dept)
                [void]$item.SubItems.Add($esc)
                [void]$item.SubItems.Add($emp)
                $item.Tag = $u.SamAccountName
                [void]$script:list.Items.Add($item)
            }

            & $script:updateCount
            $script:btnMarcar.Text = "Marcar todos"
            Set-AppStatus "Pesquisa concluida. Encontrados: $($script:list.Items.Count)."
        }
        catch {
            Show-ErrorMessage "Erro ao pesquisar no Active Directory:`r`n`r`n$($_.Exception.Message)"
            Set-AppStatus "Erro na pesquisa."
        }
        finally {
            $script:btnPesquisar.Enabled = $true
            $script:btnPesquisar.Text = "Pesquisar"
        }
    })

    $script:btnMassPrevia.Add_Click({
        $selecionados = @($script:list.Items | Where-Object { $_.Checked })

        if ($selecionados.Count -eq 0) {
            Show-WarningMessage "Marque pelo menos um usuario."
            return
        }

        $alvoCargo = if ($script:cmbMassCargo.SelectedIndex -gt 0) { $script:cmbMassCargo.SelectedItem.ToString() } else { "" }
        $alvoDepto = if ($script:cmbMassDepartamento.SelectedIndex -gt 0) { $script:cmbMassDepartamento.SelectedItem.ToString() } else { "" }
        $alvoEscrit = if ($script:cmbMassEscritorio.SelectedIndex -gt 0) { $script:cmbMassEscritorio.SelectedItem.ToString() } else { "" }
        $alvoEmpresa = if ($script:cmbMassEmpresa.SelectedIndex -gt 0) { $script:cmbMassEmpresa.SelectedItem.ToString() } else { "" }

        $temCampo = $alvoCargo -or $alvoDepto -or $alvoEscrit -or $alvoEmpresa

        if (-not $temCampo) {
            Show-WarningMessage "Selecione pelo menos um campo para alterar."
            return
        }

        $linhas = @()
        $total = 0

        foreach ($item in $selecionados) {
            $login = $item.Tag

            try {
                $u = Get-ADUser `
                    -Identity $login `
                    -Properties Title, Department, physicalDeliveryOfficeName, Company `
                    -Credential $script:AdminCreds `
                    -ErrorAction Stop

                $atualCargo = if ($u.Title) { $u.Title } else { "-" }
                $atualDepto = if ($u.Department) { $u.Department } else { "-" }
                $atualEscrit = if ($u.physicalDeliveryOfficeName) { $u.physicalDeliveryOfficeName } else { "-" }
                $atualEmpresa = if ($u.Company) { $u.Company } else { "-" }

                $linhas += "=== $login ==="

                if ($alvoCargo -and $atualCargo -ne $alvoCargo) {
                    $linhas += "  Cargo: $atualCargo -> $alvoCargo"
                    $total++
                }
                if ($alvoDepto -and $atualDepto -ne $alvoDepto) {
                    $linhas += "  Departamento: $atualDepto -> $alvoDepto"
                    $total++
                }
                if ($alvoEscrit -and $atualEscrit -ne $alvoEscrit) {
                    $linhas += "  Escritorio: $atualEscrit -> $alvoEscrit"
                    $total++
                }
                if ($alvoEmpresa -and $atualEmpresa -ne $alvoEmpresa) {
                    $linhas += "  Empresa: $atualEmpresa -> $alvoEmpresa"
                    $total++
                }

                $linhas += ""
            }
            catch {
                $linhas += "=== $login === ERRO: $($_.Exception.Message)"
            }
        }

        $script:txtMassPreview.Text = $linhas -join "`r`n"
        $script:lblMassResumo.Text = "$total alteracao(es) prevista(s)"
        $script:btnMassConfirmar.Enabled = ($total -gt 0)
        Set-AppStatus "Pre-visualizacao gerada."
    })

    $script:btnMassConfirmar.Add_Click({
        $selecionados = @($script:list.Items | Where-Object { $_.Checked })

        $alvoCargo = if ($script:cmbMassCargo.SelectedIndex -gt 0) { $script:cmbMassCargo.SelectedItem.ToString() } else { "" }
        $alvoDepto = if ($script:cmbMassDepartamento.SelectedIndex -gt 0) { $script:cmbMassDepartamento.SelectedItem.ToString() } else { "" }
        $alvoEscrit = if ($script:cmbMassEscritorio.SelectedIndex -gt 0) { $script:cmbMassEscritorio.SelectedItem.ToString() } else { "" }
        $alvoEmpresa = if ($script:cmbMassEmpresa.SelectedIndex -gt 0) { $script:cmbMassEmpresa.SelectedItem.ToString() } else { "" }

        $totalPrevisto = @($script:txtMassPreview.Text -split "`r`n" | Where-Object { $_ -match " -> " }).Count

        if (-not (Confirm-Action `
            "Confirmar $totalPrevisto alteracao(es) em $($selecionados.Count) usuario(s)?`r`n`r`nDeseja continuar?" `
            "Confirmar alteracao em massa")) {
            return
        }

        if (-not (Ensure-ADModule)) { return }

        try {
            $script:btnMassConfirmar.Enabled = $false
            $script:btnMassConfirmar.Text = "Aplicando..."
            Set-AppStatus "Aplicando alteracoes em massa..."

            $aplicadas = 0
            $erros = 0

            foreach ($item in $selecionados) {
                $login = $item.Tag

                try {
                    $u = Get-ADUser `
                        -Identity $login `
                        -Properties Title, Department, physicalDeliveryOfficeName, Company, info `
                        -Credential $script:AdminCreds `
                        -ErrorAction Stop

                    $diffs = @()

                    if ($alvoCargo -and $u.Title -ne $alvoCargo) {
                        Set-ADUser -Identity $login -Title $alvoCargo -Credential $script:AdminCreds -ErrorAction SilentlyContinue
                        $diffs += "Cargo: $($u.Title) -> $alvoCargo"
                    }
                    if ($alvoDepto -and $u.Department -ne $alvoDepto) {
                        Set-ADUser -Identity $login -Department $alvoDepto -Credential $script:AdminCreds -ErrorAction SilentlyContinue
                        $diffs += "Departamento: $($u.Department) -> $alvoDepto"
                    }
                    if ($alvoEscrit -and $u.physicalDeliveryOfficeName -ne $alvoEscrit) {
                        Set-ADUser -Identity $login -Office $alvoEscrit -Credential $script:AdminCreds -ErrorAction SilentlyContinue
                        $diffs += "Escritorio: $($u.physicalDeliveryOfficeName) -> $alvoEscrit"
                    }
                    if ($alvoEmpresa -and $u.Company -ne $alvoEmpresa) {
                        Set-ADUser -Identity $login -Company $alvoEmpresa -Credential $script:AdminCreds -ErrorAction SilentlyContinue
                        $diffs += "Empresa: $($u.Company) -> $alvoEmpresa"
                    }

                    if ($diffs.Count -gt 0) {
                        $aplicadas += $diffs.Count

                        $novoLog = Get-LogLine "Alteracao em massa: $($diffs -join '; ')"

                        if ($u.info) {
                            $novoLog = "$novoLog`r`n$($u.info)"
                        }

                        Set-ADUser `
                            -Identity $login `
                            -Replace @{info = $novoLog} `
                            -Credential $script:AdminCreds `
                            -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    $erros++
                }
            }

            Show-InfoMessage "Alteracao em massa concluida.`r`n`r`nAlteracoes aplicadas: $aplicadas`r`nErros: $erros"
            Set-AppStatus "Alteracao em massa concluida."
        }
        catch {
            Show-ErrorMessage "Erro na alteracao em massa:`r`n`r`n$($_.Exception.Message)"
        }
        finally {
            $script:btnMassConfirmar.Enabled = $true
            $script:btnMassConfirmar.Text = "Confirmar alteracoes"
        }
    })
}

# ============================================================
# GERENCIADOR DE GRUPOS
# ============================================================

function Show-Grupos {

    Clear-Content

    Add-StandardTitle `
        $content `
        "Gerenciar grupos" `
        "Consulte, adicione, remova, copie e compare os grupos de um usuario."

    $script:grupoLogin = ""

    $nextY = Add-UserSearch 95 {
        param($login)
        $script:grupoLogin = $login
        Carregar-GruposUsuario $login
    } 120

    $boxGrupos = New-GroupBox "Grupos do usuario" 25 ($nextY + 5) 935 250
    $content.Controls.Add($boxGrupos)

    $script:lstGrupos = New-Object System.Windows.Forms.ListView
    $script:lstGrupos.Location = New-Object System.Drawing.Point(20, 24)
    $script:lstGrupos.Size = New-Object System.Drawing.Size(640, 200)
    $script:lstGrupos.View = [System.Windows.Forms.View]::Details
    $script:lstGrupos.CheckBoxes = $true
    $script:lstGrupos.FullRowSelect = $true
    $script:lstGrupos.GridLines = $true
    $script:lstGrupos.MultiSelect = $true
    $script:lstGrupos.Scrollable = $true
    $script:lstGrupos.UseCompatibleStateImageBehavior = $false

    [void]$script:lstGrupos.Columns.Add("Grupo", 400)
    [void]$script:lstGrupos.Columns.Add("Tipo", 200)

    $boxGrupos.Controls.Add($script:lstGrupos)

    $lblNovoGrupo = New-Label "Novo grupo:" 680 20 120 22
    $boxGrupos.Controls.Add($lblNovoGrupo)

    $script:txtNovoGrupo = New-TextBox 680 45 230 28
    $boxGrupos.Controls.Add($script:txtNovoGrupo)

    $script:btnAdicionarGrupo = New-ActionButton "Adicionar" 680 80 110 30 $script:Colors.Success
    $boxGrupos.Controls.Add($script:btnAdicionarGrupo)

    $script:btnRemoverGrupo = New-ActionButton "Remover marcados" 800 80 130 30 $script:Colors.Danger
    $boxGrupos.Controls.Add($script:btnRemoverGrupo)

    $script:btnAtualizarGrupos = New-ActionButton "Atualizar lista" 680 120 250 30 $script:Colors.Dark
    $boxGrupos.Controls.Add($script:btnAtualizarGrupos)

    $lblAlvo = New-Label "Usuario alvo (login):" 680 160 200 22
    $boxGrupos.Controls.Add($lblAlvo)

    $script:txtAlvoGrupos = New-TextBox 680 185 230 28
    $boxGrupos.Controls.Add($script:txtAlvoGrupos)

    $script:btnCopiarGrupos = New-ActionButton "Copiar para alvo" 680 220 130 30 $script:Colors.Primary
    $boxGrupos.Controls.Add($script:btnCopiarGrupos)

    $script:btnCompararGRUPOS = New-ActionButton "Comparar com alvo" 820 220 120 30 $script:Colors.Dark
    $boxGrupos.Controls.Add($script:btnCompararGRUPOS)

    $script:btnAtualizarGrupos.Add_Click({
        if (-not $script:grupoLogin) {
            Show-WarningMessage "Busque e selecione um usuario primeiro."
            return
        }
        Carregar-GruposUsuario $script:grupoLogin
    })

    $script:btnAdicionarGrupo.Add_Click({
        $nomeGrupo = $script:txtNovoGrupo.Text.Trim()

        if (-not $script:grupoLogin) {
            Show-WarningMessage "Busque e selecione um usuario primeiro."
            return
        }

        if ([string]::IsNullOrWhiteSpace($nomeGrupo)) {
            Show-WarningMessage "Digite o nome do grupo."
            return
        }

        if (-not (Ensure-ADModule)) { return }

        try {
            $grupo = Get-ADGroup -Filter "Name -eq '$nomeGrupo'" -Credential $script:AdminCreds -ErrorAction Stop

            if (-not $grupo) {
                Show-WarningMessage "Grupo '$nomeGrupo' nao encontrado no AD."
                return
            }

            Add-ADGroupMember `
                -Identity $grupo.DistinguishedName `
                -Members $script:grupoLogin `
                -Credential $script:AdminCreds `
                -Confirm:$false `
                -ErrorAction Stop

            $novoLog = Get-LogLine "Grupo adicionado: $nomeGrupo"

            $u = Get-ADUser -Identity $script:grupoLogin -Properties info -Credential $script:AdminCreds -ErrorAction SilentlyContinue

            if ($u.info) {
                $novoLog = "$novoLog`r`n$($u.info)"
            }

            Set-ADUser `
                -Identity $script:grupoLogin `
                -Replace @{info = $novoLog} `
                -Credential $script:AdminCreds `
                -ErrorAction SilentlyContinue

            $script:txtNovoGrupo.Clear()
            Carregar-GruposUsuario $script:grupoLogin
            Set-AppStatus "Grupo adicionado."
        }
        catch {
            Show-ErrorMessage "Erro ao adicionar o grupo:`r`n`r`n$($_.Exception.Message)"
        }
    })

    $script:btnRemoverGrupo.Add_Click({
        $marcados = @($script:lstGrupos.Items | Where-Object { $_.Checked })

        if ($marcados.Count -eq 0) {
            Show-WarningMessage "Marque pelo menos um grupo na lista."
            return
        }

        if (-not $script:grupoLogin) {
            Show-WarningMessage "Busque e selecione um usuario primeiro."
            return
        }

        $nomes = @($marcados | ForEach-Object { $_.SubItems[0].Text })

        if (-not (Confirm-Action `
            "Remover $($marcados.Count) grupo(s) de '$script:grupoLogin'?`r`n`r`n$($nomes -join "`r`n")`r`n`r`nDeseja continuar?" `
            "Remover grupos")) {
            return
        }

        if (-not (Ensure-ADModule)) { return }

        $removidos = 0
        $erros = 0

        try {
            foreach ($item in $marcados) {
                $dn = $item.Tag
                try {
                    Remove-ADGroupMember `
                        -Identity $dn `
                        -Members $script:grupoLogin `
                        -Credential $script:AdminCreds `
                        -Confirm:$false `
                        -ErrorAction Stop
                    $removidos++
                }
                catch {
                    $erros++
                }
            }

            $novoLog = Get-LogLine "Grupos removidos: $($nomes -join ', ') (removidos: $removidos, erros: $erros)"

            $u = Get-ADUser -Identity $script:grupoLogin -Properties info -Credential $script:AdminCreds -ErrorAction SilentlyContinue

            if ($u.info) {
                $novoLog = "$novoLog`r`n$($u.info)"
            }

            Set-ADUser `
                -Identity $script:grupoLogin `
                -Replace @{info = $novoLog} `
                -Credential $script:AdminCreds `
                -ErrorAction SilentlyContinue

            Carregar-GruposUsuario $script:grupoLogin
            Show-InfoMessage "Grupos removidos: $removidos`r`nErros: $erros"
            Set-AppStatus "Remocao de grupos concluida."
        }
        catch {
            Show-ErrorMessage "Erro ao remover grupos:`r`n`r`n$($_.Exception.Message)"
        }
    })

    $script:btnCopiarGrupos.Add_Click({
        $alvo = $script:txtAlvoGrupos.Text.Trim()

        if (-not $script:grupoLogin) {
            Show-WarningMessage "Busque e selecione um usuario origem primeiro."
            return
        }

        if ([string]::IsNullOrWhiteSpace($alvo)) {
            Show-WarningMessage "Digite o login do usuario alvo."
            return
        }

        if ($script:grupoLogin -eq $alvo) {
            Show-WarningMessage "Origem e alvo nao podem ser o mesmo usuario."
            return
        }

        if (-not (Ensure-ADModule)) { return }

        try {
            $origem = Get-ADUser -Identity $script:grupoLogin -Properties MemberOf, DisplayName -Credential $script:AdminCreds -ErrorAction Stop
            $dest = Get-ADUser -Identity $alvo -Properties MemberOf, DisplayName -Credential $script:AdminCreds -ErrorAction Stop

            $aAdicionar = @($origem.MemberOf | Where-Object { $dest.MemberOf -notcontains $_ })

            if ($aAdicionar.Count -eq 0) {
                Show-InfoMessage "O usuario alvo '$alvo' ja possui todos os grupos da origem."
                return
            }

            if (-not (Confirm-Action `
                "Copiar $($aAdicionar.Count) grupo(s) de '$script:grupoLogin' para '$alvo'?`r`n`r`nDeseja continuar?" `
                "Copiar grupos")) {
                return
            }

            $adicionados = 0
            $erros = 0

            foreach ($dn in $aAdicionar) {
                try {
                    Add-ADGroupMember -Identity $dn -Members $alvo -Credential $script:AdminCreds -Confirm:$false -ErrorAction Stop
                    $adicionados++
                }
                catch {
                    $erros++
                }
            }

            $novoLog = Get-LogLine "Grupos copiados da origem '$script:grupoLogin' (adicionados: $adicionados, erros: $erros)."

            $destInfo = Get-ADUser -Identity $alvo -Properties info -Credential $script:AdminCreds -ErrorAction SilentlyContinue

            if ($destInfo.info) {
                $novoLog = "$novoLog`r`n$($destInfo.info)"
            }

            Set-ADUser -Identity $alvo -Replace @{info = $novoLog} -Credential $script:AdminCreds -ErrorAction SilentlyContinue

            Show-InfoMessage "Grupos copiados: $adicionados`r`nErros: $erros"
            Set-AppStatus "Copiado de grupos concluido."
        }
        catch {
            Show-ErrorMessage "Erro ao copiar grupos:`r`n`r`n$($_.Exception.Message)"
        }
    })

    $script:btnCompararGRUPOS.Add_Click({
        $alvo = $script:txtAlvoGrupos.Text.Trim()

        if (-not $script:grupoLogin) {
            Show-WarningMessage "Busque e selecione um usuario primeiro."
            return
        }

        if ([string]::IsNullOrWhiteSpace($alvo)) {
            Show-WarningMessage "Digite o login do usuario a comparar."
            return
        }

        Show-CompararGrupos $script:grupoLogin $alvo
    })
}

function Carregar-GruposUsuario {
    param([string]$Login)

    if (-not (Ensure-ADModule)) { return }

    try {
        $u = Get-ADUser `
            -Identity $Login `
            -Properties MemberOf, DisplayName `
            -Credential $script:AdminCreds `
            -ErrorAction Stop

        $script:lstGrupos.Items.Clear()

        if (-not $u.MemberOf) {
            Set-AppStatus "O usuario nao pertence a nenhum grupo."
            return
        }

        $detalhes = @(Get-ADGroup `
            -Filter * `
            -Properties GroupCategory `
            -Credential $script:AdminCreds `
            -ErrorAction SilentlyContinue)

        foreach ($dn in ($u.MemberOf | Sort-Object)) {
            $nome = ($dn -split ',')[0].Replace('CN=', '')

            $tipo = "Grupo"
            $acha = $detalhes | Where-Object { $_.DistinguishedName -eq $dn } | Select-Object -First 1
            if ($acha) {
                $tipo = if ($acha.GroupCategory -eq "Distribution") { "Distribuicao" } else { "Seguranca" }
            }

            $item = New-Object System.Windows.Forms.ListViewItem($nome)
            [void]$item.SubItems.Add($tipo)
            $item.Tag = $dn
            [void]$script:lstGrupos.Items.Add($item)
        }

        Set-AppStatus "Grupos carregados: $($script:lstGrupos.Items.Count)."
    }
    catch {
        Show-ErrorMessage "Erro ao carregar grupos:`r`n`r`n$($_.Exception.Message)"
    }
}

function Show-CompararGrupos {
    param(
        [string]$UsuarioA = "",
        [string]$UsuarioB = ""
    )

    Clear-Content

    Add-StandardTitle `
        $content `
        "Comparar grupos de dois usuarios" `
        "Compare as associacoes de grupo entre dois usuarios."

    $script:gruposCmpA = @()
    $script:gruposCmpB = @()

    $lblA = New-Label "Usuario A (login):" 25 95 200 22
    $content.Controls.Add($lblA)

    $script:txtCmpA = New-TextBox 25 120 350 28
    $script:txtCmpA.Text = $UsuarioA
    $content.Controls.Add($script:txtCmpA)

    $script:btnCmpCarregarA = New-ActionButton "Carregar A" 390 118 160 32 $script:Colors.Primary
    $content.Controls.Add($script:btnCmpCarregarA)

    $lblB = New-Label "Usuario B (login):" 590 95 200 22
    $content.Controls.Add($lblB)

    $script:txtCmpB = New-TextBox 590 120 350 28
    $script:txtCmpB.Text = $UsuarioB
    $content.Controls.Add($script:txtCmpB)

    $script:btnCmpCarregarB = New-ActionButton "Carregar B" 790 118 160 32 $script:Colors.Dark
    $content.Controls.Add($script:btnCmpCarregarB)

    $script:btnCmpComparar = New-ActionButton "Comparar grupos" 25 165 450 40 $script:Colors.Success
    $content.Controls.Add($script:btnCmpComparar)

    $script:txtCmpResultado = New-Object System.Windows.Forms.TextBox
    $script:txtCmpResultado.Location = New-Object System.Drawing.Point(25, 225)
    $script:txtCmpResultado.Size = New-Object System.Drawing.Size(935, 400)
    $script:txtCmpResultado.Multiline = $true
    $script:txtCmpResultado.ReadOnly = $true
    $script:txtCmpResultado.ScrollBars = "Vertical"
    $script:txtCmpResultado.Font = New-Object System.Drawing.Font("Consolas", 9)
    $content.Controls.Add($script:txtCmpResultado)

    $script:btnCmpCarregarA.Add_Click({
        $login = $script:txtCmpA.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($login)) { Show-WarningMessage "Digite o login."; return }
        $script:gruposCmpA = @(Get-GruposLogin $login)
        Set-AppStatus "Usuario A carregado ($($script:gruposCmpA.Count) grupo(s))."
    })

    $script:btnCmpCarregarB.Add_Click({
        $login = $script:txtCmpB.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($login)) { Show-WarningMessage "Digite o login."; return }
        $script:gruposCmpB = @(Get-GruposLogin $login)
        Set-AppStatus "Usuario B carregado ($($script:gruposCmpB.Count) grupo(s))."
    })

    $script:btnCmpComparar.Add_Click({
        if (-not $script:gruposCmpA -or -not $script:gruposCmpB) {
            Show-WarningMessage "Carregue os dois usuarios antes de comparar."
            return
        }

        $soA = @($script:gruposCmpA | Where-Object { $script:gruposCmpB -notcontains $_ })
        $soB = @($script:gruposCmpB | Where-Object { $script:gruposCmpA -notcontains $_ })
        $comuns = @($script:gruposCmpA | Where-Object { $script:gruposCmpB -contains $_ })

        $linhas = @()
        $linhas += "=== COMPARACAO DE GRUPOS ==="
        $linhas += ""
        $linhas += "Usuario A: $($script:txtCmpA.Text.Trim()) - $($script:gruposCmpA.Count) grupo(s)"
        $linhas += "Usuario B: $($script:txtCmpB.Text.Trim()) - $($script:gruposCmpB.Count) grupo(s)"
        $linhas += ""
        $linhas += "Grupos em comum: $($comuns.Count)"
        foreach ($g in ($comuns | Sort-Object)) { $linhas += "  [COMUM] $g" }
        $linhas += ""
        $linhas += "Somente A: $($soA.Count)"
        foreach ($g in ($soA | Sort-Object)) { $linhas += "  [A] $g" }
        $linhas += ""
        $linhas += "Somente B: $($soB.Count)"
        foreach ($g in ($soB | Sort-Object)) { $linhas += "  [B] $g" }

        $script:txtCmpResultado.Text = $linhas -join "`r`n"
        Set-AppStatus "Comparacao concluida."
    })
}

function Get-GruposLogin {
    param([string]$Login)

    if (-not (Ensure-ADModule)) { return @() }

    try {
        $u = Get-ADUser `
            -Identity $Login `
            -Properties MemberOf `
            -Credential $script:AdminCreds `
            -ErrorAction Stop

        if (-not $u.MemberOf) {
            return @()
        }

        $nomes = @($u.MemberOf | ForEach-Object { ($_ -split ',')[0].Replace('CN=', '') })
        return @($nomes | Sort-Object -Unique)
    }
    catch {
        Show-ErrorMessage "Erro ao consultar grupos de '$Login':`r`n`r`n$($_.Exception.Message)"
        return @()
    }
}

# ============================================================
# CENTRAL DE INCONSISTENCIAS (AUDITORIA SOMENTE LEITURA)
# ============================================================

$script:AuditData = @()
$script:UsersAudit = @()
$script:ComputersAudit = @()
$script:UserSearchBaseDN = ""
$script:ComputerSearchBaseDN = ""
$script:StandardComputerOUDN = ""

function Add-AuditCard {
    param(
        [System.Windows.Forms.Panel]$Parent,
        [string]$Title,
        [string]$Value,
        [int]$X,
        [int]$Y,
        [int]$W = 205,
        [int]$H = 100,
        [System.Drawing.Color]$ValueColor = $script:Colors.Text
    )

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.Size = New-Object System.Drawing.Size($W, $H)
    $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $panel.BackColor = [System.Drawing.Color]::White

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = $Title
    $lblTitle.Location = New-Object System.Drawing.Point(12, 10)
    $lblTitle.Size = New-Object System.Drawing.Size(($W - 24), 25)
    $lblTitle.ForeColor = $script:Colors.Muted
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $panel.Controls.Add($lblTitle)

    $lblValue = New-Object System.Windows.Forms.Label
    $lblValue.Text = $Value
    $lblValue.Location = New-Object System.Drawing.Point(12, 38)
    $lblValue.Size = New-Object System.Drawing.Size(($W - 24), 45)
    $lblValue.ForeColor = $ValueColor
    $lblValue.Font = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
    $panel.Controls.Add($lblValue)

    $Parent.Controls.Add($panel)

    return $lblValue
}

function Resolve-SearchBase {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        $domain = Get-ADDomain -Credential $script:AdminCreds -ErrorAction Stop
        return $domain.DistinguishedName
    }

    return (Convert-PathOUToDN $Value)
}

function Get-MissingFields {
    param($User)

    $missing = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace([string]$User.Title)) {
        [void]$missing.Add("Cargo")
    }

    if ([string]::IsNullOrWhiteSpace([string]$User.Department)) {
        [void]$missing.Add("Departamento")
    }

    if ([string]::IsNullOrWhiteSpace([string]$User.physicalDeliveryOfficeName)) {
        [void]$missing.Add("Escritorio")
    }

    if ([string]::IsNullOrWhiteSpace([string]$User.Company)) {
        [void]$missing.Add("Empresa")
    }

    if ([string]::IsNullOrWhiteSpace([string]$User.Mail)) {
        [void]$missing.Add("E-mail")
    }

    if ([string]::IsNullOrWhiteSpace([string]$User.employeeType)) {
        [void]$missing.Add("Vinculo")
    }

    if ([string]::IsNullOrWhiteSpace([string]$User.Description)) {
        [void]$missing.Add("Descricao")
    }

    return @($missing)
}

function Get-UserAudit {
    param([string]$SearchBase)

    Set-AppStatus "Consultando usuarios do Active Directory..."

    $properties = @(
        "DisplayName",
        "SamAccountName",
        "Enabled",
        "Title",
        "Department",
        "physicalDeliveryOfficeName",
        "Company",
        "Mail",
        "employeeType",
        "Description",
        "DistinguishedName"
    )

    $users = @(Get-ADUser `
        -SearchBase $SearchBase `
        -Filter * `
        -Properties $properties `
        -Credential $script:AdminCreds `
        -ErrorAction Stop)

    $data = New-Object System.Collections.Generic.List[object]

    foreach ($user in $users) {
        $missing = Get-MissingFields $user

        $obj = [PSCustomObject]@{
            Nome             = if ($user.DisplayName) { $user.DisplayName } else { $user.SamAccountName }
            Login            = $user.SamAccountName
            Ativo            = [bool]$user.Enabled
            Cargo            = if ($user.Title) { $user.Title } else { "" }
            Departamento     = if ($user.Department) { $user.Department } else { "" }
            Escritorio       = if ($user.physicalDeliveryOfficeName) { $user.physicalDeliveryOfficeName } else { "" }
            Empresa          = if ($user.Company) { $user.Company } else { "" }
Email            = if ($user.Mail) { $user.Mail } else { "" }
            Vinculo          = if ($user.employeeType) { $user.employeeType } else { "" }
            Descricao        = if ($user.Description) { $user.Description } else { "" }
            Incompleto       = ($missing.Count -gt 0)
            CamposAusentes   = ($missing -join ", ")
            DistinguishedName = $user.DistinguishedName
        }

        [void]$data.Add($obj)
    }

    return $data.ToArray()
}

function Get-ComputerAudit {
    param(
        [string]$SearchBase,
        [string]$StandardOU
    )

    Set-AppStatus "Consultando computadores do Active Directory..."

    $computers = @(Get-ADComputer `
        -SearchBase $SearchBase `
        -Filter * `
        -Properties DistinguishedName, Name, SamAccountName, Enabled `
        -Credential $script:AdminCreds `
        -ErrorAction Stop)

    $data = New-Object System.Collections.Generic.List[object]

    foreach ($computer in $computers) {
        $fora = $false

        if (-not [string]::IsNullOrWhiteSpace($StandardOU)) {
            $fora = -not (
                ($computer.DistinguishedName -eq $StandardOU) -or
                ($computer.DistinguishedName -like "*,${StandardOU}")
            )
        }

        $obj = [PSCustomObject]@{
            Nome        = $computer.Name
            Login       = $computer.SamAccountName
            Ativo       = [bool]$computer.Enabled
            ForaOUPadrao = $fora
            OUAtual     = $computer.DistinguishedName
        }

        [void]$data.Add($obj)
    }

    return $data.ToArray()
}

function Build-AuditData {
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($u in @($script:UsersAudit | Where-Object { $_.Incompleto })) {
        $parts = @($u.CamposAusentes -split ", " | Where-Object { $_ })

        foreach ($field in $parts) {
            [void]$rows.Add([PSCustomObject]@{
                Categoria = "Usuario"
                Inconsistencia = "Sem $field"
                Nome = $u.Nome
                Login = $u.Login
                Detalhe = $field
                Ativo = $u.Ativo
                Origem = $u.DistinguishedName
            })
        }
    }

    foreach ($c in @($script:ComputersAudit | Where-Object { $_.ForaOUPadrao })) {
        [void]$rows.Add([PSCustomObject]@{
            Categoria = "Computador"
            Inconsistencia = "Fora da OU padrao"
            Nome = $c.Nome
            Login = $c.Login
            Detalhe = "OU atual: $($c.OUAtual)"
            Ativo = $c.Ativo
            Origem = $c.OUAtual
        })
    }

    $script:AuditData = $rows.ToArray()
}

function Update-AuditCounters {
    $users = @($script:UsersAudit)
    $computers = @($script:ComputersAudit)

    $active = @($users | Where-Object { $_.Ativo }).Count
    $disabled = @($users | Where-Object { -not $_.Ativo }).Count
    $incomplete = @($users | Where-Object { $_.Incompleto }).Count
    $noDepartment = @($users | Where-Object { [string]::IsNullOrWhiteSpace($_.Departamento) -and $_.Ativo }).Count
    $noTitle = @($users | Where-Object { [string]::IsNullOrWhiteSpace($_.Cargo) -and $_.Ativo }).Count
    $noOffice = @($users | Where-Object { [string]::IsNullOrWhiteSpace($_.Escritorio) -and $_.Ativo }).Count

    if ($null -ne $script:cardActive) {
        $script:cardActive.Text = [string]$active
        $script:cardDisabled.Text = [string]$disabled
        $script:cardIncomplete.Text = [string]$incomplete
        $script:cardNoDepartment.Text = [string]$noDepartment
        $script:cardNoTitle.Text = [string]$noTitle
        $script:cardNoOffice.Text = [string]$noOffice
    }

    if ($null -ne $script:cardOutsideOU) {
        if ([string]::IsNullOrWhiteSpace($script:StandardComputerOUDN)) {
            $script:cardOutsideOU.Text = "-"
        }
        else {
            $outside = @($computers | Where-Object { $_.ForaOUPadrao }).Count
            $script:cardOutsideOU.Text = [string]$outside
        }
    }
}

function Invoke-AuditCentral {
    if ($null -ne $script:auditAsync -and -not $script:auditAsync.IsCompleted) {
        Show-WarningMessage "Ja existe uma auditoria em execucao. Aguarde a conclusao."
        return
    }

    if (-not (Ensure-ADModule)) { return }

    try {
        if ([string]::IsNullOrWhiteSpace($script:UserSearchBaseDN)) {
            $script:UserSearchBaseDN = Resolve-SearchBase $script:Padroes.OUUsuarios
        }

        if ([string]::IsNullOrWhiteSpace($script:ComputerSearchBaseDN)) {
            $script:ComputerSearchBaseDN = Resolve-SearchBase "dominio.com.br/WORKSTATIONS/"
        }
    }
    catch {
        Show-ErrorMessage "Nao foi possivel resolver os escopos da auditoria.`r`n`r`n$($_.Exception.Message)"
        return
    }

    $userBase = $script:UserSearchBaseDN
    $compBase = $script:ComputerSearchBaseDN
    $stdOU = [string]$script:StandardComputerOUDN
    $cred = $script:AdminCreds

    $blocoAudit = {
        param($Cred, $UserBase, $CompBase, $StdOU)

        Import-Module ActiveDirectory -ErrorAction Stop

        $users = @(Get-ADUser `
            -SearchBase $UserBase `
            -Filter * `
            -Properties DisplayName, SamAccountName, Enabled, Title, Department, physicalDeliveryOfficeName, Company, Mail, employeeType, Description, DistinguishedName `
            -Credential $Cred `
            -ErrorAction Stop)

        $dataUsers = New-Object System.Collections.Generic.List[object]

        foreach ($user in $users) {
            $missing = New-Object System.Collections.Generic.List[string]

            if ([string]::IsNullOrWhiteSpace([string]$user.Title)) { [void]$missing.Add("Cargo") }
            if ([string]::IsNullOrWhiteSpace([string]$user.Department)) { [void]$missing.Add("Departamento") }
            if ([string]::IsNullOrWhiteSpace([string]$user.physicalDeliveryOfficeName)) { [void]$missing.Add("Escritorio") }
            if ([string]::IsNullOrWhiteSpace([string]$user.Company)) { [void]$missing.Add("Empresa") }
            if ([string]::IsNullOrWhiteSpace([string]$user.Mail)) { [void]$missing.Add("E-mail") }
            if ([string]::IsNullOrWhiteSpace([string]$user.employeeType)) { [void]$missing.Add("Vinculo") }
            if ([string]::IsNullOrWhiteSpace([string]$user.Description)) { [void]$missing.Add("Descricao") }

            [void]$dataUsers.Add([PSCustomObject]@{
                Nome             = if ($user.DisplayName) { $user.DisplayName } else { $user.SamAccountName }
                Login            = $user.SamAccountName
                Ativo            = [bool]$user.Enabled
                Cargo            = if ($user.Title) { $user.Title } else { "" }
                Departamento     = if ($user.Department) { $user.Department } else { "" }
                Escritorio       = if ($user.physicalDeliveryOfficeName) { $user.physicalDeliveryOfficeName } else { "" }
                Empresa          = if ($user.Company) { $user.Company } else { "" }
                Email            = if ($user.Mail) { $user.Mail } else { "" }
                Vinculo          = if ($user.employeeType) { $user.employeeType } else { "" }
                Descricao        = if ($user.Description) { $user.Description } else { "" }
                Incompleto       = ($missing.Count -gt 0)
                CamposAusentes   = ($missing -join ", ")
                DistinguishedName = $user.DistinguishedName
            })
        }

        $computers = @(Get-ADComputer `
            -SearchBase $CompBase `
            -Filter * `
            -Properties DistinguishedName, Name, SamAccountName, Enabled `
            -Credential $Cred `
            -ErrorAction Stop)

        $dataComputers = New-Object System.Collections.Generic.List[object]

        foreach ($computer in $computers) {
            $fora = $false

            if (-not [string]::IsNullOrWhiteSpace($StdOU)) {
                $fora = -not (
                    ($computer.DistinguishedName -eq $StdOU) -or
                    ($computer.DistinguishedName -like "*,$StdOU")
                )
            }

            [void]$dataComputers.Add([PSCustomObject]@{
                Nome        = $computer.Name
                Login       = $computer.SamAccountName
                Ativo       = [bool]$computer.Enabled
                ForaOUPadrao = $fora
                OUAtual     = $computer.DistinguishedName
            })
        }

        return [PSCustomObject]@{
            Users      = $dataUsers.ToArray()
            Computers  = $dataComputers.ToArray()
        }
    }

    Set-AppStatus "Iniciando auditoria (pode levar alguns minutos)..."
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $script:btnAudit.Enabled = $false
    $script:btnAudit.Text = "Auditando..."

    $script:auditPipe = [System.Management.Automation.PowerShell]::Create()
    [void]$script:auditPipe.AddScript($blocoAudit)
    [void]$script:auditPipe.AddArgument($cred)
    [void]$script:auditPipe.AddArgument($userBase)
    [void]$script:auditPipe.AddArgument($compBase)
    [void]$script:auditPipe.AddArgument($stdOU)

    try {
        $script:auditAsync = $script:auditPipe.BeginInvoke()
    }
    catch {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $script:btnAudit.Enabled = $true
        $script:btnAudit.Text = "Executar auditoria"
        $script:auditPipe.Dispose()
        $script:auditPipe = $null
        $script:auditAsync = $null
        Show-ErrorMessage "Nao foi possivel iniciar a auditoria.`r`n`r`n$($_.Exception.Message)"
        return
    }

    $script:auditTimer = New-Object System.Windows.Forms.Timer
    $script:auditTimer.Interval = 500

    $script:auditTimer.Add_Tick({
        if ($null -eq $script:auditAsync) {
            $script:auditTimer.Stop()
            return
        }

        if (-not $script:auditAsync.IsCompleted) {
            return
        }

        $script:auditTimer.Stop()

        $form.Cursor = [System.Windows.Forms.Cursors]::Default
        $script:btnAudit.Enabled = $true
        $script:btnAudit.Text = "Executar auditoria"

        try {
            $saida = $script:auditPipe.EndInvoke($script:auditAsync)
            $res = $saida[0]

            $script:UsersAudit = @($res.Users)
            $script:ComputersAudit = @($res.Computers)

            Build-AuditData
            Update-AuditCounters

            Set-AppStatus "Auditoria concluida. Usuarios: $($script:UsersAudit.Count) | Computadores: $($script:ComputersAudit.Count)"
        }
        catch {
            $script:UsersAudit = @()
            $script:ComputersAudit = @()
            Build-AuditData
            Update-AuditCounters
            Set-AppStatus "Erro durante a auditoria."
            Show-ErrorMessage "A auditoria encontrou um erro.`r`n`r`n$($_.Exception.Message)"
        }
        finally {
            $script:auditPipe.Dispose()
            $script:auditPipe = $null
            $script:auditAsync = $null
        }
    })

    $script:auditTimer.Start()
}

function Show-AuditCentral {

    Clear-Content

    Add-StandardTitle `
        $content `
        "Central de inconsistencias" `
        "Auditoria em modo somente leitura para identificar cadastros incompletos e maquinas fora da OU padrao."

    $gb = New-GroupBox "Escopos da auditoria" 25 92 965 150
    $content.Controls.Add($gb)

    $l1 = New-Label "Base de usuarios (opcional):" 20 28 260 22
    $gb.Controls.Add($l1)

    $script:txtUserBase = New-TextBox 20 54 800 28
    $script:txtUserBase.Text = if ($script:UserSearchBaseDN) { $script:UserSearchBaseDN } else { $script:Padroes.OUUsuarios }
    $gb.Controls.Add($script:txtUserBase)

    $lHint1 = New-Label "Aceita DN ou caminho amigavel, ex.: dominio.com.br/USUARIOS/" 20 87 800 20
    $lHint1.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lHint1.ForeColor = $script:Colors.Muted
    $gb.Controls.Add($lHint1)

    $l2 = New-Label "Base de computadores (opcional):" 20 113 300 22
    $gb.Controls.Add($l2)

    $script:txtCompBase = New-TextBox 300 113 520 28
    $script:txtCompBase.Text = if ($script:ComputerSearchBaseDN) { $script:ComputerSearchBaseDN } else { "dominio.com.br/WORKSTATIONS/" }
    $gb.Controls.Add($script:txtCompBase)

    $script:btnSalvarEscopos = New-ActionButton "Salvar escopos" 640 175 150 32 $script:Colors.Success
    $content.Controls.Add($script:btnSalvarEscopos)

    $script:csvOU = New-TextBox 25 258 700 30
    $script:csvOU.Text = if ($script:StandardComputerOUDN) { $script:StandardComputerOUDN } else { "" }
    $content.Controls.Add($script:csvOU)

    $script:lblOU = New-Label "OU padrao dos computadores (opcional):" 25 233 400 22
    $content.Controls.Add($script:lblOU)

    $script:btnAudit = New-ActionButton "Executar auditoria" 750 256 210 34 $script:Colors.Primary
    $content.Controls.Add($script:btnAudit)

    $script:cardActive = Add-AuditCard $content "Usuarios ativos" "0" 25 310 185 100 $script:Colors.Success
    $script:cardDisabled = Add-AuditCard $content "Usuarios desativados" "0" 225 310 185 100 $script:Colors.Muted
    $script:cardIncomplete = Add-AuditCard $content "Cadastros incompletos" "0" 425 310 205 100 $script:Colors.Warning
    $script:cardNoDepartment = Add-AuditCard $content "Sem departamento" "0" 645 310 180 100 $script:Colors.Warning
    $script:cardNoTitle = Add-AuditCard $content "Sem cargo" "0" 840 310 145 100 $script:Colors.Warning
    $script:cardNoOffice = Add-AuditCard $content "Sem escritorio" "0" 25 425 185 100 $script:Colors.Warning
    $script:cardOutsideOU = Add-AuditCard $content "Maquinas fora da OU" "0" 225 425 205 100 $script:Colors.Danger

    $hintBox = New-GroupBox "Como usar" 25 545 965 140
    $content.Controls.Add($hintBox)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = "1. Configure os escopos da auditoria (opcional).`r`n" +
        "2. Informe a OU padrao dos computadores para habilitar essa verificacao.`r`n" +
        "3. Execute a auditoria.`r`n" +
        "4. Use as opcoes abaixo para detalhar as inconsistencias encontradas.`r`n" +
        "5. Exporte os resultados para CSV."
    $hint.Location = New-Object System.Drawing.Point(20, 28)
    $hint.Size = New-Object System.Drawing.Size(900, 100)
    $hint.ForeColor = $script:Colors.Text

    $hintBox.Controls.Add($hint)

    $btnInconsistencias = New-ActionButton "Ver inconsistencias" 25 705 220 40 $script:Colors.Primary
    $content.Controls.Add($btnInconsistencias)

    $btnIncompletos = New-ActionButton "Cadastros incompletos" 255 705 220 40 $script:Colors.Primary
    $content.Controls.Add($btnIncompletos)

    $btnForaOU = New-ActionButton "Maquinas fora da OU" 485 705 220 40 $script:Colors.Primary
    $content.Controls.Add($btnForaOU)

    $btnExportAudit = New-ActionButton "Exportar inconsistencia" 715 705 220 40 $script:Colors.Success
    $content.Controls.Add($btnExportAudit)

    $btnInconsistencias.Add_Click({ Show-AuditInconsistencias })
    $btnIncompletos.Add_Click({ Show-AuditUsersIncomplete })
    $btnForaOU.Add_Click({ Show-AuditComputersOutsideOU })
    $btnExportAudit.Add_Click({ Export-AuditCSV -Rows $script:AuditData })

    $script:btnSalvarEscopos.Add_Click({
        try {
            $script:UserSearchBaseDN = Resolve-SearchBase $script:txtUserBase.Text.Trim()
            $script:ComputerSearchBaseDN = Resolve-SearchBase $script:txtCompBase.Text.Trim()

            if ([string]::IsNullOrWhiteSpace($script:csvOU.Text)) {
                $script:StandardComputerOUDN = ""
            }
            else {
                $script:StandardComputerOUDN = Resolve-SearchBase $script:csvOU.Text

                $null = Get-ADOrganizationalUnit `
                    -Identity $script:StandardComputerOUDN `
                    -Credential $script:AdminCreds `
                    -ErrorAction Stop
            }

            Show-InfoMessage "Escopos salvos.`r`n`r`nOU padrao de maquinas: $(if ($script:StandardComputerOUDN) { $script:StandardComputerOUDN } else { "nao configurada" })"
            Set-AppStatus "Escopos atualizados."
        }
        catch {
            Show-ErrorMessage "Nao foi possivel salvar os escopos.`r`n`r`n$($_.Exception.Message)"
        }
    })

    $script:btnAudit.Add_Click({ Invoke-AuditCentral })

    Update-AuditCounters
}

function Show-AuditInconsistencias {

    Clear-Content

    Add-StandardTitle `
        $content `
        "Inconsistencias encontradas" `
        "Lista consolidada de problemas identificados pela auditoria atual."

    $script:filterAudit = New-Object System.Windows.Forms.ComboBox
    $script:filterAudit.Location = New-Object System.Drawing.Point(25, 92)
    $script:filterAudit.Size = New-Object System.Drawing.Size(200, 28)
    $script:filterAudit.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$script:filterAudit.Items.Add("Todas")
    [void]$script:filterAudit.Items.Add("Usuarios")
    [void]$script:filterAudit.Items.Add("Computadores")
    $script:filterAudit.SelectedIndex = 0
    $content.Controls.Add($script:filterAudit)

    $script:txtAuditSearch = New-TextBox 240 92 350 28
    $script:txtAuditSearch.Text = "Pesquisar nome, login ou inconsistencia..."
    $content.Controls.Add($script:txtAuditSearch)

    $btnExport = New-ActionButton "Exportar CSV" 605 88 155 36 $script:Colors.Success
    $content.Controls.Add($btnExport)

    $btnVoltar = New-ActionButton "Voltar" 770 88 155 36 $script:Colors.Dark
    $content.Controls.Add($btnVoltar)

    $script:gridAudit = New-Object System.Windows.Forms.DataGridView
    $script:gridAudit.Location = New-Object System.Drawing.Point(25, 135)
    $script:gridAudit.Size = New-Object System.Drawing.Size(935, 440)
    $script:gridAudit.ReadOnly = $true
    $script:gridAudit.AllowUserToAddRows = $false
    $script:gridAudit.AllowUserToDeleteRows = $false
    $script:gridAudit.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $script:gridAudit.MultiSelect = $false
    $script:gridAudit.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $script:gridAudit.RowHeadersVisible = $false
    $script:gridAudit.BackgroundColor = [System.Drawing.Color]::White
    $script:gridAudit.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $content.Controls.Add($script:gridAudit)

    [void]$script:gridAudit.Columns.Add("Categoria", "Categoria")
    [void]$script:gridAudit.Columns.Add("Inconsistencia", "Inconsistencia")
    [void]$script:gridAudit.Columns.Add("Nome", "Nome")
    [void]$script:gridAudit.Columns.Add("Login", "Login")
    [void]$script:gridAudit.Columns.Add("Detalhe", "Detalhe")
    [void]$script:gridAudit.Columns.Add("Ativo", "Ativo")

    $script:RecarregarAudit = {
        $script:gridAudit.Rows.Clear()

        $cat = [string]$script:filterAudit.SelectedItem
        $term = $script:txtAuditSearch.Text.Trim()

        if ($term -eq "Pesquisar nome, login ou inconsistencia...") {
            $term = ""
        }

        $items = @($script:AuditData)

        if ($cat -eq "Usuarios") {
            $items = @($items | Where-Object { $_.Categoria -eq "Usuario" })
        }
        elseif ($cat -eq "Computadores") {
            $items = @($items | Where-Object { $_.Categoria -eq "Computador" })
        }

        if (-not [string]::IsNullOrWhiteSpace($term)) {
            $items = @($items | Where-Object {
                $_.Nome -like "*$term*" -or
                $_.Login -like "*$term*" -or
                $_.Inconsistencia -like "*$term*" -or
                $_.Detalhe -like "*$term*"
            })
        }

        foreach ($item in $items) {
            [void]$script:gridAudit.Rows.Add(
                $item.Categoria,
                $item.Inconsistencia,
                $item.Nome,
                $item.Login,
                $item.Detalhe,
                $(if ($item.Ativo) { "Sim" } else { "Nao" })
            )
        }

        Set-AppStatus "$($items.Count) inconsistencia(s) exibida(s)."
    }

    $script:filterAudit.Add_SelectedIndexChanged({ & $script:RecarregarAudit })
    $script:txtAuditSearch.Add_TextChanged({ & $script:RecarregarAudit })

    $btnExport.Add_Click({ Export-AuditCSV -Rows $script:AuditData })
    $btnVoltar.Add_Click({ Show-AuditCentral })

    & $script:RecarregarAudit
}

function Show-AuditUsersIncomplete {

    Clear-Content

    Add-StandardTitle `
        $content `
        "Cadastros incompletos" `
        "Usuarios com pelo menos um campo cadastral considerado obrigatorio."

    $script:gridAuditUsers = New-Object System.Windows.Forms.DataGridView
    $script:gridAuditUsers.Location = New-Object System.Drawing.Point(25, 92)
    $script:gridAuditUsers.Size = New-Object System.Drawing.Size(935, 480)
    $script:gridAuditUsers.ReadOnly = $true
    $script:gridAuditUsers.AllowUserToAddRows = $false
    $script:gridAuditUsers.AllowUserToDeleteRows = $false
    $script:gridAuditUsers.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $script:gridAuditUsers.MultiSelect = $false
    $script:gridAuditUsers.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $script:gridAuditUsers.RowHeadersVisible = $false
    $script:gridAuditUsers.BackgroundColor = [System.Drawing.Color]::White
    $script:gridAuditUsers.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $content.Controls.Add($script:gridAuditUsers)

    [void]$script:gridAuditUsers.Columns.Add("Nome", "Nome")
    [void]$script:gridAuditUsers.Columns.Add("Login", "Login")
    [void]$script:gridAuditUsers.Columns.Add("Cargo", "Cargo")
    [void]$script:gridAuditUsers.Columns.Add("Departamento", "Departamento")
    [void]$script:gridAuditUsers.Columns.Add("Escritorio", "Escritorio")
    [void]$script:gridAuditUsers.Columns.Add("Empresa", "Empresa")
    [void]$script:gridAuditUsers.Columns.Add("CamposAusentes", "Campos ausentes")

    foreach ($u in @($script:UsersAudit | Where-Object { $_.Incompleto })) {
        [void]$script:gridAuditUsers.Rows.Add(
            $u.Nome,
            $u.Login,
            $u.Cargo,
            $u.Departamento,
            $u.Escritorio,
            $u.Empresa,
            $u.CamposAusentes
        )
    }

    $btnExport = New-ActionButton "Exportar usuarios" 25 595 190 38 $script:Colors.Success
    $content.Controls.Add($btnExport)

    $btnVoltar = New-ActionButton "Voltar" 225 595 190 38 $script:Colors.Dark
    $content.Controls.Add($btnVoltar)

    $btnExport.Add_Click({
        $rows = @($script:UsersAudit | Where-Object { $_.Incompleto })
        Export-AuditCSV -Rows $rows
    })

    $btnVoltar.Add_Click({ Show-AuditCentral })

    Set-AppStatus "$(@($script:UsersAudit | Where-Object { $_.Incompleto }).Count) cadastro(s) incompleto(s)."
}

function Show-AuditComputersOutsideOU {

    Clear-Content

    Add-StandardTitle `
        $content `
        "Maquinas fora da OU padrao" `
        "Lista de computadores cuja OU atual nao corresponde a configuracao definida."

    if ([string]::IsNullOrWhiteSpace($script:StandardComputerOUDN)) {
        $warning = New-Object System.Windows.Forms.Label
        $warning.Text = "A OU padrao de computadores ainda nao foi configurada. Acesse a Central de inconsistencias."
        $warning.Location = New-Object System.Drawing.Point(25, 95)
        $warning.Size = New-Object System.Drawing.Size(900, 35)
        $warning.ForeColor = $script:Colors.Danger
        $warning.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $content.Controls.Add($warning)
        return
    }

    $lblOU = New-Label "OU padrao: $script:StandardComputerOUDN" 25 95 950 40
    $lblOU.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $content.Controls.Add($lblOU)

    $script:gridAuditComputers = New-Object System.Windows.Forms.DataGridView
    $script:gridAuditComputers.Location = New-Object System.Drawing.Point(25, 145)
    $script:gridAuditComputers.Size = New-Object System.Drawing.Size(935, 420)
    $script:gridAuditComputers.ReadOnly = $true
    $script:gridAuditComputers.AllowUserToAddRows = $false
    $script:gridAuditComputers.AllowUserToDeleteRows = $false
    $script:gridAuditComputers.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $script:gridAuditComputers.MultiSelect = $false
    $script:gridAuditComputers.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $script:gridAuditComputers.RowHeadersVisible = $false
    $script:gridAuditComputers.BackgroundColor = [System.Drawing.Color]::White
    $script:gridAuditComputers.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $content.Controls.Add($script:gridAuditComputers)

    [void]$script:gridAuditComputers.Columns.Add("Nome", "Maquina")
    [void]$script:gridAuditComputers.Columns.Add("Login", "SamAccountName")
    [void]$script:gridAuditComputers.Columns.Add("Ativo", "Ativo")
    [void]$script:gridAuditComputers.Columns.Add("OUAtual", "OU atual")

    foreach ($c in @($script:ComputersAudit | Where-Object { $_.ForaOUPadrao })) {
        [void]$script:gridAuditComputers.Rows.Add(
            $c.Nome,
            $c.Login,
            $(if ($c.Ativo) { "Sim" } else { "Nao" }),
            $c.OUAtual
        )
    }

    $btnExport = New-ActionButton "Exportar maquinas" 25 590 190 38 $script:Colors.Success
    $content.Controls.Add($btnExport)

    $btnVoltar = New-ActionButton "Voltar" 225 590 190 38 $script:Colors.Dark
    $content.Controls.Add($btnVoltar)

    $btnExport.Add_Click({
        $rows = @($script:ComputersAudit | Where-Object { $_.ForaOUPadrao })
        Export-AuditCSV -Rows $rows
    })

    $btnVoltar.Add_Click({ Show-AuditCentral })

    Set-AppStatus "$(@($script:ComputersAudit | Where-Object { $_.ForaOUPadrao }).Count) maquina(s) fora da OU padrao."
}

function Export-AuditCSV {
    param([array]$Rows)

    if ($null -eq $Rows -or @($Rows).Count -eq 0) {
        Show-WarningMessage "Nao ha dados para exportar."
        return
    }

    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = "Arquivo CSV (*.csv)|*.csv"
    $dialog.Title = "Exportar auditoria"
    $dialog.FileName = "Auditoria-AD-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    try {
        @($Rows) | Export-Csv `
            -Path $dialog.FileName `
            -NoTypeInformation `
            -Encoding UTF8 `
            -Delimiter ';'

        Show-InfoMessage "Arquivo exportado com sucesso:`r`n`r`n$($dialog.FileName)"
        Set-AppStatus "Exportacao concluida."
    }
    catch {
        Show-ErrorMessage "Nao foi possivel exportar o CSV.`r`n`r`n$($_.Exception.Message)"
    }
}

# ============================================================
# NAVEGACAO
# ============================================================

$btnDashboard = Add-SidebarButton "Inicio / Dashboard" 55 { Show-Dashboard }
$btnSenha = Add-SidebarButton "Reset / desbloqueio de senha" 105 { Show-ResetSenha }
$btnAcessos = Add-SidebarButton "Consultar acessos" 155 { Show-Acessos }
$btnDesativar = Add-SidebarButton "Desativar usuario" 205 { Show-Desativar }
$btnMaquinas = Add-SidebarButton "Mover maquinas / OU" 255 { Show-Maquinas }
$btnRelatorio = Add-SidebarButton "Gerar relatorio" 305 { Show-Report }
$btnEmMassa = Add-SidebarButton "Alteracao em massa" 355 { Show-EmMassa }
$btnLog = Add-SidebarButton "Historico do usuario" 405 { Show-Log }
$btnCadastro = Add-SidebarButton "Cadastro de usuario" 455 { Show-Cadastro }
$btnGrupos = Add-SidebarButton "Gerenciar grupos" 505 { Show-Grupos }
$btnPadroes = Add-SidebarButton "Valores padronizados" 555 { Show-Padroes }
$btnCentral = Add-SidebarButton "Central de inconsistencias" 605 { Show-AuditCentral }

$linha = New-Object System.Windows.Forms.Label
$linha.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
$linha.Location = New-Object System.Drawing.Point(15, 660)
$linha.Size = New-Object System.Drawing.Size(215, 2)
$sidebar.Controls.Add($linha)

$btnTrocarLogin = Add-SidebarButton "Trocar login" 680 {
    $cred = Show-LoginWindow
    if ($cred) {
        Update-LoginDisplay
        Show-Dashboard
        Set-AppStatus "Login alterado."
    }
}

$btnSair = Add-SidebarButton "Sair" 730 {
    if (Confirm-Action "Deseja realmente fechar o Gerenciador AD?" "Sair") {
        $form.Close()
    }
}

# ============================================================
# EVENTOS DO MENU
# ============================================================

$menuLogin.Add_Click({
    $cred = Show-LoginWindow
    if ($cred) {
        Update-LoginDisplay
        Show-Dashboard
        Set-AppStatus "Login alterado."
    }
})

$menuSair.Add_Click({
    if (Confirm-Action "Deseja realmente fechar o Gerenciador AD?" "Sair") {
        $form.Close()
    }
})

$menuSenha.Add_Click({ Show-ResetSenha })
$menuAcessos.Add_Click({ Show-Acessos })
$menuDesativar.Add_Click({ Show-Desativar })
$menuMaquinas.Add_Click({ Show-Maquinas })
$menuRelatorio.Add_Click({ Show-Report })
$menuLog.Add_Click({ Show-Log })
$menuCadastro.Add_Click({ Show-Cadastro })
$menuCentral.Add_Click({ Show-AuditCentral })
$menuEmMassa.Add_Click({ Show-EmMassa })
$menuGrupos.Add_Click({ Show-Grupos })
$menuPadroes.Add_Click({ Show-Padroes })

# ============================================================
# INICIALIZACAO
# ============================================================

if (-not (Ensure-ADModule)) {
    return
}

Load-Padroes

if (-not $script:OUDestinoDesativados) {
    $script:OUDestinoDesativados = $script:Padroes.OUUsuarios -replace '^OU=[^,]+,', 'OU=DESATIVADOS,'
}

$credInicial = Show-LoginWindow

if (-not $credInicial) {
    return
}

Update-LoginDisplay
Show-Dashboard
Set-AppStatus "Aplicativo pronto."

# ============================================================
# EXECUCAO
# ============================================================

[void]$form.ShowDialog()

# Limpa a referencia da credencial ao fechar.
$script:AdminCreds = $null
$script:CurrentUser = ""
