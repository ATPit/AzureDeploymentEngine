#Internal Function
Function Invoke-AffinityGroup
{
	Param (
		$AffinityGroupName,
		$Location,
		$SubscriptionId
	)
	
	
	Enable-AzdeAzureSubscription $SubscriptionId
	$existingAffinityGroup = Get-AzureAffinityGroup $AffinityGroupName -ErrorAction 0
	if (!$existingAffinityGroup)
	{
        #Locally silence verbose logging
        if ($verboselevel -lt 3)
        {
            Set-variable -Name VerbosePreference -Scope local -Value "SilentlyContinue"
        }
	    New-AzureAffinityGroup -Name $AffinityGroupName -Location $Location | out-null
	}
	Else
	{
		if (($existingAffinityGroup.Location) -ne $Location)
		{
			Write-Error "Affinity group $AffinityGroupName but with the wrong location. Please delete it manually"
			Break
		}
	    Write-Verbose "Affinity group $AffinityGroupName with location $Location already exists."
	}

	
}

#Internal Function
Function Invoke-StorageAccount
{
	Param (
		$StorageAccountName,
		$AffinityGroupName,
		$SubscriptionId
	)
	
	
	Enable-AzdeAzureSubscription $SubscriptionId
    #Locally silence verbose logging
        if ($verboselevel -lt 3)
        {
            Set-variable -Name VerbosePreference -Scope local -Value "SilentlyContinue"
        }
	$ExistingStorageAccount = Get-AzureStorageAccount -StorageAccountName $StorageAccountName -ErrorAction 0
	if (!$ExistingStorageAccount)
	{
		Write-Verbose "Creating Storage account $StorageAccountName"
	    New-AzureStorageAccount -StorageAccountName $StorageAccountName  -AffinityGroup $AffinityGroupName | out-null
	}
	Else
	{
		if (($ExistingStorageAccount.AffinityGroup) -ne $AffinityGroupName)
		{
			Write-Error "Storage account $StorageAccountName exists, but in the wrong affinity group. Please delete manually"
			Write-Error "      Expected $AffinityGroupName, got $($ExistingStorageAccount.AffinityGroup)"
			Break
		}
	    Write-Verbose "Storage account $StorageAccountName already exists"
	}

    if ((Get-AzureSubscription -Current).CurrentStorageAccountName -ne $StorageAccountName)
    {
        $currentsub = Get-AzureSubscription -Current
        Set-AzureSubscription -SubscriptionName $currentsub.SubscriptionName -CurrentStorageAccountName $StorageAccountName
    }
    $StorageAccountName
	
}

#Invoke-Network -networksettings $NetworkSettings -SubscriptionId $SubscriptionId -project $ThisProject
Function Invoke-network
{
    Param (
    $subscriptionid,
    $AffinityGroupName,
    $project,
    $networkname)

    try
    {
        $existingNetwork = Get-AzureVNetSite -VNetName $networkname
    }
    catch
    {}

    if ($existingNetwork)
    {
        #Verify that the network is correctly setup
    }
    Else
    {
        Write-verbose "Creating network $networkname in Affinity Group $AffinityGroupName"
        
        #Get the subnets
        $subnets = $network.Subnets
        $ArSubnetsObj = @()
        Foreach ($subnet in $subnets)
        {
            
            $subnetname =  $subnet.subnetname
            $subnetobj = "" | Select SubnetPrefix, SubnetName
            $subnetobj.Subnetprefix = $subnet.SubnetCidr
            $subnetobj.SubnetName = $subnetname
            $ArSubnetsObj += $subnetobj
            $subnetobj,$subnetprefix,$subnetname = $null
        }

        #Create the network
        New-AzureANVNetSite -VNetName $networkname -AffinityGroupName $AffinityGroupName -VNetAddressPrefix $network.AddressPrefix -subnets $ArSubnetsObj #-SubnetName $SubnetName -SubnetAddressPrefix $SubnetAddressPrefix 
        Write-enhancedVerbose -MinimumVerboseLevel 1 -Message "Network updated"
    }


}

