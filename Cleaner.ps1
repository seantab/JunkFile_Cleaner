# ========================================================================
# File Cleaner Bot - Main Engine
# ========================================================================
# Portable file cleanup utility with smart categorization and web interface
# 
# Authored and Architect: Sean Tabrizi
# Email: seantab@gmail.com
# ========================================================================

param(
    [switch]$DryRun = $false,
    [switch]$NoUI = $false
)

# Import required modules
Add-Type -AssemblyName System.Web
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Get script directory (this is now the root for portable utility)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CleanerRoot = $ScriptDir
$RootDir = $ScriptDir

# Global variables for session state
$global:TargetDirectory = $null
$global:ScanResults = $null
$global:SessionState = 'directory_selection'  # States: directory_selection, file_type_selection, file_review

# Load configurations
function Load-Config {
    param($ConfigPath)
    try {
        if (-not (Test-Path $ConfigPath)) {
            Write-Warning "Config file not found: $ConfigPath"
            return @{}
        }
        $yamlContent = Get-Content $ConfigPath -Raw
        # Simple YAML parser for our needs
        $config = @{}
        $yamlContent -split "`n" | ForEach-Object {
            if ($_ -match '^\s*([^#:]+):\s*(.+)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim().Trim('"')
                if ($value -match '^\d+$') { $value = [int]$value }
                elseif ($value -match '^true$|^false$') { $value = [bool]::Parse($value) }
                $config[$key] = $value
            }
        }
        return $config
    }
    catch {
        Write-Error "Failed to load config from $ConfigPath : $_"
        return @{}
    }
}

# Load cleaner config from script directory
$CleanerConfig = Load-Config "$CleanerRoot\cleaner_config.yaml"

# Get port configuration from YAML
$CleanerPort = $null
if ($CleanerConfig.ContainsKey('port')) {
    $CleanerPort = $CleanerConfig['port']
}
# Fallback to default port if not found
if (-not $CleanerPort) {
    $CleanerPort = 8502
    Write-Host "Using default port: $CleanerPort" -ForegroundColor Gray
} else {
    # Clean up the port value (remove any comments or extra text)
    $CleanerPort = $CleanerPort -replace '\s*#.*$', '' -replace '\s+', ''
    # Ensure it's a valid integer
    if (-not ($CleanerPort -match '^\d+$')) {
        Write-Warning "Invalid port configuration: $CleanerPort, using default 8502"
        $CleanerPort = 8502
    } else {
        $CleanerPort = [int]$CleanerPort
    }
}

# Initialize log file path and ensure directory exists
$LogDir = Join-Path $CleanerRoot "FileCleaner_logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$LogFile = Join-Path $LogDir "cleaner_log.txt"

Write-Host "File Cleaner Bot v2.0 (Portable)" -ForegroundColor Cyan
Write-Host "Script Directory: $CleanerRoot" -ForegroundColor Green
Write-Host "Backup Location: $CleanerRoot\_FileCleaner_Backup" -ForegroundColor Green
Write-Host "Log Directory: $LogDir" -ForegroundColor Green

