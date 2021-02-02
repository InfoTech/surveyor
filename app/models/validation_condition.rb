class ValidationCondition < ApplicationRecord
  unloadable
  include Surveyor::Models::ValidationConditionMethods
end
