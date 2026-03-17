import { LightningElement ,track, api } from 'lwc';
import getProducts from '@salesforce/apex/ProductCarouselController.getProducts';

export default class ProductCarousel extends LightningElement {    

    @api title;
    @api type;

    products = [];

    @track activeIndex = 0;

    cardWidth = 236; // must match CSS

    /*connectedCallback() {
        if (this.type === 'recent') {
            this.products = [
                { name: 'RYOBI ONE+ 18V', imageUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/mukt3fxxtxz6fgzltiv9.png', imageRedirectUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/mukt3fxxtxz6fgzltiv9.png', price: 99, reviews: 4805, url: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/mukt3fxxtxz6fgzltiv9.png' },
                { name: 'RYOBI Drill', imageUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/ugpauqyr6k4ykemyumuu.png', imageRedirectUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/ugpauqyr6k4ykemyumuu.png', price: 39, reviews: 4805, url: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/ugpauqyr6k4ykemyumuu.png' },
                { name: 'Wood Drilling Set', imageUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/sjahfb9mmbzzyogf87fk.jpg', imageRedirectUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/sjahfb9mmbzzyogf87fk.jpg', price: 16, reviews: 4805, url: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/sjahfb9mmbzzyogf87fk.jpg' },
                { name: 'ONE+ 18V Cordless Dual Function', imageUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/b1tituywkemxfgon7r8h.jpg', imageRedirectUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/b1tituywkemxfgon7r8h.jpg', price: 16, reviews: 4805, url: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/b1tituywkemxfgon7r8h.jpg' }
            ];
        } else {
            this.products = [
                { name: 'Discount Tool 1', imageUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/mukt3fxxtxz6fgzltiv9.png', imageRedirectUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/mukt3fxxtxz6fgzltiv9.png', price: 29, reviews: 4805, url: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/mukt3fxxtxz6fgzltiv9.png' },
                { name: 'Discount Tool 2', imageUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/ugpauqyr6k4ykemyumuu.png', imageRedirectUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/ugpauqyr6k4ykemyumuu.png', price: 19, reviews: 4805, url: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/ugpauqyr6k4ykemyumuu.png' },
                { name: 'Discount Tool 3', imageUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/sjahfb9mmbzzyogf87fk.jpg', imageRedirectUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/sjahfb9mmbzzyogf87fk.jpg', price: 15,reviews: 4805, url: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/sjahfb9mmbzzyogf87fk.jpg' },
                { name: 'Discount Tool 4', imageUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/b1tituywkemxfgon7r8h.jpg', imageRedirectUrl: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/b1tituywkemxfgon7r8h.jpg', price: 16, reviews: 4805, url: 'https://s3-us-west-2.amazonaws.com/dev-or-devrl-s3-bucket/sample-apps/coral-clouds/b1tituywkemxfgon7r8h.jpg' }
            ];
        }
    }

    renderedCallback() {
        const carousel = this.refs.carouselTrack;
        if (!carousel._scrollBound) {
            carousel.addEventListener('scroll', this.handleScroll.bind(this));
            carousel._scrollBound = true;
        }
    }

    handleScroll() {
        const carousel = this.refs.carouselTrack;

        const scrollLeft = carousel.scrollLeft;
        const maxScroll =
            carousel.scrollWidth - carousel.clientWidth;

        let index;

        // ✅ FORCE FIRST DOT
        if (scrollLeft <= 2) {
            index = 0;
        }
        // ✅ FORCE LAST DOT
        else if (scrollLeft >= maxScroll - 2) {
            index = this.products.length - 1;
        }
        // ✅ NORMAL CASE (MIDDLE)
        else {
            const center =
                scrollLeft + carousel.clientWidth / 2;
            index = Math.round(center / this.cardWidth);
        }

        index = Math.max(0, Math.min(index, this.products.length - 1));

        if (index !== this.activeIndex) {
            this.activeIndex = index;
        }
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
    }*/

    connectedCallback() {
        this.loadProducts();
    }

    loadProducts() {
        getProducts({ type: this.type })
            .then(result => {
                this.products = result || [];
            })
            .catch(error => {
                console.error('Error loading products', error);
            });
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
                      (scrollLeft + carousel.clientWidth / 2) /
                          this.cardWidth
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

    handleAddToCart(event) {
    const redirectUrl = event.currentTarget.dataset.url;

    console.log('Redirecting to:', redirectUrl);

    if (redirectUrl) {
        window.location.assign(redirectUrl);
    }
}
   
}