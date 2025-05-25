<# 
The compressed software binary file is called software.zip.
Paths need to be updated for each application.
If this file changes, you have to re-create the Custom Image Template.
This script is not updated in a CIT after the Custom Image Templates first run.
No parameters are used in this script.  All variables are set in the script.
This script was tested on Windows 11 Enterprise multi-session 23H2

Author: Travis Roberts
Date: May 10, 2025
Version: 1.0
Copyright (c) 2025 Travis Roberts

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>

#region Variables
# path to the software.zip archive file with the application binaries.  Must be publicly accessible, suggest using a SAS URL on a blob storage account.
$archiveSource = "<path to your archive source>"
$logDir = "c:\CITLog"
$azCopyDir = 'c:\CustomImageTemplate'
#endregion


#region LogFile
# Check if the log directory exists, if not create it
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir
}
# Create the log file with the current date
$logFile = Join-Path $logDir "$(get-date -format 'yyyyMMdd')_softwareinstall.log"
function Write-Log {
    Param($message)
    Write-Output "$(get-date -format 'yyyyMMdd HH:mm:ss') $message" | Out-File -Encoding utf8 $logFile -Append
}
#endregion

#region Download AZCopy
# The following commands download and install AZCopy.
# AZCopy is used to download the archive file from the <ArchiveSource> location.
# Check for the azCopyDir directory, if not create it
try {
    if (-not (Test-Path $azCopyDir)) {
        New-Item -ItemType Directory -Path $azCopyDir -ErrorAction Stop
        Write-Log "Created the $azCopyDir directory"
    }
    else {
        Write-Log "The $azCopyDir directory already exists"
    }  
}   
catch {
    Write-Log "Error creating the $azCopyDir directory: $($_.Exception.Message)"
}

# Download the AZCopy zip file and extract it to the Custom Image Template directory
try {
    invoke-webrequest -uri 'https://aka.ms/downloadazcopy-v10-windows' -OutFile "$azCopyDir\azcopy.zip" -ErrorAction Stop
    Expand-Archive "$azCopyDir\azcopy.zip" $azCopyDir -ErrorAction Stop
    copy-item "$azCopyDir\azcopy_windows_amd64_*\azcopy.exe\" -Destination $azCopyDir -ErrorAction Stop
    Write-Log "AZCopy downloaded and extracted successfully"
}
catch {
    Write-Log "Error downloading or extracting AZCopy: $($_.Exception.Message)"
}

# Command that uses AZCopy to download the archive file and extract to the Custom Image Template directory
# Use the SAS URL for the <ArchiveSource>
try {
    &${azCopyDir}\azcopy.exe copy $archiveSource ${azCopyDir}\software.zip 
    Expand-Archive "$azCopyDir\software.zip" $azCopyDir -ErrorAction Stop
    Write-Log "Archive file downloaded and extracted successfully"
}
catch {
    Write-Log "Error downloading or extracting the archive file: $($_.Exception.Message)"
}

#endregion


#region Notepad++ .exe
# Tested, no updater working as expected
try {
    Start-Process -filepath 'c:\CustomImageTemplate\NotepadPP\npp.8.8.1.Installer.x64.exe' -Wait -ErrorAction Stop -ArgumentList '/S', '/noUpdater'
    if (Test-Path "C:\Program Files\Notepad++\notepad++.exe") {
        Write-Log "Notepad++ has been installed"
    }
    else {
        Write-Log "Error locating the Notepad++ executable"
    }
}
catch {
    $ErrorMessage = $_.Exception.message
    Write-Log "Error installing Notepad++: $ErrorMessage"
}
# Check if NotepadPlusPlus per-user AppPackage is installed and remove it
# Prevents Sysprep.exe from finishing
try {
    $appPackage = Get-AppxPackage -Name  NotepadPlusPlus 
    if ($appPackage) {
        Remove-AppxPackage -Package $appPackage.PackageFullName -ErrorAction Stop
        Write-Log "NotepadPlusPlus per-user AppPackage removed successfully"
    }
    else {
        Write-Log "NotepadPlusPlus per-user AppPackage not found"
    }
}
catch {
    Write-Log "Error removing NotepadPlusPlus per-user AppPackage: $($_.Exception.Message)"
}

#endregion


#region 7-Zip .msi
try {
     Start-Process -filepath msiexec.exe -Wait -ErrorAction Stop -ArgumentList '/i', 'C:\CustomImageTemplate\7zip\7z2409-x64.msi', '/quiet' 
    if (Test-Path "C:\Program Files\7-Zip\7z.exe") {
        Write-Log "7-Zip has been installed"
    }
    else {
        write-log "Error locating the 7-Zip executable"
    }
}
catch {
    $ErrorMessage = $_.Exception.message
    write-log "Error installing 7-Zip: $ErrorMessage"
}
#endregion

#region Chocolatey
# Install Chocolatey
# Check if Chocolatey is already installed and install if not with logging
try {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Log "Installing Chocolatey"
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }
    else {
        Write-Log "Chocolatey is already installed"
    }
}
catch {
    Write-Log "Error installing Chocolatey: $($_.Exception.Message)"
}
# Install Chrome with Chocolatey with logging
try {
    Write-Log "Installing Google Chrome with Chocolatey"
    $chromeInstall = choco install googlechrome --yes --ignore-checksums --no-progress --log-level=error
    Write-Log $chromeInstall 
    if (Test-Path "C:\Program Files\Google\Chrome\Application\chrome.exe") {
        Write-Log "Google Chrome has been installed successfully"
    }
    else {
        Write-Log "Error verifying the installation of Google Chrome"
    }
}
catch {
    Write-Log "Error installing Google Chrome: $($_.Exception.Message)"
}
#endregion
