'use strict';

const assert = require('assert');
const { formatGreeting } = require('../index.js');

function invoke(name) {
  return new Promise((resolve, reject) => {
    const maybePromise = formatGreeting(name, (err, result) => {
      if (err) return reject(err);
      resolve(result);
    });
    if (maybePromise && typeof maybePromise.then === 'function') {
      maybePromise.then(resolve, reject);
    }
  });
}

async function main() {
  const result = await invoke('AWS Transform');
  assert.strictEqual(result, 'Hello, AWS Transform!');

  const defaultResult = await invoke(undefined);
  assert.strictEqual(defaultResult, 'Hello, world!');

  console.log('local-invoke: all assertions passed');
}

main().catch((err) => {
  console.error('local-invoke: FAILED');
  console.error(err);
  process.exit(1);
});
