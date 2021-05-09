<# 	This module helps in creating two-node cluster file share in Azure.
	Run the commands from this module in the way mentioned below when running first time.
	1. Join-Domain
	2. Install-Roles
	3. New-S2DCluster
	4. New-ClusterDisk
	5. Add-ClusterFileServer
	5. Add-ClusterFileShare 
	6. Update-FileServerRoleIP #>
function Join-Domain {
	#This function joins a server to a domain using domain administrator credentials
	param (
		[CmdletBinding(SupportsShouldProcess)]
		[Parameter(Mandatory,
		HelpMessage="Enter the name of the domain that the VM will be joined to")]
		[string]$Domain,
		[Parameter(Mandatory,
		HelpMessage="Enter a username that has the domain join previliges")]
		[string]$AdminUsername,
		[Parameter(Mandatory,
		HelpMessage="Enter the password of the username that was provided")]
		[securestring]$AdminPassword
	)
	Begin {
		$ComputerName = hostname
		Write-Verbose -Message "Starting command Join-Domain on $ComputerName."
	}
	Process {
		try {
			#Write-Verbose -Message "Converting the password to secure string."
			#$SecDomainPasswd = ConvertTo-SecureString -String $AdminPassword -AsPlainText -Force
			Write-Verbose -Message "Creating new PSCredential Object."
			$DomainJoinCred = New-Object System.Management.Automation.PSCredential($AdminUsername, $AdminPassword)
			Write-Verbose -Message "Joining the computer $ComputerName to domain."
			Add-Computer -DomainName $Domain -Credential $DomainJoinCred -ErrorAction Stop
		}
		Catch {
			Write-Host "An Error Occured --> $_"
			"$Error"
		}
	}
	End {
		$GetDomain = (Get-WmiObject -Class Win32_ComputerSystem).domain #Checks if the computer is joined to domain or not.
		if ($GetDomain -ne "WORKGROUP") {
			Write-Verbose -Message "Ending command Join-Domain. Computer will restart now."
			Restart-Computer -Force
		}
		else {
			Write-Host "$ComputerName was not able to join to the domain. Refer the error for details."
			Write-verbose -Message "Ending command Join-Domain"
		}
	}
} 
function Install-Roles {
<# This function installs File Server and Failover clustering roles and 
   necessary management tools on the VMs #>
	param (
		[CmdletBinding(SupportsShouldProcess)]
		[Parameter(Mandatory,
		HelpMessage="Enter the server names separeted by commas")]
		[string[]]$VMs
	)
	Begin {
		Write-Verbose -Message "Starting function Install-Roles on $VMs"
	}
	Process {
		try {
			$LogRunDate = Get-Date -Format "MMddyyyy-hhmm"
			Write-Verbose -Message "Creating log directory if it does not exist."
			New-Item -ItemType Directory -Path "C:\AzureClusterScript\Logs" -ErrorAction SilentlyContinue | Out-File Null
			$LogPath = "C:\AzureClusterScript\Logs\Install-Roles_$($LogRunDate).log"
			Write-Verbose -Message "Installing File Server and Failover Clustering roles on $VMs"
			Invoke-Command $VMs{Install-WindowsFeature -Name FS-FileServer, Failover-Clustering -IncludeAllSubFeature -IncludeManagementTools}
		}
		Catch {
			Write-Host "An Error Occured. Refer to $LogPath for details."
			"$_"
			$ErrorString = $_ | Out-String
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => An Error occured - $_" | Out-File $LogFolder -Append -Encoding ascii -NoClobber
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => Exception Details - $($ErrorString)" | Out-File $LogFolder -Append -Encoding ascii -NoClobber
		}
	}
	End {
		Write-Verbose -Message "Ending function Install-Roles. $VMs will restart now."
		Invoke-Command $VMs{Restart-Computer -Force}
	}
}
function New-S2DCluster {
# This function creates a cluster, enables Storage Spaces Direct as cluster storage and configures cloud witness as cluster quorum
	param(
		[CmdletBinding(SupportsShouldProcess)]
		[Parameter(Mandatory,
		HelpMessage="Enter the server names separeted by commas")]
		[String[]]$VMs,
		[Parameter(Mandatory,
		HelpMessage="Enter a name for the cluster")]
		[String]$ClusterName,
		[Parameter(Mandatory,
		HelpMessage="Enter the name of the storage account")]
		[String]$StorageAccountName,
		[Parameter(Mandatory,
		HelpMessage="Enter the storage account access Key")]
		[String]$StorageAccessKey
	)
	Begin {
		Write-Verbose -Message "Starting command New-S2DCluster on Azure VMs $VMs."
	}
	Process {
		try {
			$LogRunDate = Get-Date -Format "MMddyyyy-hhmm"
			Write-Verbose -Message "Creating log directory if it does not exist."
			New-Item -ItemType Directory -Path "C:\AzureClusterScript\Logs" -ErrorAction SilentlyContinue | Out-File Null
			$LogPath = "C:\AzureClusterScript\Logs\New-S2DCluster_$($LogRunDate).log"
			Write-Verbose -Message "Validating whether $VMs can form the cluster or not."
			Test-Cluster -Node $VMs
			# Validating cluster helps in foreseeing any problem that could be aroused in creating cluster
			Write-Verbose -Message "Creating cluster now."
			New-Cluster -Node $VMs -Name $ClusterName -NoStorage -ErrorAction Stop
			<# When running New-Cluster cmdlet on Azure VMs which have Windows Server 2019, a static IP 
			is not needed to bring the Cluster Network Object (CNO) online. Failover Clustering in Win Server 2019 
			uses Distributed server Name (DSN) as Network name resoruce. DSN uses the underlying nodes' IPs to bring the CNO online #>
			Write-verbose -Message "Enabling shared storage for the cluster $ClusterName."
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => Enabling storage spaces direct on the cluster." 
			Enable-ClusterS2D -confirm:$False #confirm:$False does not ask user to provide confirmation when enabling Storage Spaces Direct for the cluster
			# Creates a storage pool for the cluster that acts as shared storage
			Write-Verbose  -Message "Configuring cluster quorum for $ClusterName."
			# Cloud witness acts as quorum for the cluster
			Set-ClusterQuorum -CloudWitness -AccountName $StorageAccountName -AccessKey $StorageAccessKey
			Write-Host "Successfully created cluster $ClusterName."
		}
		Catch {
			Write-Host "An Error Occured. Refer to $LogPath for details."
			"$_"
			$ErrorString = $_ | Out-String
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => An Error occured - $_" | Out-File $LogPath -Append -Encoding ascii -NoClobber
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => Exception Details - $($ErrorString)" | Out-File $LogPath -Append -Encoding ascii -NoClobber
		}
	}
	End {
		Write-Verbose -Message "Ending command New-S2DCluster on Azure VMs $VMs."
	}
}
function New-ClusterDisk {
# Creates a cluster virtual disk, partitions it and makes it a shared storage
param(
	[CmdletBinding(SupportsShouldProcess)]
	[Parameter(Mandatory,
	HelpMessage="Enter a name for the virtual disk")]
	[String]$ClusterVirtualDiskName,
	[Parameter(Mandatory,
	HelpMessage="Enter a size for the cluster disk")]
	[UInt64]$ClusterVirtualDiskSize,
	[Parameter(Mandatory,
	HelpMessage="Enter the drive letter")]
	[Char]$ClusterDiskDriveLetter
	#[switch]$ShadowCopyDisk
	)
	Begin{
		$ClusterName = Get-Cluster
		Write-Verbose -Message "Starting function New-ClusterDisk on $ClusterName."
	}
	Process {
		try {
			$LogRunDate = Get-Date -Format "MMddyyyy-hhmm"
			Write-Verbose -Message "Creating log directory if it does not exist."
			New-Item -ItemType Directory -Path "C:\AzureClusterScript\Logs" -ErrorAction SilentlyContinue | Out-File Null
			$LogPath = "C:\AzureClusterScript\Logs\New-ClusterDisk_$($LogRunDate).log"
			Write-Verbose -Message "Configuring cluster virtual disk"
			#if ($ShadowCopyDisk) {
				<# When -ShadowCopyDisk (swich) is used at the end of the New-ClusterDisk cmdlet,
				the cluster disk will be created with 4K AllocationUnitSize. As per the best practice in enabling 
				shadow copies for volumes, shadow copies need to be stored in storage volume (dedicated cluster disk) instead of storing the copies on data disk.
				If best practices are being followed, the source/data volume should have 64K AUS and storage volume shoud have 4K AUS. #>
				<# New-Volume -StoragePoolFriendlyName S2D* -FriendlyName $ClusterVirtualDiskName -Size $ClusterVirtualDiskSize -FileSystem NTFS -ProvisioningType Fixed -DriveLetter $ClusterDiskDriveLetter #>
			#}
			#else { 
				<#New-Volume -StoragePoolFriendlyName S2D* -FriendlyName $ClusterVirtualDiskName -Size $ClusterVirtualDiskSize -FileSystem NTFS -ProvisioningType Fixed -DriveLetter $ClusterDiskDriveLetter -AllocationUnitSize 65536#>
			#}
			New-Volume -StoragePoolFriendlyName S2D* -FriendlyName $ClusterVirtualDiskName -Size $ClusterVirtualDiskSize -FileSystem NTFS -ProvisioningType Fixed -DriveLetter $ClusterDiskDriveLetter -AllocationUnitSize 65536
		}
			catch {
			Write-Host "An Error Occured. Refer to $LogPath for details."
			"$_"
			$ErrorString = $_ | Out-String
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => An Error occured - $_" | Out-File $LogPath -Append -Encoding ascii -NoClobber
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => Exception Details - $($ErrorString)" | Out-File $LogPath -Append -Encoding ascii -NoClobber
		}
	}
	End {
		Write-Verbose -Message "Ending function New-Clusterdisk on $ClusterName."
	}
}
function Add-ClusterFileServer {
# This functions creates a file server as a cluster role with static IP assigned to it and attach it 
	param(
		[CmdletBinding(SupportsShouldProcess)]
		[Parameter(Mandatory)]
		[String]$ClusterFileServerName,
		[Parameter(Mandatory)]
		[String]$ClusterFileServerIP,
		[Parameter(Mandatory)]
		[String]$ClusterDiskFriendlyName
	)
	Begin {
		$ClusterName = Get-Cluster
		Write-Verbose -Message "Starting function Add-ClusterFileServer on $ClusterName."
	}
	Process	{
		try {
			$LogRunDate = Get-Date -Format "MMddyyyy-hhmm"
			Write-Verbose -Message "Creating log directory if it does not exist."
			New-Item -ItemType Directory -Path "C:\AzureClusterScript\Logs" -ErrorAction SilentlyContinue | Out-File Null
			$LogPath = "C:\AzureClusterScript\Logs\Add-ClusterFileServer_$($LogRunDate).log"
			# Gathers Physical disk resource name that has been assigned to cluster disk on the cluster
			$ClusterDiskResource = (Get-ClusterResource | Where-Object {$_.Name -match "$ClusterDiskFriendlyName"}).Name
			Write-Verbose -Message "Creating cluster role on the cluster $ClusterName."
			Add-ClusterFileServerRole -Storage $ClusterDiskResource -Name $ClusterFileServerName -StaticAddress $ClusterFileServerIP
		}
		catch {
			Write-Host "An Error Occured. Refer to $LogPath for details."
			"$_"
			$ErrorString = $_ | Out-String
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => An Error occured - $_" | Out-File $LogPath -Append -Encoding ascii -NoClobber
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => Exception Details - $($ErrorString)" | Out-File $LogPath -Append -Encoding ascii -NoClobber
		}
	}
	End {
		Write-Verbose -Message "Ending function Add-ClusterFileServer on $ClusterName"
	}
}
function Add-ClusterFileShare {
	<# This function creates a highly available file share on the file server role
	and will be hosted by one of the cluster disks attached to the file server role #>
	param (
		[CmdletBinding(SupportsShouldProcess)]
		[Parameter(Mandatory,
		HelpMessage="Give the share a name")]
		[String]$ShareName,
		[Parameter(Mandatory,
		HelpMessage="Enter the name of file server role that will host the share")]
		[string]$ClusterFileServerName,
		[Parameter(Mandatory,
		HelpMessage="Enter the drive letter assigned to the cluster disk that should host the file share. Eg: 'C:'")]
		[string]$DiskDriveLetter
	)
	Begin {
		Write-Verbose -Message "Starting function Add-ClusterFileShare on cluster role $ClusterRoleName."
	}
	Process {
		try {
			$LogRunDate = Get-Date -Format "MMddyyyy-hhmm"
			Write-Verbose -Message "Creating log directory if it does not exist."
			New-Item -ItemType Directory -Path "C:\AzureClusterScript\Logs" -ErrorAction SilentlyContinue | Out-File Null
			$LogPath = "C:\AzureClusterScript\Logs\Add-ClusterFileShare_$($LogRunDate).log"
			$ShareLocalPath = "$DiskDriveLetter\Shares\$ShareName"
			Write-Verbose -Message "Testing whether the local path to share $ShareLocalPath exists on the cluster node."
			$CheckDirectoryExists = Test-Path -Path $ShareLocalPath
			if ($CheckDirectoryExists) {
				Write-Verbose -Message "Local path to share already exists."
			}
			else {
				Write-Verbose -Message "Local path to Share $ShareLocalPath does not exist on the cluster node. Creating now."
				New-Item -ItemType "Directory" -Path $ShareLocalPath
			}
			Write-Verbose -Message "Creating highly available share $ShareName."
			New-SmbShare -ContinuouslyAvailable $true -FolderEnumerationMode "Unrestricted" -Path $ShareLocalPath -Name $ShareName -ScopeName $ClusterFileServerName -ErrorAction Stop
			Write-Host "Successully created clustered share $ShareName on $ClusterFileServerName."
			Write-Verbose "Granting Everyone Full control on the share."
			Grant-SmbShareAccess -Name $ShareName -ScopeName $ClusterFileServerName -AccountName "Everyone" -AccessRight "Full" -Confirm:$false
		}
		catch {
			Write-Host "An Error Occured. Refer to $LogPath for details."
			"$_"
			$ErrorString = $_ | Out-String
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => An Error occured - $_" | Out-File $LogPath -Append -Encoding ascii -NoClobber
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => Exception Details - $($ErrorString)" | Out-File $LogPath -Append -Encoding ascii -NoClobber
		}
	}		
	End {
		Write-Verbose -Message "Ending function Add-ClusterFileShare on cluster role $FileServerName."
	}
}
function Update-FileServerRoleIP {
	<# This function updates the Ip Address resource of the cluster file server with the load balancing rule 
	that is configured on the Azure Internal load balancer. #>
	param (
		[CmdletBinding(SupportsShouldProcess)]
		[Parameter(Mandatory,
		HelpMessage="Name of the file server role for which load balancing rule is in place")]
		[String]$ClusterRoleName,
		[Parameter(Mandatory,
		HelpMessage="IP address of the file server that needs load balancing")]
		[String]$ClusterRoleIP,
		[Parameter(Mandatory,
		HelpMessage="Enter the health port configured at the load balancer")]
		[String]$HealthPort
	)
	Begin {
		$ClusterName = (Get-Cluster).Name
		Write-Verbose -Message "Starting function Update-FileServerIP on cluster resource $IPResourceName."
		}
	Process {
		try {
			$LogRunDate = Get-Date -Format "MMddyyyy-hhmm"
			Write-Verbose -Message "Creating log directory if it does not exist."
			New-Item -ItemType Directory -Path "C:\AzureClusterScript\Logs" -ErrorAction SilentlyContinue | Out-File Null
			$LogPath = "C:\AzureClusterScript\Logs\Update-FileServerRoleIP_$($LogRunDate).log"
			Write-Verbose -Message "Collecting cluster network information for cluster $ClusterName."
			$ClusterNetworkName=(Get-ClusterNetwork).Name
			Write-Verbose -Message "Collecting IP address resource information for file server $ClusterRoleName."
			$IPResourceName = (Get-ClusterGroup $ClusterRoleName | Get-ClusterResource | Where-Object {$_.Name -match "IP"}).Name 
			# Updates file server IP Address resource with the Load balancer health probe used for the file server IP
			$params = @{"Address"="$ClusterRoleIP";
			"ProbePort"="$HealthPort";
			"SubnetMask"="255.255.255.255";
			"Network"="$ClusterNetworkName";
			"OverrideAddressMatch"=1; 
			"EnableDhcp"=0}
			# Updates File Server IP Address resource with the azure load balancing rule that is already configured
			Get-ClusterResource $IPResourceName | Set-ClusterParameter -Multiple $params
			Write-Verbose -Message "Restarting cluster group $ClusterRoleName."
			Stop-ClusterGroup -Name $ClusterRoleName
			Start-ClusterGroup -Name $ClusterRoleName
		}
		catch {
			Write-Host "An Error Occured. Refer to $LogPath for details."
			"$_"
			$ErrorString = $_ | Out-String
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => An Error occured - $_" | Out-File $LogPath -Append -Encoding ascii -NoClobber
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => Exception Details - $($ErrorString)" | Out-File $LogPath -Append -Encoding ascii -NoClobber
		}
	}
	End {
	Write-Verbose -Message "Ending function Update-FileServerIP on cluster resource $IPResourceName."
	}
}
function Rename-ClusterFileServer {
	param (
		[CmdletBinding(SupportsShouldProcess)]
		[Parameter(Mandatory,
		HelpMessage="Enter the name of the file server that needs to be renamed")]
		[string]$ClusterFileServerName,
		[Parameter(Mandatory,
		HelpMessage="Enter the name of the file server that needs to be renamed")]
		[string]$NewClusterFileServerName
	)
	Begin {
		Write-Verbose -Message "Starting function Rename-ClusterFileServer."
	}
	Process {
		try {
			$LogRunDate = Get-Date -Format "MMddyyyy-hhmm"
			Write-Verbose -Message "Creating log directory if it does not exist."
			New-Item -ItemType Directory -Path "C:\AzureClusterScript\Logs" -ErrorAction SilentlyContinue | Out-File Null
			$LogPath = "C:\AzureClusterScript\Logs\Rename-ClusterFileServer_$($LogRunDate).log"
			Write-Verbose -Message "Renaming Cluster group $ClusterFileServerName to $NewClusterFileServerName"
			$GetClusterGroup = Get-ClusterGroup $ClusterFileServerName -ErrorAction Stop
			($GetClusterGroup).Name = "$NewClusterFileServerName"
			Write-Verbose -Message "Renaming $ClusterFileServerName network name resource to $NewClusterFileServerName."
			$GetNewClusterGroup = Get-ClusterGroup $NewClusterFileServerName
			$GetClusterResource = $GetNewClusterGroup | Get-ClusterResource
			($GetClusterResource | Where-Object {$_.ResourceType -match "Name"}).Name = "$NewClusterFileServerName"
			#gathers file server resource for cluster resource and renames it from old to new
			($GetClusterResource | Where-Object {$_.ResourceType -match "File"}).Name = "File Server (\\$NewClusterFileServerName)" 
			Write-Verbose -Message "Cluster Resource $NewClusterFileServerName going offline now."
			Stop-ClusterResource $NewClusterFileServerName
			Write-Verbose -Message "Renaming the Dns Name value of the network name resource from $ClusterFileServerName to $NewClusterFileServerName."
			$GetClusterResource | Where-Object {$_.ResourceType -match "Name"} | Set-ClusterParameter -Name DnsName -Value "$NewClusterFileServerName"
			#gathers cluster resource name information and renames it to new name
			$GetClusterResource | Where-Object {$_.ResourceType -match "Name"} | Set-ClusterParameter -Name "Name" -Value "$NewClusterFileServerName"
			Write-Verbose -Message "Starting cluster Group $NewClusterFileServerName."
			Start-ClusterGroup $NewClusterFileServerName
			#updating the DNS with the new network name of the cluster resource
			Get-ClusterGroup $NewClusterFileServerName | Get-ClusterResource | Where-Object {$_.ResourceType -match "Name"} | Update-ClusterNetworkNameResource
			Write-Host "Succesfully renamed the cluster file server to $NewClusterFileServerName."
			Get-ClusterResource $NewClusterFileServerName | Get-ClusterParameter | Where-Object {$_.ResourceType -match "Name"}
		}
		catch {
			Write-Host "An Error Occured. Refer to $LogPath for details."
			"$_"
			$ErrorString = $_ | Out-String
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => An Error occured - $_" | Out-File $LogPath -Append -Encoding ascii -NoClobber
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => Exception Details - $($ErrorString)" | Out-File $LogPath -Append -Encoding ascii -NoClobber
		}
	}
	End {
		Write-Verbose -Message "Ending function Rename-ClusterFileServer."
	}
}
function Resize-ClusterDisk {
	param (
		[CmdletBinding()]
		[Parameter(Mandatory,
		HelpMessage="Eneter the name of the cluster disk that needs to be resized")]
		[string]$ClusterVirtualDiskName,
		[Parameter(Mandatory,
		HelpMessage="Enter the size")]
		[UInt64]$NewSize
	)
	Begin {
		Write-Verbose -Message "Starting function Resize-ClusterDisk."
	}
	Process {
		try {
			$LogRunDate = Get-Date -Format "MMddyyyy-hhmm"
			Write-Verbose -Message "Creating log directory if it does not exist."
			New-Item -ItemType Directory -Path "C:\AzureClusterScript\Logs" -ErrorAction SilentlyContinue | Out-File Null
			$LogPath = "C:\AzureClusterScript\Logs\Resize-ClusterDisk_$($LogRunDate).log"
			Write-Verbose -Message "Resizing the virtual disk $ClusterVirtualDiskName."
			#choose virtual disk
			$GetClusterDisk = Get-VirtualDisk $ClusterVirtualDiskName -ErrorAction Stop
			$GetClusterDisk | Resize-VirtualDisk -Size $NewSize -ErrorAction Stop
			Write-Verbose -Message "Resizing the virtual disk partition."
			#Gathers the virtual disk partition
			$GetClusterDiskPartition = $GetClusterDisk | Get-Disk | Get-Partition | Where-Object {$_.PartitionNumber -Eq 2}
			#Resizes the disk partition to its maximum supported size
			$GetClusterDiskPartition | Resize-Partition -Size ($GetClusterDiskPartition | Get-PartitionSupportedSize).SizeMax
			#When the partition gets resized, volume gets resized too
			Write-Host "Successfully resized the virtual disk $ClusterVirtualDiskName to $NewSize."
		}
		catch {
			Write-Host "An Error Occured. Refer to $LogPath for details."
			"$_"
			$ErrorString = $_ | Out-String
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => An Error occured - $_" | Out-File $LogPath -Append -Encoding ascii -NoClobber
			"`r`n$(Get-Date -format 'yyyy/MM/dd-HH:mm') => Exception Details - $($ErrorString)" | Out-File $LogPath -Append -Encoding ascii -NoClobber
		}
	}
}