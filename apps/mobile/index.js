import { registerRootComponent } from 'expo';

import App from './App';
import { installOfflineProbe } from './src/offline/nativeProbe';

installOfflineProbe();

registerRootComponent(App);
