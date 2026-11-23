#!/bin/bash
# Instalação do Mac do usuário final do Nevoni ONE (o equivalente do instalar.ps1, do Windows).
#
# Uso: no Terminal, na conta do Mac do usuário (sem sudo), com o usuário presente para o login do GitHub:
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/NevoniONE/nevoni-one-instalacao/main/instalar.sh)"
#
# Pode rodar de novo quantas vezes precisar: o que já estiver feito é só conferido.
# Só a conferência final, sem mudar nada:
#
#   NEVONI_MODO=conferir /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/NevoniONE/nevoni-one-instalacao/main/instalar.sh)"
#
# Este arquivo não contém nenhum segredo: o login e o token são do próprio usuário, feitos na hora.
# Roteiro completo da TI: docs/ROTEIRO_INSTALACAO_USUARIO_FINAL.md, no repositório do núcleo.
#
# Escrito para o bash 3.2 que vem no macOS: sem jq e sem python (no Mac sem as ferramentas da Apple,
# o python3 e o git são só atalhos que abrem uma janela de instalação).

ORG="NevoniONE"
PNPM_VERSAO="9.12.0"
PASTA="$HOME/NevoniONE"
MANAGED_DIR="/Library/Application Support/ClaudeCode"
MANAGED="$MANAGED_DIR/managed-settings.json"
MANAGED_CONTEUDO='{ "disableAutoMode": "disable", "permissions": { "disableBypassPermissionsMode": "disable" } }'
CLAUDE_APP="/Applications/Claude.app"
# Claude Desktop já instalado só para esta conta (arrastado para a pasta Aplicativos do usuário).
if [ ! -d "$CLAUDE_APP" ] && [ -d "$HOME/Applications/Claude.app" ]; then CLAUDE_APP="$HOME/Applications/Claude.app"; fi
CLAUDE_ASSINATURA="Developer ID Application: Anthropic, PBC ("
AGENTE_ID="br.com.nevoni.one.token"
AGENTE="$HOME/Library/LaunchAgents/$AGENTE_ID.plist"
LOG="/Users/Shared/nevoni-one-instalacao.log"
BLOCO_INICIO="# >>> Nevoni ONE (instalar.sh) >>>"
BLOCO_FIM="# <<< Nevoni ONE <<<"
# Arquivos que o Terminal (e a aba Code do Claude) leem ao abrir: os do zsh, padrão do macOS, e os
# do bash quando a conta ainda usa o bash (contas antigas; achado no Mac do Victor, 23/11/2026).
# No bash, o arquivo de login é o primeiro que existir (o bash só lê um); sem nenhum, o .bash_profile.
arquivos_shell() {
  local f
  echo "$HOME/.zprofile"
  echo "$HOME/.zshrc"
  case "$SHELL" in
    */bash)
      echo "$HOME/.bashrc"
      for f in .bash_profile .bash_login .profile; do
        if [ -f "$HOME/$f" ]; then echo "$HOME/$f"; return 0; fi
      done
      echo "$HOME/.bash_profile"
      ;;
  esac
}

# /usr/local/bin primeiro: é onde os instaladores oficiais do Node e do GitHub CLI colocam os comandos.
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

etapa() { printf '\n\033[36m== %s ==\033[0m\n' "$1"; }
ok() { printf '  \033[32mok\033[0m     %s\n' "$1"; }
aviso() { printf '  \033[33mAVISO\033[0m  %s\n' "$1"; }
falha() { printf '  \033[31mFALHA\033[0m  %s\n' "$1"; }
existe() { command -v "$1" >/dev/null 2>&1; }
# Lê do teclado mesmo quando o script chega pelo curl.
perguntar() { local r; read -r -p "  $1 " r </dev/tty; printf '%s' "$r"; }

