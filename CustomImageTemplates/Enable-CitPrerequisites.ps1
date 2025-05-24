<#
.SYNOPSIS
This script sets up the prerequisites to use Custom Image Templates in Azure Virtual Desktop (AVD).

.DESCRIPTION
This Azure PowerShell script sets up the prerequisites for creating custom image templates in Azure Virtual Desktop (AVD) environments. 
It creates a managed identity and assigns it the necessary roles for image creation.
It can also creates an Azure Compute Gallery (ACG) and/or an image definition if they do not already exist.

.PARAMETER imageResourceGroupName
The name of the resource group where the managed identity will be created and where the ACG and image definition will be created if they do not already exist.
This is also the resource group where the image will be created if not using the ACG.

.PARAMETER subscriptionId
The subscription ID where the resources will be managed.

.PARAMETER location
The Azure region where the resources will be deployed.

.PARAMETER vnetRgName
(Optional) The name of the resource group containing an existing virtual network. The temporary VM used to build the image can attach to an existing VNet. 
This role is required to allow the managed identity to join the VM to a VNet in this resource group.
If not provided, no networking role is created.

.PARAMETER acgGalleryName
(Optional) The name of the Azure Compute Gallery (ACG). If provided and the gallery does not exist, it will be created.
if the gallery already exists, it will be used to create a new image definition.
If not provided, a new ACG will not be created.

.PARAMETER imageDefName
(Optional) The name of the image definition. If provided and the image definition does not exist, it will be created.

.PARAMETER Publisher
(Optional) The publisher name for the image definition. Default is 'myCo'. Update this to your company name.

.PARAMETER Offer
(Optional) The offer name for the image definition. Default is 'Windows'.

.PARAMETER Sku
(Optional) The SKU name for the image definition. Default is 'Win11'.

.EXAMPLE
Log into Azure with rights to create and manage resources in the specified subscription. using the command:
PS> Connect-AzAccount
PS> Select-AzSubscription -SubscriptionId <YourSubscriptionId>
Enable prerequisites for Custom Image Templates without a VNet or ACG:
PS> .\Enable-CitPrerequisites.ps1 -imageResourceGroupName "<YourResourceGroupName>" -subscriptionId "<YourSubscriptionId>" -location "<YourLocation>"

Enable prerequisites for Custom Image Templates with a VNet and ACG, VNet and ACG are optional:
PS> .\Enable-CitPrerequisites.ps1 -imageResourceGroupName "<YourResourceGroupName>" -subscriptionId "<YourSubscriptionId>" -location "<YourLocation>" -vnetRgName "<YourVNetResourceGroupName>" -acgGalleryName "<YourACGGalleryName>" -acgImageDefName "<YourACGImageDefinitionName>"

.NOTES
Author: Travis Roberts
Date: May 10, 2025
Version: 1.0

Copyright (c) 2025 Travis Roberts

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

.LINK
Custom Image Templates Microsoft Docs: https://learn.microsoft.com/en-us/azure/virtual-desktop/create-custom-image-templates?WT.mc_id=AZ-MVP-5004159
Azure Image Builder Microsoft Docs: https://learn.microsoft.com/en-us/azure/virtual-machines/image-builder-overview?WT.mc_id=AZ-MVP-5004159
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]
    $imageResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]
    $subscriptionId,

    [Parameter(Mandatory = $true)]
    [string]
    $location,

    [Parameter()]
    [string]
    $vnetRgName = $null,

    [Parameter()]
    [string]
    $acgGalleryName = $null,

    [Parameter()]
    [string]
    $acgImageDefName = $null,

    [Parameter()]
    [string]
    $Publisher = 'myCo',

    [Parameter()]
    [string]
    $Offer = 'Windows',

    [Parameter()]
    [string]
    $Sku = 'Win11'

)
<# Define variables for parameters, this section is used for testing interactively only.
$imageResourceGroupName = "TestCITRG"
$subscriptionId = "a37dc7e3-884d-4c14-86f0-d409af2aaff8"
$location = "Central US"
$vnetRgName = "TestAVDCITVnetRG"
$acgGalleryName = "CITGallery1"
$acgImageDefName = "CITDefinition1"
$Publisher = "myCo"
$Offer = "Windows"
$Sku = "Win11"
#>

# Set the subscription context.
Set-AzContext -SubscriptionId $subscriptionId
Write-Output "The context is set to subscription: $subscriptionId"


# Check if a PowerShell modules are available and if not, install them.
$modules = @(
    "Az.Accounts",
    "Az.ImageBuilder",
    "Az.ManagedServiceIdentity"
)
foreach ($module in $modules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Output "Module $module is not installed. Installing..."
        Install-Module -Name $module -Force -Scope CurrentUser
        Write-Output "Module $module installed successfully."
        Import-Module $module
        Write-Output "Module $module imported successfully."
    }
    else {
        Write-Output "Module $module is already installed."
        Import-Module $module
        Write-Output "Module $module imported successfully."
    }
}


