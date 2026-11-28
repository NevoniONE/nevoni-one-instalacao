#!/bin/bash
# Limpeza do Mac do usuário final do Nevoni ONE: desfaz tudo o que o instalar.sh fez, inclusive os
# programas (o equivalente do limpar.ps1, do Windows).
#
# Uso: no Terminal, na conta do Mac do usuário (sem sudo):
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/NevoniONE/nevoni-one-instalacao/main/limpar.sh)"
#
# Pode rodar de novo quantas vezes precisar: o que já estiver removido é só conferido.
# Antes de apagar a pasta dos módulos, o script confere se há trabalho que ainda não está no GitHub.
# Node.js e GitHub CLI só são desinstalados quando vieram dos instaladores oficiais (.pkg), como o
# instalar.sh faz; os de outra origem (por exemplo, Homebrew) ficam, com um aviso.

PASTA="$HOME/NevoniONE"
MANAGED_DIR="/Library/Application Support/ClaudeCode"
MANAGED="$MANAGED_DIR/managed-settings.json"
CLAUDE_APP="/Applications/Claude.app"
AGENTE_ID="br.com.nevoni.one.token"
AGENTE="$HOME/Library/LaunchAgents/$AGENTE_ID.plist"
LOG="/Users/Shared/nevoni-one-instalacao.log"
BLOCO_INICIO="# >>> Nevoni ONE (instalar.sh) >>>"
BLOCO_FIM="# <<< Nevoni ONE <<<"
ARQUIVOS_SHELL="$HOME/.zprofile $HOME/.zshrc $HOME/.bashrc $HOME/.bash_profile $HOME/.bash_login $HOME/.profile"
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

FALHAS=0
etapa() { printf '\n\033[36m== %s ==\033[0m\n' "$1"; }
ok() { printf '  \033[32mok\033[0m     %s\n' "$1"; }
aviso() { printf '  \033[33mAVISO\033[0m  %s\n' "$1"; }
# Conta as falhas, para a mensagem final não dizer "concluída" quando algo falhou.
falha() { FALHAS=$((FALHAS + 1)); printf '  \033[31mFALHA\033[0m  %s\n' "$1"; }
existe() { command -v "$1" >/dev/null 2>&1; }
perguntar() { local r; read -r -p "$1 " r </dev/tty; printf '%s' "$r"; }
tem_git() {
  local g
  g="$(command -v git 2>/dev/null)" || return 1
  if [ "$g" = "/usr/bin/git" ]; then xcode-select -p >/dev/null 2>&1 || return 1; fi
  git --version >/dev/null 2>&1
}
# Pacote (.pkg) que instalou o arquivo, pelo registro do macOS; vazio se veio de outra origem.
pacote_de() { pkgutil --file-info "$1" 2>/dev/null | awk -F': ' '/^pkgid:/ { print $2; exit }'; }

