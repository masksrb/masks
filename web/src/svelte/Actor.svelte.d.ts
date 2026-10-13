import type { Component } from "svelte";
import type { Account } from "../types.js";

export interface ActorProps {
  account: Account;
  avatarUrl?: string | null;
  size?: number;
  onSignOut?: (() => void) | null;
  signOutLabel?: string;
  onSwitchOrganization?: ((key: string) => void) | null;
  class?: string;
}

declare const Actor: Component<ActorProps>;

export default Actor;
