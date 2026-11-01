FAILURES: dict[str, tuple[str, str]] = {
    "no_token": (
        "invalid_token",
        "the request carries no token",
    ),
    "not_a_jwt": (
        "invalid_token",
        "that token is not a signed JWT",
    ),
    "no_key": (
        "invalid_token",
        "{} publishes no key {}",
    ),
    "not_signed_by": (
        "invalid_token",
        "that token was not signed by {}",
    ),
    "not_an_algorithm": (
        "invalid_token",
        "{} is not an algorithm masks signs with",
    ),
    "wrong_type": (
        "invalid_token",
        "that token is typed {}, not {}",
    ),
    "expired": (
        "invalid_token",
        "that token has expired",
    ),
    "not_valid_yet": (
        "invalid_token",
        "that token is not valid yet",
    ),
    "issued_in_future": (
        "invalid_token",
        "that token was issued in the future",
    ),
    "other_issuer": (
        "invalid_token",
        "that token was issued by another server",
    ),
    "other_audience": (
        "invalid_token",
        "that token was issued for another app",
    ),
    "missing_claims": (
        "invalid_token",
        "that token is missing {}",
    ),
    "unverified": (
        "invalid_token",
        "that token could not be verified",
    ),
    "too_old": (
        "invalid_token",
        "the person signed in longer ago than max_age allows",
    ),
    "bound_as_bearer": (
        "invalid_token",
        "that token is held to a key, so it is presented as DPoP with a proof",
    ),
    "unbound_as_dpop": (
        "invalid_token",
        "that token is held to no key, so it is presented as Bearer",
    ),
    "not_active": (
        "invalid_token",
        "the issuer reports this token is not active",
    ),
    "no_id_token": (
        "invalid_token",
        "the token endpoint answered without an ID token",
    ),
    "id_token_other_sign_in": (
        "invalid_token",
        "that ID token was issued for another sign-in",
    ),
    "id_token_other_client": (
        "invalid_token",
        "that ID token was issued to another client",
    ),
    "id_token_several_audiences": (
        "invalid_token",
        "that ID token names several audiences and was not issued to this client",
    ),
    "id_token_other_access_token": (
        "invalid_token",
        "that ID token was issued with another access token",
    ),
    "id_token_other_organization": (
        "invalid_token",
        "that ID token does not name the organization {}",
    ),
    "not_a_logout": (
        "invalid_token",
        "that token is not about a logout",
    ),
    "logout_names_nobody": (
        "invalid_token",
        "that logout token names neither a subject nor a session",
    ),
    "logout_with_nonce": (
        "invalid_token",
        "that logout token carries a nonce, so it is an ID token",
    ),
    "one_proof": (
        "invalid_dpop_proof",
        "exactly one DPoP proof is required",
    ),
    "proof_not_a_jwt": (
        "invalid_dpop_proof",
        "that proof is not a signed JWT",
    ),
    "proof_type": (
        "invalid_dpop_proof",
        "a proof is typed {}",
    ),
    "proof_algorithm": (
        "invalid_dpop_proof",
        "{} is not an algorithm a proof may use",
    ),
    "proof_no_key": (
        "invalid_dpop_proof",
        "a proof carries the public key that signed it",
    ),
    "proof_key_private": (
        "invalid_dpop_proof",
        "a proof key is public",
    ),
    "proof_key_unreadable": (
        "invalid_dpop_proof",
        "that proof carries a key this API cannot read",
    ),
    "proof_unsigned": (
        "invalid_dpop_proof",
        "that proof was not signed by the key it carries",
    ),
    "proof_other_key": (
        "invalid_dpop_proof",
        "that proof was signed by another key than the token is held to",
    ),
    "proof_other_token": (
        "invalid_dpop_proof",
        "that proof was made for another token",
    ),
    "proof_other_method": (
        "invalid_dpop_proof",
        "that proof was made for another method",
    ),
    "proof_other_url": (
        "invalid_dpop_proof",
        "that proof was made for another URL",
    ),
    "proof_not_now": (
        "invalid_dpop_proof",
        "that proof was not made just now",
    ),
    "proof_no_jti": (
        "invalid_dpop_proof",
        "a proof carries a jti",
    ),
    "proof_replayed": (
        "invalid_dpop_proof",
        "that proof has already been used",
    ),
    "no_scope": (
        "insufficient_scope",
        "this token does not carry {}",
    ),
    "not_granted": (
        "insufficient_scope",
        "masks did not grant {}",
    ),
    "no_privilege": (
        "insufficient_scope",
        "this account does not hold the {} privilege",
    ),
    "no_organization": (
        "insufficient_organization",
        "this sign-in names no organization",
    ),
    "other_organization": (
        "insufficient_organization",
        "this sign-in is for {}, and this needs {}",
    ),
    "other_role": (
        "insufficient_role",
        "{} in {} is not {}",
    ),
    "unreachable": (
        "temporarily_unavailable",
        "{} could not be reached",
    ),
    "keys_unreachable": (
        "temporarily_unavailable",
        "{} could not be reached for its keys",
    ),
    "replay_store_unreachable": (
        "temporarily_unavailable",
        "the replay store could not be reached",
    ),
    "replay_store_answer": (
        "temporarily_unavailable",
        "the replay store answered with something other than true or false",
    ),
    "store_unreachable": (
        "temporarily_unavailable",
        "the store could not be reached",
    ),
    "not_checked": (
        "temporarily_unavailable",
        "the token could not be checked",
    ),
    "plain_http": (
        "insecure_url",
        "plain http is allowed only on this machine: {}",
    ),
    "not_http": (
        "insecure_url",
        "{} is not an http or https URL",
    ),
    "other_origin": (
        "foreign_origin",
        "that URL belongs to another origin: {}",
    ),
    "tokens_only_for": (
        "foreign_origin",
        "tokens are held only for {}, not {}",
    ),
    "answered_status": (
        "server_error",
        "{} answered {}",
    ),
    "not_json": (
        "server_error",
        "{} answered with something other than JSON",
    ),
    "not_an_object": (
        "server_error",
        "{} answered with JSON that is not an object",
    ),
    "too_large": (
        "server_error",
        "{} answered with more than a megabyte",
    ),
    "publishes_nothing": (
        "invalid_issuer",
        "{} publishes no {}",
    ),
    "names_another": (
        "invalid_issuer",
        "{} publishes a document naming {}",
    ),
    "resource_names_another": (
        "invalid_target",
        "{} publishes metadata naming {}",
    ),
    "state_mismatch": (
        "invalid_state",
        "the state did not match the one this sign-in started with",
    ),
    "nothing_in_flight": (
        "invalid_request",
        "this browser has no sign-in in flight",
    ),
    "no_callback_code": (
        "invalid_request",
        "the callback carried no code",
    ),
    "code_expired": (
        "expired_token",
        "the code expired before anyone approved it",
    ),
    "no_refresh_token": (
        "invalid_grant",
        "there is no refresh token to renew these tokens with",
    ),
    "not_held_to_key": (
        "invalid_dpop_proof",
        "the token endpoint answered with a token that is not held to this key",
    ),
    "no_avatars": (
        "invalid_style",
        "{} does not serve {} avatars",
    ),
    "not_connected": (
        "handshake_required",
        "this app has not shaken hands with {}",
    ),
    "nothing_connected": (
        "access_denied",
        "masks connected nothing for {}",
    ),
    "no_refresh_for_connection": (
        "invalid_grant",
        "masks issued no refresh token to keep the connection with",
    ),
    "delegation_not_answering": (
        "temporarily_unavailable",
        "masks is not answering",
    ),
}
