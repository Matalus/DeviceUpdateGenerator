
##Auto-Generated using "PSProject Builder" Created by Matt Hamende 2018
#######################################################################
#Description: generates wireframe powershell projects
#Features:
## Define ScriptRoot
## Standard Function Libraries
## PSModule Prerequities Loader
## JSON Config File
########################################################################

#Set Default Error Handling - Set to Continue for Production
$ErrorActionPreference = "Stop"

#Define Logger Function
Function Log($message) {
    "$(Get-Date -Format u) | $message"
}

#Define Script Root for relative paths
$RunDir = split-path -parent $MyInvocation.MyCommand.Definition
Log "Setting Location to: $RunDir"
Set-Location $RunDir # Sets directory

#Imports Function Library
Log "Importing Modules"
Try {
    Remove-Module Functions -ErrorAction SilentlyContinue
}
Catch {}
Try {
    Import-Module "$RunDir\Modules\Functions.psm1" -DisableNameChecking -ErrorAction SilentlyContinue
}
Catch { $_ }

#Load Config
Log "Loading Config"
$Config = (Get-Content "$RunDir\config.json") -join "`n" | ConvertFrom-Json

#Load Prerequisites
Prereqs -config $Config

## Script Below this line #######################################################

Log "Importing Type Data..."
[array]$importList = Get-ChildItem $RunDir\Export -Filter "*.xls*"


if ($importList.Count -gt 1) {
    $importList = $importList | Out-GridView -PassThru -Title "Select a Source Import File"
    <# -- Legacy Host Select
    Write-Host -ForegroundColor Yellow "Select an Export to Extract Types"
    $enum = 1
    $menu = @{} 
    ForEach ($file in $importList) {
        $menu.Add($enum, $file)
        ""
        Write-Host -ForegroundColor Cyan "$($enum): $($file.Name) : $($file.Length) : $($file.LastWriteTime)" 
        $enum++
    }
    ""
    $key = Read-Host -Prompt "Enter Selection Number and Press Enter to continue"
    $importList = $menu[[int]$key]
    #>
}


$VersionList = @(
    "3.0",
    "3.3.2",
    "3.7"
)

$Version = $VersionList | Out-GridView -PassThru -Title "Select a RunSmart Version"

if ($Version -notin $VersionList) {
    Write-Error "Must Select a valid version - Set 'SchemaVersion' in config.json"
}

[array]$Export_Module_Types = Import-Excel -Path $importList.FullName -WorksheetName "Partitions" -DataOnly | Where-Object {
    $_.Partition_Module_Type_CD.length -gt 1
}

if ($Export_Module_Types.Count -ge 1) {

    $Export_Module_Types | ForEach-Object {
        $_.Partition_Module_Type_CD = "'$($_.Partition_Module_Type_CD)'" 
    }


    $Module_Types_String = $Export_Module_Types.Partition_Module_Type_CD -join ","

    $SQLParams = @{
        ServerInstance = $Config.dbconfig.ServerInstance
        Database       = $Config.dbconfig.Database
        Credential     = New-Object System.Management.Automation.PSCredential(
            $Config.dbconfig.Username,
            (ConvertTo-SecureString $Config.dbconfig.Password -AsPlainText -Force)
        )
        Query          = "SELECT * FROM dbo.Partition_Module_Types WHERE Partition_Module_Name IN ($Module_Types_String) ORDER BY Partition_Module_Type_CD"
    }
    [array]$Module_Types = Invoke-SqlCmd2 @SQLParams

    Log "Found: $($Module_Types.Count) Module Types"
}

[array]$Device_Types = Import-Excel -Path $importList.FullName -WorksheetName "Device_Types" -DataOnly
$Device_Types | ForEach-Object {$_.Device_Type_CD = [int]$_.Device_Type_CD}
$Device_Types = $Device_Types | Sort-Object Device_Type_CD
Log "Found: $($Device_Types.count) Device Types"

[array]$Sensor_Types = Import-Excel -Path $importList.FullName -WorksheetName "Device_Sensor_Types" -DataOnly | Sort-Object Sensor_Type_CD
$Sensor_Types | ForEach-Object {$_.Sensor_Type_CD = [int]$_.Sensor_Type_CD}
$Sensor_Types = $Sensor_Types | Sort-Object Sensor_Type_CD
Log "Found: $($Sensor_Types.Count) Sensor Types"

