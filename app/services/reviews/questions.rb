module Reviews
  # Product questions and answers (M6). Contract: docs/plans/2026-11-26-reviews-api-contract.md ("M6 questions").
  #
  #   Reviews::Questions.answer!(question, body: '...', by: admin)  # official answer; publishes, emails
  #   Reviews::Questions.reject!(question)                           # no email
  #   Reviews::Questions.remove_answer!(answer)                      # back to the queue when none is left
  #   Reviews::Questions.json(question, answers)                     # the public shape
  #
  # Only answered questions are public: published, with at least one published answer
  # (Spree::ProductQuestion.answered). A question waits as pending until staff answer it in admin
  # (Reviews > Questions). Answering emails the asker (ProductQuestionMailer#answered), inline.
  module Questions
    module_function

    def store_name
      Reviews.store&.name.to_s.strip.presence || 'Our store'
    end

    # An official, published answer from staff. Publishes the question and emails the asker.
    # Returns the answer, which carries validation errors when it couldn't be saved.
    def answer!(question, body:, by:, now: Time.current)
      answer = question.answers.build(body: body.to_s.strip, user: by, official: true, verified_buyer: false,
                                      status: 'published', published_at: now, display_name: store_name)
      Spree::ProductQuestion.transaction do
        answer.save!
        question.update_columns(status: 'published', published_at: question.published_at || now, updated_at: now)
      end
      notify(answer)
      answer
    rescue ActiveRecord::RecordInvalid
      answer
    end

    def reject!(question, now: Time.current)
      question.update_columns(status: 'rejected', updated_at: now)
    end

    # Removes an answer. A question left with no published answer goes back to the queue, so it
    # leaves the product page and waits for a new one.
    def remove_answer!(answer, now: Time.current)
      question = answer.question
      answer.destroy!
      return if question.status == 'rejected' || question.answers.published.exists?

      question.update_columns(status: 'pending', published_at: nil, updated_at: now)
    end

    # Emails the asker when they have an address. Delivery errors are logged, never raised: the
    # answer is saved either way.
    def notify(answer)
      user = answer.question.user
      return false if user.nil? || user.email.blank? || (user.respond_to?(:deleted?) && user.deleted?)

      ProductQuestionMailer.answered(answer).deliver_now
      true
    rescue StandardError => e
      Rails.logger.error("[reviews] question #{answer.question_id} answer email failed: #{e.class}")
      false
    end

    # The public question shape. `answers` are its published answers in display order.
    def json(question, answers, store_name: self.store_name)
      {
        id: question.id,
        body: question.body,
        display_name: question.display_name,
        asked_at: question.created_at&.utc&.iso8601,
        answers: answers.map { |answer| answer_json(answer, store_name) }
      }
    end

    def answer_json(answer, store_name)
      {
        id: answer.id,
        body: answer.body,
        display_name: answer.official ? store_name : answer.display_name,
        official: answer.official,
        verified_buyer: answer.verified_buyer,
        answered_at: (answer.published_at || answer.created_at)&.utc&.iso8601
      }
    end
  end
end
