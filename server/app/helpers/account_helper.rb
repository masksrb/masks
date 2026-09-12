module AccountHelper
  ICONS = {
    email: '<path d="M3 6.5h14v11H3z"/><path d="m3.5 7 6.5 5 6.5-5"/>',
    password: '<circle cx="8" cy="8" r="3.5"/><path d="m10.5 10.5 6 6M14 14l1.5-1.5M16 16l1-1"/>',
    passkey: '<path d="M10 3.5c-3 0-5.5 2.4-5.5 5.4 0 1.2.3 2.1.8 3"/><path d="M10 6.5c-1.4 0-2.5 1.1-2.5 2.4 0 2.6.4 4.4 1 6.1"/><path d="M10 9c0 3 .4 5.2 1 7"/><path d="M15.2 5.5c.8 1 1.3 2.2 1.3 3.4 0 2.6-.3 4.6-.9 6.4"/><path d="M12.5 8.9c0 2.6-.2 4.5-.7 6.1"/>',
    device: '<rect x="6" y="2.5" width="8" height="15" rx="2"/><path d="M9 15h2"/>',
    apps: '<rect x="3" y="3" width="6" height="6" rx="1.5"/><rect x="11" y="3" width="6" height="6" rx="1.5"/><rect x="3" y="11" width="6" height="6" rx="1.5"/><rect x="11" y="11" width="6" height="6" rx="1.5"/>',
    linked: '<path d="M8.5 11.5a3 3 0 0 1 0-4.2l2-2a3 3 0 0 1 4.2 4.2l-1 1"/><path d="M11.5 8.5a3 3 0 0 1 0 4.2l-2 2a3 3 0 0 1-4.2-4.2l1-1"/>',
    picture: '<rect x="3" y="4" width="14" height="12" rx="2"/><circle cx="7.5" cy="8.5" r="1.5"/><path d="m4 14 4-3.5 3 2.5 2.5-2 2.5 3"/>',
    bell: '<path d="M6 9a4 4 0 0 1 8 0c0 3 .8 4.2 1.5 5h-11C5.2 13.2 6 12 6 9Z"/><path d="M8.5 14.5a1.5 1.5 0 0 0 3 0"/>',
    activity: '<circle cx="10" cy="10" r="7"/><path d="M10 6v4.2l2.6 1.8"/>',
    manage: '<path d="M10 2.5 3.5 5v5c0 3.4 2.7 6.2 6.5 7.5 3.8-1.3 6.5-4.1 6.5-7.5V5L10 2.5Z"/>'
  }.freeze

  def account_text(key, **options)
    t("account.index.#{key}", **options)
  end

  def account_icon(name)
    tag.svg(
      ICONS.fetch(name).html_safe,
      viewBox: "0 0 20 20",
      fill: "none",
      stroke: "currentColor",
      "stroke-width": 1.4,
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      "aria-hidden": true
    )
  end
end
