# frozen_string_literal: true

#:nodoc:
module Response
  def json_response(object, status = :ok)
    render json: object, status: status
  end

  def response_with_message(status, message)
    {
      status: status,
      message: message
    }
  end

  def response_with_id(status, message, id)
    {
      status: status,
      message: message,
      id: id
    }
  end

  def redirect_response(url)
    redirect_to url, status: :found
  end

  def error_response(
    status_code = 400,
    message = 'Something is wrong with the parameters or the request itself.',
    status = 'Error'
  )
    render json: response_with_message(status, message), status: status_code
  end

  def successful_response(message, status = :ok)
    render json: response_with_message('Success', message), status: status
  end

  def successful_put(message = 'Record Updated Successfully', status = 'Success')
    render json: response_with_message(status, message), status: :ok
  end

  def successful_post(id, message = 'Record Created Successfully', status = 'Success')
    render json: response_with_id(status, message, id), status: :created
  end

  def unprocessable_entity(message = 'There is a problem with the request body you sent.')
    render json: response_with_message(
      'Error',
      message
    ), status: :unprocessable_entity
  end

  def not_found(message = 'Record not found')
    render json: response_with_message('Error', message), status: :not_found
  end

  def error_model(code, message)
    render :json => {
      response_code: code,
      response_message: message
    }
    return
  end
  def success_model(code, message)
    render :json => {
      response_code: code,
      response_message: message
    }
    return
  end
  def unauthorized_401_error(code, message)
    render :json => {
      response_code: code,
      response_message: message
    }
    return
  end
  def singular_success_model(code, message, object)
    render :json => {
      response_code: status,
      response_message: message,
      response_data: object
    }
  end
  def un_expected_error(message, status_code = 302)
    render :json => {
      response_code: status_code,
      response_message: message,
    }
  end
  def render_object_success(object, message, object_name ,count = 0,offset = 0)
    render :json =>
    {
      response_code: 200,
      response_message: message,
      response_data:
      {
        total_records: count, offset: offset, "#{object_name}": object
      }
    }
  end
end
