module Idv
  class InPersonController < ApplicationController
    include Idv::AvailabilityConcern
    include RenderConditionConcern

    check_or_render_not_found -> { InPersonConfig.enabled_for_issuer?(current_sp&.issuer) }

    before_action :confirm_two_factor_authenticated
    before_action :redirect_unless_enrollment

    include IdvSession
    include Flow::FlowStateMachine
    include Idv::ThreatMetrixConcern

    before_action :redirect_if_flow_completed

    FLOW_STATE_MACHINE_SETTINGS = {
      step_url: :idv_in_person_step_url,
      final_url: :idv_in_person_ssn_url,
      flow: Idv::Flows::InPersonFlow,
      analytics_id: 'In Person Proofing',
    }.freeze

    private

    def redirect_unless_enrollment
      redirect_to idv_url unless current_user.establishing_in_person_enrollment
    end

    def redirect_if_flow_completed
      flow_finish if idv_session.applicant
    end
  end
end
