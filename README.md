# Farmable

Farmable is an offline-first decision-support app for South African smallholder farmers. Farmers can plan a field, check a crop, compare nearby markets and track costs from one phone-first interface.

Crop results, prices, weather and financial values are labelled as sample data until live services are connected.

## Run Farmable

```bash
npm install
npm run dev
```

Create a production build with `npm run build`.

## Interaction

The background corn cob is a code-native SVG. Anime.js 4.5.0 maps page scroll progress to the position of its kernels, husks and silk. Scrolling down breaks it apart; scrolling up seeks the same animation backwards and reassembles it. Visitors who prefer reduced motion see the intact cob without the scroll effect.

The farmer interface works without a backend. Navigation links move to the relevant section, the crop check produces and saves a sample result, market rows can be selected and confirmed, and the cost record recalculates when a sample expense is added or removed. These actions use browser state and reset when the page is reloaded.

The header and footer use a transparent CC0 corn mark. Licensed farm photographs fill the crop-image placeholders. Sources and licences are recorded in [ASSET-LICENSES.md](./ASSET-LICENSES.md).
