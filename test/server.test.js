const { test, describe, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createServer } = require('../src/server');

describe('HTTP application', () => {
  let server;
  let base;

  before(async () => {
    server = createServer();
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    base = `http://127.0.0.1:${server.address().port}`;
  });

  // KILL HANGING CONNECTIONS HERE
  after(async () => {
    if (server) {
      server.close();
      if (typeof server.closeAllConnections === 'function') {
        server.closeAllConnections(); // Forces fetch keep-alive sockets to drop
      }
    }
  });

  test('home returns the classroom message and version', async () => {
    const response = await fetch(base);
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.match(body.message, /Jenkins EC2/);
    assert.equal(body.version, process.env.APP_VERSION || 'local');
  });

  test('health endpoint is ready', async () => {
    const response = await fetch(`${base}/health`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: 'ok' });
  });

  test('unknown routes return 404', async () => {
    const response = await fetch(`${base}/missing`);
    assert.equal(response.status, 404);
    assert.deepEqual(await response.json(), { error: 'Not found' });
  });

  test('responses advertise JSON content', async () => {
    const response = await fetch(base);
    assert.equal(response.headers.get('content-type'), 'application/json');
    await response.json();
  });
});
