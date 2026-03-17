**A retail solution powered by Data 360 - DIY Store Front**</br>
====================

Welcome to the DIY Storefront, a sample retail application. DIY Storefront is a fictional retail store that uses Data 360, Agentforce, and the Salesforce Platform to deliver highly personalized customer experiences.

The DIY Storefront app showcases Data 360, Agents, and Prompts by using both structured and unstructured data, including Intelligent Context, to process complex information.

There are 3 required steps, these steps allow you to setup Data 360, import data (both structured and unstructured), and setup the employee agent within your Salesforce instance. After completing the first three steps, if you want to install the agent in your own website use Step 4, and if you want to install the agent on an Experience Cloud site follow step 5. Steps 4 & 5 are optional. 
<details><summary>

  ## 1. Pre-Deployment Instructions
</summary>


### Step 1. Salesforce Org Setup Requirements for the DIY Store Front App (5 min)

   To support the DIY app, you can either create a new Salesforce Org or use an existing one, provided it includes the following features and licenses: 

  | Requirement | Details |
  | ----- | ----- |
  | Licenses Required | - Data Cloud</br>- Sales Cloud</br>- Service Cloud|
  | Features Required | - Service Agent</br>- Einstein Agent</br>- Copilot</br>- Prompt Builder</br>- Agentforce Data Library</br> - Agentforce Studio</br> - Process Content - Intelligent Context|


> [!IMPORTANT]
> It is recommended to start with a brand-new environment to avoid conflicts with any previous work you may have done. A developer org can also be used.

