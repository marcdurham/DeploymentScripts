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
        $OutputFolder, `
        [switch]
        $DeleteOutputDir, `
        [Parameter(Mandatory)]
        $CertFile, `
        [Parameter(Mandatory)]
        $DeploymentRootUrl, `
        $FileExtension, `
        $FileExtDescription, `
        $FileExtProgId, `
        $VersionPrefix = "1.0.0.",
        $Processor = "MSIL") 

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
    Write-Host "Entry Point: $($Files[0])"

    Write-Host "Getting last revision from Revision.txt..."
    $revisionString = Get-Content "../../Revision.txt"
    $revision = [Int32]::Parse($revisionString) + 1
    $version = "$VersionPrefix$revision"
    Write-Host "Deploying as version: $version"
    
    Write-Host "Current Folder: $(Get-Location)"
    
    $appManifest = "$AppShortName.exe.manifest"
    $deployManifest = "$AppShortName.application"

    $signingAlgorithm = "sha256RSA"

    $projectFolder = "$($(Get-Location).Path)"
    $OutputFolder = (Resolve-Path "$projectFolder/$OutputFolder")
    $releaseRelativePath = "Application Files/$AppShortName" + "_$($version.Replace(".", "_"))"
    $releaseFolder = "$OutputFolder/$releaseRelativePath"
    
    Write-Host "Project Folder: $projectFolder"
    Write-Host "Output Folder: $OutputFolder"
    Write-Host "Release Folder: $releaseFolder"

    $appCodeBasePath = "$releaseRelativePath/$appManifest"
    $appManifestPath = "$releaseFolder/$appManifest"
    $rootDeployManifestPath = "$OutputFolder/$deployManifest"
    $releaseDeployManifestPath = "$releaseFolder/$deployManifest"
    $releaseDeployUrl = "$DeploymentRootUrl/$releaseRelativePath/$deployManifest"

    Write-Host "Appliction Manifest Path: $appManifestPath"
    Write-Host "Root Deployment Manifest Path: $rootDeployManifestPath"
    Write-Host "Release Deployment Manifest Path: $releaseDeployManifestPath"
    
    Write-Host "Checking if output folder already exists..."
    if (Get-Item $releaseFolder -ErrorAction  SilentlyContinue) {
        Write-Host "    Output folder already exists."
        if ($DeleteOutputDir) {
            Write-Host "    Deleting existing output folder..."
            Remove-Item -Recurse $releaseFolder
        } else {
            Write-Host "    Include the -DeleteOutputDir parameter to automatically delete an existing output folder with the same name."
            return
        }
    } else {
         Write-Host "    Output folder does not already exist.  Continue."
    }

    Write-Host "Creating output folders..."
    New-Item $releaseFolder -ItemType directory | Out-Null
 
    Write-Host "Copying files into the output folder..."
    Copy-Item $Files -Destination $releaseFolder
    
    Write-Host "Generating application manifest file: $appManifestPath"
    mage -New Application `
        -ToFile "$appManifestPath" `
        -Name $AppLongName `
        -Version $version `
        -Processor $Processor `
        -FromDirectory $releaseFolder `
        -TrustLevel FullTrust `
        -Algorithm $signingAlgorithm `
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

    Write-Host "Generating deployment manifest file: $rootDeployManifestPath"
    mage -New Deployment `
        -ToFile "$rootDeployManifestPath" `
        -Name $AppLongName `
        -Version $version `
        -MinVersion none `
        -Processor $Processor `
        -AppManifest "$appManifestPath" `
        -AppCodeBase "$($appCodeBasePath.Replace(" ", "%20"))" `
        -CertFile $CertFile `
        -IncludeProviderURL true `
        -ProviderURL "$DeploymentRootUrl/$deployManifest" `
        -Install true `
        -Publisher $Publisher `
        -Algorithm $signingAlgorithm | Out-Host

    Write-Host "Renaming files for web server deployment with .deploy..."
    Get-ChildItem $releaseFolder | `
        Foreach-Object { `
            if (-not $_.FullName.EndsWith(".manifest")) { `
                Rename-Item $_.FullName "$($_.FullName).deploy" } } 

    Write-Host "Resigning application manifest..."
    mage -Sign "$appManifestPath" -CertFile $CertFile | Out-Host
    
    Write-Host "Altering inner  deployment manifest details..."
    $xml = [xml](Get-Content "$rootDeployManifestPath")
    
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
    $xml.Save("$rootDeployManifestPath")

    Write-Host "Signing altered inner deployment manifest..."
    mage -Sign "$rootDeployManifestPath" `
        -CertFile $CertFile | Out-Host

    Write-Host "Loading deployment manifest to make root copy..."
    $secondXml = [xml](Get-Content "$rootDeployManifestPath")

    Write-Host "Altering root deployment manifest..."
    $deploymentProviderNode = $secondXml.SelectSingleNode("//*[local-name() = 'deploymentProvider']")
    $deploymentProviderNode.SetAttribute("codebase", "$($secondDeployUrl.Replace(" ", "%20"))")

    Write-Host "Saving altered root deployment manifest..."
    $secondXml.Save("$releaseDeployManifestPath")

    Write-Host "Signing altered root deployment manifest..."
    mage -Sign "$releaseDeployManifestPath" `
        -CertFile $CertFile | Out-Host

    Write-Host "ClickOnce deployment created."
    Write-Host "Uploading files to Amazon Web Services S3..."
    
    Write-Host "Moving to Output Folder..."
    cd $OutputFolder
    Write-Host "Current Folder: $(Get-Location)"

    $publishFiles = dir $releaseFolder -Recurse -File

    $parentFolder = [System.IO.Path]::GetFullPath("$OutputFolder")

    [System.Collections.ArrayList]$relativeFilePaths = @()
    foreach ($f in $publishFiles) {
        $relativeFilePath = "$($f.FullName.SubString($parentFolder.Length+1))"
        $relativeFilePaths.Add($relativeFilePath) | Out-Null
    }

    Write-Host "Last File:"
    $realDeployManifestPath = [System.IO.Path]::GetFullPath($rootDeployManifestPath)
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

