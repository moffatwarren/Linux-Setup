# Git commands

## Identity and login

```sh
gh auth login
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
git config --list
```

If you are not using `gh auth`, store credentials instead:

```sh
git config --global credential.helper store
```

## Everyday

```sh
git status
git add .
git add filename.txt anotherfile.js
git add --all
git commit -m "Your descriptive commit message here"
git push origin master
git pull origin master
```

## Seeing what changed

| Command | Shows |
|---|---|
| `git diff` | changes not yet staged (before `git add`) |
| `git diff --staged` | changes already staged (after `git add`) |
| `git diff HEAD` | everything, staged and unstaged |
| `git diff path/to/your/file.txt` | unstaged changes in one file |
| `git diff --staged path/to/your/file.txt` | staged changes in one file |

## Starting a new repo

1. Create the new repo on GitHub and copy its URL.
2. In the project folder:

```sh
git init -b main
echo ".claude/" >> .gitignore
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/you/your-repo.git
git push -u origin main
```
