function Publish-ClickOnce {
    param(
        [Parameter(Mandatory)]
        $Files, `
        [Parameter(Mandatory)]
        $AppLongName, `
        [Parameter(Mandatory)]
        $AppShortName, `
        [Parameter(Mandatory)]
        $IconFile, `
        [Parameter(Mandatory)]
        $Publisher, `
        [Parameter(Mandatory)]
        $OutputDir, `
        [switch]
        $DeleteOutputDir, `
        [Parameter(Mandatory)]
        $CertFile, `
        [Parameter(Mandatory)]
        $DeploymentRootUrl, `
        [Parameter(Mandatory)]
        $AmazonS3BucketName, `
        $AmazonCannedACLName = "public-read", `
        [Parameter(Mandatory)]
        $AmazonRegion, `
        $FileExtension, `
        $FileExtDescription, `
        $FileExtProgId) 

    Write-Host "Creating ClickOnce deployment for $AppLongName..."

    Write-Host "Changing current directory to binary release folder..."
    pushd .\
    cd ".\bin\Release"

    $missing = 0
    Write-Host "Peparing $($Files.Count) files for deployment:"
    foreach ($f in $Files) {
        Write-Host "    $f" -NoNewline
        if (Test-Path $f) {
            Write-Host " EXISTS" -ForegroundColor Green
        } else {
            $missing += 1
            Write-Host " MISSING" -ForegroundColor Red
        }
    }

    if ($missing -gt 0) {
        Write-Host "$missing files missing. Aborting script." -ForegroundColor Red
        return
    }

    Write-Host "The first file, at index 0, will be the ""Entry Point"" file, or the main .exe."

    Write-Host "Getting last revision from Revision.txt..."
    $revisionString = Get-Content "../../Revision.txt"
    $revision = [Int32]::Parse($revisionString) + 1
    $version = "1.0.0.$revision"
    Write-Host "Deploying as version: $version"
    
    Write-Host "Current Folder: $(Get-Location)"
    
    $appManifest = "$AppShortName.exe.manifest"
    $deployManifest = "$AppShortName.application"

    $processor = "MSIL"
    $algorithm = "sha256RSA"

    $projectDir = "$($(Get-Location).Path)"
    $OutputDir = "$projectDir/$OutputDir"
    $relativeVersionDir = "Application Files/$AppShortName" + "_$($version.Replace(".", "_"))"
    $versionDir = "$OutputDir/$relativeVersionDir"
    
    Write-Host "Project Dir: $projectDir"
    Write-Host "Output Dir: $OutputDir"
    Write-Host "Version Dir: $versionDir"

    $appCodeBasePath = "$relativeVersionDir/$appManifest"
    $appManifestPath = "$versionDir/$appManifest"
    $deployManifestPath = "$OutputDir/$deployManifest"
    $secondDeployManifestPath = "$versionDir/$deployManifest"
    $secondDeployUrl = "$DeploymentRootUrl/$relativeVersionDir/$deployManifest"

    Write-Host "Appliction Manifest Path: $appManifestPath"
    Write-Host "Deployment Manifest Path: $deployManifestPath"
    Write-Host "Second Deployment Manifest Path: $secondDeployManifestPath"
    
    Write-Host "Checking if output folder already exists..."
    if (Get-Item $versionDir -ErrorAction  SilentlyContinue) {
        Write-Host "    Output folder already exists."
        if ($DeleteOutputDir) {
            Write-Host "    Deleting existing output folder..."
            Remove-Item -Recurse $versionDir
        } else {
            Write-Host "    Include the -DeleteOutputDir parameter to automatically delete an existing output folder with the same name."
            return
        }
    } else {
         Write-Host "    Output folder does not already exist.  Continue."
    }

    Write-Host "Creating output folders..."
    New-Item $versionDir -ItemType directory | Out-Null
 
    Write-Host "Copying files into the output folder..."
    Copy-Item $Files -Destination $versionDir
    
    Write-Host "Generating application manifest file: $appManifestPath"
    mage -New Application `
        -ToFile "$appManifestPath" `
        -Name $AppLongName `
        -Version $version `
        -Processor $processor `
        -FromDirectory $versionDir `
        -TrustLevel FullTrust `
        -Algorithm $algorithm `
        -IconFile $IconFile | Out-Host

    Write-Host "Adding file association to application manifest file ... "
    [xml]$doc = Get-Content (Resolve-Path "$appManifestPath")
    $fa = $doc.CreateElement("fileAssociation")
    $fa.SetAttribute("xmlns", "urn:schemas-microsoft-com:clickonce.v1")
    $fa.SetAttribute("extension", "$FileExtension")
    $fa.SetAttribute("description", "$FileExtDescription")
    $fa.SetAttribute("progid", "$FileExtProgId")
    $fa.SetAttribute("defaultIcon", "$IconFile")
    $doc.assembly.AppendChild($fa) | Out-Null
    $doc.Save((Resolve-Path "$appManifestPath"))

    mage -Sign "$appManifestPath" `
        -CertFile "$CertFile" | Out-Host

    Write-Host "Generating deployment manifest file: $deployManifestPath"
    mage -New Deployment `
        -ToFile "$deployManifestPath" `
        -Name $AppLongName `
        -Version $version `
        -MinVersion none `
        -Processor $processor `
        -AppManifest "$appManifestPath" `
        -AppCodeBase "$($appCodeBasePath.Replace(" ", "%20"))" `
        -CertFile $CertFile `
        -IncludeProviderURL true `
        -ProviderURL "$DeploymentRootUrl/$deployManifest" `
        -Install true `
        -Publisher $Publisher `
        -Algorithm $algorithm | Out-Host

    Write-Host "Renaming files for web server deployment with .deploy..."
    Get-ChildItem $versionDir | `
        Foreach-Object { `
            if (-not $_.FullName.EndsWith(".manifest")) { `
                Rename-Item $_.FullName "$($_.FullName).deploy" } } 

    Write-Host "Resigning application manifest..."
    mage -Sign "$appManifestPath" -CertFile $CertFile | Out-Host
    
    Write-Host "Altering inner  deployment manifest details..."
    $xml = [xml](Get-Content "$deployManifestPath")
    
    #Change application identiy name
    $assemblyIdentityNode = $xml.SelectSingleNode("//*[local-name() = 'assemblyIdentity']")
    $assemblyIdentityNode.SetAttribute("name", "$deployManifest")
    
    #Map file extensions to .deploy
    $deploymentNode = $xml.SelectSingleNode("//*[local-name() = 'deployment']")
    $deploymentNode.SetAttribute("mapFileExtensions", "true")
    
    #Update every day
    $expirationNode = $xml.SelectSingleNode("//*[local-name() = 'expiration']")
    $expirationNode.SetAttribute("maximumAge", "1")
    $expirationNode.SetAttribute("unit", "days")
    
    Write-Host "Saving altered inner deployment manifest..."
    $xml.Save("$deployManifestPath")

    Write-Host "Signing altered inner deployment manifest..."
    mage -Sign "$deployManifestPath" `
        -CertFile $CertFile | Out-Host

    Write-Host "Loading deployment manifest to make root copy..."
    $secondXml = [xml](Get-Content "$deployManifestPath")

    Write-Host "Altering root deployment manifest..."
    $deploymentProviderNode = $secondXml.SelectSingleNode("//*[local-name() = 'deploymentProvider']")
    $deploymentProviderNode.SetAttribute("codebase", "$($secondDeployUrl.Replace(" ", "%20"))")

    Write-Host "Saving altered root deployment manifest..."
    $secondXml.Save("$secondDeployManifestPath")

    Write-Host "Signing altered root deployment manifest..."
    mage -Sign "$secondDeployManifestPath" `
        -CertFile $CertFile | Out-Host

    Write-Host "ClickOnce deployment created."
    Write-Host "Uploading files to Amazon Web Services S3..."
    
    Write-Host "Moving to Output Folder..."
    cd $OutputDir
    Write-Host "Current Folder: $(Get-Location)"

    $publishFiles = dir $versionDir -Recurse -File

    $parentFolder = [System.IO.Path]::GetFullPath("$OutputDir")

    [System.Collections.ArrayList]$relativeFilePaths = @()
    foreach ($f in $publishFiles) {
        $relativeFilePath = "$($f.FullName.SubString($parentFolder.Length+1))"
        $relativeFilePaths.Add($relativeFilePath) | Out-Null
    }

    Write-Host "Last File:"
    $realDeployManifestPath = [System.IO.Path]::GetFullPath($deployManifestPath)
    $relativeFilePath = "$($realDeployManifestPath.SubString($parentFolder.Length+1))"
    $relativeFilePaths.Add($relativeFilePath) | Out-Null
        
    Write-Host "Current Folder: $(Get-Location)"
 
    #Write-Host "Moving back to project folder..."
    #popd

    #Write-Host "Current Folder: $(Get-Location)"
    
    Write-Host  "Saving Current Revision $revision to Revision.txt file..."
    Set-Content -Value "$revision" -Path "$projectDir/Revision.txt" -Encoding UTF8
    Write-Host "Done."

    return $relativeFilePaths
}

