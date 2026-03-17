@IsTest
public class ProductCarouselController_Test {

    /* =====================================================
       TEST: RECENT PURCHASED PRODUCTS
       ===================================================== */
    @IsTest
    static void testRecentPurchasedProducts() {

        SoqlStubProvider stub = new RecentPurchaseStub();

        Test.createSoqlStub(ssot__Account__dlm.SObjectType, stub);
        Test.createSoqlStub(ssot__SalesOrder__dlm.SObjectType, stub);
        Test.createSoqlStub(ssot__SalesOrderProduct__dlm.SObjectType, stub);
        Test.createSoqlStub(ssot__Product__dlm.SObjectType, stub);

        Test.startTest();
        List<ProductCarouselController.ProductDTO> results =
            ProductCarouselController.getRecentPurchasedProducts(
                '001000000000001AAA'
            );
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());
    }

    /* =====================================================
       TEST: DISCOUNTED PRODUCTS
       ===================================================== */
    @IsTest
    static void testDiscountedProducts() {

        SoqlStubProvider stub = new PromotionStub();

        Test.createSoqlStub(ssot__PromotionOffer__dlm.SObjectType, stub);
        Test.createSoqlStub(ssot__PromotionProduct__dlm.SObjectType, stub);
        Test.createSoqlStub(ssot__Product__dlm.SObjectType, stub);

        Test.startTest();
        List<ProductCarouselController.ProductDTO> results =
            ProductCarouselController.getDiscountedProductsFromPromotions();
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());
    }

    /* =====================================================
       TEST: RANDOM PRODUCTS (GUEST PATH)
       ===================================================== */
    @IsTest
    static void testRandomProducts_guestPath() {

        SoqlStubProvider stub = new RandomProductStub();
        Test.createSoqlStub(ssot__Product__dlm.SObjectType, stub);

        Test.startTest();
        List<ProductCarouselController.ProductDTO> results =
            ProductCarouselController.getProducts('any');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assertEquals(1, results.size());
    }

    /* =====================================================
       STUB: RECENT PURCHASE FLOW
       ===================================================== */
    private class RecentPurchaseStub extends SoqlStubProvider {

        private final Id ACCOUNT_ID = '001000000000001AAA';
        private final Id CONTACT_ID = '003000000000001AAA';
        private final Id ORDER_ID   = '801000000000001AAA';
        private final Id PRODUCT_ID = '01t000000000001AAA';

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
                            'ssot__Id__c' => ACCOUNT_ID,
                            'ssot__AccountType__c' => 'Person',
                            'Contact_Id__c' => CONTACT_ID
                        }
                    )
                };
            }

            if (sot == ssot__SalesOrder__dlm.SObjectType) {
                return new List<SObject>{
                    Test.createStubQueryRow(
                        sot,
                        new Map<String, Object>{
                            'ssot__Id__c' => ORDER_ID,
                            'ssot__BillToAccountId__c' => ACCOUNT_ID,
                            'ssot__BillToContactId__c' => CONTACT_ID,
                            'ssot__SoldToCustomerId__c' => CONTACT_ID,
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
                            'ssot__SalesOrderId__c' => ORDER_ID,
                            'ssot__ProductId__c' => PRODUCT_ID,
                            'ssot__TotalLineAmount__c' => 100,
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
                            'ssot__Id__c' => PRODUCT_ID,
                            'ssot__Name__c' => 'Purchased Product',
                            'Display_URL__c' => 'https://example.com/p.png'
                        }
                    )
                };
            }

            return new List<SObject>();
        }
    }

    /* =====================================================
       STUB: PROMOTION FLOW
       ===================================================== */
    private class PromotionStub extends SoqlStubProvider {

        private final Id PROMO_ID   = 'a0P000000000001AAA';
        private final Id PRODUCT_ID = '01t000000000002AAA';

        public override List<SObject> handleSoqlQuery(
            SObjectType sot,
            String query,
            Map<String, Object> bindVars
        ) {

            if (sot == ssot__PromotionOffer__dlm.SObjectType) {
                return new List<SObject>{
                    Test.createStubQueryRow(
                        sot,
                        new Map<String, Object>{
                            'ssot__Id__c' => PROMO_ID,
                            'Discount__c' => 20,
                            'ssot__PromotionId__c' => PROMO_ID
                        }
                    )
                };
            }

            if (sot == ssot__PromotionProduct__dlm.SObjectType) {
                return new List<SObject>{
                    Test.createStubQueryRow(
                        sot,
                        new Map<String, Object>{
                            'ssot__PromotionId__c' => PROMO_ID,
                            'ssot__ProductId__c' => PRODUCT_ID
                        }
                    )
                };
            }

            if (sot == ssot__Product__dlm.SObjectType) {
                return new List<SObject>{
                    Test.createStubQueryRow(
                        sot,
                        new Map<String, Object>{
                            'ssot__Id__c' => PRODUCT_ID,
                            'ssot__Name__c' => 'Discounted Product',
                            'Display_URL__c' => 'https://example.com/d.png'
                        }
                    )
                };
            }

            return new List<SObject>();
        }
    }

    /* =====================================================
       STUB: RANDOM PRODUCTS
       ===================================================== */
    private class RandomProductStub extends SoqlStubProvider {

        private final Id PRODUCT_ID = '01t000000000009AAA';

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
                            'ssot__Id__c' => PRODUCT_ID,
                            'ssot__Name__c' => 'Random Product',
                            'Display_URL__c' => 'https://example.com/r.png',
                            'ssot__IsActive__c' => 'true',
                            'ssot__ProductSKU__c' => 'SKU-001'
                        }
                    )
                };
            }

            return new List<SObject>();
        }
    }
}