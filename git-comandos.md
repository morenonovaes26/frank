# Comandos Git do projeto Frank

Repositório: https://github.com/morenonovaes26/frank
Pasta de trabalho: /opt/frank
Branch principal: main

Nunca cole tokens ou senhas em arquivos deste repositório.

---

## 1. Verificar o estado atual

```bash
cd /opt/frank

# Mostra arquivos modificados, novos e não rastreados
git status

# Histórico resumido dos commits
git log --oneline

# Confirma para qual repositório o push vai
git remote -v
```

---

## 2. Fluxo do dia a dia (editar, commitar, enviar)

```bash
cd /opt/frank

# Atualizar do GitHub antes de começar (evita conflitos)
git pull

# ... editar os arquivos ...

# Conferir o que mudou antes de adicionar
git status
git diff

# Adicionar TODAS as alterações (o .gitignore já bloqueia .env e arquivos grandes)
git add -A

# Conferir de novo o que vai entrar no commit
git status

# Criar o commit com uma mensagem clara (verbo no imperativo, uma linha)
git commit -m "Atualiza inventário com VMID do ubuntu-infra"

# Enviar para o GitHub
git push
```

---

## 3. Adicionar um arquivo específico

```bash
# Em vez de tudo, adiciona só um arquivo
git add inventario.yaml

# Adiciona uma pasta inteira
git add scripts/
```

---

## 4. Verificar se algum segredo está prestes a ser enviado

```bash
# Lista arquivos que serão commitados (depois do git add)
git diff --cached --name-only

# Procura padrões de token ou senha nos arquivos staged
git diff --cached | grep -iE "token|password|secret|api_key|passwd" || echo "Nada suspeito encontrado"

# Confirma que o .env não está sendo rastreado
git ls-files | grep -x '\.env' || echo ".env não está versionado"
```

Se algum segredo aparecer no histórico, não basta apagá-lo em um commit novo. Troque a credencial imediatamente e me avise para reescrever o histórico.

---

## 5. Desfazer (escolha com cuidado)

```bash
# Tirar um arquivo da área de staging, sem perder as alterações
git restore --staged inventario.yaml

# Descartar alterações em um arquivo (IRREVERSÍVEL: perde o que foi editado)
git restore inventario.yaml

# Desfazer o último commit, mantendo as alterações nos arquivos
git reset --soft HEAD~1

# Corrigir a mensagem do último commit (só antes de fazer push)
git commit --amend -m "Nova mensagem"

# Ver um arquivo como estava em um commit antigo
git show <hash-do-commit>:inventario.yaml
```

Depois de um `git push`, prefira criar um novo commit que reverte, em vez de reescrever o histórico:

```bash
git revert <hash-do-commit>
git push
```

---

## 6. Trabalhar com branches (recomendado para mudanças grandes)

```bash
# Criar e mudar para uma branch nova
git checkout -b feature/vulnerabilidades-n8n

# Enviar a branch nova ao GitHub pela primeira vez
git push -u origin feature/vulnerabilidades-n8n

# Voltar para a main
git checkout main

# Atualizar a main
git pull

# Juntar a branch na main (faça isso pelo GitHub via Pull Request, ou localmente)
git merge feature/vulnerabilidades-n8n
git push
```

---

## 7. Sincronização e conflitos

```bash
# Buscar mudanças do GitHub sem aplicar ainda
git fetch

# Ver o que mudou no remoto antes de aplicar
git log HEAD..origin/main --oneline

# Aplicar as mudanças do remoto
git pull

# Se der conflito: abrir os arquivos marcados com <<<<<<<, escolher o texto
# certo, depois:
git add <arquivo-resolvido>
git commit
git push
```

---

## 8. Problemas comuns

```bash
# "dubious ownership" (pasta com dono diferente)
git config --global --add safe.directory /opt/frank

# "Repository not found" ou credencial antiga em cache
printf "protocol=https\nhost=github.com\n" | git credential reject
git push   # informe o usuário e o token novo quando pedir

# Ver a configuração de identidade usada nos commits
git config user.name
git config user.email

# Definir identidade (uma vez por máquina)
git config --global user.name "Seu Nome"
git config --global user.email "seu-email@exemplo.com"

# "Permission denied" em /opt/frank
sudo chown -R $USER /opt/frank
```

---

## 9. Regras do projeto

- Só versionar `.env.example`. O `.env` real fica apenas no servidor.
- Não versionar ISOs, OVAs, dados de banco nem logs (já bloqueado pelo `.gitignore`).
- Mensagens de commit no imperativo e em português, por exemplo: "Adiciona script de backup do NPM".
- Antes de mudar o `inventario.yaml`, atualize também os `TODO` pendentes para não deixar informação desatualizada.
- Manter o repositório privado.
