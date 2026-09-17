const fs = require('fs');
const path = require('path');

function ensureViroLink(config) {
  const projectRoot = config.modRequest.projectRoot;
  const source = path.resolve(projectRoot, '../../node_modules/@reactvision/react-viro');
  const packageDirectory = path.join(projectRoot, 'node_modules', '@reactvision');
  const target = path.join(packageDirectory, 'react-viro');

  if (!fs.existsSync(source)) {
    throw new Error(`Cannot find @reactvision/react-viro at ${source}`);
  }

  fs.mkdirSync(packageDirectory, { recursive: true });
  if (!fs.existsSync(target)) {
    fs.symlinkSync(source, target, process.platform === 'win32' ? 'junction' : 'dir');
  }
  return config;
}

module.exports = function withViroMonorepo(config) {
  const { withDangerousMod } = require('@expo/config-plugins');
  return ['ios', 'android'].reduce((current, platform) => {
    return withDangerousMod(current, [platform, async (next) => ensureViroLink(next)]);
  }, config);
};
