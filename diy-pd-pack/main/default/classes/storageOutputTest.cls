@IsTest
private class storageOutputTest {

    @IsTest
    static void test_storageOutput_fields() {
        
        // Arrange
        storageOutput outObj = new storageOutput();
        outObj.message = 'Test storage message';
        outObj.productsJson = '[{"id":"123","name":"HVAC Filter","qty":2}]';

        // Act
        // (No logic to execute – DTO only)

        // Assert
        System.assertEquals('Test storage message', outObj.message,
            'Message field should match input value');

        System.assertEquals(
            '[{"id":"123","name":"HVAC Filter","qty":2}]',
            outObj.productsJson,
            'productsJson should store the JSON string correctly'
        );
    }
}