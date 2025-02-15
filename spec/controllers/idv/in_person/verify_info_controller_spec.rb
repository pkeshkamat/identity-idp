require 'rails_helper'

RSpec.describe Idv::InPerson::VerifyInfoController do
  let(:pii_from_user) { Idp::Constants::MOCK_IDV_APPLICANT_SAME_ADDRESS_AS_ID.dup }
  let(:flow_session) do
    { pii_from_user: pii_from_user }
  end

  let(:user) { create(:user, :with_phone, with: { phone: '+1 (415) 555-0130' }) }
  let(:service_provider) { create(:service_provider) }

  let(:ab_test_args) do
    { sample_bucket1: :sample_value1, sample_bucket2: :sample_value2 }
  end

  before do
    stub_sign_in(user)
    subject.idv_session.flow_path = 'standard'
    subject.idv_session.ssn = Idp::Constants::MOCK_IDV_APPLICANT_SAME_ADDRESS_AS_ID[:ssn]
    subject.user_session['idv/in_person'] = flow_session
    allow(subject).to receive(:ab_test_analytics_buckets).and_return(ab_test_args)
  end

  describe '#step_info' do
    it 'returns a valid StepInfo object' do
      expect(Idv::InPerson::VerifyInfoController.step_info).to be_valid
    end
  end

  describe 'before_actions' do
    it 'includes authentication before_action' do
      expect(subject).to have_actions(
        :before,
        :confirm_two_factor_authenticated,
      )
    end

    it 'includes outage before_action' do
      expect(subject).to have_actions(
        :before,
        :check_for_mail_only_outage,
      )
    end

    it 'confirms ssn step complete' do
      expect(subject).to have_actions(
        :before,
        :confirm_ssn_step_complete,
      )
    end
  end

  before do
    stub_analytics
    stub_attempts_tracker
  end

  describe '#show' do
    let(:analytics_name) { 'IdV: doc auth verify visited' }
    let(:analytics_args) do
      {
        analytics_id: 'In Person Proofing',
        flow_path: 'standard',
        irs_reproofing: false,
        step: 'verify',
      }.merge(ab_test_args)
    end

    it 'renders the show template' do
      get :show

      expect(response).to render_template :show
    end

    it 'sends analytics_visited event' do
      get :show

      expect(@analytics).to have_logged_event(
        'IdV: doc auth verify visited',
        hash_including(**analytics_args, same_address_as_id: true),
      )
    end

    context 'when done' do
      let(:review_status) { 'review' }
      let(:async_state) { instance_double(ProofingSessionAsyncResult) }
      let(:adjudicated_result) do
        {
          context: {
            stages: {
              threatmetrix: {
                transaction_id: 1,
                review_status: review_status,
                response_body: {
                  tmx_summary_reason_code: ['Identity_Negative_History'],
                },
              },
            },
          },
          errors: {},
          exception: nil,
          success: true,
          threatmetrix_review_status: review_status,
        }
      end

      it 'logs proofing results with analytics_id' do
        allow(controller).to receive(:load_async_state).and_return(async_state)
        allow(async_state).to receive(:done?).and_return(true)
        allow(async_state).to receive(:result).and_return(adjudicated_result)

        get :show

        expect(@analytics).to have_logged_event(
          'IdV: doc auth verify proofing results',
          hash_including(**analytics_args, success: true),
        )
      end
    end

    context 'tracks costs' do
      let(:review_status) { 'pass' }
      let(:async_state) { instance_double(ProofingSessionAsyncResult) }
      let(:adjudicated_result) do
        {
          context: {
            stages: {
              threatmetrix: {
                transaction_id: 1,
              },
              resolution: {
                transaction_id: 'resolution-mock-transaction-id-123',
                vendor_name: 'ResolutionMock',
              },
              residential_address: {
                transaction_id: 'resolution-mock-transaction-id-123',
                vendor_name: 'ResolutionMock',
              },
              state_id: {
                transaction_id: 'state-id-mock-transaction-id-456',
                vendor_name: 'StateIdMock',
              },
            },
          },
        }
      end

      before do
        allow(controller).to receive(:load_async_state).and_return(async_state)
        allow(async_state).to receive(:done?).and_return(true)
      end

      context 'when same address as id is true and in aamva jurisdiction' do
        it 'adds costs to database' do
          allow(async_state).to receive(:result).and_return(adjudicated_result)

          get :show

          lexis_nexis_costs = SpCost.where(cost_type: 'lexis_nexis_resolution')
          expect(lexis_nexis_costs.count).to eq(1)

          aamva_costs = SpCost.where(cost_type: 'aamva')
          expect(aamva_costs.count).to eq(1)

          threatmetrix_costs = SpCost.where(cost_type: 'threatmetrix')
          expect(threatmetrix_costs.count).to eq(1)
        end
      end

      context 'when same address as id is true and not in aamva jurisdiction' do
        it 'adds costs to database' do
          adjudicated_result[:context][:stages][:state_id][:vendor_name] = 'UnsupportedJurisdiction'
          allow(async_state).to receive(:result).and_return(adjudicated_result)

          get :show

          lexis_nexis_costs = SpCost.where(cost_type: 'lexis_nexis_resolution')
          expect(lexis_nexis_costs.count).to eq(1)

          aamva_costs = SpCost.where(cost_type: 'aamva')
          expect(aamva_costs.count).to eq(0)

          threatmetrix_costs = SpCost.where(cost_type: 'threatmetrix')
          expect(threatmetrix_costs.count).to eq(1)
        end
      end

      context 'when same address as id is false and in aamva jurisdiction' do
        let(:pii_from_user) do
          { same_address_as_id: 'false' }
        end

        it 'adds costs to database' do
          allow(async_state).to receive(:result).and_return(adjudicated_result)

          get :show

          lexis_nexis_costs = SpCost.where(cost_type: 'lexis_nexis_resolution')
          expect(lexis_nexis_costs.count).to eq(2)

          aamva_costs = SpCost.where(cost_type: 'aamva')
          expect(aamva_costs.count).to eq(1)

          threatmetrix_costs = SpCost.where(cost_type: 'threatmetrix')
          expect(threatmetrix_costs.count).to eq(1)
        end
      end

      context 'when same address as id is false and not in aamva jurisdiction' do
        let(:pii_from_user) do
          { same_address_as_id: 'false' }
        end

        it 'adds costs to database' do
          adjudicated_result[:context][:stages][:state_id][:vendor_name] = 'UnsupportedJurisdiction'
          allow(async_state).to receive(:result).and_return(adjudicated_result)

          get :show

          lexis_nexis_costs = SpCost.where(cost_type: 'lexis_nexis_resolution')
          expect(lexis_nexis_costs.count).to eq(2)

          aamva_costs = SpCost.where(cost_type: 'aamva')
          expect(aamva_costs.count).to eq(0)

          threatmetrix_costs = SpCost.where(cost_type: 'threatmetrix')
          expect(threatmetrix_costs.count).to eq(1)
        end
      end
    end
  end

  describe '#update' do
    it 'redirects to the expected page' do
      put :update

      expect(response).to redirect_to idv_in_person_verify_info_url
    end

    let(:pii_from_user) { Idp::Constants::MOCK_IDV_APPLICANT_STATE_ID_ADDRESS.dup }
    let(:enrollment) { InPersonEnrollment.new }
    before do
      allow(user).to receive(:establishing_in_person_enrollment).and_return(enrollment)
    end

    it 'sets uuid_prefix and state_id_type on pii_from_user' do
      expect(Idv::Agent).to receive(:new).
        with(hash_including(uuid_prefix: service_provider.app_id)).and_call_original
      # our test data already has the expected value by default
      subject.user_session['idv/in_person'][:pii_from_user].delete(:state_id_type)
      put :update

      expect(subject.user_session['idv/in_person'][:pii_from_user][:state_id_type]).
        to eq 'drivers_license'
      expect(subject.user_session['idv/in_person'][:pii_from_user][:uuid_prefix]).
        to eq service_provider.app_id
    end

    context 'a user does not have an establishing in person enrollment associated with them' do
      before do
        allow(user).to receive(:establishing_in_person_enrollment).and_return(nil)
      end

      it 'indicates to the IDV agent that an IPP enrollment is not in progress' do
        expect_any_instance_of(Idv::Agent).to receive(:proof_resolution).
          with(
            kind_of(DocumentCaptureSession),
            should_proof_state_id: anything,
            trace_id: subject.send(:amzn_trace_id),
            threatmetrix_session_id: nil,
            user_id: anything,
            request_ip: request.remote_ip,
            ipp_enrollment_in_progress: false,
          )

        put :update
      end
    end

    context 'a user does have an establishing in person enrollment associated with them' do
      it 'indicates to the IDV agent that ipp_enrollment_in_progress is enabled' do
        expect_any_instance_of(Idv::Agent).to receive(:proof_resolution).with(
          kind_of(DocumentCaptureSession),
          should_proof_state_id: anything,
          trace_id: anything,
          threatmetrix_session_id: anything,
          user_id: anything,
          request_ip: anything,
          ipp_enrollment_in_progress: true,
        )

        put :update
      end

      it 'captures state id address fields in the pii' do
        expect(Idv::Agent).to receive(:new).
          with(Idp::Constants::MOCK_IDV_APPLICANT_STATE_ID_ADDRESS.merge(uuid_prefix: nil)).
          and_call_original
        put :update
      end
    end

    it 'passes the X-Amzn-Trace-Id to the proofer' do
      expect_any_instance_of(Idv::Agent).to receive(:proof_resolution).
        with(
          kind_of(DocumentCaptureSession),
          should_proof_state_id: anything,
          trace_id: subject.send(:amzn_trace_id),
          threatmetrix_session_id: nil,
          user_id: anything,
          request_ip: request.remote_ip,
          ipp_enrollment_in_progress: true,
        )

      put :update
    end

    it 'only enqueues a job once' do
      put :update
      expect_any_instance_of(Idv::Agent).to_not receive(:proof_resolution)

      put :update
    end

    context 'when pii_from_user is blank' do
      it 'redirects' do
        flow_session[:pii_from_user] = {}
        put :update
        expect(response.status).to eq 302
      end
    end

    context 'when different users use the same SSN within the same timeframe' do
      let(:user2) { create(:user) }

      before do
        allow(IdentityConfig.store).to receive(:proof_ssn_max_attempts).and_return(3)
        allow(IdentityConfig.store).to receive(:proof_ssn_max_attempt_window_in_minutes).
          and_return(10)
      end

      it 'rate limits them all' do
        put :update
        subject.idv_session.verify_info_step_document_capture_session_uuid = nil
        put :update
        subject.idv_session.verify_info_step_document_capture_session_uuid = nil
        put :update
        put :update
        expect_any_instance_of(Idv::Agent).to_not receive(:proof_resolution)
        expect(response).to redirect_to(idv_session_errors_ssn_failure_url)
        subject.idv_session.verify_info_step_document_capture_session_uuid = nil

        stub_sign_in(user2)
        put :update
        expect_any_instance_of(Idv::Agent).to_not receive(:proof_resolution)
        expect(response).to redirect_to(idv_session_errors_ssn_failure_url)
      end
    end

    it 'invalidates future steps' do
      expect(subject).to receive(:clear_future_steps!)

      put :update
    end
  end
end
