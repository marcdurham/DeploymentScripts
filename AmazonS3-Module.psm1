function UploadTo-AmazonS3 {
   param($relativeFilePath, `
		$amazonBucketName, `
		$amazonRegion)
		
    #The bucket name must match the domain name for Amazon's DNS to work.
	"Amazon Bucket: $amazonBucketName"
	"Amazon Region: $amazonRegion"
    "Uploading File: $relativeFilePath ..."
    Write-S3Object -BucketName $amazonBucketName `
        -Region $amazonRegion `
        -File $relativeFilePath `
        -Key "$($relativeFilePath)" `
        -CannedACLName public-read
}