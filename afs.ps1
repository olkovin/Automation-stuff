# File: afs.ps1
# made by t.me/olekovin
# and ofc a brave and smart claude.ai and copilot

# Функція для зчитування конфігураційного файлу
function Read-Config {
    param (
        [string]$ConfigPath = "config.ini"
    )
    $config = @{}
    if (Test-Path $ConfigPath) {
        Get-Content $ConfigPath | ForEach-Object {
            if ($_ -match "^\s*([^#].*?)\s*=\s*(.*?)\s*$") {
                $config[$Matches[1]] = $Matches[2]
            }
        }
    } else {
        Write-Host "Config file not found: $ConfigPath"
    }
    return $config
}

# Функція для локалізації
function Get-LocalizedString {
    param (
        [string]$Key,
        [string]$Lang = "UA"
    )
    $strings = @{
        "UA" = @{
            "StartScript" = "Початок виконання скрипта"
            "EndScript" = "Завершення виконання скрипта"
            "FileProcessed" = "Оброблено файл:"
            "ErrorOccurred" = "Виникла помилка:"
            "FileIgnored" = "Проігноровано файл:"
            "ConfigLoaded" = "Завантажено конфігурацію:"
            "NoFilesFound" = "Файлів для обробки не знайдено"
            "TaskCreated" = "Створено завдання в планувальнику:"
            "TaskRemoved" = "Видалено завдання з планувальника:"
            "TaskExists" = "Завдання вже існує в планувальнику:"
            "TaskNotFound" = "Завдання не знайдено в планувальнику:"
            "TestFilesGenerated" = "Згенеровано тестові файли:"
            "ConfigFileGenerated" = "Згенеровано конфігураційний файл:"
        }
        "EN" = @{
            "StartScript" = "Script execution started"
            "EndScript" = "Script execution completed"
            "FileProcessed" = "Processed file:"
            "ErrorOccurred" = "An error occurred:"
            "FileIgnored" = "Ignored file:"
            "ConfigLoaded" = "Configuration loaded:"
            "NoFilesFound" = "No files found for processing"
            "TaskCreated" = "Task created in scheduler:"
            "TaskRemoved" = "Task removed from scheduler:"
            "TaskExists" = "Task already exists in scheduler:"
            "TaskNotFound" = "Task not found in scheduler:"
            "TestFilesGenerated" = "Test files generated:"
            "ConfigFileGenerated" = "Configuration file generated:"
        }
    }
    return $strings[$Lang][$Key]
}

