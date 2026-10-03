import {
  create,
  get,
  parseCreationOptionsFromJSON,
  parseRequestOptionsFromJSON,
  supported,
} from "@github/webauthn-json/browser-ponyfill";

let pending = null;

export const available = () => supported();

export async function autofillable() {
  const conditional =
    globalThis.PublicKeyCredential?.isConditionalMediationAvailable;

  return supported() && (await conditional?.call(PublicKeyCredential)) === true;
}

export function settle() {
  pending?.abort();
  pending = null;
}

export async function enrol(options) {
  const credential = await create(
    parseCreationOptionsFromJSON({ publicKey: options }),
  );

  return JSON.stringify(credential.toJSON());
}

export async function assert(options) {
  settle();

  const credential = await get(
    parseRequestOptionsFromJSON({ publicKey: options }),
  );

  return JSON.stringify(credential.toJSON());
}

export async function autofill(options) {
  settle();

  const controller = new AbortController();
  pending = controller;

  try {
    const credential = await get(
      parseRequestOptionsFromJSON({
        publicKey: options,
        mediation: "conditional",
        signal: controller.signal,
      }),
    );

    return JSON.stringify(credential.toJSON());
  } finally {
    if (pending === controller) pending = null;
  }
}

export function refused(error) {
  return error?.name === "NotAllowedError" || error?.name === "AbortError";
}
