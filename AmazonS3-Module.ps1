function UploadTo-AmazonS3 {
    param($relativeFilePath)

    #The bucket name must match the domain name for Amazon's DNS to work.
    "Uploading File: $relativeFilePath ..."
    Write-S3Object -BucketName $bucketName `
        -Region $amazonRegion `
        -File $relativeFilePath `
        -Key "$($relativeFilePath)" `
        -CannedACLName public-read
}