function Invoke-AzDeVirtualMachine
{
    Param (
        [Parameter(ParameterSetName='SingleVm')]
        [AzureDeploymentEngine.Vm]$vm,
        $affinityGroupName
    )

    $cloudserviceName = $vm.VmSettings.CloudServiceName

    if (!($cloudserviceName))
    {
        Throw "Invalid or no cloudservice defined"
    }


    
        
    if (!(Get-AzureService -ServiceName $cloudserviceName -ErrorAction 0 -verbose:$false))
    {
        Write-enhancedVerbose -MinimumVerboseLevel 2 -Message "Creating new cloud service $cloudserviceName"
        New-AzureService -AffinityGroup $affinityGroupName -ServiceName $cloudserviceName | out-null
    }
    Else
    {
        Write-enhancedVerbose -MinimumVerboseLevel 3 -Message "checking that cloud service $cloudserviceName is unlocked"
        $cloudservicelockCounter = 0
        Do
        {
            if ($cloudservicelockCounter -gt 0)
            {
                Start-Sleep -Seconds 10
            }
            if ($cloudservicelockCounter -eq 1)
            {
                Write-enhancedVerbose -MinimumVerboseLevel 2 -Message "Waiting for cloud service $cloudserviceName to become unlocked"
            }
            if ($cloudservicelockCounter -gt 60)
            {
                throw "Timed out waiting for cloud service $cloudserviceName to become unlocked"
            }
            $cslockstatus = Get-AzureDeployment -ServiceName $cloudserviceName -Verbose:$false -ErrorAction SilentlyContinue
            $cloudservicelockCounter ++
        }
        until (($cslockstatus.Locked -eq $false) -or ($cslockstatus -eq $null))
        
    }
    #csvms is an array of vms going to the same cs. These will have to be done one by one
   
    #Assume the vm does not already exist
    $DoDeployVM = $true

    #Test if the VM exists
    $VMsCheck = Get-AzureVM -verbose:$false
    if ($vmsCheck | where {$_.Name -eq $vm.VmName})
    {
        $VMCheck = $VMsCheck | where {$_.Name -eq $vm.VmName}
        $DoDeployVM = $false
        #VM exists in the right cloud service
        if (($vm.VmSettings.AlwaysRedeploy -eq $true) -and ($VMCheck.ServiceName -eq $cloudserviceName))
        {
            Write-enhancedVerbose -MinimumVerboseLevel 1 -Message "Found existing vm $($vm.VmName). Tearing down according to settings"
            Remove-AzureVM -Name $vmcheck.Name -ServiceName $vmcheck.ServiceName -DeleteVHD -Verbose:$false
            $DoDeployVM = $true
        }
        Elseif (($vm.VmSettings.AlwaysRedeploy -eq $true) -and ($VMCheck.ServiceName -ne $cloudserviceName))
        {
            Write-enhancedVerbose -MinimumVerboseLevel 1 -Message "Found existing vm $($vm.VmName), but in the wrong cloud service. Skipping, although settings state alwaysredeploy"
            Write-Warning "Found existing vm $($vm.VmName), but in the wrong cloud service. Skipping, although settings state alwaysredeploy"
        }
        Else
        {
            Write-enhancedVerbose -MinimumVerboseLevel 1 -Message "Found existing vm $($vm.VmName). Skipping."
        }
        


        if ($VMCheck.ServiceName -ne $cloudserviceName)
        {
            #VM exists, but in different subnet
            Write-Warning "VM $($VMCheck.Name) already exists, but in the wrong cloud service"
        } 

        if ($VMCheck.Status -ne "ReadyRole")
        {
            if ($vm.vmsettings.StartIfStopped -eq $true)
            {
                Write-enhancedVerbose -MinimumVerboseLevel 2 -Message "Existing vm $($vm.VmName) seems to be shutdown. Booting. This might take a few minutes."
                Start-AzdeAzureVM -vm $VMCheck -wait $true
            }
            Else
            {
                Write-enhancedVerbose -MinimumVerboseLevel 3 -Message "Existing vm $($vm.VmName) seems to be shutdown. Leaving it according to settings"
            }
            

        }
        
        $vmcheck | Add-Member -MemberType NoteProperty -Name "AlreadyExistingVm" -Value $true -Force
        if ($DoDeployVM -ne $true)
        {
            return $VMCheck
        }
        
    }
    if ($DoDeployVM -eq $true)
    {
        #Create the VM
        $image = Get-AzureVMImage -verbose:$false| where {$_.ImageFamily -eq $vm.VmSettings.VmImage} | Sort-Object PublishedDate | Select -First 1
        
        #If that didnt work, try using the label. Maybe the full name was specified.
        if (!$image)
        {
            Get-AzureVMImage -verbose:$false| where {$_.Label -eq $vm.VmSettings.VmImage}
        }
        if (!$image){throw "Could not find the image specified ( $($vm.VmSettings.VmImage) ). Specify a valid image (either ImageFamily or Label from get-azurevmimage)"}
        $azurevm = New-AzureVMConfig -Name $vm.VmName -InstanceSize $vm.VmSettings.VMSize -Image $image.imagename
        if ($vm.VmSettings.JoinDomain -eq $true)
        {
            #TODO: This code should be moved out of here:
            #Get the domain settings
            if (!($Project.ProjectSettings.AdDomainName))
            {
                $Project.ProjectSettings.AdDomainName = $projectname.Replace(" ","")
                $Project.ProjectSettings.AdDomainName = $Project.ProjectSettings.AdDomainName + ".ad"
                Write-enhancedVerbose -MinimumVerboseLevel 1 -Message "setting AD domain name to $($Project.ProjectSettings.AdDomainName)"
            }

            $azdeAdDomainName = $project.ProjectSettings.AdDomainName
            $azurevm | Add-AzureProvisioningConfig -WindowsDomain -AdminUsername $vm.VmSettings.LocalAdminCredential.UserName -Password $vm.VmSettings.LocalAdminCredential.Password -domainpassword $vm.VmSettings.DomainJoinCredential.Password -DomainUserName $vm.VmSettings.DomainJoinCredential.UserName -Domain $azdeAdDomainName -JoinDomain $azdeAdDomainName | out-null
        }
        Else
        {
            $azurevm | Add-AzureProvisioningConfig -Windows -AdminUserName $vm.VmSettings.LocalAdminCredential.UserName -Password $vm.VmSettings.LocalAdminCredential.Password        
        }
        
        
        if ($vm.VmSettings.DataDiskSize -gt 0)
        {
            $datadisksizeInGb = ($vm.VmSettings.DataDiskSize) # / 1GB
            $azurevm |Add-AzureDataDisk -CreateNew -DiskSizeInGB $datadisksizeInGb -DiskLabel 'DataDrive' -LUN 0 -ErrorVariable datadiskerror| out-null
        }

        if ($datadiskerror)
        {
            Write-enhancedVerbose -MinimumVerboseLevel 1 -Message "Couldn't add the data disk to vm $($vm.VmName): $datadiskerror. Skipping this VM."
            Write-error "Couldn't add the data disk to vm $($vm.VmName): $datadiskerror. Skipping this VM"
            $datadiskerror = $null
            return
        }

        if ($vm.VmSettings.Subnet)
        {
            $azurevm | Set-AzureSubnet -SubnetNames $vm.vmsettings.Subnet | out-null
        }
        $nowtime = get-date

        if (($vm.VmSettings.WaitforVmDeployment) -eq $false)
        {
            Write-enhancedVerbose -MinimumVerboseLevel 1 -Message "Deploying vm $($vm.VmName) - started $nowtime"
        }
        Else
        {
            Write-enhancedVerbose -MinimumVerboseLevel 1 -Message "Deploying vm $($vm.VmName) - started $nowtime - will wait for the vm to be deployed"
        }
        
        #Get the real vnet name in case "projectname" was used
        #case-insensitive replace
        $Actualnetworkname = [AzureDeploymentEngine.StringExtensions]::Replace($vm.VmSettings.VnetName,"projectname",$projectname,"OrdinalIgnoreCase")
        $azurevm | New-AzureVM -ServiceName $vm.vmsettings.cloudservicename -VNetName $Actualnetworkname -WaitForBoot:$vm.VmSettings.WaitforVmDeployment -Verbose:$false -WarningAction SilentlyContinue | out-null
        
        
        $ReturnObjectVM = get-azurevm -Verbose:$false -ServiceName $vm.vmsettings.cloudservicename -Name $vm.VmName
        $ReturnObjectVM | Add-Member -MemberType NoteProperty -Name "AlreadyExistingVm" -Value $false -Force
        return $ReturnObjectVM
    }

      
    


}


function Start-AzdeAzureVM
{
    Param (
        $vm,
        [bool]$waitforboot
    )
    $vm = get-azurevm -Name $vm.Name -ServiceName $vm.servicename
    if (!$vm)
    {
        write-error "I was told to start VM $($vm.Name) in cloudservice $($vm.servicename), but I couldn't find it."
    }

    $vm | Start-AzureVM -Verbose:$false
    
        #Attempt connection
        $retries = 0
        Do {
            if ($retries -gt 1)
            {
                start-sleep -Seconds 10
            }
            
            $vm = $vm | get-azurevm -Verbose:$false

            $retries ++
        }
        until (($retries -gt 30) -or ($vm.status -eq "ReadyROle"))
        if ($retries -gt 30)
        {
            Write-error "Timed out waiting for VM $($vm.Name) to start"
        }
    

}