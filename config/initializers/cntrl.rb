cntrl_config = Rails.application.config_for(:cntrl)
Rails.application.config.cntrl = ActiveSupport::OrderedOptions.new

cntrl_config.each do |key, value|
  if value.is_a?(Hash)
    nested = ActiveSupport::OrderedOptions.new
    value.each { |k, v| nested[k] = v }
    Rails.application.config.cntrl[key] = nested
  else
    Rails.application.config.cntrl[key] = value
  end
end
