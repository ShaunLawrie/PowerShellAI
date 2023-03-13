$Script:OpenAIKey = $null

foreach ($directory in @('Public', 'Private')) {
    Get-ChildItem -Path "$PSScriptRoot\$directory" -Recurse -Filter "*.ps1" | ForEach-Object { . $_.FullName }
}
