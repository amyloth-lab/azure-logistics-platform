# Scripts

| Script | Purpose |
|---|---|
| `check-prereqs.ps1` | Windows workstation check for Day 1 tools |
| `check-prereqs.sh` | WSL2/Linux check for Ansible and build tools |
| `build_backlog_csv.py` | Regenerate the Azure Boards import CSV |
| `validate_repo.py` | Check local Markdown links, CSV shape, Python syntax, and diagrams |

Run the Windows check from the repository root:

```powershell
pwsh -File .\scripts\check-prereqs.ps1
```

Run the Linux check in WSL:

```bash
chmod +x scripts/check-prereqs.sh
./scripts/check-prereqs.sh
```

Regenerate the backlog after editing the rows in `build_backlog_csv.py`:

```powershell
python scripts/build_backlog_csv.py
```

Validate the repository before a commit:

```powershell
python scripts/validate_repo.py
```

These scripts only inspect or generate local files. They do not install tools, create Azure resources, or read secrets.
