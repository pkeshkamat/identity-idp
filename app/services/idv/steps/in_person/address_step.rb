module Idv
  module Steps
    module InPerson
      class AddressStep < DocAuthBaseStep
        STEP_INDICATOR_STEP = :verify_info

        def self.analytics_visited_event
          :idv_in_person_proofing_address_visited
        end

        def analytics_submitted_event
          :idv_in_person_proofing_residential_address_submitted
        end

        def call
          attrs = Idv::InPerson::AddressForm::ATTRIBUTES

          attrs = attrs.difference([:same_address_as_id])
          flow_session[:pii_from_user][:same_address_as_id] = 'false' if updating_address?

          attrs.each do |attr|
            flow_session[:pii_from_user][attr] = flow_params[attr]
          end

          redirect_to idv_in_person_verify_info_url if updating_address?

          redirect_to idv_in_person_ssn_url
        end

        def extra_view_variables
          {
            form:,
            pii:,
            updating_address: updating_address?,
          }
        end

        private

        def updating_address?
          flow_session[:pii_from_user].has_key?(:address1)
        end

        def pii
          data = flow_session[:pii_from_user]
          data = data.merge(flow_params) if params.has_key?(:in_person_address)
          data.deep_symbolize_keys
        end

        def flow_params
          params.require(:in_person_address).permit(
            *Idv::InPerson::AddressForm::ATTRIBUTES,
          )
        end

        def form
          @form ||= Idv::InPerson::AddressForm.new
        end

        def form_submit
          form.submit(flow_params)
        end
      end
    end
  end
end
