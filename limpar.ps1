# Limpeza da máquina do usuário final do Nevoni ONE: desfaz tudo o que o instalar.ps1 fez,
# inclusive os programas (decisão de Fred, 02/10/2026).
#
# Uso: no PowerShell COMUM (não como administrador), na conta do Windows do usuário:
#
#   irm https://raw.githubusercontent.com/NevoniONE/nevoni-one-instalacao/main/limpar.ps1 | iex
#
# Pode rodar de novo quantas vezes precisar: o que já estiver removido é só conferido.
# Antes de apagar a pasta dos módulos, o script confere se há trabalho que ainda não está no GitHub.

function Limpar-NevoniONE {
  $PASTA = Join-Path $env:LOCALAPPDATA "NevoniONE"
  $MANAGED = "C:\Program Files\ClaudeCode\managed-settings.json"
  $PROGRAMAS = @(
    @{ Comando = "gh"; Nome = "GitHub CLI"; Padrao = "^GitHub CLI" },
    @{ Comando = "node"; Nome = "Node.js"; Padrao = "^Node\.js" },
    @{ Comando = "git"; Nome = "Git"; Padrao = "^Git$|^Git version" }
  )

  function Etapa($texto) { Write-Host ""; Write-Host "== $texto ==" -ForegroundColor Cyan }
  function Ok($texto) { Write-Host "  ok     $texto" -ForegroundColor Green }
  function Aviso($texto) { Write-Host "  AVISO  $texto" -ForegroundColor Yellow }
  # Conta as falhas, para a mensagem final não dizer "concluída" quando algo falhou.
  $estado = @{ falhas = 0 }
  function Falha($texto) { $estado.falhas++; Write-Host "  FALHA  $texto" -ForegroundColor Red }
  function Existe($comando) { [bool](Get-Command $comando -ErrorAction SilentlyContinue) }
  function Atualizar-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
  }
  # Roda comandos numa única janela de administrador (uma senha só). Os desinstaladores MSI (Node,
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

  # Confere de verdade: com o Claude Desktop aberto, a pasta dos módulos fica em uso (achado da T1).
  while (Get-Process -Name "Claude" -ErrorAction SilentlyContinue) {
    Read-Host "O Claude Desktop está aberto. Feche-o por completo (ícone perto do relógio, botão direito, Sair) e pressione Enter"
    Start-Sleep -Seconds 3
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
  # Contas guardadas no cofre do Windows: as do Git (git:https://...github.com) e as do próprio
  # GitHub CLI (gh:github.com...), que ficam mesmo quando o logout acima não acontece (sem rede).
  $alvos = @(cmdkey /list | Select-String -Pattern "(LegacyGeneric:target=)?(git:https://[^\s]*github\.com[^\s]*|gh:github\.com[^\s]*)" -AllMatches |
    ForEach-Object { $_.Matches } | ForEach-Object { $_.Value } | Sort-Object -Unique)
  foreach ($alvo in $alvos) {
    cmdkey "/delete:$alvo" | Out-Null
    if ($LASTEXITCODE -eq 0) { Ok "conta guardada no Windows removida ($alvo)" } else { Falha "não consegui remover a conta guardada $alvo" }
  }
  [Environment]::SetEnvironmentVariable("NODE_AUTH_TOKEN", $null, "User")
  $env:NODE_AUTH_TOKEN = $null
  Remove-Item -Recurse -Force (Join-Path $env:APPDATA "GitHub CLI") -ErrorAction SilentlyContinue
  if ((Existe "gh") -and "$(gh api user -q .login 2>$null)".Trim()) { Falha "o GitHub CLI ainda está logado" }
  else { Ok "sem login do GitHub e sem token dos pacotes" }

  Etapa "3. Configurações do Git"
  if (Existe "git") {
    foreach ($chave in @("user.name", "user.email", "core.autocrlf", "core.longpaths")) { git config --global --unset-all $chave 2>$null }
    git config --global --remove-section credential.https://github.com 2>$null
    Ok "configurações removidas"
  } else { Ok "o Git já não está instalado" }

  Etapa "4. Pasta dos módulos"
  if (Test-Path $PASTA) {
    # O node_modules tem caminhos maiores que o limite antigo do Windows (260 caracteres), e o
    # Remove-Item do PowerShell 5.1 não apaga esses arquivos (achado da T1). O "rd" com o prefixo
    # \\?\ aceita caminhos longos.
    $erro = ""
    try { Remove-Item -Recurse -Force $PASTA -ErrorAction Stop } catch { $erro = $_.Exception.Message }
    if (Test-Path $PASTA) { cmd.exe /c "rd /s /q `"\\?\$PASTA`"" 2>$null | Out-Null }
    if (Test-Path $PASTA) {
      Start-Sleep -Seconds 5
      cmd.exe /c "rd /s /q `"\\?\$PASTA`"" 2>$null | Out-Null
    }
    if (-not (Test-Path $PASTA)) { Ok "pasta apagada" }
    else {
      Falha "não consegui apagar $PASTA. Erro: $erro"
      Write-Host "  Se for arquivo em uso: feche o Claude Desktop, o Explorador de Arquivos e os terminais nessa pasta, e rode de novo."
    }
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

  Etapa "6. Proteção do Claude Desktop e programas"
  $comandos = @()
  $removerProtecao = Test-Path $MANAGED
  $desinstalar = @($PROGRAMAS | Where-Object { Existe $_.Comando })
  if ($removerProtecao) {
    Write-Host "  vai remover: proteção do Claude Desktop"
    $comandos += "Tentar 'proteção do Claude Desktop' { Remove-Item -Force '$MANAGED'; if (-not (Get-ChildItem 'C:\Program Files\ClaudeCode' -ErrorAction SilentlyContinue)) { Remove-Item -Force 'C:\Program Files\ClaudeCode' -ErrorAction SilentlyContinue } }"
  } else { Ok "proteção do Claude Desktop já não existia" }
  foreach ($p in $PROGRAMAS) {
    if (Existe $p.Comando) {
      Write-Host "  vai desinstalar: $($p.Nome)"
      $comandos += "Tentar '$($p.Nome)' { Desinstalar '$($p.Padrao)' }"
    } else { Ok "$($p.Nome) já não está instalado" }
  }
  if ($comandos.Count -gt 0) {
    # Mesmo se a senha não for informada, confere e diz o que ficou para trás.
    [void](Como-Administrador $comandos)
    Atualizar-Path
    if ($removerProtecao) {
      if (Test-Path $MANAGED) { Falha "não consegui remover $MANAGED" } else { Ok "proteção do Claude Desktop removida" }
    }
    foreach ($p in $desinstalar) {
      if (Existe $p.Comando) { Falha "o $($p.Nome) continua instalado (registro em $env:PUBLIC\nevoni-one-instalacao.log)" }
      else { Ok "$($p.Nome) desinstalado" }
    }
  }

  Write-Host ""
  if ($estado.falhas -eq 0) { Write-Host "LIMPEZA CONCLUÍDA." -ForegroundColor Green }
  else { Write-Host "LIMPEZA INCOMPLETA: $($estado.falhas) item(ns) com FALHA acima. Rode de novo; se continuar, mande o print para a one@." -ForegroundColor Red }
  Write-Host "No Claude Desktop, a pasta do módulo some da lista ao ser aberta; se a máquina deixar de ser do usuário, saia da conta dele no app."
}

Limpar-NevoniONE
