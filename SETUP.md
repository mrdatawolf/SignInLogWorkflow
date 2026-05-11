---
port: 
start: powershell -STA -File .\Start-SignInLogWorkflow.ps1
---

# Setup

## Prerequisites

- **Windows** with **PowerShell 5.1** or later
- **Firefox** installed (falls back to the default browser if not found)
- A UNC share accessible from your machine with the following folder structure:
  ```
  <BaseFolder>\
    O365 Signins\
      Interactive\
      NonInteractive\
      O365logins.sqlite3
    companies.xlsx
  ```
- `companies.xlsx` — an Excel workbook with a **Companies** sheet containing `Abbrv` and `Group` columns; clients in the `SLG` group (plus `BT`) are processed
- `Admin Emails.xlsx` — an Excel workbook with `Client`, `Email`, and `Password` columns containing admin credentials for each client abbreviation
- The **ImportExcel** PowerShell module (automatically installed on first run if missing)

## Installation

```powershell
git clone https://github.com/mrdatawolf/SignInLogWorkflow.git
cd SignInLogWorkflow
```

## Configuration

```powershell
Copy-Item .env.example .env
```

Edit `.env` and fill in your values:

```
baseFolder=\\server\share\ClientData
companiesFilename=companies.xlsx
adminEmailsFile=\\server\share\Data\Admin Emails.xlsx
```

| Key | Description |
|-----|-------------|
| `baseFolder` | UNC path to the root share folder |
| `companiesFilename` | Filename of the companies workbook inside `baseFolder` |
| `adminEmailsFile` | Full path to the Admin Emails workbook |

## Running

Right-click `Start-SignInLogWorkflow.ps1` and choose **Run with PowerShell**, or launch it from a terminal:

```powershell
powershell -STA -File .\Start-SignInLogWorkflow.ps1
```

> The `-STA` flag is required for the WPF UI. The script re-launches itself in STA mode automatically if needed.

On first launch, the **Setup** screen will verify that all required paths are accessible. Fix any failures shown in red and click **Retry Checks** until all pass, then click **Proceed to Workflow**.

## Notes

Click **Settings** in the navigation bar to update folder paths without editing `.env`. Changes are saved to `config.json` next to the script and take effect after the next client load.
