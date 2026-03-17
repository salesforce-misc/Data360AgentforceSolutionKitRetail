public with sharing class CustomerPromotionEligibility {

    // ============================
    // Test Mock Support (SAFE)
    // ============================
    @TestVisible static List<ssot__SalesOrder__dlm> mockSalesOrders;
    @TestVisible static List<ssot__SalesOrderProduct__dlm> mockSOPs;
    @TestVisible static List<ssot__PromotionProduct__dlm> mockPromoProducts;
    @TestVisible static List<ssot__PromotionOffer__dlm> mockOffers;
    @TestVisible static List<ssot__Product__dlm> mockProducts;

    // ============================
    // DTO Classes
    // ============================
    public class PromoProductDTO {
        @AuraEnabled public Id productId;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public String displayUrl;
    }

    public class Output {
        @AuraEnabled public List<String> messages;
        @AuraEnabled public List<PromoProductDTO> products;

        public Output() {
            messages = new List<String>();
            products = new List<PromoProductDTO>();
        }
    }

    // Wrapper used by Flow
    public class PromoOutputADT {
        @InvocableVariable public String message;
        @InvocableVariable public String productsJson;
    }

    // ============================
    // Invocable Method
    // ============================
    @InvocableMethod(label='Get Eligible Promotional Products')
    public static List<PromoOutputADT> getPromoProductsForFlow(List<Id> contactIds) {

        List<PromoOutputADT> wrapper = new List<PromoOutputADT>();
        PromoOutputADT res = new PromoOutputADT();
        res.message = '';
        res.productsJson = '[]';

        if (contactIds == null || contactIds.isEmpty()) {
            wrapper.add(res);
            return wrapper;
        }

        Id inputId = contactIds[0];

        // Resolve Contact from ContactId OR AccountId
        Id conId;
        List<Contact> cList = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Id = :inputId OR AccountId = :inputId
            LIMIT 1
        ];

        if (!cList.isEmpty()) {
            conId = cList[0].Id;
        }

        if (conId == null) {
            wrapper.add(res);
            return wrapper;
        }

        List<Output> outputs = buildPromoOutputs(new List<Id>{ conId });

        if (!outputs.isEmpty()) {
            Output out = outputs[0];

            if (!out.messages.isEmpty()) {
                res.message = String.join(out.messages, '\n');
            }

            if (!out.products.isEmpty()) {
                res.productsJson = JSON.serialize(out.products);
            }
        }

        wrapper.add(res);
        return wrapper;
    }

    // ============================
    // Core Logic
    // ============================
    public static List<Output> buildPromoOutputs(List<Id> contactIds) {

        if (contactIds == null || contactIds.isEmpty()) {
            return new List<Output>();
        }

        // STEP 1 – Sales Orders
        List<ssot__SalesOrder__dlm> salesOrders;

        if (Test.isRunningTest() && mockSalesOrders != null) {
            salesOrders = mockSalesOrders;
        } else {
            salesOrders = [
                SELECT ssot__Id__c, ssot__BillToContactId__c
                FROM ssot__SalesOrder__dlm
                WHERE ssot__BillToContactId__c IN :contactIds
            ];
        }

        Set<Id> salesOrderIds = new Set<Id>();
        Map<Id, Id> soToContact = new Map<Id, Id>();

        for (ssot__SalesOrder__dlm so : salesOrders) {
            if (so.ssot__Id__c != null) {
                Id soId = (Id)so.ssot__Id__c;
                salesOrderIds.add(soId);
                soToContact.put(soId, (Id)so.ssot__BillToContactId__c);
            }
        }

        // STEP 1B – Ordered Products
        List<ssot__SalesOrderProduct__dlm> sops;

        if (Test.isRunningTest() && mockSOPs != null) {
            sops = mockSOPs;
        } else if (!salesOrderIds.isEmpty()) {
            sops = [
                SELECT ssot__SalesOrderId__c, ssot__ProductId__c
                FROM ssot__SalesOrderProduct__dlm
                WHERE ssot__SalesOrderId__c IN :salesOrderIds
            ];
        } else {
            sops = new List<ssot__SalesOrderProduct__dlm>();
        }

        Map<Id, Set<Id>> contactToOrderedProducts = new Map<Id, Set<Id>>();
        for (Id cId : contactIds) {
            contactToOrderedProducts.put(cId, new Set<Id>());
        }

        for (ssot__SalesOrderProduct__dlm sop : sops) {
            Id soId = (Id)sop.ssot__SalesOrderId__c;
            Id prodId = (Id)sop.ssot__ProductId__c;

            Id billTo = soToContact.get(soId);
            if (billTo != null) {
                contactToOrderedProducts.get(billTo).add(prodId);
            }
        }

        // STEP 2 – Promotion Products
        List<ssot__PromotionProduct__dlm> promoProducts;

        if (Test.isRunningTest() && mockPromoProducts != null) {
            promoProducts = mockPromoProducts;
        } else {
            promoProducts = [
                SELECT ssot__ProductId__c, ssot__PromotionId__c
                FROM ssot__PromotionProduct__dlm
            ];
        }

        Map<Id, Set<Id>> productToPromoIds = new Map<Id, Set<Id>>();
        Set<Id> promoIds = new Set<Id>();
        Set<Id> promoProductIds = new Set<Id>();

        for (ssot__PromotionProduct__dlm pp : promoProducts) {
            Id productId = (Id)pp.ssot__ProductId__c;
            Id promoId = (Id)pp.ssot__PromotionId__c;

            promoProductIds.add(productId);
            promoIds.add(promoId);

            if (!productToPromoIds.containsKey(productId)) {
                productToPromoIds.put(productId, new Set<Id>());
            }
            productToPromoIds.get(productId).add(promoId);
        }

        // STEP 3 – Promotion Offers
        List<ssot__PromotionOffer__dlm> offers;

        if (Test.isRunningTest() && mockOffers != null) {
            offers = mockOffers;
        } else if (!promoIds.isEmpty()) {
            offers = [
                SELECT ssot__Id__c, ssot__Description__c
                FROM ssot__PromotionOffer__dlm
                WHERE ssot__Id__c IN :promoIds
            ];
        } else {
            offers = new List<ssot__PromotionOffer__dlm>();
        }

        Map<Id, String> promoIdToDesc = new Map<Id, String>();
        for (ssot__PromotionOffer__dlm o : offers) {
            promoIdToDesc.put(
                (Id)o.ssot__Id__c,
                String.isBlank(o.ssot__Description__c)
                    ? 'No promotion description available'
                    : o.ssot__Description__c
            );
        }

        // STEP 4 – Products
        List<ssot__Product__dlm> products;

        if (Test.isRunningTest() && mockProducts != null) {
            products = mockProducts;
        } else if (!promoProductIds.isEmpty()) {
            products = [
                SELECT ssot__Id__c, ssot__Name__c, ssot__Description__c, Display_URL__c
                FROM ssot__Product__dlm
                WHERE ssot__Id__c IN :promoProductIds
            ];
        } else {
            products = new List<ssot__Product__dlm>();
        }

        // STEP 5 – Build Output
        List<Output> results = new List<Output>();

        for (Id cId : contactIds) {

            Output out = new Output();
            Set<Id> alreadyOrdered = contactToOrderedProducts.get(cId);

            for (ssot__Product__dlm prod : products) {

                Id prodId = (Id)prod.ssot__Id__c;

                if (alreadyOrdered.contains(prodId)) continue;

                PromoProductDTO dto = new PromoProductDTO();
                dto.productId = prodId;
                dto.name = prod.ssot__Name__c;
                dto.description = prod.ssot__Description__c;
                dto.displayUrl = prod.Display_URL__c;

                out.products.add(dto);

                Set<Id> promoSet = productToPromoIds.get(prodId);
                if (promoSet != null) {
                    for (Id pid : promoSet) {
                        String promoDesc = promoIdToDesc.get(pid); // FIXED
                        out.messages.add(dto.name + ' has discount of: ' + promoDesc);
                    }
                }
            }

            results.add(out);
        }

        return results;
    }
}