[array]$Measurement_Types = Import-Excel -Path $importList.FullName -WorksheetName "Device_Measurement_Types" -DataOnly 
$Measurement_Types | ForEach-Object {$_.Measurement_Type_CD = [int]$_.Measurement_Type_CD}
$Measurement_Types = $Measurement_Types | Sort-Object Measurement_Type_CD
Log "Found:$($Measurement_Types.Count) Measurement Types"

[array]$Enumerations = Import-Excel -Path $importList.FullName -WorksheetName "Device_Measurement_Type_Text" -DataOnly | Sort-Object Measurement_Type_CD, Measurement_Value
$Enumerations | ForEach-Object {$_.Measurement_Type_CD = [int]$_.Measurement_Type_CD}
$Enumerations | ForEach-Object {$_.Measurement_Value = [int]$_.Measurement_Value}
$Enumerations = $Enumerations | Sort-Object Measurement_Type_CD, Measurement_Value
Log "Found:$($Enumerations.Count) Measurement Type Text"

Log "Enumerating System Codes..."
$System_Codes = @{
    "Environment"                    = 1
    "Energy Recovery Network"        = 2
    "Power Distribution Network"     = 3
    "Information Technology Network" = 4
}

Log "Enumerating Measurement Unit Codes..."
$Measurement_Unit_Codes = @{
    "Imperial"	= 1
    "Metric"   = 2
}

Log "Building Insert Summary..."
$Body = @"
-- BASELAYER TECHNOLOGY 2018 - Device Types Update
-- This Script will add the following Types for import if they don't already exist
-- ###################################################
"@

$Body += "`n`n-- MODULE TYPES: ($($Module_Types.Count)) Type_CD Name Description" 
ForEach ($type in $Module_Types) {
    $Body += "`n-- $($type.Partition_Module_Type_CD) $($type.Partition_Module_Name) $($type.Description)" 
}

$Body += "`n`n-- DEVICE TYPES: ($($Device_Types.Count)) Type_CD Device_Type_Name" 
ForEach ($type in $Device_Types) {
    $Body += "`n-- $($type.Device_Type_CD) $($type.Device_Type_Name)" 
}

$Body += "`n`n-- SENSOR TYPES: ($($Sensor_Types.Count)) Type_CD Sensor_Name"
ForEach ($type in $Sensor_Types) {
    $Body += "`n-- $($type.Sensor_Type_CD) $($type.Sensor_Name)"
}

$Body += "`n`n-- MEASUREMENT TYPES: ($($Measurement_Types.Count)) Type_CD Name Description"
ForEach ($type in $Measurement_Types) {
    $Body += "`n-- $($type.Measurement_Type_CD) $($type.Measurement_Name) $($type.Description)"
}

$Body += "`n`n-- MEASUREMENT TYPE TEXT: ($($Enumerations.Count)) Type_CD Name Value Text"
ForEach ($type in $Enumerations) {
    $Body += "`n-- $($type.Measurement_Type_CD) $(($Measurement_Types | where-object{$_.Measurement_Type_CD -eq $type.Measurement_Type_CD}).Measurement_Name) $($type.Measurement_Value) $($type.Measurement_Value_Text)"
}

Log "Generating Script..."
$Body += @"


-- BEGIN SCRIPT"
--------------------------------------------------------------------------------------------------------------------------------------- Auto-generated 

IF DB_NAME() IN ('master','msdb','model','tempdb')
BEGIN
   print 'Error: You are in a system database.  Change the database context to the RunSmart user database (usually IODC_Central) and re-run this script.'
   SET NOEXEC ON
END
GO

--------------------------------------------------------------------------------------------------------------------------------------- Auto-generated 
"@

$Body += @"
--------------------------------------------------------------------------------------------------------------------------------------- Auto-generated 
-- Turn On Inserts for Partition_Module_Types
SET IDENTITY_INSERT dbo.Partition_Module_Types ON

"@

