# AVDTools
*Repository for updated AVD management tools*

**Enable-CitPrerequisites.ps1** - This file is used to enable the prerequisites for Custom Image Templates (CIT).  The code was pieced together from the commands in the Azure Virtual Desktop CIT and AIB Microsoft documentation. Refer to the scripts help section for information on using the script. Elevated rights are required to run this script.  When ran, the script will:
1. Create the resource group.
2. Create the Managed Identity.
3. Check the required providers on the subscription and register them if needed.
4. Create and assign the role definition with rights to manage images on the resource group.
5. If provided, create and assign the role definition to use a private network.
6. Create the Azure Compute Gallery (ACG).
7. Create the ACG image definition.
8. Output details used to crate a CIT
The script checks for the presence of a resource before it creates it.  The script can be ran multiple times if needed.

**Install-CitApplications.ps1** - This script is used as an example of how to deploy different software applications as part of a Custom Image Template installation. The script uses a compressed file called software.zip to install an .msi and .exe file.  It also uses Chocolatey to install an application from a public repository.  When ran, the script will:
1. Create a logging function.
2. Download and extract AZCopy.
3. Use AZCopy to download the software.zip file from a blob storage container using a SAS URL.
4. Extract the install source files and install the .msi and .exe package.
5. Check for and remove the per-user NotepadPlusPlus AppPackage that prevents Sysprep.exe from running.
6. Use Chocolatey to install and application.


