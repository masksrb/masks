import { createServer } from "node:http";

export async function listen(handler) {
  const server = createServer(handler);

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  const { port } = server.address();

  return {
    url: `http://127.0.0.1:${port}`,
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}

export function json(response, status, value, headers = {}) {
  response.writeHead(status, {
    "content-type": "application/json",
    ...headers,
  });
  response.end(JSON.stringify(value));
}
