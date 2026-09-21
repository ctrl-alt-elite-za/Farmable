module.exports = function (api) {
  api.cache(true);
  return {
    presets: ['babel-preset-expo'],
    // Reanimated 4 and VisionCamera frame processors both run on the worklets
    // runtime, and its Babel plugin must be the last plugin in the list.
    plugins: ['react-native-worklets/plugin'],
  };
};
