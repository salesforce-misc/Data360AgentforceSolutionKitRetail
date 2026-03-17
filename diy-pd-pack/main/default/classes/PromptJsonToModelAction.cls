public with sharing class PromptJsonToModelAction {

    @InvocableMethod(label='Convert Product JSON to Winter Products')
    public static List<PromptOutputADT> convert(List<String> jsonText) {

        PromptOutputADT out = new PromptOutputADT();

        if (jsonText == null || jsonText.isEmpty() || String.isBlank(jsonText[0])) {
            out.message = 'No JSON provided';
            out.productsJson = '[]';
            return new List<PromptOutputADT>{ out };
        }

        String raw = jsonText[0].trim();
        raw = raw.replace('```json', '').replace('```', '').trim();

        Integer startIdx = raw.indexOf('{');
        Integer endIdx = raw.lastIndexOf('}');
        if (startIdx >= 0 && endIdx > startIdx) {
            raw = raw.substring(startIdx, endIdx + 1);
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(raw);

        out.message = (String) parsed.get('message');

        // Extract products and serialize back to JSON string
        Object productsObj = parsed.get('products');
        if (productsObj == null) {
            out.productsJson = '[]';
            return new List<PromptOutputADT>{ out };
        }

        out.productsJson = JSON.serialize(productsObj);

        return new List<PromptOutputADT>{ out };
    }
}