require 'rails_helper'

RSpec.describe 'content security policy' do
  context 'on endpoints that will redirect to an SP' do
    context 'when openid_connect_content_security_form_action_enabled is enabled' do
      before do
        allow(IdentityConfig.store).to(
          receive(:openid_connect_content_security_form_action_enabled),
        ).and_return(true)
      end

      it 'includes a CSP with a form action that will allow a redirect to the CSP' do
        visit_password_form_with_sp
        follow_redirect!

        content_security_policy = parse_content_security_policy

        expect(content_security_policy['default-src']).to eq("'self'")
        expect(content_security_policy['base-uri']).to eq("'self'")
        expect(content_security_policy['child-src']).to eq("'self'")
        expect(content_security_policy['connect-src']).to eq("'self'")
        expect(content_security_policy['font-src']).to eq("'self' data:")
        expect(content_security_policy['form-action']).to eq(
          "'self' http://localhost:7654 https://example.com http://www.example.com",
        )
        expect(content_security_policy['img-src']).to eq(
          "'self' data: login.gov https://s3.us-west-2.amazonaws.com",
        )
        expect(content_security_policy['media-src']).to eq("'self'")
        expect(content_security_policy['object-src']).to eq("'none'")
        expect(content_security_policy['script-src']).to match(
          /'self' 'unsafe-eval' 'nonce-[\w\d=\/+]+'/,
        )
        expect(content_security_policy['style-src']).to eq("'self'")
      end

      it 'uses logout SP to override CSP form action that will allow a redirect to the CSP' do
        visit_password_form_with_sp
        visit_logout_form_with_sp

        content_security_policy = parse_content_security_policy

        expect(content_security_policy['form-action']).to eq(
          "'self' gov.gsa.openidconnect.test:",
        )
      end
    end

    context 'when openid_connect_content_security_form_action_enabled is disabled' do
      before do
        allow(IdentityConfig.store).to(
          receive(:openid_connect_content_security_form_action_enabled),
        ).and_return(false)
      end

      it 'includes a CSP without SP hosts in form-action' do
        visit_password_form_with_sp
        follow_redirect!

        content_security_policy = parse_content_security_policy

        expect(content_security_policy['default-src']).to eq("'self'")
        expect(content_security_policy['base-uri']).to eq("'self'")
        expect(content_security_policy['child-src']).to eq("'self'")
        expect(content_security_policy['connect-src']).to eq("'self'")
        expect(content_security_policy['font-src']).to eq("'self' data:")
        expect(content_security_policy['form-action']).to eq(
          "'self'",
        )
        expect(content_security_policy['img-src']).to eq(
          "'self' data: login.gov https://s3.us-west-2.amazonaws.com",
        )
        expect(content_security_policy['media-src']).to eq("'self'")
        expect(content_security_policy['object-src']).to eq("'none'")
        expect(content_security_policy['script-src']).to match(
          /'self' 'unsafe-eval' 'nonce-[\w\d=\/+]+'/,
        )
        expect(content_security_policy['style-src']).to eq("'self'")
      end

      it 'uses logout SP to override CSP form action that will allow a redirect to the CSP' do
        visit_password_form_with_sp
        visit_logout_form_with_sp

        content_security_policy = parse_content_security_policy

        expect(content_security_policy['form-action']).to eq(
          "'self'",
        )
      end
    end
  end

  context 'on endpoints that will not redirect to an SP' do
    it 'includes a restrictive CSP' do
      get forgot_password_path

      content_security_policy = parse_content_security_policy

      expect(content_security_policy['default-src']).to eq("'self'")
      expect(content_security_policy['base-uri']).to eq("'self'")
      expect(content_security_policy['child-src']).to eq("'self'")
      expect(content_security_policy['connect-src']).to eq("'self'")
      expect(content_security_policy['font-src']).to eq("'self' data:")
      expect(content_security_policy['form-action']).to eq("'self'")
      expect(content_security_policy['img-src']).to eq(
        "'self' data: login.gov https://s3.us-west-2.amazonaws.com",
      )
      expect(content_security_policy['media-src']).to eq("'self'")
      expect(content_security_policy['object-src']).to eq("'none'")
      expect(content_security_policy['script-src']).to match(
        /'self' 'unsafe-eval' 'nonce-[\w\d=\/+]+'/,
      )
      expect(content_security_policy['style-src']).to eq("'self'")
    end
  end

  def parse_content_security_policy
    header = response.headers['Content-Security-Policy']
    header.split(';').each_with_object({}) do |directive, result|
      tokens = directive.strip.split(/\s+/)
      key = tokens.first
      rules = tokens[1..-1].join(' ')
      result[key] = rules
    end
  end

  def visit_password_form_with_sp
    params = {
      client_id: 'urn:gov:gsa:openidconnect:sp:server',
      response_type: 'code',
      acr_values: Saml::Idp::Constants::IAL2_AUTHN_CONTEXT_CLASSREF,
      scope: 'openid email profile:name social_security_number',
      redirect_uri: 'http://localhost:7654/auth/result',
      state: SecureRandom.hex,
      nonce: SecureRandom.hex,
    }
    get(
      openid_connect_authorize_path,
      params: params,
      headers: { 'Accept' => '*/*' },
    )
  end

  def visit_logout_form_with_sp
    params = {
      client_id: 'urn:gov:gsa:openidconnect:test',
      post_logout_redirect_uri: 'gov.gsa.openidconnect.test://result/signout',
      state: 'a' * 22,
    }

    get(
      openid_connect_logout_path,
      params: params,
    )
  end
end
