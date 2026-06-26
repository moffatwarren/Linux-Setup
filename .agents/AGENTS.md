# Custom Workspace Rules

- **Permission Policy**: Always ask the user for explicit permission before making any file changes (creation, modification, deletion) or executing terminal commands. When asking for permission to edit a file, always display the proposed changes (such as a diff or code snippet) first so the user can review them.
- **Target Files Only**: Only propose and make changes to files within this repository workspace directory (`/home/warren/Linux-Setup`). Do not ask for permission to change, or make changes to, the live home/system environment (such as `~/.config/` or active system files).
