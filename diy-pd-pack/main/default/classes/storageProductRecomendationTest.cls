@IsTest
    public without sharing class storageProductRecomendationTest {

    @IsTest
    public static void testReturnStorageProductsStub() {

        // ===== Step 0: Create real Account and Contact =====a
        Account testAcc = new Account(Name = 'Test Account');
        insert testAcc;

        Contact testCon = new Contact(
            FirstName = 'Test',
            LastName = 'User',
            AccountId = testAcc.Id,
            Email = 'testuser@example.com'
        );
        insert testCon;

        // ===== Step 1: Create SOQL stubs  =====
        Test.startTest();

        Test.createSoqlStub(ssot__SalesOrder__dlm.sObjectType, new SalesOrderSoqlStub(testCon.Id));
        Test.createSoqlStub(ssot__SalesOrderProduct__dlm.sObjectType, new SalesOrderProductSoqlStub());
        Test.createSoqlStub(ssot__Product__dlm.sObjectType, new ProductSoqlStub());

        // ===== Step 2: Call the method under test =====
        storageProductRecomendation.Response response = storageProductRecomendation.returnStorageProducts(testCon.Id);

        Test.stopTest();

        // ===== Step 3: Assertions =====
        System.assertNotEquals(null, response, 'Response should not be null');
        System.assert(response.messages.size() > 0, 'There should be at least one message');
        System.assert(response.products.size() > 0, 'There should be at least one recommended product');

        // Check the message content
        System.assert(response.messages[0].contains('Power Tools'), 'Message should reference past Power Tools purchase');

        // Check product details
        System.assertEquals('Storage Rack', response.products[0].ssot__Name__c, 'Product name should match stubbed data');
    }
    
        @IsTest
    public static void testInvocable_storageProducts() {
         Account testAcc = new Account(Name = 'Test Account');
        insert testAcc;

        Contact testCon = new Contact(
            FirstName = 'Test',
            LastName = 'User',
            AccountId = testAcc.Id,
            Email = 'testuser@example.com'
        );
        insert testCon;
        
        // Prepare Invocable Request
        storageProductInvocable.Request req = new storageProductInvocable.Request();
        req.requestType = 'STORAGE_PRODUCTS';
        req.contactId   = testCon.Id;
        
        List<storageProductInvocable.Request> requests = new List<storageProductInvocable.Request>{ req };
        
        Test.startTest();

        Test.createSoqlStub(ssot__SalesOrder__dlm.sObjectType,new SalesOrderSoqlStub(testCon.Id));
        Test.createSoqlStub(ssot__SalesOrderProduct__dlm.sObjectType,new SalesOrderProductSoqlStub());
        Test.createSoqlStub(ssot__Product__dlm.sObjectType,new ProductSoqlStub());
        List<storageOutput> outputs = storageProductInvocable.invoke(requests);

        Test.stopTest();
        System.assertEquals(1, outputs.size());
        storageOutput out = outputs[0];
         System.assertNotEquals(null, out.message);
          System.assert( out.message.contains('Power Tools'),'Customer Purchased  Power Tools');
         System.assertNotEquals(null, out.productsJson);
        System.assertNotEquals('[]', out.productsJson);
        List<Object> products =(List<Object>)JSON.deserializeUntyped(out.productsJson);
        System.assertEquals(1, products.size());
         Map<String, Object> product =(Map<String, Object>)products[0];
         System.assertEquals('P002', product.get('id'));
        System.assertEquals('Storage Rack', product.get('name'));
         System.assertEquals( 'http://example.com/product/2',product.get('displayUrl'));
        
    }

    // ===== SalesOrder Stub =====
    public class SalesOrderSoqlStub extends SoqlStubProvider {
        private Id contactId;
        public SalesOrderSoqlStub(Id conId) {
            this.contactId = conId;
        }
        public override List<sObject> handleSoqlQuery(sObjectType sot, String stubbedQuery, Map<String, Object> bindVars) {
            ssot__SalesOrder__dlm order = (ssot__SalesOrder__dlm)Test.createStubQueryRow(
                sot,
                new Map<String, Object>{
                    'ssot__Id__c' => 'SO001',
                    'ssot__BillToContactId__c' => contactId,
                    'ssot__OrderStartDate__c' => Date.today().addDays(-10)
                }
            );
            return new List<sObject>{ order };
        }
    }

    // ===== SalesOrderProduct Stub =====
    public class SalesOrderProductSoqlStub extends SoqlStubProvider {
        public override List<sObject> handleSoqlQuery(sObjectType sot, String stubbedQuery, Map<String, Object> bindVars) {
            ssot__SalesOrderProduct__dlm sop = (ssot__SalesOrderProduct__dlm)Test.createStubQueryRow(
                sot,
                new Map<String, Object>{
                    'ssot__Id__c' => 'SOP001',
                    'ssot__SalesOrderId__c' => 'SO001',
                    'ssot__ProductId__c' => 'P001'
                }
            );
            return new List<sObject>{ sop };
        }
    }

    // ===== Product Stub =====
    public class ProductSoqlStub extends SoqlStubProvider {
        public override List<sObject> handleSoqlQuery(sObjectType sot, String stubbedQuery, Map<String, Object> bindVars) {
            List<ssot__Product__dlm> products = new List<ssot__Product__dlm>();

            // Past purchased Power Tool
            products.add((ssot__Product__dlm)Test.createStubQueryRow(
                sot,
                new Map<String, Object>{
                    'ssot__Id__c' => 'P001',
                    'ssot__Name__c' => 'Cordless Drill',
                    'ssot__Description__c' => 'High performance drill',
                    'ssot__ProductFamily__c' => 'Power Tools'
                }
            ));

            // Recommended Storage Product
            products.add((ssot__Product__dlm)Test.createStubQueryRow(
                sot,
                new Map<String, Object>{
                    'ssot__Id__c' => 'P002',
                    'ssot__Name__c' => 'Storage Rack',
                    'ssot__Description__c' => 'Perfect for garages',
                    'ssot__ProductFamily__c' => 'Storage',
                    'Display_URL__c' => 'http://example.com/product/2'
                }
            ));

            return (List<sObject>)products;
        }
    }
}