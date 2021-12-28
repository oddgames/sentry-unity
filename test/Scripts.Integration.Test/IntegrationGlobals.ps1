$ErrorActionPreference = "Stop"

function ProjectRoot 
{
    if ($null -ne $Global:NewProjectPathCache)
    {
        return [string]$Global:NewProjectPathCache
    }
    $Global:NewProjectPathCache = (Get-Item .).FullName
    return [string]$Global:NewProjectPathCache
}

function GetTestAppName
{
    If ($IsMacOS)
    {
        return "test.app"
    }
    ElseIf($IsWindows)
    {
        return "test.exe"
    }
    Else
    {
        Throw "Cannot find Test App name for the current operating system"
    }
}


$NewProjectName = "IntegrationTest"

#New Integration Project paths
$Global:NewProjectPathCache = $null
$NewProjectPath = "$(ProjectRoot)/samples/$NewProjectName"
$NewProjectEditorBuildSettingsPath = "$NewProjectPath/ProjectSettings"
$NewProjectBuildPath = "$NewProjectPath/Build"
$NewProjectAssetsPath = "$NewProjectPath/Assets"

$UnityOfBugsPath =  "$(ProjectRoot)/samples/unity-of-bugs"

$NewProjectLogPath = "$(ProjectRoot)/samples/logfile.txt"

$IntegrationScriptsPath = "$(ProjectRoot)/test/Scripts.Integration.Test"
$PackageReleaseOutput = "$(ProjectRoot)/test-package-release"

function FormatUnityPath
{
    param ($path)

    If ($path)
    {
        #Ajust path on MacOS
        If ($path -match "Unity.app/$")
        {
            $path = $path + "Contents/MacOS"
        }
        $unityPath = $path
    }
    Else
    {
        Throw "Unity path is required."
    }

    If ($IsMacOS)
    {
        $unityPath = $unityPath + "/Unity"
    }
    ElseIf ($IsWindows)
    {
        $unityPath = $unityPath +  "/Unity.exe"
    }
    Else
    {
        Throw "Cannot find Unity executable name for the current operating system"
    }

    Write-Host "Unity path is $unityPath"
    return $unityPath
}

function ClearUnityLog
{
    Write-Host -NoNewline "Removing Unity log:"
    If (Test-Path -Path "$NewProjectLogPath") 
    {
        #Force is required if it's opened by another process.
        Remove-Item -Path "$NewProjectLogPath" -Force
    }
    Write-Output " OK"
}

function WaitForLogFile
{
    $timeout = 30
    Write-Host -NoNewline "Waiting for log file "
    do
    {
        $LogCreated = Test-Path -Path "$NewProjectLogPath"
        Write-Host -NoNewline "."
        $timeout--
        If ($timeout -eq 0)
        {
            Throw "Timeout"
        }
        ElseIf (!$LogCreated) #validate
        {
            Start-Sleep -Seconds 1
        }
    } while ($LogCreated -ne $true)
    Write-Output " OK"
}

function SubscribeToUnityLogFile()
{
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [System.Diagnostics.Process]$UnityProcess,
        [Parameter(Mandatory=$false, Position=1)]
        [string] $SuccessString,
        [Parameter(Mandatory=$false, Position=2)]
        [string]$FailString
    )

    $returnCondition = $null
    $unityClosed = $null

    If ($UnityProcess -eq $null)
    {
        Throw "Unity process not received"
    }

    $logFileStream = New-Object System.IO.FileStream("$NewProjectLogPath", [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    If (-not $logFileStream)
    {
        Throw "Failed to open logfile on $NewProjectLogPath"
    }
    $logStreamReader = New-Object System.IO.StreamReader($LogFileStream)

    do
    {  

        If ($logFileStream.Length -eq $logFileStream.Position)
        {
            Start-Sleep -Milliseconds 100
        }
        Else
        {
            $line = $logStreamReader.ReadLine()
            $dateNow = Get-Date -UFormat "%T %Z"

            #print line as normal/errored/warning
            If ($null -ne ($line | select-string "ERROR | Failed "))
            {
                # line contains "ERROR " OR " Failed "
                Write-Host "$dateNow - $line" -ForegroundColor Red
            }
            ElseIf ($null -ne ($line | Select-String "WARNING | Line:"))
            {
                Write-Host "$dateNow - $line" -ForegroundColor Yellow
            }
            Else
            {
                $Host.UI.WriteLine("$dateNow - $line")
            }

            If ($SuccessString -and ($line | Select-String $SuccessString))
            {
                $returnCondition = $line
            }
            ElseIf($FailString -and ($line | Select-String $FailString))
            {
                $returnCondition = $line
            }

            If ($UnityProcess.HasExited -and !$unityClosed)
            {
                $currentPos = $logFileStream.Position
                $logStreamReader.Dispose()
                $logFileStream.Dispose()
                
                Start-Sleep -Milliseconds 1000

                $logFileStream = New-Object System.IO.FileStream("$NewProjectLogPath", [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite) -ErrorAction Stop
                $logFileStream.Seek($currentPos, [System.IO.SeekOrigin]::Begin)
                $logStreamReader = New-Object System.IO.StreamReader($LogFileStream) -ErrorAction Stop

                $unityClosed = $true
            }          
        }

    } while (!$UnityProcess.HasExited -or $logFileStream.Length -ne $logFileStream.Position)
    $logStreamReader.Dispose()
    $logFileStream.Dispose()
    return $returnCondition
}