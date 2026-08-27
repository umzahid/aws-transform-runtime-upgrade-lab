'use strict';

exports.handler = async function (event, context) {
  const name = (event && event.name) || 'world';
  return { message: `Hello, ${name}!` };
};
