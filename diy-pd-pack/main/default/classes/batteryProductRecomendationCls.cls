public without sharing class batteryProductRecomendationCls {

    // ---- Input wrapper ----
    public class Request {
        @AuraEnabled @InvocableVariable(required=true)
        public String requestType;   // Expecting BATTERY_PRODUCTS

        @AuraEnabled @InvocableVariable
        public Id contactId;
    }

    //  Create Recent Purchased Order Details (last 90 days)
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

        if (orders.isEmpty()) return pastProductSet;

        for (ssot__SalesOrder__dlm ord : orders) {
            if (ord.ssot__Id__c != null) {
                orderIdSet.add(ord.ssot__Id__c);
            }
        }
		system.debug('ORDER ID SET'+orderIdSet);
        if (orderIdSet.isEmpty()) return pastProductSet;
		
        List<ssot__SalesOrderProduct__dlm> orderProductList = [
            SELECT ssot__ProductId__c
            FROM ssot__SalesOrderProduct__dlm
            WHERE ssot__SalesOrderId__c IN :orderIdSet
              
        ];

        for (ssot__SalesOrderProduct__dlm oi : orderProductList) {
            pastProductSet.add(oi.ssot__ProductId__c);
        }

        return pastProductSet;
    }

    
    //Invocable: Battery Product Details -> returns storageOutput
       
    @InvocableMethod(
        label='Battery Product Details'
        description='Returns message + productsJson for BATTERY_PRODUCTS. Suitable for Flow Apex-defined variables.'
    )
    public static List<storageOutput> returnBatteryRecomendation(List<Request> reqList) {

        List<storageOutput> outputs = new List<storageOutput>();
        if (reqList == null || reqList.isEmpty()) return outputs;

        // Bulkify: one output per request
        for (Request req : reqList) {

            storageOutput out = new storageOutput();
            out.message = '';
            out.productsJson = '[]';

            if (req == null || req.contactId == null) {
                outputs.add(out);
                continue;
            }

           if (req.requestType != null && req.requestType != 'BATTERY_PRODUCTS') {
                outputs.add(out);
                continue;
            }

        	    Contact contactRec = [
                SELECT Id, AccountId
                FROM Contact
                WHERE Id = :req.contactId OR AccountId = :req.contactId
                LIMIT 1
            ];
            Id conId = contactRec.Id;

            Set<String> pastProductIds = getRecentProductIds(conId);
            if (pastProductIds.isEmpty()) {
                out.message = 'No recent purchases found in the last 90 days.';
                outputs.add(out);
                continue;
            }

            // Pull products (you can filter if you want, but keeping close to your logic)
            List<ssot__Product__dlm> prodList = [
                SELECT ssot__Id__c, ssot__Name__c, ssot__ProductFamily__c,
                       ssot__Description__c, Display_URL__c
                FROM ssot__Product__dlm
            ];

            Set<String> pastBatteryPurchaseSet = new Set<String>();
            List<ssot__Product__dlm> productToolsList = new List<ssot__Product__dlm>();

            for (ssot__Product__dlm prod : prodList) {

                // Identify battery purchases from recent products
                if (pastProductIds.contains(prod.ssot__Id__c)) {
                    if (prod.ssot__ProductFamily__c == 'Batteries' && prod.ssot__Name__c != null) {
                        pastBatteryPurchaseSet.add(prod.ssot__Name__c);
                    }
                }

                // Recommend tools: max 4 + specifically "Brushless Drill Driver"
                if (prod.ssot__ProductFamily__c == 'Power Tools' || prod.ssot__ProductFamily__c == 'Hand Tools') {

                    // Ensure Brushless Drill Driver is included
                    if (prod.ssot__Name__c == 'Brushless Drill Driver') {
                        productToolsList.add(prod);
                        continue;
                    }

                    if (productToolsList.size() < 4) {
                        productToolsList.add(prod);
                    }
                }
            }

            // Build message
            if (!pastBatteryPurchaseSet.isEmpty()) {
                out.message =
                    'Since you are already invested in ' +
                    String.join(new List<String>(pastBatteryPurchaseSet), ', ') +
                    ' battery product.';
            } else {
                out.message = 'You have not purchased any battery product.';
            }

            // Build productsJson (JSON array)
            if (!productToolsList.isEmpty()) {
                List<Map<String, Object>> dtoList = new List<Map<String, Object>>();

                for (ssot__Product__dlm p : productToolsList) {
                    dtoList.add(new Map<String, Object>{
                        'name'        => p.ssot__Name__c,
                        'description' => p.ssot__Description__c,
                        'displayUrl'  => p.Display_URL__c
                    });
                }

                out.productsJson = JSON.serialize(dtoList);
            }

            outputs.add(out);
        }

        return outputs;
    }
}