# Функція для логування
function Write-Log {
    param (
        [string]$Message,
        [string]$LogPath,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    $logFileName = "log_" + (Get-Date -Format "dd-MM-yyyy") + ".txt"
    $fullLogPath = Join-Path (Split-Path $LogPath) $logFileName
    
    if (-not (Test-Path (Split-Path $fullLogPath))) {
        New-Item -ItemType Directory -Path (Split-Path $fullLogPath) -Force | Out-Null
    }
    Add-Content -Path $fullLogPath -Value $logMessage
    if ($config.admin_mode -eq "true" -or $config.interval -eq "once") {
        Write-Host $logMessage
    }
}

# Функція для створення структури папок
function Create-FolderStructure {
    param (
        [DateTime]$Date,
        [string]$BaseFolder,
        [string]$NamingPattern,
        [string]$Lang
    )
    $year = $Date.Year
    $month = if ($NamingPattern -like "*month*") {
        (Get-Culture).DateTimeFormat.GetMonthName($Date.Month)
    } else {
        $Date.Month.ToString("00")
    }
    $day = $Date.Day.ToString("00")
    
    $folderPath = Join-Path -Path $BaseFolder -ChildPath $year
    $folderPath = Join-Path -Path $folderPath -ChildPath $month
    $folderPath = Join-Path -Path $folderPath -ChildPath $day
    
    if (-not (Test-Path $folderPath)) {
        New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
    }
    
    return $folderPath
}

# Функція для додавання завдання в планувальник
function Add-SchedulerTask {
    param (
        [string]$TaskName,
        [string]$ScriptPath,
        [string]$Interval,
        [int]$RepetitiveInterval
    )
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$ScriptPath`""
    
    switch ($Interval) {
        "on-boot" {
            $trigger = New-ScheduledTaskTrigger -AtStartup
        }
        "repetetive" {
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Seconds $RepetitiveInterval)
        }
        "once" {
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date)
        }
        default {
            throw "Invalid scheduler interval"
        }
    }
    
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskName -Description "AutoFileSorter Task"
}

# Функція для видалення завдання з планувальника
function Remove-SchedulerTask {
    param (
        [string]$TaskName
    )
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        return $true
    }
    return $false
}

# Функція для перевірки наявності завдання в планувальнику
function Test-SchedulerTask {
    param (
        [string]$TaskName
    )
    return Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}

# Функція для видалення старих логів
function Remove-OldLogs {
    param (
        [string]$LogPath,
        [int]$DaysToKeep
    )
    $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
    Get-ChildItem -Path (Split-Path $LogPath) -Filter "log_*.txt" | 
        Where-Object { $_.LastWriteTime -lt $cutoffDate } | 
        Remove-Item -Force
}

# Функція для обробки відносних шляхів
function Resolve-RelativePath {
    param (
        [string]$Path,
        [string]$BasePath
    )
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    } else {
        return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($BasePath, $Path))
    }
}

# Основна функція сортування файлів
function Sort-Files {
    param (
        [hashtable]$Config
    )
    $lang = $Config.script_processing_lang
    $logPath = if ($Config.log_path) { $Config.log_path } else { Join-Path $PSScriptRoot "script_logs\log.txt" }
    
    Write-Log -Message (Get-LocalizedString -Key "StartScript" -Lang $lang) -LogPath $logPath
    Write-Log -Message "$((Get-LocalizedString -Key "ConfigLoaded" -Lang $lang)) $($Config | Out-String)" -LogPath $logPath
    
    $srcPath = if ($Config.src_path) { 
        Resolve-RelativePath -Path $Config.src_path -BasePath $PSScriptRoot 
    } else { 
        $PSScriptRoot 
    }
    
    $dstPath = if ($Config.dst_path) { 
        Resolve-RelativePath -Path $Config.dst_path -BasePath $PSScriptRoot 
    } else { 
        $srcPath 
    }
    
    Write-Log -Message "Source path: $srcPath" -LogPath $logPath
    Write-Log -Message "Destination path: $dstPath" -LogPath $logPath
    
    $searchParams = @{
        Path = $srcPath
        Recurse = $true
    }
    
    if ($Config.search_filter_type -eq "extension") {
        $searchParams.Add("Include", "*.$($Config.search_filter)")
    } elseif ($Config.search_filter_type -eq "name-regex") {
        $searchParams.Add("Filter", "*")
    } else {
        throw "Invalid search_filter_type"
    }
    
    $files = Get-ChildItem @searchParams | Where-Object { $_.Name -ne $Config.config_file_name }
    
    if ($files.Count -eq 0) {
        Write-Log -Message (Get-LocalizedString -Key "NoFilesFound" -Lang $lang) -LogPath $logPath
        return
    }
    
    foreach ($file in $files) {
        if ($Config.search_filter_type -eq "name-regex" -and $file.Name -notmatch $Config.search_filter) {
            Write-Log -Message "$((Get-LocalizedString -Key "FileIgnored" -Lang $lang)) $($file.Name)" -LogPath $logPath -Level "INFO"
            continue
        }
        
        # Отримання дати з імені файлу
        if ($file.Name -match '_(\d{6})') {
            $dateString = $Matches[1]
            $year = "20" + $dateString.Substring(0, 2)
            $month = $dateString.Substring(2, 2)
            $day = $dateString.Substring(4, 2)
            $fileDate = [DateTime]::ParseExact("$year$month$day", "yyyyMMdd", $null)
        } else {
            $fileDate = $file.LastWriteTime
        }
        
        $destinationFolder = Create-FolderStructure -Date $fileDate -BaseFolder $dstPath -NamingPattern $Config.destination_naming_pattern -Lang $lang
        $destinationPath = Join-Path -Path $destinationFolder -ChildPath $file.Name
        
        try {
            Move-Item -Path $file.FullName -Destination $destinationPath -Force
            Write-Log -Message "$((Get-LocalizedString -Key "FileProcessed" -Lang $lang)) $($file.Name)" -LogPath $logPath -Level "INFO"
        } catch {
            Write-Log -Message "$((Get-LocalizedString -Key "ErrorOccurred" -Lang $lang)) $($_.Exception.Message)" -LogPath $logPath -Level "ERROR"
        }
    }
    
    Write-Log -Message (Get-LocalizedString -Key "EndScript" -Lang $lang) -LogPath $logPath
}

# Функція для генерації тестових файлів
function Generate-TestFiles {
    param (
        [string]$Directory
    )
    $testFiles = @(
        @{Name="0314_2410111145113_001.jpg"; Date="2024-10-11T15:51:00"},
        @{Name="0313_2410111445454_001.jpg"; Date="2024-10-11T15:45:00"},
        @{Name="0312_2409111429506_001.jpg"; Date="2024-09-11T15:29:00"},
        @{Name="0311_2409111440957_001.jpg"; Date="2024-09-11T15:10:00"},
        @{Name="0310_2408111131747_001.jpg"; Date="2024-08-11T14:17:00"},
        @{Name="0309_2408111130739_001.jpg"; Date="2024-08-11T14:07:00"},
        @{Name="0308_2407111125446_001.jpg"; Date="2024-07-11T13:54:00"},
        @{Name="0307_2407111129939_001.jpg"; Date="2024-07-11T13:39:00"},
        @{Name="0300_2410110723909_001.jpg"; Date="2024-10-11T08:39:00"}
    )

    foreach ($file in $testFiles) {
        $filePath = Join-Path -Path $Directory -ChildPath $file.Name
        New-Item -ItemType File -Path $filePath -Force | Out-Null
        $fileDate = [datetime]::ParseExact($file.Date, "yyyy-MM-ddTHH:mm:ss", $null)
        (Get-Item $filePath).CreationTime = $fileDate
        (Get-Item $filePath).LastWriteTime = $fileDate
    }

    return $testFiles.Count
}

# Функція для генерації конфігураційного файлу за замовчуванням
function Generate-DefaultConfig {
    param (
        [string]$ConfigPath
    )
    $defaultConfig = @"
# Configuration file for AutoFileSorter script

# Language for script processing and logging (UA for Ukrainian, EN for English)
script_processing_lang=EN

# Type of search filter (extension or name-regex)
search_filter_type=extension

# Value for the search filter (e.g., jpg for extension, or regex pattern for name-regex)
search_filter=jpg

# Source path to search for files
# You can use absolute path: C:\Users\YourName\Documents\FilesToSort
# Or relative path: .\FilesToSort or ..\FilesToSort
# Leave empty for current directory
src_path=

# Destination path to place sorted files
# You can use absolute path: D:\SortedFiles
# Or relative path: .\SortedFiles or ..\SortedFiles
# Leave empty for current directory
dst_path=

# Pattern for naming destination folders (yyyy for year, MM for month, dd for day)
destination_naming_pattern=yyyy.MM.dd

# Enable debug mode for detailed logging (true or false)
debug=true

# Scheduler action (add, remove, or check)
scheduler=

# Interval for scheduled runs (once, on-boot, or repetetive)
interval=once

# Interval in seconds for repetitive scheduling
repetetive_interval=3600

# Path for the log file (leave empty for default location)
log_path=

# Name of this configuration file
config_file_name=config.ini

# Enable admin mode (true or false)
admin_mode=false

# Number of days to keep logs before removing
remove_logs_older_than=30
"@

    Set-Content -Path $ConfigPath -Value $defaultConfig
}

# Функція для відображення адміністративного меню
function Show-AdminMenu {
    param (
        [hashtable]$Config,
        [bool]$IsConfigMissing
    )
    $lang = $Config.script_processing_lang
    $taskName = "AutoFileSorter"

    while ($true) {
        Clear-Host
        Write-Host "Sort script admin menu, please choose action:"
        Write-Host "1. Enable/Disable Scheduler run"
        Write-Host "2. Check Scheduler run status"
        Write-Host "3. Generate test files in source directory"
        Write-Host "4. Generate default config file in current directory"
        Write-Host "5. Run file sorting script"
        Write-Host "6. Exit"

        $choice = Read-Host "Enter your choice (1-6)"

        switch ($choice) {
            "1" {
                if ($IsConfigMissing) {
                    Write-Host "Error: Cannot enable scheduler without a configuration file. Please create a config file first (option 4)." -ForegroundColor Red
                } else {
                    $task = Test-SchedulerTask -TaskName $taskName
                    if ($task) {
                        $confirm = Read-Host "Task is currently enabled. Do you want to disable it? (Y/N)"
                        if ($confirm -eq "Y") {
                            Remove-SchedulerTask -TaskName $taskName
                            Write-Host "$((Get-LocalizedString -Key "TaskRemoved" -Lang $lang)) $taskName"
                        }
                    } else {
                        $confirm = Read-Host "Task is currently disabled. Do you want to enable it? (Y/N)"
                        if ($confirm -eq "Y") {
                            Add-SchedulerTask -TaskName $taskName -ScriptPath $PSCommandPath -Interval $Config.interval -RepetitiveInterval $Config.repetetive_interval
                            Write-Host "$((Get-LocalizedString -Key "TaskCreated" -Lang $lang)) $taskName"
                        }
                    }
                }
                Pause
            }
            "2" {
                $task = Test-SchedulerTask -TaskName $taskName
                if ($task) {
                    Write-Host "$((Get-LocalizedString -Key "TaskExists" -Lang $lang)) $taskName"
                    Write-Host "Task details:"
                    $task | Format-List
                } else {
                    Write-Host "$((Get-LocalizedString -Key "TaskNotFound" -Lang $lang)) $taskName"
                }
                Pause
            }
            "3" {
                $srcPath = if ($Config.src_path) { 
                    Resolve-RelativePath -Path $Config.src_path -BasePath $PSScriptRoot 
                } else { 
                    $PSScriptRoot 
                }
                $fileCount = Generate-TestFiles -Directory $srcPath
                Write-Host "$((Get-LocalizedString -Key "TestFilesGenerated" -Lang $lang)) $fileCount"
                Write-Host "Files created in: $srcPath"
                Pause
            }
            "4" {
                $configPath = Join-Path -Path $PSScriptRoot -ChildPath "config.ini"
                Generate-DefaultConfig -ConfigPath $configPath
                Write-Host "$((Get-LocalizedString -Key "ConfigFileGenerated" -Lang $lang)) $configPath"
                $IsConfigMissing = $false
                Pause
            }
            "5" {
                if ($IsConfigMissing) {
                    Write-Host "Error: Cannot run the script without a configuration file. Please create a config file first (option 4)." -ForegroundColor Red
                } else {
                    Write-Host "Running file sorting script..."
                    Sort-Files -Config $Config
                    Write-Host "File sorting completed."
                }
                Pause
            }
            "6" {
                return
            }
            default {
                Write-Host "Invalid choice. Please try again."
                Pause
            }
        }
    }
}

# Головна логіка скрипта
try {
    $configPath = Join-Path -Path $PSScriptRoot -ChildPath "config.ini"
    $isConfigMissing = -not (Test-Path $configPath)
    
    if ($isConfigMissing) {
        Write-Host "Config file not found. Starting in administrative mode."
        Write-Host "Please create a config file to start using the script."
        $config = @{
            "admin_mode" = "true"
            "script_processing_lang" = "EN"
            "remove_logs_older_than" = "30"
            "src_path" = ""
            "dst_path" = ""
        }
    } else {
        $config = Read-Config -ConfigPath $configPath
    }
    
    $taskName = "AutoFileSorter"
    
    if (-not $isConfigMissing) {
        $logPath = if ($config.log_path) { $config.log_path } else { Join-Path $PSScriptRoot "script_logs\log.txt" }
        Remove-OldLogs -LogPath $logPath -DaysToKeep ([int]$config.remove_logs_older_than)
    }
    
    if ($config.admin_mode -eq "true") {
        Show-AdminMenu -Config $config -IsConfigMissing $isConfigMissing
    } else {
        if ($config.scheduler -eq "add") {
            if (-not (Test-SchedulerTask -TaskName $taskName)) {
                Add-SchedulerTask -TaskName $taskName -ScriptPath $PSCommandPath -Interval $config.interval -RepetitiveInterval $config.repetetive_interval
                Write-Log -Message "$((Get-LocalizedString -Key "TaskCreated" -Lang $config.script_processing_lang)) $taskName" -LogPath $logPath
            } else {
                Write-Log -Message "$((Get-LocalizedString -Key "TaskExists" -Lang $config.script_processing_lang)) $taskName" -LogPath $logPath
            }
        } elseif ($config.scheduler -eq "remove") {
            if (Remove-SchedulerTask -TaskName $taskName) {
                Write-Log -Message "$((Get-LocalizedString -Key "TaskRemoved" -Lang $config.script_processing_lang)) $taskName" -LogPath $logPath
            } else {
                Write-Log -Message "$((Get-LocalizedString -Key "TaskNotFound" -Lang $config.script_processing_lang)) $taskName" -LogPath $logPath
            }
        } elseif ($config.scheduler -eq "check") {
            $task = Test-SchedulerTask -TaskName $taskName
            if ($task) {
                Write-Log -Message "$((Get-LocalizedString -Key "TaskExists" -Lang $config.script_processing_lang)) $taskName" -LogPath $logPath
                Write-Log -Message "Task details: $($task | Out-String)" -LogPath $logPath
            } else {
                Write-Log -Message "$((Get-LocalizedString -Key "TaskNotFound" -Lang $config.script_processing_lang)) $taskName" -LogPath $logPath
            }
        }
        
        Sort-Files -Config $config
    }
} catch {
    $logPath = if ($config.log_path) { $config.log_path } else { Join-Path $PSScriptRoot "script_logs\log.txt" }
    Write-Log -Message "$((Get-LocalizedString -Key "ErrorOccurred" -Lang $config.script_processing_lang)) $($_.Exception.Message)" -LogPath $logPath -Level "ERROR"
}

# Затримка перед закриттям консолі (тільки якщо в режимі адміністратора або при одноразовому запуску)
if ($config.admin_mode -eq "true" -or $config.interval -eq "once") {
    Write-Host "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}