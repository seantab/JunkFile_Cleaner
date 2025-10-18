# File Cleaner Bot v2.0 (Portable)

**Authored and Architect: Sean Tabrizi**  
**Email: seantab@gmail.com**

A portable file cleanup utility with smart categorization, web interface, and automatic backup protection.

## Tech Stack

**Backend:**
- PowerShell 5.1+ (Windows built-in)
- System.Net.HttpListener (Web server)
- System.Windows.Forms (Native folder browser)
- System.IO.Compression (ZIP backup)

**Frontend:**
- HTML5 + CSS3 (Modern gradient UI)
- Vanilla JavaScript (No dependencies)
- Responsive design with flexbox/grid

**Configuration:**
- YAML (Human-readable config)

**Key Features:**
- Zero external dependencies
- Fully portable (runs from any directory)
- Native Windows integration
- Single-file PowerShell engine

## Features

- **Smart File Categorization** - Automatically identifies and categorizes temporary files, logs, cache, and data files
- **Web-Based UI** - Clean, modern interface for reviewing and selecting files to delete
- **Automatic Backup** - All deleted files are backed up to a ZIP archive before removal
- **Configurable Retention** - Set different retention periods for different file types
- **Protected Items** - Never accidentally delete important configuration or source files
- **Portable** - Drop into any project directory and run
- **Recent Directories** - Quick access to your last 5 scanned directories

## Quick Start

1. **Run the launcher**: Double-click `Start_Cleaner.bat`
2. **Select directory**: Choose any directory you want to clean (can be anywhere on your system)
3. **Choose file types**: Review detected file categories and select which types to include
4. **Review & clean**: See the complete file list, select files, and delete with automatic backup

### 3-Step Workflow

**Step 1: Select Directory** [>>]
- Enter any directory path on your system
- Quick options for current directory or custom path
- Validates directory exists before scanning

**Step 2: Choose File Types** [...]
- See all detected file categories with counts and sizes
- Select which categories you want to review
- Preview retention periods and recommendations
- Warning: You'll see the full file list before any deletion

**Step 3: Review & Clean** [CLEAN]
- Detailed file list with ages, sizes, and paths
- Select individual files or entire categories
- All files backed up before deletion
- Meaningful backup names with directory and timestamp

## File Structure

```
File_cleaner_bot/
├── Cleaner.ps1                # Main PowerShell engine
├── Start_Cleaner.bat          # Windows launcher
├── cleaner_config.yaml        # Configuration file
├── README.md                  # This file
├── logs/                      # Operation logs
└── _FileCleaner_Backup/       # Backup archives with meaningful names
```

## Configuration

Edit `cleaner_config.yaml` to customize:

### File Categories

The utility scans for these file types by default:

- **Log Files** (.log, .out, .txt) - 30 day retention
- **Temporary Files** (.pid, .coverage, .tmp) - 1 day retention
- **Python Cache** (.pyc, .pyo, __pycache__) - 30 day retention
- **Data & Reports** (.csv, .xlsx, .xls) - 90 day retention
- **Test Coverage** (htmlcov, .html) - 14 day retention

### Protected Items

These are **never** deleted:

- Configuration files (*.yaml, *.json, *.yml)
- Scripts (*.ps1, *.bat, *.sql)
- Documentation (*.md)
- Source control (.git directory)
- The File Cleaner Bot itself

### Backup Settings

```yaml
backup:
  enabled: true
  location: "_FileCleaner_Backup"
  compress: true
  filename_pattern: "Backup_{target_directory}_{timestamp}.zip"
  max_backup_age_days: 30
```

**Backup File Naming:**
- Format: `Backup_ProjectName_YYYYMMDD_HHMMSS.zip`
- Example: `Backup_MyProject_20251018_103045.zip`
- Easy identification of what was cleaned and when

### Recent Directories

The utility remembers your last 5 scanned directories for quick access:
- Stored in browser localStorage
- Shows time since last scan (e.g., "2h ago", "3d ago")
- Click any recent directory to instantly select it
- Configurable limit in `cleaner_config.yaml` (`max_recent_directories`)

## Usage

### Web Interface (Default)

```batch
Start_Cleaner.bat
```

- Opens browser automatically
- Review files by category
- Select files individually or by category
- See real-time selection counters
- Confirm before deletion

### Command Line Mode

```powershell
powershell -ExecutionPolicy Bypass -File Cleaner.ps1 -NoUI
```

