module Surveyor
  module Models
    module ResponseMethods
      def self.included(base)
        # Associations
        base.send :belongs_to, :response_set, optional: true
        base.send :belongs_to, :question, optional: true
        base.send :belongs_to, :answer, optional: true
        @@validations_already_included ||= nil
        unless @@validations_already_included
          # Validations
          base.send :validates_presence_of, :response_set_id, :question_id, :answer_id
          base.send :validates, :float_value, numericality: { only_float: true, message: "^Please enter a numeric value."}, if: -> { validate?(%w[float]) }
          base.send :validates, :integer_value, numericality: { only_integer: true, message: "^Please enter a numeric value." }, if: -> { validate?(%w[integer]) }
          
          @@validations_already_included = true
        end
        base.send :include, Surveyor::ActsAsResponse # includes "as" instance method
        
        # Class methods
        base.instance_eval do
          def applicable_attributes(attrs)
            result = ActiveSupport::HashWithIndifferentAccess.new(attrs)
            answer_id = result[:answer_id].is_a?(Array) ? result[:answer_id].last : result[:answer_id] # checkboxes are arrays / radio buttons are not arrays
            if result[:string_value] && !answer_id.blank? && Answer.exists?(answer_id)
              answer = Answer.find(answer_id)
              result.delete(:string_value) unless answer.response_class && answer.response_class.to_sym == :string
            end
            result
          end

          def validate_group(hash_of_hashes, response_set)
            invalid = []
            (hash_of_hashes || {}).each_pair do |k, hash|
              response = Response.new(hash.merge(response_set: response_set))
              invalid << {question: hash['question_id'], message: response.errors.full_messages} unless response.valid?
            end
            invalid
          end
        end
      end

      # Instance Methods
      def answer_id=(val)
        write_attribute :answer_id, (val.is_a?(Array) ? val.detect{|x| !x.to_s.blank?} : val)
      end
      def correct?
        question.correct_answer.nil? or self.answer.response_class != "answer" or (question.correct_answer.id.to_i == answer.id.to_i)
      end

      def dependent?
        return false unless self.response_set && self.question
        return self.question.dependency || (self.question.question_group && self.question.question_group.dependency)
      end

      #A response can be dependent on either its question, or the question group it belongs to. 
      #In order to determine if we need to validate this response, we need to check both dependencies 
      # (if either exist).
      def dependency_met?
        if dependent?
          return true if self.question.dependency && self.question.dependency.is_met?(self.response_set) 
          return true if self.question.question_group && self.question.question_group.dependency && self.question.question_group.dependency.is_met?(self.response_set)
          return false
        end

        return true
      end
      
      def validate?(fields)
        return false unless dependency_met?
        return false if self.answer.nil?
        return true if !marked_for_destruction? && fields.include?(self.answer.response_class)
        return false
      end

      def to_s # used in dependency_explanation_helper
        if self.answer.response_class == "answer" and self.answer_id
          return self.answer.text
        else
          return "#{(self.string_value || self.text_value || self.integer_value || self.float_value || nil).to_s}"
        end
      end
    end
  end
end
