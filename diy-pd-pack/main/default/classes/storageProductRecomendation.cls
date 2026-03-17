public without sharing class storageProductRecomendation {

    /* ===== Response class for product recommendations ===== */
    public class Response {
        @AuraEnabled @InvocableVariable
        public List<String> messages = new List<String>();

        @AuraEnabled @InvocableVariable
        public List<ssot__Product__dlm> products = new List<ssot__Product__dlm>();
    }

    /* ===============================
       Create Recent Purchased Order Details
       =============================== */
    public static Set<String> getRecentProductIds(Id contactId) {

        Set<String> pastProductSet = new Set<String>();
        Set<String> orderIdSet = new Set<String>();

        if (contactId == null) return pastProductSet;

        List<ssot__SalesOrder__dlm> orders = [
            SELECT ssot__Id__c, ssot__BillToContactId__c, ssot__OrderStartDate__c
            FROM ssot__SalesOrder__dlm
            WHERE ssot__BillToContactId__c = :contactId
              AND ssot__OrderStartDate__c >= LAST_N_DAYS:90
        ];

        System.debug('orders:' + orders);
        if (orders.isEmpty()) return pastProductSet;

        for (ssot__SalesOrder__dlm ord : orders) {
            if (ord.ssot__Id__c != null) {
                orderIdSet.add(ord.ssot__Id__c);
            }
        }

        if (orderIdSet.isEmpty()) return pastProductSet;

        List<ssot__SalesOrderProduct__dlm> orderProductList = [
            SELECT ssot__Id__c, ssot__SalesOrderId__c, ssot__ProductId__c
            FROM ssot__SalesOrderProduct__dlm
            WHERE ssot__SalesOrderId__c IN :orderIdSet
        ];

        System.debug('orderProductList:' + orderProductList);

        for (ssot__SalesOrderProduct__dlm oi : orderProductList) {
            if (oi.ssot__ProductId__c != null) {
                pastProductSet.add(oi.ssot__ProductId__c);
            }
        }

        System.debug('pastProductSet:' + pastProductSet);
        return pastProductSet;
    }

    /* ===============================
       Storage Product Recommendations
       =============================== */
    public static Response returnStorageProducts(Id contactId) {

        Response result = new Response();
        if (contactId == null) return result;

        Id conId;
        List<Contact> cList = [
            SELECT Id, Name, AccountId
            FROM Contact
            WHERE Id = :contactId OR AccountId = :contactId
            LIMIT 1
        ];

        if (!cList.isEmpty()) {
            conId = cList[0].Id;
        }

        System.debug('conId:' + conId);

        if (conId == null) return result;

        Set<String> pastFamilySet = new Set<String>();
        List<ssot__Product__dlm> prodList = new List<ssot__Product__dlm>();

        Set<String> pastProductIds = getRecentProductIds(conId);
        if (pastProductIds.isEmpty()) return result;

       
        List<ssot__Product__dlm> productList = [
            SELECT ssot__Id__c,
                   ssot__Name__c,
                   ssot__Description__c,
                   ssot__ProductFamily__c,
                   Display_URL__c
            FROM ssot__Product__dlm
            WHERE ssot__ProductFamily__c IN ('Power Tools', 'Storage')
        ];

        System.debug('productList:' + productList);

        for (ssot__Product__dlm prod : productList) {

            String familyName = prod.ssot__ProductFamily__c;

            if (pastProductIds.contains(prod.ssot__Id__c) && familyName != null) {
                if (familyName == 'Power Tools') {
                    pastFamilySet.add(familyName);
                }
            }

            //  Recommend storage products related to garages
            if (familyName == 'Storage') {
                if (prod.ssot__Description__c != null &&
                    prod.ssot__Description__c.toLowerCase().contains('garages')) {
                    prodList.add(prod);
                }
            }
        }

        System.debug('pastFamilySet:' + pastFamilySet);

        if (!pastFamilySet.isEmpty()) {
            result.messages.add(
                'I noticed you’ve picked up several ' +
                String.join(new List<String>(pastFamilySet), ', ') +
                ' recently, but it seems like you don\'t have garage storage yet. ' +
                'Plus, there\'s a 15% coupon available!:'
            );
        }

        if (!prodList.isEmpty()) {
            result.products.addAll(prodList);
        }

        System.debug('result:' + result);
        return result;
    }
}