import {
  create,
  get,
  parseCreationOptionsFromJSON,
  parseRequestOptionsFromJSON,
  supported,
} from "@github/webauthn-json/browser-ponyfill";

export const available = () => supported();

export async function enrol(options) {
  const credential = await create(
    parseCreationOptionsFromJSON({ publicKey: options }),
  );

  return JSON.stringify(credential.toJSON());
}

export async function assert(options) {
  const credential = await get(
    parseRequestOptionsFromJSON({ publicKey: options }),
  );

  return JSON.stringify(credential.toJSON());
}

export function refused(error) {
  return error?.name === "NotAllowedError" || error?.name === "AbortError";
}
