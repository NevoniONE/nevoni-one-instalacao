# Instalação da máquina do usuário final do Nevoni ONE.
#
# Uso: no PowerShell COMUM (não como administrador), na conta do Windows do usuário, com o usuário
# presente para o login do GitHub:
#
#   irm https://raw.githubusercontent.com/NevoniONE/nevoni-one-instalacao/main/instalar.ps1 | iex
#
# Pode rodar de novo quantas vezes precisar: o que já estiver feito é só conferido.
# Só a conferência final, sem mudar nada:
#
#   $env:NEVONI_MODO = "conferir"; irm https://raw.githubusercontent.com/NevoniONE/nevoni-one-instalacao/main/instalar.ps1 | iex
#
# Este arquivo não contém nenhum segredo: o login e o token são do próprio usuário, feitos na hora.
# Roteiro completo da TI: docs/ROTEIRO_INSTALACAO_USUARIO_FINAL.md, no repositório do núcleo.

function Instalar-NevoniONE {
  $ORG = "NevoniONE"
  $PNPM_VERSAO = "9.12.0"
  $PASTA = Join-Path $env:LOCALAPPDATA "NevoniONE"
  $MANAGED = "C:\Program Files\ClaudeCode\managed-settings.json"
  $MANAGED_CONTEUDO = '{ "disableAutoMode": "disable", "permissions": { "disableBypassPermissionsMode": "disable" } }'
  $PROGRAMAS = @(
    @{ Comando = "git"; Nome = "Git"; Instalar = "Instalar-Git" },
    @{ Comando = "node"; Nome = "Node.js"; Instalar = "Instalar-Node" },
    @{ Comando = "gh"; Nome = "GitHub CLI"; Instalar = "Instalar-GhCli" }
  )

  function Etapa($texto) { Write-Host ""; Write-Host "== $texto ==" -ForegroundColor Cyan }
  function Ok($texto) { Write-Host "  ok     $texto" -ForegroundColor Green }
  function Aviso($texto) { Write-Host "  AVISO  $texto" -ForegroundColor Yellow }
  function Falha($texto) { Write-Host "  FALHA  $texto" -ForegroundColor Red }
  function Existe($comando) { [bool](Get-Command $comando -ErrorAction SilentlyContinue) }
  function Atualizar-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
  }
  # Roda comandos numa única janela de administrador (uma senha só). Os instaladores MSI (Node,
  # GitHub CLI) em modo silencioso não pedem a senha sozinhos: sem administrador, só recusam.
  function Como-Administrador($comandos) {
    $log = Join-Path $env:PUBLIC "nevoni-one-instalacao.log"
    Remove-Item $log -ErrorAction SilentlyContinue
    # Funções da janela de administrador. Sem winget: numa janela elevada por outra conta (a
    # administradora), o Windows nega a execução do winget, que é um app da Loja por usuário
    # (achado da simulação T1). Os instaladores vêm direto das fontes oficiais, com o hash
    # SHA-256 conferido; a desinstalação usa o registro do Windows ("Adicionar ou remover programas").
    $funcoesAdmin = @'
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$pastaTemp = Join-Path $env:TEMP "nevoni-one-instalacao"
New-Item -ItemType Directory -Force $pastaTemp | Out-Null
function Baixar($url, $nome, $sha256) {
  $destino = Join-Path $pastaTemp $nome
  Write-Host "baixando $url"
  Invoke-WebRequest -Uri $url -OutFile $destino -UseBasicParsing
  if (-not $sha256) { throw "sem hash para conferir $nome" }
  if ((Get-FileHash $destino -Algorithm SHA256).Hash.ToLower() -ne $sha256.ToLower()) { throw "o hash de $nome não confere" }
  Write-Host "hash conferido: $nome"
  return $destino
}
function Instalador-GitHub($repo, $padrao) {
  $versao = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing -Headers @{ "User-Agent" = "nevoni-one-instalacao" }
  $item = $versao.assets | Where-Object { $_.name -match $padrao } | Select-Object -First 1
  if (-not $item) { throw "não achei o instalador em $repo" }
  $sha = if ("$($item.digest)" -like "sha256:*") { "$($item.digest)".Substring(7) } else { $null }
  return Baixar $item.browser_download_url $item.name $sha
}
function Rodar-Msi($arquivo, $acao) {
  $p = Start-Process msiexec.exe -ArgumentList $acao, "`"$arquivo`"", "/qn", "/norestart" -Wait -PassThru
  if ($p.ExitCode -notin 0, 3010) { throw "msiexec terminou com código $($p.ExitCode)" }
}
function Instalar-Git {
  $f = Instalador-GitHub "git-for-windows/git" '^Git-[\d.]+-64-bit\.exe$'
  $p = Start-Process $f -ArgumentList "/VERYSILENT", "/NORESTART", "/SP-", "/SUPPRESSMSGBOXES" -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "instalador do Git terminou com código $($p.ExitCode)" }
}
function Instalar-Node {
  $versao = (Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -UseBasicParsing | Where-Object { $_.lts } | Select-Object -First 1).version
  $nome = "node-$versao-x64.msi"
  $somas = (Invoke-WebRequest -Uri "https://nodejs.org/dist/$versao/SHASUMS256.txt" -UseBasicParsing).Content
  $sha = ($somas -split "`n" | Where-Object { $_.Trim().EndsWith($nome) } | Select-Object -First 1) -split "\s+" | Select-Object -First 1
  Rodar-Msi (Baixar "https://nodejs.org/dist/$versao/$nome" $nome $sha) "/i"
}
function Instalar-GhCli {
  Rodar-Msi (Instalador-GitHub "cli/cli" '^gh_[\d.]+_windows_amd64\.msi$') "/i"
}
function Desinstalar($padrao) {
  $chaves = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
  $itens = Get-ItemProperty $chaves -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match $padrao }
  foreach ($i in $itens) {
    Write-Host "desinstalando $($i.DisplayName)"
    if ($i.WindowsInstaller -eq 1) {
      $p = Start-Process msiexec.exe -ArgumentList "/x", $i.PSChildName, "/qn", "/norestart" -Wait -PassThru
    } else {
      $p = Start-Process $i.UninstallString.Trim('"') -ArgumentList "/VERYSILENT", "/NORESTART", "/SUPPRESSMSGBOXES" -Wait -PassThru
    }
    Write-Host "  código de saída: $($p.ExitCode)"
  }
}
function Tentar($rotulo, [scriptblock]$acao) {
  try { & $acao; Write-Host "OK: $rotulo" } catch { Write-Host "ERRO em ${rotulo}: $($_.Exception.Message)" }
}
'@
    $script = "Start-Transcript -Path '$log' -Force | Out-Null`r`n$funcoesAdmin`r`n$($comandos -join "`r`n")`r`nStop-Transcript | Out-Null"
    $codificado = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    Write-Host "  o Windows vai pedir a senha de administrador; uma janela abre, trabalha e fecha sozinha..."
    try { Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $codificado" }
    catch { Falha "a senha de administrador não foi informada"; return $false }
    return $true
  }
  function Conta-GitHub {
    if (-not (Existe "gh")) { return "" }
    $login = gh api user -q .login 2>$null
    if ($LASTEXITCODE -ne 0) { return "" }
    return "$login".Trim()
  }
  function Repositorios {
    $nomes = gh repo list $ORG --limit 100 --json name -q ".[].name" 2>$null
    return @($nomes | Where-Object { $_ -like "nevoni-one-modulo-*" })
  }
  function Usuario-EhAdministrador {
    return [bool]((whoami /groups) -match "S-1-5-32-544")
  }

  function Conferir {
    Etapa "Conferência final"
    $falhas = 0
    foreach ($p in $PROGRAMAS) {
      if (Existe $p.Comando) { Ok "$($p.Nome) instalado" } else { Falha "$($p.Nome) não está instalado"; $falhas++ }
    }
    $v = if (Existe "pnpm") { "$(pnpm --version 2>$null)".Trim() } else { "" }
    if ($v -eq $PNPM_VERSAO) { Ok "pnpm $PNPM_VERSAO" } else { Falha "pnpm deveria ser $PNPM_VERSAO (está '$v')"; $falhas++ }

    $conta = Conta-GitHub
    if (-not $conta) { Falha "GitHub CLI sem login"; $falhas++ }
    elseif ($conta -eq $ORG) { Falha "o GitHub está logado com a conta guardiã ($ORG). Use a conta do usuário"; $falhas++ }
    else {
      Ok "GitHub logado como $conta"
      $status = (gh auth status 2>&1 | Out-String)
      if ($status -match "read:packages") { Ok "token com read:packages" } else { Falha "token sem read:packages"; $falhas++ }
    }

    $helper = (git config --global --get-all credential.https://github.com.helper 2>$null | Out-String)
    if ($helper -match "auth git-credential") { Ok "o Git usa o login do GitHub CLI (sem a janela de contas)" } else { Falha "o Git não usa o login do GitHub CLI"; $falhas++ }
    $email = "$(git config --global user.email 2>$null)".Trim()
    if ($email -like "*@users.noreply.github.com") { Ok "e-mail privado do GitHub: $email" } else { Falha "e-mail do Git não é o privado do GitHub ('$email')"; $falhas++ }
    $nome = "$(git config --global user.name 2>$null)".Trim()
    if ($nome) { Ok "nome nos envios: $nome" } else { Falha "nome do Git em branco"; $falhas++ }
    if ("$(git config --global core.longpaths 2>$null)".Trim() -eq "true") { Ok "caminhos longos ligados" } else { Falha "core.longpaths não está ligado"; $falhas++ }
    if ("$(git config --global core.autocrlf 2>$null)".Trim() -eq "false") { Ok "quebras de linha pelo repositório" } else { Falha "core.autocrlf deveria ser false"; $falhas++ }

    if ([Environment]::GetEnvironmentVariable("NODE_AUTH_TOKEN", "User")) { Ok "token de leitura dos pacotes gravado" } else { Falha "NODE_AUTH_TOKEN não está gravado"; $falhas++ }

    $protecao = $null
    if (Test-Path $MANAGED) { try { $protecao = Get-Content $MANAGED -Raw | ConvertFrom-Json } catch { $protecao = $null } }
    if ($protecao -and $protecao.disableAutoMode -eq "disable" -and $protecao.permissions.disableBypassPermissionsMode -eq "disable") {
      Ok "proteção do Claude Desktop gravada"
    } else { Falha "proteção do Claude Desktop ausente ou com erro ($MANAGED)"; $falhas++ }

    $repos = if ($conta -and $conta -ne $ORG) { Repositorios } else { @() }
    if ($repos.Count -eq 0) { Falha "nenhum repositório de módulo acessível para a conta do usuário (convite do passo 2?)"; $falhas++ }
    foreach ($r in $repos) {
      $caminho = Join-Path $PASTA $r
      if ((Test-Path (Join-Path $caminho ".git")) -and (Test-Path (Join-Path $caminho "node_modules"))) { Ok "módulo $r em $caminho" }
      else { Falha "módulo $r não está copiado e instalado em $caminho"; $falhas++ }
    }

    if (Usuario-EhAdministrador) { Aviso "a conta do Windows do usuário tem direito de administrador. O roteiro pede uma conta sem esse direito" }

    Write-Host ""
    if ($falhas -eq 0) {
      Write-Host "MÁQUINA PRONTA." -ForegroundColor Green
      Write-Host ""
      Write-Host "Falta só o que é feito na tela do Claude Desktop (roteiro, passos 7 e 9):"
      Write-Host "  1. Feche o Claude Desktop por completo (ícone perto do relógio, botão direito, Sair) e abra de novo."
      Write-Host "  2. Aba Code, escolher pasta, e cole na barra de endereço o caminho de cada módulo:"
      foreach ($r in $repos) { Write-Host "       %LOCALAPPDATA%\NevoniONE\$r" }
      Write-Host "  3. 'Confiar no workspace', modo 'Aceitar edições' e a caixa 'worktree' desmarcada."
      Write-Host "  4. Conversa nova: o usuário digita 'Bom dia!' e confere o passo 9."
    } else {
      Write-Host "A MÁQUINA AINDA NÃO ESTÁ PRONTA: $falhas item(ns) com FALHA acima." -ForegroundColor Red
      Write-Host "Rode o script de novo. Se a falha continuar, mande o print para a one@."
    }
  }

  Write-Host "Instalação da máquina do usuário final do Nevoni ONE" -ForegroundColor Cyan

  if ($env:NEVONI_MODO -eq "conferir") { $env:NEVONI_MODO = $null; Conferir; return }

  $elevado = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if ($elevado) {
    Falha "este PowerShell está como administrador. Feche-o e rode no PowerShell comum, na conta do usuário."
    return
  }

  Etapa "1. Programas e proteção do Claude Desktop"
  $comandos = @()
  foreach ($p in $PROGRAMAS) {
    if (Existe $p.Comando) { Ok "$($p.Nome) já instalado" }
    else {
      Write-Host "  vai instalar: $($p.Nome)"
      $comandos += "Tentar '$($p.Nome)' { $($p.Instalar) }"
    }
  }
  $atual = if (Test-Path $MANAGED) { (Get-Content $MANAGED -Raw).Trim() } else { "" }
  if ($atual -eq $MANAGED_CONTEUDO) { Ok "proteção do Claude Desktop já gravada" }
  else {
    Write-Host "  vai gravar: proteção do Claude Desktop"
    $comandos += "New-Item -ItemType Directory -Force 'C:\Program Files\ClaudeCode' | Out-Null"
    $comandos += "[IO.File]::WriteAllText('$MANAGED', '$MANAGED_CONTEUDO')"
  }
  if ($comandos.Count -gt 0) {
    if (-not (Como-Administrador $comandos)) { return }
    Atualizar-Path
    $faltou = $false
    foreach ($p in $PROGRAMAS) {
      if (Existe $p.Comando) { Ok "$($p.Nome) instalado" } else { Falha "não consegui instalar o $($p.Nome)"; $faltou = $true }
    }
    if (Test-Path $MANAGED) { Ok "proteção do Claude Desktop gravada" } else { Falha "não consegui gravar $MANAGED"; $faltou = $true }
    if ($faltou) { Write-Host "  O registro da janela de administrador está em $env:PUBLIC\nevoni-one-instalacao.log. Mande para a one@."; return }
  }

  Etapa "2. Ajustes na conta do usuário"
  try { Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force -ErrorAction Stop; Ok "execução de scripts liberada para o npm" }
  catch { Aviso "não consegui ajustar a política de execução: $($_.Exception.Message)" }
  $npmGlobal = Join-Path $env:APPDATA "npm"
  $pathUsuario = [Environment]::GetEnvironmentVariable("Path", "User")
  if (-not $pathUsuario) { $pathUsuario = "" }
  if (($pathUsuario -split ";") -notcontains $npmGlobal) {
    [Environment]::SetEnvironmentVariable("Path", (($pathUsuario.TrimEnd(";") + ";" + $npmGlobal).TrimStart(";")), "User")
    Atualizar-Path
    Ok "pasta do npm no caminho do usuário"
  }
  # O aviso do npm é desligado antes de usar o npm, para não aparecer já na instalação.
  npm config set update-notifier false 2>$null
  $v = if (Existe "pnpm") { "$(pnpm --version 2>$null)".Trim() } else { "" }
  if ($v -eq $PNPM_VERSAO) { Ok "pnpm $PNPM_VERSAO já instalado" }
  else {
    npm install -g "pnpm@$PNPM_VERSAO" --no-fund --no-audit --loglevel=error
    Atualizar-Path
    Ok "pnpm $PNPM_VERSAO instalado (a 12.x é bloqueada pelo Smart App Control)"
  }
  pnpm config set update-notifier false 2>$null
  Ok "avisos de atualização do npm e do pnpm desligados (ninguém atualiza por engano)"

  Etapa "3. Login do GitHub (com o usuário presente)"
  $conta = Conta-GitHub
  if ($conta -eq $ORG) {
    Falha "o GitHub está logado com a conta guardiã ($ORG). Ela nunca é usada na máquina do usuário. Saindo dela..."
    gh auth logout --hostname github.com --user $ORG
    $conta = ""
  }
  if ($conta) {
    $resposta = Read-Host "  O GitHub está logado como '$conta'. É a conta do usuário? (S/N)"
    if ($resposta -notmatch "^[sS]") { gh auth logout --hostname github.com --user $conta; $conta = "" }
  }
  if (-not $conta) {
    Write-Host "  Vai aparecer um código de 8 caracteres. Pressione Enter para abrir o navegador,"
    Write-Host "  confira que o GitHub está na conta DO USUÁRIO, cole o código e autorize."
    Write-Host "  Se perguntar 'Authenticate Git with your GitHub credentials?', responda Y."
    gh auth login --hostname github.com --git-protocol https --web --scopes read:packages
    $conta = Conta-GitHub
    if (-not $conta) { Falha "o login do GitHub não foi concluído. Rode o script de novo."; return }
  }
  if ((gh auth status 2>&1 | Out-String) -notmatch "read:packages") {
    Write-Host "  falta a permissão de ler os pacotes; o navegador vai abrir de novo para autorizar."
    gh auth refresh --hostname github.com --scopes read:packages
  }
  gh auth setup-git
  Ok "GitHub logado como $conta, e o Git usa esse login (sem a janela de escolher conta)"

  Etapa "4. Identificação nos envios"
  $id = "$(gh api user -q .id)".Trim()
  $email = "$id+$conta@users.noreply.github.com"
  $nome = "$(git config --global user.name 2>$null)".Trim()
  if (-not $nome) { $nome = "$(gh api user -q .name 2>$null)".Trim() }
  if (-not $nome) { $nome = (Read-Host "  Nome completo do usuário, como deve aparecer nos envios").Trim() }
  git config --global user.name "$nome"
  git config --global user.email "$email"
  git config --global core.autocrlf false
  git config --global core.longpaths true
  Ok "nome '$nome' e e-mail privado $email"
  Write-Host "  (no GitHub do usuário, Settings > Emails, as opções 'Keep my email addresses private' e"
  Write-Host "   'Block command line pushes that expose my email' devem estar marcadas: passo 1 do roteiro)"

  Etapa "5. Token de leitura dos pacotes da empresa"
  $token = "$(gh auth token)".Trim()
  [Environment]::SetEnvironmentVariable("NODE_AUTH_TOKEN", $token, "User")
  $env:NODE_AUTH_TOKEN = $token
  Ok "gravado na conta do usuário (é o mesmo token do login do GitHub e não expira)"

  Etapa "6. Módulos do usuário"
  New-Item -ItemType Directory -Force $PASTA | Out-Null
  $repos = Repositorios
  if ($repos.Count -eq 0) { Falha "a conta $conta não tem acesso a nenhum repositório de módulo. Confira o convite (passo 2 do roteiro)."; return }
  foreach ($r in $repos) {
    $caminho = Join-Path $PASTA $r
    if (Test-Path (Join-Path $caminho ".git")) { Ok "$r já copiado" }
    else {
      gh repo clone "$ORG/$r" "$caminho"
      if ($LASTEXITCODE -ne 0) { Falha "não consegui copiar $r"; continue }
      Ok "$r copiado"
    }
    Push-Location $caminho
    pnpm install --reporter=silent
    $instalou = ($LASTEXITCODE -eq 0)
    Pop-Location
    if ($instalou) { Ok "$r com os pacotes instalados" } else { Falha "pnpm install falhou em $r (erro 401/403: falta liberar a leitura dos pacotes para a conta $conta)" }
  }
  foreach ($antigo in @([Environment]::GetFolderPath("Desktop"), [Environment]::GetFolderPath("MyDocuments"))) {
    Get-ChildItem $antigo -Directory -Recurse -Depth 3 -Filter "nevoni*modulo-*" -ErrorAction SilentlyContinue |
      ForEach-Object { Aviso "cópia antiga fora do lugar padrão: $($_.FullName). Apague-a, com o Claude Desktop fechado." }
  }

  Conferir
}

Instalar-NevoniONE