# Check if the resource group exists and if not,create it.
if ($null -eq (Get-AzResourceGroup -Name $imageResourceGroupName -Location $location -ErrorAction SilentlyContinue)) {
    Write-Output "Resource group $imageResourceGroupName does not exist in $location. Creating it..."
    New-AzResourceGroup -Name $imageResourceGroupName -Location $location
    Write-Output "Resource group $imageResourceGroupName created successfully."
}
else {
    Write-Output "Resource group $imageResourceGroupName exists in the location $location."
}


# Create a managed identity for CIT in the Image Resource Group
$citIdentityName = "DesktopVirtualizationCustomImageTemplateIdentity"
$citRoleDefName = "Desktop Virtualization Custom Image Template Role"
$vnetRoleDefName = "Desktop Virtualization Custom Image Templates Networking Role"

# Check if the managed identity already exists and if not, create it
$existingIdentity = Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroupName -Name $citIdentityName -ErrorAction SilentlyContinue
if ($null -eq $existingIdentity) {
    Write-Output "Creating managed identity $citIdentityName..."
    $identityNamePrincipalId = (New-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroupName -Name $citIdentityName -Location $location).PrincipalId
    Write-Output "Managed identity $citIdentityName created successfully."
    Start-Sleep -Seconds 10
}
else {
    Write-Output "Managed identity $citIdentityName already exists."
    $identityNamePrincipalId = (Get-AzUserAssignedIdentity -ResourceGroupName $imageResourceGroupName -Name $citIdentityName).PrincipalId
}


# Check the required resource providers are registered and if not, register them.
# Moved after creating the managed identity to avoid errors if the new identity is not available after creation.
$providers = @(
    "Microsoft.DesktopVirtualization",
    "Microsoft.VirtualMachineImages",
    "Microsoft.Compute",
    "Microsoft.Storage",
    "Microsoft.Network",
    "Microsoft.KeyVault",
    "Microsoft.ManagedIdentity",
    "Microsoft.ContainerInstance"
)
ForEach ($provider in $providers) {
    $providerState = Get-AzResourceProvider -ProviderNamespace $provider -ErrorAction SilentlyContinue
    if ($providerState.RegistrationState -contains "Unregistered") {
        Write-Output "Registering provider: $provider"
        Register-AzResourceProvider -ProviderNamespace $provider
    }
    else {
        Write-Output "Provider $provider is already registered."
    }
}



# Set the new role definition for the managed identity
$roleDefinition = New-Object Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition
$roleDefinition.Name = $citRoleDefName
$roleDefinition.Description = "Access to create resources for the AVD Custom Image Template image build"
$roleDefinition.Actions = @(
    "Microsoft.Compute/galleries/read",
    "Microsoft.Compute/galleries/images/read",
    "Microsoft.Compute/galleries/images/versions/read",
    "Microsoft.Compute/galleries/images/versions/write",
    "Microsoft.Compute/images/write",
    "Microsoft.Compute/images/read",
    "Microsoft.Compute/images/delete"
)
$roleDefinition.AssignableScopes = @("/subscriptions/$subscriptionId/resourceGroups/$imageResourceGroupName")


# Check if the role definition already exists and if not, create it
$existingRoleDef = Get-AzRoleDefinition -Name $citRoleDefName -ErrorAction SilentlyContinue
if ($null -eq $existingRoleDef) {
    Write-Output "Creating role definition for $citRoleDefName..."
    $roleDefinition = New-AzRoleDefinition @roleDefinition
} else {
    Write-Output "Role definition for $citRoleDefName already exists."
}


# Assign the role to the managed identity
$roleAssignment = @{
    "ObjectId"           = $identityNamePrincipalId
    "RoleDefinitionName" = $citRoleDefName
    "Scope"              = "/subscriptions/$subscriptionId/resourceGroups/$imageResourceGroupName"
}
# Test if the role assignment already exists and if not, create it
$existingRoleAssignment = Get-AzRoleAssignment -ObjectId $identityNamePrincipalId -RoleDefinitionName $citRoleDefName -Scope "/subscriptions/$subscriptionId/resourceGroups/$imageResourceGroupName" -ErrorAction SilentlyContinue
if ($null -eq $existingRoleAssignment) {
    Write-Output "Creating role assignment for $citRoleDefName..."
    New-AzRoleAssignment @roleAssignment
} else {
    Write-Output "Role assignment for $citRoleDefName already exists."
}


