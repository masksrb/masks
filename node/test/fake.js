import { createServer } from "node:http";
import {
  calculateJwkThumbprint,
  EmbeddedJWK,
  exportJWK,
  generateKeyPair,
  importJWK,
  jwtVerify,
  SignJWT,
} from "jose";

const ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer";
const ACCESS_TOKEN = "urn:ietf:params:oauth:token-type:access_token";
const UPSTREAM = "urn:masks:params:oauth:token-type:upstream_access_token";

export function random() {
  return crypto.randomUUID().replaceAll("-", "");
}

export async function listen(handler) {
  const server = createServer(handler);

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  const { port } = server.address();

  return {
    url: `http://127.0.0.1:${port}`,
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}

async function body(request) {
  const chunks = [];

  for await (const chunk of request) chunks.push(chunk);

  return Buffer.concat(chunks).toString("utf8");
}

export function json(response, status, value, headers = {}) {
  response.writeHead(status, {
    "content-type": "application/json",
    ...headers,
  });
  response.end(JSON.stringify(value));
}

function oauthError(response, status, code, headers = {}) {
  json(
    response,
    status,
    { error: code, error_description: `${code} from the fake` },
    headers,
  );
}

export class Fake {
  audience = "https://files.example";
  kid = "signing-1";
  clients = new Map();
  registrations = new Map();
  registrationReads = 0;
  initial = new Map();
  assertions = new Set();
  revoked = [];
  enrolled = new Map();
  described = new Map();
  hints = [];
  exchanges = [];
  codes = new Map();
  grants = new Map();
  users = new Map();
  handshakes = [];
  lifetime = 3600;
  nonceOverride = undefined;
  authTime = undefined;
  refreshRefusal = undefined;
  userinfoCalls = 0;
  tokenRequests = [];
  upstreamAnswer = "upstream";
  enrollments = [];
  pending = 0;
  slowed = false;
  nonce = "";
  foreignURI = false;

  static async start() {
    const fake = new Fake();
    const { privateKey, publicKey } = await generateKeyPair("RS256", {
      extractable: true,
    });

    fake.signing = privateKey;
    fake.public = {
      ...(await exportJWK(publicKey)),
      kid: fake.kid,
      alg: "RS256",
      use: "sig",
    };

    const server = await listen((request, response) =>
      fake.handle(request, response).catch((error) => {
        response.writeHead(500);
        response.end(String(error));
      }),
    );

    fake.url = server.url;
    fake.close = server.close;

    return fake;
  }

  add(id, client) {
    this.clients.set(id, { refresh: new Set(), ...client });
  }

  async issue(claims, typ) {
    return new SignJWT(claims)
      .setProtectedHeader({ alg: "RS256", typ, kid: this.kid })
      .sign(this.signing);
  }

  accessToken(id, scope, jkt, extra = {}) {
    const now = Math.floor(Date.now() / 1000);
    const claims = {
      iss: this.url,
      sub: id,
      aud: this.audience,
      exp: now + this.lifetime,
      iat: now,
      jti: random(),
      client_id: id,
      scope,
      ...extra,
    };

    if (jkt) claims.cnf = { jkt };

    return this.issue(claims, "at+jwt");
  }

  async handle(request, response) {
    const path = new URL(request.url, this.url).pathname;
    const text = await body(request);

    if (
      request.method === "GET" &&
      path === "/.well-known/openid-configuration"
    ) {
      return json(response, 200, {
        issuer: this.url,
        token_endpoint: `${this.url}/token`,
        jwks_uri: `${this.url}/.well-known/jwks.json`,
        device_authorization_endpoint: `${this.url}/device_authorization`,
        revocation_endpoint: `${this.url}/revoke`,
        introspection_endpoint: `${this.url}/introspect`,
        registration_endpoint: `${this.url}/register`,
        enrollment_endpoint: `${this.url}/enrollments`,
        authorization_endpoint: `${this.url}/authorize`,
        userinfo_endpoint: `${this.url}/userinfo`,
        end_session_endpoint: `${this.url}/logout`,
        handshake_endpoint: `${this.url}/handshake`,
        backchannel_logout_supported: this.backchannel ?? true,
        authorization_response_iss_parameter_supported: true,
      });
    }

    if (request.method === "GET" && path === "/.well-known/jwks.json") {
      return json(response, 200, { keys: [this.public] });
    }

    const form = new URLSearchParams(text);

    if (request.method === "POST" && path === "/token") {
      return this.token(request, response, form);
    }

    if (request.method === "POST" && path === "/device_authorization") {
      const { id, ok } = await this.authenticated(request, form);

      if (!ok || form.get("client_id") !== id) {
        return oauthError(response, 401, "invalid_client");
      }

      return json(response, 200, {
        device_code: "device-code",
        user_code: "ABCD EFGH",
        verification_uri: `${this.url}/device`,
        expires_in: 600,
        interval: 0,
      });
    }

    if (request.method === "POST" && path === "/revoke") {
      const { ok } = await this.authenticated(request, form);
      if (!ok) return oauthError(response, 401, "invalid_client");

      this.revoked.push(form.get("token"));
      response.writeHead(200);
      return response.end();
    }

    if (request.method === "GET" && path === "/userinfo") {
      return this.userinfo(request, response);
    }

    if (request.method === "GET" && path.startsWith("/avatars/")) {
      if (request.headers.authorization === undefined) {
        response.writeHead(401);
        return response.end();
      }

      this.avatarAsks = [...(this.avatarAsks ?? []), request.url];

      if (this.avatarRedirect) {
        response.writeHead(302, { location: this.avatarRedirect });
        return response.end();
      }

      response.writeHead(200, {
        "content-type": this.avatarType ?? "image/png",
      });
      return response.end(this.avatarBody ?? Buffer.from("png-bytes"));
    }

    if (request.method === "POST" && path === "/introspect") {
      const { ok } = await this.authenticated(request, form);
      if (!ok) return oauthError(response, 401, "invalid_client");

      this.hints.push(form.get("token_type_hint"));

      return json(
        response,
        200,
        this.described.get(form.get("token")) ?? { active: false },
      );
    }

    if (request.method === "POST" && path === "/enrollments") {
      return this.enroll(request, response, form);
    }

    if (request.method === "DELETE" && path.startsWith("/enrollments/")) {
      return this.unenroll(
        request,
        response,
        form,
        decodeURIComponent(path.slice(13)),
      );
    }

    if (request.method === "POST" && path === "/register") {
      return this.register(request, response, text);
    }

    if (path.startsWith("/register/")) {
      return this.registration(request, response, path.slice(10), text);
    }

    response.writeHead(404);
    response.end();
  }

  async authenticated(request, form) {
    const header = request.headers.authorization ?? "";

    if (header.startsWith("Basic ")) {
      const [id, secret] = Buffer.from(header.slice(6), "base64")
        .toString("utf8")
        .split(":")
        .map((part) => decodeURIComponent(part.replaceAll("+", " ")));
      const client = this.clients.get(id);

      return {
        id,
        client,
        ok:
          !!client &&
          client.method === "client_secret_basic" &&
          client.secret === secret,
      };
    }

    const id = form.get("client_id");
    const client = this.clients.get(id);

    if (!client) return { id, ok: false };

    switch (client.method) {
      case "client_secret_post":
        return { id, client, ok: form.get("client_secret") === client.secret };
      case "none":
        return { id, client, ok: true };
      case "private_key_jwt":
        return { id, client, ok: await this.asserted(form, id, client) };
      default:
        return { id, client, ok: false };
    }
  }

  async asserted(form, id, client) {
    if (form.get("client_assertion_type") !== ASSERTION_TYPE) return false;

    try {
      const { payload } = await jwtVerify(
        form.get("client_assertion"),
        async (header) => {
          const jwk = client.jwks.keys.find((key) => key.kid === header.kid);
          if (!jwk) throw new Error("unknown kid");

          return importJWK(jwk, "ES256");
        },
        {
          algorithms: ["ES256"],
          audience: [this.url, `${this.url}/token`],
          clockTolerance: 0,
        },
      );

      if (
        payload.iss !== id ||
        payload.sub !== id ||
        !payload.jti ||
        !payload.exp
      )
        return false;
      if (payload.exp - payload.iat > 3600) return false;
      if (this.assertions.has(payload.jti)) return false;

      this.assertions.add(payload.jti);

      return true;
    } catch {
      return false;
    }
  }

  async proof(request, path) {
    const presented = request.headers.dpop;
    if (!presented) return { jkt: "", ok: true };

    try {
      const { payload, protectedHeader } = await jwtVerify(
        presented,
        EmbeddedJWK,
        {
          typ: "dpop+jwt",
          algorithms: ["ES256"],
        },
      );

      if (
        payload.htm !== "POST" ||
        payload.htu !== `${this.url}${path}` ||
        payload.ath
      ) {
        return { ok: false };
      }

      if (this.nonce && payload.nonce !== this.nonce) return { ok: false };

      return {
        jkt: await calculateJwkThumbprint(protectedHeader.jwk, "sha256"),
        ok: true,
      };
    } catch {
      return { ok: false };
    }
  }

  async token(request, response, form) {
    const { jkt, ok } = await this.proof(request, "/token");

    if (!ok) {
      if (this.nonce) {
        this.refusals = (this.refusals ?? 0) + 1;
        return oauthError(response, 400, "use_dpop_nonce", {
          "dpop-nonce": this.nonce,
        });
      }

      return oauthError(response, 400, "invalid_dpop_proof");
    }

    const {
      id,
      client,
      ok: authenticated,
    } = await this.authenticated(request, form);
    if (!authenticated) return oauthError(response, 401, "invalid_client");

    this.tokenRequests.push(form.get("grant_type"));

    switch (form.get("grant_type")) {
      case "client_credentials":
        break;
      case "authorization_code": {
        const held = this.codes.get(form.get("code"));
        this.codes.delete(form.get("code"));

        if (
          !held ||
          held.client_id !== id ||
          held.redirect_uri !== form.get("redirect_uri") ||
          held.challenge !==
            Buffer.from(
              await crypto.subtle.digest(
                "SHA-256",
                new TextEncoder().encode(form.get("code_verifier") ?? ""),
              ),
            ).toString("base64url")
        ) {
          return oauthError(response, 400, "invalid_grant");
        }

        return this.signIn(response, id, held, jkt);
      }
      case "refresh_token": {
        const presented = form.get("refresh_token");

        if (this.grants.has(presented)) {
          if (this.refreshRefusal) {
            return oauthError(
              response,
              this.refreshRefusal.status,
              this.refreshRefusal.code,
            );
          }

          const held = this.grants.get(presented);
          this.grants.delete(presented);

          return this.signIn(response, id, held, jkt);
        }

        if (!client.refresh.has(presented))
          return oauthError(response, 400, "invalid_grant");

        client.refresh.delete(presented);
        break;
      }
      case "urn:ietf:params:oauth:grant-type:device_code":
        if (this.pending > 0) {
          this.pending--;

          if (!this.slowed) {
            this.slowed = true;
            return oauthError(response, 400, "slow_down");
          }

          return oauthError(response, 400, "authorization_pending");
        }
        break;
      case "urn:ietf:params:oauth:grant-type:token-exchange": {
        const asked = {};

        for (const [name, value] of form) {
          if (name.startsWith("client_")) continue;
          asked[name] =
            asked[name] === undefined ? value : [asked[name], value].flat();
        }

        asked.dpop = jkt;
        this.exchanges.push(asked);

        if (!form.get("subject_token"))
          return oauthError(response, 400, "invalid_request");

        if (form.get("requested_token_type") === UPSTREAM) {
          return json(response, 200, {
            access_token: "from-the-provider",
            token_type: "Bearer",
            issued_token_type:
              this.upstreamAnswer === "upstream" ? UPSTREAM : ACCESS_TOKEN,
            expires_in: 60,
            scope: "calendar.readonly",
          });
        }

        return json(response, 200, {
          access_token: await this.accessToken(
            id,
            form.get("scope") ?? "",
            jkt,
          ),
          issued_token_type: ACCESS_TOKEN,
          token_type: jkt ? "DPoP" : "Bearer",
          expires_in: 300,
          scope: form.get("scope") ?? "",
        });
      }
      default:
        return oauthError(response, 400, "unsupported_grant_type");
    }

    const scope = form.get("scope") || client.scope || "";
    const refresh = random();
    client.refresh.add(refresh);

    return json(response, 200, {
      access_token: await this.accessToken(id, scope, jkt),
      token_type: jkt ? "DPoP" : "Bearer",
      expires_in: 3600,
      scope,
      refresh_token: refresh,
    });
  }

  authorize(target, options = {}) {
    const asked = new URL(target).searchParams;
    const redirect = new URL(asked.get("redirect_uri"));

    this.authorized = asked;

    if (options.error) {
      redirect.searchParams.set("error", options.error);
      redirect.searchParams.set("error_description", "declined in the fake");
      redirect.searchParams.set("state", asked.get("state"));
      return redirect.toString();
    }

    const code = random();
    const sub = options.sub ?? "ada";
    const scope = options.scope ?? asked.get("scope");

    this.codes.set(code, {
      client_id: asked.get("client_id"),
      redirect_uri: asked.get("redirect_uri"),
      challenge: asked.get("code_challenge"),
      nonce: asked.get("nonce"),
      scope,
      resource: asked.getAll("resource"),
      organization: asked.get("organization"),
      sub,
      sid: options.sid ?? `sid-${random()}`,
    });

    redirect.searchParams.set("code", code);
    redirect.searchParams.set("state", options.state ?? asked.get("state"));
    redirect.searchParams.set("iss", options.iss ?? this.url);

    return redirect.toString();
  }

  actor(sub) {
    return {
      name: "Ada Lovelace",
      preferred_username: "ada",
      email: "ada@example.com",
      email_verified: true,
      tenant: { uuid: "t-1", subdomain: "acme", name: "Acme" },
      "masks:avatars": {
        photo: `${this.url}/avatars/${sub}`,
        identicon: `${this.url}/avatars/${sub}/identicon`,
      },
      org: { id: "o-1", key: "acme", name: "Acme", role: "owner" },
      orgs: [
        { id: "o-1", key: "acme", name: "Acme", role: "owner" },
        { id: "o-2", key: "globex", name: "Globex", role: "member" },
      ],
      ...(this.users.get(sub) ?? {}),
    };
  }

  async signIn(response, id, held, jkt) {
    const now = Math.floor(Date.now() / 1000);
    const actor = this.actor(held.sub);
    const scopes = (held.scope ?? "").split(" ").filter(Boolean);
    const audience = held.resource?.length ? held.resource : [this.audience];
    const refresh = random();

    this.grants.set(refresh, held);

    const answer = {
      access_token: await this.accessToken(held.sub, held.scope, jkt, {
        aud: audience.length === 1 ? audience[0] : audience,
        client_id: id,
        ...(scopes.includes("organization") || actor.org
          ? { org: actor.org }
          : {}),
      }),
      token_type: jkt ? "DPoP" : "Bearer",
      expires_in: this.lifetime,
      scope: held.scope,
      refresh_token: refresh,
    };

    if (scopes.includes("openid")) {
      answer.id_token = await this.issue(
        {
          iss: this.url,
          sub: held.sub,
          aud: id,
          exp: now + 300,
          iat: now,
          sid: held.sid,
          nonce: this.nonceOverride ?? held.nonce ?? undefined,
          auth_time: this.authTime,
          name: actor.name,
          email: actor.email,
          org: actor.org,
        },
        "JWT",
      );
    }

    const delegated = scopes.find((scope) =>
      scope.startsWith("masks:delegate:"),
    );

    if (delegated) {
      const provider = delegated.slice("masks:delegate:".length);
      answer.delegations = [
        {
          connection: `connection-${provider}`,
          provider,
          provider_name: "Google",
          subject: "ada@gmail.example",
        },
      ];
    }

    return json(response, 200, answer);
  }

  async userinfo(request, response) {
    this.userinfoCalls++;

    const header = request.headers.authorization ?? "";
    const token = header.replace(/^(Bearer|DPoP) /, "");

    try {
      const { payload } = await jwtVerify(
        token,
        await importJWK(this.public, "RS256"),
      );

      return json(response, 200, {
        sub: payload.sub,
        ...this.actor(payload.sub),
      });
    } catch {
      return oauthError(response, 401, "invalid_token");
    }
  }

  shake(target, options = {}) {
    const asked = new URL(target).searchParams;
    const back = new URL(asked.get("return_to"));

    this.handshakes.push(asked);

    if (options.error) {
      back.searchParams.set("error", options.error);
      back.searchParams.set("state", asked.get("state"));
      return back.toString();
    }

    const token = random();
    const id = `app-${random()}`;

    this.initial.set(token, id);
    back.searchParams.set("initial_access_token", token);
    back.searchParams.set("iss", options.iss ?? this.url);
    back.searchParams.set("state", options.state ?? asked.get("state"));

    return back.toString();
  }

  logoutToken(claims = {}, typ = "logout+jwt") {
    const now = Math.floor(Date.now() / 1000);

    return this.issue(
      {
        iss: this.url,
        aud: claims.aud,
        iat: now,
        exp: now + 120,
        jti: random(),
        events: {
          "http://schemas.openid.net/event/backchannel-logout": {},
        },
        ...claims,
      },
      typ,
    );
  }

  async enroll(request, response, form) {
    const { id, ok } = await this.authenticated(request, form);
    if (!ok) return oauthError(response, 401, "invalid_client");

    const scope = form.get("scope") ?? "";
    if (!scope) return oauthError(response, 400, "invalid_request");

    const token = random();
    const expiresIn = Number(form.get("expires_in") || 900);

    const machine = `machine-${random()}`;

    this.initial.set(token, machine);
    this.enrolled.set(machine, id);
    this.enrollments.push({
      app: id,
      scope,
      name: form.get("client_name"),
      expires_in: form.get("expires_in"),
      dpop: request.headers.dpop,
    });

    return json(response, 201, {
      initial_access_token: token,
      expires_in: expiresIn,
      scope,
    });
  }

  async unenroll(request, response, form, machine) {
    const { id, ok } = await this.authenticated(request, form);
    if (!ok) return oauthError(response, 401, "invalid_client");

    if (this.enrolled.get(machine) !== id) {
      return oauthError(response, 404, "invalid_request");
    }

    this.clients.delete(machine);
    response.writeHead(204);
    return response.end();
  }

  register(request, response, text) {
    const presented = (request.headers.authorization ?? "").replace(
      /^Bearer /,
      "",
    );
    const id = this.initial.get(presented);

    if (!id) return oauthError(response, 401, "invalid_token");

    this.initial.delete(presented);

    const metadata = JSON.parse(text || "{}");
    const token = random();

    const secret =
      metadata.token_endpoint_auth_method === "client_secret_basic" ||
      metadata.token_endpoint_auth_method === "client_secret_post"
        ? random()
        : undefined;

    this.add(id, {
      method: metadata.token_endpoint_auth_method,
      jwks: metadata.jwks ?? { keys: [] },
      scope: metadata.scope,
      secret,
      metadata,
    });
    this.registrations.set(id, token);

    const uri = this.foreignURI
      ? `https://elsewhere.example/register/${id}`
      : `${this.url}/register/${id}`;

    return json(response, 201, {
      ...metadata,
      client_id: id,
      ...(secret ? { client_secret: secret } : {}),
      registration_access_token: token,
      registration_client_uri: uri,
    });
  }

  registration(request, response, id, text) {
    if (request.method === "GET") this.registrationReads += 1;

    const held = this.registrations.get(id);
    const client = this.clients.get(id);

    if (!held || request.headers.authorization !== `Bearer ${held}`) {
      return oauthError(response, 401, "invalid_token");
    }

    if (request.method === "DELETE") {
      if (this.registrationDown) {
        return oauthError(response, 503, "temporarily_unavailable");
      }

      this.registrations.delete(id);
      this.clients.delete(id);
      response.writeHead(204);
      return response.end();
    }

    if (request.method === "PUT") {
      const metadata = JSON.parse(text || "{}");
      client.scope = metadata.scope;

      return json(response, 200, { ...metadata, client_id: id });
    }

    return json(response, 200, {
      client_id: id,
      token_endpoint_auth_method: client.method,
      scope: client.scope,
    });
  }
}
