export interface Tenant {
  uuid?: string;
  subdomain?: string;
  name?: string;
}

export type AvatarStyle = "photo" | "identicon" | "initials";

export interface Avatars {
  photo: string | null;
  identicon: string;
  initials: string;
}

export interface Account {
  signed_in: boolean;
  subject?: string;
  name?: string;
  nickname?: string;
  email?: string;
  email_verified?: boolean;
  picture?: string;
  avatars?: Avatars;
  tenant?: Tenant;
  scopes: string[];
  expires_at?: number;
}

export interface Refusal {
  signed_in: false;
  error: "login_required" | "handshake_required" | string;
  login_url?: string;
  handshake_url?: string;
}

export type Status =
  | { state: "signed_in"; account: Account }
  | { state: "signed_out"; loginUrl: string }
  | { state: "handshake_required"; handshakeUrl: string };

export interface Claims {
  [claim: string]: unknown;
}

export interface Tokens {
  access_token: string;
  id_token?: string;
  refresh_token?: string;
  token_type: string;
  scope: string;
  expires_in: number;
  obtained_at: number;
}

export interface Discovery {
  issuer: string;
  authorization_endpoint: string;
  token_endpoint: string;
  userinfo_endpoint?: string;
  avatar_endpoint?: string;
  avatar_styles_supported?: AvatarStyle[];
  avatar_sizes_supported?: number[];
  jwks_uri?: string;
  revocation_endpoint?: string;
  end_session_endpoint?: string;
  tenant?: Tenant;
  [claim: string]: unknown;
}

export class MasksError extends Error {
  readonly code: string;
  readonly description?: string;
  readonly status?: number;

  constructor(code: string, description?: string, status?: number) {
    super(description ? `${code}: ${description}` : code);

    this.name = "MasksError";
    this.code = code;
    this.description = description;
    this.status = status;
  }
}
