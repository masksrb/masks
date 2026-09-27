import { useState } from "react";
import { initials, personFrom } from "../person.js";
import type { Account } from "../types.js";

export interface PersonProps {
  account: Account;
  avatarUrl?: string | null;
  size?: number;
  onSignOut?: () => void;
  signOutLabel?: string;
  onSwitchOrganization?: (key: string) => void;
  className?: string;
}

export function Person({
  account,
  avatarUrl = null,
  size = 44,
  onSignOut,
  signOutLabel = "Sign out",
  onSwitchOrganization,
  className,
}: PersonProps) {
  const info = personFrom(account);
  const [broken, setBroken] = useState<string | null>(null);
  const showsAvatar = avatarUrl && broken !== avatarUrl;

  return (
    <div className={["masks-person", className].filter(Boolean).join(" ")}>
      {showsAvatar ? (
        <img
          className="masks-person-avatar"
          src={avatarUrl}
          alt=""
          width={size}
          height={size}
          onError={() => setBroken(avatarUrl)}
        />
      ) : (
        <span
          className="masks-person-avatar masks-person-avatar-letters"
          style={{
            width: size,
            height: size,
            fontSize: Math.round(size * 0.38),
          }}
        >
          {initials(info.name)}
        </span>
      )}

      <div className="masks-person-who">
        <span className="masks-person-name">{info.name}</span>

        {(info.details.length > 0 || info.unconfirmed) && (
          <span className="masks-person-sub">
            {info.details.join(" · ")}
            {info.unconfirmed && (
              <span className="masks-person-note">unconfirmed</span>
            )}
          </span>
        )}

        {info.organization && (
          <span className="masks-person-org">
            {info.organization.name}
            <span className="masks-person-org-role">{info.role}</span>
          </span>
        )}

        {info.manager && <span className="masks-person-role">Manager</span>}

        {onSwitchOrganization && info.others.length > 0 && (
          <span className="masks-person-orgs">
            {info.others.map((other) => (
              <button
                key={other.key}
                type="button"
                className="masks-person-switch"
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
          className="masks-person-signout"
          onClick={onSignOut}
        >
          {signOutLabel}
        </button>
      )}
    </div>
  );
}
