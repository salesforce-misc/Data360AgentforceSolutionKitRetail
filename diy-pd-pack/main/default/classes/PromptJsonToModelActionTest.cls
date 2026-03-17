@IsTest
private class PromptJsonToModelActionTest {

    // =====================================================
    // 1. Null Input
    // Covers: jsonText == null
    // =====================================================
    @IsTest
    static void testNullInput() {

        Test.startTest();
        List<PromptOutputADT> res =
            PromptJsonToModelAction.convert(null);
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assertEquals('No JSON provided', res[0].message);
        System.assertEquals('[]', res[0].productsJson);
    }

    // =====================================================
    // 2. Empty List
    // Covers: jsonText.isEmpty()
    // =====================================================
    @IsTest
    static void testEmptyList() {

        Test.startTest();
        List<PromptOutputADT> res =
            PromptJsonToModelAction.convert(new List<String>());
        Test.stopTest();

        System.assertEquals('No JSON provided', res[0].message);
        System.assertEquals('[]', res[0].productsJson);
    }

    // =====================================================
    // 3. Blank String
    // Covers: String.isBlank(jsonText[0])
    // =====================================================
    @IsTest
    static void testBlankString() {

        List<String> input = new List<String>{ '   ' };

        List<PromptOutputADT> res =
            PromptJsonToModelAction.convert(input);

        System.assertEquals('No JSON provided', res[0].message);
        System.assertEquals('[]', res[0].productsJson);
    }

    // =====================================================
    // 4. Valid JSON with Products
    // =====================================================
    @IsTest
    static void testValidJson() {

        String json =
            '{' +
            '"message":"Winter deals available",' +
            '"products":[' +
                '{"id":"1","name":"Jacket"}' +
            ']' +
            '}';

        List<PromptOutputADT> res =
            PromptJsonToModelAction.convert(new List<String>{ json });

        System.assertEquals(1, res.size());
        System.assertEquals('Winter deals available', res[0].message);
        System.assert(res[0].productsJson.contains('Jacket'));
    }

    // =====================================================
    // 5. JSON inside ```json block
    // Covers: replace('```json') logic
    // =====================================================
    @IsTest
    static void testJsonCodeBlock() {

        String json =
            '```json\n' +
            '{ "message":"Block message", "products":[{"id":"2","name":"Coat"}] }' +
            '\n```';

        List<PromptOutputADT> res =
            PromptJsonToModelAction.convert(new List<String>{ json });

        System.assertEquals('Block message', res[0].message);
        System.assert(res[0].productsJson.contains('Coat'));
    }

    // =====================================================
    // 6. JSON without Products
    // Covers: productsObj == null
    // =====================================================
    @IsTest
    static void testJsonWithoutProducts() {

        String json =
            '{ "message":"No products available" }';

        List<PromptOutputADT> res =
            PromptJsonToModelAction.convert(new List<String>{ json });

        System.assertEquals('No products available', res[0].message);
        System.assertEquals('[]', res[0].productsJson);
    }

    // =====================================================
    // 7. JSON with extra text before/after
    // Covers: substring extraction logic
    // =====================================================
    @IsTest
    static void testJsonWithExtraText() {

        String json =
            'Some intro text ' +
            '{ "message":"Trim test", "products":[{"id":"3","name":"Boots"}] }' +
            ' some footer';

        List<PromptOutputADT> res =
            PromptJsonToModelAction.convert(new List<String>{ json });

        System.assertEquals('Trim test', res[0].message);
        System.assert(res[0].productsJson.contains('Boots'));
    }
}