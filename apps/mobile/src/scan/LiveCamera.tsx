import { Text } from 'react-native';

/** Web/unsupported platform entry never imports a native camera module. */
export function LiveCamera() {
  return <Text>Camera preview requires an Android or iOS development build.</Text>;
}