# O /usr/bin/git existe em todo Mac, mas sem as ferramentas de linha de comando da Apple ele só abre
# a janela de instalação: o Git só conta como instalado com elas (ou com outro git no caminho).
tem_git() {
  local g
  g="$(command -v git 2>/dev/null)" || return 1
  if [ "$g" = "/usr/bin/git" ]; then xcode-select -p >/dev/null 2>&1 || return 1; fi
  git --version >/dev/null 2>&1
}
tem_programa() {
  case "$1" in
    git) tem_git ;;
    *) existe "$1" ;;
  esac
}
PROG_COMANDOS="git node gh"
nome_programa() {
  case "$1" in
    git) echo "Git (ferramentas de linha de comando da Apple)" ;;
    node) echo "Node.js" ;;
    gh) echo "GitHub CLI" ;;
  esac
}
funcao_programa() {
  case "$1" in
    git) echo "instalar_git" ;;
    node) echo "instalar_node" ;;
    gh) echo "instalar_gh" ;;
  esac
}
versao_pnpm() { if existe pnpm; then pnpm --version 2>/dev/null | tr -d '[:space:]'; fi; }
protecao_gravada() { [ -f "$MANAGED" ] && [ "$(cat "$MANAGED" 2>/dev/null)" = "$MANAGED_CONTEUDO" ]; }
claude_assinado() {
  [ -d "$CLAUDE_APP" ] || return 1
  codesign --verify --deep --strict "$CLAUDE_APP" >/dev/null 2>&1 || return 1
  codesign -dvv "$CLAUDE_APP" 2>&1 | grep -q "^Authority=$CLAUDE_ASSINATURA"
}
usuario_eh_administrador() { id -Gn | tr ' ' '\n' | grep -qx admin; }
conta_github() {
  existe gh || return 0
  gh api user -q .login 2>/dev/null | tr -d '[:space:]'
}
repositorios() {
  gh repo list "$ORG" --limit 100 --json name -q '.[].name' 2>/dev/null | grep '^nevoni-one-modulo-'
}
bloco_no_shell() { grep -qF "$BLOCO_INICIO" "$1" 2>/dev/null; }

