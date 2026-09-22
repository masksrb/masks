import { useState } from "react";
import { initials, personFrom } from "../person.js";
import type { Account } from "../types.js";

export interface PersonProps {
  account: Account;
  avatarUrl?: string | null;
  size?: number;
  onSignOut?: () => void;
  signOutLabel?: string;
  className?: string;
}

export function Person({
  account,
  avatarUrl = null,
  size = 44,
  onSignOut,
  signOutLabel = "Sign out",
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

        {info.manager && <span className="masks-person-role">Manager</span>}
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
