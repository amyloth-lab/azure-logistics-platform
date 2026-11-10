# Day 1 - Do This First

**If the main guide feels like too much, ignore it for now.** Follow this file from top to bottom. It is the minimum path.

- **Time:** about 3 hours, not 4.5.
- **You do not need Terraform, Ansible, Docker, Kubernetes tools, or security scanners today.** Install those before Day 2/3.
- **Today's only hard outcomes:**
  1. The project is in a GitHub repository.
  2. Azure CLI is signed in to the right subscription.
  3. Azure DevOps has the project, Sprint 1, and the Day 1 backlog.
  4. You can explain the diagrams at a high level.
  5. `day-1` is committed and tagged.

Work in this order. Do not jump ahead.

---

## Step 0 - Open the right terminal (2 minutes)

1. Press `Win`, type **PowerShell**, and open **Windows PowerShell** or **PowerShell 7**.
2. Run:

```powershell
# Run from the repository root
Get-ChildItem
```

You should see `README.md`, `docs`, `diagrams`, `scripts`, and the other folders.

If the path does not exist, find the folder where this project was saved and use that path instead.

**Checkpoint:** `Get-ChildItem` lists the project files.

---

## Step 1 - Install Git and GitHub CLI (15 minutes)

In the same PowerShell window:

```powershell
winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
winget install --id GitHub.cli -e --source winget --accept-package-agreements --accept-source-agreements
```

Close PowerShell and open it again. Then check:

```powershell
git --version
gh --version
```

Expected:

```text
git version 2.x.x
gh version 2.x.x
```

### If `winget` is not available

Install manually:

- Git for Windows: <https://git-scm.com/download/win>
- GitHub CLI: <https://cli.github.com/>

After installing, close **all** terminals and VS Code windows, reopen PowerShell, and run the two version checks again.

**Checkpoint:** both commands print a version.

---

## Step 2 - Open the project in VS Code (3 minutes)

Still in PowerShell:

```powershell
code .
```

VS Code opens the project folder.

If `code` is not recognized, open VS Code manually, choose **File > Open Folder**, and select the repository root folder.

In VS Code, open **Terminal > New Terminal**. Use this terminal for the rest of the steps.

**Checkpoint:** the VS Code Explorer shows `README.md`, `docs`, `diagrams`, and `scripts`.

---

## Step 3 - Initialize Git and make the first commit (10 minutes)

In the VS Code terminal:

```powershell
git init -b main
git config user.name "Your Name"
git config user.email "you@example.com"
git add .
git status
```

Replace `Your Name` and `you@example.com` with your details.

`git status` should show the project files as **Changes to be committed**.

### Scan for secrets before committing

If you installed Gitleaks:

```powershell
gitleaks detect --source . --verbose --redact --no-git
```

If Gitleaks is not installed, do a basic manual check:

```powershell
git grep -nE "AccountKey=|SharedAccessKey=|client_secret|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY" -- .
```

The repository should contain **no real** subscription IDs, tenant IDs, passwords, connection strings, PATs, or private keys.

Commit:

```powershell
git commit -m "docs(day-1): architecture, network, identity, and delivery plan"
```

**Checkpoint:** `git log --oneline -1` shows your commit.

---

## Step 4 - Create the GitHub repository and push (10 minutes)

```powershell
gh auth login
```

Choose:

- **GitHub.com**
- **HTTPS**
- **Login with a web browser**
- Follow the one-time code prompt.

Then create the private repository and push:

```powershell
gh repo create azure-logistics-platform --private --source . --remote origin --push
```

If the name is already taken, use a unique name:

```powershell
gh repo create azure-logistics-platform-yourname --private --source . --remote origin --push
```

Open it:

```powershell
gh repo view --web
```

**Checkpoint:** the repository opens in your browser with the project files.

---

## Step 5 - Protect the `main` branch (5 minutes)

In GitHub:

1. Open the repository.
2. Go to **Settings > Branches**.
3. Click **Add branch protection rule**.
4. Branch name pattern: `main`.
5. Enable **Require a pull request before merging**.
6. Set **Required approvals** to `1`.
7. Enable **Dismiss stale pull request approvals when new commits are pushed**.
8. Enable **Do not allow bypassing the above settings**.
9. Enable **Block force pushes** and **Restrict deletions**.
10. Save.

Do not add required status checks yet. You will add the Azure DevOps build check on Day 4.

> If GitHub says branch protection is not available for this private repository, your plan does not include it. Use a public repository with no secrets, or use a GitHub plan that supports protected branches. Record the choice in `docs/day-01/review-notes.md`.

**Checkpoint:** `main` shows as protected in GitHub.

---

## Step 6 - Fix and sign in to Azure CLI (10 minutes)

Check:

```powershell
az --version
```

If it prints a version, skip to the login below.

### If you see `PermissionError: ... az.sess`

Run:

```powershell
Remove-Item "$env:USERPROFILE\.azure\az.sess" -Force -ErrorAction SilentlyContinue
```

Then try again.

If it still fails, repair the folder permissions:

```powershell
icacls "$env:USERPROFILE\.azure" /grant "$($env:USERNAME):(OI)(CI)F" /T
```

If that is denied, run PowerShell as Administrator and try the same command, or reinstall Azure CLI from:

<https://learn.microsoft.com/cli/azure/install-azure-cli-windows>

### Sign in

```powershell
az login
az account list --output table
```

Find the subscription you want to use. Copy its **SubscriptionId**, then:

```powershell
az account set --subscription "<paste-subscription-id-here>"
az account show --output jsonc
```

