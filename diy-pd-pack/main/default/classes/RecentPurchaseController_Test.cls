@IsTest
public class RecentPurchaseController_Test {

    /* =====================================================
       TEST 1: RecentPurchaseController (WORKING)
       ===================================================== */
    @IsTest
    static void testGetRecentPurchasedProducts() {

        SoqlStubProvider stub = new RecentPurchaseSoqlStub();

        Test.createSoqlStub(ssot__Account__dlm.SObjectType, stub);
        Test.createSoqlStub(ssot__SalesOrder__dlm.SObjectType, stub);
        Test.createSoqlStub(ssot__SalesOrderProduct__dlm.SObjectType, stub);
        Test.createSoqlStub(ssot__Product__dlm.SObjectType, stub);

        Test.startTest();
        List<RecentPurchaseController.ProductDTO> results =
            RecentPurchaseController.getRecentPurchasedProducts('001000000000001');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].productName);
        System.assertNotEquals(null, results[0].imageUrl);
    }

    /* =====================================================
       TEST 2: ProductCarouselController (SAFE PATH ONLY)
       ===================================================== */
    @IsTest
    static void testProductCarousel_randomProducts() {

        SoqlStubProvider stub = new ProductCarouselSoqlStub();
        Test.createSoqlStub(ssot__Product__dlm.SObjectType, stub);

        Test.startTest();
        List<ProductCarouselController.ProductDTO> results =
            ProductCarouselController.getProducts('trending');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() > 0);

        ProductCarouselController.ProductDTO dto = results[0];
        System.assertNotEquals(null, dto.productId);
        System.assertNotEquals(null, dto.name);
        System.assertNotEquals(null, dto.imageUrl);
        System.assertNotEquals(null, dto.url);
        System.assertNotEquals(null, dto.reviews);
    }

    /* =====================================================
       SOQL STUB: Recent Purchases
       ===================================================== */
    private class RecentPurchaseSoqlStub extends SoqlStubProvider {

        public override List<SObject> handleSoqlQuery(
            SObjectType sot,
            String query,
            Map<String, Object> bindVars
        ) {

            if (sot == ssot__Account__dlm.SObjectType) {
                return new List<SObject>{
                    Test.createStubQueryRow(
                        sot,
                        new Map<String, Object>{
                            'ssot__Id__c' => '001000000000001',
                            'ssot__AccountType__c' => 'Person',
                            'Contact_Id__c' => '003000000000001'
                        }
                    )
                };
            }

            if (sot == ssot__SalesOrder__dlm.SObjectType) {
                return new List<SObject>{
                    Test.createStubQueryRow(
                        sot,
                        new Map<String, Object>{
                            'ssot__Id__c' => '801000000000001',
                            'ssot__BillToAccountId__c' => '001000000000001',
                            'ssot__BillToContactId__c' => '003000000000001',
                            'ssot__SoldToCustomerId__c' => '003000000000001',
                            'ssot__OrderStartDate__c' => System.now()
                        }
                    )
                };
            }

            if (sot == ssot__SalesOrderProduct__dlm.SObjectType) {
                return new List<SObject>{
                    Test.createStubQueryRow(
                        sot,
                        new Map<String, Object>{
                            'ssot__SalesOrderId__c' => '801000000000001',
                            'ssot__ProductId__c' => '01t000000000001',
                            'ssot__OrderedQuantity__c' => 1,
                            'ssot__UnitPriceAmount__c' => 100
                        }
                    )
                };
            }

            if (sot == ssot__Product__dlm.SObjectType) {
                return new List<SObject>{
                    Test.createStubQueryRow(
                        sot,
                        new Map<String, Object>{
                            'ssot__Id__c' => '01t000000000001',
                            'ssot__Name__c' => 'Purchased Product',
                            'Display_URL__c' => 'https://cdn.example.com/purchased.png',
                            'ssot__Description__c' => 'Test',
                            'ssot__ProductFamily__c' => 'TestFamily'
                        }
                    )
                };
            }

            return new List<SObject>();
        }
    }

    /* =====================================================
       SOQL STUB: Product Carousel (Trending / Random)
       ===================================================== */
    private class ProductCarouselSoqlStub extends SoqlStubProvider {

        public override List<SObject> handleSoqlQuery(
            SObjectType sot,
            String query,
            Map<String, Object> bindVars
        ) {

            if (sot == ssot__Product__dlm.SObjectType) {
                return new List<SObject>{
                    Test.createStubQueryRow(
                        sot,
                        new Map<String, Object>{
                            'ssot__Id__c' => '01t000000000101',
                            'ssot__Name__c' => 'Trending Product 1',
                            'Display_URL__c' => 'https://cdn.example.com/t1.png',
                            'ssot__IsActive__c' => 'true',
                            'ssot__ProductSKU__c' => 'SKU-001'
                        }
                    ),
                    Test.createStubQueryRow(
                        sot,
                        new Map<String, Object>{
                            'ssot__Id__c' => '01t000000000102',
                            'ssot__Name__c' => 'Trending Product 2',
                            'Display_URL__c' => 'https://cdn.example.com/t2.png',
                            'ssot__IsActive__c' => 'true',
                            'ssot__ProductSKU__c' => 'SKU-002'
                        }
                    )
                };
            }

            return new List<SObject>();
        }
    }
    
    @isTest
    static void testGetAccountDetails() {
        Account testAccount = new Account(
            Name = 'Test Account',
            ShippingCity = 'Test City',
            ShippingState = 'Test State',
            ShippingPostalCode = '123456',
            ShippingStreet = '123 Test Street'
        );
        insert testAccount;

        Contact testContact = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            AccountId = testAccount.Id,
            Lifetime_Value__c = 1000,
            Average_Purchase_Value__c = 0.75,
            Average_Order_Value__c = 250
        );
        insert testContact;

        Test.startTest();
        Account result = GetAccounts.getAccountDetails(testAccount.Id);
        Test.stopTest();
      
    }
}