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
    backup_codes_generated_at timestamp(6) without time zone
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
    post_logout_redirect_uris jsonb DEFAULT '[]'::jsonb NOT NULL
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
    updated_at timestamp(6) without time zone NOT NULL
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
    payload jsonb
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
-- Name: clients id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients ALTER COLUMN id SET DEFAULT nextval('public.clients_id_seq'::regclass);


--
-- Name: consents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consents ALTER COLUMN id SET DEFAULT nextval('public.consents_id_seq'::regclass);


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
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);


--
-- Name: consents consents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consents
    ADD CONSTRAINT consents_pkey PRIMARY KEY (id);


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
-- Name: index_sessions_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_actor_id ON public.sessions USING btree (actor_id);


--
-- Name: index_sessions_on_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sessions_on_digest ON public.sessions USING btree (digest);


--
-- Name: index_sessions_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_tenant_id ON public.sessions USING btree (tenant_id);


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
-- Name: index_tokens_on_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tokens_on_digest ON public.tokens USING btree (digest);


--
-- Name: index_tokens_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tokens_on_parent_id ON public.tokens USING btree (parent_id);


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
-- Name: tokens fk_rails_3bbe3ff1e4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT fk_rails_3bbe3ff1e4 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


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
-- Name: tokens fk_rails_759b47e63a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT fk_rails_759b47e63a FOREIGN KEY (actor_id) REFERENCES public.actors(id);


--
-- Name: tokens fk_rails_86c4a10c3c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT fk_rails_86c4a10c3c FOREIGN KEY (client_id) REFERENCES public.clients(id);


--
-- Name: signing_keys fk_rails_bb7b6b543d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signing_keys
    ADD CONSTRAINT fk_rails_bb7b6b543d FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: consents fk_rails_eb0bd2c006; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.consents
    ADD CONSTRAINT fk_rails_eb0bd2c006 FOREIGN KEY (client_id) REFERENCES public.clients(id);


--
-- Name: actors; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.actors ENABLE ROW LEVEL SECURITY;

--
-- Name: clients; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;

--
-- Name: consents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.consents ENABLE ROW LEVEL SECURITY;

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
-- Name: clients tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.clients USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


--
-- Name: consents tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.consents USING ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint)) WITH CHECK ((tenant_id = (NULLIF(current_setting('masks.tenant_id'::text, true), ''::text))::bigint));


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