# Roda os comandos como administrador, com UM pedido de senha do macOS (a janela aceita a conta de
# qualquer administrador do Mac, como o pedido de senha do Windows). Os instaladores vêm direto das
# fontes oficiais, com o hash SHA-256 conferido; o Claude Desktop, com a assinatura da Anthropic.
como_administrador() {
  local script
  script="$(mktemp /tmp/nevoni-one-instalacao.XXXXXX)" || { falha "não consegui criar o arquivo temporário"; return 1; }
  {
    printf 'MANAGED_DIR=%q\nMANAGED=%q\nMANAGED_CONTEUDO=%q\nPNPM_VERSAO=%q\nCLAUDE_APP=%q\nCLAUDE_ASSINATURA=%q\n' \
      "$MANAGED_DIR" "$MANAGED" "$MANAGED_CONTEUDO" "$PNPM_VERSAO" "$CLAUDE_APP" "$CLAUDE_ASSINATURA"
    cat <<'FUNCOES'
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# A pasta pessoal do administrador: sem isso, o npm rodando como administrador gravaria arquivos
# dele na pasta do usuário, e o npm do usuário daria erro de permissão depois.
export HOME=/var/root
TEMP_DIR="$(mktemp -d /tmp/nevoni-one-instalacao-arquivos.XXXXXX)"
trap 'hdiutil detach "$TEMP_DIR/montagem" -quiet >/dev/null 2>&1; rm -rf "$TEMP_DIR"' EXIT
echo "início: $(date)"
baixar() { # url nome sha256
  local destino="$TEMP_DIR/$2" h
  echo "baixando $1"
  curl -fsSL --retry 3 -o "$destino" "$1" || { echo "não consegui baixar $2"; return 1; }
  [ -n "$3" ] || { echo "sem hash para conferir $2"; return 1; }
  h="$(shasum -a 256 "$destino" | awk '{print $1}')"
  [ "$h" = "$3" ] || { echo "o hash de $2 não confere"; return 1; }
  echo "hash conferido: $2"
}
instalar_pkg() { installer -pkg "$TEMP_DIR/$1" -target / ; }
# Ferramentas de linha de comando da Apple (trazem o Git), pelo mesmo caminho do instalador do Homebrew.
instalar_git() {
  local marca="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress" rotulo
  touch "$marca"
  rotulo="$(softwareupdate -l 2>/dev/null | grep -B 1 -E 'Command Line Tools' | awk -F'*' '/^ *\*/ {print $2}' | sed -e 's/^ *Label: //' -e 's/^ *//' | sort -V | tail -n 1)"
  if [ -z "$rotulo" ]; then rm -f "$marca"; echo "a atualização de software não ofereceu as ferramentas de linha de comando"; return 1; fi
  echo "instalando: $rotulo (pode levar alguns minutos)"
  softwareupdate -i "$rotulo" --verbose
  rm -f "$marca"
  xcode-select --switch /Library/Developer/CommandLineTools
  xcode-select -p >/dev/null 2>&1
}
instalar_node() {
  local versao nome sha
  versao="$(curl -fsSL https://nodejs.org/dist/index.tab | awk -F'\t' 'NR > 1 && $10 != "-" && v == "" { v = $1 } END { print v }')"
  [ -n "$versao" ] || { echo "não achei a versão LTS do Node"; return 1; }
  nome="node-$versao.pkg"
  sha="$(curl -fsSL "https://nodejs.org/dist/$versao/SHASUMS256.txt" | awk -v n="$nome" '$2 == n { print $1 }')"
  baixar "https://nodejs.org/dist/$versao/$nome" "$nome" "$sha" && instalar_pkg "$nome"
}
instalar_gh() {
  local tag versao nome sha
  tag="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest)"
  tag="${tag##*/}"
  versao="${tag#v}"
  [ -n "$versao" ] || { echo "não achei a versão do GitHub CLI"; return 1; }
  nome="gh_${versao}_macOS_universal.pkg"
  sha="$(curl -fsSL "https://github.com/cli/cli/releases/download/$tag/gh_${versao}_checksums.txt" | awk -v n="$nome" '$2 == n { print $1 }')"
  baixar "https://github.com/cli/cli/releases/download/$tag/$nome" "$nome" "$sha" && instalar_pkg "$nome"
}
# Só quando o Node é o do instalador oficial (/usr/local): o pnpm vai para /usr/local/bin, que está no
# caminho de todo programa do Mac, inclusive do Claude Desktop.
instalar_pnpm() { /usr/local/bin/npm install -g "pnpm@$PNPM_VERSAO" --no-fund --no-audit --loglevel=error; }
gravar_protecao() {
  mkdir -p "$MANAGED_DIR" && printf '%s' "$MANAGED_CONTEUDO" > "$MANAGED" && chown root:wheel "$MANAGED" && chmod 644 "$MANAGED"
}
# Claude Desktop: imagem .dmg oficial da Anthropic (a mesma para chip Apple e Intel). Sem hash
# publicado: confere a assinatura digital (Anthropic, PBC) e a aprovação da Apple (Gatekeeper).
instalar_claude() {
  local dmg="$TEMP_DIR/Claude.dmg" app
  echo "baixando o Claude Desktop (cerca de 300 MB)"
  curl -fsSL --retry 3 -o "$dmg" "https://claude.ai/api/desktop/darwin/universal/dmg/latest/redirect" || return 1
  hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$TEMP_DIR/montagem" -quiet || return 1
  app="$(find "$TEMP_DIR/montagem" -maxdepth 1 -name '*.app' | head -n 1)"
  [ -n "$app" ] || { echo "não achei o aplicativo dentro da imagem do Claude Desktop"; return 1; }
  codesign --verify --deep --strict "$app" || { echo "a assinatura do Claude Desktop não confere"; return 1; }
  codesign -dvv "$app" 2>&1 | grep -q "^Authority=$CLAUDE_ASSINATURA" || { echo "o Claude Desktop não está assinado pela Anthropic"; return 1; }
  spctl --assess --type execute "$app" || { echo "o Gatekeeper não aprovou o Claude Desktop"; return 1; }
  echo "assinatura da Anthropic conferida"
  rm -rf "$CLAUDE_APP" && ditto "$app" "$CLAUDE_APP"
}
tentar() {
  local rotulo="$1"; shift
  if "$@"; then echo "OK: $rotulo"; else echo "ERRO em $rotulo"; fi
}
FUNCOES
    printf '%s\n' "$@"
    echo 'echo "fim: $(date)"'
  } >"$script"
  rm -f "$LOG"
  echo "  o macOS vai pedir a senha de um administrador do Mac (uma vez só); o andamento aparece abaixo..."
  : >"$LOG" 2>/dev/null
  tail -n +1 -F "$LOG" 2>/dev/null &
  local espiao=$!
  local resultado=0
  /usr/bin/osascript -e "do shell script \"/bin/bash '$script' > '$LOG' 2>&1\" with administrator privileges" >/dev/null 2>&1 || resultado=1
  sleep 1
  kill "$espiao" >/dev/null 2>&1
  wait "$espiao" 2>/dev/null
  rm -f "$script"
  if [ "$resultado" -ne 0 ]; then falha "a senha de administrador não foi informada (ou a janela foi cancelada)"; return 1; fi
  return 0
}