### Step 2. Salesforce CLI
- Install VSCode [Download](https://code.visualstudio.com/download)
- [Install the Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) or Verify that your installed CLI version is greater than `2.56.7` by running `sf -v` in a terminal.
- Open VS Code > Go To> Extensions->Search for Salesforce Extension Pack>Click Install
- Install Git(Ignore if already installed) [Git](https://git-scm.com/install/)
- Open VS Code > Go To Extensions->Search for Git Extension Pack>Click Install
### Step 3. Enable Data Cloud.

| Step | Action and Details | Images |
| ----- | ----- | ----- |
| Verify and Enable Data Cloud for Your Org |- Make sure that Data Cloud provisioning is complete before proceeding.</br>- To verify this, go to Data Cloud Setup. The page should appear as shown if provisioning is complete.</br>- If you see a Get Started button, click it and wait for the process to finish.</br>- This process can take up to ten minutes.|<img width="450" alt="DatacloudSetup" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Pre-Deployment/DataCloudSetupHome.png">|

### Step 4. Enable Features In Your Environment (20 minutes)

| Step | Action and Details | Images |
| ----- | ----- | ----- |
| Enable Promotion Attribute |- Go to Setup</br>- Search Global Promotions Management Setting</br>- Enable the "Global Promotions Management Setting"</br>- Enable the "Product Catalog Management"|<img width="450" alt="Promotion" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Pre-Deployment/Global%20Promotion%20Mgt.png">|
| Turn on Einstein |- Go to Setup.</br>- In the Quick Find box, search for Einstein Setup.</br>- Click **Turn On Einstein**.|<img width="450" alt="Einstein" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Pre-Deployment/Turn%20on%20Einstein.png?raw=true">|
| Turn on Agentforce |**Note:** You may need to refresh the page to see the Agentforce Agents menu after turning on Einstein.<br><br>- Go to Setup.</br>- In the Quick Find box, type **Agentforce Agents**.</br>-Toggle on **Agentforce**.|<img width="450" alt="Agent1" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Pre-Deployment/AgentforceAgents02.png">|
| Modify the Data Cloud Architect Permission Set | - Go to Setup.</br>- In the Quick Find box, search for and select **Permission Sets**.</br>- Open the **Data Cloud Architect** permission set.</br>- Click **Data Cloud Data Space Management** under Apps.</br>- Click Edit, **Enable the default data space**, and click Save.</br>- Confirm by clicking OK.|<img width="450" alt="DSSpace2" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/DC%20Architect%20Data%20Space%20Enable.png">|
| Enable Person Account |- Go to Setup</br>- Enter Person Accounts in the Quick Find box and select **Person Accounts**.</br>- Review the information and steps provided on the Setup page to understand the configuration.</br>- Turn on the Person Accounts Toggle."|<img width="450" alt="PS" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Pre-Deployment/PersonAccounts.png">|


### Step 5. Base metadata deployment



1. Clone this repository:

    ```bash
    git clone https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit.git
    ```

1. Authorize your org with the Salesforce CLI.

- Ctrl+Shift+P Select SFDX:Authorize an Org -> Select Project Default -> Enter the Org alias -> Authorize the Org.

1. Deploy the base app metadata.

    ```bash
    sf project deploy start -d diy-base
    ```
 
1. Assign Base Permission Set to Default User.

   ```bash
   sf org assign permset -n DIYRetailBasePS
    ```

1. Activate Standard PriceBook.

    ```bash
    sf apex run -f scripts/apex/activatePricebook.apex
    ```

1. Replace the Standard Price Book variable in the JSON file with the actual Standard PricebookId by following the steps below in order.
   ***Choose PowerShell in VS code Terminal**


    ```bash
    $pbQuery = sf data query -q "SELECT Id FROM Pricebook2 WHERE IsStandard = true AND IsActive = true LIMIT 1" --json | ConvertFrom-Json
    ```
    ```bash
    $STD_PB_ID = $pbQuery.result.records[0].Id
    ```
    ```bash
    Write-Output "Standard Price Book Id: $STD_PB_ID"
    ```
    ```bash
    (Get-Content data\pricebookentries.json) -replace "STANDARD_PRICEBOOK_ID", $STD_PB_ID | Set-Content data\pricebookentries.json
    ```

1. Import Sample data.

    ```bash
    sf data tree import -p data/plan.json
   ```

1. Adjust Order Effective Date.

    ```bash
    sf apex run -f scripts/apex/updateEffectiveDatesonOrder.apex
    ```

1. Activate Orders Data Using Anonymous Apex.

    ```bash
    sf apex run -f scripts/apex/activateOrderStatus.apex
    ```



</details>

<details><summary>

  ## 2. Data Cloud and Intelligent Context Configuration
</summary>

### Step 1. Install Datakit and Deploy In Your Environment.

| Step | Action and Details | Image |
|------|-------------|-------|
| Install Data Kit | - **Install Data Kit**:<br>`sf project deploy start -d diy-datacloud`<br><br>- **Open your org** (if not already open):<br>`sf org open` | ![](images/datakit.png) |
| Deploy Datakit Into Your Org | - Go to **Setup** </br>- Enter **Data Kits** in the **Quick Find** box. </br>- Select **Data360RetailDIYDataKit** <br>- Click **Datakit Deploy** <br>**Note**: The deployment process may take approximately 25 minutes to complete. You can monitor the progress in the Deployment History section.|<img width="450" alt="InstallDatakit1" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/InstallDatakit1.png">|

### Step 2. Extract Source files.

| Step | Action and Details | Image |
|------|--------------------|-------|
| Navigate to Documents folder in GitHub Repository | - Open a web browser and go to [GitHub](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/tree/master/DIY%20Documents/DIY%20Documents).<br>- Once inside the repository, you will see the **DIY Documents** at the root level.<br>- Click on a **folder name** to open it and view its contents.<br>- Click on **Customer Affinities** to open the file<br>- Click on **Download** to save in your system<br>**Note**: Follow the above procedure to download the following documents: **POS**, **Website**, **Customer Engagements**, **Bathroom_Remodelling_Instructions**, **Building Deck**, and **DIY Seasonal**.Ensure that all files are securely saved to your local system, as they will be required for subsequent processing and configuration steps.| |

### Step 3. Upload Files for Datastreams.

| Step | Action and Details | Image |
|------|--------------------|-------|
| Update File in Data Cloud |- Navigate to **Data Cloud** from the **App Launcher** → Go to **Data Streams** (sometimes under **Data → Data Streams**) → Click on **Customer Affinities** where the **Connection Type** is set to **File Upload**.<br>- Click **Update File** in the Data Stream interface to open the file selection dialog.<br>- Upload the new file:<br>- Browse and select the **Customer Affinities** filethat was downloaded in the previous step.<br>- Ensure the file matches the expected format (CSV, JSON, etc.).<br>- Click **Deploy**.<br>- Verify the file in the Data Stream:<br>- Optionally, check **Processing History** or **Deployment History** to ensure the file was ingested successfully without errors.<br> **Note:** Follow the above steps for **Website Customers**, **POS Customers**, and **Customer Engagement** using files that you have downloaded from the previous step.|<img width="450" alt="UploadDataStream1" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/FLUP1.png"> <img width="450" alt="UploadDataStream1" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/FLUP2.png"> <img width="450" alt="UploadDataStream1" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/FLUP3.png">|
| Data Cloud Copy Field Enrichment Sync | - Go to Object Manager.</br>- Search for and select Contact.</br>- Click on Data Cloud Copy Field.</br>- Select Average Order Value Lifetime default and click Start Sync.</br>- In the dialog box, click Start Sync.</br>- This process can take up to 15 minutes to complete.</br>- Click Sync History to ensure the status is Complete.</br>**Note:** Follow the above steps to process the following **Data Cloud Copy Fields**: **Average Purchase Value (default), Customer Lifespan (default), Customer Lifetime Value (default)**, and **Unified Contact Profile Information**. Ensure that the sync status for each field is verified and confirmed.|<img width="450" alt="DataCopyField3" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/DataCopyField3.png"><img width="450" alt="DataCopyField2" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/DataCopyField2.png"><img width="450" alt="DataCopyField3" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/DataCopyField3.png"> |
| Data Cloud Related List to the Contact | - Go to Object Manager.</br>- Search for and select Contact.</br>- Go to the Data Cloud Related List tab.</br>- Click New.</br>- Under Data Cloud Object, select **Customer Affinities** and click Next.</br>- Keep the default values and click Next.</br>- Change the related list label to **Customer Affinities**.</br>- Check the Contact Layout checkbox.</br>- Check the Add related list to users’ existing record page customizations checkbox.</br>- Click Next.</br> |<img width="450" alt="DataCopyField3" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/CustomerEffinitiesRL.png">|

### Step 4. Agentforce Data Library Setup

| Step | Action and Details | Image |
|------|--------------------|-------|
| Agentforce Data Library Setup and Files Upload | - Go to **Setup** → Enter **Agentforce** in the **Quick Find** box >> Click **Agentforce Data Library** → Click **New Library** → Enter the name **“Diy Building A Deck”** → Click **Save**.<br><br>-Under the "Diy Building A Deck" library, select **Data Type** as **Files** → Click **Upload Files** → Choose **“Building_a_Deck_Instructions.pdf”** file that was downloaded in the previous step → Once file upload is complete, click **Done**. <br><br>-You can wait until the **Status** updates to **Ready** .This  process may take approximately 20 minutes. <br/>Follow the steps described above to create the additional libraries: <br/>i.  Create a library named **Diy Seasonal**, set the Data Type to **Files** and upload the **DIY Seasonal Product.pdf** file that was downloaded in the previous step.<br/>ii. Create a library named **DIY Bathroom Library**,set the Data Type to **Files** and upload the **Bathroom_Remodelling_Instructions.pdf** file that was downloaded in the previous step. |<img width="400" alt="ADLSetup" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/ADLSetup.png?raw=true"><img width="400" alt="BuilddeckAdl" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/BuilddeckAdl.png?raw=true"> <img width="400" alt="diyBathroomADL" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/diyBathroomADL.png?raw=true"> <img width="400" alt="diySeasonalADL" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/diySeasonalADL.png?raw=true"> |

### Step 5. Intelligent Context Setup Guide – Data Cloud


| Step | Action and Details | Image |
|------|-------------|-------|
| Intelligent Context Setup – Data Cloud | - Go to **App Launcher** → Enter **Data Cloud** and open the **Data Cloud** app → Click **Process Content**.<br><br>-Click **Intelligent Context** → Click **New Configuration** → Enter the name **“DIY Bathroom”** and click **Save**.<br><br>-Click **Upload File**, select **“Bathroom_Remodelling_Instructions.pdf”** file that was downloaded in the previous step., then click **Done**. Wait a minute for the file to be ready for preview.<br><br>- Click **Set up my configuration using smart defaults** and wait for the chunks to be generated.<br><br>- Click **Modify** to navigate to **Edit Configuration** and configure: <br>i. **Pre-processing**: No preprocessing; **Image Processing**: Toggle Off <br>ii. **Parsing**: Select **LLM-based Parsing**, then click **Save** and wait for chunk generation → Once chunk generation is successful then click **Publish**.<br><br>- Select **UDMO** that was created by the ADL **when you uploaded the file for Diy Bathroom such ADL_DIY_Bathroom_Li”**, click **Next**, then click **Publish**.<br><br>- A new search index will be created with the name as **DIY_Bathroom** . This process may take a few minutes to reach the **Ready** status.<br><br>- Create another **Intelligent Context** for Building a Deck by applying the same steps used for DIY Bathroom, with the following adjustments: <br/>-Name the intelligent context as **“Building a Deck”** <br/>-Upload the file **“Building_a_Deck_Instructions.pdf”** file that was downloaded in the previous step <br/>-Click **“Set up my configuration using smart defaults”** and set the configuration as described in the DIY Bathroom steps, then click Publish<br/>- When publishing,select the **UDMO** that was created by the ADL **when you uploaded the file for Building a Deck such as ADL_Diy_Building_A**<br/>-A new search index will be created with the name as **Building a Deck**.  This process may take a few minutes to reach the **Ready** status.|<img width="300" alt="ICSetup" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/ICSetup.png"> <img width="300" alt="ICSetup3" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/ICSetup3.png"> <img width="300" alt="ICSetup" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/ICSetup4.png"> <img width="300" alt="ICSetup" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/ICSetup5.png"> <img width="300" alt="ICSetup" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/ICSetup6.png"> <img width="300" alt="ICSetup" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/ICSetup7.png"> <img width="300" alt="ICSetup" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/ICBuildDeck1.png"> <img width="300" alt="ICSetup" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/ICBuildDeck3.png"> <img width="300" alt="ICSetup" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/ICBuildDeck4.png"> |

### Step 6. Individual Retriever Setup – Data Cloud

| Step | Action and Details | Image |
|------|--------------------|-------|
| Individual Retriever Setup – DIY Bathroom & Building a Deck | - Go to **App Launcher** >> Enter **Data Cloud** and open the **Data Cloud App** >> Click **Einstein Studio** >> Click **Retrievers** >> Click **Individual Retriever** >> Click **Next**.<br><br>-Select **Data Cloud** >> Select **Data Space** as **Default** >> Choose data model object that was created by the ADL when you uploaded the file for Bathroom such as **ADL_DIY_Bathroom_Li** >> Select Data model object's search index configuration as **DIY_Bathroom** >> Click **Next**.<br><br>- Select **All Documents** >> Click **Next**.<br><br>-Click **Field Name** >> Select **Related Attribute** >> Select **DIY_Bathroom chunk** >> Select **Chunk** <br/>- Click **Add Field** >> Add the following fields:<br>i. **Chunk Sequence Number**<br>ii. **Data Source**<br>iii. **Data Source Object**<br>iv. **Internal Organization**<br>v. **Record Id**<br>vi. **Source Record Id**.<br><br>-Click **Next** >> Click **Save**>> Click **Activate** button.<br><br>**Note:**  To create another Retriever, follow the procedure described above, making adjustments for the new dataset as needed:<br/>-Click on **Data Cloud**<br/>-Choose Default as the **Data Space**<br/>Choose the data model object that was created by the ADL when you uploaded the file for Building a Deck such as **ADL_Diy_Building_A**<br/>-Choose **Building_a_Deck** value as Data model object's search index configuration<br/>-Same as before, select All Documents and click Next <br/>-Configure fields by clicking Field Name, selecting Related Attribute, choosing **Building_a_Deck Chunk** ,and selecting **Chunk** and the additional fields remain exactly the same as those used in the Diy Bathroom Retriever.<br/>-Refer Screenshot. |<img width="300" alt ="RetrivalBathroom" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/RetriverBathroom2.png"> <img width="300" alt="RetriverBathroom1" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/RetriverBathroom3.png"> <img width="300" alt="RetriverBathroom1" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/RetriverBathroom4.png"> <img width="300" alt="RetriverBathroom1" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/RetriverBathroom5.png"> <img width="300" alt="RetriverBathroom1" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/RetriverBathroom6.png"> <img width="300" alt="RetriverBuilding1" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/RetriverBuildDeck1.png"> <img width="300" alt="RetriverBuilding1" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/RetriverBuildDeck3.png"> <img width="300" alt="RetriverBuilding1" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/ADL_IC_Retriever_Images/RetriverBuildDeck4.png"> |


### Step 8. Refresh Data Cloud Components


| Step | Action and Details | Images |
| ----- | ----- | ----- |
| Refresh Data Stream | - Go to App Launcher</br>- Click on the Data Cloud App</br>- Navigate to the Data Streams tab</br>- For each data stream listed, click the downward arrow on the right-hand side of the data stream name and select Refresh Now</br>- Wait until the status shows Success and verify the Last Processed Records</br>- Follow above steps one by one for all Data Streams: **Account_Home**, **Contact_Home**, **Product2_Home**, **Pricebook2_Home**, **PricebookEntry_Home**, **Asset_Home**, **AssetWarranty_Home**, **Order_Home**, **OrderItem_Home**, **Promotion_Home**, **PromotionProduct_Home**, **ServiceAppointment_Home**|![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/RefreshDataStream.png?raw=true)|
| Run Identity Resolution Ruleset | - Go to the **Identity Resolution** tab</br>- Choose and select **Unified Customer**</br>- Click **Run Ruleset** | ![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/RUNIR.png)|
| Run Calculated Insights | - Go to the **Calculated Insights** tab</br>- Choose and select **Average Order Value Lifetime**<br>- Click **Publish Now** <br>- Follow the above steps to the following calculated insights, publishing them in the same order:<br/>- **Average Purchase Value**,**Average Purchase Frequency**,**Customer Lifespan**,**Customer Lifetime**| ![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/RUNCI.png) |
| Publish Segment |- Go to the Segment tab.</br>- Choose and select Power Buyer Program Members. </br>- Click Run Publish Now|![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/PublishSegment.png)| 

⚠️ **Important Note:** If you still cannot see the values under Account 360 Record page then follow the above refresh steps again in the same series. 
</details>


<details><summary>

  ## 3. Agentforce Agents Installation
</summary>

### Step 1. Install Agents and Activate

| Step | Action and Details | Image |
|------|-------------|-------|
| Agent Setup and Configuration | - **Install Agents**:<br>`sf project deploy start -d diy-pd-pack`<br><br>- **Assign Permission Set to the Default User**:<br>`sf org assign permset -n RetailDIYStorePS`.<br></br>- **Activate Agent**: <br>`sf agent activate --api-name DIY_Employee_Agent`<br><br>- **Create Agent User**:<br>`sf apex run -f scripts/apex/createAgentUser.apex`<br></br>- **Open your org**(if not already open):</br>`sf org open`.
| Assign User to Service Agent |- Click on setup, Search for and Select Agentforce Agents.<br/>- Click on ‘DIY Assitant’->Click on Open Builder <br/>- Click on setting->Click on company field and just give one space and remove space.<br/>- Select Agent User to Service Agent User -> click on Activate|<img width="300" alt="servicragent" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/AgentforceImages/activateServiceAgent.png?raw=true">|
| Add Seasonal Product Retriever | - Go to **Setup** → enter **Prompt Builder** → open **seasonalPlantRecomendation** prompt template</br>- Replace **DIY_SEASONAL_RETRIEVER** with retriever following steps:</br>i. Click **Insert Resource** → **Retrievers** → **Configure Retrievers**</br>ii. Again Click on Retrivers ->Select the retriever created by the ADL when you **uploaded the file for seasonal products(Eg:File_ADL_Diy_Seasonal)** </br>iii. Under **Search Text**, choose **Free Text** → **Question**</br>iv. For **Output Fields**, select **Chunk** → **Apply and Insert**</br>v. Click **Save As** → **Save as New Version** → **Activate** | <img width="300" alt="RS" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/seasonRetriverPrompt1.png?raw=true">  <img width="300" alt="RS" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/seasonRetriverPrompt6.png?raw=true"> <img width="300" alt="RS" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/seasonRetriverPrompt7.png?raw=true"> |
| Add Building A Deck Retriever | - Go to **Setup** → enter **Prompt Builder** → open **Building Deck Prompt** prompt template</br>- Replace **DIY_BUILDING_RETRIEVER** with retriever following steps:</br>i. Click **Insert Resource** → **Retrievers** → **Configure Retrievers**</br>ii.Again Click on Retrievers ->Choose the Retriever **created earlier for Building a Deck during the Individual Retriever Setup(Eg:Building_a_Deck Retriver)** </br>iii. Under **Search Text**, choose **Free Text** → **Question**</br>iv. For **Output Fields**, select **Chunk** → **Apply and Insert**</br>v. Click **Save As** → **Save as New Version** → **Activate** | <img width="300" alt="BD" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/BuildingdeckRetriverPrompt1.png"> <img width="300" alt="BD" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/BuildingdeckRetriverPrompt2.png"> <img width="300" alt="BD" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/BuildingdeckRetriverPrompt3.png">|
| Add DIY Bathroom Retriever to Storage Cabinet Prompt | - Go to **Setup** → enter **Prompt Builder** → open **storageCabinetDetails** prompt</br>- Replace **DIY_BATHROOM_RETRIEVER** with retriever following steps:</br>i. Click **Insert Resource** → **Retrievers** → **Configure Retrievers**</br>ii. Again Click on Retrievers ->Choose the Retriever **created earlier for DIY Bathroom Retriever during the Individual Retriever Setup (eg:DIY_Bathroom Retriever)** </br>iii. Under **Search Text**, choose **Free Text** → **Question**</br>iv. For **Output Fields**, select **Chunk** → **Apply and Insert**</br>v. Click **Save As** → **Save as New Version** → **Activate** |<img width="300" alt="BD" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/storageRetriverPrompt1.png"> <img width="300" alt="BD" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/storageRetriverPrompt2.png"> <img width="300" alt="BD" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/storageRetriverPrompt3.png"> |
| Add DIY Bathroom Retriever to Bathroom Remodeling Prompt | - Go to **Setup** → enter **Prompt Builder** → open **Bathroom Remodeling Prompt**</br>- Replace **DIYDIY_BATHROOM_RETRIEVER** with retriever following steps:</br>i. Click **Insert Resource** → **Retrievers** → **Configure Retrievers**</br>ii.Again Click on Retrievers -Choose the Retriever **created earlier for DIY Bathroom Retriever during the Individual Retriever Setup (eg:DIY_Bathroom Retriever)** </br>iii. Under **Search Text**, choose **Free Text** → **Question and Category**</br>iv. For **Output Fields**, select **Chunk** → **Apply and Insert**</br>v. Copy retriever and replace all other **DIYDIY_BATHROOM_RETRIEVER** instances</br>vi. Click **Save As** → **Save as New Version** → **Activate** | <img width="300" alt="BD" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/BathroomRetriverPrompt1.png"> <img width="300" alt="BD" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/BathroomRetriverPrompt2.png"> <img width="300" alt="BD" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/BathroomRetriverPrompt3.png"> <img width="300" alt="BD" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/BathroomRetriverPrompt4.png"> |
| Assigning Permission to App | - Go to **Setup** -> Enter **App Manager**<br>- Click on **DIY Store Front App**<br>- Click on **Edit** from arrow -> Click **User Profiles**<br>- Search **System Administrator** from Available Profiles and select it and click on right arrow -> so it will be present under **Selected Profiles** <br>- Click on Save|<img width="300" alt="appProfile" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/diyStoreFrontApp.png?raw=true">|
| Activate Account Record Page | - Go to **Setup** -> In Quick Find, type **Lightning App Builder** click on it.<br>- Click on **Retail Account Record Page** from the list.<br>- Click on **Edit** -> In the top-right corner, click **Activate** -> Click on **Assign as Org Default** in the popup <br>- Click **Save**|<img width="300" alt="appProfile" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/retailAccountPage.png?raw=true"><img width="300" alt="appProfile" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/retailAccountPage1.png?raw=true"><img width="300" alt="appProfile" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Data%20Cloud%20Images/retailAccountPage2.png?raw=true">|
| Testing Guideline | -To continue with testing, click on the App Launcher, select the DIY Store Front App, open the Account tab, search for the Mark Smith record, and verify that isDIYRecord is set to true under the Details tab. | <img width="300" alt="RecordPageImage" src="https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/AgentforceImages/Account%20Record%20Page.png?raw=true"> |
  
</details>

<details><summary>

 ## 4. (Optional) Deploy Service Agent on an External Website
</summary>

### Step 1. Embedded Service Messaging Setup and Configuration

| Step | Action and Details | Image |
|------|-------------|-------|
| Enable Messaging Channel | - Navigate to Setup go to messaging setting. </br>- Toggle on the messaging.|![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/MessagingSettings.png)|
| Configure Site Setting |- In Setup, search for Sites and click Register My Salesforce Site Domain.</br>- After registration, open the Embedded Service Deployment and locate the Site Endpoint that starts with **ESW** (ESA Web Deployment).</br>- Click the endpoint link to open the site settings.</br>- Under Trusted Domains for Inline Frames, click Add Domain.</br>- Enter the same external website URL used earlier.</br>- Click Save.|![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/RegisterDomain.png)|
| Embedded Service Messaging Setup |- **Install Embedded Service Package**:</br>`sf project deploy start -d diy-embeddedservice`.<br><br>- **Activate Messaging Channel**:</br>`sf apex run -f scripts/apex/activateMessagingChannel.apex`
| Publish ESA | - Click on Setup </br>- In Quick Find, Search and Select Embedded Service Deployments.</br>- Click on ESA Web Deployment </br>- Click on 'Publish' button </br>- Wait for confirmation Message |![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/PublishESA.png)|
| Create a New Version of Omni-Channel Flow  |- Click on Setup</br>- Search for Flows in the Quick Find box and select it.</br>- Open the flow **Route Conversations to Agentforce Service Agents**.</br>- Deactivate the flow and open the**Route to Service Agent** element.</br>- Refresh the Service Channel by selecting a different option and then reselect Live Messaging.</br>- Set **Route To as** Agentforce Service Agent and choose **DIY Assistant**.</br>- In Fallback Queue ID, remove the existing queue and reselect the same queue.</br>- Click Save As New Version, then click Activate.  |![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/RouteToAgentforceServiceAgent.png)|

### Step 2. CORS Configuration

| Step | Action and Details | Image |
|------|-------------|-------|
| Configure CORS Settings | - From Setup, search for CORS and , click New.</br>- Enter the external website URL. Do not include a trailing “/”.</br>- Click New and Add.<br>   _https://*.my.salesforce-scrt.com_</br>- Click New and Add _https://d2rn326tyl2v2c.cloudfront.net_.|![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Commerce%20Cloud/AWS(CORS).png)|


### Step 3. Trusted URL Configuration

| Step | Action and Details | Image |
|------|-------------|-------|
| Configure Trusted URL | - In Setup, search for Trusted URLs and select it, then click New Trusted Domain.</br>-Enter the API Name and URL — use the same external site URL provided earlier.</br>- Select **frame-src (iframe content)**.</br>- Click Save.</br>- Click New Trusted Domain.</br>-Enter the Name as **CloudFrontImages** and the URL as _https://d2rn326tyl2v2c.cloudfront.net_.</br>- Select the required CSP Directives as shown in the screenshot, then click Save. |![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/CloudFrontTrustedURL.png)|


### Step 4. Get Embedded Service Deployment Code Snippet

| Step | Action and Details | Image |
|------|-------------|-------|
| Script for Executing Agent in External Site |- From Setup, search for Embedded Service Deployments.</br>- Select ESA Web Deployment, scroll down, and click Install Code Snippet.</br>- Copy the code snippet. ||


### Step 5. Verify the Agent on the External Website

  That’s it! You’re all set. The Agentforce widget should now be visible on your external website.
</details>

<details><summary>

  ## 5. (Optional) Setup Commerce Cloud and Experience Cloud
</summary>

### Step 1. Experience Cloud Setup

  | Step | Action and Details | Images |
  | ----- | ----- | ----- |
  | Enable Commerce Cloud | - From Setup, enter **Commerce** in the Quick Find box.</br>- Select **Settings** under **Commerce**.</br>- Turn on **Enable Commerce**. |![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Commerce%20Cloud/EnableCommerce.png)|
  | Create a Basic Experience Builder Site | - From Setup, enter **Digital Experiences** in the Quick Find box.</br>- Select **All Sites** under **Digital Experiences**.</br>- Click New to open the Creation wizard with template options.</br>- Select the **Commerce Store (LWR)** template.</br>- Click Get Started.</br>- Provide Store Name as ‘DIYStorefront’ and ensure the URL ends with /DIYStorefront</br>- Click Create. Your site will be created in Preview status. |![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/Creating%20Site.png)![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/SiteNameAndURL.png)|
  | Activate Site | - From Setup, enter **Digital Experiences** and select **All Sites** under **Digital Experiences**.</br>- Click Workspaces next to DIYStorefront.</br>- Select Administration.</br>- In Settings, click Activate and confirm by clicking OK.</br>- Your site will now be live and fully set up.|![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/Activating%20Site.png)|
  | Register Site Setting |- Go to Domains from Setup under User Interface and copy the Experience Cloud Sites Domain.</br>- Open the ESW Web Deployment site.</br>- Under Trusted Domains for Inline Frames, click New.</br>- Paste the copied domain URL and click Save. | ![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/DomainPageForURL.png) |
  |Digital Experience  |- From Setup, search for Digital Experiences and select Settings.</br>- Enable Allow using standard external profiles for self-registration, user creation, and login.</br>- Click OK in the dialog box.|![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/digitalExperienceAllow.png)|
  | Experience Cloud Automated Setup | - **Deploy Experience cloud package**</br>`sf project deploy start -d diy-pd-experience-optional`<br></br>- **Create Experience Site User**<br>`sf apex run -f scripts/apex/createSiteUser.apex` ||
  | CORS Configuration | - From Setup, search for CORS and click New.</br>- Add **https://*.my.salesforce-scrt.com** and Save.</br>- From Setup, search for and select **Domains** under **User Interface**.</br>- Copy the **My Domain URL** and the **Experience Cloud Sites Domain**.</br>- Add both URLs separately in CORS and click Save.|![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Commerce%20Cloud/SCRT(CORS).png)![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/DomainPageForURL.png)|
  |Trusted URL | - Go to **Domains** under **User Interface** and copy the Experience Cloud Sites Domain.</br>- From Setup, search for Trusted URLs and click New Trusted URL.</br>- Enter the Name as **DIYStore** and paste the copied domain URL, ensuring it starts with https://.</br>- Make Sure to select all the CSP directives. </br>-Click Save. |![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/DIYStoreTrustesURL.png)|
  
  
### Step 2. Commerce Cloud Setup
  | Step | Action and Details | Images |
  | ----- | ----- | ----- |
  | Enable Search Index | - Click on App Launcher, Search and Select Commerce application.</br>- Scroll down to Setting and expand it</br>- Click on Search</br>- Use the toggle to turn on Automatic Updates.|![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Commerce%20Cloud/SearchIndexCMStart.png)|
  | Enable Guest access | - Click on the App Launcher, search for and select the Commerce application and select DiyStoreFront. </br>- On the left-hand side, click Stores under Settings. </br>- Go to Buyer Access Tab. </br>- Navigate to the Buyer Access tab. </br>- Scroll down to the Guest Access section. </br>- Click on Enable button and click on Continue.|![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Commerce%20Cloud/GuestAccessEnable.png)|
  | Assign Guest User to Buyer Group | - In the DiyStoreFront store,  On the left-hand side, click Stores under Settings.<br/>- Click on Buyer Access Tab </br>- Click on DIYStorefront Guest Buyer Profile under Guest Access .</br>- Click on Related ->Click on Buyer Groups , Click on Assign Button <br/> -Select the checkbox for DIYStorefront Buyer Group and click on Assign Button|![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Commerce%20Cloud/BuyerGroup.png) ![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Commerce%20Cloud/AssignGuestToBuyerGroup.png)|
  | Assign Customer User to Buyer Group |- Go to the App Launcher, search for Accounts, and open it.</br>- Open the **Mark Smith** account and click **Enable as Buyer**.</br>- In **DIYStoreFront**, navigate to Settings > Buyer Access.</br>- Open the **DIYStorefront Buyer Group**.</br>- Under Buyer Group Members, click Assign, search for Mark Smith, and click Save. |![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/enableBuyerGrp1.png?raw=true)![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/enableBuyerGrp2.png?raw=true)![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/AssignCustomerUserForBG.png)|
  | Execute Commerce Script | - **Create Commerce Data**:</br>`sf apex run -f scripts/apex/createCommerceData.apex` <br></br>- **Create Store Pricebook**:</br>`sf apex run -f scripts/apex/storePricebookCreation.apex`||
  | Create CMS Workspace  |- Click on the App Launcher \>\> Select the Commerce application \>\> Click on Stores.</br>- Open DIYStorefront Store</br>- Scroll down to Content Manager</br>- Click on Add workspace</br>-  Enter details such as Name "DIYStoreFront CMS". </br>- click on Next</br>- Add **DIYStoreFrontChannel & DIYStoreFront**. </br>- Click Next</br>- Keep language as it is and click on Finish | ![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Commerce%20Cloud/CMSWorkspaceChannel.png)![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Commerce%20Cloud/CMSWorkspaceChannel.png)|
  | Link Image to a Product   |- Download Images from [CMS Images](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/tree/master/DIYStore%20Product%20Images)</br>- Click the App Launcher.</br>- Select the Commerce application.</br>- Open Stores and select DIYStorefront.</br>- Navigate to Merchandise > Products and open the required product.</br>- Scroll down to the Media section.</br>- Click Add and select Add Image from Library.</br>- Choose the appropriate image and click Save. | ![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Commerce%20Cloud/Merchandise.png)![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Commerce%20Cloud/Media.png)|
  | Publish Website Design |- Click on the App Launcher.</br>- Select the Commerce application.</br>- Go to Stores and select DIYStoreFront.</br>- Scroll down to Website Design.</br>- From the dropdown, select Product, Category, then click Publish (this step may not be required if you are using the Commerce Console).</br>- Go back to the DIYStoreFront store.</br>- Click Home, then click Preview to verify that the products are displayed on the site.|![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Commerce%20Cloud/PublishProduct.png)![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Commerce%20Cloud/PublishCategory.png)|
  | Update Search Index |- From Commerce App Go to Setting >> Search.  </br>- Under Search Index Tab >> Click on Update Button on the top Right corner. </br>- Select Full Update. </br>- Wait until the update completes to see the product in ExperienceSite. |![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Commerce%20Cloud/searchindexupdate.png)![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Commerce%20Cloud/searchindexStatus.png)| 

### Step 3. Configure Experience Site Images from CMS Workspace
  | Step | Action and Details | Images |
  | ----- | ----- | ----- |
  | Add Site Logo | - From Setup, search for All Sites and click Builder next to DIYStorefront.</br>- On the top-left corner, click on the Site Logo.</br>- Click **Select Image from CMS** and choose the appropriate **DIY Store logo** image/br>- Scroll to the bottom, select the Footer Logo, and update it by selecting the same **DIY Store logo** from CMS.|![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/TopSiteLogo.png)![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/FooterLogo.png)|
 | Configure Background Images | - Click on the Background Image section in Experience Builder.</br>- Click **Select Image from CMS** and choose the **DIYStoreBanner** image.</br>- Scroll to the middle of the page to locate the Left and Right Background Image sections.</br>- Select **DIYStoreBanner3** for the Left section and **DIYStoreBanner2** for the Right section. |![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/BackgroundBanner.png)![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/BannerLeft.png)![image](https://git.soma.salesforce.com/gdevadoss/Data360RetailSolutionKit/blob/master/Experience%20Cloud/BannerRight.png)|
  
</details>
<details><summary>

 ## Behind the Scenes - how is the agent powered?
</summary>
Curious to see the all possible utterances  and how they are powered by the Agent. Here is a list of all the possible conversations, the corresponding topics, and the components that power them. </br></br>
$${\color{blue} A \space guest \space user \space asks \space general \space sales \space and \space seasonal \space preparation \space questions \space through \space the \space Service \space Agent(DIY Assistant) \space deployed \space on \space the \space external \space website.}$$


 | Sl. No. | Utterance | Behind the Scene | Topic | Components |
   | ----- | ----- | ----- | ----- | ----- |
   | 1. |What is on sale right now? |  Based on the structured data ingested into Data Cloud, we are fetching the promotional products and displaying them. | DIY Store Assistant | a) Apex </br>ItemsOnSale|
   | 2. |Do I need anything for seasonal prep? | An initial prompt evaluates the current weather data. Based on the evaluated conditions, a subsequent prompt dynamically fetches weather-specific product  | DIY Store Assistant | a) Flow </br>Seasonal Product Recommender</br></br>b) Prompt<br>Season Predictor<br>Fetch Seasonal Products|
   | 3. |How do I protect my plants over the winter? | Reads unstructured data from PDF that has been ingested into Data Cloud, where it is chunked, vectorized, and indexed for easy retrieval. |plant Seasonal Recomendation | a) Prompt Action <br/> seasonalPlantRecomendation |

   $${\color{blue} For \space LoggedIn \space User \space on \space Service \space Agent(DIY Assistant) \space is \space Deployed }$$ There is a single contact populated with all the relevant information needed to drive these conversations — Mark Smith. By using this contact, you can log in to Experience Cloud and have full conversations.

 | Sl. No. | Utterance | Behind the Scene | Topic | Components |
   | ----- | ----- | ----- | ----- | ----- |
   | 1. |I’m stopping by the store later — anything I should pick up? | Use LLM to analyze customer past purchase history about power tools and but does not have any storage products, and recommend suitable storage options used an prompt|Customer Purchase Order | a) Prompt Action <br/>combineRecomendationMethod </br></br>b) Apex Class<br/> GenericProductService</br>GenericProductInvocable |
   | 2. |That storage cabinet looks huge. Not sure how I’d get it home |Reads unstructured data from PDF that has been ingested into Data Cloud, where it is chunked, vectorized, and indexed for easy retrieval. |Customer Purchase Order |a) Prompt Action <br/> storageCabinetDetails b)Retriever <br/>DIY_Bathroom Retriever|
   | 3. |Do I need anything for seasonal prep? | An initial prompt evaluates the current weather data. Based on the evaluated conditions, a subsequent prompt dynamically fetches weather-specific product  | DIY Store Assistant | a) Flow </br>Seasonal Product Recommender</br></br>b) Prompt<br>Season Predictor<br>Fetch Seasonal Products|
   | 4. |What are the current sales that would interest me? | The system leverages structured data ingested into Data Cloud to analyze the customer’s historical purchase records. Any products that overlap with active promotions are filtered out, and only the remaining eligible promotional products are displayed. | DIY Store Assistant | a) Apex</br>Generic Product Engine |
   | 5. |My furnace has been acting up | The system uses structured Data Cloud data to verify installation and maintenance records. It evaluates whether the product has exceeded its warranty period and provides the corresponding warranty status (in-warranty or out-of-warranty). If requested, it also suggests an appropriate basic maintenance plan. |DIY Store Assistance| a) Apex </br>HVACWarrantyService|
   | 6. |I’m remodeling my bathroom — what do I need? |Reads unstructured data from PDF that has been ingested into Data Cloud, where it is chunked, vectorized, and indexed for easy retrieval.|DIY Projects|a) Prompt Action <br/> Bathroom Remodeling Prompt</br></br> b)Retriever <br/>DIY_Bathroom Retriever|
   | 7. |I bought composite decking — is my blade okay? | Use LLM to analyze customer past purchase history about blade product and provide information as blade product description and features |Blade Product | a) Prompt Action<br/> BladeProductRecomendation</br></br> b) Flow <br/> Fetch Seasonal Products  |
   | 8. |I’m thinking about upgrading my tools. |Use LLM to analyze customer past purchase history about battery product and recommends environmentally friendly alternatives. |Customer Purchase Products |a) Prompt Action <br/> BatteryProductRecomendation</br></br>b) Apex Class<br/> GenericProductService</br>GenericProductInvocabler |
   | 9. |Anything interesting on sale right now?| Structured data stored in Data Cloud is used to analyze the customer’s past purchase history and derive product categories. Based on the identified categories, relevant products are recommended.  | DIY Store Assistant | a) Apex</br>CurrentSalesRecommendation|