# Create a custom role for custom Image template Networking role if a VNet resource group name is provided
if ($vnetRgName) {
    # Create the role definition for the managed identity
    $vnetRoleDefinition = New-Object Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition
    $vnetRoleDefinition.Name = $vnetRoleDefName
    $vnetRoleDefinition.Description = "Access to read and join network resources for the AVD Cutom Image Template image build"
    $vnetRoleDefinition.Actions = @(
        "Microsoft.Network/virtualNetworks/read",
        "Microsoft.Network/virtualNetworks/subnets/join/action"
    )
    $vnetRoleDefinition.AssignableScopes = @("/subscriptions/$subscriptionId/resourceGroups/$vnetRgName")

    # Check of the role definition already exists and if not, create it
    $existingVnetRoleDef = Get-AzRoleDefinition -Name $vnetRoleDefName -ErrorAction SilentlyContinue
    if ($null -eq $existingVnetRoleDef) {
        Write-Output "Creating role definition for $vnetRoleDefName..."
        $vnetRoleDefinition = New-AzRoleDefinition @vnetRoleDefinition
    } else {
        Write-Output "Role definition for $vnetRoleDefName already exists."
    }
   
    # Assign the role to the managed identity
    $vnetRoleAssignment = @{
        "ObjectId"           = $identityNamePrincipalId
        "RoleDefinitionName" = $vnetRoleDefName
        "Scope"              = "/subscriptions/$subscriptionId/resourceGroups/$vnetRgName"

    }

    # Test if the role assignment already exists and if not, create it
    $existingVnetRoleAssignment = Get-AzRoleAssignment -ObjectId $identityNamePrincipalId -RoleDefinitionName $vnetRoleDefName -Scope "/subscriptions/$subscriptionId/resourceGroups/$vnetRgName" -ErrorAction SilentlyContinue
    if ($null -eq $existingVnetRoleAssignment) {
        Write-Output "Creating role assignment for $vnetRoleDefName..."
        New-AzRoleAssignment @vnetRoleAssignment
    } else {
        Write-Output "Role assignment for $vnetRoleDefName already exists."
    } 
}

# Check if the ACG Gallery exists and create it if not
if ($acgGalleryName) {
    $acgGallery = Get-AzResource -ResourceGroupName $imageResourceGroupName -Name $acgGalleryName -ResourceType "Microsoft.Compute/galleries" -ErrorAction SilentlyContinue
    if ($null -eq $acgGallery) {
        Write-Output "ACG Gallery $acgGalleryName does not exist. Creating it..."
        New-AzGallery -ResourceGroupName $imageResourceGroupName -Name $acgGalleryName -Location $location -Description "ACG Gallery for Custom Image Template"
        Write-Output "ACG Gallery $acgGalleryName created successfully."
    }
    else {
        Write-Output "ACG Gallery $acgGalleryName exists in the locaiton $location."
    }
}else {
    Write-Output "ACG name not provided. Skipping ACG creation."
}

# Check if the ACG Image Definition exists and create it if not
if ($acgImageDefName -AND $acgGalleryName) {
    $acgImageDef = Get-AzResource -ResourceGroupName $imageResourceGroupName -Name $acgImageDefName -ResourceType "Microsoft.Compute/galleries/images" -ErrorAction SilentlyContinue
    if ($null -eq $acgImageDef) {
        Write-Output "ACG Image Definition $acgImageDefName does not exist. Creating it..."
        $GalleryParams = @{
            GalleryName       = $acgGalleryName
            ResourceGroupName = $imageResourceGroupName
            Location          = $location
            Name              = $acgImageDefName
            OsState           = 'generalized'
            OsType            = 'Windows'
            Publisher         = $Publisher
            Offer             = $Offer
            Sku               = $Sku
        }
        New-AzGalleryImageDefinition @GalleryParams
        Write-Output "ACG Image Definition $acgImageDefName created successfully."
    }
    else {
        Write-Output "ACG Image Definition $acgImageDefName exists in the locaiton $location."
    }
}else {
    Write-Output "ACG Image Definition name not provided. Skipping image definition creation."
}

# Output details needed to create the custom image template
Write-Output ""
Write-Output "######Custom Image Template Prerequisites Created######"
Write-Output "Please wait ~10 minutes for the managed identity and the role assignments to apply."
Write-Output "The resource group name is: $imageResourceGroupName"
Write-Output "The location of the managed identity is: $location"
Write-Output "The Managed Identity Name is: $citIdentityName"
if ($acgGalleryName) {
    Write-Output "The Azure Compute Gallery name is: $acgGalleryName"
    Write-Output "The Image Definition name is: $acgImageDefName"
}
If ($vnetRgName) {
    Write-Output "The VNet Resource Group name is: $vnetRgName"
    Write-Output "VNets in this resource group include:"
    Get-AzVirtualNetwork -ResourceGroupName $vnetRgName | Select-Object Name, Location
}
