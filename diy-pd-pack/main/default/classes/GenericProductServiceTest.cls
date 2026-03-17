@IsTest
public without sharing class GenericProductServiceTest {
    
    // ========================================================
    // GenericProductService Methods using SOQL Stubs
    // ========================================================
    @IsTest
    public static void testAllMethods_WithSoqlStubs() {
        
        // Account and contact
        Account acct = new Account(Name = 'Test Account');
        insert acct;
        
        Contact con = new Contact(
            FirstName = 'Test',
            LastName  = 'User',
            AccountId = acct.Id
        );
        insert con;
        
        Id dummyContactId = con.Id;
        
        //  Register SOQL Stubs
        SoqlStubProvider stub = new GenericProductServiceSoqlStub(dummyContactId);
        
        Test.createSoqlStub(ssot__SalesOrder__dlm.sObjectType, stub);
        Test.createSoqlStub(ssot__SalesOrderProduct__dlm.sObjectType, stub);
        Test.createSoqlStub(ssot__Product__dlm.sObjectType, stub);
        Test.createSoqlStub(ssot__PromotionProduct__dlm.sObjectType, stub);
        

        // Execute all service methods
        Test.startTest();
        
        GenericProductService.Response promoRes =
            GenericProductService.customerPromotionEligibility(dummyContactId);
        
        GenericProductService.Response storageRes =
            GenericProductService.returnStorageRecommendation(dummyContactId);
        
        GenericProductService.Response bladeRes =
            GenericProductService.returnBladeRecomendation(dummyContactId);
        
        GenericProductService.Response batteryRes =
            GenericProductService.returnBatteryRecomendation(dummyContactId);
        
        Test.stopTest();
        
        // Assertions
        // Promotion
        System.assertNotEquals(null, promoRes, 'Promo response should not be null');
        System.assert(promoRes.messages.size() > 0, 'Promo should have messages');
        System.assert(promoRes.products.size() > 0, 'Promo should have products');
        
        // Storage
        System.assertNotEquals(null, storageRes, 'Storage response should not be null');
        System.assert(
            storageRes.products.size() > 0 || storageRes.messages.size() > 0,
            'Storage should have products or messages'
        );
        
        // Blade
        System.assertNotEquals(null, bladeRes, 'Blade response should not be null');
        System.assert(
            bladeRes.products.size() > 0 || bladeRes.messages.size() > 0,
            'Blade should have products or messages'
        );
        
        // Battery
        System.assertNotEquals(null, batteryRes, 'Battery response should not be null');
        System.assert(batteryRes.messages.size() > 0, 'Battery should have messages');
        System.assert(batteryRes.products.size() > 0, 'Battery should have products');
    }
    
    // ========================================================
    //  GenericProductInvocable Class
    // ========================================================
    @IsTest
    public static void testGenericProductInvocable() {
        
        Account acct = new Account(Name = 'Test Account Invocable');
        insert acct;
        
        Contact con = new Contact(
            FirstName='Flow',
            LastName='User',
            AccountId=acct.Id
        );
        insert con;
        
        Id dummyContactId = con.Id;
        
       // Register SOQL Stubs (reuse existing stub)
        SoqlStubProvider stub = new GenericProductServiceSoqlStub(dummyContactId);
        
        Test.createSoqlStub(ssot__SalesOrder__dlm.sObjectType, stub);
        Test.createSoqlStub(ssot__SalesOrderProduct__dlm.sObjectType, stub);
        Test.createSoqlStub(ssot__Product__dlm.sObjectType, stub);
        Test.createSoqlStub(ssot__PromotionProduct__dlm.sObjectType, stub);
        
        //  Prepare Requests
        List<GenericProductInvocable.Request> requests = new List<GenericProductInvocable.Request>();
        
        GenericProductInvocable.Request reqPromotion = new GenericProductInvocable.Request();
        reqPromotion.requestType = 'PROMOTION';
        reqPromotion.contactId = dummyContactId;
        requests.add(reqPromotion);
        
        GenericProductInvocable.Request reqStorage = new GenericProductInvocable.Request();
        reqStorage.requestType = 'STORAGE_PRODUCTS';
        reqStorage.contactId = dummyContactId;
        requests.add(reqStorage);
        
        GenericProductInvocable.Request reqBlade = new GenericProductInvocable.Request();
        reqBlade.requestType = 'BLADE_PRODUCTS';
        reqBlade.contactId = dummyContactId;
        requests.add(reqBlade);
        
        GenericProductInvocable.Request reqBattery = new GenericProductInvocable.Request();
        reqBattery.requestType = 'BATTERY_PRODUCTS';
        reqBattery.contactId = dummyContactId;
        requests.add(reqBattery);
        
        
        Test.startTest();
        List<GenericProductInvocable.promptResponse> responses =
            GenericProductInvocable.invoke(requests);
        Test.stopTest();
        
        //  Assertions

        System.assertEquals(4, responses.size(), 'Should return 4 prompt responses');
        
        for (GenericProductInvocable.promptResponse pr : responses) {
            System.assertNotEquals(null, pr.Prompt, 'Prompt should not be null');
            System.assert(
                pr.Prompt.contains('Recommended Products') || pr.Prompt.contains('No product recommendations'),
                'Prompt should contain products or fallback message'
            );
        }
    }
    
    // ========================================================
    //  SOQL STUB PROVIDER (used for both service and invocable)
    // ========================================================
    public class GenericProductServiceSoqlStub extends SoqlStubProvider {
        
        public String contactIdStr;
        
        public GenericProductServiceSoqlStub(Id contactId) {
            this.contactIdStr = String.valueOf(contactId);
        }
        
        public override List<SObject> handleSoqlQuery(
            SObjectType sot,
            String query,
            Map<String, Object> bindVars
        ) {
            List<SObject> results = new List<SObject>();
            
            // -----------------------------
            // Sales Orders
            // -----------------------------
            if (sot == ssot__SalesOrder__dlm.sObjectType) {
                results.add(Test.createStubQueryRow(
                    sot,
                    new Map<String, Object>{
                        'ssot__Id__c' => 'SO1',
                            'ssot__BillToContactId__c' => contactIdStr
                            }
                ));
                return results;
            }
            
            // -----------------------------
            // Sales Order Products
            // -----------------------------
            if (sot == ssot__SalesOrderProduct__dlm.sObjectType) {
                
                results.add(Test.createStubQueryRow(
                    sot, new Map<String, Object>{
                        'ssot__SalesOrderId__c' => 'SO1',
                            'ssot__ProductId__c'    => 'PROD_POWER'
                            }
                ));
                
                results.add(Test.createStubQueryRow(
                    sot, new Map<String, Object>{
                        'ssot__SalesOrderId__c' => 'SO1',
                            'ssot__ProductId__c'    => 'PROD_BLADE'
                            }
                ));
                
                results.add(Test.createStubQueryRow(
                    sot, new Map<String, Object>{
                        'ssot__SalesOrderId__c' => 'SO1',
                            'ssot__ProductId__c'    => 'PROD_DECK'
                            }
                ));
                
                results.add(Test.createStubQueryRow(
                    sot, new Map<String, Object>{
                        'ssot__SalesOrderId__c' => 'SO1',
                            'ssot__ProductId__c'    => 'PROD_BATTERY'
                            }
                ));
                
                return results;
            }
            
            // -----------------------------
            // Promotion Products
            // -----------------------------
            if (sot == ssot__PromotionProduct__dlm.sObjectType) {
                results.add(Test.createStubQueryRow(
                    sot, new Map<String, Object>{
                        'ssot__ProductId__c'   => 'PROD_STORAGE',
                            'ssot__PromotionId__c' => 'PROMO1'
                            }
                ));
                return results;
            }
            
            // -----------------------------
            // Products
            // -----------------------------
            if (sot == ssot__Product__dlm.sObjectType) {
                
                results.add(Test.createStubQueryRow(
                    sot, new Map<String, Object>{
                        'ssot__Id__c'            => 'PROD_POWER',
                            'ssot__Name__c'          => 'Cordless Power Tool',
                            'ssot__ProductFamily__c'=> 'Power Tools'
                            }
                ));
                
                results.add(Test.createStubQueryRow(
                    sot, new Map<String, Object>{
                        'ssot__Id__c'            => 'PROD_STORAGE',
                            'ssot__Name__c'          => 'Storage Box',
                            'ssot__ProductFamily__c'=> 'Storage'
                            }
                ));
                
                results.add(Test.createStubQueryRow(
                    sot, new Map<String, Object>{
                        'ssot__Id__c'            => 'PROD_BLADE',
                            'ssot__Name__c'          => 'Circular Blade',
                            'ssot__ProductFamily__c'=> 'Blade'
                            }
                ));
                
                results.add(Test.createStubQueryRow(
                    sot, new Map<String, Object>{
                        'ssot__Id__c'            => 'PROD_DECK',
                            'ssot__Name__c'          => 'Composite Deck Board',
                            'ssot__ProductFamily__c'=> 'Decks'
                            }
                ));
                
                results.add(Test.createStubQueryRow(
                    sot, new Map<String, Object>{
                        'ssot__Id__c'            => 'PROD_BATTERY',
                            'ssot__Name__c'          => 'Power Battery 18V',
                            'ssot__ProductFamily__c'=> 'Batteries'
                            }
                ));
                
                return results;
            }
            
            return results;
        }
    }
}