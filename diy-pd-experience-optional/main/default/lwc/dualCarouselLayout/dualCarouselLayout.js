import { LightningElement, track  } from 'lwc';
import isGuest from '@salesforce/user/isGuest';

export default class DualCarouselLayout extends LightningElement {
    get leftCarouselTitle() {
        return isGuest
            ? 'Trending Products'
            : 'Recent Purchases';
    }
}