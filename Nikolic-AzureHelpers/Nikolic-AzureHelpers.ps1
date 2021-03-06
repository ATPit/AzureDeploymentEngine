function New-AzureANAffinityGroup
{
    param
    (
        # Specifies a name for the new affinity group that is unique to the subscription.
        [Parameter(Mandatory)]
        [String]
        $Name,
        
        # The Location parameter specifies the geographical location of the data center where the affinity group will be created.
        [Parameter(Mandatory)]
        [String]
        $Location
        )

        # Check if the current subscription's storage account's location is the same as the Location parameter
$subscription = Get-AzureSubscription -Current
$currentStorageAccountLocation = (Get-AzureStorageAccount -StorageAccountName $subscription.CurrentStorageAccountName).GeoPrimaryLocation

if ($Location -ne $currentStorageAccountLocation)
{
    throw "Selected location parameter value, ""$Location"" is not the same as the active (current) subscription's current storage account location `
        ($currentStorageAccountLocation). Either change the location parameter value, or select a different storage account for the subscription."
}


    
    $affinityGroup = Get-AzureAffinityGroup -Name $Name -ErrorAction SilentlyContinue
    if ($affinityGroup -eq $null)
    {
        try
        {
            New-AzureAffinityGroup -Name $Name -Location $Location -ErrorAction Stop
            Write-Verbose "Created affinity group $Name"
        }

        catch
        {

            Write-Error "Cannot create the affinity group $Name on $Location. $($_.Exception.Message)"

        }
    }
    else
    {
        if ($affinityGroup.Location -ne $Location)
        {
            Write-Warning "Affinity group with name $Name already exists but in location $($affinityGroup.Location), not in $Location"
        }
        else {
            Write-Warning "Affinity group with name $Name already exists in location $($affinityGroup.Location)."
        }
    }
}
  

#endregion

#region New-AzureANVnetConfigurationFile

<#
.Synopsis
   Create an empty VNet configuration file.
.DESCRIPTION
   Create an empty VNet configuration file.
.EXAMPLE
    New-AzureANVnetConfigurationFile -FilePath "$env:temp\vnet.netcfg"
.INPUTS
   None
.OUTPUTS
   None
#>
function New-AzureANVnetConfigurationFile
{
    param (
		[Parameter(Mandatory=$true)]
        [String]$FilePath
    )
    
    # get an XMLTextWriter to create the XML
    # If encoding is null it writes the file out as UTF-8, and omits the encoding attribute from the ProcessingInstruction.
    # $XmlWriter = New-Object System.XMl.XmlTextWriter($Path,$null) 
    $XmlWriter = New-Object System.XMl.XmlTextWriter($FilePath,[Text.UTF8Encoding]::UTF8) 

    # choose a pretty formatting
    $xmlWriter.Formatting = 'Indented'
    $xmlWriter.Indentation = 1
    $XmlWriter.IndentChar = "`t" 

    # write the header
    $xmlWriter.WriteStartDocument()

    # Windows Azure Virtual Network Configuration Schema
    # http://msdn.microsoft.com/en-us/library/windowsazure/jj157100.aspx

    $xmlWriter.WriteStartElement('NetworkConfiguration')
    $XmlWriter.WriteAttributeString('xmlns:xsd',"http://www.w3.org/2001/XMLSchema")
    $XmlWriter.WriteAttributeString('xmlns:xsi',"http://www.w3.org/2001/XMLSchema-instance")
    $XmlWriter.WriteAttributeString('xmlns',"http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")

    $xmlWriter.WriteStartElement('VirtualNetworkConfiguration')
    $xmlWriter.WriteStartElement('Dns')
    $xmlWriter.WriteEndElement()
    $xmlWriter.WriteStartElement('VirtualNetworkSites')
    $xmlWriter.WriteEndElement()
    $xmlWriter.WriteEndElement()

    # close the "NetworkConfiguration" node
    $xmlWriter.WriteEndElement()

    # finalize the document
    $xmlWriter.WriteEndDocument()
    $xmlWriter.Flush()
    $xmlWriter.Close() 

}

