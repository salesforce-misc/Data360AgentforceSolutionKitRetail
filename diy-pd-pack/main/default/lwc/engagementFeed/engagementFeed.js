import { LightningElement, api, wire } from 'lwc';
import getEngagementFeed from '@salesforce/apex/EngagementFeedController.getEngagementFeed';

export default class EngagementFeed extends LightningElement {

    @api recordId; // Account Id

    feedItems = [];
    isLoading = true;


    @wire(getEngagementFeed, { accountId: '$recordId' })
    wiredFeed({ error, data }) {

        this.isLoading = false;

        if (data) {
            this.feedItems = this.prepareItems(data);
        }
        else if (error) {
            console.error(error);
        }
    }


    prepareItems(data) {

        return data.map((item, index) => {

            const isLast = index === data.length - 1;

            return {
                ...item,

                iconStyle:
                    `border-color:${item.color};` +
                    `color:${item.color};` +
                    `background:${this.getLightBg(item.color)};`,

                lineClass: isLast ? 'line line--hidden' : 'line'
            };
        });
    }


    getLightBg(color) {

        switch (color) {

            case '#2e844a':
                return '#eaf5ef';

            case '#ba0517':
                return '#fde7e9';

            case '#0176d3':
                return '#e8f1fb';

            default:
                return '#f4f6f9';
        }
    }
}