$${\color{blue} For \space Employee \space Agent }$$ There is a single contact populated with all the relevant information needed to drive these conversations — Mark Smith. You can access the contact record page for this contact to have full conversations.


 | Sl. No. | Utterance | Behind the Scene | Topic | Components |
   | ----- | ----- | ----- | ----- | ----- |
   | 1. |I’m stopping by the store later — anything I should pick up? | Customer purchase history is retrieved from structured Data Cloud datasets and analyzed to identify previously purchased product categories, such as power tools |DIY Store Assistant |a) Flow</br>StorageProductEnquiry </br></br>b) Apex</br>storageProducts</br>storageProductInvocable</br></br>c) LightningType</br>storageProducts|
   | 2. |That storage cabinet looks huge. Not sure how I’d get it home |Reads unstructured data from PDF that has been ingested into Data Cloud, where it is chunked, vectorized, and indexed for easy retrieval. |Customer Purchase Products |a) Prompt Action <br/> storageCabinetDetails</br></br> b) Retriever <br/>DIY_Bathroom Retriever |
   | 3. |Do I need anything for seasonal prep? | An initial prompt evaluates the current weather data. Based on the evaluated conditions, a subsequent prompt dynamically fetches weather-specific product  | DIY Store Assistant | a) Flow </br>Seasonal Product Recommender</br></br>b) Prompt<br>Season Predictor<br>Fetch Seasonal Products</br></br>c) Apex</br>seasonalProducts</br></br>d) LightningType</br>seasonalProducts|
   | 4. |What are the current sales that would interest me? | The system leverages structured data ingested into Data Cloud to analyze the customer’s historical purchase records. Any products that overlap with active promotions are filtered out, and only the remaining eligible promotional products are displayed. | DIY Store Assistant | a) Flow</br> PromotionEligibility<br></br> b) Apex</br>Get Promotion Details</br>promotion</br></br>c) LightningType</br>promotion|
   | 5. |My furnace has been acting up  | The system uses structured Data Cloud data to verify installation and maintenance records. It evaluates whether the product has exceeded its warranty period and provides the corresponding warranty status (in-warranty or out-of-warranty). If requested, it also suggests an appropriate basic maintenance plan. |DIY Store Assistance| a) Apex</br>HVACWarrantyService|
   | 6. |I’m remodeling my bathroom — what do I need? |Reads unstructured data from PDF that has been ingested into Data Cloud, where it is chunked, vectorized, and indexed for easy retrieval.|DIY Projects|a) Prompt Action <br/> Bathroom Remodeling Prompt </br></br> b) Retriever <br/>DIY_Bathroom Retriever|
   | 7. |I bought composite decking — is my blade okay? | Uses LLM to analyze customer past purchase history about blade product and provide information as blade product description and features |Blade Product | a) Prompt Action<br/> BladeProductRecomendation |
   | 8. |I’m thinking about upgrading my tools. |Customer past purchase history is retrieved from structured Data Cloud datasets to identify battery-related products. Based on predefined product attributes and sustainability classifications, environmentally friendly alternatives are recommended accordingly.|Customer Purchase Products|a) Flow</br>UpgradingToolsSuggestion</br></br>b) Apex</br>storageProducts</br>batteryProductRecomendationCls</br></br>c) LightningType</br>storageProducts|
   | 9. |Anything interesting on sale right now?|Structured data stored in Data Cloud is used to analyze the customer’s past purchase history and derive product categories. Based on the identified categories, relevant products are recommended.  | DIY Store Assistant | a) Flow</br>SalesRecommendation</br></br>b) Apex </br>Current Sales Recommendations </br>seasonalProducts</br></br>c) LightningType</br>seasonalProducts|