conferir() {
  local guiar="$1" falhas=0 c v conta status helper email nome repos r caminho arq
  etapa "Conferência final"
  if claude_assinado; then ok "Claude Desktop instalado em $CLAUDE_APP (assinatura da Anthropic)"
  elif [ -d "$CLAUDE_APP" ]; then falha "o Claude Desktop em $CLAUDE_APP não passou na conferência da assinatura da Anthropic"; falhas=$((falhas + 1))
  else falha "Claude Desktop não está instalado em $CLAUDE_APP"; falhas=$((falhas + 1)); fi
  for c in $PROG_COMANDOS; do
    if tem_programa "$c"; then ok "$(nome_programa "$c") instalado"; else falha "$(nome_programa "$c") não está instalado"; falhas=$((falhas + 1)); fi
  done
  v="$(versao_pnpm)"
  if [ "$v" = "$PNPM_VERSAO" ]; then ok "pnpm $PNPM_VERSAO"; else falha "pnpm deveria ser $PNPM_VERSAO (está '$v')"; falhas=$((falhas + 1)); fi

  conta="$(conta_github)"
  if [ -z "$conta" ]; then falha "GitHub CLI sem login"; falhas=$((falhas + 1))
  elif [ "$conta" = "$ORG" ]; then falha "o GitHub está logado com a conta da TI ($ORG). Use a conta do usuário"; falhas=$((falhas + 1))
  else
    ok "GitHub logado como $conta"
    status="$(gh auth status 2>&1)"
    if printf '%s' "$status" | grep -q "read:packages"; then ok "token com read:packages"; else falha "token sem read:packages"; falhas=$((falhas + 1)); fi
  fi

  # Sem o Git, nem chama o git: no Mac sem as ferramentas da Apple, ele abriria a janela de instalação.
  if tem_git; then
    helper="$(git config --global --get-all credential.https://github.com.helper 2>/dev/null)"
    if printf '%s' "$helper" | grep -q "auth git-credential"; then ok "o Git usa o login do GitHub CLI"; else falha "o Git não usa o login do GitHub CLI"; falhas=$((falhas + 1)); fi
    email="$(git config --global user.email 2>/dev/null)"
    case "$email" in
      *@users.noreply.github.com) ok "e-mail privado do GitHub: $email" ;;
      *) falha "e-mail do Git não é o privado do GitHub ('$email')"; falhas=$((falhas + 1)) ;;
    esac
    nome="$(git config --global user.name 2>/dev/null)"
    if [ -n "$nome" ]; then ok "nome nos envios: $nome"; else falha "nome do Git em branco"; falhas=$((falhas + 1)); fi
    if [ "$(git config --global core.autocrlf 2>/dev/null)" = "false" ]; then ok "quebras de linha pelo repositório"; else falha "core.autocrlf deveria ser false"; falhas=$((falhas + 1)); fi
  else
    falha "sem o Git, as configurações do Git não foram conferidas"; falhas=$((falhas + 1))
  fi

  # O token dos pacotes chega por dois caminhos: o Terminal (bloco nos arquivos do zsh e do bash, que lê o
  # token do login do gh na hora) e os aplicativos abertos pelo Dock (agente de login).
  for arq in $(arquivos_shell); do
    if bloco_no_shell "$arq"; then ok "token dos pacotes no Terminal ($arq)"; else falha "falta o bloco do Nevoni ONE em $arq"; falhas=$((falhas + 1)); fi
  done
  if [ -f "$AGENTE" ] && [ -n "$(launchctl getenv NODE_AUTH_TOKEN 2>/dev/null)" ]; then ok "token dos pacotes para os aplicativos (agente de login)"
  else falha "o token dos pacotes não chega aos aplicativos ($AGENTE)"; falhas=$((falhas + 1)); fi

  if protecao_gravada && [ "$(stat -f %Su "$MANAGED" 2>/dev/null)" = "root" ]; then ok "proteção do Claude Desktop gravada"
  else falha "proteção do Claude Desktop ausente ou com erro ($MANAGED)"; falhas=$((falhas + 1)); fi

  repos=""
  if [ -n "$conta" ] && [ "$conta" != "$ORG" ]; then repos="$(repositorios)"; fi
  if [ -z "$repos" ]; then falha "nenhum repositório de módulo acessível para a conta do usuário (convite do passo 2?)"; falhas=$((falhas + 1)); fi
  for r in $repos; do
    caminho="$PASTA/$r"
    if [ -d "$caminho/.git" ] && [ -d "$caminho/node_modules" ]; then ok "módulo $r em $caminho"
    else falha "módulo $r não está copiado e instalado em $caminho"; falhas=$((falhas + 1)); fi
  done

  if usuario_eh_administrador; then aviso "a conta do Mac do usuário é de administrador. O roteiro pede uma conta sem esse direito"; fi

  echo ""
  if [ "$falhas" -eq 0 ]; then
    printf '\033[32mMÁQUINA PRONTA.\033[0m\n'
    if [ "$guiar" = "guiar" ]; then
      # O que só existe na tela do aplicativo: o script abre o Claude Desktop e mostra o que fazer.
      while pgrep -x Claude >/dev/null 2>&1; do
        perguntar "O Claude Desktop está aberto. Feche-o por completo (no menu Claude, Sair, ou Cmd+Q) e pressione Enter" >/dev/null
        sleep 3
      done
      # Copia a pasta dos módulos, com a barra no fim, como no Windows: na janela de escolher pasta
      # aparecem as pastas de todos os módulos da pessoa, e ela clica na que quer.
      printf '%s/' "$PASTA" | pbcopy 2>/dev/null
      open "$CLAUDE_APP"
      echo ""
      echo "O Claude Desktop foi aberto. Com o usuário presente:"
      echo "  1. Entrar com a conta @nevoni.com.br do usuário."
      echo "  2. Aba Code, botão de escolher pasta (ao lado de 'Local'). Na janela, apertar Cmd+Shift+G,"
      echo "     colar (Cmd+V) o caminho da pasta dos módulos, que já está copiado, e apertar Enter. Clicar"
      echo "     UMA vez na pasta do módulo e só então em 'Abrir'. Se o Cmd+V não colar, digite ~/NevoniONE/"
      echo "     Pastas dos módulos deste usuário:"
      for r in $repos; do echo "       $PASTA/$r"; done
      echo "  3. 'Confiar no workspace', modo 'Aceitar edições' e a caixa 'worktree' desmarcada."
      echo "  4. Se perguntar onde abrir os links: o navegador padrão do Mac."
      echo "  5. Oriente o usuário a não usar o botão 'Criar PR': o envio para aprovação é pedido ao Claude."
      echo "  6. Conversa nova: o usuário digita 'Bom dia!' e confere o passo 5 do roteiro."
    fi
  else
    printf '\033[31mA MÁQUINA AINDA NÃO ESTÁ PRONTA: %s item(ns) com FALHA acima.\033[0m\n' "$falhas"
    echo "Rode o script de novo. Se a falha continuar, mande o print para a TI."
  fi
}

