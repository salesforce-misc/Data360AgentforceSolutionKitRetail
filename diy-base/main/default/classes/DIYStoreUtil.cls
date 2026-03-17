/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-27-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public with sharing class DIYStoreUtil {
    
   
    /**
     * Activates the Standard Price Book if it is not active
     */
    public static void activateStandardPricebook() {
        
        // Get Standard Pricebook Id
        Id stdPricebookId = Test.isRunningTest() 
            ? Test.getStandardPricebookId()
            : [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;

        // Query existing Standard PriceBook
        Pricebook2 stdPricebook = [
            SELECT Id, IsActive
            FROM Pricebook2
            WHERE Id = :stdPricebookId
            LIMIT 1
        ];

        // Activate only if not already active
        if (!stdPricebook.IsActive) {
            stdPricebook.IsActive = true;
            update stdPricebook;
        }
    }

//Activate Order Status 
//
    public static void updateOrderStatusToActivated(){
        List<Order> ordersToActivate = [
            SELECT Id, Status,(SELECT OrderId FROM OrderItems)
            FROM Order Where BillToContact.isDIYRecord__c  = true and Status = 'Draft' and Name IN ('HVAC Maintenance','HVAC Installation')                                  
        ];
        System.debug('## ordersToActivate = '+ordersToActivate);
        List<Order> readyToActivate = new List<Order>();
        
        for (Order ord : ordersToActivate) {
            System.debug('## ord.OrderItems.isEmpty() = '+ord.OrderItems.isEmpty());
            if (!ord.OrderItems.isEmpty()) {
                ord.Status = 'Activated';
                readyToActivate.add(ord);
            } else {
                System.debug('Skipping Order (No OrderItems): ' + ord.Id);
            }
        }
        
        if (!readyToActivate.isEmpty()) {
            update readyToActivate;
        }        
    }
    
  // Create Agent User with required Permission Set Licenses and Permission Sets
   @TestVisible
    private final static Set<String> PERM_SET_LICENSES = new Set<String>{'AgentforceServiceAgentUserPsl','GenieDataPlatformStarterPsl','EinsteinGPTPromptTemplatesPsl','AgentforceServiceAgentBuilderPsl'};         
    private final static Set<String> PERM_SETS = new Set<String>{'GenieAdmin','EinsteinGPTPromptTemplateUser','EinsteinGPTPromptTemplateManager','AgentforceServiceAgentBuilder','AgentforceServiceAgentBase','AgentforceServiceAgentSecureBase','AgentforceServiceAgentUser','GenieUserEnhancedSecurity','RetailDIYStorePS'};                      
            public static void setup() {
                String uniqueString = String.valueOf(DateTime.now().getTime());    
                // Get agent profile
                Profile p = [
                    SELECT Id
                    FROM Profile
                    WHERE Name = 'Einstein Agent User'
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
                
                User u = new user();
                    u.FirstName = 'Einstein';
                    u.LastName = 'User';
                    u.Email = 'eagent' + uniqueString + '@example.com';
                    u.Username = 'eagent' + uniqueString + '@example.com';
                    u.Alias = 'ea' + uniqueString.substring(uniqueString.length()-3);
                    u.TimeZoneSidKey = 'America/New_York';
                    u.LocaleSidKey = 'en_US';
                    u.EmailEncodingKey = 'UTF-8';
                    u.LanguageLocaleKey = 'en_US';
                    u.ProfileId = p.Id;
                    insert u;
                    System.debug('Created user: ' + u.Username);
                 Set<Id> targetPslIds = getPermissionSetLicenseIds();

                //Assign Permission Set Licenses to user
                List<PermissionSetLicenseAssign> pslAssignments = new List<PermissionSetLicenseAssign>();
                for (Id pslId : targetPslIds) {
                    pslAssignments.add(new PermissionSetLicenseAssign(
                        AssigneeId = u.Id,
                        PermissionSetLicenseId = pslId
                    ));

                }
                insert pslAssignments;
                // Query Permission Sets to assign                
                List<PermissionSet> setsToAssign = [
                    SELECT Id
                    FROM PermissionSet
                    WHERE Name IN :PERM_SETS
                ];
                
                // Assign Permission Sets to user
                List<PermissionSetAssignment> psAssignments = new List<PermissionSetAssignment>();
                for (PermissionSet ps : setsToAssign) {
                    psAssignments.add(new PermissionSetAssignment(
                        AssigneeId = u.Id,
                        PermissionSetId = ps.Id
                    ));
                }
                insert psAssignments;
            }
    
    
    @TestVisible
    private static Set<Id> getPermissionSetLicenseIds() {
        return new Map<Id, PermissionSetLicense>(
            [
                SELECT Id
                FROM PermissionSetLicense
                WHERE DeveloperName IN :PERM_SET_LICENSES
                WITH SECURITY_ENFORCED
            ]
        )
            .keySet();
    }
  
   
    
    
    /**
     * Updates EffectiveDate to a random past date
     * within the last 120 days for Orders
     * where Bill To Contact name matches the input.
     */
     public static void updateEffectiveDate() { 
        DIYStoreUtil.syncContactIdsForRelatedRecords();

        List<Order> ordersToUpdate = [ SELECT Id,Name,Status FROM Order WHERE BillToContact.isDIYRecord__c  = true
                                      AND Name NOT IN ('HVAC Maintenance','HVAC Installation ') AND Id IN 
                                      (SELECT OrderId FROM OrderItem)];

        if (ordersToUpdate.isEmpty()) {
            System.debug('No Orders found for contact: ' + ordersToUpdate);
            return;
        }

        Date today = Date.today();

        for (Order o : ordersToUpdate) {            
			Integer randomDays = -1;
            // Set EffectiveDate to random past date
            o.EffectiveDate = today.addDays(-randomDays);
            o.EndDate = today.addYears(2);
            o.Status = 'Activated';
        }

        update ordersToUpdate;

        DIYStoreUtil.updateOrderStatusToActivated();
        DIYStoreUtil.assignCopyFieldPermission();
        
        
        System.debug('Updated Orders count: ' + ordersToUpdate.size());
    }
    
     public static void syncContactIdsForRelatedRecords() {

        /* --------------------------------------------------
           1. Get today's Orders
        -------------------------------------------------- */
        List<Order> orders = [
            SELECT Id, AccountId, BillToContactId
            FROM Order
            WHERE CreatedDate = TODAY
            AND AccountId != NULL and Account.IsPersonAccount = true
        ];

        /* --------------------------------------------------
           2. Get Assets: Name = HVAC Installation
        -------------------------------------------------- */
        List<Asset> assets = [
            SELECT Id, AccountId, ContactId, Name
            FROM Asset
            WHERE Name = 'HVAC Installation'
            AND AccountId != NULL and Account.IsPersonAccount = true
        ];

        /* --------------------------------------------------
           3. Get Service Appointments (1 per Account assumed)
        -------------------------------------------------- */
        List<ServiceAppointment> appointments = [
            SELECT Id, AccountId, ContactId
            FROM ServiceAppointment
            WHERE AccountId != NULL and Account.IsPersonAccount = true
        ];

        /* --------------------------------------------------
           4. Collect Account Ids
        -------------------------------------------------- */
        Set<Id> accountIds = new Set<Id>();

        for (Order o : orders) {
            accountIds.add(o.AccountId);
        }

        for (Asset a : assets) {
            accountIds.add(a.AccountId);
        }

        for (ServiceAppointment sa : appointments) {
            accountIds.add(sa.AccountId);
        }

        if (accountIds.isEmpty()) {
            return;
        }

        /* --------------------------------------------------
           5. Query Person Accounts
        -------------------------------------------------- */
        Map<Id, Account> accountMap = new Map<Id, Account>([
            SELECT Id, PersonContactId, IsPersonAccount
            FROM Account
            WHERE Id IN :accountIds
            AND IsPersonAccount = true
        ]);

        /* --------------------------------------------------
           6. Prepare Updates
        -------------------------------------------------- */
        List<Order> ordersToUpdate = new List<Order>();
        List<Asset> assetsToUpdate = new List<Asset>();
        List<ServiceAppointment> appointmentsToUpdate = new List<ServiceAppointment>();

        /* Orders */
        for (Order o : orders) {

            Account acc = accountMap.get(o.AccountId);

            if (acc != null && acc.PersonContactId != null) {

                if (o.BillToContactId == null) {

                    o.BillToContactId = acc.PersonContactId;
                    ordersToUpdate.add(o);
                }
            }
        }

        /* Assets */
        for (Asset a : assets) {

            Account acc = accountMap.get(a.AccountId);

            if (acc != null && acc.PersonContactId != null) {

                if (a.ContactId == null) {

                    a.ContactId = acc.PersonContactId;
                    assetsToUpdate.add(a);
                }
            }
        }

        /* Service Appointments */
        for (ServiceAppointment sa : appointments) {

            Account acc = accountMap.get(sa.AccountId);

            if (acc != null && acc.PersonContactId != null) {

                if (sa.ContactId == null) {

                    sa.ContactId = acc.PersonContactId;
                    appointmentsToUpdate.add(sa);
                }
            }
        }

        /* --------------------------------------------------
           7. Bulk Update
        -------------------------------------------------- */

        if (!ordersToUpdate.isEmpty()) {
            update ordersToUpdate;
        }

        if (!assetsToUpdate.isEmpty()) {
            update assetsToUpdate;
        }

        if (!appointmentsToUpdate.isEmpty()) {
            update appointmentsToUpdate;
        }
    }
    
     @future
    public static void assignCopyFieldPermission(){
        // ============================================================
        // Customer 360 Permission Fix Script
        // ============================================================
        
        // Fields to grant access
        List<String> copyFieldAccess = new List<String>{
            'Average_Order_Value__c','Average_Purchase_Value__c','Customer_Since__c',
                'Lifetime_Value__c','Customer_BrandAffinity__c','Customer_OwnershipStatus__c',
                'Customer_PurchaseFrequency__c','Customer_MaritalStatus__c',
                'Customer_IsSingleFamilyHome__c','Customer_Seasonality__c',
                'Customer_FamilySizes__c','Customer_ResidenceType__c',
                'Customer_Unified_Individual_Id__c','Customer_ProjectFrequency__c',
                'Customer_StorePreference__c','Customer_IncomeLevel__c',
                'Customer_GarageSize__c','Customer_Type__c',
                'Customer_IsWorkshopSpacePresent__c','Customer_VehicleType__c',
                'Customer_ServicePreference__c','Customer_SkillLevel__c'
                };
                    
                    // Get Permission Set
                    List<PermissionSet> permissionSetList = [
                        SELECT Id 
                        FROM PermissionSet 
                        WHERE Label ='Customer 360 Data Platform Integration' 
                        LIMIT 1
                    ];
        
        if(permissionSetList.isEmpty()){
            System.debug('Permission Set not found.');
            return;
        }
        
        Id permSetId = permissionSetList[0].Id;
        String objectName = 'Contact';
        
        // ============================================================
        // FIELD PERMISSIONS
        // ============================================================
        
        // Prepare full field names
        Set<String> fullFieldNames = new Set<String>();
        for(String field : copyFieldAccess){
            fullFieldNames.add(objectName + '.' + field);
        }
        
        // Query existing field permissions
        List<FieldPermissions> existingFieldPerms = [
            SELECT Id, Field, PermissionsRead, PermissionsEdit
            FROM FieldPermissions
            WHERE ParentId = :permSetId
            AND Field IN :fullFieldNames
        ];
        
        Map<String, FieldPermissions> existingFieldMap = new Map<String, FieldPermissions>();
        for(FieldPermissions fp : existingFieldPerms){
            existingFieldMap.put(fp.Field, fp);
        }
        
        List<FieldPermissions> fieldsToInsert = new List<FieldPermissions>();
        List<FieldPermissions> fieldsToUpdate = new List<FieldPermissions>();
        
        for(String field : copyFieldAccess){
            
            String fullName = objectName + '.' + field;
            
            if(existingFieldMap.containsKey(fullName)){
                
                FieldPermissions existingFP = existingFieldMap.get(fullName);
                
                if(existingFP.PermissionsRead == true && existingFP.PermissionsEdit == true){
                    continue; // Already correct
                }
                
                existingFP.PermissionsRead = true;
                existingFP.PermissionsEdit = true;
                fieldsToUpdate.add(existingFP);
                
            } else {
                
                fieldsToInsert.add(new FieldPermissions(
                    ParentId = permSetId,
                    SObjectType = objectName,
                    Field = fullName,
                    PermissionsRead = true,
                    PermissionsEdit = true
                ));
            }
        }
        
        if(!fieldsToInsert.isEmpty()){
            insert fieldsToInsert;
            System.debug('Inserted Field Permissions: ' + fieldsToInsert.size());
        }
        
        if(!fieldsToUpdate.isEmpty()){
            update fieldsToUpdate;
            System.debug('Updated Field Permissions: ' + fieldsToUpdate.size());
        }
        
        // ============================================================
        // OBJECT PERMISSIONS (Contact + Account)
        // ============================================================
        
  List<String> objectsToCheck = new List<String>{'Account','Contact'};

//  Query existing Object Permissions
List<ObjectPermissions> existingPermissions = [
    SELECT Id,
           SObjectType,
           PermissionsRead,
           PermissionsEdit,
           PermissionsDelete,
           PermissionsViewAllRecords,
           PermissionsModifyAllRecords
    FROM ObjectPermissions
    WHERE ParentId = :permSetId
    AND SObjectType IN :objectsToCheck
];

//  Map existing permissions
Map<String, ObjectPermissions> existingMap = new Map<String, ObjectPermissions>();
for(ObjectPermissions op : existingPermissions){
    existingMap.put(op.SObjectType, op);
}

//  Prepare lists
List<ObjectPermissions> toInsert = new List<ObjectPermissions>();
List<ObjectPermissions> toUpdate = new List<ObjectPermissions>();

//  Process each object
for(String objName : objectsToCheck){

    if(existingMap.containsKey(objName)){

        ObjectPermissions op = existingMap.get(objName);
        Boolean needsUpdate = false;

        if(!op.PermissionsRead){
            op.PermissionsRead = true;
            needsUpdate = true;
        }

        if(!op.PermissionsEdit){
            op.PermissionsEdit = true;
            needsUpdate = true;
        }

        if(!op.PermissionsDelete){
            op.PermissionsDelete = true;
            needsUpdate = true;
        }

        if(!op.PermissionsViewAllRecords){
            op.PermissionsViewAllRecords = true;
            needsUpdate = true;
        }

        if(!op.PermissionsModifyAllRecords){
            op.PermissionsModifyAllRecords = true;
            needsUpdate = true;
        }

        if(needsUpdate){
            toUpdate.add(op);
        }

    } else {

        // Insert if not exists
        toInsert.add(new ObjectPermissions(
            ParentId = permSetId,
            SObjectType = objName,
            PermissionsRead = true,
            PermissionsCreate = false,
            PermissionsEdit = true,
            PermissionsDelete = true,
            PermissionsViewAllRecords = true,
            PermissionsModifyAllRecords = true
        ));
    }
}

//  Perform DML
if(!toInsert.isEmpty()){
    insert toInsert;
    System.debug('Inserted Object Permissions: ' + toInsert.size());
}

if(!toUpdate.isEmpty()){
    update toUpdate;
    System.debug('Updated Object Permissions: ' + toUpdate.size());
}

System.debug('Permission assignment completed successfully.');
    }
  
    
    public static void expSiteUserCreation(){
        List<Contact> contactRecord = [SELECT Id, FirstName, Name, LastName, Email FROM Contact WHERE Name = 'Mark Smith' AND isDIYRecord__c = true LIMIT 1];
        UserLicense ul=[SELECT Id, Status, MasterLabel, Name FROM UserLicense Where Name='Customer Community Plus Login' LIMIT 1];
        Profile profList = [SELECT Id, UserLicenseId FROM Profile Where Name = 'Customer Community Plus Login User' LIMIT 1];
     
        if (!contactRecord.isEmpty()  && profList != null) {
                String uniqueString = String.valueOf(DateTime.now().getTime());
                String emailAddress = contactRecord[0].Email;
                System.debug('community user email ->'+emailAddress);
                String userName = emailAddress +'diy'+uniqueString;
                
                User usr = new user();
                usr.FirstName = 'Mark';
                usr.LastName='Smith';
                usr.Email = emailAddress;               
                usr.Alias = 'ms' + uniqueString.substring(uniqueString.length()-3);
                usr.Username = userName;
                usr.LocaleSidKey = 'en_US';
                usr.TimeZoneSidKey = 'GMT';
                usr.ProfileID = profList.Id;
                usr.LanguageLocaleKey = 'en_US';
                usr.EmailEncodingKey = 'UTF-8';
                usr.ContactId = contactRecord[0].Id;
                //usr.IsPortalEnabled = true;
                insert usr;
                System.debug(usr + 'usr');
                
                User userRecord = [SELECT Id, IsPortalEnabled, ProfileId FROM User WHERE ContactId = :contactRecord[0].Id LIMIT 1]; 
                If(userRecord != NULL){
                    userRecord.IsPortalEnabled = true;
                    UPDATE userRecord;
                }
            
            
            List<PermissionSet> permSets = [SELECT Id  FROM PermissionSet WHERE 
                                            Name IN ('B2BBuyer', 'RetailDIYStorePS')];
            
            if (!permSets.isEmpty()) {
                List<PermissionSetAssignment> psaList = new List<PermissionSetAssignment>();
                
                for (PermissionSet ps : permSets) {
                    psaList.add(new PermissionSetAssignment(
                        AssigneeId = usr.Id,
                        PermissionSetId = ps.Id
                    ));
                }
                insert psaList;
            }
            System.setPassword(usr.Id, 'orgfarm123');
        }
    }
    
    
    
}