#endregion

#region Set-AzureANVNetFileValue

<#
.SYNOPSIS
   Sets the provided values in the VNet file of a subscription's VNet file 
.DESCRIPTION
   It sets the VNetName and AffinityGroup of a given subscription's VNEt configuration file.
.EXAMPLE
    Set-AzureANVNetFileValue -FilePath c:\temp\servvnet.netcfg -VNet testvnet -AffinityGroupName affinityGroup1
.INPUTS
   None
.OUTPUTS
   None
#>
function Set-AzureANVNetFileValue
{
    [CmdletBinding()]
    param (
        
        # The path to the exported VNet file
        [String]$FilePath, 
        
        # Name of the new VNet site
        [String]$VNet, 
        
        # The affinity group the new Vnet site will be associated with
        [String]$AffinityGroupName, 
        
        # Address prefix for the Vnet.
        [String]$VNetAddressPrefix, 
        
        # The name of the subnet to be added to the Vnet
        #[String] $SubnetName, 
        
        # Array of subnets
         $Subnets
        )
    
    $xml = New-Object XML
    $xml.Load($FilePath)
    
    $vnetSiteNodes = $xml.GetElementsByTagName("VirtualNetworkSite")
    
    $foundVirtualNetworkSite = $null
    if ($vnetSiteNodes -ne $null)
    {
        $foundVirtualNetworkSite = $vnetSiteNodes | Where-Object { $_.name -eq $VNet }
    }

    if ($foundVirtualNetworkSite -ne $null)
    {
        $foundVirtualNetworkSite.AffinityGroup = $AffinityGroupName
    }
    else
    {
        $virtualNetworkSites = $xml.NetworkConfiguration.VirtualNetworkConfiguration.GetElementsByTagName("VirtualNetworkSites")
        if ($null -ne $virtualNetworkSites)
        {
            
            $virtualNetworkElement = $xml.CreateElement("VirtualNetworkSite", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            
            $vNetSiteNameAttribute = $xml.CreateAttribute("name")
            $vNetSiteNameAttribute.InnerText = $VNet
            $virtualNetworkElement.Attributes.Append($vNetSiteNameAttribute) | Out-Null
            
            $affinityGroupAttribute = $xml.CreateAttribute("AffinityGroup")
            $affinityGroupAttribute.InnerText = $AffinityGroupName
            $virtualNetworkElement.Attributes.Append($affinityGroupAttribute) | Out-Null
            
            $addressSpaceElement = $xml.CreateElement("AddressSpace", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")            
            $addressPrefixElement = $xml.CreateElement("AddressPrefix", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            $addressPrefixElement.InnerText = $VNetAddressPrefix
            $addressSpaceElement.AppendChild($addressPrefixElement) | Out-Null
            $virtualNetworkElement.AppendChild($addressSpaceElement) | Out-Null
            
            $subnetsElement = $xml.CreateElement("Subnets", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            foreach ($subnet in $Subnets)
			{
				$subnetname = $subnet.subnetname
        		$subnetprefix = $subnet.subnetprefix
			
				$subnetElement = $xml.CreateElement("Subnet", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
	            $subnetNameAttribute = $xml.CreateAttribute("name")
	            $subnetNameAttribute.InnerText = $SubnetName
	            $subnetElement.Attributes.Append($subnetNameAttribute) | Out-Null
	            $subnetAddressPrefixElement = $xml.CreateElement("AddressPrefix", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
	            $subnetAddressPrefixElement.InnerText = $subnetprefix
	            $subnetElement.AppendChild($subnetAddressPrefixElement) | Out-Null
	            $subnetsElement.AppendChild($subnetElement) | Out-Null
	            $virtualNetworkElement.AppendChild($subnetsElement) | Out-Null
			}
			
			
            
            $virtualNetworkSites.AppendChild($virtualNetworkElement) | Out-Null
        }
        else
        {
            throw "Can't find 'VirtualNetworkSite' tag"
        }
    }
    
    $xml.Save($filePath)
}

#endregion

#region New-AzureANVNetSite

<#
.SYNOPSIS
   Creates a Virtual Network Site if it does not exist and sets the subnet details.
.DESCRIPTION
   Creates the VNet site if it does not exist. It first downloads the network configuration for the subscription.
   If there is no network configuration, it creates an empty one first using the New-AzureANVnetConfigurationFile helper
   function, then updates the network file with the provided VNet settings also by adding the subnet.
.EXAMPLE
   New-AzureANVNetSite -VNetName NovaVnet -SubnetName NovaSubnet -AffinityGroupName NovaAff
#>
function New-AzureANVNetSite
{
    [CmdletBinding()]
    param
    (
        
        # Name of the Vnet site
        [Parameter(Mandatory)]
        [String]
        $VNetName,
        
        # Name of the subnet
        [Parameter(Mandatory)]
        $Subnets,
        
        # The affinity group the vnet will be associated with
        [Parameter(Mandatory)]
        [String]
        $AffinityGroupName,
        
        # Address prefix for the VNet 
        [String]$VNetAddressPrefix
        

        )


        # Check if the VNet site exists. If it does, throw an error.
        try{$VNetSite = Get-AzureVNetSite -VNetName $VNetName -ErrorAction SilentlyContinue}
        catch {}
        
        if ($VNetSite -ne $null)
        {
            throw "VNet site $VNetName already exists. Please provide a different name."
        }
    
    $vNetFilePath = "{0}\{1}{2}" -f $env:temp, $AffinityGroupName, 'VNet.netcfg'
    Get-AzureVNetConfig -ExportToFile $vNetFilePath | Out-Null
    if (!(Test-Path $vNetFilePath))
    {
        New-AzureANVnetConfigurationFile -FilePath $vNetFilePath
    }

	Set-AzureANVNetFileValue -FilePath $vNetFilePath -VNet $VNetName -AffinityGroup $AffinityGroupName -VNetAddressPrefix $VNetAddressPrefix -subnets $subnets
    
	Set-AzureVNetConfig -ConfigurationPath $vNetFilePath -ErrorAction SilentlyContinue -ErrorVariable errorVariable | Out-Null
    if (!($?))
    {
        throw "Cannot set the vnet configuration for the subscription, please see the file $vNetFilePath. Error detail is: $errorVariable"
    }
    Write-Verbose "Modified and saved the VNET Configuration for the subscription"
    
    # Remove-Item $vNetFilePath
}

#endregion

#region Get-AzureANLatestImage

<#
.SYNOPSIS
  Returns the latest image for a given image family.
.DESCRIPTION
  Will return the latest image based on a filter match on the ImageFamily and PublishedDate of the image.
.EXAMPLE
  The following example will return the latest SQL Server image.  It could be SQL Server 2014, 2012 or 2008
    
    Get-AzureANLatestImage -ImageFamily "*SQL Server*"
#>
function Get-AzureANLatestImage
{
    param
    (

        [Parameter(Mandatory)]
        [String]
        $ImageFamily
    )

    $LatestImage = Get-AzureVMImage |
    Where { $_.ImageFamily -eq $ImageFamily } |
    sort PublishedDate -Descending |
    Select-Object -ExpandProperty ImageName -First 1


    if ($LatestImage) {$LatestImage}
    else {
    Write-Error "Cannot find an image that belongs to the specified image family. Valid values for ImageFamily parameter are $((Get-AzureVMImage | select imagefamily -Unique).imagefamily -join ', ')"
    return
    }

}

#endregion

#region Install-AzureANWinRMCertificate

<#
.SYNOPSIS

Downloads and installs the certificate created or initially uploaded during creation of a Windows based Windows Azure Virtual Machine.

.DESCRIPTION

Downloads and installs the certificate created or initially uploaded during creation of a Windows based Windows Azure Virtual Machine.
Running this script installs the downloaded certificate into your local machine certificate store (why it requires PowerShell to run elevated). 
This allows you to connect to remote machines without disabling SSL checks and increasing your security. 


.PARAMETER ServiceName

The name of the cloud service the virtual machine is deployed in.

.PARAMETER Name

The name of the virtual machine to install the certificate for. 

.EXAMPLE

Install-AzureANWinRMCertificate -ServiceName "mycloudservice" -VMName "myvm1" 

#>
function Install-AzureANWinRMCertificate {
    param(
        [string]$ServiceName,
        [string] $VMName
    )

Function IsAdmin
{
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()` 
        ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator") 
    
    return $IsAdmin
}


	if((IsAdmin) -eq $false)
	{
		Write-Error "Must run PowerShell elevated to install WinRM certificates."
		return
	}
	

    Write-Verbose "Installing WinRM Certificate for remote access: $ServiceName $VMName"

    # Retrieve the certificate
	$WinRmCertificateThumbprint = (Get-AzureVM -ServiceName $ServiceName -Name $VMName | select -ExpandProperty vm).DefaultWinRMCertificateThumbprint
	$AzureX509cert = Get-AzureCertificate -ServiceName $ServiceName -Thumbprint $WinRmCertificateThumbprint -ThumbprintAlgorithm sha1

    $installedCert = Get-Item Cert:\LocalMachine\Root\$WinRmCertificateThumbprint -ErrorAction SilentlyContinue
    
    if ($installedCert -eq $null)
    {

        # Read in the certificate to a memory buffer to import it to a X509 certificate object.
        $certBytes = [System.Convert]::FromBase64String($AzureX509cert.Data)
        $x509Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate
        $x509Cert.Import($certBytes)
        
        Write-Verbose 'Adding the X509 certificate to the store.'
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root", "LocalMachine"
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $store.Add($x509Cert)
        $store.Close()


    }
}

#endregion

#region Add-AzureANDnsServerConfiguration

<#
.SYNOPSIS
   Modifies the virtual network configuration XML file to include a DNS service reference.
.DESCRIPTION
   This a small utility that programmatically modifies the vnet configuration file to add a DNS server
   then adds the DNS server's reference to the specified VNet site.
.EXAMPLE
    Add-AzureANDnsServerConfiguration -Name "contoso" -IpAddress "10.0.0.4" -VNetName "dcvnet"
.INPUTS
   None
.OUTPUTS
   None
#>
function Add-AzureANDnsServerConfiguration
{
    [CmdletBinding()]
   param
    (
        [String]
        $Name,

        [String]
        $IpAddress,

        [String]
        $VNetName
    )

    $vNet = Get-AzureVNetSite -VNetName $VNetName -ErrorAction SilentlyContinue
    if ($vNet -eq $null)
    {
        throw "VNetSite $VNetName does not exist. Cannot add DNS server reference."
    }

    $vNetFilePath = "{0}\{1}{2}" -f $env:temp, $AffinityGroupName, 'VNet.netcfg'
    Get-AzureVNetConfig -ExportToFile $vnetFilePath | Out-Null
    if (!(Test-Path $vNetFilePath))
    {
        throw "Cannot retrieve the VNet configuration file."
    }

    $xml = New-Object XML
    $xml.Load($vnetFilePath)

    $dns = $xml.NetworkConfiguration.VirtualNetworkConfiguration.Dns
    if ($dns -eq $null)
    {
        $dns = $xml.CreateElement("Dns", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
        $xml.NetworkConfiguration.VirtualNetworkConfiguration.AppendChild($dns) | Out-Null
    }

    # Dns node is returned as an empy element, and in Powershell 3.0 the empty elements are returned as a string with dot notation
    # use Select-Xml instead to bring it in.
    # When using the default namespace in Select-Xml cmdlet, an arbitrary namespace name is used (because there is no name
    # after xmlns:)
    $namespace = @{network="http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration"}
    $dnsNode = select-xml -xml $xml -XPath "//network:Dns" -Namespace $namespace
    $dnsElement = $null

    # In case the returning node is empty, let's create it
    if ($dnsNode -eq $null)
    {
        $dnsElement = $xml.CreateElement("Dns", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
        $xml.NetworkConfiguration.VirtualNetworkConfiguration.AppendChild($dnsElement)
    }
    else
    {
        $dnsElement = $dnsNode.Node
    }

    $dnsServersNode = select-xml -xml $xml -XPath "//network:DnsServers" -Namespace $namespace
    $dnsServersElement = $null

    if ($dnsServersNode -eq $null)
    {
        $dnsServersElement = $xml.CreateElement("DnsServers", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
        $dnsElement.AppendChild($dnsServersElement) | Out-Null
    }
    else
    {
        $dnsServersElement = $dnsServersNode.Node
    }

    $dnsServersElements = $xml.GetElementsByTagName("DnsServer")
    $dnsServerElement = $dnsServersElements | Where-Object {$_.name -eq $Name}
    if ($dnsServerElement -ne $null)
    {
        $dnsServerElement.IpAddress = $IpAddress
    }
    else
    {
        $dnsServerElement = $xml.CreateElement("DnsServer", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
        $nameAttribute = $xml.CreateAttribute("name")
        $nameAttribute.InnerText = $Name
        $dnsServerElement.Attributes.Append($nameAttribute) | Out-Null
        $ipAddressAttribute = $xml.CreateAttribute("IPAddress")
        $ipAddressAttribute.InnerText = $IpAddress
        $dnsServerElement.Attributes.Append($ipAddressAttribute) | Out-Null
        $dnsServersElement.AppendChild($dnsServerElement) | Out-Null
    }

    # Now set the DnsReference for the network site
    $xpathQuery = "//network:VirtualNetworkSite[@name = '" + $VNetName + "']"
    $foundVirtualNetworkSite = select-xml -xml $xml -XPath $xpathQuery -Namespace $namespace 

    if ($foundVirtualNetworkSite -eq $null)
    {
        throw "Cannot find the VNet $VNetName"
    }

    $dnsServersRefElementNode = $foundVirtualNetworkSite.Node.GetElementsByTagName("DnsServersRef")

    $dnsServersRefElement = $null
    if ($dnsServersRefElementNode.Count -eq 0)
    {
        $dnsServersRefElement = $xml.CreateElement("DnsServersRef", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
        $foundVirtualNetworkSite.Node.AppendChild($dnsServersRefElement) | Out-Null
    }
    else
    {
        $dnsServersRefElement = $foundVirtualNetworkSite.DnsServersRef
    }
    
    $xpathQuery = "/DnsServerRef[@name = '" + $Name + "']"
    $dnsServerRef = $dnsServersRefElement.SelectNodes($xpathQuery)
    $dnsServerRefElement = $null

    if($dnsServerRef.Count -eq 0)
    {
        $dnsServerRefElement = $xml.CreateElement("DnsServerRef", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")        
        $dnsServerRefNameAttribute = $xml.CreateAttribute("name")
        $dnsServerRefElement.Attributes.Append($dnsServerRefNameAttribute) | Out-Null
        $dnsServersRefElement.AppendChild($dnsServerRefElement) | Out-Null
    }

    if ($dnsServerRefElement -eq $null)
    {
        throw "No DnsServerRef element is found"
    }    

    $dnsServerRefElement.name = $name

    $xml.Save($vnetFilePath)
    Set-AzureVNetConfig -ConfigurationPath $vnetFilePath
}

#endregion

#Export-ModuleMember -Function New-AzureANAffinityGroup, New-AzureANVNetSite, Get-AzureANLatestImage, Install-AzureANWinRMCertificate, Add-AzureANDnsServerConfiguration