### Dry Run Mode

```powershell
powershell -ExecutionPolicy Bypass -File Cleaner.ps1 -DryRun
```

## Web Interface Features

- **Category Grouping** - Files organized by type
- **Bulk Actions** - Select all, select old files, or clear selection per category
- **Smart Recommendations** - Color-coded suggestions (green = safe to delete, red = keep)
- **File Details** - Size, age, last modified date, and relative path
- **Summary Dashboard** - Total files, potential space savings
- **Refresh** - Re-scan without restarting
- **Safe Shutdown** - Close server cleanly

## Safety Features

1. **Automatic Backup** - All deleted files are zipped before removal
2. **Protected Patterns** - Configuration and source files are never shown
3. **Confirmation Required** - Must confirm before deletion
4. **Detailed Logging** - All operations logged to `FileCleaner_logs/cleaner_log.txt`
5. **Retention Periods** - Files within retention period marked as "KEEP"

## Logs

Operation logs are stored in `FileCleaner_logs/cleaner_log.txt`:

- Timestamp of each operation
- Files deleted
- Backup archive location
- Any errors encountered

## Backup Archives

Deleted files are backed up to `_FileCleaner_Backup/` with meaningful names:

```
_FileCleaner_Backup/
├── Backup_ProjectA_20251018_093045.zip
├── Backup_ProjectB_20251018_103022.zip
└── Backup_TestDir_20251018_143511.zip
```

**Features:**
- Includes target directory name for easy identification
- Timestamp in YYYYMMDD_HHMMSS format
- Backups kept for 30 days by default (configurable)
- All files preserved in original directory structure

## Customization

### Add New File Categories

Edit `cleaner_config.yaml`:

```yaml
file_categories:
  my_custom_category:
    name: "My Custom Files"
    description: "Description of these files"
    extensions: [".ext1", ".ext2"]
    directories: ["path/to/scan"]
    default_retention_days: 14
    recommendation: "Your recommendation"
    always_preserve: false
```

### Change Port

Edit `cleaner_config.yaml`:

```yaml
ui:
  port: 8502  # Change to your preferred port
```

### Disable Auto-Open Browser

Edit `cleaner_config.yaml`:

```yaml
ui:
  auto_open_browser: false
```

## Troubleshooting

### Port Already in Use

Change the port in `cleaner_config.yaml` or close the application using port 8502.

### PowerShell Execution Policy

If you get an execution policy error, run:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### No Files Found

This is normal for a fresh installation. The utility will find files after your project generates logs, cache, or temporary files.

## Requirements

- Windows OS
- PowerShell 5.0 or later (included in Windows 10+)
- No additional dependencies required

## Use Cases

- **Multi-Project Cleanup** - Scan and clean any directory on your system
- **Test Artifact Removal** - Clean up test execution logs and artifacts
- **Python Development** - Remove cache and coverage files
- **Data Management** - Archive old data files and reports
- **Disk Space Recovery** - Free up space from temporary files
- **Project Maintenance** - Keep multiple project directories clean
- **Safe Experimentation** - Try cleaning with automatic backup protection

## Version History

**v2.1 (Portable) - Enhanced UX**
- 📁 **Recent Directories**: Quick access to last 5 scanned directories with timestamps
- 🎯 **Topmost Folder Browser**: Dialog now opens in front of browser window
- 🎨 **UI Polish**: Clean interface without keyboard shortcut distractions
- 🔧 **YAML Configuration**: Customize recent directory limit

**v2.0 (Portable) - Enhanced**
- [+] **3-Step Workflow**: Directory selection -> File type selection -> Review & clean
- [>>] **True Portability**: Scan ANY directory on your system, not just where utility is located
- [BAK] **Meaningful Backups**: Backup files named with target directory and timestamp
- [UI] **Modern UI**: Beautiful gradient design with step indicators
- [!] **Safety First**: See file type recommendations before viewing individual files
- [DIR] **Smart Backup Location**: All backups in `_FileCleaner_Backup` with clear naming
- [UX] **Improved UX**: Native folder browser, instant shutdown, back navigation

**v2.0 (Portable) - Initial**
- Converted to standalone portable utility
- Removed project-specific dependencies
- Simplified configuration
- Updated branding and documentation

**v1.0**
- Initial LoadTest-integrated version

## License

Free to use and modify for any project.

## Support

For issues or questions, check the logs in `FileCleaner_logs/cleaner_log.txt` for detailed error messages.
