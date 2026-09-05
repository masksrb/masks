import { available, enrol, refused } from "../lib/passkey.js";

const csrf = () =>
  document.querySelector('meta[name="csrf-token"]')?.content ?? "";

const form = document.getElementById("add-passkey");
const field = document.getElementById("passkey-credential");
const name = document.getElementById("passkey-name");
const button = document.getElementById("add-passkey-button");
const unusable = document.getElementById("passkey-unusable");

async function options() {
  const response = await fetch("/account/passkeys/options", {
    method: "POST",
    credentials: "same-origin",
    headers: { Accept: "application/json", "X-CSRF-Token": csrf() },
  });

  if (!response.ok)
    throw new Error(`could not start enrolment: ${response.status}`);

  return response.json();
}

async function add(event) {
  event.preventDefault();

  button.disabled = true;
  unusable.hidden = true;

  try {
    field.value = await enrol(await options());
    form.submit();
  } catch (error) {
    if (!refused(error)) {
      unusable.textContent = "That passkey could not be added on this device.";
      unusable.hidden = false;
    }

    button.disabled = false;
  }
}

if (form && available()) {
  form.hidden = false;
  button.addEventListener("click", add);
} else if (name) {
  name.closest("[data-passkeys]")?.setAttribute("data-unsupported", "true");
}
