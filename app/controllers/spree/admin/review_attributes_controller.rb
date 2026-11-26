module Spree
  module Admin
    # Reviews > Review questions (Spree::ReviewAttribute): the extra questions in the review form,
    # e.g. "Quality" (1 to 5) or "Fit" (Runs small to Runs large). Drag rows to reorder.
    #
    # Reviews store answers by key, so the key is set once, at create, and never accepted on
    # update; a question that has answers can only be deactivated (the model refuses to destroy it).
    class ReviewAttributesController < ResourceController
      def index
        @answer_counts = Spree::ReviewAttribute.answer_counts
      end

      def update_positions
        ApplicationRecord.transaction do
          params.require(:positions).each do |id, index|
            Spree::ReviewAttribute.find_by(id: id)&.set_list_position(index)
          end
        end

        respond_to do |format|
          format.js { head :ok }
          format.json { head :ok }
          format.html { redirect_to collection_url }
        end
      end

      private

      def model_class
        Spree::ReviewAttribute
      end

      def collection
        Spree::ReviewAttribute.ordered.includes(:taxons)
      end

      def permitted_resource_params
        return ActionController::Parameters.new unless params[:review_attribute].present?

        fields = %i[label kind low_label high_label applies_to active]
        fields << :key if new_actions.include?(action)
        attrs = params.require(:review_attribute).permit(*fields, taxon_ids: [])
        attrs[:key] = attrs[:key].to_s.strip.downcase if attrs.key?(:key)
        attrs[:label] = attrs[:label].to_s.strip if attrs.key?(:label)
        if attrs[:kind] == 'scale'
          attrs[:low_label] = nil
          attrs[:high_label] = nil
        end
        attrs
      end
    end
  end
end
