module Idv
  class DocPiiForm
    include ActiveModel::Model

    validate :name_valid?
    validate :dob_valid?
    validates_presence_of :address1, { message: proc {
                                                  I18n.t('doc_auth.errors.alerts.address_check')
                                                } }
    validates :zipcode, format: {
      with: /\A[0-9]{5}(?:-[0-9]{4})?\z/,
      message: proc {
        I18n.t('doc_auth.errors.general.no_liveness')
      },
    }
    validates :jurisdiction, :state, inclusion: { in: Idp::Constants::STATE_AND_TERRITORY_CODES,
                                                  message: proc {
                                                    I18n.t('doc_auth.errors.general.no_liveness')
                                                  } }

    validates_presence_of :state_id_number, { message: proc {
      I18n.t('doc_auth.errors.general.no_liveness')
    } }

    attr_reader :first_name, :last_name, :dob, :address1, :state, :zipcode, :attention_with_barcode,
                :jurisdiction, :state_id_number
    alias_method :attention_with_barcode?, :attention_with_barcode

    def initialize(pii:, attention_with_barcode: false)
      @pii_from_doc = pii
      @first_name = pii[:first_name]
      @last_name = pii[:last_name]
      @dob = pii[:dob]
      @address1 = pii[:address1]
      @state = pii[:state]
      @zipcode = pii[:zipcode]
      @jurisdiction = pii[:state_id_jurisdiction]
      @state_id_number = pii[:state_id_number]
      @attention_with_barcode = attention_with_barcode
    end

    def submit
      response = Idv::DocAuthFormResponse.new(
        success: valid?,
        errors: errors,
        extra: {
          pii_like_keypaths: self.class.pii_like_keypaths,
          attention_with_barcode: attention_with_barcode?,
        },
      )
      response.pii_from_doc = pii_from_doc
      response
    end

    def self.pii_like_keypaths
      keypaths = [[:pii]]
      attrs = %i[name dob dob_min_age address1 state zipcode jurisdiction state_id_number]
      attrs.each do |k|
        keypaths << [:errors, k]
        keypaths << [:error_details, k]
        keypaths << [:error_details, k, k]
      end
      keypaths
    end

    private

    attr_reader :pii_from_doc

    def name_valid?
      return if first_name.present? && last_name.present?

      errors.add(:name, name_error, type: :name)
    end

    def dob_valid?
      if dob.blank?
        errors.add(:dob, dob_error, type: :dob)
        return
      end

      dob_date = DateParser.parse_legacy(dob)
      today = Time.zone.today
      age = today.year - dob_date.year - ((today.month > dob_date.month ||
        (today.month == dob_date.month && today.day >= dob_date.day)) ? 0 : 1)
      if age < IdentityConfig.store.idv_min_age_years
        errors.add(:dob_min_age, dob_min_age_error, type: :dob)
      end
    end

    def generic_error
      I18n.t('doc_auth.errors.general.no_liveness')
    end

    def name_error
      I18n.t('doc_auth.errors.alerts.full_name_check')
    end

    def dob_error
      I18n.t('doc_auth.errors.alerts.birth_date_checks')
    end

    def dob_min_age_error
      I18n.t('doc_auth.errors.pii.birth_date_min_age')
    end
  end
end