ForEach ($type in $Module_Types) {
    $Body += "`n-- INSERTS - $($type.Partition_Module_Type_CD) $($type.Partition_Module_Name) $($type.Description)"
    $Body += "`nIF NOT EXISTS (SELECT 1 FROM dbo.Partition_Module_Types WITH(NOLOCK) WHERE Partition_Module_Type_CD=$($type.Partition_Module_Type_CD))"
    $Body += "`n	INSERT INTO [dbo].[Partition_Module_Types] ([Partition_Module_Type_CD] ,[Partition_Type_CD] ,[Partition_Module_Name] ,[Description] ,[Is_Power_Module] ,[Is_Data_Module] ,[Module_Shell_Count] ,[Last_Updated_By] ,[Last_Update_Date] ,[Is_Deleted] ,[Has_Legacy_BC_Screen] ,[Has_Legacy_PDN_Screen] ,[Has_Legacy_ERN_Screen] ,[Has_First_Person])"
    $Body += "`n	VALUES ($([int]$type.Partition_Module_Type_CD)"
    $Body += " ,$([int]$type.Partition_Type_CD)"
    $Body += " ,'$($type.Partition_Module_Name)'"
    $Body += " ,'$($type.Description)'"
    $Body += " ,$([int]$type.Is_Power_Module)"
    $Body += " ,$([int]$type.Is_Data_Module)"
    $Body += " ,$([int]$type.Module_Shell_Count)"
    $Body += " ,616"
    $Body += " ,SYSUTCDATETIME()"
    $Body += " ,0"
    $Body += " ,$([int]$type.Has_Legacy_BC_Screen)"
    $Body += " ,$([int]$type.Has_Legacy_PDN_Screen)"
    $Body += " ,$([int]$type.Has_Legacy_ERN_Screen)"
    $Body += " ,$([int]$type.Has_First_Person)"
    $Body += ")"
    $Body += "`nGO"
}

$Body += @"

-- Turn OFF Inserts for Partition_Module_Types
SET IDENTITY_INSERT dbo.Partition_Module_Types OFF
GO
--------------------------------------------------------------------------------------------------------------------------------------- Auto-generated 
-- Turn On Inserts for Measurement_Types
SET IDENTITY_INSERT dbo.Device_Measurement_Types ON

"@

ForEach ($type in $Measurement_Types) {
    $Body += "`n-- INSERTS - $($type.Measurement_Type_CD) $($type.Measurement_Name)"
    $Body += "`nIF NOT EXISTS (SELECT 1 FROM dbo.Device_Measurement_Types WITH(NOLOCK) WHERE Measurement_Type_CD=$($type.Measurement_Type_CD))"
    $Body += "`n	INSERT INTO [dbo].[Device_Measurement_Types] ([Measurement_Type_CD] ,[Measurement_Name] ,[Description] ,[Last_Updated_By] ,[Last_Update_Date] ,[Is_Boolean] ,[Is_Deleted] ,[Is_Ranged_Value] ,[Measurement_Unit_System_Type_CD])"
    $Body += "`n	VALUES ($([int]$type.Measurement_Type_CD)"
    $Body += " ,'$($type.Measurement_Name)'"
    $Body += " ,'$($type.Description)'"
    $Body += " ,616"
    $Body += " ,SYSUTCDATETIME()"
    $Body += " ,$([int][System.Convert]::ToBoolean($type.Is_Boolean))"
    $Body += " ,0"
    $Body += " ,$([int][System.Convert]::ToBoolean($type.Is_Ranged_Value))"
    if ($type.Measurement_Unit_System_Type_CD -eq $Null) {
        $Body += " ,NULL"
    }
    else {
        $Body += " ,$($Measurement_Unit_Codes[$type.Measurement_Unit_System_Type_CD])"
    }
    $Body += ")"
    $Body += "`nGO"
}

$Body += @"

-- Turn OFF Inserts for Measurement_Types
SET IDENTITY_INSERT dbo.Device_Measurement_Types OFF
GO

--------------------------------------------------------------------------------------------------------------------------------------- Auto-generated 

"@

ForEach ($type in $Enumerations) {
    $Body += "`n-- INSERTS - $($type.Measurement_Type_CD) $($type.Measurement_Value) - $($type.Measurement_Value_Text)"
    $Body += "`nIF NOT EXISTS (SELECT 1 FROM dbo.Device_Measurement_Type_Text WITH(NOLOCK) WHERE Measurement_Type_CD=$($type.Measurement_Type_CD) AND Measurement_Value=$($type.Measurement_Value))"
    $Body += "`n	INSERT INTO [dbo].[Device_Measurement_Type_Text] ([Measurement_Type_CD] ,[Measurement_Value] ,[Measurement_Value_Text] ,[Last_Updated_By] ,[Last_Update_Date] ,[Is_Deleted] ,[Description])"
    $Body += "`n	VALUES ($([int]$type.Measurement_Type_CD)"
    $Body += " ,$($type.Measurement_Value)"
    $Body += " ,'$($type.Measurement_Value_Text)'"
    $Body += " ,616"
    $Body += " ,SYSUTCDATETIME()"
    $Body += " ,0"
    if ($type.Description -eq $Null) {
        $Body += " ,NULL"
    }
    else {
        $Body += " ,'$($type.Description)'"
    }
    $Body += ")"
    $Body += "`nGO"
}

