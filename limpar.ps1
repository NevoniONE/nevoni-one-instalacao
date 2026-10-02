# Limpeza da máquina do usuário final do Nevoni ONE: desfaz tudo o que o instalar.ps1 fez,
# inclusive os programas (decisão de Fred, 02/10/2026).
#
# Uso: no PowerShell COMUM (não como administrador), na conta do Windows do usuário:
#
#   irm https://raw.githubusercontent.com/NevoniONE/nevoni-one-instalacao/main/limpar.ps1 | iex
#
# Antes de apagar a pasta dos módulos, o script confere se há trabalho que ainda não está no GitHub.

function Limpar-NevoniONE {
  $PASTA = Join-Path $env:LOCALAPPDATA "NevoniONE"
  $MANAGED = "C:\Program Files\ClaudeCode\managed-settings.json"
  $PROGRAMAS = @(
    @{ Id = "GitHub.cli"; Comando = "gh"; Nome = "GitHub CLI" },
    @{ Id = "OpenJS.NodeJS.LTS"; Comando = "node"; Nome = "Node.js" },
    @{ Id = "Git.Git"; Comando = "git"; Nome = "Git" }
  )

  function Etapa($texto) { Write-Host ""; Write-Host "== $texto ==" -ForegroundColor Cyan }
  function Ok($texto) { Write-Host "  ok     $texto" -ForegroundColor Green }
  function Aviso($texto) { Write-Host "  AVISO  $texto" -ForegroundColor Yellow }
  function Falha($texto) { Write-Host "  FALHA  $texto" -ForegroundColor Red }
  function Existe($comando) { [bool](Get-Command $comando -ErrorAction SilentlyContinue) }
  function Atualizar-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
  }

  Write-Host "Limpeza da máquina do usuário final do Nevoni ONE" -ForegroundColor Cyan
  $elevado = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if ($elevado) { Falha "este PowerShell está como administrador. Feche-o e rode no PowerShell comum, na conta do usuário."; return }

  Write-Host ""
  Write-Host "Vai ser removido desta conta do Windows:"
  Write-Host "  - o login do GitHub, o token dos pacotes e as contas do GitHub guardadas no Windows;"
  Write-Host "  - as configurações do Git feitas na instalação;"
  Write-Host "  - a pasta dos módulos ($PASTA);"
  Write-Host "  - o pnpm e as configurações do npm;"
  Write-Host "  - a proteção do Claude Desktop;"
  Write-Host "  - os programas Git, Node.js e GitHub CLI."
  Write-Host "O Claude Desktop não é desinstalado. Se a máquina deixar de ser do usuário, saia da conta dele no app."
  if ((Read-Host "Para confirmar, digite LIMPAR") -ne "LIMPAR") { Write-Host "Nada foi feito."; return }

  if (Get-Process -Name "Claude" -ErrorAction SilentlyContinue) {
    Read-Host "Feche o Claude Desktop por completo (ícone perto do relógio, botão direito, Sair) e pressione Enter"
  }

  Etapa "1. Trabalho que ainda não está no GitHub"
  $pendentes = @()
  if ((Test-Path $PASTA) -and (Existe "git")) {
    Get-ChildItem $PASTA -Directory | ForEach-Object {
      if (Test-Path (Join-Path $_.FullName ".git")) {
        $alteracoes = git -C $_.FullName status --porcelain 2>$null
        $semEnviar = git -C $_.FullName log --branches --not --remotes --oneline 2>$null
        if ($alteracoes -or $semEnviar) { $pendentes += $_.Name }
      }
    }
  }
  if ($pendentes.Count -gt 0) {
    Aviso "há trabalho que não foi guardado no GitHub em: $($pendentes -join ', ')."
    Write-Host "  Peça ao Claude do usuário, nessa pasta, para guardar o progresso antes de limpar."
    if ((Read-Host "  Para apagar mesmo assim, digite APAGAR") -ne "APAGAR") { Write-Host "Nada foi feito."; return }
  } else { Ok "nenhum trabalho pendente" }

  Etapa "2. Login do GitHub"
  if (Existe "gh") {
    for ($i = 0; $i -lt 5; $i++) {
      $login = "$(gh api user -q .login 2>$null)".Trim()
      if ($LASTEXITCODE -ne 0 -or -not $login) { break }
      gh auth logout --hostname github.com --user $login 2>$null | Out-Null
      Ok "saiu da conta $login"
    }
  }
  $alvos = @(cmdkey /list | Select-String -Pattern "(LegacyGeneric:target=)?(git:https://[^\s]*github\.com[^\s]*)" -AllMatches |
    ForEach-Object { $_.Matches } | ForEach-Object { $_.Value } | Sort-Object -Unique)
  foreach ($alvo in $alvos) { cmdkey "/delete:$alvo" | Out-Null; Ok "conta guardada no Windows removida ($alvo)" }
  [Environment]::SetEnvironmentVariable("NODE_AUTH_TOKEN", $null, "User")
  $env:NODE_AUTH_TOKEN = $null
  Ok "token dos pacotes removido"
  Remove-Item -Recurse -Force (Join-Path $env:APPDATA "GitHub CLI") -ErrorAction SilentlyContinue

  Etapa "3. Configurações do Git"
  if (Existe "git") {
    foreach ($chave in @("user.name", "user.email", "core.autocrlf", "core.longpaths")) { git config --global --unset-all $chave 2>$null }
    git config --global --remove-section credential.https://github.com 2>$null
    Ok "configurações removidas"
  }

  Etapa "4. Pasta dos módulos"
  if (Test-Path $PASTA) {
    try { Remove-Item -Recurse -Force $PASTA -ErrorAction Stop; Ok "pasta apagada" }
    catch { Falha "a pasta está em uso. Feche o Claude Desktop, o Explorador de Arquivos e os terminais nessa pasta, e rode de novo." }
  } else { Ok "pasta já não existia" }

  Etapa "5. pnpm e npm"
  if (Existe "npm") {
    npm uninstall -g pnpm --loglevel=error 2>$null | Out-Null
    npm config delete update-notifier 2>$null
  }
  foreach ($p in @((Join-Path $env:LOCALAPPDATA "pnpm"), (Join-Path $env:LOCALAPPDATA "pnpm-cache"), (Join-Path $env:APPDATA "npm"), (Join-Path $env:APPDATA "npm-cache"))) {
    Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue
  }
  $npmGlobal = Join-Path $env:APPDATA "npm"
  $pathUsuario = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($pathUsuario) {
    $novo = (($pathUsuario -split ";") | Where-Object { $_ -and $_ -ne $npmGlobal }) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $novo, "User")
  }
  try { Set-ExecutionPolicy -Scope CurrentUser Undefined -Force -ErrorAction Stop } catch { }
  Ok "pnpm e configurações do npm removidos"

  Etapa "6. Proteção do Claude Desktop"
  if (Test-Path $MANAGED) {
    Write-Host "  o Windows vai pedir a senha de administrador..."
    $comando = "Remove-Item -Force '$MANAGED'; if (-not (Get-ChildItem 'C:\Program Files\ClaudeCode' -ErrorAction SilentlyContinue)) { Remove-Item -Force 'C:\Program Files\ClaudeCode' -ErrorAction SilentlyContinue }"
    $codificado = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($comando))
    try { Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList "-NoProfile -EncodedCommand $codificado" } catch { }
    if (Test-Path $MANAGED) { Falha "não consegui remover $MANAGED" } else { Ok "removida" }
  } else { Ok "já não existia" }

  Etapa "7. Programas"
  foreach ($p in $PROGRAMAS) {
    if (-not (Existe $p.Comando)) { Ok "$($p.Nome) já não está instalado"; continue }
    if (-not (Existe "winget")) { Falha "o winget não está disponível para desinstalar o $($p.Nome)"; continue }
    Write-Host "  desinstalando $($p.Nome)... (o Windows pode pedir a senha de administrador)"
    winget uninstall --id $p.Id -e --silent --accept-source-agreements | Out-Null
    Atualizar-Path
    if (Existe $p.Comando) { Falha "o $($p.Nome) continua instalado" } else { Ok "$($p.Nome) desinstalado" }
  }

  Write-Host ""
  Write-Host "LIMPEZA CONCLUÍDA. Confira os itens com FALHA acima, se houver." -ForegroundColor Green
  Write-Host "No Claude Desktop, a pasta do módulo some da lista ao ser aberta; se a máquina deixar de ser do usuário, saia da conta dele no app."
}

Limpar-NevoniONE
