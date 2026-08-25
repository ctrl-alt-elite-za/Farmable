# Farmable

Farmable is a hackathon frontend for an offline-first decision-support app for South African smallholder farmers. It demonstrates how a farmer could plan a field, check a crop, compare nearby markets and track costs from one phone-first interface.

This branch contains a frontend demonstration only. Crop results, prices, weather and financial values are labelled sample data; no live API or machine-learning model is connected.

## Run the demo

```bash
npm install
npm run dev
```

Create a production build with `npm run build`.

## Interaction

The background corn cob is a code-native SVG. Anime.js 4.5.0 maps page scroll progress to the position of its kernels, husks and silk. Scrolling down breaks it apart; scrolling up seeks the same animation backwards and reassembles it. Visitors who prefer reduced motion see the intact cob without the scroll effect.

The farmer preview is also fully interactive without a backend. Navigation links move to the relevant section, the crop check produces and saves a sample result, market rows can be selected and confirmed, and the cost record recalculates when a sample expense is added or removed. These actions use browser state and reset when the page is reloaded.

The header and footer use a transparent public-domain corn illustration. Its source and licence are recorded in [ASSET-LICENSES.md](./ASSET-LICENSES.md).
