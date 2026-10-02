# Instalação da máquina do usuário final do Nevoni ONE

Scripts da TI da Nevoni para preparar e limpar a máquina de quem desenvolve módulos do Nevoni ONE
pelo Claude Desktop. Não contêm nenhum segredo: o login e o token são do próprio usuário, feitos na
hora da instalação.

No **PowerShell comum** (não como administrador), na conta do Windows do usuário:

| Para | Comando |
|---|---|
| Instalar (ou conferir e completar) | `irm https://raw.githubusercontent.com/NevoniONE/nevoni-one-instalacao/main/instalar.ps1 \| iex` |
| Só conferir, sem mudar nada | `$env:NEVONI_MODO = "conferir"; irm https://raw.githubusercontent.com/NevoniONE/nevoni-one-instalacao/main/instalar.ps1 \| iex` |
| Limpar tudo, inclusive os programas | `irm https://raw.githubusercontent.com/NevoniONE/nevoni-one-instalacao/main/limpar.ps1 \| iex` |

O roteiro completo da TI fica no repositório do núcleo (`docs/ROTEIRO_INSTALACAO_USUARIO_FINAL.md`).
