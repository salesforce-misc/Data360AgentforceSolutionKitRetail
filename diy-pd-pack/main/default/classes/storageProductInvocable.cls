public class storageProductInvocable {

    // ---- Input wrapper ----
    public class Request {
        @AuraEnabled @InvocableVariable(required=true)
        public String requestType;   // Expecting 'STORAGE_PRODUCTS'

        @AuraEnabled @InvocableVariable
        public Id contactId;
    }

    @InvocableMethod(
        label='Storage Products (Flow JSON Output)'
        description='Returns message + productsJson for STORAGE_PRODUCTS using storageOutput'
        category='Agent'
    )
    public static List<storageOutput> invoke(List<Request> requests) {

        // Invocable must return a LIST [1](https://www.infallibletechie.com/2025/03/salesforce-custom-agent-actions-using-apex-rest.html)
        List<storageOutput> outputs = new List<storageOutput>();

        for (Request req : requests) {

            storageOutput out = new storageOutput();
            out.message = '';
            out.productsJson = '[]';

            if (req != null &&
                req.requestType == 'STORAGE_PRODUCTS' &&
                req.contactId != null) {

                storageProductRecomendation.Response res =
                    storageProductRecomendation.returnStorageProducts(req.contactId);

                // message (flatten list -> string)
                if (res != null && res.messages != null && !res.messages.isEmpty()) {
                    out.message = String.join(res.messages, '\n');
                }

                // productsJson (serialize product list for UI)
                if (res != null && res.products != null && !res.products.isEmpty()) {

                    // JSON-friendly list with only UI-required fields
                    List<Map<String, Object>> dtoList = new List<Map<String, Object>>();

                    for (ssot__Product__dlm p : res.products) {
                        dtoList.add(new Map<String, Object>{
                            'id'          => p.ssot__Id__c,
                            'name'        => p.ssot__Name__c,
                            'description' => p.ssot__Description__c,
                            'displayUrl'  => p.Display_URL__c
                        });
                    }

                    out.productsJson = JSON.serialize(dtoList);
                }
            }

            outputs.add(out);
        }

        return outputs;
    }
}