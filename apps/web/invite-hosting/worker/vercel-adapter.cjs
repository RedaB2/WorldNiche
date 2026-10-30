module.exports = async (request, response) => {
  const { default: handler } = await import('./handler.mjs');
  const result = await handler.fetch(new Request(new URL(request.url, 'https://worldniche.app'), {
    method: request.method,
    headers: request.headers,
  }));
  response.writeHead(result.status, Object.fromEntries(result.headers));
  response.end(request.method === 'HEAD' ? undefined : Buffer.from(await result.arrayBuffer()));
};
