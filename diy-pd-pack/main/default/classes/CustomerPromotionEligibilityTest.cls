@IsTest
private class CustomerPromotionEligibilityTest {

    // =====================================================
    // Helper Methods
    // =====================================================

    private static Contact createContact(Boolean withAccount) {
        Account acc;
        if (withAccount) {
            acc = new Account(Name = 'Test Account');
            insert acc;
        }

        Contact con = new Contact(
            LastName = 'Test Contact',
            AccountId = withAccount ? acc.Id : null
        );
        insert con;
        return con;
    }

    // Create valid 18-char fake Ids
    private static String fakeId(String prefix) {
        return prefix + '000000000000AAA';
    }

    private static ssot__SalesOrder__dlm createSalesOrder(String soId, Id contactId) {
        return (ssot__SalesOrder__dlm) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'ssot__Id__c' => soId,
                'ssot__BillToContactId__c' => contactId
            }),
            ssot__SalesOrder__dlm.class
        );
    }

    private static ssot__SalesOrderProduct__dlm createSOP(String soId, String productId) {
        return (ssot__SalesOrderProduct__dlm) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'ssot__SalesOrderId__c' => soId,
                'ssot__ProductId__c' => productId
            }),
            ssot__SalesOrderProduct__dlm.class
        );
    }

    private static ssot__PromotionProduct__dlm createPromoProduct(String productId, String promoId) {
        return (ssot__PromotionProduct__dlm) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'ssot__ProductId__c' => productId,
                'ssot__PromotionId__c' => promoId
            }),
            ssot__PromotionProduct__dlm.class
        );
    }

    private static ssot__PromotionOffer__dlm createOffer(String promoId) {
        return (ssot__PromotionOffer__dlm) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'ssot__Id__c' => promoId,
                'ssot__Description__c' => '10% Discount'
            }),
            ssot__PromotionOffer__dlm.class
        );
    }

    private static ssot__Product__dlm createProduct(String productId) {
        return (ssot__Product__dlm) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'ssot__Id__c' => productId,
                'ssot__Name__c' => 'Test Product',
                'ssot__Description__c' => 'Sample',
                'Display_URL__c' => 'http://test.com'
            }),
            ssot__Product__dlm.class
        );
    }

    private static void resetMocks() {
        CustomerPromotionEligibility.mockSalesOrders = null;
        CustomerPromotionEligibility.mockSOPs = null;
        CustomerPromotionEligibility.mockPromoProducts = null;
        CustomerPromotionEligibility.mockOffers = null;
        CustomerPromotionEligibility.mockProducts = null;
    }

    // =====================================================
    // 1. Full Flow (Main Coverage)
    // =====================================================
    @IsTest
    static void testFullFlow() {

        Contact con = createContact(true);

        String soId = fakeId('a01');
        String orderedProductId = fakeId('a02');
        String promoProductId = fakeId('a03');
        String promoId = fakeId('a04');

        // Ordered product should be excluded
        CustomerPromotionEligibility.mockSalesOrders =
            new List<ssot__SalesOrder__dlm>{
                createSalesOrder(soId, con.Id)
            };

        CustomerPromotionEligibility.mockSOPs =
            new List<ssot__SalesOrderProduct__dlm>{
                createSOP(soId, orderedProductId)
            };

        // Promotion product (different from ordered)
        CustomerPromotionEligibility.mockPromoProducts =
            new List<ssot__PromotionProduct__dlm>{
                createPromoProduct(promoProductId, promoId)
            };

        CustomerPromotionEligibility.mockOffers =
            new List<ssot__PromotionOffer__dlm>{
                createOffer(promoId)
            };

        CustomerPromotionEligibility.mockProducts =
            new List<ssot__Product__dlm>{
                createProduct(promoProductId)
            };

        Test.startTest();
        List<CustomerPromotionEligibility.PromoOutputADT> res =
            CustomerPromotionEligibility.getPromoProductsForFlow(
                new List<Id>{ con.Id }
            );
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assert(res[0].productsJson.contains('Test Product'));
        System.assert(res[0].message.contains('discount'));

        resetMocks();
    }

    // =====================================================
    // 2. Null Input
    // =====================================================
    @IsTest
    static void testNullInput() {

        List<CustomerPromotionEligibility.PromoOutputADT> res =
            CustomerPromotionEligibility.getPromoProductsForFlow(null);

        System.assertEquals(1, res.size());
        System.assertEquals('', res[0].message);
    }

    // =====================================================
    // 3. Empty Input
    // =====================================================
    @IsTest
    static void testEmptyInput() {

        List<CustomerPromotionEligibility.PromoOutputADT> res =
            CustomerPromotionEligibility.getPromoProductsForFlow(new List<Id>());

        System.assertEquals(1, res.size());
    }

    // =====================================================
    // 4. Invalid Id (no contact found)
    // =====================================================
    @IsTest
    static void testInvalidId() {

        List<CustomerPromotionEligibility.PromoOutputADT> res =
            CustomerPromotionEligibility.getPromoProductsForFlow(
                new List<Id>{ UserInfo.getUserId() }
            );

        System.assertEquals(1, res.size());
    }

    // =====================================================
    // 5. AccountId Path (Employee Agent scenario)
    // =====================================================
    @IsTest
    static void testAccountIdInput() {

        Contact con = createContact(true);

        List<CustomerPromotionEligibility.PromoOutputADT> res =
            CustomerPromotionEligibility.getPromoProductsForFlow(
                new List<Id>{ con.AccountId }
            );

        System.assertEquals(1, res.size());
    }
}