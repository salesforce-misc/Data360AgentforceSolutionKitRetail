public with sharing class HVACWarrantyService {

    // ===== TEST MOCK SUPPORT (No impact in production) =====
    @TestVisible private static Set<String> mockProductIds;
    @TestVisible private static List<ssot__SalesOrder__dlm> mockOrders;
    @TestVisible private static Set<String> mockOrdersWithHvac;

    public class HVACRequest {
        @InvocableVariable(required=true)
        public Id contactId; // Can be ContactId OR AccountId (Employee Agent)
    }

    public class HVACMessageResult {
        @InvocableVariable
        public String message;
    }

    @InvocableMethod(
        label='Get HVAC Warranty Message'
        description='Returns only the HVAC warranty/tune-up message based on the most recent eligible HVAC order.'
    )
    public static List<HVACMessageResult> getHVACMessage(List<HVACRequest> requests) {

        List<HVACMessageResult> outputs = new List<HVACMessageResult>();
        if (requests == null || requests.isEmpty()) return outputs;

        Date threeYearsAgo = Date.today().addYears(-3);

        for (HVACRequest req : requests) {

            HVACMessageResult resp = new HVACMessageResult();
            resp.message = '';

            if (req == null || req.contactId == null) {
                resp.message = buildHVACMessageWithOrderEffectiveDate(null);
                outputs.add(resp);
                continue;
            }

            // Resolve ContactId from Contact or Account
            Id conId;
            List<Contact> cList = [
                SELECT Id, AccountId
                FROM Contact
                WHERE Id = :req.contactId OR AccountId = :req.contactId
                LIMIT 1
            ];

            if (!cList.isEmpty()) {
                conId = cList[0].Id;
            }

            if (conId == null) {
                resp.message = buildHVACMessageWithOrderEffectiveDate(null);
                outputs.add(resp);
                continue;
            }

            // ====================================================
            // 1) HVAC Product IDs (DMO)
            // ====================================================
            Set<String> hvacProductIds = new Set<String>();

            if (Test.isRunningTest() && mockProductIds != null) {
                hvacProductIds = mockProductIds;
            } else {
                for (ssot__Product__dlm p : [
                    SELECT ssot__Id__c
                    FROM ssot__Product__dlm
                    WHERE ssot__Name__c LIKE 'HVAC Installation%'
                       OR ssot__Name__c LIKE 'HVAC Maintenance%'
                ]) {
                    if (p.ssot__Id__c != null) {
                        hvacProductIds.add(p.ssot__Id__c);
                    }
                }
            }

            if (hvacProductIds.isEmpty()) {
                resp.message = buildHVACMessageWithOrderEffectiveDate(null);
                outputs.add(resp);
                continue;
            }

            // ====================================================
            // 2) Orders older than 3 years (DMO)
            // ====================================================
            List<ssot__SalesOrder__dlm> orders;

            if (Test.isRunningTest() && mockOrders != null) {
                orders = mockOrders;
            } else {
                orders = [
                    SELECT ssot__Id__c, ssot__OrderStartDate__c
                    FROM ssot__SalesOrder__dlm
                    WHERE ssot__BillToContactId__c = :conId
                      AND ssot__OrderStartDate__c < :threeYearsAgo
                    ORDER BY ssot__OrderStartDate__c ASC
                ];
            }

            if (orders.isEmpty()) {
                resp.message = buildHVACMessageWithOrderEffectiveDate(null);
                outputs.add(resp);
                continue;
            }

            // 3) Collect Order IDs
            Set<String> orderIds = new Set<String>();
            for (ssot__SalesOrder__dlm so : orders) {
                if (so.ssot__Id__c != null) {
                    orderIds.add(so.ssot__Id__c);
                }
            }

            if (orderIds.isEmpty()) {
                resp.message = buildHVACMessageWithOrderEffectiveDate(null);
                outputs.add(resp);
                continue;
            }

            // ====================================================
            // 4) Orders with HVAC items (DMO)
            // ====================================================
            Set<String> ordersWithHvacItems = new Set<String>();

            if (Test.isRunningTest() && mockOrdersWithHvac != null) {
                ordersWithHvacItems = mockOrdersWithHvac;
            } else {
                for (ssot__SalesOrderProduct__dlm oi : [
                    SELECT ssot__SalesOrderId__c
                    FROM ssot__SalesOrderProduct__dlm
                    WHERE ssot__SalesOrderId__c IN :orderIds
                      AND ssot__ProductId__c IN :hvacProductIds
                ]) {
                    if (oi.ssot__SalesOrderId__c != null) {
                        ordersWithHvacItems.add(oi.ssot__SalesOrderId__c);
                    }
                }
            }

            // ====================================================
            // 5) Find latest eligible order date
            // ====================================================
            Date latest = null;

            for (ssot__SalesOrder__dlm o : orders) {
                if (o == null || o.ssot__Id__c == null) continue;
                if (!ordersWithHvacItems.contains(o.ssot__Id__c)) continue;

                Date eff = (o.ssot__OrderStartDate__c == null)
                    ? null
                    : o.ssot__OrderStartDate__c.date();

                if (eff == null) continue;

                if (latest == null || eff > latest) {
                    latest = eff;
                }
            }

            resp.message = buildHVACMessageWithOrderEffectiveDate(latest);
            outputs.add(resp);
        }

        return outputs;
    }

    // ====================================================
    // Helper Methods (unchanged)
    // ====================================================

    private static String getOrdinalSuffix(Integer day) {
        if (day == null) return '';
        Integer mod100 = Math.mod(day, 100);
        if (mod100 >= 11 && mod100 <= 13) return 'th';
        Integer mod10 = Math.mod(day, 10);
        if (mod10 == 1) return 'st';
        if (mod10 == 2) return 'nd';
        if (mod10 == 3) return 'rd';
        return 'th';
    }

    private static String formatDateWithOrdinal(Date d) {
        if (d == null) return 'TBD';
        Integer day = d.day();
        String suffix = getOrdinalSuffix(day);
        DateTime dt = DateTime.newInstance(d, Time.newInstance(0, 0, 0, 0));
        String base = dt.format('d MMM yyyy');
        return String.valueOf(day) + suffix + base.substring(String.valueOf(day).length());
    }

    private static String buildHVACMessageWithOrderEffectiveDate(Date orderEffectiveDate) {
        String formatted = formatDateWithOrdinal(orderEffectiveDate);
        return 'Your HVAC system is about due for a tune-up.\n' +
               'Last maintenance date was: ' + formatted + '\n' +
               'I can schedule a certified inspection this week. Would you also like a quote on a warranty extension?';
    }
}