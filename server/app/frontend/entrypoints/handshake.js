const button = document.querySelector("[data-countdown]");

if (button) {
  const ready = button.textContent;
  const waiting = button.dataset.waiting;
  let left = Number(button.dataset.countdown);

  const render = () => {
    button.disabled = left > 0;
    button.textContent = left > 0 ? waiting.replace("%{seconds}", left) : ready;
  };

  render();

  const timer = setInterval(() => {
    if (document.visibilityState !== "visible") return;

    left -= 1;
    render();

    if (left <= 0) clearInterval(timer);
  }, 1000);
}
