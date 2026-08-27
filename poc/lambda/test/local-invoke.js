'use strict';

const assert = require('assert');
const { handler } = require('../index.js');

function invoke(event) {
  return new Promise((resolve, reject) => {
    const maybePromise = handler(event, {}, (err, result) => {
      if (err) return reject(err);
      resolve(result);
    });
    if (maybePromise && typeof maybePromise.then === 'function') {
      maybePromise.then(resolve, reject);
    }
  });
}

async function main() {
  const result = await invoke({ name: 'AWS Transform' });
  assert.strictEqual(result.message, 'Hello, AWS Transform!');

  const defaultResult = await invoke({});
  assert.strictEqual(defaultResult.message, 'Hello, world!');

  console.log('local-invoke: all assertions passed');
}

main().catch((err) => {
  console.error('local-invoke: FAILED');
  console.error(err);
  process.exit(1);
});
