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

    Write-Verbose "Creating ClickOnce deployment for $AppLongName..."

    Write-Verbose "Peparing $($Files.Count) Files to Deploy:"
    foreach ($f in $Files) {
        Write-Verbose "    $f"
    }

    Write-Verbose "The first file, at index 0, will be the ""Entry Point"" file, or the main .exe."

    Write-Verbose "Getting last revision from Revision.txt..."
    $revisionString = Get-Content "./Revision.txt"
    $revision = [Int32]::Parse($revisionString) + 1
    $version = "1.0.0.$revision"
    Write-Verbose "Deploying as version: $version"

    Write-Verbose "Moving to binary release folder..."
    pushd .\
    cd ".\bin\Release"
    
    Write-Verbose "Current Folder: $(Get-Location)"
    
    $appManifest = "$AppShortName.exe.manifest"
    $deployManifest = "$AppShortName.application"

    $processor = "MSIL"
    $algorithm = "sha256RSA"

    $projectDir = "$($(Get-Location).Path)"
    $OutputDir = "$projectDir/$OutputDir"
    $relativeVersionDir = "Application Files/$AppShortName" + "_$($version.Replace(".", "_"))"
    $versionDir = "$OutputDir/$relativeVersionDir"
    
    Write-Verbose "Project Dir: $projectDir"
    Write-Verbose "Output Dir: $OutputDir"
    Write-Verbose "Version Dir: $versionDir"

    $appCodeBasePath = "$relativeVersionDir/$appManifest"
    $appManifestPath = "$versionDir/$appManifest"
    $deployManifestPath = "$OutputDir/$deployManifest"
    $secondDeployManifestPath = "$versionDir/$deployManifest"
    $secondDeployUrl = "$DeploymentRootUrl/$relativeVersionDir/$deployManifest"

    Write-Verbose "Appliction Manifest Path: $appManifestPath"
    Write-Verbose "Deployment Manifest Path: $deployManifestPath"
    Write-Verbose "Second Deployment Manifest Path: $secondDeployManifestPath"
    
    Write-Verbose "Checking if output folder already exists..."
    if (Get-Item $versionDir -ErrorAction  SilentlyContinue) {
        Write-Verbose "    Output folder already exists."
        if ($DeleteOutputDir) {
            Write-Verbose "    Deleting existing output folder..."
            Remove-Item -Recurse $versionDir
        } else {
            Write-Verbose "    Include the -DeleteOutputDir parameter to automatically delete an existing output folder with the same name."
            return
        }
    } else {
         Write-Verbose "    Output folder does not already exist.  Continue."
    }

    Write-Verbose "Creating output folders..."
    New-Item $versionDir -ItemType directory | Out-Null
 
    Write-Verbose "Copying files into the output folder..."
    Copy-Item $Files -Destination $versionDir
    
    Write-Verbose "Generating application manifest file: $appManifestPath"
    mage -New Application `
        -ToFile "$appManifestPath" `
        -Name $AppLongName `
        -Version $version `
        -Processor $processor `
        -FromDirectory $versionDir `
        -TrustLevel FullTrust `
        -Algorithm $algorithm `
        -IconFile $IconFile | Out-Null

    Write-Verbose "Adding file association to application manifest file ... "
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
        -CertFile "$CertFile" | Out-Null

    Write-Verbose "Generating deployment manifest file: $deployManifestPath"
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
        -Algorithm $algorithm | Out-Null

    Write-Verbose "Renaming files for web server deployment with .deploy..."
    Get-ChildItem $versionDir | `
        Foreach-Object { `
            if (-not $_.FullName.EndsWith(".manifest")) { `
                Rename-Item $_.FullName "$($_.FullName).deploy" } } 

    Write-Verbose "Resigning application manifest..."
    mage -Sign "$appManifestPath" -CertFile $CertFile | Out-Null
    
    Write-Verbose "Altering deployment manifest details..."
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
    
    Write-Verbose "Saving first altered deployment manifest..."
    $xml.Save("$deployManifestPath")

    Write-Verbose "Signing first altered deployment manifest..."
    mage -Sign "$deployManifestPath" `
        -CertFile $CertFile | Out-Null

    Write-Verbose "Loading deployment manifest to make second copy..."
    $secondXml = [xml](Get-Content "$deployManifestPath")

    Write-Verbose "Altering second manifest..."
    $deploymentProviderNode = $secondXml.SelectSingleNode("//*[local-name() = 'deploymentProvider']")
    $deploymentProviderNode.SetAttribute("codebase", "$($secondDeployUrl.Replace(" ", "%20"))")

    Write-Verbose "Saving second altered deployment manifest..."
    $secondXml.Save("$secondDeployManifestPath")

    Write-Verbose "Signing second altered deployment manifest..."
    mage -Sign "$secondDeployManifestPath" `
        -CertFile $CertFile | Out-Null

    Write-Verbose "ClickOnce deployment created."
    Write-Verbose "Uploading files to Amazon Web Services S3..."
    
    Write-Verbose "Moving to Output Folder..."
    cd $OutputDir
    Write-Verbose "Current Folder: $(Get-Location)"

    $publishFiles = dir $versionDir -Recurse -File

    $parentFolder = [System.IO.Path]::GetFullPath("$OutputDir")

    [System.Collections.ArrayList]$relativeFilePaths = @()
    foreach ($f in $publishFiles) {
        $relativeFilePath = "$($f.FullName.SubString($parentFolder.Length+1))"
        Write-Verbose "$relativeFilePath"
        $relativeFilePaths.Add($relativeFilePath) | Out-Null
        #Write-S3Object `
        #    -BucketName $AmazonS3BucketName `
        #    -Region $AmazonRegion `
        #    -File $relativeFilePath `
        #    -Key "$($relativeFilePath)" `
        #    -CannedACLName $AmazonCannedACLName
    }

    Write-Verbose "Last File:"
    $realDeployManifestPath = [System.IO.Path]::GetFullPath($deployManifestPath)
    $relativeFilePath = "$($realDeployManifestPath.SubString($parentFolder.Length+1))"
    Write-Verbose "$relativeFilePath"
    $relativeFilePaths.Add($relativeFilePath) | Out-Null
   # Write-S3Object `
   #     -BucketName $AmazonS3BucketName `
   #     -Region $AmazonRegion `
   #     -File $relativeFilePath `
   #     -Key "$($relativeFilePath)" `
   #     -CannedACLName $AmazonCannedACLName
        
    Write-Verbose "Current Folder: $(Get-Location)"
 
    Write-Verbose "Moving back to project folder..."
    popd

    Write-Verbose "Current Folder: $(Get-Location)"
    
    Write-Verbose  "Saving Current Revision $revision to Revision.txt file..."
    Set-Content -Value "$revision" -Path "./Revision.txt" -Encoding UTF8
    Write-Verbose "Done."

    return $relativeFilePaths
}

