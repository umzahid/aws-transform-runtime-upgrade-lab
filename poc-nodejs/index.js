'use strict';

function formatGreeting(name, callback) {
  var displayName = name || 'world';
  var buf = Buffer.from(displayName, 'utf8');
  callback(null, 'Hello, ' + buf.toString('utf8') + '!');
}

module.exports = { formatGreeting: formatGreeting };
