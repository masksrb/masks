export interface Tenant {
  uuid?: string;
  subdomain?: string;
  name?: string;
}

export interface Account {
  signed_in: boolean;
  subject?: string;
  name?: string;
  nickname?: string;
  email?: string;
  email_verified?: boolean;
  tenant?: Tenant;
  scopes: string[];
  expires_at?: number;
}

export interface Refusal {
  signed_in: false;
  error: string;
  login_url: string;
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
