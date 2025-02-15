require 'rails_helper'

RSpec.describe 'idv/welcome/show.html.erb' do
  let(:user_fully_authenticated) { true }
  let(:sp_name) { nil }
  let(:user) { create(:user) }

  before do
    @decorated_sp_session = instance_double(ServiceProviderSession)
    allow(@decorated_sp_session).to receive(:sp_name).and_return(sp_name)
    allow(view).to receive(:decorated_sp_session).and_return(@decorated_sp_session)
    allow(view).to receive(:user_fully_authenticated?).and_return(user_fully_authenticated)
    allow(view).to receive(:user_signing_up?).and_return(false)
    allow(view).to receive(:url_for).and_wrap_original do |method, *args, &block|
      method.call(*args, &block)
    rescue
      ''
    end
  end

  context 'in doc auth with an authenticated user' do
    before do
      assign(:current_user, user)
      render
    end

    it 'renders a link to return to the SP' do
      expect(rendered).to have_link(t('links.cancel'))
    end
  end

  context 'without service provider' do
    it 'renders troubleshooting options' do
      render

      expect(rendered).to have_link(t('idv.troubleshooting.options.supported_documents'))
      expect(rendered).to have_link(
        t('idv.troubleshooting.options.learn_more_address_verification_options'),
      )
      expect(rendered).not_to have_link(
        nil,
        href: return_to_sp_failure_to_proof_url(step: 'welcome', location: 'missing_items'),
      )
    end
  end

  context 'with service provider' do
    let(:sp_name) { 'Example App' }

    it 'renders troubleshooting options' do
      render

      expect(rendered).to have_link(t('idv.troubleshooting.options.supported_documents'))
      expect(rendered).to have_link(
        t('idv.troubleshooting.options.learn_more_address_verification_options'),
      )
      expect(rendered).to have_link(
        t('idv.troubleshooting.options.get_help_at_sp', sp_name: sp_name),
        href: return_to_sp_failure_to_proof_url(step: 'welcome', location: 'missing_items'),
      )
    end
  end

  it 'renders a link to the privacy & security page' do
    render
    expect(rendered).to have_link(
      t('doc_auth.instructions.learn_more'),
      href: policy_redirect_url(flow: :idv, step: :welcome, location: :footer),
    )
  end
end
