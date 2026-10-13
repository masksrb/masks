import { useState } from "react";
import { actorFrom, initials } from "../actor.js";
import type { Account } from "../types.js";

export interface ActorProps {
  account: Account;
  avatarUrl?: string | null;
  size?: number;
  onSignOut?: () => void;
  signOutLabel?: string;
  onSwitchOrganization?: (key: string) => void;
  className?: string;
}

export function Actor({
  account,
  avatarUrl = null,
  size = 44,
  onSignOut,
  signOutLabel = "Sign out",
  onSwitchOrganization,
  className,
}: ActorProps) {
  const info = actorFrom(account);
  const [broken, setBroken] = useState<string | null>(null);
  const showsAvatar = avatarUrl && broken !== avatarUrl;

  return (
    <div className={["masks-actor", className].filter(Boolean).join(" ")}>
      {showsAvatar ? (
        <img
          className="masks-actor-avatar"
          src={avatarUrl}
          alt=""
          width={size}
          height={size}
          onError={() => setBroken(avatarUrl)}
        />
      ) : (
        <span
          className="masks-actor-avatar masks-actor-avatar-letters"
          style={{
            width: size,
            height: size,
            fontSize: Math.round(size * 0.38),
          }}
        >
          {initials(info.name)}
        </span>
      )}

      <div className="masks-actor-who">
        <span className="masks-actor-name">{info.name}</span>

        {(info.details.length > 0 || info.unconfirmed) && (
          <span className="masks-actor-sub">
            {info.details.join(" · ")}
            {info.unconfirmed && (
              <span className="masks-actor-note">unconfirmed</span>
            )}
          </span>
        )}

        {info.organization && (
          <span className="masks-actor-org">
            {info.organization.name}
            <span className="masks-actor-org-role">{info.role}</span>
          </span>
        )}

        {info.manager && <span className="masks-actor-role">Manager</span>}

        {onSwitchOrganization && info.others.length > 0 && (
          <span className="masks-actor-orgs">
            {info.others.map((other) => (
              <button
                key={other.key}
                type="button"
                className="masks-actor-switch"
                onClick={() => onSwitchOrganization(other.key)}
              >
                {other.name}
              </button>
            ))}
          </span>
        )}
      </div>

      {onSignOut && (
        <button
          type="button"
          className="masks-actor-signout"
          onClick={onSignOut}
        >
          {signOutLabel}
        </button>
      )}
    </div>
  );
}
