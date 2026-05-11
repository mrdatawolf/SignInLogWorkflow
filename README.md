# SignInLogWorkflow

SignInLogWorkflow is a PowerShell WPF desktop application that automates the daily process of collecting Microsoft Entra (Azure AD) sign-in logs for multiple managed clients and importing them into a central SQLite database. For each client in your list, the tool walks you through a guided four-step workflow: it opens a private Firefox window directly to that client's Entra sign-in log page and copies their admin username to your clipboard, then copies their password to your clipboard so you can authenticate and download the sign-in JSON exports, then automatically detects the downloaded files, moves them to the correct location on the UNC share, and runs the database import in the background — all while you move on to the next client.

---

## Setup, Configuration & Running

See [SETUP.md](SETUP.md) for prerequisites, installation, configuration, and how to run the application.

---

## Workflow (per client session)

Once the prechecks pass, the application loads the client list and steps you through each client automatically:

| Step | What you do | What the app does |
|------|-------------|-------------------|
| **1 — Open Browser** | Click **Open Browser** | Opens Firefox in private mode to the client's Entra sign-in log page; copies their username to your clipboard |
| **2 — Log In** | Paste the username, click **Username Done** | Copies the client's password to your clipboard |
| **3 — Download & Confirm** | Authenticate, export the Interactive and Non-Interactive sign-in JSON files, then click **Files Done** | Finds today's JSON files in your Downloads folder, moves them to the UNC share, and starts the SQLite import in the background |
| **4 — Next Client** | Click **Next Client** at any time after files are moved | Moves to the next pending client while the import continues in the background |

The progress bar and client list update in real time. You can **Skip** any client to exclude them from the current session.