instalar_nevoni_one() {
  local c comandos vai_pnpm_admin node_local conta resposta token id email nome aviso repos r caminho antigo
  printf '\033[36mInstalação do Mac do usuário final do Nevoni ONE\033[0m\n'

  if [ "$(uname -s)" != "Darwin" ]; then falha "este script é para o Mac. No Windows, use o instalar.ps1."; return 1; fi
  if [ "$(id -u)" -eq 0 ]; then falha "o script está rodando como administrador (sudo). Rode sem sudo, na conta do usuário."; return 1; fi
  local versao_macos chip
  versao_macos="$(sw_vers -productVersion 2>/dev/null)"
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then chip="Apple"; else chip="Intel"; fi
  echo "  macOS $versao_macos, chip $chip"
  if [ "${versao_macos%%.*}" -lt 13 ] 2>/dev/null; then
    aviso "macOS anterior ao 13 (Ventura): o Node e o Claude Desktop podem recusar a instalação. Atualize o macOS antes."
  fi

  if [ "$NEVONI_MODO" = "conferir" ]; then conferir ""; return 0; fi

  etapa "1. Programas, proteção do Claude Desktop e Claude Desktop"
  comandos=()
  for c in $PROG_COMANDOS; do
    if tem_programa "$c"; then ok "$(nome_programa "$c") já instalado"
    else
      echo "  vai instalar: $(nome_programa "$c")"
      comandos+=("tentar '$(nome_programa "$c")' $(funcao_programa "$c")")
    fi
  done
  # O pnpm entra na mesma senha quando o Node é (ou vai ser) o do instalador oficial, em /usr/local.
  node_local=0
  if ! existe node || [ "$(command -v node)" = "/usr/local/bin/node" ]; then node_local=1; fi
  vai_pnpm_admin=0
  if [ "$(versao_pnpm)" = "$PNPM_VERSAO" ]; then ok "pnpm $PNPM_VERSAO já instalado"
  elif [ "$node_local" -eq 1 ]; then
    echo "  vai instalar: pnpm $PNPM_VERSAO"
    comandos+=("tentar 'pnpm $PNPM_VERSAO' instalar_pnpm")
    vai_pnpm_admin=1
  fi
  if protecao_gravada; then ok "proteção do Claude Desktop já gravada"
  else
    echo "  vai gravar: proteção do Claude Desktop"
    comandos+=("tentar 'proteção do Claude Desktop' gravar_protecao")
  fi
  if claude_assinado; then ok "Claude Desktop já instalado"
  else
    if [ -d "$CLAUDE_APP" ]; then echo "  vai reinstalar: Claude Desktop (o atual não passou na conferência da assinatura)"
    else echo "  vai instalar: Claude Desktop"; fi
    comandos+=("tentar 'Claude Desktop' instalar_claude")
    # O aplicativo não pode ser trocado com ele aberto.
    while pgrep -x Claude >/dev/null 2>&1; do
      perguntar "O Claude Desktop está aberto. Feche-o por completo (no menu Claude, Sair, ou Cmd+Q) e pressione Enter" >/dev/null
      sleep 3
    done
  fi
  if [ "${#comandos[@]}" -gt 0 ]; then
    como_administrador "${comandos[@]}" || return 1
    local faltou=0
    for c in $PROG_COMANDOS; do
      if tem_programa "$c"; then ok "$(nome_programa "$c") instalado"; else falha "não consegui instalar o $(nome_programa "$c")"; faltou=1; fi
    done
    if [ "$vai_pnpm_admin" -eq 1 ]; then
      if [ "$(versao_pnpm)" = "$PNPM_VERSAO" ]; then ok "pnpm $PNPM_VERSAO instalado"; else falha "não consegui instalar o pnpm $PNPM_VERSAO"; faltou=1; fi
    fi
    if protecao_gravada; then ok "proteção do Claude Desktop gravada"; else falha "não consegui gravar $MANAGED com o conteúdo certo"; faltou=1; fi
    if claude_assinado; then ok "Claude Desktop instalado (assinatura da Anthropic conferida)"; else falha "não consegui instalar o Claude Desktop"; faltou=1; fi
    if [ "$faltou" -eq 1 ]; then echo "  O registro da parte de administrador está em $LOG. Mande para a TI."; return 1; fi
  fi

  etapa "2. Ajustes na conta do usuário"
  # O aviso do npm é desligado antes de usar o npm, para não aparecer já na instalação.
  npm config set update-notifier false >/dev/null 2>&1
  if [ "$(versao_pnpm)" != "$PNPM_VERSAO" ]; then
    # Node de outra origem (por exemplo, Homebrew): o pnpm vai para a pasta global desse Node, que é do usuário.
    npm install -g "pnpm@$PNPM_VERSAO" --no-fund --no-audit --loglevel=error
    hash -r
    if [ "$(versao_pnpm)" = "$PNPM_VERSAO" ]; then ok "pnpm $PNPM_VERSAO instalado"
    else falha "não consegui instalar o pnpm $PNPM_VERSAO (está '$(versao_pnpm)'). Rode o script de novo."; return 1; fi
  fi
  pnpm config set update-notifier false >/dev/null 2>&1
  ok "avisos de atualização do npm e do pnpm desligados (ninguém atualiza por engano)"

  etapa "3. Login do GitHub (com o usuário presente)"
  conta="$(conta_github)"
  if [ "$conta" = "$ORG" ]; then
    falha "o GitHub está logado com a conta da TI ($ORG). Ela nunca é usada na máquina do usuário. Saindo dela..."
    gh auth logout --hostname github.com --user "$ORG"
    conta=""
  fi
  if [ -n "$conta" ]; then
    resposta="$(perguntar "O GitHub está logado como '$conta'. É a conta do usuário? (S/N)")"
    case "$resposta" in
      [sS]*) ;;
      *) gh auth logout --hostname github.com --user "$conta"; conta="" ;;
    esac
  fi
  if [ -z "$conta" ]; then
    echo "  Vai aparecer um código de 8 caracteres. Pressione Enter para abrir o navegador,"
    echo "  confira que o GitHub está na conta DO USUÁRIO, cole o código e autorize."
    echo "  Se perguntar 'Authenticate Git with your GitHub credentials?', responda Y."
    gh auth login --hostname github.com --git-protocol https --web --scopes read:packages </dev/tty
    conta="$(conta_github)"
    if [ -z "$conta" ]; then falha "o login do GitHub não foi concluído. Rode o script de novo."; return 1; fi
  fi
  if ! gh auth status 2>&1 | grep -q "read:packages"; then
    echo "  falta a permissão de ler os pacotes; o navegador vai abrir de novo para autorizar."
    gh auth refresh --hostname github.com --scopes read:packages </dev/tty
    if ! gh auth status 2>&1 | grep -q "read:packages"; then falha "o token continua sem permissão de ler os pacotes. Rode o script de novo."; return 1; fi
  fi
  gh auth setup-git
  if ! git config --global --get-all credential.https://github.com.helper 2>/dev/null | grep -q "auth git-credential"; then
    falha "não consegui ligar o Git ao login do GitHub CLI (gh auth setup-git). Rode o script de novo."; return 1
  fi
  ok "GitHub logado como $conta, e o Git usa esse login"

  etapa "4. Identificação nos envios"
  id="$(gh api user -q .id | tr -d '[:space:]')"
  email="$id+$conta@users.noreply.github.com"
  nome="$(git config --global user.name 2>/dev/null)"
  if [ -z "$nome" ]; then nome="$(gh api user -q .name 2>/dev/null)"; fi
  if [ -z "$nome" ]; then nome="$(perguntar "Nome completo do usuário, como deve aparecer nos envios:")"; fi
  git config --global user.name "$nome"
  git config --global user.email "$email"
  git config --global core.autocrlf false
  ok "nome '$nome' e e-mail privado $email"
  echo "  (no GitHub do usuário, Settings > Emails, as opções 'Keep my email addresses private' e"
  echo "   'Block command line pushes that expose my email' devem estar marcadas: passo 1 do roteiro)"

  etapa "5. Token de leitura dos pacotes da empresa"
  # O token não fica escrito em arquivo nenhum: é lido na hora do login do gh, que o guarda nas
  # Chaves do macOS. Terminal: bloco nos arquivos do zsh (e do bash, se a conta usa o bash). Aplicativos abertos pelo Dock (o
  # Claude Desktop): um agente de login que repassa o token ao abrir a sessão do Mac.
  for arq in $(arquivos_shell); do
    if bloco_no_shell "$arq"; then ok "bloco já presente em $arq"
    else
      {
        echo ""
        echo "$BLOCO_INICIO"
        echo "# Token de leitura dos pacotes da empresa: é o do login do GitHub CLI, lido na hora."
        echo 'if [ -z "${NODE_AUTH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then'
        echo '  export NODE_AUTH_TOKEN="$(gh auth token 2>/dev/null)"'
        echo 'fi'
        echo "$BLOCO_FIM"
      } >>"$arq"
      ok "bloco gravado em $arq"
    fi
  done
  mkdir -p "$HOME/Library/LaunchAgents"
  cat >"$AGENTE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$AGENTE_ID</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>launchctl setenv NODE_AUTH_TOKEN "\$(gh auth token 2>/dev/null)"</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)" "$AGENTE" >/dev/null 2>&1
  launchctl bootstrap "gui/$(id -u)" "$AGENTE" >/dev/null 2>&1
  token="$(gh auth token 2>/dev/null)"
  launchctl setenv NODE_AUTH_TOKEN "$token"
  export NODE_AUTH_TOKEN="$token"
  ok "token ligado no Terminal e nos aplicativos (é o mesmo do login do GitHub e não expira)"

  etapa "6. Módulos do usuário"
  mkdir -p "$PASTA"
  # Proteção: se a pessoa selecionar a pasta dos módulos em vez da de um módulo, o Claude avisa
  # logo na primeira conversa, em vez de trabalhar fora do módulo.
  cat >"$PASTA/CLAUDE.md" <<'AVISO'
