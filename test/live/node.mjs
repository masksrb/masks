import { createServer } from "node:http";
import { createInterface } from "node:readline";
import {
  Client,
  Handshake,
  Issuer,
  Key,
  bound,
} from "../../node/dist/index.js";

const port = Number(process.argv[process.argv.indexOf("--port") + 1] || 4412);

const held = {
  issuer: undefined,
  handshake: undefined,
  state: undefined,
  redirectURI: undefined,
  scope: undefined,
  registration: undefined,
  client: undefined,
  started: undefined,
  token: undefined,
  logouts: [],
  waiting: [],
};

function reply(answer) {
  process.stdout.write(`${JSON.stringify(answer)}\n`);
}

function query(url) {
  return new URL(url).searchParams;
}

async function body(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
}

const server = createServer(async (request, response) => {
  try {
    if (request.method === "POST" && request.url === "/backchannel") {
      const form = new URLSearchParams(await body(request));
      const logout = await held.client.logoutToken(form.get("logout_token") ?? "");

      held.logouts.push(logout);
      for (const resolve of held.waiting.splice(0)) resolve(logout);

      response.writeHead(200);
      return response.end();
    }

    response.writeHead(404);
    response.end();
  } catch (error) {
    process.stderr.write(`node live app: ${error}\n`);
    response.writeHead(400);
    response.end();
  }
});

const steps = {
  async handshake(asked) {
    held.issuer = await Issuer.discover(asked.issuer);
    held.redirectURI = asked.redirect_uri;
    held.scope = asked.signin_scope ?? asked.scope.filter((scope) => !scope.endsWith(":"));
    held.handshake = new Handshake(held.issuer, {
      name: asked.name,
      resource: asked.resource,
      redirectURIs: [asked.redirect_uri],
      returnTo: asked.return_to,
      scope: asked.scope,
      backchannelLogoutURI: asked.backchannel_logout_uri,
    });

    const started = held.handshake.start();
    held.state = started.state;

    return { url: started.url, state: started.state };
  },

  async "handshake:complete"(asked) {
    held.registration = await held.handshake.complete(query(asked.url), held.state);
    held.client = held.issuer.client(held.registration);

    return { client_id: held.registration.client_id };
  },

  async signin(asked) {
    held.started = await held.client.start({
      redirectURI: held.redirectURI,
      scope: held.scope,
      prompt: asked.prompt ?? undefined,
      maxAge: asked.max_age ?? undefined,
    });

    return { url: held.started.url };
  },

  async "signin:complete"(asked) {
    const signedIn = await held.client.complete(asked.url, held.started);
    held.token = signedIn.token;
    const claims = signedIn.claims ?? {};

    return {
      sub: claims.sub,
      sid: claims.sid,
      auth_time: claims.auth_time,
      amr: claims.amr,
      refresh_token: !!held.token.refresh_token,
      id_token: !!held.token.id_token,
    };
  },

  async refresh() {
    const renewed = await held.client.refresh(held.token.refresh_token);
    const rotated =
      !!renewed.refresh_token &&
      renewed.refresh_token !== held.token.refresh_token &&
      renewed.access_token !== held.token.access_token;
    held.token = renewed;

    const sub = renewed.id_token
      ? (await held.client.identity(renewed.id_token)).sub
      : (await held.client.userinfo(renewed)).sub;

    return { rotated, sub };
  },

  async logout(asked) {
    const timeout = (asked.timeout ?? 30) * 1000;
    const logout =
      held.logouts.shift() ??
      (await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error("no logout token arrived")), timeout);
        held.waiting.push((received) => {
          clearTimeout(timer);
          held.logouts.shift();
          resolve(received);
        });
      }));

    return { sid: logout.sid, sub: logout.sub };
  },

  async machine(asked) {
    const enrollment = await held.client.enroll({ scope: [asked.scope], name: "live machine" });
    const key = await Key.generate();
    const dpop = await Key.generate();
    const registered = await held.issuer.register(
      {
        client_name: "live machine",
        grant_types: ["client_credentials"],
        scope: asked.scope,
        token_endpoint_auth_method: "private_key_jwt",
        jwks: key.jwks(),
        dpop_bound_access_tokens: true,
      },
      enrollment.initial_access_token,
    );
    const machine = new Client({ issuer: held.issuer, id: registered.client_id, key, dpop });
    const token = await machine.clientCredentials({ scope: [asked.scope], resource: [asked.resource] });
    const introspected = await held.client.introspect(token.access_token);

    return {
      client_id: registered.client_id,
      bound: bound(token),
      active: introspected.active === true,
      scope: token.scope,
      jkt: introspected.cnf?.jkt === dpop.thumbprint,
    };
  },
};

server.listen(port, "127.0.0.1", () => {
  reply({ ready: true });

  const lines = createInterface({ input: process.stdin });
  let chain = Promise.resolve();

  lines.on("line", (line) => {
    chain = chain.then(async () => {
      const asked = JSON.parse(line);

      if (asked.step === "quit") {
        server.close();
        process.exit(0);
      }

      try {
        const step = steps[asked.step];
        if (!step) throw new Error(`unknown step ${asked.step}`);
        reply(await step(asked));
      } catch (error) {
        reply({ error: `${error?.constructor?.name ?? "Error"}: ${error?.message ?? error}` });
      }
    });
  });

  lines.on("close", () => {
    server.close();
    process.exit(0);
  });
});
