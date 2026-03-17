public with sharing class CurrentSalesRecommendation {

    private static final Integer LOOKBACK_DAYS = 90;
    private static final Integer MAX_RESULTS  = 5;
    private static final Integer TOP_FAMILIES = 4;

    // =====================================================
    // Test Mock Support (SAFE – No impact to production)
    // =====================================================
    @TestVisible static List<ssot__SalesOrder__dlm> mockRecentOrders;
    @TestVisible static List<ssot__SalesOrderProduct__dlm> mockOrderProducts;
    @TestVisible static List<ssot__Product__dlm> mockPurchasedProducts;
    @TestVisible static List<ssot__Product__dlm> mockCandidateProducts;

    public class RecommendationRequest {
        @InvocableVariable(required=true)
        public Id contactId;
    }

    public class RecProductDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public String displayUrl;
        @AuraEnabled public String productFamily;
        @AuraEnabled public String sku;
    }

    public class Output {
        @AuraEnabled public List<String> messages;
        @AuraEnabled public List<RecProductDTO> products;

        public Output() {
            messages = new List<String>();
            products = new List<RecProductDTO>();
        }
    }

    @InvocableMethod(
        label='Current Sales Recommendations'
        description='Finds top purchased product families and recommends other products.'
    )
    public static List<PromptOutputADT> recommend(List<RecommendationRequest> requests) {

        List<PromptOutputADT> wrapper = new List<PromptOutputADT>();
        if (requests == null || requests.isEmpty()) return wrapper;

        for (RecommendationRequest req : requests) {

            PromptOutputADT res = new PromptOutputADT();
            res.message = '';
            res.productsJson = '[]';

            if (req == null || req.contactId == null) {
                wrapper.add(res);
                continue;
            }

            Output out = buildRecommendationOutput(req.contactId);

            if (out != null && out.messages != null && !out.messages.isEmpty()) {
                res.message = String.join(out.messages, '\n');
            }

            if (out != null && out.products != null && !out.products.isEmpty()) {
                res.productsJson = JSON.serialize(out.products);
            }

            wrapper.add(res);
        }

        return wrapper;
    }

    // =====================================================
    // Core Logic (unchanged)
    // =====================================================
    private static Output buildRecommendationOutput(Id contactId) {

        Contact contactListId = [
            SELECT Id, Name, AccountId
            FROM Contact
            WHERE Id = :contactId OR AccountId = :contactId
            LIMIT 1
        ];

        Id conId = contactListId.Id;

        Output out = new Output();
        if (conId == null) return out;

        DateTime startDt = DateTime.now().addDays(-LOOKBACK_DAYS);

        // =====================================================
        // 1) Recent Orders
        // =====================================================
        List<ssot__SalesOrder__dlm> recentOrders;

        if (Test.isRunningTest() && mockRecentOrders != null) {
            recentOrders = mockRecentOrders;
        } else {
            recentOrders = [
                SELECT ssot__Id__c, ssot__BillToContactId__c, ssot__OrderStartDate__c
                FROM ssot__SalesOrder__dlm
                WHERE ssot__BillToContactId__c = :conId
                  AND ssot__OrderStartDate__c >= :startDt
            ];
        }

        if (recentOrders.isEmpty()) {
            return out;
        }

        Set<String> orderIds = new Set<String>();
        for (ssot__SalesOrder__dlm o : recentOrders) {
            if (o.ssot__Id__c != null) orderIds.add(o.ssot__Id__c);
        }

        if (orderIds.isEmpty()) return out;

        // =====================================================
        // 2) Purchased Products
        // =====================================================
        Set<String> purchasedProductIds = new Set<String>();

        List<ssot__SalesOrderProduct__dlm> orderProducts;

        if (Test.isRunningTest() && mockOrderProducts != null) {
            orderProducts = mockOrderProducts;
        } else {
            orderProducts = [
                SELECT ssot__SalesOrderId__c, ssot__ProductId__c
                FROM ssot__SalesOrderProduct__dlm
                WHERE ssot__SalesOrderId__c IN :orderIds
            ];
        }

        for (ssot__SalesOrderProduct__dlm op : orderProducts) {
            purchasedProductIds.add(op.ssot__ProductId__c);
        }

        if (purchasedProductIds.isEmpty()) return out;

        // =====================================================
        // 3) Family Counts
        // =====================================================
        Map<String, Integer> familyCounts = new Map<String, Integer>();

        List<ssot__Product__dlm> purchasedProducts;

        if (Test.isRunningTest() && mockPurchasedProducts != null) {
            purchasedProducts = mockPurchasedProducts;
        } else {
            purchasedProducts = [
                SELECT ssot__Id__c, ssot__ProductFamily__c
                FROM ssot__Product__dlm
                WHERE ssot__Id__c IN :purchasedProductIds
                  AND ssot__ProductSKU__c LIKE 'SKU%'
            ];
        }

        for (ssot__Product__dlm p : purchasedProducts) {
            String fam = p.ssot__ProductFamily__c;
            if (String.isBlank(fam)) continue;

            if (!familyCounts.containsKey(fam)) {
                familyCounts.put(fam, 1);
            } else {
                familyCounts.put(fam, familyCounts.get(fam) + 1);
            }
        }

        if (familyCounts.isEmpty()) return out;

        // =====================================================
        // Sort families (existing logic unchanged)
        // =====================================================
        List<String> familiesSorted = new List<String>();
        familiesSorted.addAll(familyCounts.keySet());

        for (Integer i = 0; i < familiesSorted.size(); i++) {
            for (Integer j = i + 1; j < familiesSorted.size(); j++) {

                String famA = familiesSorted[i];
                String famB = familiesSorted[j];

                if (familyCounts.get(famB) > familyCounts.get(famA)) {
                    String temp = famA;
                    familiesSorted[i] = famB;
                    familiesSorted[j] = temp;
                }
            }
        }

        List<String> topFamiliesList = new List<String>();
        for (Integer i = 0; i < familiesSorted.size() && i < TOP_FAMILIES; i++) {
            topFamiliesList.add(familiesSorted[i]);
        }

        Set<String> topFamiliesSet = new Set<String>();
        topFamiliesSet.addAll(topFamiliesList);

        Integer candidateLimit = MAX_RESULTS * 10;

        // =====================================================
        // 5) Candidate Products
        // =====================================================
        List<ssot__Product__dlm> candidates;

        if (Test.isRunningTest() && mockCandidateProducts != null) {
            candidates = mockCandidateProducts;
        } else {
            candidates = [
                SELECT Display_URL__c,
                       ssot__Description__c,
                       ssot__Id__c,
                       ssot__Name__c,
                       ssot__ProductFamily__c,
                       ssot__ProductSKU__c
                FROM ssot__Product__dlm
                WHERE ssot__ProductFamily__c IN :topFamiliesSet
                  AND ssot__Id__c NOT IN :purchasedProductIds
                  AND ssot__ProductSKU__c LIKE 'SKU%'
                ORDER BY ssot__ProductFamily__c, ssot__Name__c, ssot__ProductSKU__c
                LIMIT :candidateLimit
            ];
        }

        for (ssot__Product__dlm p : candidates) {

            if (out.products.size() >= MAX_RESULTS) break;

            RecProductDTO dto = new RecProductDTO();
            dto.id = p.ssot__Id__c;
            dto.name = p.ssot__Name__c;
            dto.description = p.ssot__Description__c;
            dto.displayUrl = p.Display_URL__c;
            dto.productFamily = p.ssot__ProductFamily__c;
            dto.sku = p.ssot__ProductSKU__c;

            out.products.add(dto);
        }

        // =====================================================
        // Messages (UNCHANGED)
        // =====================================================
        String familiesPhrase = buildFamiliesPhrase(topFamiliesList);

        String alignWord = 'aligns';
        if (topFamiliesList.size() == 2) alignWord = 'both align';
        if (topFamiliesList.size() >= 3) alignWord = 'all align';

        out.messages.add(
            'Your local store has excess inventory on ' + familiesPhrase + ' — ' + alignWord + ' with what you’ve bought before.'
        );
        out.messages.add(
            'I can bundle them for you and apply an in-store pickup incentive.'
        );

        return out;
    }

    private static String buildFamiliesPhrase(List<String> fams) {
        if (fams == null || fams.isEmpty()) return 'these items';

        List<String> cleaned = new List<String>();
        for (String f : fams) {
            if (!String.isBlank(f)) cleaned.add(f);
        }

        if (cleaned.size() == 1) return cleaned[0];
        if (cleaned.size() == 2) return cleaned[0] + ' and ' + cleaned[1];

        String phrase = '';
        for (Integer i = 0; i < cleaned.size(); i++) {
            if (i == cleaned.size() - 1) {
                phrase += 'and ' + cleaned[i];
            } else {
                phrase += cleaned[i] + ', ';
            }
        }
        return phrase;
    }
}