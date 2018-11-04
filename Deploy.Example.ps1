Import-Module AWSPowerShell
Import-Module .\ClickOnce-Module.ps1

#Build project
"Building..."
msbuild.exe AppName.WinForms.csproj /p:Configuration=Release /p:TargetVersion=4.0

pushd .\
cd ".\bin\Release"

""
# Optional Extra Commands Here
# "Compressing UserManual folder..."
# 7z a -sfx UserManual.exe UserManual

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
    -AppLongName "Full Application Name" `
    -AppShortName "AppName" `
    -IconFile "AppNameIcon.ico" `
    -Publisher "Your Name" `
    -OutputDir "../../../../ClickOnceDeploy" `
    -CertFile "../../../AppName.pfx" `
    -DeploymentRootUrl "http://appname.md9.us" `
    -AmazonRegion "us-west-2" `
    -AmazonS3BucketName "appname.md9.us" `
    -FileExt ".abc" `
    -FileExtDescription "Application Name ABC File" `
    -FileExtProgId "AppName.ABC" `
    -ErrorAction Stop

popd