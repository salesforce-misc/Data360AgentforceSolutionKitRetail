import { LightningElement, api, wire } from 'lwc';
import getAccountDetails from '@salesforce/apex/GetAccounts.getAccountDetails';

export default class CustomerMetrics extends LightningElement {

        @api recordId;
          
          @wire(getAccountDetails, { accountId: '$recordId' })
          account;

          get hasData() {
            return this.account?.data !== undefined;
           }
        
          get error() {
                return this.account?.error;
            }

            get averageOrderValue() {
                const value = this.account?.data?.Contacts?.[0]?.Average_Order_Value__c;
                return (value || value === 0) ? (Math.round(value * 100) / 100) : '';
            }
            
          
            get customerSince() {
                const value = this.account?.data?.Contacts?.[0]?.Customer_Since__c;
                if(!value){
                    return '';
                }
                const dateObj = new Date(value);
                const year = dateObj.getUTCFullYear();
                const month = String(dateObj.getUTCMonth() +1).padStart(2, '0');
                const day = String(dateObj.getUTCDate()).padStart(2, '0');
                //return '${year} - ${month} - ${day}';
                return this.account?.data?.Contacts?.[0]?.Customer_Since__c?.split('T')[0] || '';
            }          
    
     
    
}