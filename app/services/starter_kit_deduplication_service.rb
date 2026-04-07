class StarterKitDeduplicationService
  def self.should_process?(honeybee_patient_id, ndcs)
    config = Rails.application.config.cntrl.starter_kit
    bundle_ndc = config["bundle_ndc"]
    device_ndcs = config["device_ndcs"]
    dedup_window = config["dedup_window_minutes"].minutes

    # Device-only NDCs → skip (wait for bundle)
    non_device_ndcs = ndcs - device_ndcs
    return false if non_device_ndcs.empty?

    # Kit bundle present → check time window
    if ndcs.include?(bundle_ndc)
      mapping = PatientMapping.find_by(honeybee_patient_id: honeybee_patient_id)
      return true unless mapping

      recent = PharmacyOrder
        .where(patient_mapping: mapping)
        .where("created_at > ?", dedup_window.ago)
        .exists?

      return !recent
    end

    true
  end
end
