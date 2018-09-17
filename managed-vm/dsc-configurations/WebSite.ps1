Configuration IgniteDemo
{
   param 
    (  
        # Name of the VM for the hybrid worker group 
        [Parameter(Mandatory)] 
        [ValidateNotNullOrEmpty()] 
        [String]$VMName,

        # Name of the website to create 
        [Parameter(Mandatory)] 
        [ValidateNotNullOrEmpty()] 
        [String]$WebSiteName, 
       
        # Source Path for Website content 
        [Parameter(Mandatory)] 
        [ValidateNotNullOrEmpty()] 
        [String]$SourcePath, 
        
        # Destination path for Website content 
        [Parameter(Mandatory)] 
        [ValidateNotNullOrEmpty()] 
        [String]$DestinationPath   
         
    ) 
    # Import the module that defines custom resources 
    Import-DscResource -Module cAzureStorage 
    Import-DscResource -ModuleName xWebAdministration 
    Import-DscResource -ModuleName xPSDesiredStateConfiguration
    Import-DscResource -Module xNetworking
    Import-DscResource -ModuleName HybridRunbookWorkerDsc -ModuleVersion 1.0.0.2

    $AutomationEndpoint = Get-AutomationVariable AutomationEndpoint
    $AutomationKey = Get-AutomationPSCredential AutomationCredential
    $StorageKey = Get-AutomationVariable -Name StorageKey
    $StorageAccount = Get-AutomationVariable -Name StorageAccountName
    $StorageContainer = Get-AutomationVariable -Name StorageContainer

    Node $VMName
    { 
        # Wait 20 minutes for hybrid worker bits to be downloaded, else fail.
        WaitForHybridRegistrationModule ModuleWait
        {
            IsSingleInstance = 'Yes'
            RetryIntervalSec = 60
            RetryCount = 20
        }

        HybridRunbookWorker Onboard
        {
            Ensure    = 'Present'
            Endpoint  = $AutomationEndpoint
            Token     = $AutomationKey
            GroupName = $VMName
            DependsOn = '[WaitForHybridRegistrationModule]ModuleWait'
        }
        # Install the IIS role 
        WindowsFeature IIS 
        { 
            Ensure          = "Present" 
            Name            = "Web-Server" 
        } 
        # Install the ASP .NET 4.5 role 
        WindowsFeature AspNet45 
        { 
            Ensure          = "Present" 
            Name            = "Web-Asp-Net45" 
        } 
        # Stop the default website 
        xWebsite DefaultSite  
        { 
            Ensure          = "Present" 
            Name            = "Default Web Site" 
            State           = "Stopped" 
            PhysicalPath    = "C:\inetpub\wwwroot" 
            DependsOn       = "[WindowsFeature]IIS" 
        } 

        # Copy Demo site content from Azure Storage
        cAzureStorage DemoContent 
        {
            Path                    =  $SourcePath
            StorageAccountName      =  $StorageAccount
            StorageAccountContainer =  $StorageContainer
            StorageAccountKey       =  $StorageKey
        }

        # Copy the website content 
        File WebContent 
        { 
            Ensure          = "Present" 
            SourcePath      = $SourcePath 
            DestinationPath = $DestinationPath 
            Recurse         = $true 
            Type            = "Directory"
            Checksum        = "SHA-256"
            DependsOn       = "[WindowsFeature]AspNet45"
        }        
        # Create the new Website
        xWebsite NewWebsite 
        { 
            Ensure          = "Present" 
            Name            = $WebSiteName 
            State           = "Started" 
            PhysicalPath    = $DestinationPath 
            BindingInfo     = 
                MSFT_xWebBindingInformation
                {
                    Protocol              = "HTTP"
                    Port                  = 81
                }
            DependsOn       = "[File]WebContent"
        } 

        # Set firewall rule for port 81 traffic
        xFirewall Firewall-81 
        {
 	        Name                      = "Allow Port 81"
 	        Action                    = "Allow"
 	        Direction                 = "Inbound"
 	        DisplayName               = "Port 81"
 	        Enabled                   = "True"
 	        Ensure                    = "Present"
 	        LocalPort                 = "81"
 	        Protocol                  = "TCP"
 	        RemotePort                = "Any"
            DependsOn       = "[xWebsite]NewWebsite"
        }
    } 
}