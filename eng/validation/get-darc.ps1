$path = "$PSScriptRoot\darc\$(New-Guid)"

& $PSScriptRoot\..\common\darc-init.ps1 -darcVersion "1.1.0-beta.20418.1" -toolpath $path | Out-Host

return "$path\darc.exe"