# Uma senha de administrador só (a janela aceita a conta de qualquer administrador do Mac).
como_administrador() {
  local script resultado=0
  script="$(mktemp /tmp/nevoni-one-limpeza.XXXXXX)" || { falha "não consegui criar o arquivo temporário"; return 1; }
  {
    cat <<'FUNCOES'
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOME=/var/root
echo "início: $(date)"
# Apaga os arquivos que o pacote registrou e esquece o registro. As pastas compartilhadas
# (como /usr/local/bin) ficam; as do próprio Node são apagadas à parte.
remover_pacote() {
  local base
  base="$(pkgutil --pkg-info "$1" | awk -F': ' '/^volume:/ { v = $2 } /^location:/ { l = $2 } END { print v "/" l }')"
  pkgutil --only-files --files "$1" | while read -r f; do rm -f "${base%/}/$f"; done
  pkgutil --forget "$1"
}
remover_node() {
  local p
  for p in $(pkgutil --pkgs | grep -E '^org\.nodejs\.'); do remover_pacote "$p"; done
  rm -rf /usr/local/lib/node_modules /usr/local/include/node
  rm -f /usr/local/bin/pnpm /usr/local/bin/pnpx /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack /usr/local/bin/node
}
remover_gh() { remover_pacote "$1"; rm -f /usr/local/bin/gh; }
remover_git() {
  local p
  rm -rf /Library/Developer/CommandLineTools
  for p in $(pkgutil --pkgs | grep -E '^com\.apple\.pkg\.CLTools_'); do pkgutil --forget "$p"; done
  xcode-select --reset
}
remover_protecao() { rm -f "$MANAGED"; rmdir "$MANAGED_DIR" 2>/dev/null; return 0; }
remover_claude() { rm -rf "$CLAUDE_APP"; }
tentar() {
  local rotulo="$1"; shift
  if "$@"; then echo "OK: $rotulo"; else echo "ERRO em $rotulo"; fi
}
FUNCOES
    printf 'MANAGED_DIR=%q\nMANAGED=%q\nCLAUDE_APP=%q\n' "$MANAGED_DIR" "$MANAGED" "$CLAUDE_APP"
    printf '%s\n' "$@"
    echo 'echo "fim: $(date)"'
  } >"$script"
  rm -f "$LOG"
  echo "  o macOS vai pedir a senha de um administrador do Mac (uma vez só)..."
  /usr/bin/osascript -e "do shell script \"/bin/bash '$script' > '$LOG' 2>&1\" with administrator privileges" >/dev/null 2>&1 || resultado=1
  rm -f "$script"
  if [ "$resultado" -ne 0 ]; then falha "a senha de administrador não foi informada (ou a janela foi cancelada)"; return 1; fi
  return 0
}

