import type { Component } from "svelte";
import type { Account } from "../types.js";

export interface PersonProps {
  account: Account;
  avatarUrl?: string | null;
  size?: number;
  onSignOut?: (() => void) | null;
  signOutLabel?: string;
  class?: string;
}

declare const Person: Component<PersonProps>;

export default Person;
