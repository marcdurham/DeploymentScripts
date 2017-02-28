Import-Module .\AmazonS3-Module.ps1
Import-Module .\ClickOnce-Module.ps1

#Build project
"Building..."
msbuild.exe AppName.WinForms.csproj /p:Configuration=Release /p:TargetVersion=4.0

pushd .\
cd ".\bin\Release"

""
"Compressing UserManual folder..."
7z a -sfx UserManual.exe UserManual

""
"Configuring files to deploy..." 
#Configure file paths 
#The first file is the "Entry Point" file, the main .exe.
$files = `
    "AppName.exe", `
    "AppName.pdb", `
    "AppName.exe.config", `
    "AppNameIcon.ico", `
    "UserManual.exe", `
    "AppName.Common.dll", `
    "AppName.Common.pdb"

"Creating ClickOnce manifest files..." 
Create-ClickOnce $files `
    -AppProperName "Application Name" `
    -AppShortName "AppName" `
    -IconFilename "AppNameIcon.ico" `
    -Publisher "Marc Durham" `
    -OutputDir "../../../../ClickOnceDeploy" `
    -CertFile "../../../AppName.pfx" `
    -DeploymentUrl "http://appname.md9.us" `
    -AmazonRegion "us-west-2" `
    -BucketName "appname.md9.us" `
    -ErrorAction Stop

popd