# File analysis function
function Analyze-Files {
    param(
        [string]$TargetPath,
        [switch]$Verbose
    )
    
    if (-not $TargetPath) {
        $TargetPath = $global:TargetDirectory
    }
    if (-not $TargetPath) {
        $TargetPath = $RootDir
    }
    
    $results = @()
    $pathsChecked = 0
    $pathsFound = 0
    $pathsMissing = @()
    
    $categories = @{
        'Log Files' = @{
            paths = @("$TargetPath\logs", "$TargetPath\FileCleaner_logs")
            extensions = @('.log', '.out', '.txt')
            retention_days = 30
            description = 'Application and execution log files'
            recommendation = 'Keep recent logs for troubleshooting'
        }
        'Temp Files' = @{
            paths = @("$TargetPath")
            extensions = @('.pid', '.coverage', '.tmp', '.temp')
            retention_days = 1
            description = 'Temporary process and coverage files'
            recommendation = 'Always safe to delete'
        }
        'Python Cache' = @{
            paths = @("$TargetPath")
            patterns = @('__pycache__', '.pytest_cache', '.benchmarks')
            extensions = @('.pyc', '.pyo')
            retention_days = 30
            description = 'Python cache and benchmark files'
            recommendation = 'Safe to clean - regenerated automatically'
        }
        'Data Files' = @{
            paths = @("$TargetPath")
            extensions = @('.csv', '.xlsx', '.xls')
            retention_days = 90
            description = 'Generated data and report files'
            recommendation = 'Archive older files, keep recent ones'
        }
        'Test Coverage' = @{
            paths = @("$TargetPath")
            patterns = @('htmlcov', 'coverage')
            extensions = @('.html')
            retention_days = 14
            description = 'HTML coverage reports and test artifacts'
            recommendation = 'Coverage reports can be regenerated'
        }
    }

    foreach ($category in $categories.Keys) {
        $categoryInfo = $categories[$category]
        $cutoffDate = (Get-Date).AddDays(-$categoryInfo.retention_days)
        
        foreach ($path in $categoryInfo.paths) {
            $pathsChecked++
            if (Test-Path $path) {
                $pathsFound++
                $files = @()
                
                # Handle extensions
                if ($categoryInfo.extensions) {
                    foreach ($ext in $categoryInfo.extensions) {
                        $files += Get-ChildItem -Path $path -Filter "*$ext" -Recurse -File -ErrorAction SilentlyContinue
                    }
                }
                
                # Handle patterns (like matrix_*)
                if ($categoryInfo.patterns) {
                    foreach ($pattern in $categoryInfo.patterns) {
                        $files += Get-ChildItem -Path $path -Filter $pattern -Recurse -ErrorAction SilentlyContinue
                    }
                }
                
                foreach ($file in $files) {
                    $isOld = $file.LastWriteTime -lt $cutoffDate
                    $sizeKB = [math]::Round($file.Length / 1KB, 2)
                    
                    $results += [PSCustomObject]@{
                        Category = $category
                        FileName = $file.Name
                        FullPath = $file.FullName
                        RelativePath = $file.FullName.Replace($TargetPath, '').TrimStart('\')
                        SizeKB = $sizeKB
                        LastModified = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
                        Age = ((Get-Date) - $file.LastWriteTime).Days
                        IsOld = $isOld
                        Recommendation = if ($isOld) { "DELETE - Older than $($categoryInfo.retention_days) days" } else { "KEEP - Within retention period" }
                        Description = $categoryInfo.description
                        SafeToDelete = $isOld
                    }
                }
            } else {
                $pathsMissing += $path
            }
        }
    }
    
    # Store diagnostics for later display
    $script:PathDiagnostics = @{
        PathsChecked = $pathsChecked
        PathsFound = $pathsFound
        PathsMissing = $pathsMissing
    }
    
    return $results | Sort-Object Category, Age -Descending
}

# Generate Directory Selection HTML (Step 1)
function Generate-DirectorySelectionHTML {
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>File Cleaner Bot - Select Directory</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 50%, #d946ef 100%); min-height: 100vh; }
        .container { max-width: 800px; margin: 50px auto; background: white; padding: 40px; border-radius: 20px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); }
        .header { text-align: center; margin-bottom: 40px; }
        .header h1 { color: #1e293b; margin: 0 0 10px 0; font-size: 32px; font-weight: 700; }
        .header p { color: #64748b; margin: 0; font-size: 16px; }
        .step-indicator { display: flex; justify-content: center; margin-bottom: 40px; gap: 10px; }
        .step { flex: 1; text-align: center; padding: 12px; background: #f1f5f9; border-radius: 8px; font-size: 14px; font-weight: 500; }
        .step.active { background: linear-gradient(135deg, #6366f1, #8b5cf6); color: white; font-weight: 600; }
        .step.inactive { color: #94a3b8; }
        .info-box { background: linear-gradient(135deg, #dbeafe, #e0e7ff); border-left: 4px solid #6366f1; padding: 20px; border-radius: 12px; margin-bottom: 30px; }
        .info-box p { margin: 0; color: #1e293b; line-height: 1.6; }
        .info-box strong { color: #6366f1; }
        .btn-shutdown { position: absolute; top: 20px; right: 20px; background: linear-gradient(135deg, #f97316, #ea580c); color: white; padding: 10px 20px; border: none; border-radius: 8px; cursor: pointer; font-size: 14px; font-weight: 600; transition: all 0.3s; z-index: 10; }
        .btn-shutdown:hover { transform: translateY(-2px); box-shadow: 0 5px 20px rgba(249, 115, 22, 0.4); }
        .loading-overlay { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); z-index: 9999; justify-content: center; align-items: center; }
        .loading-overlay.active { display: flex; }
        .loading-message { background: white; padding: 30px 50px; border-radius: 12px; font-size: 18px; font-weight: 600; color: #1e293b; }
        .btn-browse-dir { background: linear-gradient(135deg, #f59e0b, #d97706); color: white; padding: 18px 40px; border: none; border-radius: 12px; cursor: pointer; font-size: 18px; width: 100%; font-weight: 600; margin-bottom: 20px; transition: all 0.3s; }
        .btn-browse-dir:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(245, 158, 11, 0.4); }
        .btn-browse-dir.selected { background: linear-gradient(135deg, #10b981, #059669); }
        .btn-browse-dir.selected:hover { box-shadow: 0 8px 25px rgba(16, 185, 129, 0.4); }
        .recent-dirs { margin: 20px 0; }
        .recent-title { font-size: 14px; color: #64748b; margin-bottom: 10px; font-weight: 500; }
        .recent-item { background: #f8fafc; border: 2px solid #e2e8f0; padding: 10px 15px; border-radius: 8px; margin-bottom: 8px; cursor: pointer; transition: all 0.2s; display: flex; justify-content: space-between; align-items: center; }
        .recent-item:hover { border-color: #6366f1; background: #f0f3ff; transform: translateX(5px); }
        .recent-path { font-family: 'Consolas', monospace; font-size: 13px; color: #475569; }
        .recent-time { font-size: 11px; color: #94a3b8; }
        .selected-path { background: #f8fafc; border: 2px solid #e2e8f0; padding: 15px; border-radius: 8px; margin-bottom: 20px; color: #475569; font-family: 'Consolas', monospace; font-size: 14px; min-height: 24px; }
        .selected-path.empty { color: #94a3b8; font-style: italic; }
        .btn-scan { background: linear-gradient(135deg, #6366f1, #8b5cf6); color: white; padding: 18px 40px; border: none; border-radius: 12px; cursor: pointer; font-size: 18px; width: 100%; font-weight: 600; transition: all 0.3s; }
        .btn-scan:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(99, 102, 241, 0.4); }
        .btn-scan:disabled { background: #cbd5e1; cursor: not-allowed; transform: none; }
    </style>
</head>
<body>
    <div class="container">
        <button type="button" class="btn-shutdown" onclick="shutdownCleaner()">[OFF] Close Cleaner</button>
        <div class="header">
            <h1>[CLEAN] File Cleaner Bot</h1>
            <p>Portable file cleanup utility with smart categorization</p>
        </div>
        
        <div class="step-indicator">
            <div class="step active">1. Select Directory</div>
            <div class="step inactive">2. Choose File Types</div>
            <div class="step inactive">3. Review & Clean</div>
        </div>
        
        <div class="info-box">
            <p><strong>[DIR] Select a directory to scan</strong><br>
            Choose any directory on your system to analyze for temporary files, logs, and cache that can be safely cleaned.</p>
        </div>
        
        <div class="loading-overlay" id="loadingOverlay">
            <div class="loading-message">Opening folder browser...</div>
        </div>
        
        <button type="button" class="btn-browse-dir" onclick="browseForDirectory()">[BROWSE] Select Directory to Clean</button>
        
        <div id="recentDirs" class="recent-dirs"></div>
        
        <div id="selectedPath" class="selected-path empty">No directory selected</div>
        
        <button type="button" id="scanBtn" class="btn-scan" onclick="scanDirectory()" disabled>[SCAN] Scan Directory</button>
    </div>

    <script>
        let selectedDirectory = '';
        const MAX_RECENT = 5;
        
        // Load and display recent directories
        function loadRecentDirectories() {
            const recent = JSON.parse(localStorage.getItem('recentDirectories') || '[]');
            const container = document.getElementById('recentDirs');
            
            if (recent.length > 0) {
                let html = '<div class="recent-title">Recent Directories:</div>';
                recent.forEach((item, index) => {
                    const timeAgo = getTimeAgo(item.timestamp);
                    const escapedPath = item.path.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
                    html += '<div class="recent-item" onclick="selectRecentDirectory(\'' + escapedPath + '\')">';
                    html += '<span class="recent-path">' + item.path + '</span>';
                    html += '<span class="recent-time">' + timeAgo + '</span>';
                    html += '</div>';
                });
                container.innerHTML = html;
            }
        }
        
        function getTimeAgo(timestamp) {
            const seconds = Math.floor((Date.now() - timestamp) / 1000);
            if (seconds < 60) return 'Just now';
            if (seconds < 3600) return Math.floor(seconds / 60) + 'm ago';
            if (seconds < 86400) return Math.floor(seconds / 3600) + 'h ago';
            return Math.floor(seconds / 86400) + 'd ago';
        }
        
        function selectRecentDirectory(path) {
            selectedDirectory = path;
            document.getElementById('selectedPath').textContent = selectedDirectory;
            document.getElementById('selectedPath').classList.remove('empty');
            document.getElementById('scanBtn').disabled = false;
            document.querySelector('.btn-browse-dir').classList.add('selected');
        }
        
        function saveToRecent(path) {
            let recent = JSON.parse(localStorage.getItem('recentDirectories') || '[]');
            // Remove if already exists
            recent = recent.filter(item => item.path !== path);
            // Add to front
            recent.unshift({ path: path, timestamp: Date.now() });
            // Keep only MAX_RECENT
            recent = recent.slice(0, MAX_RECENT);
            localStorage.setItem('recentDirectories', JSON.stringify(recent));
        }
        
        // Load recent directories on page load
        window.addEventListener('DOMContentLoaded', loadRecentDirectories);
        
        function browseForDirectory() {
            // Show loading overlay to block UI
            document.getElementById('loadingOverlay').classList.add('active');
            
            // Request folder selection from server
            fetch('/browse-folder', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' }
            }).then(response => response.json())
              .then(result => {
                  if (result.success && result.path) {
                      selectedDirectory = result.path;
                      document.getElementById('selectedPath').textContent = selectedDirectory;
                      document.getElementById('selectedPath').classList.remove('empty');
                      document.getElementById('scanBtn').disabled = false;
                      // Change button to green
                      document.querySelector('.btn-browse-dir').classList.add('selected');
                      // Save to recent directories
                      saveToRecent(selectedDirectory);
                      loadRecentDirectories();
                  }
                  // Hide loading overlay
                  document.getElementById('loadingOverlay').classList.remove('active');
              }).catch(err => {
                  console.error('Browse error:', err);
                  // Hide loading overlay on error
                  document.getElementById('loadingOverlay').classList.remove('active');
              });
        }
        
        function scanDirectory() {
            if (!selectedDirectory) {
                alert('Please select a directory first');
                return;
            }
            
            fetch('/scan', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ targetDir: selectedDirectory })
            }).then(response => response.json())
              .then(result => {
                  if (result.success) {
                      location.reload();
                  } else {
                      alert('Error: ' + result.message);
                  }
              });
        }
        
        function shutdownCleaner() {
            fetch('/shutdown', {
                method: 'POST'
            }).then(() => {
                window.close();
            }).catch(() => {
                window.close();
            });
        }
    </script>
</body>
</html>
"@
    return $html
}

# Generate File Type Selection HTML (Step 2)
function Generate-FileTypeSelectionHTML {
    param($ScanSummary)
    
    $categoriesHtml = ""
    foreach ($cat in $ScanSummary.Keys | Sort-Object) {
        $info = $ScanSummary[$cat]
        $checked = if ($info.Count -gt 0) { "checked" } else { "" }
        $categoriesHtml += @"
            <div class="category-card">
                <input type="checkbox" id="cat_$($cat -replace ' ', '')" name="categories" value="$cat" $checked>
                <label for="cat_$($cat -replace ' ', '')">
                    <div class="category-header">
                        <h3>$cat</h3>
                        <span class="badge">$($info.Count) files</span>
                    </div>
                    <p class="category-desc">$($info.Description)</p>
                    <div class="category-stats">
                        <span>[SIZE] $([math]::Round($info.TotalSizeKB/1024, 2)) MB</span>
                        <span>[TIME] $($info.RetentionDays) days</span>
                    </div>
                </label>
            </div>
"@
    }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>File Cleaner Bot - Select File Types</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 50%, #d946ef 100%); min-height: 100vh; }
        .container { max-width: 1000px; margin: 50px auto; background: white; padding: 40px; border-radius: 20px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); }
        .header { text-align: center; margin-bottom: 40px; }
        .header h1 { color: #1e293b; margin: 0 0 10px 0; font-size: 32px; font-weight: 700; }
        .header p { color: #64748b; margin: 0; font-size: 16px; }
        .btn-shutdown { position: absolute; top: 20px; right: 20px; background: linear-gradient(135deg, #f97316, #ea580c); color: white; padding: 10px 20px; border: none; border-radius: 8px; cursor: pointer; font-size: 14px; font-weight: 600; transition: all 0.3s; z-index: 10; }
        .btn-shutdown:hover { transform: translateY(-2px); box-shadow: 0 5px 20px rgba(249, 115, 22, 0.4); }
        .step-indicator { display: flex; justify-content: center; margin-bottom: 40px; gap: 10px; }
        .step { flex: 1; text-align: center; padding: 12px; background: #f1f5f9; border-radius: 8px; font-size: 14px; font-weight: 500; }
        .step.active { background: linear-gradient(135deg, #6366f1, #8b5cf6); color: white; font-weight: 600; }
        .step.completed { background: linear-gradient(135deg, #10b981, #059669); color: white; font-weight: 600; }
        .step.inactive { color: #94a3b8; }
        .info-box { background: linear-gradient(135deg, #fef3c7, #fde68a); border-left: 4px solid #f59e0b; padding: 20px; border-radius: 12px; margin-bottom: 30px; }
        .info-box p { margin: 0; color: #78350f; line-height: 1.6; }
        .info-box strong { color: #f59e0b; }
        .categories-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 20px; margin-bottom: 30px; min-height: 200px; }
        .categories-grid.empty { display: flex; justify-content: center; align-items: center; }
        .empty-state { text-align: center; padding: 60px 40px; background: linear-gradient(135deg, #f0fdf4, #dcfce7); border: 2px dashed #10b981; border-radius: 16px; max-width: 600px; }
        .empty-state h3 { color: #166534; margin: 0 0 15px 0; font-size: 24px; }
        .empty-state p { color: #15803d; margin: 0; line-height: 1.8; font-size: 15px; }
        .empty-state code { background: #fff; padding: 2px 8px; border-radius: 4px; color: #6366f1; font-weight: 600; }
        .category-card { background: #f8f9fa; border-radius: 12px; padding: 20px; border: 3px solid transparent; transition: all 0.3s; position: relative; }
        .category-card:has(input:checked) { border-color: #6366f1; background: #f0f3ff; }
        .category-card input[type="checkbox"] { position: absolute; top: 20px; right: 20px; transform: scale(1.5); cursor: pointer; }
        .category-card label { cursor: pointer; display: block; }
        .category-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; padding-right: 40px; }
        .category-header h3 { margin: 0; color: #1e293b; font-size: 18px; }
        .badge { background: #6366f1; color: white; padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: 600; }
        .category-desc { color: #64748b; font-size: 14px; margin: 10px 0; }
        .category-stats { display: flex; gap: 15px; font-size: 13px; color: #94a3b8; margin-top: 10px; }
        .actions { display: flex; gap: 15px; justify-content: center; }
        .btn { padding: 15px 40px; border: none; border-radius: 12px; cursor: pointer; font-size: 16px; font-weight: 600; transition: all 0.3s; }
        .btn-back { background: #94a3b8; color: white; }
        .btn-back:hover { background: #64748b; transform: translateY(-2px); }
        .btn-continue { background: linear-gradient(135deg, #6366f1, #8b5cf6); color: white; }
        .btn-continue:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(99, 102, 241, 0.4); }
        .target-info { background: linear-gradient(135deg, #dbeafe, #e0e7ff); border: 2px solid #6366f1; padding: 15px; border-radius: 12px; margin-bottom: 30px; text-align: center; }
        .target-info strong { color: #6366f1; }
    </style>
</head>
<body>
    <div class="container">
        <button type="button" class="btn-shutdown" onclick="shutdownCleaner()">[OFF] Close Cleaner</button>
        <div class="header">
            <h1>[CLEAN] File Cleaner Bot</h1>
            <p>Select file types to clean</p>
        </div>
        
        <div class="step-indicator">
            <div class="step completed">[OK] Select Directory</div>
            <div class="step active">2. Choose File Types</div>
            <div class="step inactive">3. Review & Clean</div>
        </div>
        
        <div class="target-info">
            <strong>[TARGET]</strong> $($global:TargetDirectory)
        </div>
        
        <div class="info-box">
            <p><strong>[!] Select file categories to include</strong><br>
            Choose which types of files you want to review for cleanup. You'll see the complete list of files on the next screen before any deletion occurs.</p>
        </div>
        
        <form id="categoryForm" method="post" action="/select-categories">
            <div class="categories-grid" id="categoriesContainer">
                $categoriesHtml
            </div>
            
            <div class="actions">
                <button type="button" class="btn btn-back" onclick="goBack()">[<] Back</button>
                <button type="submit" class="btn btn-continue">Continue to Review [>]</button>
            </div>
        </form>
    </div>

    <script>
        // Check if there are no categories and show fun message
        window.addEventListener('DOMContentLoaded', function() {
            const container = document.getElementById('categoriesContainer');
            const categoryCards = container.querySelectorAll('.category-card');
            
            if (categoryCards.length === 0) {
                container.classList.add('empty');
                container.innerHTML = '<div class="empty-state">' +
                    '<h3>All Clean!</h3>' +
                    '<p>No junk files found here! Your directory is squeaky clean.</p>' +
                    '<p style="margin-top: 15px;">Missing something? Update <code>cleaner_config.yaml</code> to hunt for those mysterious file types!</p>' +
                    '</div>';
            }
        });
        
        function goBack() {
            fetch('/reset', { method: 'POST' })
                .then(() => location.reload());
        }
        
        function shutdownCleaner() {
            fetch('/shutdown', {
                method: 'POST'
            }).then(() => {
                window.close();
            }).catch(() => {
                window.close();
            });
        }
        
        document.getElementById('categoryForm').addEventListener('submit', function(e) {
            e.preventDefault();
            const selected = Array.from(document.querySelectorAll('input[name="categories"]:checked'))
                .map(cb => cb.value);
            
            if (selected.length === 0) {
                alert('Please select at least one file category');
                return;
            }
            
            fetch('/select-categories', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ categories: selected })
            }).then(() => location.reload());
        });
    </script>
</body>
</html>
"@
    return $html
}

# Generate HTML UI (Step 3 - File Review)
function Generate-HTML {
    param($FileData)
    
    $totalFiles = $FileData.Count
    $totalSizeKB = ($FileData | Measure-Object -Property SizeKB -Sum).Sum
    $oldFiles = ($FileData | Where-Object { $_.IsOld }).Count
    $oldSizeKB = ($FileData | Where-Object { $_.IsOld } | Measure-Object -Property SizeKB -Sum).Sum
    
    $categories = $FileData | Group-Object Category
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>File Cleaner Bot</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; margin-bottom: 30px; }
        .header h1 { color: #2c3e50; margin: 0; }
        .header p { color: #7f8c8d; margin: 5px 0; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 30px; }
        .summary-card { background: linear-gradient(135deg, #3498db, #2980b9); color: white; padding: 20px; border-radius: 8px; text-align: center; }
        .summary-card.warning { background: linear-gradient(135deg, #e74c3c, #c0392b); }
        .summary-card.success { background: linear-gradient(135deg, #27ae60, #229954); }
        .summary-card h3 { margin: 0 0 10px 0; font-size: 24px; }
        .summary-card p { margin: 0; opacity: 0.9; }
        .category { margin-bottom: 30px; border: 1px solid #ddd; border-radius: 8px; overflow: hidden; }
        .category-header { background: #34495e; color: white; padding: 15px; cursor: pointer; }
        .category-header:hover { background: #2c3e50; }
        .category-content { display: none; }
        .category-content.active { display: block; }
        .bulk-actions { padding: 15px; background: #ecf0f1; border-bottom: 1px solid #ddd; }
        .bulk-actions button { margin-right: 10px; padding: 8px 15px; border: none; border-radius: 4px; cursor: pointer; }
        .btn-select-all { background: #3498db; color: white; }
        .btn-select-old { background: #e67e22; color: white; }
        .btn-clear { background: #95a5a6; color: white; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); table-layout: fixed; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        th { background: #f8f9fa; font-weight: 600; resize: horizontal; position: relative; }
        th:hover { background: #e9ecef; }
        .col-select { width: 50px; }
        .col-filename { width: 25%; }
        .col-path { width: 35%; }
        .col-size { width: 80px; }
        .col-age { width: 80px; }
        .col-modified { width: 120px; }
        .col-recommendation { width: 20%; }
        tr:hover { background: #f8f9fa; }
        .checkbox { transform: scale(1.2); }
        .old-file { background: #fff5f5; }
        .safe-delete { color: #27ae60; font-weight: bold; }
        .keep-file { color: #e74c3c; font-weight: bold; }
        .actions { position: fixed; bottom: 20px; right: 20px; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 4px 20px rgba(0,0,0,0.15); display: flex; gap: 10px; }
        .btn-back { background: #94a3b8; color: white; padding: 12px 24px; border: none; border-radius: 4px; cursor: pointer; font-size: 16px; }
        .btn-back:hover { background: #64748b; }
        .btn-refresh { background: #3498db; color: white; padding: 12px 24px; border: none; border-radius: 4px; cursor: pointer; font-size: 16px; }
        .btn-refresh:hover { background: #2980b9; }
        .btn-delete { background: #e74c3c; color: white; padding: 12px 24px; border: none; border-radius: 4px; cursor: pointer; font-size: 16px; }
        .btn-delete:hover { background: #c0392b; }
        .btn-close { background: #f39c12; color: white; padding: 12px 24px; border: none; border-radius: 4px; cursor: pointer; font-size: 16px; }
        .btn-close:hover { background: #e67e22; }
        .url-info { background: #d4edda; border: 1px solid #c3e6cb; padding: 10px; border-radius: 4px; margin-bottom: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>File Cleaner Bot</h1>
            <p>Smart file cleanup with backup protection</p>
            <div class="url-info">
                <strong>URL:</strong> http://localhost:$CleanerPort | <strong>Root:</strong> $RootDir
            </div>
        </div>
        
        <div class="summary">
            <div class="summary-card">
                <h3>$totalFiles</h3>
                <p>Total Files Found</p>
            </div>
            <div class="summary-card warning">
                <h3>$oldFiles</h3>
                <p>Files Past Retention</p>
            </div>
            <div class="summary-card success">
                <h3>$([math]::Round($totalSizeKB/1024, 2)) MB</h3>
                <p>Total Size</p>
            </div>
            <div class="summary-card warning">
                <h3>$([math]::Round($oldSizeKB/1024, 2)) MB</h3>
                <p>Potential Space Savings</p>
            </div>
        </div>
        
        <form id="cleanupForm" method="post" action="/cleanup">
"@

        foreach ($category in $categories) {
        $categoryName = $category.Name
        $categoryFiles = $category.Group
        $categoryCount = $categoryFiles.Count
        $categorySize = [math]::Round(($categoryFiles | Measure-Object -Property SizeKB -Sum).Sum / 1024, 2)
        $oldInCategory = ($categoryFiles | Where-Object { $_.IsOld }).Count
        
        $html += @"
        <div class="category">
            <div class="category-header" onclick="toggleCategory('$($categoryName -replace ' ', '')')">
                <strong>$categoryName</strong> ($categoryCount files, $categorySize MB) - $oldInCategory past retention
                <span class="selection-counter" id="counter-$($categoryName -replace ' ', '')" style="color: #3498db; font-weight: bold; margin-left: 10px;"></span>
            </div>
            <div class="category-content" id="$($categoryName -replace ' ', '')">
                <div class="bulk-actions">
                    <button type="button" onclick="selectAllInCategory('$($categoryName -replace ' ', '')')" class="btn-select-all">Select All</button>
                    <button type="button" onclick="selectOldInCategory('$($categoryName -replace ' ', '')')" class="btn-select-old">Select Old Files</button>
                    <button type="button" onclick="clearSelectionInCategory('$($categoryName -replace ' ', '')')" class="btn-clear">Clear Selection</button>
                </div>
                <table>
                    <thead>
                        <tr>
                            <th class="col-select">Select</th>
                            <th class="col-filename">File Name</th>
                            <th class="col-path">Path</th>
                            <th class="col-size">Size (KB)</th>
                            <th class="col-age">Age (Days)</th>
                            <th class="col-modified">Last Modified</th>
                            <th class="col-recommendation">Recommendation</th>
                        </tr>
                    </thead>
                    <tbody>
"@
        
        foreach ($file in $categoryFiles) {
            $rowClass = ""  # Don't mark files as old to prevent auto-selection
            $recClass = if ($file.SafeToDelete) { "safe-delete" } else { "keep-file" }
            $checked = ""  # Always start with unchecked boxes after refresh
            
            $html += @"
                        <tr class="$rowClass">
                            <td><input type="checkbox" class="checkbox category-$($categoryName -replace ' ', '')" name="files" value="$($file.FullPath)" $checked></td>
                            <td>$($file.FileName)</td>
                            <td>$($file.RelativePath)</td>
                            <td>$($file.SizeKB)</td>
                            <td>$($file.Age)</td>
                            <td>$($file.LastModified)</td>
                            <td class="$recClass">$($file.Recommendation)</td>
                        </tr>
"@
        }
        
        $html += @"
                    </tbody>
                </table>
            </div>
        </div>
"@
    }

    $html += @"
        </form>
        
        <div class="actions">
            <button type="button" onclick="goBackToCategories()" class="btn-back">[<] Back to File Types</button>
            <button type="button" onclick="refreshData()" class="btn-refresh">Refresh Data</button>
            <button type="button" onclick="performCleanup()" class="btn-delete">Delete Selected Files</button>
            <button type="button" onclick="closeServer()" class="btn-close">Close Cleaner</button>
        </div>
    </div>

    <script>
        function toggleCategory(categoryId) {
            const content = document.getElementById(categoryId);
            content.classList.toggle('active');
        }
        
        function updateSelectionCounter(categoryId) {
            const checkboxes = document.querySelectorAll('.category-' + categoryId);
            const selectedCount = Array.from(checkboxes).filter(cb => cb.checked).length;
            const counter = document.getElementById('counter-' + categoryId);
            if (counter) {
                if (selectedCount > 0) {
                    counter.textContent = '(' + selectedCount + ' selected for removal)';
                } else {
                    counter.textContent = '';
                }
            }
        }
        
        function selectAllInCategory(categoryId) {
            const checkboxes = document.querySelectorAll('.category-' + categoryId);
            checkboxes.forEach(cb => cb.checked = true);
            updateSelectionCounter(categoryId);
        }
        
        function selectOldInCategory(categoryId) {
            const checkboxes = document.querySelectorAll('.category-' + categoryId);
            checkboxes.forEach(cb => {
                const row = cb.closest('tr');
                cb.checked = row.classList.contains('old-file');
            });
            updateSelectionCounter(categoryId);
        }
        
        function clearSelectionInCategory(categoryId) {
            const checkboxes = document.querySelectorAll('.category-' + categoryId);
            checkboxes.forEach(cb => cb.checked = false);
            updateSelectionCounter(categoryId);
        }
        
        function performCleanup() {
            const selected = document.querySelectorAll('input[name="files"]:checked');
            if (selected.length === 0) {
                alert('No files selected for deletion.');
                return;
            }
            
            const fileList = Array.from(selected).map(cb => cb.value);
            const totalSize = Array.from(selected).reduce((sum, cb) => {
                const row = cb.closest('tr');
                const sizeCell = row.cells[3].textContent;
                return sum + parseFloat(sizeCell);
            }, 0);
            
            if (confirm('Delete ' + selected.length + ' files (' + (totalSize/1024).toFixed(2) + ' MB)?\\n\\nFiles will be backed up before deletion.')) {
                // Send to PowerShell for processing
                fetch('/cleanup', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ files: fileList })
                }).then(response => response.text())
                  .then(result => {
                      alert(result);
                      location.reload();
                  });
            }
        }
        
        // Close server function
        function closeServer() {
            fetch('/shutdown', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' }
            }).then(() => {
                window.close();
            }).catch(() => {
                window.close();
            });
        }
        
        // Go back to file type selection
        function goBackToCategories() {
            fetch('/reset-to-categories', { method: 'POST' })
                .then(() => location.reload());
        }
        
        // Refresh data function
        function refreshData() {
            location.reload();
        }
        
        // Save column widths to localStorage
        function saveColumnWidths() {
            const tables = document.querySelectorAll('table');
            tables.forEach((table, tableIndex) => {
                const widths = {};
                const headers = table.querySelectorAll('th');
                headers.forEach((th, index) => {
                    widths[index] = th.offsetWidth;
                });
                localStorage.setItem('columnWidths_' + tableIndex, JSON.stringify(widths));
            });
        }
        
        // Load column widths from localStorage
        function loadColumnWidths() {
            const tables = document.querySelectorAll('table');
            tables.forEach((table, tableIndex) => {
                const savedWidths = localStorage.getItem('columnWidths_' + tableIndex);
                if (savedWidths) {
                    const widths = JSON.parse(savedWidths);
                    const headers = table.querySelectorAll('th');
                    headers.forEach((th, index) => {
                        if (widths[index]) {
                            th.style.width = widths[index] + 'px';
                        }
                    });
                }
            });
        }
        
        // Make columns resizable
        function makeColumnsResizable() {
            const tables = document.querySelectorAll('table');
            tables.forEach(table => {
                const headers = table.querySelectorAll('th');
                headers.forEach(th => {
                    th.style.position = 'relative';
                    const resizer = document.createElement('div');
                    resizer.style.position = 'absolute';
                    resizer.style.top = '0';
                    resizer.style.right = '0';
                    resizer.style.width = '5px';
                    resizer.style.height = '100%';
                    resizer.style.cursor = 'col-resize';
                    resizer.style.background = 'transparent';
                    
                    let isResizing = false;
                    
                    resizer.addEventListener('mousedown', (e) => {
                        isResizing = true;
                        document.addEventListener('mousemove', handleMouseMove);
                        document.addEventListener('mouseup', () => {
                            isResizing = false;
                            document.removeEventListener('mousemove', handleMouseMove);
                            saveColumnWidths();
                        });
                    });
                    
                    function handleMouseMove(e) {
                        if (!isResizing) return;
                        const rect = th.getBoundingClientRect();
                        const newWidth = e.clientX - rect.left;
                        if (newWidth > 50) {
                            th.style.width = newWidth + 'px';
                        }
                    }
                    
                    th.appendChild(resizer);
                });
            });
        }
        
        // Auto-expand first category and clear all selections
        document.addEventListener('DOMContentLoaded', function() {
            const firstCategory = document.querySelector('.category-content');
            if (firstCategory) firstCategory.classList.add('active');
            loadColumnWidths();
            
            // Clear all checkbox selections on page load
            clearAllSelections();
            
            // Add event listeners to all checkboxes for real-time counter updates
            const allCheckboxes = document.querySelectorAll('input[name="files"]');
            allCheckboxes.forEach(checkbox => {
                checkbox.addEventListener('change', function() {
                    // Extract category from checkbox class
                    const classes = this.className.split(' ');
                    const categoryClass = classes.find(cls => cls.startsWith('category-'));
                    if (categoryClass) {
                        const categoryId = categoryClass.replace('category-', '');
                        updateSelectionCounter(categoryId);
                    }
                });
            });
        });
        
        // Function to clear all selections across all categories
        function clearAllSelections() {
            const allCheckboxes = document.querySelectorAll('input[name="files"]');
            allCheckboxes.forEach(cb => cb.checked = false);
            
            // Update all counters after clearing
            const categories = ['XEFiles', 'TestLogs', 'ExcelReports', 'TempFiles', 'JunkFiles', 'MatrixLogs', 'PythonCache', 'CSVDataFiles', 'BackupFiles'];
            categories.forEach(categoryId => {
                updateSelectionCounter(categoryId);
            });
        }
        
        // Initialize everything when DOM is ready
        makeColumnsResizable();
    </script>
</html>
"@

    return $html
}

# Start HTTP server for UI
function Start-WebServer {
    param($Html, $Port = 8502)
    
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$Port/")
    $listener.Start()
    
    Write-Host "Starting web server on http://localhost:$Port" -ForegroundColor Green
    
    # Auto-open browser
    if (-not $NoUI) {
        Start-Process "http://localhost:$Port"
        Write-Host "Browser should open automatically. If not, visit: http://localhost:$Port" -ForegroundColor Yellow
    }
    
    try {
        while ($listener.IsListening) {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            
            if ($request.Url.AbsolutePath -eq "/") {
                # Determine which screen to show based on session state
                $htmlContent = ""
                
                if ($global:SessionState -eq 'directory_selection' -or -not $global:TargetDirectory) {
                    # Step 1: Directory Selection
                    $htmlContent = Generate-DirectorySelectionHTML
                }
                elseif ($global:SessionState -eq 'file_type_selection') {
                    # Step 2: File Type Selection
                    $scanSummary = @{}
                    foreach ($file in $global:ScanResults) {
                        if (-not $scanSummary.ContainsKey($file.Category)) {
                            $scanSummary[$file.Category] = @{
                                Count = 0
                                TotalSizeKB = 0
                                Description = $file.Description
                                RetentionDays = 30  # Default, will be overridden
                            }
                        }
                        $scanSummary[$file.Category].Count++
                        $scanSummary[$file.Category].TotalSizeKB += $file.SizeKB
                    }
                    $htmlContent = Generate-FileTypeSelectionHTML -ScanSummary $scanSummary
                }
                else {
                    # Step 3: File Review
                    $htmlContent = Generate-HTML -FileData $global:FileAnalysisResults
                }
                
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($htmlContent)
                $response.ContentLength64 = $buffer.Length
                $response.ContentType = "text/html"
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            elseif ($request.Url.AbsolutePath -eq "/browse-folder" -and $request.HttpMethod -eq "POST") {
                # Handle folder browser request
                try {
                    Add-Type -AssemblyName System.Windows.Forms
                    
                    # Create a topmost form to host the dialog
                    $form = New-Object System.Windows.Forms.Form
                    $form.TopMost = $true
                    $form.MinimizeBox = $false
                    $form.MaximizeBox = $false
                    $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
                    $form.ShowInTaskbar = $false
                    
                    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
                    $folderBrowser.Description = "Select directory to clean"
                    $folderBrowser.RootFolder = [System.Environment+SpecialFolder]::MyComputer
                    $folderBrowser.SelectedPath = $CleanerRoot
                    
                    # Show dialog with topmost form as owner
                    $dialogResult = $folderBrowser.ShowDialog($form)
                    
                    $form.Dispose()
                    
                    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
                        $selectedPath = $folderBrowser.SelectedPath
                        $result = @{ success = $true; path = $selectedPath } | ConvertTo-Json
                    } else {
                        $result = @{ success = $false } | ConvertTo-Json
                    }
                } catch {
                    Write-Host "Folder browser error: $_" -ForegroundColor Red
                    $result = @{ success = $false; message = $_.Exception.Message } | ConvertTo-Json
                }
                
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
                $response.ContentLength64 = $buffer.Length
                $response.ContentType = "application/json"
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            elseif ($request.Url.AbsolutePath -eq "/scan" -and $request.HttpMethod -eq "POST") {
                # Handle directory scan request
                $reader = New-Object System.IO.StreamReader($request.InputStream)
                $json = $reader.ReadToEnd()
                $data = $json | ConvertFrom-Json
                
                $targetDir = $data.targetDir
                if (Test-Path $targetDir) {
                    $global:TargetDirectory = $targetDir
                    Write-Host "Scanning directory: $targetDir" -ForegroundColor Yellow
                    $global:ScanResults = Analyze-Files -TargetPath $targetDir
                    $global:SessionState = 'file_type_selection'
                    
                    $result = @{ success = $true } | ConvertTo-Json
                } else {
                    $result = @{ success = $false; message = "Directory not found: $targetDir" } | ConvertTo-Json
                }
                
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
                $response.ContentLength64 = $buffer.Length
                $response.ContentType = "application/json"
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            elseif ($request.Url.AbsolutePath -eq "/select-categories" -and $request.HttpMethod -eq "POST") {
                # Handle category selection
                $reader = New-Object System.IO.StreamReader($request.InputStream)
                $json = $reader.ReadToEnd()
                $data = $json | ConvertFrom-Json
                
                $selectedCategories = $data.categories
                $global:FileAnalysisResults = $global:ScanResults | Where-Object { $selectedCategories -contains $_.Category }
                $global:SessionState = 'file_review'
                
                $buffer = [System.Text.Encoding]::UTF8.GetBytes("OK")
                $response.ContentLength64 = $buffer.Length
                $response.ContentType = "text/plain"
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            elseif ($request.Url.AbsolutePath -eq "/reset" -and $request.HttpMethod -eq "POST") {
                # Reset to directory selection
                $global:TargetDirectory = $null
                $global:ScanResults = $null
                $global:SessionState = 'directory_selection'
                
                $buffer = [System.Text.Encoding]::UTF8.GetBytes("OK")
                $response.ContentLength64 = $buffer.Length
                $response.ContentType = "text/plain"
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            elseif ($request.Url.AbsolutePath -eq "/reset-to-categories" -and $request.HttpMethod -eq "POST") {
                # Reset to file type selection (keep scan results)
                $global:SessionState = 'file_type_selection'
                $global:FileAnalysisResults = $null
                
                $buffer = [System.Text.Encoding]::UTF8.GetBytes("OK")
                $response.ContentLength64 = $buffer.Length
                $response.ContentType = "text/plain"
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            elseif ($request.Url.AbsolutePath -eq "/cleanup" -and $request.HttpMethod -eq "POST") {
                $reader = New-Object System.IO.StreamReader($request.InputStream)
                $json = $reader.ReadToEnd()
                $data = $json | ConvertFrom-Json
                
                # Debug: Log received data
                $debugEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - RECEIVED: $($data.files.Count) files"
                Add-Content -Path $LogFile -Value $debugEntry
                
                # Filter out null, empty, or whitespace-only file paths
                $validFiles = @()
                foreach ($file in $data.files) {
                    if (-not [string]::IsNullOrWhiteSpace($file)) {
                        $validFiles += $file.ToString().Trim()
                    }
                }
                
                $debugEntry2 = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - VALID: $($validFiles.Count) files after filtering"
                Add-Content -Path $LogFile -Value $debugEntry2
                
                $result = Perform-Cleanup -FilePaths $validFiles
                
                # Re-analyze files after cleanup to refresh the data
                $global:FileAnalysisResults = Analyze-Files
                
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
                $response.ContentLength64 = $buffer.Length
                $response.ContentType = "text/plain"
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            elseif ($request.Url.AbsolutePath -eq "/shutdown" -and $request.HttpMethod -eq "POST") {
                $buffer = [System.Text.Encoding]::UTF8.GetBytes("Server shutting down...")
                $response.ContentLength64 = $buffer.Length
                $response.ContentType = "text/plain"
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.Close()
                break
            }
            
            $response.Close()
        }
    }
    finally {
        $listener.Stop()
    }
}

# Generate .gitignore patterns for temporary files
function Get-GitIgnorePatterns {
    $patterns = @()
    
    # Temporary files
    $patterns += "*.pid"
    $patterns += "*.coverage"
    $patterns += "*.tmp"
    $patterns += "*.temp"
    
    # XE files (keep recent ones but ignore old ones)
    $patterns += "monitor/xe/*.xel"
    
    # Log files in specific directories
    $patterns += "logs/**/*.log"
    $patterns += "logs/**/*.out"
    $patterns += "py/logs/*.log"
    $patterns += "tests/results/*.log"
    
    # Python cache and artifacts
    $patterns += "py/.benchmarks/"
    $patterns += "py/.pytest_cache/"
    $patterns += "**/*.pyc"
    $patterns += "**/*.pyo"
    $patterns += "**/__pycache__/"
    
    # Large trace files
    $patterns += "**/*.trc"
    $patterns += "**/*.tdf"
    
    # Backup directories
    $patterns += "_Backup/"
    $patterns += "File_cleaner_bot/logs/"
    
    return $patterns
}

# Create temporary .gitignore for upload
function New-UploadGitIgnore {
    param([string]$TempIgnoreFile)
    
    $patterns = Get-GitIgnorePatterns
    $content = @"
# Temporary .gitignore for clean uploads
# Generated by LoadTest File Cleaner Bot
# This excludes temporary and log files during upload

"@
    
    $content += "`n" + ($patterns -join "`n")
    
    Set-Content -Path $TempIgnoreFile -Value $content -Encoding UTF8
    return $patterns.Count
}

# Perform actual cleanup with backup
function Perform-Cleanup {
    param([string[]]$FilePaths)
    
    # Debug: Log what we received
    $debugEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - CLEANUP FUNCTION: Received $($FilePaths.Count) file paths"
    Add-Content -Path $LogFile -Value $debugEntry
    
    if ($FilePaths.Count -eq 0) {
        return "No files selected for cleanup."
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $targetName = if ($global:TargetDirectory) { 
        Split-Path $global:TargetDirectory -Leaf 
    } else { 
        "Unknown" 
    }
    $backupDir = Join-Path $CleanerRoot "_FileCleaner_Backup"
    
    # Create backup directory if it doesn't exist
    if (!(Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    
    $backupFile = Join-Path $backupDir "Backup_${targetName}_${timestamp}.zip"
    $deletedFiles = @()
    $errors = @()
    
    try {
        # Create backup archive
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::Open($backupFile, 'Create')
        
        foreach ($filePath in $FilePaths) {
            # Debug: Log each file path as we process it
            $debugPath = if ($filePath) { $filePath.ToString() } else { "NULL" }
            $debugEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - PROCESSING: '$debugPath'"
            Add-Content -Path $LogFile -Value $debugEntry
            
            # Skip null, empty, or whitespace-only paths
            if ([string]::IsNullOrWhiteSpace($filePath)) {
                $errors += "Skipped null or empty file path: '$debugPath'"
                continue
            }
            
            # Store original path to prevent corruption
            $originalPath = $filePath.ToString()
            
            if (Test-Path $originalPath) {
                try {
                    # Check if it's a directory or file
                    if (Test-Path $originalPath -PathType Container) {
                        # Handle directory - skip backup, just delete
                        Remove-Item -LiteralPath $originalPath -Force -Recurse
                        $deletedFiles += $originalPath
                        
                        # Log the action
                        $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - DELETED DIRECTORY: $originalPath (no backup - directory)"
                        Add-Content -Path $LogFile -Value $logEntry
                    }
                    else {
                        # Handle file - backup then delete
                        # Use target directory for relative path, or fall back to original path's directory
                        $baseDir = if ($global:TargetDirectory) { $global:TargetDirectory } else { Split-Path $originalPath -Parent }
                        $relativePath = $originalPath.Replace($baseDir, "").TrimStart('\')
                        if ([string]::IsNullOrWhiteSpace($relativePath)) {
                            $relativePath = Split-Path $originalPath -Leaf
                        }
                        $entry = $zip.CreateEntry($relativePath)
                        
                        # Use using statement pattern for proper disposal
                        $entryStream = $entry.Open()
                        try {
                            $fileStream = [System.IO.File]::OpenRead($originalPath)
                            try {
                                $fileStream.CopyTo($entryStream)
                            }
                            finally {
                                $fileStream.Close()
                            }
                        }
                        finally {
                            $entryStream.Close()
                        }
                        
                        # Delete original file using stored path
                        Remove-Item -LiteralPath $originalPath -Force
                        $deletedFiles += $originalPath
                        
                        # Log the action
                        $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - DELETED: $originalPath (backed up to $backupFile)"
                        Add-Content -Path $LogFile -Value $logEntry
                    }
                }
                catch {
                    $errors += "Failed to process ${originalPath}: $($_.Exception.Message)"
                }
            }
            else {
                $errors += "File not found: $originalPath"
            }
        }
        
        $zip.Dispose()
        
        $result = "Cleanup completed successfully!`n"
        $result += "Files deleted: $($deletedFiles.Count)`n"
        $result += "Backup created: $backupFile`n"
        
        if ($errors.Count -gt 0) {
            $result += "`nErrors encountered:`n" + ($errors -join "`n")
        }
        
        return $result
    }
    catch {
        return "Cleanup failed: $($_.Exception.Message)"
    }
}

# Main execution
if (-not $NoUI) {
    Write-Host "Analyzing LoadTest files..." -ForegroundColor Yellow
    Write-Host "Debug: Scanning root directory: $RootDir" -ForegroundColor Cyan
    $fileData = Analyze-Files

    Write-Host "Debug: Found $($fileData.Count) files for analysis" -ForegroundColor Cyan
    
    if ($fileData.Count -eq 0) {
        Write-Host "`nNo residual files found for cleanup!" -ForegroundColor Green
        Write-Host "`nDiagnostic Information:" -ForegroundColor Yellow
        Write-Host "  Paths checked: $($script:PathDiagnostics.PathsChecked)" -ForegroundColor Cyan
        Write-Host "  Paths found: $($script:PathDiagnostics.PathsFound)" -ForegroundColor Cyan
        Write-Host "  Paths missing: $($script:PathDiagnostics.PathsMissing.Count)" -ForegroundColor Cyan
        
        Write-Host "`nThis is normal for a fresh installation!" -ForegroundColor Green
        Write-Host "Opening web interface anyway - you can refresh it after running tests..." -ForegroundColor Yellow
    }
    else {
        Write-Host "Found $($fileData.Count) files for review" -ForegroundColor Green
    }
    
    Write-Host "Starting web interface on http://localhost:$CleanerPort ..." -ForegroundColor Yellow
    
    # Store file data globally for web server access
    $global:FileAnalysisResults = $fileData
    $html = Generate-HTML -FileData $fileData
    Start-WebServer -Html $html -Port $CleanerPort
}
else {
    # Command line mode
    Write-Host "Analyzing LoadTest files..." -ForegroundColor Yellow
    $fileData = Analyze-Files
    
    if ($fileData.Count -eq 0) {
        Write-Host "`nNo residual files found for cleanup!" -ForegroundColor Green
        Write-Host "`nDiagnostic Information:" -ForegroundColor Yellow
        Write-Host "  Paths checked: $($script:PathDiagnostics.PathsChecked)" -ForegroundColor Cyan
        Write-Host "  Paths found: $($script:PathDiagnostics.PathsFound)" -ForegroundColor Cyan
        Write-Host "  Paths missing: $($script:PathDiagnostics.PathsMissing.Count)" -ForegroundColor Cyan
        
        if ($script:PathDiagnostics.PathsMissing.Count -gt 0) {
            Write-Host "`nMissing directories (will be created when you run tests):" -ForegroundColor Yellow
            $script:PathDiagnostics.PathsMissing | Select-Object -First 10 | ForEach-Object {
                $relativePath = $_.Replace($RootDir, '').TrimStart('\')
                Write-Host "  - $relativePath" -ForegroundColor Gray
            }
            if ($script:PathDiagnostics.PathsMissing.Count -gt 10) {
                Write-Host "  ... and $($script:PathDiagnostics.PathsMissing.Count - 10) more" -ForegroundColor Gray
            }
        }
        
        Write-Host "`nThis is normal for a fresh installation!" -ForegroundColor Green
        Write-Host "The File Cleaner Bot will find files after you:" -ForegroundColor White
        Write-Host "  1. Run load tests (creates .log, .out files)" -ForegroundColor White
        Write-Host "  2. Generate Extended Events data (creates .xel files)" -ForegroundColor White
        Write-Host "  3. Create performance reports (creates .xlsx files)" -ForegroundColor White
        Write-Host "  4. Run Python tests (creates cache and coverage files)" -ForegroundColor White
    }
    else {
        Write-Host "`nFound $($fileData.Count) files for review:" -ForegroundColor Green
        $fileData | Format-Table -AutoSize
    }
}
