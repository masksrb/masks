SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: actors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.actors (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    nickname character varying NOT NULL,
    name character varying,
    email character varying,
    password_digest character varying,
    scopes text DEFAULT ''::text NOT NULL,
    otp_secret text,
    otp_enabled_at timestamp(6) without time zone,
    email_verified_at timestamp(6) without time zone,
    last_login_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    given_name character varying,
    family_name character varying,
    middle_name character varying,
    profile_url character varying,
    picture_url character varying,
    website_url character varying,
    gender character varying,
    birthdate character varying,
    zoneinfo character varying,
    locale character varying,
    backup_code_digests jsonb DEFAULT '[]'::jsonb NOT NULL,
    backup_codes_generated_at timestamp(6) without time zone,
    activated_at timestamp(6) without time zone,
    webauthn_id character varying
);

ALTER TABLE ONLY public.actors FORCE ROW LEVEL SECURITY;


--
-- Name: actors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.actors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: actors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.actors_id_seq OWNED BY public.actors.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: authenticators; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.authenticators (
    id bigint NOT NULL,
    aaguid character varying NOT NULL,
    name character varying NOT NULL,
    source character varying NOT NULL,
    icon text,
    certification character varying,
    statuses jsonb DEFAULT '[]'::jsonb NOT NULL,
    compromised_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: authenticators_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.authenticators_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: authenticators_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.authenticators_id_seq OWNED BY public.authenticators.id;


--
-- Name: avatars; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.avatars (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    actor_id bigint NOT NULL,
    content_type character varying NOT NULL,
    digest character varying NOT NULL,
    byte_size integer NOT NULL,
    data bytea NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.avatars FORCE ROW LEVEL SECURITY;


--
-- Name: avatars_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.avatars_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: avatars_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.avatars_id_seq OWNED BY public.avatars.id;


--
-- Name: clients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clients (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    client_id character varying NOT NULL,
    secret_digest character varying,
    name character varying NOT NULL,
    redirect_uris jsonb DEFAULT '[]'::jsonb NOT NULL,
    grant_types jsonb DEFAULT '["authorization_code"]'::jsonb NOT NULL,
    response_types jsonb DEFAULT '["code"]'::jsonb NOT NULL,
    resources jsonb DEFAULT '[]'::jsonb NOT NULL,
    allowed_scopes text DEFAULT ''::text NOT NULL,
    token_endpoint_auth_method character varying DEFAULT 'client_secret_basic'::character varying NOT NULL,
    application_type character varying DEFAULT 'web'::character varying NOT NULL,
    client_uri character varying,
    logo_uri character varying,
    tos_uri character varying,
    policy_uri character varying,
    dynamic boolean DEFAULT false NOT NULL,
    registration_token_digest character varying,
    secret_expires_at timestamp(6) without time zone,
    archived_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    approved_at timestamp(6) without time zone,
    approved_by_id bigint,
    required_scopes text DEFAULT ''::text NOT NULL,
    post_logout_redirect_uris jsonb DEFAULT '[]'::jsonb NOT NULL,
    backchannel_logout_uri character varying,
    backchannel_logout_session_required boolean DEFAULT false NOT NULL
);

ALTER TABLE ONLY public.clients FORCE ROW LEVEL SECURITY;


--
-- Name: clients_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.clients_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: clients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.clients_id_seq OWNED BY public.clients.id;


--
-- Name: connections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.connections (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    provider_id bigint NOT NULL,
    actor_id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    subject character varying NOT NULL,
    label character varying,
    scopes text DEFAULT ''::text NOT NULL,
    refresh_token text,
    access_token text,
    access_token_expires_at timestamp(6) without time zone,
    connected_at timestamp(6) without time zone,
    revoked_at timestamp(6) without time zone,
    revoked_reason character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    email character varying,
    email_verified boolean DEFAULT false NOT NULL,
    signed_in_at timestamp(6) without time zone
);

ALTER TABLE ONLY public.connections FORCE ROW LEVEL SECURITY;


--
-- Name: connections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.connections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: connections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.connections_id_seq OWNED BY public.connections.id;


--
-- Name: consents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.consents (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    actor_id bigint NOT NULL,
    client_id bigint NOT NULL,
    scopes text DEFAULT ''::text NOT NULL,
    audience jsonb DEFAULT '[]'::jsonb NOT NULL,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.consents FORCE ROW LEVEL SECURITY;


--
-- Name: consents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.consents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: consents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.consents_id_seq OWNED BY public.consents.id;


--
-- Name: device_factors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.device_factors (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    device_id bigint NOT NULL,
    actor_id bigint NOT NULL,
    factor character varying NOT NULL,
    satisfied_at timestamp(6) without time zone NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.device_factors FORCE ROW LEVEL SECURITY;


--
-- Name: device_factors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.device_factors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: device_factors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.device_factors_id_seq OWNED BY public.device_factors.id;


--
-- Name: devices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.devices (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    public_id character varying NOT NULL,
    version character varying NOT NULL,
    name character varying,
    user_agent character varying,
    ip_address character varying,
    last_seen_at timestamp(6) without time zone NOT NULL,
    blocked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.devices FORCE ROW LEVEL SECURITY;


--
-- Name: devices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.devices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: devices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.devices_id_seq OWNED BY public.devices.id;


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    actor_id bigint,
    by_id bigint,
    client_id bigint,
    device_id bigint,
    action character varying NOT NULL,
    ip_address character varying,
    user_agent character varying,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.events FORCE ROW LEVEL SECURITY;


--
-- Name: events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.events_id_seq OWNED BY public.events.id;


--
-- Name: namespaces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.namespaces (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    client_id bigint,
    name character varying NOT NULL,
    resource character varying NOT NULL,
    claimed_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.namespaces FORCE ROW LEVEL SECURITY;


--
-- Name: namespaces_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.namespaces_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: namespaces_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.namespaces_id_seq OWNED BY public.namespaces.id;


--
-- Name: passkeys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.passkeys (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    actor_id bigint NOT NULL,
    name character varying,
    external_id character varying NOT NULL,
    public_key text NOT NULL,
    sign_count bigint DEFAULT 0 NOT NULL,
    aaguid character varying,
    discoverable boolean DEFAULT false NOT NULL,
    user_verified boolean DEFAULT false NOT NULL,
    last_used_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.passkeys FORCE ROW LEVEL SECURITY;


--
-- Name: passkeys_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.passkeys_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: passkeys_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.passkeys_id_seq OWNED BY public.passkeys.id;


--
-- Name: providers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.providers (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    key character varying NOT NULL,
    name character varying NOT NULL,
    authorization_url character varying NOT NULL,
    token_url character varying NOT NULL,
    revocation_url character varying,
    userinfo_url character varying,
    client_id character varying NOT NULL,
    client_secret text,
    scopes text DEFAULT ''::text NOT NULL,
    authorize_params jsonb DEFAULT '{}'::jsonb NOT NULL,
    subject_claim character varying DEFAULT 'sub'::character varying NOT NULL,
    label_claim character varying DEFAULT 'email'::character varying NOT NULL,
    archived_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    issuer character varying,
    jwks_uri character varying,
    jwks jsonb DEFAULT '{}'::jsonb NOT NULL,
    jwks_fetched_at timestamp(6) without time zone,
    signs_in boolean DEFAULT false NOT NULL,
    provisions boolean DEFAULT false NOT NULL,
    email_domains text DEFAULT ''::text NOT NULL,
    signup_scopes text DEFAULT ''::text NOT NULL
);

ALTER TABLE ONLY public.providers FORCE ROW LEVEL SECURITY;


--
-- Name: providers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.providers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: providers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.providers_id_seq OWNED BY public.providers.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    actor_id bigint NOT NULL,
    digest character varying NOT NULL,
    user_agent character varying,
    ip_address character varying,
    authenticated_at timestamp(6) without time zone NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    amr jsonb DEFAULT '[]'::jsonb NOT NULL,
    device_id bigint,
    device_version character varying,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    origin character varying
);

ALTER TABLE ONLY public.sessions FORCE ROW LEVEL SECURITY;


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: signing_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.signing_keys (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    kid character varying NOT NULL,
    algorithm character varying DEFAULT 'RS256'::character varying NOT NULL,
    private_pem text NOT NULL,
    public_jwk jsonb NOT NULL,
    activated_at timestamp(6) without time zone,
    retired_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);

ALTER TABLE ONLY public.signing_keys FORCE ROW LEVEL SECURITY;


--
-- Name: signing_keys_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.signing_keys_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: signing_keys_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.signing_keys_id_seq OWNED BY public.signing_keys.id;


--
-- Name: tenants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenants (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    subdomain character varying NOT NULL,
    name character varying NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    archived_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    dynamic_client_scopes text
);


--
-- Name: tenants_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tenants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tenants_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tenants_id_seq OWNED BY public.tenants.id;


--
-- Name: tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tokens (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    type character varying NOT NULL,
    actor_id bigint,
    client_id bigint,
    parent_id bigint,
    digest character varying NOT NULL,
    scopes text DEFAULT ''::text NOT NULL,
    audience jsonb DEFAULT '[]'::jsonb NOT NULL,
    redirect_uri character varying,
    nonce character varying,
    code_challenge character varying,
    code_challenge_method character varying,
    expires_at timestamp(6) without time zone NOT NULL,
    consumed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    authenticated_at timestamp(6) without time zone,
    requested_claims jsonb,
    payload jsonb,
    device_id bigint,
    session_id bigint
);

ALTER TABLE ONLY public.tokens FORCE ROW LEVEL SECURITY;


--
-- Name: tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tokens_id_seq OWNED BY public.tokens.id;


--
-- Name: actors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actors ALTER COLUMN id SET DEFAULT nextval('public.actors_id_seq'::regclass);


--
-- Name: authenticators id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.authenticators ALTER COLUMN id SET DEFAULT nextval('public.authenticators_id_seq'::regclass);


--
-- Name: avatars id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.avatars ALTER COLUMN id SET DEFAULT nextval('public.avatars_id_seq'::regclass);


--
-- Name: clients id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients ALTER COLUMN id SET DEFAULT nextval('public.clients_id_seq'::regclass);


--
-- Name: connections id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connections ALTER COLUMN id SET DEFAULT nextval('public.connections_id_seq'::regclass);


--
-- Name: consents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consents ALTER COLUMN id SET DEFAULT nextval('public.consents_id_seq'::regclass);


--
-- Name: device_factors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_factors ALTER COLUMN id SET DEFAULT nextval('public.device_factors_id_seq'::regclass);


--
-- Name: devices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices ALTER COLUMN id SET DEFAULT nextval('public.devices_id_seq'::regclass);


--
-- Name: events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events ALTER COLUMN id SET DEFAULT nextval('public.events_id_seq'::regclass);


--
-- Name: namespaces id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.namespaces ALTER COLUMN id SET DEFAULT nextval('public.namespaces_id_seq'::regclass);


--
-- Name: passkeys id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.passkeys ALTER COLUMN id SET DEFAULT nextval('public.passkeys_id_seq'::regclass);


--
-- Name: providers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.providers ALTER COLUMN id SET DEFAULT nextval('public.providers_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: signing_keys id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signing_keys ALTER COLUMN id SET DEFAULT nextval('public.signing_keys_id_seq'::regclass);


--
-- Name: tenants id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants ALTER COLUMN id SET DEFAULT nextval('public.tenants_id_seq'::regclass);


--
-- Name: tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens ALTER COLUMN id SET DEFAULT nextval('public.tokens_id_seq'::regclass);


--
-- Name: actors actors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actors
    ADD CONSTRAINT actors_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: authenticators authenticators_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.authenticators
    ADD CONSTRAINT authenticators_pkey PRIMARY KEY (id);


--
-- Name: avatars avatars_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.avatars
    ADD CONSTRAINT avatars_pkey PRIMARY KEY (id);


--
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);


--
-- Name: connections connections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connections
    ADD CONSTRAINT connections_pkey PRIMARY KEY (id);


--
-- Name: consents consents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consents
    ADD CONSTRAINT consents_pkey PRIMARY KEY (id);


--
-- Name: device_factors device_factors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_factors
    ADD CONSTRAINT device_factors_pkey PRIMARY KEY (id);


--
-- Name: devices devices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: namespaces namespaces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.namespaces
    ADD CONSTRAINT namespaces_pkey PRIMARY KEY (id);


--
-- Name: passkeys passkeys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.passkeys
    ADD CONSTRAINT passkeys_pkey PRIMARY KEY (id);


--
-- Name: providers providers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.providers
    ADD CONSTRAINT providers_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: signing_keys signing_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signing_keys
    ADD CONSTRAINT signing_keys_pkey PRIMARY KEY (id);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


--
-- Name: tokens tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT tokens_pkey PRIMARY KEY (id);


--
-- Name: index_actors_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actors_on_tenant_id ON public.actors USING btree (tenant_id);


--
-- Name: index_actors_on_tenant_id_and_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actors_on_tenant_id_and_email ON public.actors USING btree (tenant_id, email);


--
-- Name: index_actors_on_tenant_id_and_nickname; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_actors_on_tenant_id_and_nickname ON public.actors USING btree (tenant_id, nickname);


--
-- Name: index_actors_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_actors_on_uuid ON public.actors USING btree (uuid);


--
-- Name: index_authenticators_on_aaguid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_authenticators_on_aaguid ON public.authenticators USING btree (aaguid);


--
-- Name: index_avatars_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_avatars_on_actor_id ON public.avatars USING btree (actor_id);


--
-- Name: index_avatars_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_avatars_on_tenant_id ON public.avatars USING btree (tenant_id);


--
-- Name: index_avatars_on_tenant_id_and_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_avatars_on_tenant_id_and_actor_id ON public.avatars USING btree (tenant_id, actor_id);


--
-- Name: index_clients_on_approved_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_clients_on_approved_by_id ON public.clients USING btree (approved_by_id);


--
-- Name: index_clients_on_registration_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_clients_on_registration_token_digest ON public.clients USING btree (registration_token_digest);


--
-- Name: index_clients_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_clients_on_tenant_id ON public.clients USING btree (tenant_id);


--
-- Name: index_clients_on_tenant_id_and_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_clients_on_tenant_id_and_client_id ON public.clients USING btree (tenant_id, client_id);


--
-- Name: index_connections_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connections_on_actor_id ON public.connections USING btree (actor_id);


--
-- Name: index_connections_on_provider_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connections_on_provider_id ON public.connections USING btree (provider_id);


--
-- Name: index_connections_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connections_on_tenant_id ON public.connections USING btree (tenant_id);


--
-- Name: index_connections_on_tenant_id_and_provider_id_and_subject; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_connections_on_tenant_id_and_provider_id_and_subject ON public.connections USING btree (tenant_id, provider_id, subject);


--
-- Name: index_connections_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_connections_on_uuid ON public.connections USING btree (uuid);


--
-- Name: index_consents_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_consents_on_actor_id ON public.consents USING btree (actor_id);


--
-- Name: index_consents_on_actor_id_and_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_consents_on_actor_id_and_client_id ON public.consents USING btree (actor_id, client_id);


--
-- Name: index_consents_on_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_consents_on_client_id ON public.consents USING btree (client_id);


--
-- Name: index_consents_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_consents_on_tenant_id ON public.consents USING btree (tenant_id);


--
-- Name: index_device_factors_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_device_factors_on_actor_id ON public.device_factors USING btree (actor_id);


--
-- Name: index_device_factors_on_device_and_actor_and_factor; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_device_factors_on_device_and_actor_and_factor ON public.device_factors USING btree (device_id, actor_id, factor);


--
-- Name: index_device_factors_on_device_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_device_factors_on_device_id ON public.device_factors USING btree (device_id);


--
-- Name: index_device_factors_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_device_factors_on_tenant_id ON public.device_factors USING btree (tenant_id);


--
-- Name: index_devices_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_devices_on_tenant_id ON public.devices USING btree (tenant_id);


--
-- Name: index_devices_on_tenant_id_and_last_seen_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_devices_on_tenant_id_and_last_seen_at ON public.devices USING btree (tenant_id, last_seen_at);


--
-- Name: index_devices_on_tenant_id_and_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_devices_on_tenant_id_and_public_id ON public.devices USING btree (tenant_id, public_id);


--
-- Name: index_events_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_actor_id ON public.events USING btree (actor_id);


--
-- Name: index_events_on_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_by_id ON public.events USING btree (by_id);


--
-- Name: index_events_on_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_client_id ON public.events USING btree (client_id);


--
-- Name: index_events_on_device_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_device_id ON public.events USING btree (device_id);


--
-- Name: index_events_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_tenant_id ON public.events USING btree (tenant_id);


--
-- Name: index_events_on_tenant_id_and_action_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_tenant_id_and_action_and_created_at ON public.events USING btree (tenant_id, action, created_at);


--
-- Name: index_events_on_tenant_id_and_actor_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_tenant_id_and_actor_id_and_created_at ON public.events USING btree (tenant_id, actor_id, created_at);


--
-- Name: index_events_on_tenant_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_tenant_id_and_created_at ON public.events USING btree (tenant_id, created_at);


--
-- Name: index_namespaces_on_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_namespaces_on_client_id ON public.namespaces USING btree (client_id);


--
-- Name: index_namespaces_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_namespaces_on_tenant_id ON public.namespaces USING btree (tenant_id);


--
-- Name: index_namespaces_on_tenant_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_namespaces_on_tenant_id_and_name ON public.namespaces USING btree (tenant_id, name);


--
-- Name: index_namespaces_on_tenant_id_and_resource; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_namespaces_on_tenant_id_and_resource ON public.namespaces USING btree (tenant_id, resource);


--
-- Name: index_passkeys_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_passkeys_on_actor_id ON public.passkeys USING btree (actor_id);


--
-- Name: index_passkeys_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_passkeys_on_tenant_id ON public.passkeys USING btree (tenant_id);


--
-- Name: index_passkeys_on_tenant_id_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_passkeys_on_tenant_id_and_external_id ON public.passkeys USING btree (tenant_id, external_id);


--
-- Name: index_providers_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_providers_on_tenant_id ON public.providers USING btree (tenant_id);


--
-- Name: index_providers_on_tenant_id_and_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_providers_on_tenant_id_and_key ON public.providers USING btree (tenant_id, key);


--
-- Name: index_providers_on_tenant_id_and_signs_in; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_providers_on_tenant_id_and_signs_in ON public.providers USING btree (tenant_id, signs_in);


--
-- Name: index_sessions_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_actor_id ON public.sessions USING btree (actor_id);


--
-- Name: index_sessions_on_device_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_device_id ON public.sessions USING btree (device_id);


--
-- Name: index_sessions_on_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sessions_on_digest ON public.sessions USING btree (digest);


--
-- Name: index_sessions_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_tenant_id ON public.sessions USING btree (tenant_id);


--
-- Name: index_sessions_on_tenant_id_and_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sessions_on_tenant_id_and_uuid ON public.sessions USING btree (tenant_id, uuid);


--
-- Name: index_signing_keys_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_signing_keys_on_tenant_id ON public.signing_keys USING btree (tenant_id);


--
-- Name: index_signing_keys_on_tenant_id_and_activated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_signing_keys_on_tenant_id_and_activated_at ON public.signing_keys USING btree (tenant_id, activated_at);


--
-- Name: index_signing_keys_on_tenant_id_and_kid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_signing_keys_on_tenant_id_and_kid ON public.signing_keys USING btree (tenant_id, kid);


--
-- Name: index_tenants_on_subdomain; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tenants_on_subdomain ON public.tenants USING btree (subdomain);


--
-- Name: index_tenants_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tenants_on_uuid ON public.tenants USING btree (uuid);


--
-- Name: index_tokens_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tokens_on_actor_id ON public.tokens USING btree (actor_id);


--
-- Name: index_tokens_on_client_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tokens_on_client_id ON public.tokens USING btree (client_id);


--
-- Name: index_tokens_on_device_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tokens_on_device_id ON public.tokens USING btree (device_id);


--
-- Name: index_tokens_on_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tokens_on_digest ON public.tokens USING btree (digest);


--
-- Name: index_tokens_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tokens_on_parent_id ON public.tokens USING btree (parent_id);


--
-- Name: index_tokens_on_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tokens_on_session_id ON public.tokens USING btree (session_id);


--
-- Name: index_tokens_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tokens_on_tenant_id ON public.tokens USING btree (tenant_id);


--
-- Name: index_tokens_on_tenant_id_and_type_and_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tokens_on_tenant_id_and_type_and_expires_at ON public.tokens USING btree (tenant_id, type, expires_at);


--
-- Name: actors fk_rails_06ef63a7f5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actors
    ADD CONSTRAINT fk_rails_06ef63a7f5 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: consents fk_rails_0cc92e64df; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consents
    ADD CONSTRAINT fk_rails_0cc92e64df FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: tokens fk_rails_16bf6d7922; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT fk_rails_16bf6d7922 FOREIGN KEY (parent_id) REFERENCES public.tokens(id);


--
-- Name: clients fk_rails_1a30f4383b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT fk_rails_1a30f4383b FOREIGN KEY (approved_by_id) REFERENCES public.actors(id);


--
-- Name: avatars fk_rails_1ba249dc92; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.avatars
    ADD CONSTRAINT fk_rails_1ba249dc92 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: events fk_rails_2c515e778f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_2c515e778f FOREIGN KEY (actor_id) REFERENCES public.actors(id) ON DELETE SET NULL;


--
-- Name: tokens fk_rails_3bbe3ff1e4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT fk_rails_3bbe3ff1e4 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: device_factors fk_rails_3f98713d06; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_factors
    ADD CONSTRAINT fk_rails_3f98713d06 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: connections fk_rails_4234ab53d1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connections
    ADD CONSTRAINT fk_rails_4234ab53d1 FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: clients fk_rails_4904dbddb8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT fk_rails_4904dbddb8 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: sessions fk_rails_4cc5d929b0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_4cc5d929b0 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: device_factors fk_rails_4ed392263f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_factors
    ADD CONSTRAINT fk_rails_4ed392263f FOREIGN KEY (device_id) REFERENCES public.devices(id);


--
-- Name: namespaces fk_rails_55d81b81ab; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.namespaces
    ADD CONSTRAINT fk_rails_55d81b81ab FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE SET NULL;


--
-- Name: connections fk_rails_6314b09676; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connections
    ADD CONSTRAINT fk_rails_6314b09676 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: sessions fk_rails_6473050c7b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_6473050c7b FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: consents fk_rails_657cd4331e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consents
    ADD CONSTRAINT fk_rails_657cd4331e FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: events fk_rails_6844d4946c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_6844d4946c FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: events fk_rails_6a6456eb31; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_6a6456eb31 FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE SET NULL;


--
-- Name: tokens fk_rails_759b47e63a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT fk_rails_759b47e63a FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: device_factors fk_rails_75a75fd1e0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_factors
    ADD CONSTRAINT fk_rails_75a75fd1e0 FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: namespaces fk_rails_78573ee4be; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.namespaces
    ADD CONSTRAINT fk_rails_78573ee4be FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: passkeys fk_rails_79adc8e12d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.passkeys
    ADD CONSTRAINT fk_rails_79adc8e12d FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: tokens fk_rails_86c4a10c3c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT fk_rails_86c4a10c3c FOREIGN KEY (client_id) REFERENCES public.clients(id);


--
-- Name: events fk_rails_96944fe3ef; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_96944fe3ef FOREIGN KEY (by_id) REFERENCES public.actors(id) ON DELETE SET NULL;


--
-- Name: connections fk_rails_a26555371d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connections
    ADD CONSTRAINT fk_rails_a26555371d FOREIGN KEY (provider_id) REFERENCES public.providers(id);


--
-- Name: sessions fk_rails_aec6d92ac2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_aec6d92ac2 FOREIGN KEY (device_id) REFERENCES public.devices(id);


--
-- Name: providers fk_rails_ba1a501ef5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.providers
    ADD CONSTRAINT fk_rails_ba1a501ef5 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: signing_keys fk_rails_bb7b6b543d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signing_keys
    ADD CONSTRAINT fk_rails_bb7b6b543d FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: passkeys fk_rails_bd872fde15; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.passkeys
    ADD CONSTRAINT fk_rails_bd872fde15 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: avatars fk_rails_c4fab594a7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.avatars
    ADD CONSTRAINT fk_rails_c4fab594a7 FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: devices fk_rails_d5b7012cbc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT fk_rails_d5b7012cbc FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: events fk_rails_e77ed48c6c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_e77ed48c6c FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE SET NULL;


--
-- Name: consents fk_rails_eb0bd2c006; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consents
    ADD CONSTRAINT fk_rails_eb0bd2c006 FOREIGN KEY (client_id) REFERENCES public.clients(id);


--
-- Name: tokens fk_rails_f809e5293f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT fk_rails_f809e5293f FOREIGN KEY (device_id) REFERENCES public.devices(id);


--
-- Name: tokens fk_rails_fc9481b3fa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT fk_rails_fc9481b3fa FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE SET NULL;


--
-- Name: actors; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.actors ENABLE ROW LEVEL SECURITY;

--
-- Name: avatars; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.avatars ENABLE ROW LEVEL SECURITY;

--
-- Name: clients; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;

--
-- Name: connections; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.connections ENABLE ROW LEVEL SECURITY;

--
-- Name: consents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.consents ENABLE ROW LEVEL SECURITY;

--
-- Name: device_factors; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.device_factors ENABLE ROW LEVEL SECURITY;

--
-- Name: devices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;

--
-- Name: events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

--
-- Name: namespaces; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.namespaces ENABLE ROW LEVEL SECURITY;

--
-- Name: passkeys; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.passkeys ENABLE ROW LEVEL SECURITY;

--
-- Name: providers; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.providers ENABLE ROW LEVEL SECURITY;

--
-- Name: sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: signing_keys; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.signing_keys ENABLE ROW LEVEL SECURITY;

--
-- Name: actors tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.actors USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


--
-- Name: avatars tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.avatars USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


--
-- Name: clients tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.clients USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


--
-- Name: connections tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.connections USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


--
-- Name: consents tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.consents USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


--
-- Name: device_factors tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.device_factors USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


--
-- Name: devices tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.devices USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


--
-- Name: events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.events USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


--
-- Name: namespaces tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.namespaces USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


--
-- Name: passkeys tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.passkeys USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


--
-- Name: providers tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.providers USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


--
-- Name: sessions tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.sessions USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


--
-- Name: signing_keys tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.signing_keys USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


--
-- Name: tokens tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.tokens USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


--
-- Name: tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tokens ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260906000003'),
('20260906000002'),
('20260906000001'),
('20260905000004'),
('20260905000003'),
('20260905000002'),
('20260905000001'),
('20260904000003'),
('20260904000002'),
('20260904000001'),
('20260902000001'),
('20260901120002'),
('20260901120001'),
('20260901120000'),
('20260901090000'),
('20260831150000'),
('20260831140000'),
('20260831120000'),
('20260830210000'),
('20260830150000'),
('20260830120000'),
('20260829100008'),
('20260829100007'),
('20260829100006'),
('20260829100005'),
('20260829100004'),
('20260829100003'),
('20260829100002'),
('20260829100001');

