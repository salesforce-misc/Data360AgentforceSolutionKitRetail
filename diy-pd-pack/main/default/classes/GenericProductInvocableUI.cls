public class GenericProductInvocableUI {

    // ---- Input wrapper (for Agentforce Action / Flow) ----
    public class Request {
        @InvocableVariable(required=true)
        public String requestType; // Always pass STORAGE_PRODUCTS

        @InvocableVariable(required=true)
        public Id contactId;
    }

    // ---- Output wrapper (Lightning Types will bind to THIS) ----
    public class Output {
        @InvocableVariable
        public List<ProductItem> products;

        public Output() {
            products = new List<ProductItem>();
        }
    }

    // ---- Product item DTO (minimal fields required for UI) ----
    public class ProductItem {
        @InvocableVariable public String Name;
        @InvocableVariable public String Description;
        @InvocableVariable public String DisplayUrl;
    }

    // ---- Invocable Method (UI-friendly output for Custom Lightning Type) ----
    @InvocableMethod(
        label='Storage Products - UI (Products Only)'
        description='Returns only product list for Agentforce UI rendering via Custom Lightning Types'
    )
    public static List<Output> invoke(List<Request> requests) {

        List<Output> results = new List<Output>();

        for (Request req : requests) {
            Output out = new Output();

            // Guard conditions: return empty list if request invalid
            if (req == null || req.contactId == null || req.requestType != 'STORAGE_PRODUCTS') {
                results.add(out);
                continue;
            }

            // Reuse existing logic (NO changes to GenericProductService)
            GenericProductService.Response res =
                GenericProductService.returnStorageRecommendation(req.contactId);

            // Map only required fields for UI
            if (res != null && res.products != null) {
                for (ssot__Product__dlm p : res.products) {
                    ProductItem item = new ProductItem();
                    item.Name = p.ssot__Name__c;
                    item.Description = p.ssot__Description__c;
                    item.DisplayUrl = p.Display_URL__c;
                    out.products.add(item);
                }
            }

            results.add(out);
        }

        return results;
    }
}