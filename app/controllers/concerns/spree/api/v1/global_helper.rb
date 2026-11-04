module Spree::Api::V1::GlobalHelper
  def to_timestamp(given_date)
    timestamp = given_date&.to_datetime&.strftime('%Q').to_i
    return timestamp
  end

  def to_utc_time(timestamp)
    convert_to_datetime = timestamp.to_s
    convert_to_datetime = (convert_to_datetime.to_f / 1000).to_s
    convert_to_datetime = DateTime.strptime(convert_to_datetime, '%s')
    utc_date_time = convert_to_datetime.utc
    return utc_date_time
  end

  # Public view of a user, safe to show anyone. Never add email, real or billing
  # names, phone, address or keys here. The empty keys stay so older clients that
  # read them keep working.
  def user_detail(user)
    return nil unless user
    {
      id: user.id,
      display_name: user.try(:display_name),
      email: "",
      first_name: "",
      last_name: "",
      phone: ""
    }
  end

  # For endpoints that expose other people's data (contacts, messages, threads).
  # Runs after authenticate_user, so @current_user_roles is loaded.
  def require_api_admin
    return if @current_user_roles&.include?('admin')

    render 'spree/api/errors/unauthorized', status: 401
  end
end
