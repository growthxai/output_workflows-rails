# frozen_string_literal: true

require "openssl"

module OutputWorkflows
  class WebhookVerifier
    VerificationError = Class.new(StandardError)
    MissingSecretError = Class.new(StandardError)

    def initialize(secret)
      raise MissingSecretError, "Webhook secret is required" if secret.nil? || secret.empty?

      @secret = secret
    end

    def verify!(payload, signature)
      expected = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), @secret, payload)

      unless secure_compare(expected, signature)
        raise VerificationError, "Invalid webhook signature"
      end

      true
    end

    private

    # Timing-safe string comparison
    def secure_compare(a, b)
      return false unless a.bytesize == b.bytesize

      l = a.unpack("C*")
      r = 0
      b.each_byte { |v| r |= v ^ l.shift }
      r == 0
    end
  end
end
