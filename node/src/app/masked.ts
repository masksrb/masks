import {
  type Avatars,
  avatarsOf,
  member,
  type Organization,
  organizationOf,
  organizationsOf,
  pictureOf,
} from "../claims.js";
import type { Tenant } from "../issuer.js";
import type { Privilege, Privileges } from "./privileges.js";

export interface MaskedOptions {
  claims?: Record<string, unknown>;
  scopes?: string[];
  signedIn: boolean;
  privileges: Privileges;
  accessToken?: string;
  tokenType?: string;
  expiresAt?: number;
  accountURL?: string;
  avatarURL?: string;
}

export interface MaskedJSON {
  signed_in: boolean;
  subject?: string;
  name?: string;
  nickname?: string;
  email?: string;
  email_verified?: boolean;
  picture?: string;
  avatar_url?: string;
  avatars?: Avatars;
  tenant?: Tenant;
  organization?: Organization;
  organizations?: Organization[];
  scopes: string[];
  privileges: string[];
  expires_at?: number;
  account_url?: string;
}

export class Masked {
  readonly signedIn: boolean;
  readonly claims: Readonly<Record<string, unknown>>;
  readonly scopes: readonly string[];
  readonly expiresAt?: number;
  readonly accountURL?: string;
  readonly avatarURL?: string;
  readonly #privileges: Privileges;
  readonly #accessToken?: string;
  readonly #tokenType?: string;

  constructor(options: MaskedOptions) {
    this.signedIn = options.signedIn;
    this.claims = Object.freeze({ ...(options.claims ?? {}) });
    this.scopes = Object.freeze([...(options.scopes ?? [])]);
    this.expiresAt = options.expiresAt;
    this.accountURL = options.accountURL;
    this.avatarURL = options.avatarURL;
    this.#privileges = options.privileges;
    this.#accessToken = options.accessToken;
    this.#tokenType = options.tokenType;
  }

  static nobody(privileges: Privileges): Masked {
    return new Masked({ signedIn: false, privileges });
  }

  get accessToken(): string | undefined {
    return this.signedIn ? this.#accessToken : undefined;
  }

  get authorization(): string | undefined {
    const token = this.accessToken;

    return token ? `${this.#tokenType ?? "Bearer"} ${token}` : undefined;
  }

  claim(name: string): unknown {
    return this.claims[name];
  }

  get subject(): string | undefined {
    return text(this.claims.sub);
  }

  get name(): string | undefined {
    return text(this.claims.name);
  }

  get nickname(): string | undefined {
    return text(this.claims.preferred_username);
  }

  get email(): string | undefined {
    return text(this.claims.email);
  }

  get emailVerified(): boolean {
    return this.claims.email_verified === true;
  }

  get picture(): string | undefined {
    return pictureOf(this.claims);
  }

  get avatars(): Avatars {
    return avatarsOf(this.claims);
  }

  get tenant(): Tenant | undefined {
    const held = this.claims.tenant;

    return held && typeof held === "object" ? (held as Tenant) : undefined;
  }

  get organization(): Organization | undefined {
    return organizationOf(this.claims);
  }

  get organizations(): Organization[] {
    return organizationsOf(this.claims);
  }

  role(...roles: string[]): boolean {
    const held = this.organization;

    return !!held && roles.flat().includes(held.role);
  }

  permits(scope: string): boolean {
    return this.scopes.includes(scope);
  }

  get privileges(): string[] {
    if (!this.signedIn) return [];

    return this.#privileges
      .all()
      .filter((privilege) => this.holds(privilege))
      .map((privilege) => privilege.name);
  }

  privilege(...names: string[]): boolean {
    const wanted = names.flat().map((name) => this.#privileges.get(name));

    return this.signedIn && wanted.every((privilege) => this.holds(privilege));
  }

  holds(privilege: Privilege | string): boolean {
    const held =
      typeof privilege === "string"
        ? this.#privileges.get(privilege)
        : privilege;

    if (!held.scopes.every((scope) => this.scopes.includes(scope)))
      return false;

    try {
      this.member(held);
      return true;
    } catch {
      return false;
    }
  }

  member(privilege: Privilege | string): Organization | undefined {
    const held =
      typeof privilege === "string"
        ? this.#privileges.get(privilege)
        : privilege;

    if (held.roles.length === 0 && held.organization === undefined) {
      return undefined;
    }

    return member(this.claims, held.roles, held.organization);
  }

  toJSON(): MaskedJSON {
    const avatars = this.avatars;
    const organizations = this.organizations;
    const answer: MaskedJSON = {
      signed_in: this.signedIn,
      subject: this.subject,
      name: this.name,
      nickname: this.nickname,
      email: this.email,
      email_verified:
        typeof this.claims.email_verified === "boolean"
          ? this.claims.email_verified
          : undefined,
      picture: this.picture,
      avatar_url: avatars.photo ? this.avatarURL : undefined,
      avatars: Object.keys(avatars).length > 0 ? avatars : undefined,
      tenant: this.tenant,
      organization: this.organization,
      organizations: organizations.length > 0 ? organizations : undefined,
      scopes: [...this.scopes],
      privileges: this.privileges,
      expires_at: this.expiresAt,
      account_url: this.accountURL,
    };

    return Object.fromEntries(
      Object.entries(answer).filter(([, value]) => value !== undefined),
    ) as unknown as MaskedJSON;
  }
}

function text(value: unknown): string | undefined {
  return typeof value === "string" && value !== "" ? value : undefined;
}
