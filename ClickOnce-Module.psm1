function Create-ClickOnce {
    param($appProperName, `
        $appShortName, `
        $iconFilename, `
        $publisher, `
        $outputDir, `
        $certFile, `
        $deploymentUrl, `
        $bucketName, `
        $amazonRegion) 

    "Creating ClickOnce deployment for $appProperName..."

    "Getting last revision from Revision.txt..."
    $revisionString = Get-Content "../../Revision.txt"
    $revision = [Int32]::Parse($revisionString) + 1
    $version = "1.0.0.$revision"
    "Deploying as version: $version"

    # The first file is the "Entry Point" file, the main .exe.
    $files = $args[0] 
    
    # TODO: Use these two variables, or delete them
    $appManifest = "$appShortName.exe.manifest"
    $deployManifest = "$appShortName.application"

    $processor = "MSIL"
    $algorithm = "sha256RSA"

    $projectDir = "$($(Get-Location).Path)"
    $outputDir = "$projectDir/$outputDir"
    $relativeVersionDir = "Application Files/$appShortName" + "_$($version.Replace(".", "_"))"
    $versionDir = "$outputDir/$relativeVersionDir"
    
    "Project Dir: $projectDir"
    "Output Dir: $outputDir"
    "Version Dir: $versionDir"

    $appCodeBasePath = "$relativeVersionDir/$appManifest"
    $appManifestPath = "$versionDir/$appManifest"
    $deployManifestPath = "$outputDir/$deployManifest"
    $secondDeployManifestPath = "$versionDir/$deployManifest"
    $secondDeployUrl = "$deploymentUrl/$relativeVersionDir/$deployManifest"

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
        -Name $appProperName `
        -Version $version `
        -Processor $processor `
        -CertFile "$certFile" `
        -FromDirectory $versionDir `
        -TrustLevel FullTrust `
        -Algorithm $algorithm `
        -IconFile $iconFilename
    
    "Generating deployment manifest file: $deployManifestPath"
    mage -New Deployment `
        -ToFile "$deployManifestPath" `
        -Name $appProperName `
        -Version $version `
        -MinVersion none `
        -Processor $processor `
        -AppManifest "$appManifestPath" `
        -AppCodeBase "$($appCodeBasePath.Replace(" ", "%20"))" `
        -CertFile $certFile `
        -IncludeProviderURL true `
        -ProviderURL "$deploymentUrl/$deployManifest" `
        -Install true `
        -Publisher $publisher `
        -Algorithm $algorithm 

    #-ProviderURL "$deploymentUrl/$deployManifest" `
    "Renaming files for web server deployment with .deploy..."
    Get-ChildItem $versionDir | `
        Foreach-Object { `
            if (-not $_.FullName.EndsWith(".manifest")) { `
                Rename-Item $_.FullName "$($_.FullName).deploy" } } 

    "Resigning application manifest..."
    mage -Sign "$appManifestPath" -CertFile $certFile 
 
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
    mage -Sign "$deployManifestPath" -CertFile $certFile 

    "Loading deployment manifest to make second copy..."
    $secondXml = [xml](Get-Content "$deployManifestPath")

    "Altering second manifest..."
    $deploymentProviderNode = $secondXml.SelectSingleNode("//*[local-name() = 'deploymentProvider']")
    $deploymentProviderNode.SetAttribute("codebase", "$($secondDeployUrl.Replace(" ", "%20"))")

    "Saving second altered deployment manifest..."
    $secondXml.Save("$secondDeployManifestPath")

    "Signing second altered deployment manifest..."
    mage -Sign "$secondDeployManifestPath" -CertFile $certFile 

    "ClickOnce deployment created."
    "Uploading files to Amazon Web Services S3..."
    
    cd $outputDir

    $publishFiles = dir $versionDir -Recurse -File

    $parentFolder = [System.IO.Path]::GetFullPath("$outputdir")

    foreach ($f in $publishFiles) {
        $relativeFilePath = "$($f.FullName.SubString($parentFolder.Length+1))"
        UploadTo-AmazonS3 `
		-RelativeFilePath $relativeFilePath `
        -AmazonBucketName $bucketName `
        -AmazonRegion $amazonRegion
    }

    $realDeployManifestPath = [System.IO.Path]::GetFullPath($deployManifestPath)
    $relativeFilePath = "$($realDeployManifestPath.SubString($parentFolder.Length+1))"
    UploadTo-AmazonS3 `
	    -RelativeFilePath $relativeFilePath `
        -AmazonBucketName $bucketName `
        -AmazonRegion $amazonRegion
    

    "Saving Current Revision $revision to Revision.txt..."
    Set-Content -Value "$revision" -Path "../../Revision.txt"
    "Done."
}