limpar_nevoni_one() {
  local pendentes d login i arq comandos pkg_node pkg_gh
  printf '\033[36mLimpeza do Mac do usuário final do Nevoni ONE\033[0m\n'
  if [ "$(uname -s)" != "Darwin" ]; then falha "este script é para o Mac. No Windows, use o limpar.ps1."; return 1; fi
  if [ "$(id -u)" -eq 0 ]; then falha "o script está rodando como administrador (sudo). Rode sem sudo, na conta do usuário."; return 1; fi

  echo ""
  echo "Vai ser removido desta conta do Mac:"
  echo "  - o login do GitHub, o token dos pacotes e as contas do GitHub guardadas nas Chaves;"
  echo "  - as configurações do Git feitas na instalação;"
  echo "  - a pasta dos módulos ($PASTA);"
  echo "  - o pnpm e as configurações do npm;"
  echo "  - a proteção do Claude Desktop;"
  echo "  - os programas Git (ferramentas de linha de comando da Apple), Node.js e GitHub CLI;"
  echo "  - o Claude Desktop e os dados dele nesta conta (login, conversas e configurações)."
  if [ "$(perguntar "Para confirmar, digite LIMPAR:")" != "LIMPAR" ]; then echo "Nada foi feito."; return 0; fi

  while pgrep -x Claude >/dev/null 2>&1; do
    perguntar "O Claude Desktop está aberto. Feche-o por completo (no menu Claude, Sair, ou Cmd+Q) e pressione Enter" >/dev/null
    sleep 3
  done

  etapa "1. Trabalho que ainda não está no GitHub"
  pendentes=""
  if [ -d "$PASTA" ] && tem_git; then
    for d in "$PASTA"/*/; do
      [ -d "$d.git" ] || continue
      if [ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ] || [ -n "$(git -C "$d" log --branches --not --remotes --oneline 2>/dev/null)" ]; then
        pendentes="$pendentes $(basename "$d")"
      fi
    done
  fi
  if [ -n "$pendentes" ]; then
    aviso "há trabalho que não foi guardado no GitHub em:$pendentes."
    echo "  Peça ao Claude do usuário, nessa pasta, para guardar o progresso antes de limpar."
    if [ "$(perguntar "  Para apagar mesmo assim, digite APAGAR:")" != "APAGAR" ]; then echo "Nada foi feito."; return 0; fi
  else ok "nenhum trabalho pendente"; fi

  etapa "2. Login do GitHub e token dos pacotes"
  if existe gh; then
    for i in 1 2 3 4 5; do
      login="$(gh api user -q .login 2>/dev/null | tr -d '[:space:]')"
      [ -n "$login" ] || break
      gh auth logout --hostname github.com --user "$login" >/dev/null 2>&1
      ok "saiu da conta $login"
    done
  fi
  # Contas guardadas nas Chaves do macOS: as do Git (github.com) e as do próprio GitHub CLI.
  while security delete-internet-password -s github.com >/dev/null 2>&1; do ok "conta do Git guardada nas Chaves removida"; done
  while security delete-generic-password -s gh:github.com >/dev/null 2>&1; do ok "conta do GitHub CLI guardada nas Chaves removida"; done
  rm -rf "$HOME/.config/gh"
  launchctl bootout "gui/$(id -u)" "$AGENTE" >/dev/null 2>&1
  rm -f "$AGENTE"
  launchctl unsetenv NODE_AUTH_TOKEN
  unset NODE_AUTH_TOKEN
  for arq in $ARQUIVOS_SHELL; do
    [ -f "$arq" ] || continue
    if grep -qF "$BLOCO_INICIO" "$arq"; then
      awk -v ini="$BLOCO_INICIO" -v fim="$BLOCO_FIM" '$0 == ini { pular = 1; next } $0 == fim { pular = 0; next } !pular' "$arq" >"$arq.nevoni-tmp" && mv "$arq.nevoni-tmp" "$arq"
    fi
  done
  if existe gh && [ -n "$(gh api user -q .login 2>/dev/null)" ]; then falha "o GitHub CLI ainda está logado"
  elif [ -f "$AGENTE" ] || [ -n "$(launchctl getenv NODE_AUTH_TOKEN 2>/dev/null)" ]; then falha "o token dos pacotes continua ligado ($AGENTE)"
  else ok "sem login do GitHub e sem token dos pacotes"; fi

  etapa "3. Configurações do Git"
  if tem_git; then
    for i in user.name user.email core.autocrlf; do git config --global --unset-all "$i" 2>/dev/null; done
    git config --global --remove-section credential.https://github.com 2>/dev/null
    ok "configurações removidas"
  else ok "o Git já não está instalado"; fi

  etapa "4. Pasta dos módulos"
  if [ -d "$PASTA" ]; then
    rm -rf "$PASTA"
    if [ -d "$PASTA" ]; then
      falha "não consegui apagar $PASTA"
      echo "  Se for arquivo em uso: feche o Claude Desktop, o Finder e os terminais nessa pasta, e rode de novo."
    else ok "pasta apagada"; fi
  else ok "pasta já não existia"; fi

  etapa "5. pnpm e npm"
  if existe npm; then
    # pnpm na pasta global de um Node de outra origem; o de /usr/local sai junto com o Node, como administrador.
    if [ "$(command -v pnpm 2>/dev/null)" != "/usr/local/bin/pnpm" ]; then npm uninstall -g pnpm --loglevel=error >/dev/null 2>&1; fi
    npm config delete update-notifier >/dev/null 2>&1
  fi
  rm -rf "$HOME/.npm" "$HOME/Library/pnpm" "$HOME/Library/Caches/pnpm" "$HOME/Library/Preferences/pnpm" "$HOME/.local/share/pnpm"
  ok "pnpm e configurações do npm removidos"

  etapa "6. Proteção do Claude Desktop, programas e Claude Desktop"
  comandos=()
  if [ -f "$MANAGED" ]; then echo "  vai remover: proteção do Claude Desktop"; comandos+=("tentar 'proteção do Claude Desktop' remover_protecao")
  else ok "proteção do Claude Desktop já não existia"; fi
  pkg_node=""
  if existe node; then
    pkg_node="$(pacote_de "$(command -v node)")"
    if [ -n "$pkg_node" ]; then echo "  vai desinstalar: Node.js"; comandos+=("tentar 'Node.js' remover_node")
    else aviso "o Node.js em $(command -v node) não veio do instalador oficial e fica (remova pelo gerenciador que o instalou)"; fi
  else ok "Node.js já não está instalado"; fi
  pkg_gh=""
  if existe gh; then
    pkg_gh="$(pacote_de "$(command -v gh)")"
    if [ -n "$pkg_gh" ]; then echo "  vai desinstalar: GitHub CLI"; comandos+=("tentar 'GitHub CLI' remover_gh '$pkg_gh'")
    else aviso "o GitHub CLI em $(command -v gh) não veio do instalador oficial e fica (remova pelo gerenciador que o instalou)"; fi
  else ok "GitHub CLI já não está instalado"; fi
  if [ -d /Library/Developer/CommandLineTools ]; then echo "  vai desinstalar: ferramentas de linha de comando da Apple (Git)"; comandos+=("tentar 'Git' remover_git")
  else ok "ferramentas de linha de comando da Apple já não estão instaladas"; fi
  if [ -d "$CLAUDE_APP" ]; then echo "  vai desinstalar: Claude Desktop"; comandos+=("tentar 'Claude Desktop' remover_claude")
  else ok "Claude Desktop já não está instalado"; fi
  if [ "${#comandos[@]}" -gt 0 ]; then
    # Mesmo se a senha não for informada, confere e diz o que ficou para trás.
    como_administrador "${comandos[@]}"
    hash -r
    if [ -f "$MANAGED" ]; then falha "não consegui remover $MANAGED"; else ok "proteção do Claude Desktop removida"; fi
    if [ -n "$pkg_node" ]; then if existe node; then falha "o Node.js continua instalado (registro em $LOG)"; else ok "Node.js desinstalado"; fi; fi
    if [ -n "$pkg_gh" ]; then if existe gh; then falha "o GitHub CLI continua instalado (registro em $LOG)"; else ok "GitHub CLI desinstalado"; fi; fi
    if [ -d /Library/Developer/CommandLineTools ]; then falha "as ferramentas de linha de comando da Apple continuam instaladas"; else ok "Git desinstalado"; fi
    if [ -d "$CLAUDE_APP" ]; then falha "o Claude Desktop continua instalado"; else ok "Claude Desktop desinstalado"; fi
  fi

  etapa "7. Dados do Claude nesta conta"
  # Login, conversas, pastas confiadas e configurações do Claude Desktop e da aba Code.
  local dados="$HOME/.claude $HOME/.claude.json $HOME/Library/Application Support/Claude"
  rm -rf "$HOME/.claude" "$HOME/.claude.json" "$HOME/Library/Application Support/Claude" \
    "$HOME/Library/Caches/com.anthropic.claudefordesktop" "$HOME/Library/Caches/com.anthropic.claudefordesktop.ShipIt" \
    "$HOME/Library/Preferences/com.anthropic.claudefordesktop.plist" "$HOME/Library/Logs/Claude" \
    "$HOME/Library/Saved Application State/com.anthropic.claudefordesktop.savedState"
  security delete-generic-password -s "Claude Safe Storage" >/dev/null 2>&1
  if [ -e "$HOME/.claude" ] || [ -e "$HOME/.claude.json" ] || [ -e "$HOME/Library/Application Support/Claude" ]; then
    falha "não consegui apagar todos os dados do Claude ($dados)"
  else ok "dados do Claude nesta conta removidos"; fi

  # Sobra da instalação: se tudo deu certo, o registro da parte de administrador.
  if [ "$FALHAS" -eq 0 ]; then rm -f "$LOG" 2>/dev/null; fi

  echo ""
  if [ "$FALHAS" -eq 0 ]; then printf '\033[32mLIMPEZA CONCLUÍDA.\033[0m\n'
  else printf '\033[31mLIMPEZA INCOMPLETA: %s item(ns) com FALHA acima. Rode de novo; se continuar, mande o print para a TI.\033[0m\n' "$FALHAS"; fi
}

limpar_nevoni_one
