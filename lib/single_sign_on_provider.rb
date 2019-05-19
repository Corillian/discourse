# frozen_string_literal: true

require_dependency 'single_sign_on'

class SingleSignOnProvider < SingleSignOn

  def self.parse(payload, sso_secret = nil)
    set_return_sso_url(payload)

    super
  end

  def self.set_return_sso_url(payload)
    parsed = Rack::Utils.parse_query(payload)
    decoded = Base64.decode64(parsed["sso"])
    decoded_hash = Rack::Utils.parse_query(decoded)

    @return_sso_url = decoded_hash['return_sso_url']
  end

  def self.sso_secret
    return nil unless @return_sso_url && SiteSetting.enable_sso_provider

    provider_secrets = SiteSetting.sso_provider_secrets.split(/[|\n]/)
    provider_secrets_hash = Hash[*provider_secrets]
    return_url_host = URI.parse(@return_sso_url).host
    # moves wildcard domains to the end of hash
    sorted_secrets = provider_secrets_hash.sort_by { |k, _| k }.reverse.to_h

    secret = sorted_secrets.select do |domain, _|
      WildcardDomainChecker.check_domain(domain, return_url_host)
    end
    secret.present? ? secret.values.first : nil
  end
end