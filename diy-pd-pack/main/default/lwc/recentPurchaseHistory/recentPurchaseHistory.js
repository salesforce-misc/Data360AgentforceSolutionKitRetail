import { LightningElement, api, wire, track } from 'lwc';
import getRecentProducts from '@salesforce/apex/RecentPurchaseController.getRecentPurchasedProducts';

export default class RecentPurchaseHistory extends LightningElement {
    @api recordId;
    @track products = [];
    @track error;
    @track isLoading = true;

    @track activeIndex = 0;
    cardWidth = 220; // must match CSS

    @wire(getRecentProducts, { accountId: '$recordId' })
    wiredProducts({ error, data }) {
        this.isLoading = false;

        if (data) {
            this.products = data.map(item => ({
                ...item,
                shortDescription: this.truncateText(item.description, 80)
            }));
            this.error = null;
        } else if (error) {
            this.error = error.body?.message || 'Unknown error';
        }
    }

    truncateText(text, maxLength) {
        return text && text.length > maxLength
            ? text.substring(0, maxLength) + '...'
            : text || '';
    }

    renderedCallback() {
        const carousel = this.refs.carouselTrack;
        if (carousel && !carousel._scrollBound) {
            carousel.addEventListener('scroll', this.handleScroll.bind(this));
            carousel._scrollBound = true;
        }
    }

    handleScroll() {
        const carousel = this.refs.carouselTrack;
        const scrollLeft = carousel.scrollLeft;
        const maxScroll = carousel.scrollWidth - carousel.clientWidth;

        let index =
            scrollLeft <= 2
                ? 0
                : scrollLeft >= maxScroll - 2
                ? this.products.length - 1
                : Math.round(
                      (scrollLeft + carousel.clientWidth / 2) / this.cardWidth
                  );

        this.activeIndex = Math.max(
            0,
            Math.min(index, this.products.length - 1)
        );
    }

    handleDotClick(event) {
        const index = Number(event.target.dataset.index);
        this.activeIndex = index;

        this.refs.carouselTrack.scrollTo({
            left: index * this.cardWidth,
            behavior: 'smooth'
        });
    }

    get dots() {
        return this.products.map((_, index) => ({
            index,
            className: index === this.activeIndex ? 'dot active' : 'dot'
        }));
    }
}