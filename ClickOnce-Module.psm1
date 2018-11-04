function Create-ClickOnce {
    param(
        [Parameter(Required)]
        $AppLongName, `
        [Parameter(Required)]
        $AppShortName, `
        [Parameter(Required)]
        $IconFile, `
        [Parameter(Required)]
        $Publisher, `
        [Parameter(Required)]
        $OutputDir, `
        [Parameter(Required)]
        $CertFile, `
        [Parameter(Required)]
        $DeploymentRootUrl, `
        [Parameter(Required)]
        $AmazonS3BucketName, `
        $AmazonCannedACLName = "public-read", `
        [Parameter(Required)]
        $AmazonRegion, `
        $FileExt, `
        $FileExtDescription, `
        $FileExtProgId) 

    "Creating ClickOnce deployment for $AppLongName..."

    # The first file, at index 0, will be the "Entry Point" file, the main .exe.
    $files = $args[0] 

    "Getting last revision from Revision.txt..."
    $revisionString = Get-Content "./Revision.txt"
    $revision = [Int32]::Parse($revisionString) + 1
    $version = "1.0.0.$revision"
    "Deploying as version: $version"

    "Moving to binary release folder..."
    pushd .\
    cd ".\bin\Release"
    
    $currentFolder = Get-Location
    "Current Folder: $currentFolder"
    
    # TODO: Use these two variables, or delete them
    $appManifest = "$AppShortName.exe.manifest"
    $deployManifest = "$AppShortName.application"

    $processor = "MSIL"
    $algorithm = "sha256RSA"

    $projectDir = "$($(Get-Location).Path)"
    $OutputDir = "$projectDir/$OutputDir"
    $relativeVersionDir = "Application Files/$AppShortName" + "_$($version.Replace(".", "_"))"
    $versionDir = "$OutputDir/$relativeVersionDir"
    
    "Project Dir: $projectDir"
    "Output Dir: $OutputDir"
    "Version Dir: $versionDir"

    $appCodeBasePath = "$relativeVersionDir/$appManifest"
    $appManifestPath = "$versionDir/$appManifest"
    $deployManifestPath = "$OutputDir/$deployManifest"
    $secondDeployManifestPath = "$versionDir/$deployManifest"
    $secondDeployUrl = "$DeploymentRootUrl/$relativeVersionDir/$deployManifest"

    "Appliction Manifest Path: $appManifestPath"
    "Deployment Manifest Path: $deployManifestPath"
    "Second Deployment Manifest Path: $secondDeployManifestPath"
    
    "Creating output folders..."
    mkdir $versionDir
 
    "Copying files into the output folder..."
    Copy-Item $files -Destination $versionDir
    
    "Generating application manifest file: $appManifestPath"
    mage -New Application `
        -ToFile "$appManifestPath" `
        -Name $AppLongName `
        -Version $version `
        -Processor $processor `
        -FromDirectory $versionDir `
        -TrustLevel FullTrust `
        -Algorithm $algorithm `
        -IconFile $IconFile

    "Adding file association to application manifest file ... "
    [xml]$doc = Get-Content (Resolve-Path "$appManifestPath")
    $fa = $doc.CreateElement("fileAssociation")
    $fa.SetAttribute("xmlns", "urn:schemas-microsoft-com:clickonce.v1")
    $fa.SetAttribute("extension", "$FileExt")
    $fa.SetAttribute("description", "$FileExtDescription")
    $fa.SetAttribute("progid", "$FileExtProgId")
    $fa.SetAttribute("defaultIcon", "$IconFile")
    $doc.assembly.AppendChild($fa)
    $doc.Save((Resolve-Path "$appManifestPath"))

    mage -Sign "$appManifestPath" `
        -CertFile "$CertFile"

    "Generating deployment manifest file: $deployManifestPath"
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
        -Algorithm $algorithm 

    #-ProviderURL "$DeploymentRootUrl/$deployManifest" `
    "Renaming files for web server deployment with .deploy..."
    Get-ChildItem $versionDir | `
        Foreach-Object { `
            if (-not $_.FullName.EndsWith(".manifest")) { `
                Rename-Item $_.FullName "$($_.FullName).deploy" } } 

    "Resigning application manifest..."
    mage -Sign "$appManifestPath" -CertFile $CertFile 
 
    "Altering deployment manifest details..."
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
    
    "Saving first altered deployment manifest..."
    $xml.Save("$deployManifestPath")

    "Signing first altered deployment manifest..."
    mage -Sign "$deployManifestPath" -CertFile $CertFile 

    "Loading deployment manifest to make second copy..."
    $secondXml = [xml](Get-Content "$deployManifestPath")

    "Altering second manifest..."
    $deploymentProviderNode = $secondXml.SelectSingleNode("//*[local-name() = 'deploymentProvider']")
    $deploymentProviderNode.SetAttribute("codebase", "$($secondDeployUrl.Replace(" ", "%20"))")

    "Saving second altered deployment manifest..."
    $secondXml.Save("$secondDeployManifestPath")

    "Signing second altered deployment manifest..."
    mage -Sign "$secondDeployManifestPath" -CertFile $CertFile 

    "ClickOnce deployment created."
    "Uploading files to Amazon Web Services S3..."
    
    "Moving to Output Folder..."
    cd $OutputDir
    $currentFolder = Get-Location
    "Current Director: $currentFolder"

    $publishFiles = dir $versionDir -Recurse -File

    $parentFolder = [System.IO.Path]::GetFullPath("$OutputDir")

    foreach ($f in $publishFiles) {
        $relativeFilePath = "$($f.FullName.SubString($parentFolder.Length+1))"
        Write-S3Object `
            -BucketName $AmazonS3BucketName `
            -Region $AmazonRegion `
            -File $relativeFilePath `
            -Key "$($relativeFilePath)" `
            -CannedACLName $AmazonCannedACLName
    }

    $realDeployManifestPath = [System.IO.Path]::GetFullPath($deployManifestPath)
    $relativeFilePath = "$($realDeployManifestPath.SubString($parentFolder.Length+1))"
    Write-S3Object `
        -BucketName $AmazonS3BucketName `
        -Region $AmazonRegion `
        -File $relativeFilePath `
        -Key "$($relativeFilePath)" `
        -CannedACLName $AmazonCannedACLName
        
    $here = Get-Location
    "Current Directory: $here"
 
    "Moving back to project folder..."
    popd
    $currentFolder = Get-Location
    "Current Directory: $currentFolder"
    
    "Saving Current Revision $revision to Revision.txt file..."
    Set-Content -Value "$revision" -Path "./Revision.txt" -Encoding UTF8
    "Done."
}

