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

  def user_detail(user)
    return nil unless user
    {
      id: user.id,
      email: user.email,
      first_name: user.bill_address&.firstname || "",
      last_name: user.bill_address&.lastname || "",
      phone: user.bill_address&.phone || ""
    }
  end
end