The JSON should show the correct subscription and `"state": "Enabled"`.

**Checkpoint:** `az account show` returns the intended subscription.

---

## Step 7 - Create the Azure DevOps project (10 minutes)

In the browser:

1. Go to `https://dev.azure.com/<your-org>`.
2. Click **New project**.
3. Name: `azure-logistics-platform`.
4. Visibility: **Private**.
5. Version control: **Git**.
6. Work item process: **Agile**.
7. Create.

Then:

1. Open **Project settings > Project configuration**.
2. Under **Areas**, add `Logistics`.
3. Under **Iterations**, add `Sprint 1` and set the five working dates for this week.

**Checkpoint:** the project exists and `Sprint 1` is visible under **Boards > Sprints**.

---

## Step 8 - Import the Day 1 backlog (15 minutes)

1. Open **Boards > Queries**.
2. Choose **Import work items** (some versions show **Work Items > Import Work Items**).
3. Select `docs/day-01/azure-boards-import.csv` from the project.
4. Map the columns. If a field is invalid for a work item type, ignore that field for this import.
5. Import.
6. Open **Boards > Backlogs** and verify the epics/features/stories/tasks.
7. If parent links are missing, link the top-level epics to their features manually.

If the import fails completely, create these five Day 1 items manually:

1. Epic: `Platform foundation and secure network`
2. Feature: `Hub-and-spoke network`
3. User Story: `Design hub-and-spoke CIDR plan`
4. User Story: `Define RBAC matrix and manager delete`
5. User Story: `Threat model and zero-trust controls`

**Checkpoint:** the Day 1 work items are visible on the board.

---

## Step 9 - Read the diagrams and fill the review notes (30 minutes)

Open:

- `diagrams/logical-architecture.png`
- `diagrams/network-topology.png`
- `docs/day-01/network-design.md`
- `docs/day-01/identity-and-rbac.md`

Then open `docs/day-01/review-notes.local.md` and answer the ten questions in **short** sentences. This is your **private, gitignored** copy. Put your real subscription ID and tenant details there, **not** in the tracked `review-notes.md` template.

If the local file does not exist, create it first:

```powershell
Copy-Item docs\day-01\review-notes.md docs\day-01\review-notes.local.md
```

At minimum, be able to answer these five:

1. What is the only public application entry point?
2. Where does APIM receive private traffic, and where does it send outbound traffic?
3. Which role can delete an order, and where is that enforced?
4. How does a user get a token, and how does the API know what they may do?
5. Where is Terraform state stored, and who can read it?

**Checkpoint:** `review-notes.local.md` has answers, assumptions, and at least three risks. `git check-ignore docs/day-01/review-notes.local.md` confirms it is ignored.

---

## Step 10 - Validate, commit, and tag (10 minutes)

In the VS Code terminal:

```powershell
python scripts/validate_repo.py
```

If `python` opens the Microsoft Store or is not found, try:

```powershell
py -3.12 scripts/validate_repo.py
```

You want:

```text
OK: required files
OK: markdown links
OK: backlog CSV
OK: python syntax
OK: diagrams
Validation passed.
```

Before committing, confirm the private notes are ignored and no account identifiers are in tracked files:

```powershell
git check-ignore -v docs\day-01\review-notes.local.md
git grep -nE "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|@[A-Za-z0-9.-]+\.onmicrosoft\.com|AccountKey=|SharedAccessKey=" -- .
git status --short
```

`git check-ignore` should print the matching `.gitignore` rule. `git grep` should print nothing. `git status` should **not** show `review-notes.local.md`.

If Gitleaks is installed, also run:

```powershell
gitleaks detect --source . --verbose --redact --no-git
```

Then:

```powershell
git add .
git status --short
git grep --cached -nE "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|@[A-Za-z0-9.-]+\.onmicrosoft\.com|AccountKey=|SharedAccessKey=" -- .
git commit -m "docs(day-1): complete architecture, network, RBAC, and plan"
git tag -a day-1 -m "Day 1 checkpoint: architecture and delivery plan"
git push origin main --tags
```

**Checkpoint:** `git log --oneline -1` shows the commit, and `git tag` lists `day-1`.

---

## Step 11 - Install the rest before Day 2 (optional today)

Do these later if you are tired. They are not required to finish Day 1:

```powershell
winget install --id Hashicorp.Terraform -e --source winget
winget install --id Kubernetes.kubectl -e --source winget
winget install --id Helm.Helm -e --source winget
winget install --id Docker.DockerDesktop -e --source winget
winget install --id aquasecurity.trivy -e --source winget
winget install --id terraform-linters.tflint -e --source winget
winget install --id gitleaks.gitleaks -e --source winget
```

Ansible is only needed on Day 3. If WSL2 is blocked on your machine, use a small Linux VM in Azure or GitHub Codespaces later. Do not let WSL block Day 1.

---

## Step 12 - End of Day 1

You are done when:

- [ ] The GitHub repository exists and `main` is protected.
- [ ] Azure CLI is signed in to the correct subscription.
- [ ] Azure DevOps has the project, `Sprint 1`, and the Day 1 backlog.
- [ ] `review-notes.md` is filled in.
- [ ] `python scripts/validate_repo.py` passes.
- [ ] `day-1` is committed and tagged.
- [ ] No Azure resources were created.

Then reply in the chat with exactly:

```text
EOD
```

Day 2 will start with the Terraform state bootstrap and the hub network.

---

## If you only have 30 minutes today

Do **Step 1** and **Step 2** only. Stop. Come back tomorrow and continue with Step 3. The project is not a race; the sequence matters more than the speed.
