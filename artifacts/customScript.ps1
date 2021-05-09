#Copy azopy executable from storage account to the temp folder
Start-BitsTransfer "https://lollisa.blob.core.windows.net/scripts/azcopy.exe" -Destination C:\Windows\System32
#Change the directory to the path where executable is stored
cd "C:\Windows\System32"
#Copy powershell module from storage account to powershell modules path
.\azcopy.exe copy https://lollisa.blob.core.windows.net/scripts/AzureStorageSpacesDirectClusterShare "C:\Program Files\WindowsPowershell\Modules" --recursive
#Delete executable file
Remove-Item -Path C:\Windows\System32\azcopy.exe -Force