$Body += @"

--------------------------------------------------------------------------------------------------------------------------------------- Auto-generated 
GO

"@

$Body += @"
-- Turn On Inserts for Device Types
SET IDENTITY_INSERT dbo.Device_Types ON
GO

"@

ForEach ($type in $Device_Types) {
    $Body += @"

-- INSERTS - $($type.Device_Type_CD) $($type.Device_Type_Name)
IF NOT EXISTS (SELECT 1 FROM dbo.Device_Types WITH(NOLOCK) WHERE Device_Type_CD=$($type.Device_Type_CD))
	INSERT INTO [dbo].[Device_Types] ([Device_Type_CD] ,[Device_System_CD] ,[Device_Type_Name] ,[Device_Type_Short_Name] ,[Last_Updated_By] ,[Last_Update_Date] ,[Is_Deleted])
	VALUES($([int]$type.Device_Type_CD) ,$([int]$System_Codes[$type.Device_System_CD]) ,'$($type.Device_Type_Name)' ,'$($type.Device_Type_Short_Name)' ,616 ,SYSUTCDATETIME() ,0)
GO
"@
}
$Body += @"

-- Turn OFF Inserts for Device Types
SET IDENTITY_INSERT dbo.Device_Types OFF
GO

--------------------------------------------------------------------------------------------------------------------------------------- Auto-generated 
-- Turn On Inserts for Sensor Types
SET IDENTITY_INSERT dbo.Device_Sensor_Types ON

"@

ForEach ($type in $Sensor_Types) {
    $Body += "`n-- INSERTS - $($type.Sensor_Type_CD) $($type.Sensor_Name)"
    $Body += "`nIF NOT EXISTS (SELECT 1 FROM dbo.Device_Sensor_Types WITH(NOLOCK) WHERE SENSOR_TYPE_CD=$($type.Sensor_Type_CD))"
    $Body += "`n	INSERT INTO [dbo].[Device_Sensor_Types] ([Sensor_Type_CD] ,[Device_Type_CD] ,[Sensor_Name] ,[Sensor_Short_Name] ,[Measurement_Type_CD] ,[Last_Updated_By] ,[Last_Update_Date] ,[Is_Deleted] ,[Is_Critical] ,[Rounding_Precision] ,[Deadband_Percentage] ,[External_Tag_Format] ,[Disable_History] ,[Setpoint_Timeout_Seconds]"
    if ($Version -eq "3.0") {
        $Body += " ,[Alarm_Priority_CD] ,[Warning_Priority_CD]"
    }
    $Body += ")"
    $Body += "`n	VALUES ($([int]$type.Sensor_Type_CD) ,$([int]$type.Device_Type_CD) ,'$($type.Sensor_Name)' ,'$($type.Sensor_Short_Name)' ,$([int]$type.Measurement_Type_CD) ,616 ,SYSUTCDATETIME() ,$([int]$type.Is_Deleted) ,$([int]$type.Is_Critical) ,$([int]$type.Rounding_Precision) ,$(if($type.Deadband_Percentage -eq $Null){"NULL"}else{$type.Deadband_Percentage}) ,$(if($type.External_Tag_Format -eq $null){"NULL"}else{$type.External_Tag_Format}) ,$([int]$type.Disable_History) ,$(if($type.Setpoint_Timeout_Seconds -eq $Null){"NULL"}else{$type.Setpoint_Timeout_Seconds})"
    if ($Version -eq "3.0") {
        $Body += " ,0 ,0"
    }
    $Body += ")"
    $Body += "`nGO"
}


$Body += @"

-- Turn OFF Inserts for Sensor Types
SET IDENTITY_INSERT dbo.Device_Sensor_Types OFF
GO
"@


Log "Exporting File..."
$Body |  Out-File .\$($Version)_Insert_Types.sql -Force -Encoding utf8
if ($Config.LaunchNPP -eq $true) {
    Try {
        Start Notepad++ .\$($Version)_Insert_Types.sql
    }
    Catch {Write-Error "Notepad++ Not installed please open the file in your preferred text editor"}
}
Log "Done."



