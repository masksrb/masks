module ApplicationHelper
  def account_text(key, **options)
    t("account.index.#{key}", **options)
  end
end