# Esta não é a pasta de um módulo

Esta é a pasta que guarda os módulos do Nevoni ONE desta pessoa. Não trabalhe aqui: não crie,
não altere e não apague nada nesta pasta.

Na primeira resposta, em português, diga ao usuário que a pasta escolhida no Claude Desktop
está errada: ele deve clicar de novo no botão de escolher pasta (ao lado de 'Local'), entrar
nesta pasta e clicar UMA vez na pasta do módulo (as que começam com nevoni-one-modulo-) antes de
'Abrir'. Liste as pastas de módulo que existem aqui e não faça mais nada.
AVISO
  repos="$(repositorios)"
  if [ -z "$repos" ]; then falha "a conta $conta não tem acesso a nenhum repositório de módulo. Confira o convite (passo 2 do roteiro)."; return 1; fi
  for r in $repos; do
    caminho="$PASTA/$r"
    if [ -d "$caminho/.git" ]; then ok "$r já copiado"
    else
      if ! gh repo clone "$ORG/$r" "$caminho"; then falha "não consegui copiar $r"; continue; fi
      ok "$r copiado"
    fi
    # Sem pergunta escondida: uma instalação anterior pela metade fazia o pnpm perguntar se podia
    # apagar e refazer as bibliotecas, e o script ficava parado (05/10/2026, no Windows).
    if (cd "$caminho" && pnpm install --reporter=silent --config.confirmModulesPurge=false); then ok "$r com os pacotes instalados"
    else falha "pnpm install falhou em $r (erro 401/403: falta liberar a leitura dos pacotes para a conta $conta)"; fi
  done
  for antigo in "$HOME/Desktop" "$HOME/Documents"; do
    find "$antigo" -maxdepth 3 -type d -name 'nevoni*modulo-*' 2>/dev/null | while read -r d; do
      aviso "cópia antiga fora do lugar padrão: $d. Apague-a, com o Claude Desktop fechado."
    done
  done

  conferir "guiar"
}

instalar_nevoni_one
